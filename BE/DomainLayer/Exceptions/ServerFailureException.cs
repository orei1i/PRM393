namespace DomainLayer.Exceptions;

/// <summary>
/// Thrown when a known internal server error occurs that cannot be recovered from.
/// Maps to HTTP 500 Internal Server Error.
/// </summary>
public class ServerFailureException : BaseHttpException
{
    public ServerFailureException(string message = "Internal Server Failure") : base(message) { }

    public ServerFailureException(string message, Exception innerException)
        : base(message, innerException) { }
}
