# New-code acceptance evidence

Tracking: [#30](https://github.com/andregoepel/core/issues/30).
Status: local negative/recovery validation and exact merged-main central evidence
verified on 2026-10-24. This completes the technical evidence for #30; publication
enforcement remains tracked separately in #29.

## Reviewed source change

Both `Result.Fail(null!)` and `Result.Fail<T>(null!)` previously returned a failure
with a null error, contradicting the factories' non-null argument contract and
the `MemberNotNullWhen` annotations. Two regression tests failed before the fix.
The factories now reject null with `ArgumentNullException` naming `error`.
Valid calls retain their behavior; this does not redesign the public record
initializers or claim to prevent every manually constructed invalid state.

The production test inventory increases from six to eight, with no coverage
exclusions. Full local Windows analysis discovered and passed all eight tests,
imported coverage for `Result.cs`, reported 100% overall coverage on seven lines
to cover, zero findings and a passing gate. Local analysis:
`3241c35e-7406-41ac-95df-36188a0ba2b5`.

The full Linux analysis also passed all eight discovered tests, imported coverage
for the same source and reported 100% coverage on seven coverable lines with zero
findings. Analysis: `5b9267e7-c16b-4793-a54e-3350b6a1e098`; task:
`392f998a-a912-4512-a8ff-954c9a12406e`. Dependency audits and formatting passed.

## Isolated new-code failure and recovery

Executed on 2026-10-23 in a separate loopback-only fixture project using the same
reviewed gate thresholds and frozen Core profiles. Its own clean analysis
`42d63cb1-c27c-42b5-a6e0-37415bdcd923` was selected as its specific baseline.
The central Core project, accepted baseline and policy were not changed.

One untested coverable line was added only to an ignored source copy, then tested
in a second ignored copy. The fixture baseline remained identical across both
analyses; small-change exemption remained disabled.

| Check | Negative | Covered recovery |
| --- | --- | --- |
| New lines to cover | 1 | 1 |
| New-code coverage | 0% — failed | 100% — passed |
| Overall coverage | 87.5% — passed | 100% — passed |
| Tests discovered/passed | 8/8 | 8/8 |
| Tool exit | 1 | 0 |
| Gate | ERROR | OK |
| Analysis | `73adb702-95aa-47df-8396-b9afdd5f26f8` | `e86b1823-fb03-43d7-a44e-3861806795d6` |
| Task | `1b458850-ea38-48c1-9b6d-66e518811557` | `45c1cfbc-bff4-47d7-89f7-8199a0b351a1` |

The negative run retained a failed summary and produced no trusted readiness
receipt. The recovery remained a local analysis with `releaseEligible: false`;
it is not a central readiness run or publication authorization. No probe code is
part of the proposed source change. Raw scanner, test and metric records remain
in ignored local evidence, including the initial reproduction and both fixture
results.

## Verified central main evidence

[Core PR #31](https://github.com/andregoepel/core/pull/31) merged the meaningful
source change and its tests. The unchanged analysis workflow produced the
following evidence on 2026-10-24:

| Evidence | Verified result |
| --- | --- |
| Main revision | `42874ff085ed01c2d06016195360dbdf3d910fe2` |
| Main CI | [40078055900, attempt 1](https://github.com/andregoepel/core/actions/runs/40078055900/attempts/1), passed |
| Sonar readiness | [40078086628, attempt 1](https://github.com/andregoepel/core/actions/runs/40078086628/attempts/1), passed |
| Processing task | `b407a2f9-fb90-4dae-a0bd-ec81e9fd1dcf`, `SUCCESS` |
| Analysis | `6c2fd919-6ba9-4f1d-9dfb-c17513c1a513` |
| Unchanged specific baseline | `e3555256-765a-4247-9489-9a22f02ff42b` |
| Inventory | Both projects analyzed; eight tests discovered and passed; `Result.cs` coverage imported |
| New-code coverage | **Four new lines to cover; 100% measured coverage** |
| Other new-code conditions | Zero new issues; 0% duplication; zero new hotspots |
| Overall coverage | 100%; seven lines to cover, none uncovered |
| Quality Gate | `OK`, no ignored conditions; zero findings/hotspots |
| Receipt | `library-analysis-readiness`, `analysisReady: true`, `releaseEligible: false` |
| Verification time | 2026-10-24 08:32:15 UTC; receipt was fresh until 09:30:08 UTC |

The receipt binds the exact CI run, attempt and job; source, contract and summary
hashes; analysis/task identity; and accepted policy. Read-only server checks
confirmed the latest analysis revision/build string, all 27 frozen profiles and
their rule timestamps, all six gate conditions, the disabled small-change
exemption and absence of authored coverage exclusions. The hotspot-review
percentage is inapplicable because its new-code denominator is explicitly zero;
new-code coverage has a nonzero denominator and an actual passing percentage.

The retained negative/recovery evidence above is isolated local evidence, not a
central failure drill. Temporary fixtures were removed. Raw scanner and server
snapshots remain in ignored local storage. This historical acceptance report
does not extend receipt validity: any future publication needs fresh checks for
its exact current main revision and run attempt.
