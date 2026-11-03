using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Content;

namespace ApplicationLayer.Interfaces
{
    public interface IAdminAuditService
    {
        Task<string> NameOfAsync(string adminId);

        /// <summary>Ghi nhật ký sau khi thao tác đã xong: lỗi ghi nhật ký không làm hỏng thao tác.</summary>
        Task LogAsync(string actor, string action, string target, string? note = null);
    }

    public interface IChefService
    {
        Task<List<ChefResponse>> ListAsync(string? q, string? specialty);
        Task<ChefResponse> GetAsync(string id);
        Task<ChefProfileResponse> GetMyProfileAsync(string userId);
        Task<ChefProfileResponse> SaveMyProfileAsync(string userId, SaveChefProfileRequest request);

        Task<ChefApplicationResponse> SubmitApplicationAsync(string userId, SubmitChefApplicationRequest request);
        Task<ChefApplicationStatusResponse> GetMyApplicationAsync(string userId);
        Task<List<ChefApplicationResponse>> ListApplicationsAsync(string? status);
        Task<Dictionary<string, long>> CountApplicationsAsync();
        Task<ChefApplicationResponse> ReviewApplicationAsync(string adminId, string id, ReviewChefApplicationRequest request);
    }

    public interface IRestaurantService
    {
        Task<List<RestaurantResponse>> ListPublicAsync(RestaurantListQuery query);
        Task<List<RestaurantResponse>> SuggestedAsync(string? food, double? lat, double? lng, int? limit);
        Task<RestaurantResponse> GetAsync(string id, double? lat, double? lng, string? viewerId, bool isAdmin);
        Task<List<RestaurantMediaResponse>> ListMediaAsync(string id, string? viewerId, bool isAdmin);
        Task<List<RestaurantReviewResponse>> ListReviewsAsync(string id, string? viewerId, bool isAdmin);
        Task<RestaurantReviewResponse> UpsertReviewAsync(string userId, string id, UpsertRestaurantReviewRequest request);
        Task<RestaurantSuggestionResponse> SuggestAsync(string userId, CreateRestaurantRequest request);
        Task<List<RestaurantSuggestionResponse>> ListMySuggestionsAsync(string userId);

        Task<List<AdminRestaurantResponse>> AdminListAsync(string? status, string? certified, string? source, string? search);
        Task<AdminRestaurantResponse> AdminReviewAsync(string adminId, string id, ReviewRestaurantRequest request);
        Task<AdminRestaurantResponse> AdminSetCertifiedAsync(string adminId, string id, SetRestaurantCertifiedRequest request);
        Task AdminDeleteAsync(string adminId, string id);
        Task<List<RestaurantReviewResponse>> AdminListReviewsAsync(string id);
        Task AdminDeleteReviewAsync(string adminId, string reviewId);
    }

    public interface IGeoService
    {
        Task<List<PlaceResponse>> SearchAsync(string? q, CancellationToken ct = default);
        Task<PlaceResponse> ReverseAsync(double? lat, double? lng, CancellationToken ct = default);
    }

    public interface ISearchService
    {
        Task<SearchResponse> SearchAsync(string? q, string? type, double? lat, double? lng, int? limit, string? viewerId);
        Task<List<SearchSuggestItem>> SuggestAsync(string? q, int? limit, string? viewerId);
        Task<SearchDiscoverResponse> DiscoverAsync(double? lat, double? lng);
    }

    public interface IAdService
    {
        Task<List<AdFeedItemResponse>> FeedAsync(string? placement, string? city, double? lat, double? lng, int? limit);
        Task RecordImpressionAsync(string id);
        Task RecordClickAsync(string id);

        Task<List<AdCampaignResponse>> AdminListAsync(string? status, string? city, string? search);
        Task<AdCampaignResponse> CreateAsync(string adminId, AdInputRequest request);
        Task<AdCampaignResponse> UpdateAsync(string adminId, string id, AdInputRequest request);
        Task<AdCampaignResponse> SetPausedAsync(string adminId, string id, bool paused);
        Task DeleteAsync(string adminId, string id);
    }

    public interface IVideoService
    {
        Task<VideoResponse> GetAsync(string id, string? viewerId, bool isAdmin);
        Task<VideoResponse> RetryExtractionAsync(string id, string userId, bool isAdmin);

        /// <summary>
        /// Xếp hàng trích xuất cho bài công thức có video vừa được hiển thị. Không có AI thì không làm gì.
        /// Không bao giờ ném lỗi: lỗi ở đây không được làm hỏng việc đăng bài.
        /// </summary>
        Task QueueNewPostAsync(string postId);

        /// <summary>Làm một việc trong hàng đợi. false: không có việc, hoặc AI chưa cấu hình.</summary>
        Task<bool> RunOnceAsync(CancellationToken ct = default);
    }

    public interface IAdminDashboardService
    {
        Task<OverviewResponse> GetOverviewAsync();
        Task<List<CatalogItemResponse>> ListCatalogAsync(string? kind);
        Task<CatalogItemResponse> CreateCatalogItemAsync(string adminId, CreateCatalogItemRequest request);
        Task<CatalogItemResponse> PatchCatalogItemAsync(string adminId, string id, PatchCatalogItemRequest request);
        Task DeleteCatalogItemAsync(string adminId, string id);
    }

    public interface IModerationService
    {
        Task<List<FlagResponse>> ListFlagsAsync(string? status, string? category, string? search);
        Task<Dictionary<string, long>> CountFlagsAsync();
        Task DecideAsync(string adminId, string id, ModerationDecisionRequest request);
    }

    public interface IAdminAiService
    {
        Task<TelemetryResponse> GetTelemetryAsync(string? range);
        Task<List<AiLogResponse>> ListLogsAsync(string? task, int? limit);
        Task<AiLogResponse> GetLogAsync(string id);
        Task<AiLogResponse> LabelLogAsync(string adminId, string id, LabelAiLogRequest request);
        Task<List<AiModelResponse>> ListModelsAsync();
        Task<AiModelResponse> PatchModelAsync(string adminId, string id, PatchAiModelRequest request);
        Task<AiMetricsResponse> GetMetricsAsync(string? range);
    }
}
