using System;
using System.Collections.Generic;
using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace DomainLayer.Entities
{
    /// <summary>
    /// Phiên chat. App tự sinh sessionId nên khoá là (OwnerKey, ClientSessionId):
    /// hai người trùng sessionId vẫn là hai phiên riêng, không đọc được của nhau.
    /// </summary>
    public class ChatSession : BaseEntity
    {
        /// <summary>"u:{userId}" hoặc "g:{sha256(guestToken)}".</summary>
        public string OwnerKey { get; set; } = string.Empty;

        public string ClientSessionId { get; set; } = string.Empty;

        [BsonRepresentation(BsonType.ObjectId)]
        [BsonIgnoreIfNull]
        public string? UserId { get; set; }

        public DateTime StartedAt { get; set; } = DateTime.UtcNow;
    }

    public class ChatMessage : BaseEntity
    {
        [BsonRepresentation(BsonType.ObjectId)]
        public string SessionId { get; set; } = string.Empty;

        /// <summary>"user" | "assistant"</summary>
        public string Role { get; set; } = ChatRoles.User;

        public string Content { get; set; } = string.Empty;

        /// <summary>"complete" | "streaming" | "interrupted" | "failed"</summary>
        public string Status { get; set; } = ChatMessageStatuses.Complete;

        /// <summary>Id tham chiếu sang knowledge_chunks trong DB RAG.</summary>
        public List<string> CitedChunkIds { get; set; } = new();

        /// <summary>Ảnh chụp nguồn: câu trả lời cũ vẫn giữ trích dẫn sau khi tài liệu bị xoá.</summary>
        public List<ChatCitationSnapshot> Citations { get; set; } = new();

        /// <summary>Toàn bộ nguồn đã truy xuất cho lượt này, để tiếp tục câu trả lời dở vẫn đúng số [n].</summary>
        public List<ChatCitationSnapshot> RetrievedSources { get; set; } = new();
    }

    public class ChatCitationSnapshot
    {
        public int Index { get; set; }
        public string DocId { get; set; } = string.Empty;
        public string ChunkId { get; set; } = string.Empty;
        public string Title { get; set; } = string.Empty;
        public string Publisher { get; set; } = string.Empty;
        public string SourceType { get; set; } = "scientific";
        public string Passage { get; set; } = string.Empty;
        public string? Url { get; set; }
        public DateTime? PublishedAt { get; set; }
        public bool Verified { get; set; } = true;
    }

    /// <summary>Số câu hỏi miễn phí đã dùng của một guest token (lưu dạng băm).</summary>
    public class GuestTrial : BaseEntity
    {
        public string GuestKey { get; set; } = string.Empty;

        public int Used { get; set; }
    }

    public static class ChatRoles
    {
        public const string User = "user";
        public const string Assistant = "assistant";
    }

    public static class ChatMessageStatuses
    {
        public const string Complete = "complete";
        public const string Streaming = "streaming";
        public const string Interrupted = "interrupted";
        public const string Failed = "failed";
    }
}
