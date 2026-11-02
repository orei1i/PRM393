namespace DomainLayer.Exceptions;

/// <summary>
/// Thrown when a write conflicts with existing data (e.g., unique email already exists).
/// Maps to HTTP 409 Conflict.
/// </summary>
public class ConflictException : BaseHttpException
{
    public ConflictException(string message = "Resource conflict", string? errorCode = null) : base(message, errorCode) { }

    public ConflictException(string message, Exception innerException, string? errorCode = null)
        : base(message, innerException, errorCode) { }
}
