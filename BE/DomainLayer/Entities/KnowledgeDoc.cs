using System;
using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace DomainLayer.Entities
{
    /// <summary>
    /// Tài liệu tri thức cho chatbot RAG. Nằm trong DB RAG riêng (RagDatabaseName).
    /// Chỉ tài liệu Status = Approved mới được truy xuất.
    /// </summary>
    public class KnowledgeDoc : BaseEntity
    {
        [BsonRepresentation(BsonType.ObjectId)]
        [BsonIgnoreIfNull]
        public string? ChefId { get; set; }

        [BsonIgnoreIfNull]
        public string? ChefName { get; set; }

        public string Title { get; set; } = string.Empty;

        /// <summary>"WHO" | "Chef"</summary>
        public string Source { get; set; } = KnowledgeSources.Chef;

        /// <summary>Liên kết nguồn công khai (nếu có), dùng làm url của citation.</summary>
        [BsonIgnoreIfNull]
        public string? FileUrl { get; set; }

        [BsonIgnoreIfNull]
        public string? Publisher { get; set; }

        [BsonIgnoreIfNull]
        public DateTime? PublishedAt { get; set; }

        /// <summary>"Pending" | "Approved" | "Rejected"</summary>
        public string Status { get; set; } = KnowledgeDocStatuses.Pending;

        public int ChunkCount { get; set; }

        public int CitationCount { get; set; }

        [BsonIgnoreIfNull]
        public string? ReviewNote { get; set; }

        [BsonIgnoreIfNull]
        public string? ReviewedBy { get; set; }

        [BsonIgnoreIfNull]
        public DateTime? ReviewedAt { get; set; }

        /// <summary>"Pending" | "Done" | "Failed": tạo embedding đã xong chưa.</summary>
        public string IngestStatus { get; set; } = IngestStatuses.Pending;

        [BsonIgnoreIfNull]
        public string? IngestError { get; set; }

        /// <summary>SHA-256 của nội dung đã chuẩn hoá, để chặn tài liệu trùng.</summary>
        public string ContentHash { get; set; } = string.Empty;

        public string Content { get; set; } = string.Empty;
    }

    public static class KnowledgeSources
    {
        public const string Who = "WHO";
        public const string Chef = "Chef";
    }

    public static class KnowledgeDocStatuses
    {
        public const string Pending = "Pending";
        public const string Approved = "Approved";
        public const string Rejected = "Rejected";
    }

    public static class IngestStatuses
    {
        public const string Pending = "Pending";
        public const string Done = "Done";
        public const string Failed = "Failed";
    }
}
