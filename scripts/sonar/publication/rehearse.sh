#!/usr/bin/env bash
# Exercise the pinned verifier against current main without tags or publication.
set -euo pipefail
umask 077

[[ $# -eq 4 ]] || { echo 'Usage: rehearse.sh ROOT VERIFIER_DLL READINESS_RUN CI_RUN' >&2; exit 2; }
root=$(realpath -- "$1")
verifier=$(realpath -- "$2")
readiness_run=$3
ci_run=$4
[[ "$readiness_run" =~ ^[1-9][0-9]*$ && "$ci_run" =~ ^[1-9][0-9]*$ && "$readiness_run" != "$ci_run" ]]
test -f "$verifier"
test -n "${WORKFLOWS_GITHUB_TOKEN:-}"
test -n "${WORKFLOWS_SONAR_TOKEN:-}"
test -n "${WORKFLOWS_SONAR_VERIFY_TOKEN:-}"
sha=$(git -C "$root" rev-parse HEAD)
[[ "$sha" =~ ^[a-f0-9]{40}$ ]]
test "${WORKFLOWS_SONAR_TOOL_SHA:-}" = "$(jq -er '.verifierRevision' "$root/scripts/sonar/publication-target.json")"
for name in ACTIONS_ID_TOKEN_REQUEST_TOKEN ACTIONS_ID_TOKEN_REQUEST_URL NUGET_API_KEY NUGET_AUTH_TOKEN NUGET_SYMBOL_API_KEY; do
  [[ -z "${!name:-}" ]] || { printf 'Unexpected publication credential: %s\n' "$name" >&2; exit 1; }
done

mkdir -p "$root/artifacts/sonar"
evidence=$(mktemp -d "$root/artifacts/sonar/publication-rehearsal.XXXXXXXX")
command=(dotnet "$verifier" --root "$root" --nuget-dry-run --sha "$sha" --version 0.0.0 --readiness-run "$readiness_run")

inventory() {
  find "$root/artifacts/sonar" -mindepth 1 -maxdepth 1 -type d -name 'nuget-*' -printf '%f\n' | sort
}

reject() {
  local name=$1 expected=$2 before code=0
  shift 2
  before=$(inventory)
  "$@" > "$evidence/$name.log" 2>&1 || code=$?
  if [[ $code -ne 1 ]] || ! grep -Fxq -- "$expected" "$evidence/$name.log" || [[ "$(inventory)" != "$before" ]]; then
    printf 'FAIL %s: expected rejection before package preparation. See %s\n' "$name" "$evidence/$name.log" >&2
    exit 1
  fi
  printf 'PASS %s: rejected before package preparation\n' "$name"
}

reject missing-verification-credentials 'Read-only GitHub and both existing Sonar verification credentials are required.' \
  env -u WORKFLOWS_GITHUB_TOKEN -u WORKFLOWS_SONAR_TOKEN -u WORKFLOWS_SONAR_VERIFY_TOKEN "${command[@]}"
reject publication-credential 'Run preparation without OIDC access or NuGet publication credentials.' \
  env NUGET_API_KEY=rehearsal-not-a-key "${command[@]}"
reject wrong-revision 'The checkout is not the expected main revision.' \
  dotnet "$verifier" --root "$root" --nuget-dry-run --sha 0000000000000000000000000000000000000000 --version 0.0.0 --readiness-run "$readiness_run"
reject wrong-producer 'No current, complete readiness producer inventory; revalidate main.' \
  dotnet "$verifier" --root "$root" --nuget-dry-run --sha "$sha" --version 0.0.0 --readiness-run "$ci_run"

inventory > "$evidence/before.txt"
"${command[@]}" > "$evidence/positive.log" 2>&1
inventory > "$evidence/after.txt"
mapfile -t created < <(comm -13 "$evidence/before.txt" "$evidence/after.txt")
[[ ${#created[@]} -eq 1 && "${created[0]}" =~ ^nuget-[a-f0-9]{32}$ ]]
prepared="$root/artifacts/sonar/${created[0]}"
test -f "$prepared/dry-run.json"
jq -e --arg sha "$sha" --argjson run "$readiness_run" '
  .schemaVersion == 1 and .sha == $sha and .version == "0.0.0" and
  .readinessRunId == $run and .readinessAttempt >= 1 and
  .dryRun == true and .releaseEligible == false and
  (.packages | length == 2) and
  ([.packages[].file] | sort == ["AndreGoepel.Core.0.0.0.nupkg", "AndreGoepel.Core.0.0.0.snupkg"]) and
  all(.packages[]; .packageId == "AndreGoepel.Core" and .version == "0.0.0" and
    .feed == "https://api.nuget.org/v3/index.json" and (.sha256 | test("^[a-f0-9]{64}\\z")))
' "$prepared/dry-run.json" > /dev/null
while IFS=$'\t' read -r file expected; do
  actual=$(sha256sum -- "$prepared/packages/$file")
  test "${actual%% *}" = "$expected"
done < <(jq -r '.packages[] | [.file, .sha256] | @tsv' "$prepared/dry-run.json")
cp -- "$prepared/dry-run.json" "$evidence/dry-run.json"
cp -r -- "$prepared/tests" "$evidence/tests"
jq -n --arg sha "$sha" --argjson run "$readiness_run" --argjson ci "$ci_run" '{
  schemaVersion: 1, repository: "andregoepel/core", sha: $sha,
  readinessRunId: $run, ciRunId: $ci, version: "0.0.0",
  positive: "verified-and-packed", packages: 2,
  rejectedBeforePreparation: ["missing-verification-credentials", "publication-credential", "wrong-revision", "wrong-producer"],
  tagCreated: false, uploaded: false, releaseEligible: false,
  limits: ["no hosted preparation provenance or stored intent", "no production-environment or tag-protection validation", "gate and artifact fault injection is covered separately by offline tests"]
}' > "$evidence/results.json"
printf 'PASS current-main: package and symbol archive verified; no publication\nEvidence: %s\n' "$evidence"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then printf 'evidence=%s\n' "$evidence" >> "$GITHUB_OUTPUT"; fi
