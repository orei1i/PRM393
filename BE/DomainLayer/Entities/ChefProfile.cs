using System;
using System.Collections.Generic;
using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace DomainLayer.Entities
{
    /// <summary>Hồ sơ công khai của chuyên gia. Id này là chefId khi đặt; id user nằm ở UserId.</summary>
    public class ChefProfile : BaseEntity
    {
        [BsonRepresentation(BsonType.ObjectId)]
        public string UserId { get; set; } = string.Empty;

        public string Specialty { get; set; } = string.Empty;
        public string Bio { get; set; } = string.Empty;
        public int YearsExperience { get; set; }
        public string City { get; set; } = string.Empty;
        public List<string> Certificates { get; set; } = new();

        /// <summary>0 là chưa có giá: app hiện "Chờ báo giá".</summary>
        public long PricePerDay { get; set; }
        public long FeedbackPricePerDay { get; set; }

        public int MinPlanDays { get; set; } = 3;
        public int MaxPlanDays { get; set; } = 30;
        public bool AcceptingBookings { get; set; } = true;
    }

    public class ChefApplication : BaseEntity
    {
        [BsonRepresentation(BsonType.ObjectId)]
        public string UserId { get; set; } = string.Empty;

        public List<string> Specialties { get; set; } = new();
        public int YearsExperience { get; set; }
        public string City { get; set; } = string.Empty;
        public string Bio { get; set; } = string.Empty;
        public List<ChefCertificate> Certificates { get; set; } = new();

        /// <summary>pending | approved | rejected</summary>
        public string Status { get; set; } = ChefApplicationStatuses.Pending;

        public string? ReviewNote { get; set; }
        public string? ReviewedBy { get; set; }
        public DateTime? ReviewedAt { get; set; }
    }

    public class ChefCertificate
    {
        public string Name { get; set; } = string.Empty;
        public string? FileUrl { get; set; }
    }

    public static class ChefApplicationStatuses
    {
        public const string Pending = "pending";
        public const string Approved = "approved";
        public const string Rejected = "rejected";
    }
}
