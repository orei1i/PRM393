using System;
using System.Collections.Generic;
using ApplicationLayer.DTOs.Posts;

namespace ApplicationLayer.DTOs.MealPlan
{
    public class RecipeCatalogPageResponse
    {
        public List<RecipeResponse> Items { get; set; } = new();
        public string? NextCursor { get; set; }
    }

    public class RecipeSwapRequest
    {
        public string IngredientKey { get; set; } = string.Empty;
        public string SubstituteKey { get; set; } = string.Empty;
    }

    public class CreateRecipeVariantRequest
    {
        public string Name { get; set; } = string.Empty;
        public List<RecipeSwapRequest>? Swaps { get; set; }
        public List<string>? Removed { get; set; }
    }

    public class RecipeReviewResponse
    {
        public string Id { get; set; } = string.Empty;
        public int Rating { get; set; }
        public string? Content { get; set; }
        public AuthorSummaryDto Author { get; set; } = new();
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class RecipeReviewsPageResponse
    {
        public string RecipeId { get; set; } = string.Empty;
        public double? AverageRating { get; set; }
        public int RatingCount { get; set; }
        public Dictionary<string, int> Distribution { get; set; } = new();
        public RecipeReviewResponse? MyReview { get; set; }
        public List<RecipeReviewResponse> Items { get; set; } = new();
        public string? NextCursor { get; set; }
    }

    public class UpsertRecipeReviewRequest
    {
        public int Rating { get; set; }
        public string? Content { get; set; }
    }

    public class RatingTotalsResponse
    {
        public double? AverageRating { get; set; }
        public int RatingCount { get; set; }
    }

    public class ReviewWriteResponse : RatingTotalsResponse
    {
        public RecipeReviewResponse Review { get; set; } = new();
    }

    public class SaveRecipeNoteRequest
    {
        public string? Content { get; set; }
    }

    public class RecipeNoteResponse
    {
        public string RecipeId { get; set; } = string.Empty;
        public string Content { get; set; } = string.Empty;
        public DateTime UpdatedAt { get; set; }
    }

    public class AdjustPlanRequest
    {
        public string Message { get; set; } = string.Empty;
        public string Scope { get; set; } = "day";
        public string? Date { get; set; }
    }

    public class ApplyAdjustmentRequest
    {
        public List<string> ChangeIds { get; set; } = new();
    }

    public class PlanChangeResponse
    {
        public string Id { get; set; } = string.Empty;
        public string Date { get; set; } = string.Empty;
        public string Slot { get; set; } = string.Empty;
        public string Action { get; set; } = "replace";
        public RecipeResponse? From { get; set; }
        public RecipeResponse? To { get; set; }
        public int KcalDelta { get; set; }
    }

    public class PlanAdjustmentResponse
    {
        public string ProposalId { get; set; } = string.Empty;
        public string Reply { get; set; } = string.Empty;
        public List<PlanChangeResponse> Changes { get; set; } = new();
    }

    public class ChefSuggestionResponse
    {
        public string Id { get; set; } = string.Empty;
        public string ChefId { get; set; } = string.Empty;
        public string ChefName { get; set; } = string.Empty;
        public string? Note { get; set; }
        public string Slot { get; set; } = string.Empty;
        public string TargetDate { get; set; } = string.Empty;
        public DateTime? CreatedAt { get; set; }
        public RecipeResponse Recipe { get; set; } = new();
    }
}
