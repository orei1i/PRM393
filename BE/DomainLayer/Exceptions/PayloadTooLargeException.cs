namespace DomainLayer.Exceptions;

/// <summary>
/// Thrown when the client's request payload exceeds maximum size limit.
/// Maps to HTTP 413 Payload Too Large.
/// </summary>
public class PayloadTooLargeException : BaseHttpException
{
    public PayloadTooLargeException(string message = "Payload Too Large") : base(message) { }

    public PayloadTooLargeException(string message, Exception innerException)
        : base(message, innerException) { }
}
