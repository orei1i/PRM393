using System;
using System.Collections.Generic;
using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace DomainLayer.Entities
{
    public class Restaurant : BaseEntity
    {
        public string Name { get; set; } = string.Empty;
        public string Address { get; set; } = string.Empty;

        /// <summary>Có đủ cặp hoặc không có; không bao giờ lưu 0,0 thay cho "không biết".</summary>
        public double? Latitude { get; set; }
        public double? Longitude { get; set; }

        public bool IsVeganCertified { get; set; }

        /// <summary>Pending | Approved | Rejected. Chứng nhận thuần chay là cờ riêng ở IsVeganCertified.</summary>
        public string Status { get; set; } = RestaurantStatuses.Pending;
        public string? RejectionReason { get; set; }
        public DateTime? ReviewedAt { get; set; }
        public string? ReviewedBy { get; set; }

        /// <summary>null: quán do Ban quản trị tạo.</summary>
        [BsonRepresentation(BsonType.ObjectId)]
        public string? CreatedBy { get; set; }

        /// <summary>Tên và địa chỉ đã bỏ dấu; chỉ có khi quán chưa bị từ chối, để Mongo chặn gợi ý trùng kể cả khi gửi đồng thời.</summary>
        [BsonIgnoreIfNull]
        public string? DedupeKey { get; set; }

        public List<RestaurantMedia> Media { get; set; } = new();
    }

    public class RestaurantMedia
    {
        [BsonRepresentation(BsonType.ObjectId)]
        public string Id { get; set; } = string.Empty;
        public string MediaType { get; set; } = "Image";
        public string MediaUrl { get; set; } = string.Empty;

        [BsonRepresentation(BsonType.ObjectId)]
        public string? UploadedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class RestaurantReview : BaseEntity
    {
        [BsonRepresentation(BsonType.ObjectId)]
        public string RestaurantId { get; set; } = string.Empty;

        [BsonRepresentation(BsonType.ObjectId)]
        public string UserId { get; set; } = string.Empty;

        public int Rating { get; set; }
        public string Comment { get; set; } = string.Empty;
    }

    public static class RestaurantStatuses
    {
        public const string Pending = "Pending";
        public const string Approved = "Approved";
        public const string Rejected = "Rejected";
    }
}
