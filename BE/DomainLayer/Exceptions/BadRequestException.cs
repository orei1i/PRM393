namespace DomainLayer.Exceptions;

/// <summary>
/// Thrown when the client's request data is invalid or fails basic validation.
/// Maps to HTTP 400 Bad Request.
/// </summary>
public class BadRequestException : BaseHttpException
{
    public BadRequestException(string message = "Bad Request") : base(message) { }

    public BadRequestException(string message, Exception innerException)
        : base(message, innerException) { }
}
