namespace ApplicationLayer.DTOs.Auth
{
    /// <summary>
    /// DTO trả về sau khi verify mã reset thành công. POST /auth/verify-reset-code
    /// </summary>
    public class VerifyResetCodeResponse
    {
        public string ResetToken { get; set; } = string.Empty;
    }
}
