# New-code acceptance evidence

Tracking: [#30](https://github.com/andregoepel/core/issues/30).
Status: local validation complete; exact merged-main central evidence pending.

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

## Post-merge check required before closure

After operator review and merge, validate CI and the unchanged Sonar workflow for
the exact resulting main SHA. Record the actual run IDs and attempts, task and
analysis IDs, baseline identity, discovered/passed tests, imported coverage,
nonzero `new_lines_to_cover`, measured `new_coverage` and all applicable new-code
conditions. Verify a successful fresh readiness receipt for that exact attempt.
Do not substitute this local report or overall coverage for the central result.

Keep the accepted specific baseline, frozen profiles, thresholds, small-change
setting and exclusions unchanged. If another merge or rerun supersedes the
evidence, repeat the exact-main check instead of accepting a stale receipt.
