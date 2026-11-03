using System;
using System.Collections.Generic;
using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace DomainLayer.Entities
{
    public class PlanAdjustmentChange
    {
        public string Id { get; set; } = string.Empty;
        public string Date { get; set; } = string.Empty;
        public string Slot { get; set; } = string.Empty;
        public string Action { get; set; } = "replace";
        public string? FromRecipeId { get; set; }
        public string? FromName { get; set; }
        public int FromCalories { get; set; }
        public string? ToRecipeId { get; set; }
        public int KcalDelta { get; set; }
    }

    /// <summary>Đề xuất chỉnh thực đơn đang chờ người dùng chọn.</summary>
    public class MealPlanAdjustment : BaseEntity
    {
        [BsonRepresentation(BsonType.ObjectId)]
        public string UserId { get; set; } = string.Empty;

        [BsonRepresentation(BsonType.ObjectId)]
        public string PlanId { get; set; } = string.Empty;

        public string Message { get; set; } = string.Empty;

        public string Reply { get; set; } = string.Empty;

        public List<PlanAdjustmentChange> Changes { get; set; } = new();

        public DateTime? AppliedAt { get; set; }
    }
}
