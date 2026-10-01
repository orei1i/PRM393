namespace DomainLayer.Exceptions
{
    /// <summary>Kho không đủ — map tới HTTP 400 qua <see cref="DomainException"/>.</summary>
    public class InsufficientStockException : DomainException
    {
        public InsufficientStockException(string message) : base(message) { }
    }
}