using System.Collections.Generic;

namespace ApplicationLayer.DTOs.MealPlan
{
    public class DailyTargetsDto
    {
        public int Calories { get; set; }
        public double? ProteinG { get; set; }
        public double? CarbsG { get; set; }
        public double? FatG { get; set; }
        public double? FiberG { get; set; }
    }

    public class SeasonalSwapDto
    {
        public string Ingredient { get; set; } = string.Empty;
        public string RecipeId { get; set; } = string.Empty;
    }

    public class MealSlotItemDto
    {
        public string Id { get; set; } = string.Empty;
        public string? RecipeId { get; set; }
        public string Name { get; set; } = string.Empty;
        public int Calories { get; set; }
        public double? ProteinG { get; set; }
        public double? CarbsG { get; set; }
        public double? FatG { get; set; }
        public double? FiberG { get; set; }
        public List<string> Allergens { get; set; } = new();
        public List<string> DietTags { get; set; } = new();
        public int? PrepMinutes { get; set; }
        public string? ImageUrl { get; set; }
        public string Source { get; set; } = "ai";
        public string? SourceName { get; set; }
        public double Portion { get; set; } = 1.0;
        public SeasonalSwapDto? SeasonalSwap { get; set; }
        public List<string> AllergyConflicts { get; set; } = new();
    }

    public class MealPlanDayResponse
    {
        public string Date { get; set; } = string.Empty;
        public Dictionary<string, MealSlotItemDto> Meals { get; set; } = new();
        public int TotalCalories { get; set; }
    }

    public class MealPlanResponse
    {
        public string Id { get; set; } = string.Empty;
        public string StartDate { get; set; } = string.Empty;
        public string Goal { get; set; } = "maintain";
        public DailyTargetsDto DailyTargets { get; set; } = new();
        public List<MealPlanDayResponse> Days { get; set; } = new();
    }

    public class CreateMealPlanRequest
    {
        public string StartDate { get; set; } = string.Empty;
        public bool Empty { get; set; } = true;
    }

    public class GenerateMealPlanRequest
    {
        public string StartDate { get; set; } = string.Empty;
        public bool UsePantry { get; set; } = false;
    }

    public class SwapMealRequestDto
    {
        public string Date { get; set; } = string.Empty;
        public string Slot { get; set; } = string.Empty;
        public string RecipeId { get; set; } = string.Empty;
        public string? Source { get; set; }
        public string? SourceName { get; set; }
        public double? Portion { get; set; }
    }

    public class AddMealRequestDto
    {
        public string Date { get; set; } = string.Empty;
        public string Slot { get; set; } = string.Empty;
        public string? Source { get; set; } = "manual";
        public string? SourceId { get; set; }
        public string? RecipeId { get; set; }
        public string? SourceName { get; set; }
        public string Name { get; set; } = string.Empty;
        public int Calories { get; set; }
        public double? ProteinG { get; set; }
        public double? CarbsG { get; set; }
        public double? FatG { get; set; }
        public double? FiberG { get; set; }
        public double? Portion { get; set; }
        public int? PrepMinutes { get; set; } = 15;
        public List<string>? Ingredients { get; set; }
        public List<string>? Allergens { get; set; }
    }

    public class AddMealsBatchRequestDto
    {
        public List<AddMealRequestDto> Meals { get; set; } = new();
    }

    public class AddMealsResultDto
    {
        public int Placed { get; set; }
        public int Skipped { get; set; }
        public List<MealPlanDayResponse> Days { get; set; } = new();
    }
}
