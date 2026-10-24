# Core 1.0.6: publisher correction and controlled symbol recovery

Tracks [#29](https://github.com/andregoepel/core/issues/29). The review change fixes
normal symbol routing and prepares one guarded recovery. It does not authorize
or dispatch recovery, change NuGet policies, or complete the release acceptance.

## Incident and correction

The approved release `v1.0.6` points to
`06e816a983d27e4d215042acc47e63f1ddba2075`. Preparation
[40100316402](https://github.com/andregoepel/core/actions/runs/40100316402), attempt 1,
succeeded. Publication
[40100437520](https://github.com/andregoepel/core/actions/runs/40100437520), attempt 1,
verified the handoff, preserved intent, obtained temporary NuGet credentials and
uploaded the main package with HTTP 201. Its symbol command then failed with
`File does not exist`. The intent and per-file outcome artifacts were retained.

The explicit V2 `--symbol-source` override bypassed V3 symbol-resource discovery
and caused SDK 10.0.402 to look for a legacy `.symbols.nupkg` file. Both ordinary
and recovery symbol commands now use only the NuGet V3 index as their source.
The ordinary `.nupkg` command retains `--no-symbols`, so each verified file is
dispatched separately. This follows
[NuGet's symbol publishing instructions](https://learn.microsoft.com/nuget/create-packages/symbol-packages-snupkg)
and [SymbolPackagePublish discovery](https://learn.microsoft.com/nuget/api/symbol-package-publish-resource).

The main package is already signed and indexed on NuGet. Its six payload entries
match the approved original; the additional entry is NuGet's repository signature.
The expected PDB was unavailable during reconciliation. A CLI failure alone does
not prove absence: recovery probes the exact PDB identity again before login and
immediately before upload. Only HTTP 404 permits proceeding; available symbols or
an inconclusive response stop the run.

## Recovery boundary

Only `nuget-publish.yml` changes. Preparation, CI, Sonar, their policy hashes,
other workflows, other repositories and NuGet policies remain unchanged.
The existing single `publish` job and protected `nuget-publish` environment are
retained. Every ordinary step requires `workflow_run`; every recovery step
requires `workflow_dispatch`. The existing concurrency group serializes them.

Merging this change corrects future ordinary publishing, but recovery stays off
until repository variable `CORE_106_SYMBOL_RECOVERY_SHA` is explicitly set to the
reviewed, merged **current main** SHA. The variable is absent during PR review.
Recovery also requires the exact confirmation `recover-core-1.0.6-symbols`,
main-only environment approval, the original tag unchanged, and the first attempt
of the first manual run of this publisher. Even a previous skipped manual run
requires a new review; do not use dispatches to test the switch.

`scripts/sonar/publication/recovery-106.json` fixes the original source SHA,
preparation/publication runs, four artifact IDs and archive digests, manifest,
package, signed package and PDB identities. Recovery downloads those original
artifacts and checks their live metadata, non-expiry, first-attempt run inventory
and bytes. It checks the original partial outcomes and compares the public signed
package with the original unsigned payload, including official signature
verification. No rebuilt package can substitute for the original symbols.

Historical evidence proves which bytes were approved; it is not fresh release
authorization. The pinned shared C# verifier separately validates current main's
latest successful CI/Sonar readiness, baseline, policy and source contract using
its existing non-publishing `--nuget-dry-run` path. This builds/tests current main
as version `0.0.0`; those outputs are never passed to an upload command. The
published 1.0.6 package and recovery symbols remain the immutable original bytes.
No central analysis is started by recovery.

Before login, recovery preserves an immutable 90-day intent, binds its artifact
ID/digest and repeats verification. After official `NuGet/login`, verification
runs again without NuGet or OIDC credentials. Changed readiness/run attempts,
main, policy, artifact availability, package bytes or PDB availability stop it.
The final command accepts only the hard-coded original `.snupkg`, checks its
hash and a verification age of at most two minutes, and records dispatch before
calling native `dotnet nuget push`. There is no main-package upload, wildcard,
`--skip-duplicate`, automatic retry, tag change or old-run replay in this path.

PowerShell coordinates official `gh` and `dotnet` commands plus read-only public
package/PDB requests. The existing shared C# tool performs readiness validation;
this does not add a custom uploader or GitHub/Sonar client to the Core library.

## Operator checklist after separate authorization

1. Review and merge this PR only after its checks pass. Keep main stable. Confirm
   the original artifacts are still available. The preparation artifacts have
   **24-hour retention and expire on October 25, 2026, around 13:58 UTC**. Exact
   API expiry timestamps are authoritative. If unavailable, stop and review a new
   evidence-preservation/recovery plan; do not weaken checks or rebuild 1.0.6.
2. Obtain explicit approval for the symbol-only upload on the chosen recovery
   SHA. Verify current main CI and central Sonar readiness; renew existing checks
   if needed. Local PR Sonar evidence cannot authorize recovery. The usual
   readiness/CI freshness limits still apply.
3. Set `CORE_106_SYMBOL_RECOVERY_SHA` to that exact SHA, then manually dispatch
   `nuget-publish.yml` on `main` with the exact confirmation above. Record its run
   ID and approve the protected environment only for that run and SHA. Do not
   create another release/tag or rerun either original release workflow.
4. Inspect retained intent and outcomes. `cli-success` is only a command outcome;
   interruption after dispatch is uncertain and never authorizes retry. A failure
   before dispatch also needs review because the first-manual-run guard is spent.
5. Independently retrieve the exact PDB from the NuGet symbol server, using the
   GUID/checksum in the recovery policy, and compare its SHA-256 with the original
   PDB. Recheck the public package payload/signature and indexed version. Keep
   #29 open until package **and symbols** are verified and evidence is retained.
6. Remove the recovery variable after the run, regardless of outcome. Prepare a
   later cleanup PR removing this one-time path. Do not publish an ordinary
   release on the recovery SHA: the shared verifier's one-publisher-run-per-SHA
   rule deliberately rejects it. Use a subsequent reviewed commit for the next
   normal release; do not relax the replay guard.

Recovery intent and outcome artifacts have 90-day retention. Runner cleanup is
conditional on retaining outcomes once intent exists; ephemeral runner storage
is not an archive. External evidence storage remains deferred. Actual recovery
login, hosted recovery execution and remote symbol acceptance remain unverified
until separately authorized execution; the PR's offline checks do not claim them.

## Repeatable offline validation

Run `pwsh -NoProfile -File scripts/sonar/publication/tests/recovery-106.ps1` for
recovery identity, replay, evidence, freshness, partial-outcome and event guards.
Run the existing outcome recorder and tagged-handoff tests as well.

Run `pwsh -NoProfile -File scripts/sonar/publication/tests/symbol-routing.ps1
-PackageDirectory <directory-containing-one-nupkg-and-snupkg>` with SDK 10.0.402
and Bash installed. It extracts the actual ordinary/recovery command arguments,
substitutes a loopback service index and uses the real NuGet CLI. Four cases
verify package-only routing, normal symbol routing, reproduction of the original
failure and recovery symbol routing. The mock checks endpoint, exact uploaded
payload hashes and absence of credentials. No requests go to NuGet. Linux tests
can run with container networking disabled; only loopback is required.
