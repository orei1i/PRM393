using static DomainLayer.Enums.GeneralEnum;

namespace ApplicationLayer.DTOs.Users
{
    /// <summary>
    /// Thống kê tương tác của người dùng trên nền tảng.
    /// </summary>
    public class UserStatsDto
    {
        public int Posts { get; set; } = 0;
        public int LikesReceived { get; set; } = 0;
        public int Saved { get; set; } = 0;
    }

    /// <summary>
    /// Tóm tắt trạng thái đơn đăng ký đầu bếp / chuyên gia.
    /// </summary>
    public class ChefApplicationSummaryDto
    {
        public string Status { get; set; } = "none"; // none | pending | approved | rejected
        public string? RejectReason { get; set; }
    }

    /// <summary>
    /// DTO chi tiết hồ sơ cá nhân trả về cho endpoint GET /api/v1/users/me.
    /// Khớp chính xác với mô hình UserProfileDto của Mobile App.
    /// </summary>
    public class UserProfileResponse : UserResponse
    {
        public UserStatsDto Stats { get; set; } = new();
        public ChefApplicationSummaryDto ChefApplication { get; set; } = new();
    }
}
