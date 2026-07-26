using System.Diagnostics.CodeAnalysis;

namespace AndreGoepel.Core;

/// <summary>
/// Outcome of an operation — no exceptions for flow control. Failures carry a
/// user-presentable error message.
/// </summary>
public record Result
{
    [MemberNotNullWhen(false, nameof(Error))]
    public bool IsSuccess { get; init; }

    public string? Error { get; init; }

    [MemberNotNullWhen(true, nameof(Error))]
    public bool IsFailure => !IsSuccess;

    public static Result Ok() => new() { IsSuccess = true };

    public static Result Fail(string error) => new() { IsSuccess = false, Error = error };

    public static Result<T> Ok<T>(T value) => new() { IsSuccess = true, Value = value };

    public static Result<T> Fail<T>(string error) => new() { IsSuccess = false, Error = error };
}

/// <summary>
/// A <see cref="Result"/> that also carries a value on success.
/// </summary>
public sealed record Result<T> : Result
{
    public T? Value { get; init; }
}
