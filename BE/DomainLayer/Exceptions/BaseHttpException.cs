namespace DomainLayer.Exceptions;

/// <summary>
/// Base class for all HTTP-mappable exceptions.
/// Completely decoupled from HTTP — status code mapping lives in the presentation layer middleware.
/// </summary>
public abstract class BaseHttpException : DomainException
{
    protected BaseHttpException() : base() { }

    protected BaseHttpException(string message, string? errorCode = null) : base(message, errorCode) { }

    protected BaseHttpException(string message, Exception innerException, string? errorCode = null)
        : base(message, innerException, errorCode) { }
}
