using System.Collections.Generic;
using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace DomainLayer.Entities
{
    public class Post : BaseEntity
    {
        [BsonRepresentation(BsonType.ObjectId)]
        public string UserId { get; set; } = string.Empty;

        public string Type { get; set; } = "discussion"; // "recipe" | "discussion"

        public string Title { get; set; } = string.Empty;

        public string Body { get; set; } = string.Empty;

        public string? CoverSeed { get; set; }

        public List<string> Tags { get; set; } = new();

        public string MediaType { get; set; } = "Text"; // "Text" | "Image" | "Video"

        public string? MediaUrl { get; set; }

        [BsonRepresentation(BsonType.ObjectId)]
        [BsonIgnoreIfNull]
        public string? RestaurantId { get; set; }

        public string Status { get; set; } = "Published"; // "Published" | "Pending" | "Rejected"

        public string? RejectionReason { get; set; }

        public int LikeCount { get; set; } = 0;

        public int CommentCount { get; set; } = 0;

        public int ReportCount { get; set; } = 0;

        public bool IsPinned { get; set; } = false;
    }
}
