using System.Collections.Generic;

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
        public int? PrepMinutes { get; set; } = 20;
        public List<string>? Ingredients { get; set; }
        public List<string>? Instructions { get; set; }
    }
}

