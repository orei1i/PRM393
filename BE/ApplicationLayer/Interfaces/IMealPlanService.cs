using System.Collections.Generic;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.MealPlan;

namespace ApplicationLayer.Interfaces
{
    public interface IMealPlanService
    {
        Task<MealPlanResponse> GetCurrentMealPlanAsync(string userId);
        Task<MealPlanResponse> GetMealPlanByIdAsync(string userId, string planId);
        Task<MealPlanResponse> CreateMealPlanAsync(string userId, CreateMealPlanRequest request);
        Task<MealPlanResponse> GenerateMealPlanAsync(string userId, GenerateMealPlanRequest request);
        Task<MealPlanDayResponse> SwapMealAsync(string userId, string planId, SwapMealRequestDto request);
        Task<MealPlanDayResponse> AddMealToCurrentPlanAsync(string userId, AddMealRequestDto request);
        Task<AddMealsResultDto> AddMealsBatchToCurrentPlanAsync(string userId, List<AddMealRequestDto> requests);
        Task<MealPlanDayResponse> RemoveMealAsync(string userId, string planId, string date, string slot);
        Task<IEnumerable<RecipeResponse>> GetSwapSuggestionsAsync(string userId, string planId, string date, string slot, int limit = 3);

        Task<IEnumerable<RecipeResponse>> GetMyRecipesAsync(string userId);
        Task<RecipeResponse> CreateMyRecipeAsync(string userId, CreateRecipeRequest request);
    }
}

