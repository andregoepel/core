# Sonar onboarding — first rollout wave

Tracking: [core #24](https://github.com/andregoepel/core/issues/24),
[shared tooling #27](https://github.com/andregoepel/workflows/issues/27),
[epic #238](https://github.com/andregoepel/app-foundation/issues/238).

Core uses opt-in analysis through the shared C# runner in `workflows`.
The library and its dependencies, existing CI and tag publisher are unchanged.
Central main analysis is enabled with `SONAR_MAIN_ENABLED=true`. The initial
baseline was accepted and selected on October 23, 2026. There is no package
upload, release tag, publisher migration or deployment in this wave.
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

## Reviewed main policy and baseline

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

The onboarding, profile snapshot and environment-secret forwarding changes are
merged. The caller uses `secrets: inherit` so the protected environment supplies
the two Sonar credentials to the immutable shared workflow. This also makes
caller-accessible repository secrets available to that workflow; review this
scope when adding secrets. The pinned analysis job references only the Sonar
credentials and has no publish/OIDC permissions.

André explicitly accepted the first central analysis as the baseline. Core main's
server-side new-code definition is `SPECIFIC_ANALYSIS`, with the same analysis ID
recorded in `scripts/sonar/main-policy.json`:

| Evidence | Accepted baseline |
| --- | --- |
| Analysis ID | `e3555256-765a-4247-9489-9a22f02ff42b` |
| Source revision | `6f053a880b91f83f6fdfc1d0ceef1f31abc4fa8d` |
| Analysis time | 2026-10-23 03:28:30 UTC |
| Main CI | [39894525868, attempt 1](https://github.com/andregoepel/core/actions/runs/39894525868/attempts/1), passed |
| Central analysis | [39894570021, attempt 1](https://github.com/andregoepel/core/actions/runs/39894570021/attempts/1) |
| Processing task | `a4495684-b5a5-4d54-8ef2-a77143f1c2fb`, succeeded without warnings |
| Inventory and tests | Both projects analyzed; 6 discovered tests, all passed |
| Coverage and findings | 100% coverage; 5 lines to cover, none uncovered; zero findings or hotspots |
| Quality Gate | `OK`, no ignored conditions |

The first analysis completed successfully but its workflow deliberately failed
with `Full analysis retained; a reviewed SPECIFIC_ANALYSIS baseline is still required.`
The policy had no baseline at execution time, so no readiness receipt was issued.
Selecting the baseline does not change that historical workflow result. The first
scan evaluated overall coverage and findings; it did not verify new-code conditions
against a baseline. A subsequent analysis must perform that verification.

## Complete main readiness after the policy merge

1. Verify successful main CI for the exact merged revision and attempt. Reuse its
   existing Sonar trigger; do not start another analysis while one is queued or
   running. Approve its `sonar-main` environment request while CI evidence is fresh.
2. Verify the submitted task, analysis revision/build string, complete tests and
   coverage, unchanged gate/profiles, and the selected baseline. A later analysis
   must differ from the baseline ID; the baseline cannot certify itself.
3. Require a successful readiness workflow and receipt. Check new-code conditions,
   including explicit zero-denominator evidence when the revision has no new code.
   A skipped job, successful local scan or green gate alone is not main readiness.
4. Collect a second fresh exact-main CI/Sonar set, requesting at most one rerun of
   existing CI if no suitable run exists. Record run IDs and attempts before
   requesting a rerun, and keep central scans sequential while measuring capacity.
5. Retain service-capacity evidence alongside the isolated local failed-gate/recovery
   and offline evidence tests. Keep #24 and the wave open until the remaining
   evidence is accepted.

Keep the six reviewed conditions: zero overall/new issues, at least 80% overall/new
coverage, at most 3% new duplication and all new hotspots reviewed. Preserve the
disabled small-change exemption and absence of authored coverage exclusions.
Any baseline replacement needs explicit review and a matching policy change;
do not move the baseline to hide a gate failure. Preserve agreement between the
caller pin, `tool-revision` input and policy when reviewing shared-tool upgrades.

The new workflow runs only after main-push CI. It independently rejects failed,
stale, missing, superseded or wrong-revision evidence and altered workflow/tool
pins. Its `readiness.json` receipt has kind `library-analysis-readiness`, with
`analysisReady: true` and **`releaseEligible: false`**. The artifact name is
`sonar-library-readiness-<sha>-<run-id>-<attempt>`. It cannot authorize the existing NuGet publisher.
Private scanner files and credentials are never uploaded. Main changes require
a new exact-commit CI/Sonar set. Native branch/PR analysis is not claimed.

## Rollback

Unset `SONAR_MAIN_ENABLED`; let any current analysis complete. Revoke only core's
new scoped credentials and retain diagnostic evidence. Revert the additive
Sonar caller through review if needed. Existing CI/publishing and other projects'
baselines remain untouched. No release tag or publishing test is needed for rollback.

## Validation and remaining acceptance

Full local Windows analysis and Linux recovery analysis both passed: both
projects, six passing tests, 100% coverage, zero issues and zero hotspots.
An isolated uncovered probe failed the unchanged gate at 13.9% coverage with a
nonzero scanner exit; the probe is not part of this PR. The subsequent Linux
scan of the clean source recovered successfully without weakening the gate.
The shared runner passed 259 offline tests on Windows and Linux, including
missing/stale/wrong-revision CI, reruns, skipped jobs, changed gates/profiles/
baselines and invalid coverage. PR check results are recorded in the PR/issue.

Central provisioning, scoped API access and the first complete hosted analysis are
verified. The accepted baseline is selected on the server and recorded in this
policy. Service health, profiles and configuration remained unchanged during the
first scan. Resource samples showed no restart, out-of-memory event or memory
pressure, but the short processing task fell between samples; its peak usage and
concurrent workload capacity were not established.

After this policy is merged, two successful exact-main CI/Sonar readiness sets and
further capacity evidence remain required. Baseline acceptance does not complete
or accept the rollout, and does not activate or protect the existing publisher.
