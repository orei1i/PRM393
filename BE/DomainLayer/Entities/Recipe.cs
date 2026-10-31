using System.Collections.Generic;
using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace DomainLayer.Entities
{
    public class RecipeSeasonalSwap
    {
        public string Ingredient { get; set; } = string.Empty;
        public string RecipeId { get; set; } = string.Empty;
    }

    public class Recipe : BaseEntity
    {
        public string Name { get; set; } = string.Empty;

        public string NormalizedName { get; set; } = string.Empty;

        public string? ImageUrl { get; set; }

        /// <summary>
        /// "breakfast", "lunch", "dinner", "snack_am", "snack_pm", "snack_late"
        /// </summary>
        public List<string> MealTypes { get; set; } = new();

        public int? PrepMinutes { get; set; }

        public int Calories { get; set; }

        public double? ProteinG { get; set; }

        public double? CarbsG { get; set; }

        public double? FatG { get; set; }

        public double? FiberG { get; set; }

        public List<string> Allergens { get; set; } = new();

        public List<string> DietTags { get; set; } = new();

        public List<string> Ingredients { get; set; } = new();

        public List<string> Instructions { get; set; } = new();

        public bool IsVegan { get; set; } = true;

        [BsonRepresentation(BsonType.ObjectId)]
        public string? CreatedBy { get; set; } = null; // null hoặc "system" nếu là món mặc định

        public RecipeSeasonalSwap? SeasonalSwap { get; set; }
    }
}

