namespace DomainLayer.Exceptions
{
    public class DomainException : Exception
    {
        public string? ErrorCode { get; set; }

        public DomainException()
        {
        }

        public DomainException(string message, string? errorCode = null)
            : base(message)
        {
            ErrorCode = errorCode;
        }

        public DomainException(string message, Exception innerException, string? errorCode = null)
            : base(message, innerException)
        {
            ErrorCode = errorCode;
        }
    }
}
