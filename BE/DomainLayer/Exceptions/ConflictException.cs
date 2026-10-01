namespace DomainLayer.Exceptions;

/// <summary>
/// Thrown when an operation conflicts with existing data (e.g. duplicate name, duplicate entry).
/// Maps to HTTP 409 Conflict.
/// </summary>
public class ConflictException : BaseHttpException
{
    public ConflictException(string message = "Conflict") : base(message) { }

    public ConflictException(string message, Exception innerException)
        : base(message, innerException) { }
}
