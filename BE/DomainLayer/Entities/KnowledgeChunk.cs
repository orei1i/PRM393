using System;
using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace DomainLayer.Entities
{
    public class KnowledgeChunk : BaseEntity
    {
        [BsonRepresentation(BsonType.ObjectId)]
        public string DocId { get; set; } = string.Empty;

        public int ChunkIndex { get; set; }

        public string Content { get; set; } = string.Empty;

        /// <summary>Vector đã chuẩn hoá về độ dài 1. Null cho tới khi tài liệu được duyệt.</summary>
        [BsonIgnoreIfNull]
        public float[]? Embedding { get; set; }
    }

    public class IngestionJob : BaseEntity
    {
        [BsonRepresentation(BsonType.ObjectId)]
        public string DocId { get; set; } = string.Empty;

        /// <summary>"Pending" | "Done" | "Failed"</summary>
        public string Status { get; set; } = IngestStatuses.Pending;

        [BsonIgnoreIfNull]
        public string? Error { get; set; }

        public DateTime StartedAt { get; set; } = DateTime.UtcNow;

        [BsonIgnoreIfNull]
        public DateTime? FinishedAt { get; set; }
    }
}
