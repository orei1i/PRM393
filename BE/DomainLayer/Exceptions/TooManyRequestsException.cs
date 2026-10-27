namespace DomainLayer.Exceptions;

/// <summary>
/// Thrown when the client has sent too many requests in a given amount of time.
/// Maps to HTTP 429 Too Many Requests.
/// </summary>
public class TooManyRequestsException : BaseHttpException
{
    public TooManyRequestsException(string message = "Bạn thử sai quá nhiều lần. Thử lại sau 5 phút.") : base(message) { }

    public TooManyRequestsException(string message, Exception innerException)
        : base(message, innerException) { }
}
