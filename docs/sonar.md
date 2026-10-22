# Sonar onboarding — first rollout wave

Tracking: [core #24](https://github.com/andregoepel/core/issues/24),
[shared tooling #27](https://github.com/andregoepel/workflows/issues/27),
[epic #238](https://github.com/andregoepel/app-foundation/issues/238).

Core uses opt-in analysis through the shared C# runner in `workflows`.
The library and its dependencies, existing CI and tag publisher are unchanged.
The new caller stays inactive while `SONAR_MAIN_ENABLED` is unset. There is no
package upload, release tag, publisher migration or deployment in this wave.
The existing tag publisher is **not Sonar-protected** by this addition.

## Reviewed scope

| Item | Inventory |
| --- | --- |
| Solution | `AndreGoepel.Core.slnx` |
| Production project | `src/AndreGoepel.Core/AndreGoepel.Core.csproj` |
| Test project | `tests/AndreGoepel.Core.Tests/AndreGoepel.Core.Tests.csproj` |
| Current tests | Six; discovery must find at least six and all discovered tests must pass |
| Executed coverage anchor | `src/AndreGoepel.Core/Result.cs` |
| SDK / scanner / coverage | 10.0.402 / 12.0.0 / 18.12.0 |
| Sonar Community Build | 26.10.0.133078 |
| Central / local projects | `core` / `core-local` |
| E2E / staging deployment | Not applicable: library without a host, database or browser |

Generated build/scanner output and ignored artifacts are excluded from sources.
There are no authored coverage exclusions. CSharpier remains the formatter;
Sonar's dedicated frozen profiles should preserve the accepted formatting-rule
choices without editing or sharing ownership of app-foundation's profiles.

## Local branch verification

Use PowerShell 7 and SDK 10.0.402 on Windows or Linux. Start a separate local
Sonar instance on loopback port 9000 at the reviewed version. Provision the
private `core-local` project, dedicated `Core Library 1.0.0` gate and matching
frozen profiles, with a project-analysis token and separate browse-only verifier.
The central service/project must not be used for branch scans.

The repository's `global.json` selects SDK 10.0.402 with roll-forward disabled
and preserves Microsoft.Testing.Platform. This pin applies to commands run from
the Core checkout, including the scanner's build/test commands. Install that
exact SDK before running analysis; a newer SDK cannot replace it. Keep this pin,
the analysis contract and the shared runner's SDK aligned when reviewing upgrades.

Supply short-lived local credentials through `WORKFLOWS_SONAR_TOKEN` and
`WORKFLOWS_SONAR_VERIFY_TOKEN` using protected local credential storage; do not
paste tokens into shell history. Then run:

```powershell
pwsh -NoProfile -File scripts/sonar/analyze.ps1 -ServerId '<local-server-id>' -RunName 'branch-check-01'
```

Use a new lowercase run name each time. The wrapper downloads the exact shared
revision recorded in `main-policy.json`, checks its commit, builds it in ignored
scratch space without analysis credentials, invokes it against this checkout,
and removes its owned bootstrap directory. It does not build the shared tool as
part of the Core solution or add a library dependency. Local analysis also works
for uncommitted source changes and never creates trusted main readiness.

The runner verifies CSharpier, locked restore, a clean dependency audit, both
solution projects, all discovered tests, fresh xUnit/TRX reports, source checksums,
merged coverage and the exact uploaded task/analysis/gate. A failed gate returns
a nonzero exit code. Results are under `artifacts/sonar/<run-name>/publish/summary.json`;
private diagnostics remain under the sibling `private/` directory. Inspect an
existing lock or scanner directory before removing it manually.

## Standby policy and controlled activation

`main-policy.json` records the existing CI workflow ID, content fingerprint,
required build/test/audit steps, evidence age limits, shared runner revision and
dedicated Sonar target. The existing CI has no reusable workflow reference;
unexpected references are rejected. The tag-only publishing job is intentionally
not part of main readiness.

The policy records the actual dedicated profiles provisioned on October 22, 2026.
The snapshot contains 27 languages, including 121 C# rules, with each profile's
own rule revision timestamp. Each profile is an independent copy with no parent;
the accepted CSharpier-compatible rule choices are retained. The six gate
conditions match the reviewed contract, the small-change exemption is disabled,
and there are no authored coverage exclusions. Existing profiles, defaults and
app-foundation's baseline were verified unchanged.

The private `core` project has separate scan-only and browse-only identities.
The scanner uses a project-analysis token; the verifier has no scan or admin
permission. Both were denied administration and access to app-foundation.
Their credentials are stored only in protected operator storage and Core's
`sonar-main` environment. That environment permits only the `main` branch,
requires André's approval, allows self-approval and disables administrator bypass.
Tokens expire after 90 days; renew only Core's tokens and environment secrets
before expiry, then repeat the permitted/denied access checks.

`SONAR_MAIN_ENABLED` remains unset. `baselineAnalysisId` remains null because
no central Core analysis has been performed or accepted as a baseline. The profile
snapshot must be reviewed and merged before activation. A skipped job or a
successful local scan is not central readiness. Continue this checklist in order:

1. **Complete:** both onboarding PRs are merged. Preserve the reviewed immutable commit pin
   in the new caller, `tool-revision` input and policy; update all three together
   if a reviewed upgrade changes the shared implementation.
2. **Provisioned; policy review pending:** the separate private `core` project,
   `Core Library 1.0.0` profiles and dedicated gate are configured. Review and merge
   this actual profile snapshot before allowing a central run.
3. **Configured:** keep the six reviewed gate conditions: zero overall/new issues, at least 80%
   overall/new coverage, at most 3% new duplication and all new hotspots reviewed.
   Disable the small-change exemption; retain no authored coverage exclusions.
4. **Configured and verified:** main-only protected `sonar-main` environment,
   reviewer/self-approval settings, project-scoped `SONAR_SCAN_TOKEN` and separate
   browse-only `SONAR_VERIFY_TOKEN`. No publish/OIDC permissions are granted.
5. Only after those prerequisites are reviewed, set `SONAR_MAIN_ENABLED=true`
   and request one rerun of existing CI for the current main SHA. The first
   complete analysis intentionally fails readiness while the baseline is null.
   Review its inventory, coverage, findings and exact revision; select that
   actual analysis as `SPECIFIC_ANALYSIS` and record its ID through review.
6. Collect two fresh exact-main CI/Sonar successes and service-capacity evidence,
   alongside the isolated local failed-gate/recovery and offline evidence tests.
   Do not run duplicate central scans or claim acceptance from a skipped job.
   Keep #24 and the wave open until the remaining evidence is accepted.

The new workflow runs only after main-push CI. It independently rejects failed,
stale, missing, superseded or wrong-revision evidence and altered workflow/tool
pins. Its artifact is `library-analysis-readiness`, with `analysisReady: true`
and **`releaseEligible: false`**. It cannot authorize the existing NuGet publisher.
Private scanner files and credentials are never uploaded. Main changes require
a new exact-commit CI/Sonar set. Native branch/PR analysis is not claimed.

## Rollback

Unset `SONAR_MAIN_ENABLED`; let any current analysis complete. Revoke only core's
new scoped credentials and retain diagnostic evidence. Revert the additive
Sonar caller through review if needed. Existing CI/publishing and other projects'
baselines remain untouched. No release tag or publishing test is needed for rollback.

## Validation before review

Full local Windows analysis and Linux recovery analysis both passed: both
projects, six passing tests, 100% coverage, zero issues and zero hotspots.
An isolated uncovered probe failed the unchanged gate at 13.9% coverage with a
nonzero scanner exit; the probe is not part of this PR. The subsequent Linux
scan of the clean source recovered successfully without weakening the gate.
The shared runner passed 259 offline tests on Windows and Linux, including
missing/stale/wrong-revision CI, reruns, skipped jobs, changed gates/profiles/
baselines and invalid coverage. PR check results are recorded in the PR/issue.

Central provisioning and scoped API access are verified; the service reports green
health. The profile snapshot requires review. A reviewed central baseline, hosted
readiness, two exact-main run sets and measured additional VPS capacity under
analysis load remain pending. This is not a completed or accepted rollout.
