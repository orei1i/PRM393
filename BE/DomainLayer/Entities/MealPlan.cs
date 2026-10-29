using System;
using System.Collections.Generic;
using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace DomainLayer.Entities
{
    public class MealSlotItem
    {
        public string Id { get; set; } = Guid.NewGuid().ToString("N");

        public string? RecipeId { get; set; }

        public string Name { get; set; } = string.Empty;

        public int Calories { get; set; }

        public double? ProteinG { get; set; }

        public double? CarbsG { get; set; }

        public double? FatG { get; set; }

        public double? FiberG { get; set; }

        public List<string> Allergens { get; set; } = new();

        public List<string> DietTags { get; set; } = new();

        public int PrepMinutes { get; set; } = 15;

        public string? ImageUrl { get; set; }

        /// <summary>
        /// "ai" | "manual" | "user_recipe" | "chef" | "fridge_scan"
        /// </summary>
        public string Source { get; set; } = "ai";

        public string? SourceName { get; set; }

        public double Portion { get; set; } = 1.0;

        public RecipeSeasonalSwap? SeasonalSwap { get; set; }

        public List<string> AllergyConflicts { get; set; } = new();
    }

    public class MealPlanDay
    {
        /// <summary>
        /// YYYY-MM-DD
        /// </summary>
        public string Date { get; set; } = string.Empty;

        /// <summary>
        /// key: "breakfast" | "lunch" | "dinner" | "snack_am" | "snack_pm" | "snack_late"
        /// </summary>
        public Dictionary<string, MealSlotItem> Meals { get; set; } = new();
    }

    public class MealPlanDailyTargets
    {
        public int Calories { get; set; }
        public double? ProteinG { get; set; }
        public double? CarbsG { get; set; }
        public double? FatG { get; set; }
        public double? FiberG { get; set; }
    }

    public class MealPlan : BaseEntity
    {
        [BsonRepresentation(BsonType.ObjectId)]
        public string UserId { get; set; } = string.Empty;

        /// <summary>
        /// Ngày đầu tuần: YYYY-MM-DD (thường là Thứ Hai)
        /// </summary>
        public string StartDate { get; set; } = string.Empty;

        public string Goal { get; set; } = "maintain";

        public MealPlanDailyTargets DailyTargets { get; set; } = new();

        /// <summary>
        /// Danh sách 7 ngày trong tuần
        /// </summary>
        public List<MealPlanDay> Days { get; set; } = new();
    }
}

