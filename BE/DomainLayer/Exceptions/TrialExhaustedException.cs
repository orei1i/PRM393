namespace DomainLayer.Exceptions;

/// <summary>
/// Thrown when a guest has used every free chatbot question.
/// Maps to HTTP 402 with code trial_exhausted (the mobile app shows the sign-in sheet on it).
/// </summary>
public class TrialExhaustedException : BaseHttpException
{
    public TrialExhaustedException(string message = "Bạn đã dùng hết lượt hỏi miễn phí. Đăng nhập để hỏi tiếp.")
        : base(message, "trial_exhausted") { }
}
