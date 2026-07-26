# AndreGoepel.Core

Zero-dependency shared primitives for the AndreGoepel .NET ecosystem, consumed
by app-foundation, the marten-* packages, and the apps built on them.

## Why a separate package

Every repo in the ecosystem eventually needs a handful of small, dependency-free
building blocks (starting with `Result<T>`). Putting them here — below every
other package, with zero dependencies of its own — means any repo can take a
reference without risking a circular dependency or coupling to an unrelated
framework.

## What belongs here

Only genuinely cross-cutting, dependency-free primitives. Not a general
utility dumping ground — see `CLAUDE.md` for the intake bar.

## `Result<T>`

```csharp
Result Ok() => Result.Ok();
Result Fail() => Result.Fail("Something went wrong.");

Result<int> OkWithValue() => Result.Ok(42);
Result<int> FailWithValue() => Result.Fail<int>("Invalid input.");
```

`Result<T>` inherits from `Result`, so a failed `Result<T>` still carries
`IsSuccess`/`IsFailure`/`Error` even though `Value` is unset.
