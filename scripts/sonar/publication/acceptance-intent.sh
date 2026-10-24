#!/usr/bin/env bash
# Called inside the acceptance job's revalidation step, before simulated login.
set -euo pipefail
test "$GITHUB_WORKFLOW_REF" = "$GITHUB_REPOSITORY/.github/workflows/nuget-acceptance.yml@refs/heads/main"
test "$GITHUB_RUN_ATTEMPT" = 1
for name in ACTIONS_ID_TOKEN_REQUEST_TOKEN ACTIONS_ID_TOKEN_REQUEST_URL NUGET_API_KEY NUGET_SYMBOL_API_KEY NUGET_AUTH_TOKEN; do
  test -z "${!name:-}"
done

arguments=("$VERIFIER_DLL" --root "$REPOSITORY_ROOT" --nuget-verify-acceptance-intent
  --sha "$CANDIDATE_SHA" --version "$PACKAGE_VERSION"
  --readiness-run "$READINESS_RUN" --tag "$RELEASE_TAG"
  --handoff "$HANDOFF_ROOT/batch" --manifest-sha256 "$MANIFEST_SHA256"
  --tag-object "$TAG_OBJECT" --preparation-run "$PREPARATION_RUN"
  --preparation-attempt "$PREPARATION_ATTEMPT")

expect_block() {
  local scenario="$1" expected="$2"
  shift 2
  local code=0
  "$@" > "$PUBLISH_ROOT/negative.stdout" 2> "$PUBLISH_ROOT/negative.stderr" || code=$?
  # One is the verifier's policy rejection; crashes/timeouts are not acceptance evidence.
  test "$code" = 1
  test ! -s "$PUBLISH_ROOT/negative.stdout"
  grep -Fq -- "$expected" "$PUBLISH_ROOT/negative.stderr"
  printf 'Acceptance negative passed: %s\n' "$scenario"
}

expect_block production-context 'Stored intent requires the current first-attempt context' env GITHUB_WORKFLOW_REF="$GITHUB_REPOSITORY/.github/workflows/nuget-publish.yml@refs/heads/main" dotnet "${arguments[@]}"
expect_block rerun 'Stored intent requires the current first-attempt context' env GITHUB_RUN_ATTEMPT=2 dotnet "${arguments[@]}"
expect_block changed-content 'Stored intent bytes differ from the verified intent.' env INTENT_SHA256="$(printf '%064d' 0)" dotnet "${arguments[@]}"
expect_block changed-archive 'The intent artifact is expired or differs from the expected run, identity or digest.' env INTENT_ARTIFACT_DIGEST="$(printf '%064d' 0)" dotnet "${arguments[@]}"
production=("${arguments[@]}")
production[3]=--nuget-verify-intent
expect_block production-verifier 'Stored intent requires the current first-attempt context' dotnet "${production[@]}"
printf 'Five intent negatives passed; positive revalidation must still succeed.\n'
