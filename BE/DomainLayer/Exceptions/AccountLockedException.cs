namespace DomainLayer.Exceptions;

/// <summary>
/// Thrown when the user account is locked or banned.
/// Maps to HTTP 423 Locked.
/// </summary>
public class AccountLockedException : BaseHttpException
{
    public AccountLockedException(string message = "Tài khoản đang bị khoá. Liên hệ hỗ trợ.") : base(message) { }

    public AccountLockedException(string message, Exception innerException)
        : base(message, innerException) { }
}
