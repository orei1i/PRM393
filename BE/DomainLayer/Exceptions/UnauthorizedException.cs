namespace DomainLayer.Exceptions;

/// <summary>
/// Thrown when the request lacks valid authentication credentials.
/// Maps to HTTP 401 Unauthorized.
/// </summary>
public class UnauthorizedException : BaseHttpException
{
    public UnauthorizedException(string message = "Unauthorized") : base(message) { }

    public UnauthorizedException(string message, Exception innerException)
        : base(message, innerException) { }
}
