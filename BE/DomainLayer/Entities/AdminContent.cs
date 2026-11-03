using System;
using System.Collections.Generic;
using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace DomainLayer.Entities
{
    public class CatalogItem : BaseEntity
    {
        /// <summary>category | diet_tag | allergen | specialty</summary>
        public string Kind { get; set; } = string.Empty;
        public string Code { get; set; } = string.Empty;
        public string Label { get; set; } = string.Empty;
        public bool Active { get; set; } = true;
        public string? CvLabel { get; set; }
    }

    /// <summary>
    /// Cờ kiểm duyệt AI. Hiện KHÔNG có pipeline nào tạo cờ, nên hàng đợi rỗng là dữ liệu thật;
    /// lớp này giữ sẵn chỗ để route quyết định chạy đúng khi có pipeline.
    /// </summary>
    public class ModerationFlag : BaseEntity
    {
        [BsonRepresentation(BsonType.ObjectId)]
        public string PostId { get; set; } = string.Empty;

        /// <summary>pending | escalated | resolved</summary>
        public string Status { get; set; } = "pending";
        public string PrimaryCategory { get; set; } = string.Empty;
        public double Confidence { get; set; }
        public double ToxicityScore { get; set; }
        public List<ModerationScore> Scores { get; set; } = new();
        public string Reason { get; set; } = string.Empty;
        public List<ModerationSpan> Spans { get; set; } = new();
        public string SuggestedAction { get; set; } = string.Empty;
        public string? PolicyRef { get; set; }
        public string? ModelVersion { get; set; }
        public long LatencyMs { get; set; }
        public string? TraceId { get; set; }

        public string? Action { get; set; }
        public string? DecisionNote { get; set; }
        public string? DecidedBy { get; set; }
        public DateTime? DecidedAt { get; set; }
    }

    public class ModerationScore
    {
        public string Category { get; set; } = string.Empty;
        public double Score { get; set; }
    }

    public class ModerationSpan
    {
        public int Start { get; set; }
        public int End { get; set; }
        public string Category { get; set; } = string.Empty;
    }

    /// <summary>Nhật ký thao tác admin, nguồn của "Hoạt động gần đây" ở trang tổng quan.</summary>
    public class AdminAuditLog : BaseEntity
    {
        public string Actor { get; set; } = string.Empty;
        public string Action { get; set; } = string.Empty;
        public string Target { get; set; } = string.Empty;
        public string? Note { get; set; }
    }

    /// <summary>Nhãn đúng/sai của admin cho một dòng AiLog. Tách collection để không đổi tài liệu AiLog đang được ghi.</summary>
    public class AiLogLabel : BaseEntity
    {
        [BsonRepresentation(BsonType.ObjectId)]
        public string LogId { get; set; } = string.Empty;

        /// <summary>correct | incorrect</summary>
        public string Verdict { get; set; } = string.Empty;
        public string? Note { get; set; }
        public string By { get; set; } = string.Empty;
        public DateTime At { get; set; }
    }

    /// <summary>
    /// Cấu hình quản trị của một mô hình AI. Giá trị được lưu và ghi nhật ký; hiện chatbot và vision chưa đọc
    /// các giá trị này khi chạy (xem RuntimeEnforced ở phản hồi API).
    /// </summary>
    public class AiModelConfig : BaseEntity
    {
        /// <summary>moderation | meal_plan | chatbot | vision_scan</summary>
        public string Task { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string ActiveVersion { get; set; } = string.Empty;
        public List<string> AvailableVersions { get; set; } = new();
        public bool Enabled { get; set; } = true;
        public double? Threshold { get; set; }
        public string Fallback { get; set; } = string.Empty;
        public string? UpdatedBy { get; set; }
    }
}
