#!/usr/bin/env bash
# Execute the workflows' actual event checks against offline GitHub fixtures.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)
workspace=$(mktemp -d)
trap 'rm -rf -- "$workspace"' EXIT
mkdir "$workspace/bin"
export PATH="$workspace/bin:$PATH"
export FIXTURE_SHA
FIXTURE_SHA=$(printf 'a%.0s' {1..40})
export FIXTURE_MAIN="$FIXTURE_SHA"
tag=v1.2.3
acceptance_tag="sonar-poc/nuget/$(printf 'b%.0s' {1..32})/v0.0.0"

cat > "$workspace/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'api repos/andregoepel/core/git/ref/heads/main --jq .object.sha') printf '%s\n' "$FIXTURE_MAIN" ;;
  'api --method GET repos/andregoepel/core/actions/workflows/392994102/runs '*) echo 123 ;;
  *) echo 'Unexpected fixture API request' >&2; exit 1 ;;
esac
STUB
chmod +x "$workspace/bin/gh"

extract() {
  awk -v name="$2" '
    $0 == "      - name: " name { in_step = 1; next }
    in_step && /^        run: \|$/ { in_run = 1; found = 1; next }
    in_run && /^          / { print substr($0, 11); next }
    in_run { exit }
    END { if (!found) exit 1 }
  ' "$root/.github/workflows/$1.yml" > "$workspace/$3.sh"
  test -s "$workspace/$3.sh"
}
extract nuget-prepare 'Verify tag push' producer
extract nuget-acceptance 'Validate publication trigger' consumer
extract nuget-publish 'Validate publication trigger' publisher
extract nuget-acceptance 'Obtain temporary NuGet credentials' login

jq -n --arg sha "$FIXTURE_SHA" --arg ref "refs/tags/$tag" '{
  repository: {full_name: "andregoepel/core"}, ref: $ref,
  created: true, deleted: false, forced: false,
  before: "0000000000000000000000000000000000000000", after: $sha
}' > "$workspace/producer.json"
jq -n --arg sha "$FIXTURE_SHA" --arg tag "$acceptance_tag" '{
  action: "completed", repository: {full_name: "andregoepel/core"}, workflow_run: {
    repository: {full_name: "andregoepel/core"}, head_repository: {full_name: "andregoepel/core"},
    workflow_id: 394955059, path: ".github/workflows/nuget-prepare.yml", name: "NuGet preparation",
    event: "push", status: "completed", conclusion: "success", head_sha: $sha,
    head_branch: $tag, id: 456, run_attempt: 1
  }
}' > "$workspace/consumer.json"
jq --arg tag "$tag" '.workflow_run.head_branch = $tag' "$workspace/consumer.json" > "$workspace/publisher.json"

run_case() (
  local name=$1 kind=$2 filter=$3 expected=$4 code=0
  shift 4

  # Arrange
  export GITHUB_REPOSITORY=andregoepel/core GITHUB_RUN_ATTEMPT=1
  export GITHUB_SHA="$FIXTURE_SHA" GITHUB_WORKFLOW_SHA="$FIXTURE_SHA"
  export GITHUB_EVENT_PATH="$workspace/event.json" GITHUB_OUTPUT="$workspace/output" GITHUB_STEP_SUMMARY="$workspace/summary"
  if [[ "$kind" == producer ]]; then
    export GITHUB_EVENT_NAME=push GITHUB_REF_TYPE=tag GITHUB_REF_NAME="$tag" GITHUB_REF="refs/tags/$tag"
    export GITHUB_WORKFLOW_REF="andregoepel/core/.github/workflows/nuget-prepare.yml@$GITHUB_REF"
  else
    export GITHUB_EVENT_NAME=workflow_run GITHUB_REF=refs/heads/main
    export GITHUB_WORKFLOW_REF=andregoepel/core/.github/workflows/nuget-acceptance.yml@refs/heads/main
    if [[ "$kind" == publisher ]]; then
      export GITHUB_WORKFLOW_REF=andregoepel/core/.github/workflows/nuget-publish.yml@refs/heads/main
    fi
  fi
  jq "$filter" "$workspace/$kind.json" > "$GITHUB_EVENT_PATH"
  : > "$GITHUB_OUTPUT"

  # Act
  env "$@" bash "$workspace/$kind.sh" > "$workspace/stdout" 2> "$workspace/stderr" || code=$?

  # Assert
  if [[ "$expected" == pass ]]; then
    test "$code" = 0
    local expected_version=1.2.3 expected_tag="$tag"
    if [[ "$kind" == consumer ]]; then
      expected_version=0.0.0
      expected_tag="$acceptance_tag"
    fi
    grep -qx "version=$expected_version" "$GITHUB_OUTPUT"
    if [[ "$kind" == producer ]]; then
      digest=$(sha256sum -- "$GITHUB_EVENT_PATH")
      grep -qx "event-sha256=${digest%% *}" "$GITHUB_OUTPUT"
    else
      grep -qx "tag=$expected_tag" "$GITHUB_OUTPUT"
      grep -qx 'run=456' "$GITHUB_OUTPUT"
    fi
  else
    test "$code" -ne 0
    test ! -s "$GITHUB_OUTPUT"
  fi
  printf 'PASS %s\n' "$name"
)

run_case release-lightweight-tag producer '.' pass
run_case release-annotated-tag-original-object producer '.after = "cccccccccccccccccccccccccccccccccccccccc"' pass
run_case updated-tag producer '.created = false | .before = .after' reject
run_case deleted-tag producer '.deleted = true' reject
run_case forced-tag producer '.forced = true' reject
run_case wrong-producer-repository producer '.repository.full_name = "attacker/core"' reject
run_case changed-push-ref producer '.ref = "refs/tags/v0.0.0"' reject
run_case producer-rerun producer '.' reject GITHUB_RUN_ATTEMPT=2
for invalid_tag in "$acceptance_tag" v01.2.3 v1.02.3 v1.2.03 v1.2 v1.2.3-preview v1.2.3+build v100000.2.3 v1.2.3/extra; do
  run_case "invalid-release-tag-$invalid_tag" producer ".ref = \"refs/tags/$invalid_tag\"" reject \
    GITHUB_REF_NAME="$invalid_tag" GITHUB_REF="refs/tags/$invalid_tag" \
    GITHUB_WORKFLOW_REF="andregoepel/core/.github/workflows/nuget-prepare.yml@refs/tags/$invalid_tag"
done
run_case producer-branch producer '.' reject GITHUB_REF_TYPE=branch
run_case producer-dispatch producer '.' reject GITHUB_EVENT_NAME=workflow_dispatch
run_case producer-wrong-revision producer '.' reject GITHUB_WORKFLOW_SHA=cccccccccccccccccccccccccccccccccccccccc
run_case stale-main producer '.' reject FIXTURE_MAIN=cccccccccccccccccccccccccccccccccccccccc
run_case full-consumer-event consumer '.' pass
run_case wrong-consumer-repository consumer '.workflow_run.head_repository.full_name = "attacker/core"' reject
run_case wrong-producer-id consumer '.workflow_run.workflow_id = 1' reject
run_case wrong-producer-path consumer '.workflow_run.path = ".github/workflows/ci.yml"' reject
run_case failed-producer consumer '.workflow_run.conclusion = "failure"' reject
run_case wrong-source consumer '.workflow_run.head_sha = "cccccccccccccccccccccccccccccccccccccccc"' reject
run_case producer-second-attempt consumer '.workflow_run.run_attempt = 2' reject
run_case production-tag-consumer consumer '.workflow_run.head_branch = "v0.0.0"' reject
run_case consumer-rerun consumer '.' reject GITHUB_RUN_ATTEMPT=2
run_case wrong-consumer-revision consumer '.' reject GITHUB_WORKFLOW_SHA=cccccccccccccccccccccccccccccccccccccccc
run_case production-consumer-context consumer '.' reject GITHUB_WORKFLOW_REF=andregoepel/core/.github/workflows/nuget-publish.yml@refs/heads/main
run_case full-production-event publisher '.' pass
run_case acceptance-tag-production-consumer publisher ".workflow_run.head_branch = \"$acceptance_tag\"" reject
run_case wrong-production-producer-id publisher '.workflow_run.workflow_id = 1' reject
run_case wrong-production-producer-path publisher '.workflow_run.path = ".github/workflows/ci.yml"' reject
run_case failed-production-producer publisher '.workflow_run.conclusion = "failure"' reject
run_case wrong-production-source publisher '.workflow_run.head_sha = "cccccccccccccccccccccccccccccccccccccccc"' reject
run_case production-producer-second-attempt publisher '.workflow_run.run_attempt = 2' reject
run_case production-consumer-rerun publisher '.' reject GITHUB_RUN_ATTEMPT=2
run_case production-wrong-revision publisher '.' reject GITHUB_WORKFLOW_SHA=cccccccccccccccccccccccccccccccccccccccc
run_case production-stale-main publisher '.' reject FIXTURE_MAIN=cccccccccccccccccccccccccccccccccccccccc
run_case acceptance-context-production-consumer publisher '.' reject GITHUB_WORKFLOW_REF=andregoepel/core/.github/workflows/nuget-acceptance.yml@refs/heads/main

# Act: the simulated login must succeed without any credential channel.
env -u ACTIONS_ID_TOKEN_REQUEST_TOKEN -u ACTIONS_ID_TOKEN_REQUEST_URL -u NUGET_API_KEY -u NUGET_SYMBOL_API_KEY -u NUGET_AUTH_TOKEN bash "$workspace/login.sh" > /dev/null

# Assert: any accidental publication channel is rejected before the sink.
for name in ACTIONS_ID_TOKEN_REQUEST_TOKEN ACTIONS_ID_TOKEN_REQUEST_URL NUGET_API_KEY NUGET_SYMBOL_API_KEY NUGET_AUTH_TOKEN; do
  if env "$name=dummy" bash "$workspace/login.sh" > /dev/null 2>&1; then
    printf 'FAIL simulated login accepted %s\n' "$name" >&2
    exit 1
  fi
  printf 'PASS reject-%s\n' "$name"
done
printf 'PASS credential-free simulated login\n'
