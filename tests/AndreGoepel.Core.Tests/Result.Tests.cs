namespace AndreGoepel.Core.Tests;

public sealed class ResultTests
{
    [Fact]
    public void Ok_Called_ReturnsSuccessWithNoError()
    {
        // Act
        var result = Result.Ok();

        // Assert
        Assert.True(result.IsSuccess);
        Assert.False(result.IsFailure);
        Assert.Null(result.Error);
    }

    [Fact]
    public void Fail_Called_ReturnsFailureWithError()
    {
        // Act
        var result = Result.Fail("something went wrong");

        // Assert
        Assert.False(result.IsSuccess);
        Assert.True(result.IsFailure);
        Assert.Equal("something went wrong", result.Error);
    }

    [Fact]
    public void OkOfT_Called_ReturnsSuccessWithValue()
    {
        // Act
        var result = Result.Ok(42);

        // Assert
        Assert.True(result.IsSuccess);
        Assert.False(result.IsFailure);
        Assert.Equal(42, result.Value);
        Assert.Null(result.Error);
    }

    [Fact]
    public void FailOfT_Called_ReturnsFailureWithNoValue()
    {
        // Act
        var result = Result.Fail<int>("invalid input");

        // Assert
        Assert.False(result.IsSuccess);
        Assert.True(result.IsFailure);
        Assert.Equal(default, result.Value);
        Assert.Equal("invalid input", result.Error);
    }

    // No null-forgiving operators (!) below and no explicit null checks on Error —
    // this only compiles under TreatWarningsAsErrors (CS8602) if the
    // [MemberNotNullWhen] attributes on IsSuccess/IsFailure are correct.

    [Fact]
    public void IsFailure_True_NarrowsErrorToNonNull()
    {
        // Arrange
        var result = Result.Fail("boom");

        // Act
        var length = result.IsFailure ? result.Error.Length : 0;

        // Assert
        Assert.Equal(4, length);
    }

    [Fact]
    public void IsSuccess_False_NarrowsErrorToNonNullInElseBranch()
    {
        // Arrange
        var result = Result.Fail("boom");

        // Act
        string message;
        if (result.IsSuccess)
        {
            message = "ok";
        }
        else
        {
            message = result.Error;
        }

        // Assert
        Assert.Equal("boom", message);
    }
}
