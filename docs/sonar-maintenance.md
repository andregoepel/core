# Core Sonar credential maintenance and named handoff

Tracking: [workflows #30](https://github.com/andregoepel/workflows/issues/30).
The shared [maintenance procedure](https://github.com/andregoepel/workflows/blob/752a04b788fd1cdb41e810ab62c184fe141d240a/docs/sonar-maintenance.md)
defines owner, cadence, renewal lead time and coordinated pin updates.

## Reviewed handoff

The Sonar caller now passes exactly `SONAR_SCAN_TOKEN` and `SONAR_VERIFY_TOKEN`.
It no longer inherits unrelated repository/organization secrets. The called job
continues to resolve its protected `sonar-main` environment, whose reviewer and
deployment restrictions remain in place. Named forwarding does not restrict
secrets stored directly on that environment; retain only its two Sonar entries.

The workflow reference, `tool-revision` input and `main-policy.json` agree on
shared commit `752a04b788fd1cdb41e810ab62c184fe141d240a`. SDK, scanner, coverage,
formatter, frozen profiles, gate conditions and accepted baseline are unchanged.
The NuGet publication verifier revision and publishing workflows remain unchanged.
Any later package preparation must obtain fresh evidence for its exact commit
and current policy hash through the existing verifier.

## Rotation verification

Rotate the project-analysis token and the separate Browse-only verifier token
under their existing dedicated identities. Preserve private project visibility,
operator Browse/See Source Code, required review, self-approval and disabled
administrator bypass. Keep expiry dates and token metadata in protected operator
records; never commit token values or upload scanner/private response files.

Update both Sonar secrets in `sonar-main`, `sonar-nuget-prepare` and `nuget-publish`
using the same verified replacement pair. Preserve the old generation privately
until a new protected exact-main analysis and read-only checks of the exact
replacement copies pass. A credential check must not invoke the publisher:
use an explicitly approved temporary no-upload workflow if needed, preserve
environment review, and remove its temporary branch permissions afterward.

Verify scanner submission to Core, verifier read access, denied scanner Browse,
denied source/administration/other-private-project access for both automation
identities, and unchanged direct/group permissions. Revoke superseded tokens only
after successful validation; then prove old authentication fails and the new
verifier still reads the current analysis. Retain detailed evidence privately.

## Required post-merge acceptance

The existing caller can validate rotated credentials before this PR is merged.
That does not validate the new named-secret handoff. Keep workflows #30 open until:

1. Exact-main CI passes after the caller/policy merge, and the unchanged trigger
   starts one protected Sonar run. Approve the expected run/commit only.
2. Readiness succeeds using the new shared pin, with all eight Core tests, complete
   coverage, unchanged baseline and the approved gate/profiles. Inspect the
   resulting task, revision, policy binding and readiness artifact.
3. A second fresh exact-main CI/Sonar set succeeds sequentially. Record attempts
   before rerunning CI; never start duplicate analyses or a release to test this.
4. All rotation checks and cleanup are recorded, including confirmation that no
   temporary environment deployment rule remains. Review evidence before closing
   the tracking issue.

## Rollback

If the named handoff fails, retain the failure evidence and revert the caller
and policy together to the prior reviewed pair through a PR. Keep the valid
rotated credentials; a caller rollback does not justify restoring revoked tokens.
Do not add repository-level copies, broaden inheritance as an unreviewed fix,
relax a gate or reset the baseline. Obtain fresh CI/Sonar evidence after a revert.
Before old-token revocation, a failed credential transfer can instead restore
the still-valid old generation to the affected destinations under the approved
rotation procedure. No release or publishing test is required.
