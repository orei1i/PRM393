namespace DomainLayer.Exceptions;

/// <summary>
/// Thrown when the authenticated user does not have permission to perform the requested action.
/// Maps to HTTP 403 Forbidden.
/// </summary>
public class ForbiddenException : BaseHttpException
{
    public ForbiddenException(string message = "Forbidden") : base(message) { }

    public ForbiddenException(string message, Exception innerException)
        : base(message, innerException) { }
}
