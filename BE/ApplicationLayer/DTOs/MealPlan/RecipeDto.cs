using System.Collections.Generic;
using System.Text.Json.Serialization;
using DomainLayer.Entities;

namespace ApplicationLayer.DTOs.MealPlan
{
    public class RecipeResponse
    {
        public string Id { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string? ImageUrl { get; set; }
        public int Calories { get; set; }
        public double? ProteinG { get; set; }
        public double? CarbsG { get; set; }
        public double? FatG { get; set; }
        public double? FiberG { get; set; }
        public List<string> Allergens { get; set; } = new();
        public List<string> DietTags { get; set; } = new();
        public int? PrepMinutes { get; set; }
        public List<string> Ingredients { get; set; } = new();
        public List<string> Instructions { get; set; } = new();
        public SeasonalSwapDto? SeasonalSwap { get; set; }
        public bool IsVegan { get; set; } = true;
        public int? Servings { get; set; }
        public string? CreatedBy { get; set; }

        /// <summary>Bỏ hẳn khi chưa có, vì app coi trường này có mặt là dữ liệu chuẩn.</summary>
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public List<RecipeIngredientItem>? IngredientItems { get; set; }

        public string? BasedOnRecipeId { get; set; }
        public string? BasedOnName { get; set; }
        public List<RecipeCustomization> Customizations { get; set; } = new();
        public bool NutritionEstimated { get; set; }
        public double? AverageRating { get; set; }
        public int RatingCount { get; set; }
    }

    public class CreateRecipeRequest
    {
        public string Name { get; set; } = string.Empty;
        public string? ImageUrl { get; set; }
        public int Calories { get; set; }
        public double? ProteinG { get; set; }
        public double? CarbsG { get; set; }
        public double? FatG { get; set; }
        public double? FiberG { get; set; }
        public List<string>? Allergens { get; set; }
        public List<string>? DietTags { get; set; }

        /// <summary>Không gửi thì để trống, không tự gán một con số không có thật (B33).</summary>
        public int? PrepMinutes { get; set; }
        public List<string>? Ingredients { get; set; }
        public List<string>? Instructions { get; set; }
        public int? Servings { get; set; }
        public string? BasedOnRecipeId { get; set; }
        public List<RecipeIngredientItem>? IngredientItems { get; set; }
    }
}
