namespace DomainLayer.Exceptions;

/// <summary>
/// Thrown when a required external dependency is not configured or not reachable (AI, RAG DB).
/// Maps to HTTP 503 Service Unavailable.
/// </summary>
public class ServiceUnavailableException : BaseHttpException
{
    public ServiceUnavailableException(string message, string? errorCode = "ai_unavailable") : base(message, errorCode) { }

    public ServiceUnavailableException(string message, Exception innerException, string? errorCode = "ai_unavailable")
        : base(message, innerException, errorCode) { }
}
