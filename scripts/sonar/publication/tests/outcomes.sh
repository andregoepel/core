#!/usr/bin/env bash
# Offline regression tests for the actual standby workflow's outcome recorder.
set -euo pipefail

template=${1:-"$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)/.github/workflows/nuget-publish.yml"}
workspace=$(mktemp -d)
trap 'rm -rf -- "$workspace"' EXIT
export RUNNER_TEMP="$workspace"
export INTENT_ARTIFACT_ID=123
export INTENT_ARTIFACT_DIGEST
INTENT_ARTIFACT_DIGEST=$(printf 'a%.0s' {1..64})

# Extract only this step's run block, so tests exercise the shipped Bash/jq.
awk '
  /^      - name: Record publication outcomes$/ { in_step = 1; next }
  in_step && /^        run: \|$/ { in_run = 1; found = 1; next }
  in_run && /^          / { print substr($0, 11); next }
  in_run { exit }
  END { if (!found) exit 1 }
' "$template" > "$workspace/record.sh"
test -s "$workspace/record.sh"

run_case() {
  local name=$1 count=$2 rows=$3 login=$4 push=$5 error=$6 observations=$7
  local root file index code

  # Arrange
  root=$(mktemp -d "$workspace/nuget-publish.XXXXXXXX")
  jq -n --argjson count "$count" '{
    repository: "andregoepel/core", sha: "fixture", publishRunId: 42,
    publishAttempt: 1, workflowRef: "fixture", workflowRevision: "fixture",
    packages: [range(0; $count) | {
      file: ("Fixture." + ((. / 2 | floor) | tostring) + ".1.0.0" +
        (if . % 2 == 0 then ".nupkg" else ".snupkg" end)),
      sha256: "fixture"
    }]
  }' > "$root/intent.json"
  if [[ "$rows" != absent ]]; then
    : > "$root/attempts.tsv"
    index=0
    while IFS= read -r file; do
      case "$rows" in
        incomplete) [[ $index -eq 0 ]] || break ;;
        partial) [[ $index -eq 0 ]] || break ;;
      esac
      printf '%s\tstarted\n' "$file" >> "$root/attempts.tsv"
      if [[ "$rows" == partial ]]; then break; fi
      if [[ "$rows" == uncertain && $index -eq 1 ]]; then
        printf '%s\tuncertain-exit-1\n' "$file" >> "$root/attempts.tsv"
        break
      fi
      printf '%s\tcli-success\n' "$file" >> "$root/attempts.tsv"
      index=$((index + 1))
    done < <(jq -r '.packages[].file' "$root/intent.json")
    case "$rows" in
      extra) printf 'extra.nupkg\tstarted\n' >> "$root/attempts.tsv" ;;
      reordered) sort -r "$root/attempts.tsv" > "$root/reordered.tsv"; mv "$root/reordered.tsv" "$root/attempts.tsv" ;;
    esac
  fi
  export PUBLISH_ROOT="$root" LOGIN_OUTCOME="$login" PUSH_OUTCOME="$push"
  INTENT_SHA256=$(sha256sum -- "$root/intent.json")
  export INTENT_SHA256=${INTENT_SHA256%% *}

  # Act
  code=0
  bash "$workspace/record.sh" > "$root/stdout.log" 2> "$root/stderr.log" || code=$?

  # Assert
  if [[ -n "$error" ]]; then
    if [[ $code -eq 0 ]] || [[ -e "$root/outcomes.json" ]] || ! grep -Fq -- "$error" "$root/stderr.log"; then
      printf 'FAIL %s: expected rejection: %s\n' "$name" "$error" >&2
      cat "$root/stderr.log" >&2
      exit 1
    fi
  else
    if [[ $code -ne 0 ]]; then
      printf 'FAIL %s: recorder exited %s\n' "$name" "$code" >&2
      cat "$root/stderr.log" >&2
      exit 1
    fi
    jq -e --slurpfile intent "$root/intent.json" --argjson expected "$observations" \
      --arg hash "$INTENT_SHA256" --arg login "$login" --arg push "$push" '
      .schemaVersion == 1 and .kind == "publication-outcomes" and
      .intentSha256 == $hash and .loginOutcome == $login and .pushOutcome == $push and
      .authorizesRetry == false and .remoteAcceptanceVerified == false and
      (.packages | map(.cliObservation)) == $expected and
      (.packages | map(del(.cliObservation, .events))) == $intent[0].packages
    ' "$root/outcomes.json" > /dev/null
  fi
  printf 'PASS %s\n' "$name"
}

run_case single-package-success 2 complete success success '' '["cli-success","cli-success"]'
run_case three-package-success 6 complete success success '' '["cli-success","cli-success","cli-success","cli-success","cli-success","cli-success"]'
run_case six-package-success 12 complete success success '' '["cli-success","cli-success","cli-success","cli-success","cli-success","cli-success","cli-success","cli-success","cli-success","cli-success","cli-success","cli-success"]'
run_case uncertain-second-file 2 uncertain success failure '' '["cli-success","uncertain"]'
run_case interrupted-first-file 2 partial success cancelled '' '["uncertain","unrecorded"]'
run_case failed-login 2 absent failure skipped '' '["not-dispatched","not-dispatched"]'
run_case too-many-rows 2 extra success success 'Too many attempt rows' '[]'
run_case incomplete-success 2 incomplete success success 'Inconsistent step outcomes' '[]'
run_case reordered-rows 2 reordered success success 'Invalid attempt sequence' '[]'
run_case skipped-push-with-events 2 complete success skipped 'Inconsistent step outcomes' '[]'
run_case push-with-failed-login 2 complete failure success 'Inconsistent step outcomes' '[]'
