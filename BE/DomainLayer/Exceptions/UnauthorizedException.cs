namespace DomainLayer.Exceptions;

/// <summary>
/// Thrown when authentication is missing, invalid, or expired.
/// Maps to HTTP 401 Unauthorized.
/// </summary>
public class UnauthorizedException : BaseHttpException
{
    public UnauthorizedException(string message = "Unauthorized", string? errorCode = null) : base(message, errorCode) { }

    public UnauthorizedException(string message, Exception innerException, string? errorCode = null)
        : base(message, innerException, errorCode) { }
}
