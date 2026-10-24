# Core publication gate: review and migration

Tracks [#29](https://github.com/andregoepel/core/issues/29) and the source-change
evidence in [#30](https://github.com/andregoepel/core/issues/30). This change prepares
the tagged no-upload test and removes the legacy tag publisher from CI. Production
publication stays disabled. The NuGet account policy is not changed by this PR.

## Inventory and proposed mapping

Historical read-only inventory on 2026-10-23 (before the CI publisher removal):

| Item | Observed state | Proposed state |
| --- | --- | --- |
| Package | `AndreGoepel.Core`; authenticated owner list contains only `andre.goepel` | Same package and owner |
| Publication | `ci.yml`, `pack-and-publish`, `v*` push, official NuGet/login then dotnet push | Separate verified preparation and protected publication |
| Readiness | `sonar-main.yml`, workflow 392994102 | Reuse exact successful analysis; leave this workflow unchanged |
| Required CI | `ci.yml`, workflow 320576462 | Successful exact-main run/attempt and approved workflow fingerprint |
| Repository secrets | `NUGET_USER` name present; values not read | Owner identity only; no persistent publication API key |
| Environments | `sonar-main` exists | Add `sonar-nuget-prepare` and `nuget-publish` only after approval |
| Rulesets | Default-branch protection; no release-tag ruleset observed | Immutable `v*` tags, no bypass actors |
| NuGet Trusted Publisher | One active Core policy: `andregoepel/core`, `ci.yml`, no environment restriction, exact package `AndreGoepel.Core`, push new versions only | Replace with the reviewed environment-bound Core publication policy |
| NuGet API keys | Authenticated account reports no API keys | Keep persistent API keys absent; recheck before cutover |

Public ownership source: <https://www.nuget.org/packages/AndreGoepel.Core>.
The authenticated NuGet audit confirmed the current owner list, the matching
Core Trusted Publisher policy and an empty API-key inventory. No other policy in
that account matched Core or a wildcard covering Core. No credentials were read,
created or changed. This is a point-in-time audit; repeat it before cutover. The
owner retains administrative control and can create new credentials or upload
manually, so the pipeline does not constrain future owner actions. The active
`ci.yml` policy remains a known bypass until the separately approved migration.

Proposed single policy: package `AndreGoepel.Core`; account `andre.goepel`;
GitHub owner `andregoepel`; repository `core`; workflow `nuget-publish.yml`;
environment `nuget-publish`. Restrict the production environment to `main`, require
`andregoepel` as reviewer, allow self-review for the single operator, and disallow
administrator bypass. Preparation receives only read/analysis credentials in its
own environment with a reviewed `v*` tag policy; it has no OIDC permission.

## Prepared files and shared dependency

- `scripts/sonar/publication-target.json` binds repository, readiness workflow,
  exact package inventory and the independently pinned publication verifier.
- `scripts/sonar/nuget-policy.json` pins preparation workflow identity, exact
  content hash, required successful steps and a 120-minute maximum age.
- `.github/workflows/nuget-prepare.yml` now accepts only isolated acceptance tags.
  It and the new `nuget-acceptance.yml` require the off-by-default repository
  switch `SONAR_NUGET_ACCEPTANCE_ENABLED`. Neither can publish packages.
- `nuget-publish.yml` remains unchanged, with **literal-false job and step guards**.
  CI loses only `pack-and-publish`; its build/test job and triggers are preserved.
  `main-policy.json` records the new exact CI file hash. Sonar, the earlier manual
  rehearsal and all other existing Actions remain unchanged.
- `scripts/sonar/publication/release-tags.ruleset.json` is an unapplied proposal.
- The companion [workflows PR #31](https://github.com/andregoepel/workflows/pull/31)
  adapts the accepted app-foundation verifier
  to consumer-supplied identities. Core does not copy its C# implementation or
  add tool dependencies to the published Core library.

The publication verifier is pinned to the reviewed merged workflows commit
`68683cdc6a268328ed6ce686d26c26ace479eab0`. Its main validation and all 1,086 tests
on each of Windows and Linux passed. After [Core PR #32](https://github.com/andregoepel/core/pull/32)
merged, GitHub assigned these workflow identities, read back on 2026-10-24:

| Workflow | ID | Path |
| --- | --- | --- |
| NuGet preparation | `394955059` | `.github/workflows/nuget-prepare.yml` |
| NuGet verified publication | `394955060` | `.github/workflows/nuget-publish.yml` |

The preparation ID is bound in `nuget-policy.json` and both publication-trigger
checks. The policy also pins the exact preparation file bytes, including its
updated registration comment. Any subsequent preparation edit requires a reviewed
hash update. Registration does not enable production publication. The tagged
acceptance switch is separate from the production workflow's literal-false
guards. No tag or workflow dispatch is needed to register the new consumer.

The publication verifier pin is separate from
`main-policy.json.toolRevision`, which continues to identify the accepted analysis
runner. This avoids changing the existing Sonar Action for this preparation.

## Verification before credentials and upload

1. Require an original, first-attempt release tag creation for the current main
   revision. Reject moved/deleted tags, another main tip, changed tag objects and
   a mismatched workflow revision or event.
2. Authenticate the latest completed readiness producer and its artifacts.
   Validate exact CI run/attempt and mandatory jobs/steps, source and contract
   hashes, accepted baseline, frozen policy/profiles, completed Sonar task,
   current analysis, gate conditions and freshness. Reruns, newer producers,
   changed policy or expired evidence require new validation.
3. Build and test the versioned package, compare compilation inputs with the
   analyzed build, and bind both `.nupkg` and `.snupkg` to package ID, version,
   source commit and content hashes. Preserve authenticated preparation origin.
4. In the protected publication job, verify the complete handoff and retain an
   immutable intent artifact. Revalidate the stored intent and live evidence
   before official `NuGet/login`. Revalidate the complete package batch and each
   file hash immediately before `dotnet nuget push`. Record intent, individual
   attempts and outcomes for investigation; do not blindly retry partial pushes.

`library-analysis-readiness` with `releaseEligible: false` is only analysis
evidence. It cannot authorize a push by itself. Preparation and verifier outputs
also remain non-publishing; authorization additionally requires the reviewed
enabled pipeline, current live checks, protected approval and scoped NuGet policy.
The C# tool cannot log in to NuGet or upload a package. Rehearsal uses an in-memory
sink; actual publication uses only NuGet/login and dotnet's native push command.

Run `bash scripts/sonar/publication/tests/outcomes.sh` on Linux with Bash, jq and
the standard GNU utilities to test the standby workflow's actual outcome-recording step
offline. It uses synthetic intent/event files, without credentials or uploads,
and checks successful single/multiple-package batches, partial outcomes and
malformed event sequences. The expected event count comes from the verified file
inventory: one `started` and one terminal event per package or symbol file.

## Controlled cutover and rollback

Shared support and Core preparation were merged in their respective PR #31s.
Main CI passed in both repositories, and #30's nonempty central new-code check
is recorded in [the evidence report](sonar-new-code.md). Core PR #32 merged the
disabled standby workflows, and Core PR #33 merged their assigned-ID registration.
The production cutover remains unexecuted:

1. Review and merge the bundled CI publisher removal, acceptance workflow pair,
   matching CI/preparation hashes and [tagged test runbook](nuget-tagged-acceptance.md).
   Verify main CI and Sonar against the existing baseline after merge. The
   no-upload switch remains off; the production publisher remains literal false.
2. After explicit test authorization, configure the protected acceptance
   environments, enable only the acceptance switch and execute the runbook's
   complete original-tag handoff, live tamper/intent negatives and independent
   completed-run inspection. Preserve exact run/attempt and artifact digests.
3. Recheck the NuGet owner/policy/API-key audit, then obtain approval for the
   scoped policy migration, protected production environments and immutable
   release-tag rules. Prove tag update/deletion rejection with separately
   authorized non-release tags before rollout. Retain read-back evidence privately.
4. Retire the obsolete `ci.yml` NuGet policy and any alternative upload routes.
   Removing the job from current main does not revoke that policy, stop old
   workflow reruns or make historical `v*` tags safe. Keep the issue open until
   bypass removal is demonstrated; never restore the legacy publisher as rollback.
5. Review the combined evidence and authorize final activation separately. A
   production preparation trigger/guard change requires another reviewed byte
   hash update. Enable the real publisher only after all controls are verified.
   The first real release requires fresh evidence and explicit approval.

On failure, keep publication disabled, retain evidence and revalidate main. After
activation, disable the new publication path and revoke its policy if needed;
never restore the unguarded legacy route as a rollback. Published package versions
are not transactional or safely overwriteable: reconcile NuGet state and use a
new reviewed version where necessary. External evidence storage remains deferred.

## Main verification after standby registration

Merged revision `06953d03815d5ae7152898abbbc91292505ec597` passed
[CI 40079546043, attempt 1](https://github.com/andregoepel/core/actions/runs/40079546043)
and [Sonar 40079586341, attempt 1](https://github.com/andregoepel/core/actions/runs/40079586341).
The existing CI publication job was skipped. Core has no separate E2E workflow.

The analysis and readiness artifacts were independently checked against the exact
source revision, CI job, run attempts, artifact hashes and live Sonar task. Analysis
`0be948bf-dfcd-48e7-bf79-316a78019339` passed with eight tests, 100% overall coverage,
100% new-code coverage across four new lines to cover, and no findings or hotspots.
The accepted baseline `e3555256-765a-4247-9489-9a22f02ff42b`, six gate conditions,
27 frozen profiles, disabled small-change exemption and absent coverage exclusions
were verified unchanged. The receipt remained `analysisReady: true` and
`releaseEligible: false`; its expiry was 2026-10-24 09:52:51 UTC. This is historical
validation evidence and cannot authorize a later publication.

After PR #33, revision `afaa5c91c49b3555717eb4344af37c44bb87f641` passed
[CI 40087540674](https://github.com/andregoepel/core/actions/runs/40087540674) and
[Sonar 40087584458](https://github.com/andregoepel/core/actions/runs/40087584458),
both attempt 1. Independent verification of analysis
`36c17d0b-634e-4348-a5a1-ed4356abe90f` again confirmed eight tests, 100% overall and
new-code coverage across four new lines to cover, zero findings and the unchanged
baseline and frozen profiles. That analysis-only receipt expires at
2026-10-24 11:54:05 UTC and cannot authorize publication.

## No-upload runner rehearsal

`.github/workflows/nuget-rehearsal.yml` is a separate, manual workflow. It runs only
for `main` after approval through the existing `sonar-main` environment, using its
existing verification credentials. No new environment, token or NuGet policy is
required. Its GitHub token has only contents/actions read permissions. There is
no OIDC permission, NuGet login, upload command, tag creation or deployment step.
That rehearsal did not change CI, Sonar or the preparation/publication workflows.

For an explicitly authorized repeat of this already completed rehearsal:

1. Verify CI and Sonar readiness succeeded for current main. Dispatch while the
   readiness receipt is fresh; evidence lifetime is 60 minutes and the mandatory
   CI age limit is 120 minutes. A rerun or newer main revision requires fresh
   matching evidence. The rehearsal itself never starts an analysis or changes
   the baseline.
2. Run `gh workflow run nuget-rehearsal.yml --repo andregoepel/core --ref main`
   and approve its `sonar-main` job. Each rehearsal must be a new dispatch, not
   an attempt rerun. The workflow selects the latest exact-main readiness run;
   it never silently falls back to an older successful one.
3. Review the run summary and its `core-nuget-rehearsal-<sha>-<run>-<attempt>`
   artifact. Receipts, test reports and diagnostic logs are retained for 14 days;
   package archives are left on the temporary runner and are not uploaded.

The workflow builds the pinned shared verifier and runs its 1,086 offline contract
tests, including failed/pending/missing gate, expired or superseded evidence,
artifact substitution and handoff cases. It also runs Core's 11 actual outcome
recorder scenarios. These are simulated negative cases, executed on the runner;
they do not alter the central gate or live artifacts.

`scripts/sonar/publication/rehearse.sh` then exercises the same compiled C# verifier
against live GitHub/Sonar evidence. Four invalid invocations must exit at their
expected validation boundary without creating a preparation directory: missing
verification credentials, a dummy publication credential, wrong source revision,
and a CI run supplied as the readiness producer. The valid invocation runs
`--nuget-dry-run` with version `0.0.0`, compares versioned compilation inputs,
builds and tests Core, audits dependencies, inspects both package formats and
revalidates live evidence after packing. It checks the retained file hashes and
requires `dryRun: true` and `releaseEligible: false`.

The script passed locally in an isolated Linux container against merged main
`afaa5c9` and readiness run `40087584458`: all four rejections occurred before
preparation, then the real `.nupkg` and `.snupkg` passed verification without an
upload. After PR #34 merged, hosted run
[40089669289, attempt 1](https://github.com/andregoepel/core/actions/runs/40089669289)
passed on `8ebba9694f80f0d31ece925df592bae1302b8b20`: 1,086 shared tests, 11 recorder
scenarios, four live rejections and eight versioned Core tests. The retained
artifact `12559090125` was independently downloaded and its digest verified.
[CI 40089364434](https://github.com/andregoepel/core/actions/runs/40089364434) and
[Sonar 40089400926](https://github.com/andregoepel/core/actions/runs/40089400926)
also passed at attempt 1. Its receipt expired on 2026-10-24 at 12:21:19 UTC; these
are historical results, not current release authorization.

This rehearsal does not produce an authenticated tagged preparation origin or a
stored publication intent. Protected production approvals, tag update/deletion
rejection and the hosted tagged handoff remain unverified. The bundled PR removes
the legacy CI job, while its account policy remains for a separate migration. Keep #29 open and its hosted integration criterion
unchecked until the complete handoff and negative matrix have been demonstrated.

## Remaining acceptance

#29 remains open until hosted integration, reviewed cutover and bypass removal
are evidenced, with a fresh private audit at cutover. Removing the legacy CI job
does not revoke historical credential routes or enable the future publisher. #30's technical criteria are fully
evidenced by the merged source change, isolated negative/recovery check and exact
central main readiness report. Completing #30 does not authorize publication or
close #29.
