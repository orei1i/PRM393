using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace DomainLayer.Entities
{
    public class Comment : BaseEntity
    {
        [BsonRepresentation(BsonType.ObjectId)]
        public string PostId { get; set; } = string.Empty;

        [BsonRepresentation(BsonType.ObjectId)]
        public string UserId { get; set; } = string.Empty;

        [BsonRepresentation(BsonType.ObjectId)]
        [BsonIgnoreIfNull]
        public string? ParentId { get; set; }

        public string Content { get; set; } = string.Empty;

        public int ReplyCount { get; set; } = 0;

        /// <summary>"Visible" | "Hidden". Dòng cũ không có trường này đọc ra Visible.</summary>
        public string Status { get; set; } = "Visible";

        public int ReportCount { get; set; } = 0;

        /// <summary>Lý do admin xoá, để báo lại cho tác giả.</summary>
        [BsonIgnoreIfNull]
        public string? DeleteReason { get; set; }
    }
}
