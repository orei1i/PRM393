using System.Collections.Generic;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.MealPlan;
using ApplicationLayer.DTOs.Posts;

namespace ApplicationLayer.Interfaces
{
    public interface IRecipeService
    {
        Task<RecipeCatalogPageResponse> GetCatalogAsync(string? q, bool veganOnly, int? limit, string? cursor);
        Task<RecipeResponse> GetByIdAsync(string? userId, string recipeId);
        Task<RecipeResponse> UpdateMineAsync(string userId, string recipeId, CreateRecipeRequest request);
        Task DeleteMineAsync(string userId, string recipeId);
        Task<RecipeResponse> CreateVariantAsync(string userId, string recipeId, CreateRecipeVariantRequest request);

        Task<RecipeReviewsPageResponse> GetReviewsAsync(string? userId, string recipeId, string? cursor, int? limit);
        Task<ReviewWriteResponse> UpsertMyReviewAsync(string userId, string recipeId, UpsertRecipeReviewRequest request);
        Task<RatingTotalsResponse> DeleteMyReviewAsync(string userId, string recipeId);

        Task<RecipeNoteResponse> GetMyNoteAsync(string userId, string recipeId);
        Task<RecipeNoteResponse?> SaveMyNoteAsync(string userId, string recipeId, SaveRecipeNoteRequest request);
        Task DeleteMyNoteAsync(string userId, string recipeId);

        Task<IEnumerable<PostResponse>> GetRelatedPostsAsync(string? userId, string recipeId);
    }

    public interface IMealPlanAdjustService
    {
        Task<PlanAdjustmentResponse> ProposeAsync(string userId, AdjustPlanRequest request);
        Task<MealPlanResponse> ApplyAsync(string userId, string proposalId, ApplyAdjustmentRequest request);
        Task<IEnumerable<ChefSuggestionResponse>> GetChefSuggestionsAsync(string userId);
    }
}
