# AndreGoepel.Core

Zero-dependency shared primitives for the AndreGoepel .NET ecosystem. Sits
below every other package (app-foundation, marten-*, and the apps built on
them) — nothing here may ever take a dependency back into that ecosystem.

## Solution Projects
- `AndreGoepel.Core` — the packable NuGet library
- `AndreGoepel.Core.Tests` — pure unit tests, no I/O

## Intake Bar — read before adding anything here
This is the single most expensive place in the whole stack to get wrong: a
breaking change here forces every other repo to move in lockstep. Before
adding a type or helper:
- **Zero dependencies, always.** Not even `Microsoft.Extensions.*`. If it
  needs a dependency, it belongs in a higher-level package instead.
- **Genuinely cross-cutting.** Used (or clearly about to be used) by more
  than one repo — not "might be handy someday." A single-repo need stays in
  that repo.
- **Prefer additive changes.** New types, new overloads. Changing an
  existing public member's shape is a last resort, not a first move.
- Not a general utility dumping ground — when in doubt, leave it out and
  raise it as a discussion first.

## Repo Specifics
- No ASP.NET Core, no ORM, no framework of any kind — plain C# only.
- Testing scope: the types in this package only, no integration surface.
