# Core publication gate: review and migration

Tracks [#29](https://github.com/andregoepel/core/issues/29) and the source-change
evidence in [#30](https://github.com/andregoepel/core/issues/30). This change prepares
the publication path. It does not enable it or remove the existing tag publisher.

## Inventory and proposed mapping

Read-only inventory on 2026-10-23:

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
- `.github/workflows/nuget-prepare.yml` and `nuget-publish.yml` are registered standby
  workflows with **literal-false job guards**. They cannot prepare or publish a
  release. The existing CI, Sonar and Dependabot Actions are unchanged.
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
hash update. GitHub's workflow registration state does not enable its jobs: both
job guards and the publication step guards remain literal false. No release tag
or workflow dispatch is needed to register these identities.

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
disabled standby workflows. The assigned-ID registration is prepared for review;
the production cutover remains unexecuted:

1. Review and merge the assigned preparation ID in the policy and both publication
   trigger checks together, retaining all false guards. The two workflow IDs above
   were read from GitHub after registration. Do not change thresholds, exclusions
   or small-change policy.
2. Recheck the recorded NuGet owner/policy/API-key audit. Review the exact final
   package-to-policy mapping and retire every identified alternative upload route.
3. After explicit authorization to change the existing CI, submit the cutover PR
   removing only the legacy `pack-and-publish` job. Keep both new workflows
   disabled and retain the reviewed preparation registration. Review the
   resulting CI fingerprint update; preserve all other CI behavior. Merge only
   with operator approval. Do not create `v*` test tags while the old route exists.
4. Configure the reviewed environments and immutable tag rules, prove tag update
   and deletion rejection using separately authorized non-release tags, then
   migrate the NuGet policy. Retain the resulting read-back evidence privately.
5. Run an explicitly approved hosted rehearsal with isolated non-release tags,
   no publication credentials and no upload. Test failed/pending/missing gate,
   expired/wrong-revision/superseded evidence, altered artifact and successful
   eligible handoff. Record exact run/attempt and verify cleanup. The production
   standby workflows require reviewed test-event adaptations for this drill; their
   current `v*` triggers must not be used as test triggers.
6. Review the combined evidence and authorize the final activation separately.
   Enable preparation and publication only after all bypasses are removed. First
   real release is a separate explicit operation with fresh evidence and approval.

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

## Remaining acceptance

#29 remains open until hosted integration, reviewed cutover and bypass removal
are evidenced, with a fresh private audit at cutover. Disabled standby workflows
do not enforce the current legacy publisher. #30's technical criteria are fully
evidenced by the merged source change, isolated negative/recovery check and exact
central main readiness report. Completing #30 does not authorize publication or
close #29.
