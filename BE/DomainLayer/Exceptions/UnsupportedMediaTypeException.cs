namespace DomainLayer.Exceptions;

/// <summary>
/// Thrown when the client uploads an unsupported media format/content-type.
/// Maps to HTTP 415 Unsupported Media Type.
/// </summary>
public class UnsupportedMediaTypeException : BaseHttpException
{
    public UnsupportedMediaTypeException(string message = "Unsupported Media Type") : base(message) { }

    public UnsupportedMediaTypeException(string message, Exception innerException)
        : base(message, innerException) { }
}
