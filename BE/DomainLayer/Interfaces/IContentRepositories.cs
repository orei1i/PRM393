using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using DomainLayer.Entities;

namespace DomainLayer.Interfaces
{
    public sealed record ChefStats(double Rating, int ReviewCount, int ConsultCount);

    /// <summary>Các lần ghi phải nguyên tử (có điều kiện); phần đọc thường dùng IGenericRepository.</summary>
    public interface IChefRepository
    {
        /// <summary>false: người này đã có hồ sơ đang chờ (chỉ mục unique chặn, kể cả khi gửi đồng thời).</summary>
        Task<bool> TryInsertApplicationAsync(ChefApplication application);

        /// <summary>Chuyển pending sang trạng thái mới; null nếu hồ sơ không còn ở pending.</summary>
        Task<ChefApplication?> TryDecideApplicationAsync(string id, string status, string? note, string reviewer, DateTime at);

        Task RevertToPendingAsync(string id);

        /// <summary>Tạo hồ sơ nếu chưa có; đã có thì giữ nguyên giá và mô tả của chuyên gia.</summary>
        Task CreateProfileIfMissingAsync(ChefProfile profile);

        Task<ChefProfile> UpsertProfileAsync(ChefProfile values, DateTime at);

        /// <summary>Không bao giờ hạ quyền Admin.</summary>
        Task GrantChefRoleAsync(string userId, DateTime at);

        /// <summary>Theo id user chuyên gia: điểm trung bình từ phản hồi ngày kế hoạch và số booking đã hoàn tất.</summary>
        Task<Dictionary<string, ChefStats>> GetStatsAsync(IReadOnlyCollection<string> chefUserIds);
    }

    public interface IRestaurantRepository
    {
        /// <summary>false: trùng tên và địa chỉ với quán chưa bị từ chối.</summary>
        Task<bool> TryInsertAsync(Restaurant restaurant);

        /// <summary>Duplicate = true khi duyệt lại quán bị từ chối mà đã có quán khác trùng.</summary>
        Task<(Restaurant? Row, bool Duplicate)> DecideAsync(string id, string status, string? reason, string? dedupeKey, string reviewer, DateTime at);

        /// <summary>null: không tồn tại hoặc không ở trạng thái Approved.</summary>
        Task<Restaurant?> SetCertifiedIfApprovedAsync(string id, bool value, DateTime at);

        /// <summary>Xoá mềm quán và các đánh giá. false: không tồn tại.</summary>
        Task<bool> SoftDeleteAsync(string id, DateTime at);

        Task<RestaurantReview> UpsertReviewAsync(string restaurantId, string userId, int rating, string comment, DateTime at);

        Task<bool> SoftDeleteReviewAsync(string id, DateTime at);
    }

    public interface IAdRepository
    {
        /// <summary>Chỉ tính khi chiến dịch còn chạy; số đã tiêu không vượt ngân sách. false: không tính.</summary>
        Task<bool> RecordImpressionAsync(string id, long cost, DateTime now);
        Task<bool> RecordClickAsync(string id, DateTime now);

        /// <summary>null: không tồn tại hoặc ngân sách mới thấp hơn số đã tiêu.</summary>
        Task<AdCampaign?> UpdateFieldsAsync(AdCampaign values, DateTime at);

        Task<AdCampaign?> SetPausedAsync(string id, bool paused, DateTime at);
    }

    public interface IVideoExtractionRepository
    {
        /// <summary>Tạo mới hoặc chuyển failed sang queued. Trả dòng hiện tại, kể cả khi đang xử lý.</summary>
        Task<VideoExtraction> QueueAsync(string postId, DateTime at);

        /// <summary>Nhận một việc: queued, hoặc đang xử lý nhưng máy chủ đã chết từ trước staleBefore.</summary>
        Task<VideoExtraction?> ClaimNextAsync(DateTime now, DateTime staleBefore);

        Task CompleteAsync(VideoExtraction result, DateTime at);
        Task FailAsync(string id, string reason, DateTime at);
    }

    public interface IAdminContentRepository
    {
        /// <summary>false: trùng mã trong cùng nhóm.</summary>
        Task<bool> TryInsertCatalogItemAsync(CatalogItem item);

        /// <summary>Thêm mục đang được dùng trong dữ liệu thật; không hồi sinh mục đã xoá, không đổi nhãn đã sửa.</summary>
        Task EnsureCatalogItemAsync(string kind, string code, string label, DateTime at);

        Task<ModerationFlag?> TryDecideFlagAsync(string id, string action, string note, string decidedBy, DateTime at);

        Task EnsureAiModelAsync(AiModelConfig defaults, DateTime at);

        /// <summary>Mỗi dòng log một nhãn: gán lại thì ghi đè.</summary>
        Task<AiLogLabel> UpsertLogLabelAsync(string logId, string verdict, string? note, string by, DateTime at);
    }

    /// <summary>Đọc byte video từ nơi chính máy chủ đã lưu (thư mục uploads hoặc Cloudinary).</summary>
    public interface IVideoContentReader
    {
        Task<(byte[] Bytes, string MimeType)> ReadAsync(string url, long maxBytes, CancellationToken ct = default);
    }

    public sealed record GeoPlaceResult(string Name, string Address, string? City, double Latitude, double Longitude);

    /// <summary>Định vị địa chỉ. Khi chưa cấu hình, không gọi ra ngoài và không tự tạo kết quả.</summary>
    public interface IGeocodingClient
    {
        bool IsConfigured { get; }
        Task<List<GeoPlaceResult>> SearchAsync(string query, CancellationToken ct = default);
        Task<GeoPlaceResult?> ReverseAsync(double latitude, double longitude, CancellationToken ct = default);
    }
}
