using System;
using System.Collections.Generic;
using ApplicationLayer.DTOs.Pantry;
using ApplicationLayer.DTOs.Posts;

namespace ApplicationLayer.DTOs.Content
{
    public class PersonRef
    {
        public string Id { get; set; } = string.Empty;
        public string FullName { get; set; } = string.Empty;
    }

    public class RestaurantResponse
    {
        public string Id { get; set; } = string.Empty;
        public string? CreatedBy { get; set; }
        public string? CreatedByName { get; set; }
        public string Name { get; set; } = string.Empty;
        public string Address { get; set; } = string.Empty;
        public bool IsVeganCertified { get; set; }
        public double? Latitude { get; set; }
        public double? Longitude { get; set; }
        public double? DistanceKm { get; set; }
        public double? AverageRating { get; set; }
        public int ReviewCount { get; set; }
    }

    public class RestaurantSuggestionResponse
    {
        public string Id { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string Address { get; set; } = string.Empty;
        public double? Latitude { get; set; }
        public double? Longitude { get; set; }
        public bool IsVeganCertified { get; set; }
        public PersonRef? CreatedBy { get; set; }
        public double? AverageRating { get; set; }
        public int ReviewCount { get; set; }
        public string Status { get; set; } = string.Empty;
        public string? RejectionReason { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? ReviewedAt { get; set; }
    }

    /// <summary>createdBy null nghĩa là Ban quản trị; reviewedBy là tên admin.</summary>
    public class AdminRestaurantResponse : RestaurantSuggestionResponse
    {
        public string? ReviewedBy { get; set; }
        public List<RestaurantMediaResponse> Media { get; set; } = new();
    }

    public class RestaurantMediaResponse
    {
        public string Id { get; set; } = string.Empty;
        public string MediaType { get; set; } = string.Empty;
        public string MediaUrl { get; set; } = string.Empty;
        public PersonRef? UploadedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class RestaurantReviewResponse
    {
        public string Id { get; set; } = string.Empty;
        public string UserId { get; set; } = string.Empty;
        public string RestaurantId { get; set; } = string.Empty;
        public int Rating { get; set; }
        public string Comment { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public PersonRef User { get; set; } = new();
    }

    public class UpsertRestaurantReviewRequest
    {
        public int? Rating { get; set; }
        public string? Comment { get; set; }
    }

    public class RestaurantMediaInput
    {
        public string? MediaType { get; set; }
        public string? MediaUrl { get; set; }
    }

    public class CreateRestaurantRequest
    {
        public string? Name { get; set; }
        public string? Address { get; set; }
        public double? Latitude { get; set; }
        public double? Longitude { get; set; }
        public List<RestaurantMediaInput>? Media { get; set; }
    }

    public class ReviewRestaurantRequest
    {
        public string? Decision { get; set; }
        public string? Reason { get; set; }
    }

    public class SetRestaurantCertifiedRequest
    {
        public bool? IsVeganCertified { get; set; }
    }

    public class RestaurantListQuery
    {
        public double? Lat { get; set; }
        public double? Lng { get; set; }
        public string? Q { get; set; }
        public bool CertifiedOnly { get; set; }
        public string? Sort { get; set; }
        public double? RadiusKm { get; set; }
        public int? Limit { get; set; }
    }

    public class PlaceResponse
    {
        public string Name { get; set; } = string.Empty;
        public string Address { get; set; } = string.Empty;
        public string? City { get; set; }
        public double Latitude { get; set; }
        public double Longitude { get; set; }
    }

    public class RecipeSummaryResponse
    {
        public string Id { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public int CaloriesCache { get; set; }
        public bool IsVegan { get; set; }
    }

    public class SearchSuggestionBlock
    {
        public RecipeSummaryResponse Recipe { get; set; } = new();
        public List<PostResponse> RelatedPosts { get; set; } = new();
        public List<RestaurantResponse> Restaurants { get; set; } = new();
    }

    public class SearchResponse
    {
        public string Query { get; set; } = string.Empty;
        public List<PostResponse> Posts { get; set; } = new();
        public List<PostResponse> Videos { get; set; } = new();
        public List<RecipeSummaryResponse> Recipes { get; set; } = new();
        public List<IngredientResponse> Ingredients { get; set; } = new();
        public List<RestaurantResponse> Restaurants { get; set; } = new();
        public SearchSuggestionBlock? Suggestion { get; set; }
    }

    public class SearchSuggestItem
    {
        public string Kind { get; set; } = string.Empty;
        public string Text { get; set; } = string.Empty;
        public string? Id { get; set; }
        public string? Subtitle { get; set; }
    }

    public class SearchCategoryResponse
    {
        public string Id { get; set; } = string.Empty;
        public string Label { get; set; } = string.Empty;
        public string Query { get; set; } = string.Empty;
    }

    public class SearchDiscoverResponse
    {
        /// <summary>Rỗng: BE chưa ghi lịch sử tìm kiếm nên chưa có xu hướng thật.</summary>
        public List<string> Trending { get; set; } = new();
        public List<SearchCategoryResponse> Categories { get; set; } = new();

        /// <summary>Rỗng: BE chưa có dữ liệu nguyên liệu theo mùa.</summary>
        public List<object> Seasonal { get; set; } = new();
        public List<RecipeSummaryResponse> PopularRecipes { get; set; } = new();
        public List<RestaurantResponse> NearbyRestaurants { get; set; } = new();
    }
}
