# Core tagged no-upload handoff acceptance

Part of [Core #29](https://github.com/andregoepel/core/issues/29). This runbook and
its workflow changes are prepared for review. The new hosted tagged test has not
run. It can run only after this revision reaches main and the operator authorizes
the test setup. Merging this PR removes the legacy CI publisher but does not
change NuGet policies or enable publication.

## Boundaries and workflow roles

| File | Role after merge | Activation boundary |
| --- | --- | --- |
| `ci.yml` | Existing build/test checks; legacy `pack-and-publish` job removed | Existing triggers preserved |
| `nuget-prepare.yml` | Build/test/verify the tagged package and retain authenticated origin and batch | Acceptance switch plus protected `sonar-nuget-prepare` environment |
| `nuget-acceptance.yml` | Verify handoff and stored intent, simulate login, read/discard both files, retain outcomes | Same switch plus protected `sonar-nuget-acceptance` environment |
| `nuget-publish.yml` | Future real `NuGet/login` and `dotnet nuget push` path | Unchanged literal-false job and step guards |

Only tags matching `sonar-poc/nuget/<32 lowercase hex characters>/vX.Y.Z` are
accepted by preparation and the consumer. Ordinary `v*` tags cannot use the test
path. The repository variable `SONAR_NUGET_ACCEPTANCE_ENABLED` must equal `true`;
missing or any other value skips the test jobs. It was absent when this PR was
prepared. This PR does not set it, create tags or provision environments.

Both test jobs have only contents/actions read access. Neither has OIDC access,
NuGet login or a package upload command. GitHub artifacts are evidence storage,
not a NuGet feed. The consumer checks credentials are absent before simulated
login and discards package bytes locally. Step names mentioning login/push are
fixed identifiers in the shared verification protocol; their implementations in
this acceptance workflow only simulate those operations.

## Before creating the one test tag

1. Merge only after review, then verify exact-main CI and Sonar readiness against
   the accepted baseline. Download and independently verify the evidence. Keep
   the main revision stable until the completed acceptance inspection finishes.
2. Obtain authorization for test controls and cleanup. Configure
   `sonar-nuget-prepare` with a tag-only policy `sonar-poc/nuget/*/v*`, and
   `sonar-nuget-acceptance` with a branch-only policy `main`. Require `andregoepel`
   as reviewer, allow self-review for the sole operator and disallow admin bypass.
   Read back these protections before enabling the switch. Add only protected
   copies of Core's existing `SONAR_SCAN_TOKEN` and `SONAR_VERIFY_TOKEN`; add no
   NuGet credential or OIDC permission. Do not modify `sonar-main` or its secrets.
3. Read back the registered consumer workflow ID/path and its runs for the exact
   main SHA. **There must be no prior acceptance run for that SHA**, including
   skipped or failed runs. Both producer and consumer require attempt 1. The
   stored-intent verifier accepts exactly one first-attempt consumer run per SHA.
   Never delete a failed run or weaken this rule to obtain a passing test.
4. Refresh readiness before creating a tag if needed: rerun the existing main CI
   once and await its unchanged Sonar workflow. Record run/attempt identities
   before retrying. Readiness lives 60 minutes, mandatory CI age is 120 minutes;
   environment waits and final inspection must fit inside that validity window.
5. Set only `SONAR_NUGET_ACCEPTANCE_ENABLED=true`. Create one fresh non-release
   tag on the verified main SHA, using a random 32-character lowercase hex ID and
   version `0.0.0`. Prefer a lightweight tag for the first hosted positive. Record
   the tag ref/object and candidate SHA before pushing. Do not use `v*` test tags.
   Do not create a release or change tag/branch rules for this test.

An annotated tag may be tested on a later independently reviewed main revision;
its original push `after` must remain the tag-object SHA. Never replace it with a
peeled commit to force a pass. Offline trigger fixtures cover both shapes, which
does not claim a hosted annotated-tag success. A second tag on the same SHA would
create another consumer run and invalidate the exactly-one-run check.

## Expected execution and evidence

Approve preparation, then the consumer, only after verifying the exact ref/SHA in
the pending deployment. Record IDs and attempt 1 before any retry decision.

Preparation preserves the original push event hash and `after`, builds/tests
Core's versioned compilation, verifies live readiness and produces the two exact
`AndreGoepel.Core.0.0.0.nupkg` / `.snupkg` files. It retains
`nuget-origin-<sha>-<run>-1` and `nuget-batch-<sha>-<run>-1` for one day.

The consumer authenticates the originating workflow `394955059`, its reviewed
file hash, successful jobs/steps, run attempt, tag object, artifact identity and
manifest hash. It then:

1. Alters only private downloaded copies: a changed manifest and changed package
   must be rejected at the expected digest/byte checks with verifier exit code 1.
2. Revalidates the original complete handoff and records `acceptance-intent`,
   `acceptanceOnly: true`, with the full two-file inventory.
3. Stores `nuget-publish-intent-<consumer-run>-1` before simulated login. Five
   invalid intent invocations must fail at their expected boundaries: production
   workflow context, consumer attempt 2, changed intent content hash, changed
   archive digest and the production intent verifier. Crashes, timeouts and
   unrelated API failures do not count as successful negative tests.
4. Authenticates the original stored intent and revalidates live evidence.
   Simulates login without requesting credentials, revalidates before each file,
   hashes it and reads/discards its bytes. It never contacts a NuGet upload API.
5. Retains `nuget-publish-outcomes-<consumer-run>-1` for 90 days, with
   `acceptance-outcomes`, `acceptanceOnly: true`, per-file observations and
   `authorizesRetry: false`. `cli-success` here means successful local simulation,
   not acceptance by NuGet. `remoteAcceptanceVerified` remains false.

The five intent negatives and two handoff mutations run against current live
provenance, without modifying server policy or retained artifacts. Failed/pending/
missing gate, stale/superseded evidence and other fault scenarios remain covered
by the pinned shared verifier's 1,086 offline tests and the earlier protected
runner rehearsal. Do not describe those simulated cases as live gate mutations.

## Independent completion check

Before evidence expires, download the origin, batch, intent and outcomes into a
private ignored directory. Obtain artifact IDs and ZIP digests from GitHub, match
the downloaded bytes, and verify the intent content hash. Use the pinned verifier
from `publication-target.json`, with current main checked out and only the usual
verification credentials in protected environment variables:

```bash
dotnet "$VERIFIER_DLL" --root "$REPOSITORY_ROOT" --nuget-inspect-acceptance \
  --sha "$CANDIDATE_SHA" --version 0.0.0 --readiness-run "$READINESS_RUN" \
  --tag "$RELEASE_TAG" --handoff "$HANDOFF_ROOT/batch" \
  --manifest-sha256 "$MANIFEST_SHA256" --tag-object "$TAG_OBJECT" \
  --preparation-run "$PREPARATION_RUN" --preparation-attempt 1 \
  --publish-run "$ACCEPTANCE_RUN" --intent-artifact "$INTENT_ARTIFACT_ID" \
  --intent-archive-sha256 "$INTENT_ARTIFACT_DIGEST" --intent-sha256 "$INTENT_SHA256"
```

Use plain lowercase 64-character hashes, without `sha256:` prefixes. Require
`acceptanceOnly: true`, `outcomesAvailable: true`, exactly two `cli-success`
observations, and false retry/release/remote-acceptance flags. Inspect completed
job steps and all seven negative-test messages, not just a green workflow badge.
Retain exact main/CI/readiness/task/analysis/producer/consumer identities,
run attempts, artifact IDs/digests and the inspection output locally.

If time expires, main changes or a run fails, stop and retain the evidence; do not
rerun the producer/consumer, create another tag on that SHA or refresh only one
part of the receipt. Diagnose and obtain a reviewed recovery plan. A fresh
analysis cannot retroactively validate an old preparation.

After inspection, set the acceptance switch false, remove only the explicitly
recorded test tag and temporary environments/token copies under the test's
cleanup authorization, and verify production remains disabled. Keep #29 open:
production environment/tag controls, NuGet policy migration and final activation
are separate. The old `ci.yml` Trusted Publisher policy can still authorize
historical workflow revisions until explicitly retired. New external evidence
storage remains deferred.

## Local regression checks

Run on Linux with Bash, jq and GNU utilities; no credentials or network needed:

```bash
bash scripts/sonar/publication/tests/tagged-handoff.sh
bash scripts/sonar/publication/tests/outcomes.sh
bash scripts/sonar/publication/tests/outcomes.sh .github/workflows/nuget-acceptance.yml acceptance-outcomes
```

These execute the actual workflow Bash/jq blocks: 27 event/credential scenarios
and 11 outcome scenarios for each of the production and acceptance recorders.
They complement shared contract tests; they do not replace the hosted handoff.
