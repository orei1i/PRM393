namespace DomainLayer.Exceptions;

/// <summary>
/// Thrown when the caller is authenticated but lacks permission for the resource.
/// Maps to HTTP 403 Forbidden.
/// </summary>
public class ForbiddenException : BaseHttpException
{
    public ForbiddenException(string message = "Forbidden", string? errorCode = null) : base(message, errorCode) { }

    public ForbiddenException(string message, Exception innerException, string? errorCode = null)
        : base(message, innerException, errorCode) { }
}
