using System;
using System.Collections.Generic;
using static DomainLayer.Enums.GeneralEnum;

namespace DomainLayer.Entities
{
    public class User : BaseEntity
    {
        public string Email { get; set; }

        public string? PasswordHash { get; set; }

        public string FullName { get; set; }

        public string Phone { get; set; }

        public UserStatusEnum? Status { get; set; }

        public AuthTypeEnum? AuthType { get; set; }

        public string? GoogleId { get; set; }

        public string Role { get; set; } = "Member";
    }
}