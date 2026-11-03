using System;
using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace DomainLayer.Entities
{
    public class AdCampaign : BaseEntity
    {
        [BsonRepresentation(BsonType.ObjectId)]
        public string RestaurantId { get; set; } = string.Empty;

        public string Placement { get; set; } = "nearby";
        public string Headline { get; set; } = string.Empty;
        public string Message { get; set; } = string.Empty;
        public string CtaType { get; set; } = "ViewStore";

        /// <summary>null: toàn quốc.</summary>
        public string? TargetCity { get; set; }

        public DateTime StartAt { get; set; }
        public DateTime EndAt { get; set; }
        public bool IsPaused { get; set; }
        public long Budget { get; set; }
        public long Spent { get; set; }
        public long Impressions { get; set; }
        public long Clicks { get; set; }

        [BsonRepresentation(BsonType.ObjectId)]
        public string? CreatedBy { get; set; }
    }

    public static class AdStatuses
    {
        public const string Running = "Running";
        public const string Scheduled = "Scheduled";
        public const string Paused = "Paused";
        public const string Ended = "Ended";

        /// <summary>Trạng thái không lưu, luôn tính từ dữ liệu: quá hạn hoặc hết ngân sách trước, rồi tạm dừng, rồi chưa tới ngày.</summary>
        public static string Of(AdCampaign c, DateTime now)
        {
            if (c.EndAt < now || c.Spent >= c.Budget) return Ended;
            if (c.IsPaused) return Paused;
            return c.StartAt > now ? Scheduled : Running;
        }
    }
}
