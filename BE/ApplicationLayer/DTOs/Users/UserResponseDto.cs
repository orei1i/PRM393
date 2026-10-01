using static DomainLayer.Enums.GeneralEnum;

namespace ApplicationLayer.DTOs.Users
{
    /// <summary>
    /// DTO trả về thông tin user — không bao gồm PasswordHash.
    /// </summary>
    public class UserResponse
    {
        public string Id { get; set; } = string.Empty;
        public string Email { get; set; } = string.Empty;
        public string FullName { get; set; } = string.Empty;
        public string Phone { get; set; } = string.Empty;
        public string Role { get; set; } = string.Empty;
        public UserStatusEnum? Status { get; set; }
        public AuthTypeEnum? AuthType { get; set; }
        public DateTime CreatedAt { get; set; }
    }
}
