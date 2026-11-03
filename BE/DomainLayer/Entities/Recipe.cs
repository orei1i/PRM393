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

    public class RecipeNutrition
    {
        public double? Calories { get; set; }
        public double? ProteinG { get; set; }
        public double? CarbsG { get; set; }
        public double? FatG { get; set; }
        public double? FiberG { get; set; }
    }

    public class RecipeSubstituteItem
    {
        public string Key { get; set; } = string.Empty;
        public string? IngredientId { get; set; }
        public string Name { get; set; } = string.Empty;
        public double? Quantity { get; set; }
        public string Unit { get; set; } = string.Empty;
        public string? Role { get; set; }
        public string? Note { get; set; }
        public List<string>? Allergens { get; set; }
        public RecipeNutrition? Nutrition { get; set; }
    }

    public class RecipeIngredientItem
    {
        public string Key { get; set; } = string.Empty;
        public string? IngredientId { get; set; }
        public string Name { get; set; } = string.Empty;
        public double? Quantity { get; set; }
        public string Unit { get; set; } = string.Empty;
        public string? Role { get; set; }
        public bool IsSignature { get; set; }
        public bool IsOptional { get; set; }
        /// <summary>Null là chưa ghi, khác với danh sách rỗng.</summary>
        public List<string>? Allergens { get; set; }
        public RecipeNutrition? Nutrition { get; set; }
        public List<RecipeSubstituteItem> Substitutes { get; set; } = new();
    }

    /// <summary>Một thay đổi của bản tuỳ chỉnh: Type "swap" có From, To; "remove" có Name.</summary>
    public class RecipeCustomization
    {
        public string Type { get; set; } = "swap";
        public string? From { get; set; }
        public string? To { get; set; }
        public string? Name { get; set; }
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

        /// <summary>Số phần của công thức, null là chưa ghi.</summary>
        public int? Servings { get; set; }

        /// <summary>Bảng nguyên liệu có định lượng và món thay thế. Null là công thức chỉ có nguyên liệu dạng chữ.</summary>
        [BsonIgnoreIfNull]
        public List<RecipeIngredientItem>? IngredientItems { get; set; }

        [BsonRepresentation(BsonType.ObjectId)]
        [BsonIgnoreIfNull]
        public string? BasedOnRecipeId { get; set; }

        [BsonIgnoreIfNull]
        public string? BasedOnName { get; set; }

        public List<RecipeCustomization> Customizations { get; set; } = new();

        public bool NutritionEstimated { get; set; }

        public double? AverageRating { get; set; }

        public int RatingCount { get; set; }
    }
}

