#!/usr/bin/env bash
# Test downloaded copies against live provenance; leave retained artifacts intact.
set -euo pipefail
for name in ACTIONS_ID_TOKEN_REQUEST_TOKEN ACTIONS_ID_TOKEN_REQUEST_URL NUGET_API_KEY NUGET_SYMBOL_API_KEY NUGET_AUTH_TOKEN; do
  test -z "${!name:-}"
done
workspace=$(mktemp -d "$RUNNER_TEMP/nuget-negative.XXXXXXXX")
trap 'rm -rf -- "$workspace"' EXIT
cp -R -- "$HANDOFF_ROOT/batch" "$workspace/batch"

arguments=("$VERIFIER_DLL" --root "$REPOSITORY_ROOT" --nuget-verify-handoff
  --sha "$CANDIDATE_SHA" --version "$PACKAGE_VERSION"
  --readiness-run "$READINESS_RUN" --tag "$RELEASE_TAG"
  --handoff "$workspace/batch" --manifest-sha256 "$MANIFEST_SHA256"
  --tag-object "$TAG_OBJECT" --preparation-run "$PREPARATION_RUN"
  --preparation-attempt "$PREPARATION_ATTEMPT")
expect_block() {
  local scenario=$1 expected=$2 code=0
  dotnet "${arguments[@]}" > "$workspace/stdout" 2> "$workspace/stderr" || code=$?
  test "$code" = 1
  test ! -s "$workspace/stdout"
  grep -Fq -- "$expected" "$workspace/stderr"
  printf 'Acceptance negative passed: %s\n' "$scenario"
}

# Preserve valid JSON while changing its authenticated byte hash.
printf '\n' >> "$workspace/batch/dry-run.json"
expect_block changed-manifest 'The transferred manifest does not match its trusted digest.'
cp -- "$HANDOFF_ROOT/batch/dry-run.json" "$workspace/batch/dry-run.json"

# Restrict the fixture mutation to Core's expected archive under the private copy.
file="AndreGoepel.Core.$PACKAGE_VERSION.nupkg"
test -f "$workspace/batch/packages/$file" && test ! -L "$workspace/batch/packages/$file"
printf 'tampered' >> "$workspace/batch/packages/$file"
expect_block changed-package 'Transferred package or symbol bytes changed.'
printf 'Two handoff negatives passed; the original handoff must still verify.\n'
