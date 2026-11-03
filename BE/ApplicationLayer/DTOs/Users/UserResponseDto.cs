using System.Text.Json.Serialization;
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
        [JsonConverter(typeof(JsonStringEnumConverter))]
        public UserStatusEnum? Status { get; set; }
        [JsonConverter(typeof(JsonStringEnumConverter))]
        public AuthTypeEnum? AuthType { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    /// <summary>Dòng người dùng cho Web admin.</summary>
    public class AdminUserResponse : UserResponse
    {
        public bool IsVerifiedChef { get; set; }
        public int PostCount { get; set; }
        public int ReportCount { get; set; }
        public DateTime? LastActiveAt { get; set; }
        public string? StatusReason { get; set; }
    }
}
