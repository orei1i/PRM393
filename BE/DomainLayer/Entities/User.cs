using System;
using System.Collections.Generic;
using static DomainLayer.Enums.GeneralEnum;

namespace DomainLayer.Entities
{
    public class User : BaseEntity
    {
        public string Email { get; set; }

        public string? EmailNormalized { get; set; }

        public string? PasswordHash { get; set; }

        public string FullName { get; set; }

        public string Phone { get; set; }

        public UserStatusEnum? Status { get; set; }

        public AuthTypeEnum? AuthType { get; set; }

        public string? GoogleId { get; set; }

        public string Role { get; set; } = "User";

        public string? RefreshTokenHash { get; set; }

        public DateTime? RefreshTokenExpiresAt { get; set; }

        /// <summary>Mỗi thiết bị một phiên (B55). Hai trường trên chỉ còn để đọc dòng cũ.</summary>
        public List<RefreshSession> RefreshSessions { get; set; } = new();

        public DateTime? LastActiveAt { get; set; }

        /// <summary>Lý do khoá hoặc cấm, hiện cho người dùng trong app.</summary>
        public string? StatusReason { get; set; }

        public DateTime? StatusChangedAt { get; set; }

        public string? StatusChangedBy { get; set; }
    }

    public class RefreshSession
    {
        public string Id { get; set; } = string.Empty;
        public string TokenHash { get; set; } = string.Empty;
        public DateTime ExpiresAt { get; set; }
        public DateTime CreatedAt { get; set; }
    }
}
