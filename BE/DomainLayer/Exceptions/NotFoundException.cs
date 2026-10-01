namespace DomainLayer.Exceptions;

/// <summary>
/// Thrown when a requested resource does not exist or has been soft-deleted.
/// Maps to HTTP 404 Not Found.
/// </summary>
public class NotFoundException : BaseHttpException
{
    public NotFoundException(string message = "Entity not found") : base(message) { }

    public NotFoundException(string message, Exception innerException)
        : base(message, innerException) { }
}
