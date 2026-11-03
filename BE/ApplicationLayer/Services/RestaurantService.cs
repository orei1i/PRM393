using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Content;
using ApplicationLayer.Interfaces;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Interfaces;

namespace ApplicationLayer.Services
{
    /// <summary>Quán ăn: công khai chỉ thấy Approved; tác giả và admin thấy thêm quán của mình đang chờ hoặc bị từ chối.</summary>
    public class RestaurantService : IRestaurantService
    {
        private const string Gone = "Quán không còn tồn tại.";
        private const int MaxReason = 500;

        private readonly IGenericRepository<Restaurant> _restaurants;
        private readonly IGenericRepository<RestaurantReview> _reviews;
        private readonly IGenericRepository<User> _users;
        private readonly IGenericRepository<MediaAsset> _media;
        private readonly IRestaurantRepository _store;
        private readonly IAdminAuditService _audit;
        private readonly IClock _clock;

        public RestaurantService(
            IGenericRepository<Restaurant> restaurants,
            IGenericRepository<RestaurantReview> reviews,
            IGenericRepository<User> users,
            IGenericRepository<MediaAsset> media,
            IRestaurantRepository store,
            IAdminAuditService audit,
            IClock clock)
        {
            _restaurants = restaurants;
            _reviews = reviews;
            _users = users;
            _media = media;
            _store = store;
            _audit = audit;
            _clock = clock;
        }

        /* ---------------------------------------------------------------- dữ liệu ghép */

        private async Task<Dictionary<string, User>> UsersOfAsync(IEnumerable<string?> ids)
        {
            var wanted = ids.Where(ContentText.IsId).Select(i => i!).Distinct().ToList();
            return wanted.Count == 0
                ? new Dictionary<string, User>()
                : (await _users.FindAsync(u => wanted.Contains(u.Id))).ToDictionary(u => u.Id);
        }

        private async Task<Dictionary<string, List<RestaurantReview>>> ReviewsOfAsync(IEnumerable<string> restaurantIds)
        {
            var wanted = restaurantIds.Distinct().ToList();
            if (wanted.Count == 0) return new Dictionary<string, List<RestaurantReview>>();
            var rows = await _reviews.FindAsync(v => wanted.Contains(v.RestaurantId) && !v.IsDeleted);
            return rows.GroupBy(v => v.RestaurantId).ToDictionary(g => g.Key, g => g.ToList());
        }

        private static string NameOf(string id, Dictionary<string, User> users) =>
            users.TryGetValue(id, out var u) && !u.IsDeleted ? u.FullName ?? "Thành viên" : "Thành viên";

        private static PersonRef? PersonOf(string? id, Dictionary<string, User> users) =>
            string.IsNullOrEmpty(id) ? null : new PersonRef { Id = id, FullName = NameOf(id, users) };

        private static (double? Average, int Count) Stats(string id, Dictionary<string, List<RestaurantReview>> reviews) =>
            reviews.TryGetValue(id, out var rows) && rows.Count > 0 ? (Math.Round(rows.Average(v => v.Rating), 2), rows.Count) : (null, 0);

        private static double? DistanceOf(Restaurant r, double? lat, double? lng) =>
            lat is { } a && lng is { } b && r.Latitude is { } x && r.Longitude is { } y ? Math.Round(ContentText.HaversineKm(a, b, x, y), 2) : null;

        private static RestaurantResponse MapPublic(Restaurant r, Dictionary<string, User> users, Dictionary<string, List<RestaurantReview>> reviews, double? lat, double? lng)
        {
            var (average, count) = Stats(r.Id, reviews);
            return new RestaurantResponse
            {
                Id = r.Id,
                CreatedBy = r.CreatedBy,
                CreatedByName = string.IsNullOrEmpty(r.CreatedBy) ? null : NameOf(r.CreatedBy, users),
                Name = r.Name,
                Address = r.Address,
                IsVeganCertified = r.IsVeganCertified,
                Latitude = r.Latitude,
                Longitude = r.Longitude,
                DistanceKm = DistanceOf(r, lat, lng),
                AverageRating = average,
                ReviewCount = count
            };
        }

        private static void FillSuggestion(RestaurantSuggestionResponse row, Restaurant r, Dictionary<string, User> users, Dictionary<string, List<RestaurantReview>> reviews)
        {
            var (average, count) = Stats(r.Id, reviews);
            row.Id = r.Id;
            row.Name = r.Name;
            row.Address = r.Address;
            row.Latitude = r.Latitude;
            row.Longitude = r.Longitude;
            row.IsVeganCertified = r.IsVeganCertified;
            row.CreatedBy = PersonOf(r.CreatedBy, users);
            row.AverageRating = average;
            row.ReviewCount = count;
            row.Status = r.Status;
            row.RejectionReason = r.RejectionReason;
            row.CreatedAt = r.CreatedAt;
            row.ReviewedAt = r.ReviewedAt;
        }

        private static RestaurantMediaResponse MapMedia(RestaurantMedia m, Dictionary<string, User> users) => new()
        {
            Id = m.Id,
            MediaType = m.MediaType,
            MediaUrl = m.MediaUrl,
            UploadedBy = PersonOf(m.UploadedBy, users),
            CreatedAt = m.CreatedAt
        };

        private static RestaurantReviewResponse MapReview(RestaurantReview v, Dictionary<string, User> users) => new()
        {
            Id = v.Id,
            UserId = v.UserId,
            RestaurantId = v.RestaurantId,
            Rating = v.Rating,
            Comment = v.Comment,
            CreatedAt = v.CreatedAt,
            UpdatedAt = v.UpdatedAt,
            User = new PersonRef { Id = v.UserId, FullName = NameOf(v.UserId, users) }
        };

        private async Task<AdminRestaurantResponse> MapAdminAsync(Restaurant r)
        {
            var users = await UsersOfAsync(r.Media.Select(m => m.UploadedBy).Append(r.CreatedBy));
            return MapAdmin(r, users, await ReviewsOfAsync(new[] { r.Id }));
        }

        private static AdminRestaurantResponse MapAdmin(Restaurant r, Dictionary<string, User> users, Dictionary<string, List<RestaurantReview>> reviews)
        {
            var row = new AdminRestaurantResponse
            {
                ReviewedBy = r.ReviewedBy,
                Media = r.Media.OrderBy(m => m.CreatedAt).Select(m => MapMedia(m, users)).ToList()
            };
            FillSuggestion(row, r, users, reviews);
            return row;
        }

        /// <summary>Chưa duyệt thì chỉ tác giả và admin thấy; người khác nhận 404 như quán không tồn tại.</summary>
        private async Task<Restaurant> LoadVisibleAsync(string id, string? viewerId, bool isAdmin)
        {
            var restaurant = ContentText.IsId(id) ? await _restaurants.FindByIdAsync(id) : null;
            if (restaurant == null || restaurant.IsDeleted) throw new NotFoundException(Gone);
            if (restaurant.Status != RestaurantStatuses.Approved && !isAdmin && (viewerId == null || restaurant.CreatedBy != viewerId))
                throw new NotFoundException(Gone);
            return restaurant;
        }

        /* ---------------------------------------------------------------- công khai */

        public async Task<List<RestaurantResponse>> ListPublicAsync(RestaurantListQuery query)
        {
            ContentText.RequireCoordinatePair(query.Lat, query.Lng);
            var sort = string.IsNullOrWhiteSpace(query.Sort) ? "distance" : query.Sort.Trim().ToLowerInvariant();
            if (sort is not ("distance" or "rating")) throw ContentText.Invalid("Kiểu sắp xếp không hợp lệ.");
            if (query.RadiusKm is <= 0) throw ContentText.Invalid("Bán kính phải lớn hơn 0.");
            var limit = Math.Clamp(query.Limit ?? 100, 1, 100);

            var rows = (await _restaurants.FindAsync(r => !r.IsDeleted && r.Status == RestaurantStatuses.Approved)).ToList();
            if (query.CertifiedOnly) rows = rows.Where(r => r.IsVeganCertified).ToList();

            var reviews = await ReviewsOfAsync(rows.Select(r => r.Id));
            var tokens = ContentText.Tokens(query.Q);
            if (tokens.Count > 0)
            {
                rows = rows.Where(r =>
                {
                    var comments = reviews.TryGetValue(r.Id, out var list) ? string.Join(' ', list.Select(v => v.Comment)) : string.Empty;
                    return ContentText.Matches(tokens, r.Name, ContentText.FoldAddress(r.Address), comments);
                }).ToList();
            }

            var users = await UsersOfAsync(rows.Select(r => r.CreatedBy));
            var mapped = rows.Select(r => MapPublic(r, users, reviews, query.Lat, query.Lng)).ToList();
            if (query.Lat.HasValue && query.RadiusKm is { } radius)
                mapped = mapped.Where(r => r.DistanceKm is { } d && d <= radius).ToList();

            return Sorted(mapped, sort == "distance" && query.Lat.HasValue).Take(limit).ToList();
        }

        /// <summary>Quán không có toạ độ luôn xếp cuối khi sắp theo khoảng cách.</summary>
        private static IEnumerable<RestaurantResponse> Sorted(IEnumerable<RestaurantResponse> rows, bool byDistance) =>
            byDistance
                ? rows.OrderBy(r => r.DistanceKm ?? double.MaxValue).ThenByDescending(r => r.AverageRating ?? 0).ThenBy(r => r.Name, StringComparer.Ordinal)
                : rows.OrderByDescending(r => r.AverageRating ?? 0).ThenByDescending(r => r.ReviewCount).ThenBy(r => r.Name, StringComparer.Ordinal);

        public async Task<List<RestaurantResponse>> SuggestedAsync(string? food, double? lat, double? lng, int? limit)
        {
            ContentText.RequireCoordinatePair(lat, lng);
            var tokens = ContentText.Tokens(food);
            if (tokens.Count == 0) return new List<RestaurantResponse>();

            var rows = (await _restaurants.FindAsync(r => !r.IsDeleted && r.Status == RestaurantStatuses.Approved)).ToList();
            var reviews = await ReviewsOfAsync(rows.Select(r => r.Id));
            rows = rows.Where(r =>
            {
                var comments = reviews.TryGetValue(r.Id, out var list) ? string.Join(' ', list.Select(v => v.Comment)) : string.Empty;
                return ContentText.Matches(tokens, r.Name, comments);
            }).ToList();

            var users = await UsersOfAsync(rows.Select(r => r.CreatedBy));
            return Sorted(rows.Select(r => MapPublic(r, users, reviews, lat, lng)), lat.HasValue)
                .Take(Math.Clamp(limit ?? 3, 1, 20))
                .ToList();
        }

        public async Task<RestaurantResponse> GetAsync(string id, double? lat, double? lng, string? viewerId, bool isAdmin)
        {
            ContentText.RequireCoordinatePair(lat, lng);
            var r = await LoadVisibleAsync(id, viewerId, isAdmin);
            return MapPublic(r, await UsersOfAsync(new[] { r.CreatedBy }), await ReviewsOfAsync(new[] { r.Id }), lat, lng);
        }

        public async Task<List<RestaurantMediaResponse>> ListMediaAsync(string id, string? viewerId, bool isAdmin)
        {
            var r = await LoadVisibleAsync(id, viewerId, isAdmin);
            var users = await UsersOfAsync(r.Media.Select(m => m.UploadedBy));
            return r.Media.OrderBy(m => m.CreatedAt).Select(m => MapMedia(m, users)).ToList();
        }

        public async Task<List<RestaurantReviewResponse>> ListReviewsAsync(string id, string? viewerId, bool isAdmin)
        {
            await LoadVisibleAsync(id, viewerId, isAdmin);
            return await ReviewRowsAsync(id);
        }

        private async Task<List<RestaurantReviewResponse>> ReviewRowsAsync(string id)
        {
            var rows = (await _reviews.FindAsync(v => v.RestaurantId == id && !v.IsDeleted)).ToList();
            var users = await UsersOfAsync(rows.Select(v => v.UserId));
            return rows.OrderByDescending(v => v.UpdatedAt ?? v.CreatedAt).Select(v => MapReview(v, users)).ToList();
        }

        public async Task<RestaurantReviewResponse> UpsertReviewAsync(string userId, string id, UpsertRestaurantReviewRequest request)
        {
            var restaurant = await LoadVisibleAsync(id, userId, isAdmin: false);
            if (restaurant.Status != RestaurantStatuses.Approved)
                throw new ConflictException("Quán đang chờ duyệt nên chưa nhận đánh giá.", "not_public");
            if (request.Rating is not (>= 1 and <= 5)) throw ContentText.Invalid("Chọn số sao từ 1 đến 5.");
            var comment = request.Comment?.Trim() ?? string.Empty;
            if (comment.Length < 10 || comment.Length > 500) throw ContentText.Invalid("Nhận xét cần từ 10 đến 500 ký tự.");

            var review = await _store.UpsertReviewAsync(id, userId, request.Rating.Value, comment, _clock.UtcNow);
            return MapReview(review, await UsersOfAsync(new[] { userId }));
        }

        public async Task<RestaurantSuggestionResponse> SuggestAsync(string userId, CreateRestaurantRequest request)
        {
            var name = request.Name?.Trim() ?? string.Empty;
            var address = request.Address?.Trim() ?? string.Empty;
            if (name.Length < 3 || name.Length > 120) throw ContentText.Invalid("Tên quán từ 3 đến 120 ký tự.");
            if (address.Length < 10 || address.Length > 255) throw ContentText.Invalid("Địa chỉ từ 10 đến 255 ký tự.");
            ContentText.RequireCoordinatePair(request.Latitude, request.Longitude);

            var now = _clock.UtcNow;
            var media = await ValidatedMediaAsync(request.Media, userId, now);
            var created = new Restaurant
            {
                Id = ContentText.NewId(),
                Name = name,
                Address = address,
                Latitude = request.Latitude,
                Longitude = request.Longitude,
                IsVeganCertified = false,
                Status = RestaurantStatuses.Pending,
                CreatedBy = userId,
                DedupeKey = ContentText.FoldedKey(name, address),
                Media = media,
                CreatedAt = now
            };
            if (!await _store.TryInsertAsync(created)) throw new ConflictException("Quán này đã có trên VeganLife.", "duplicate");

            var row = new RestaurantSuggestionResponse();
            FillSuggestion(row, created, await UsersOfAsync(new[] { userId }), new Dictionary<string, List<RestaurantReview>>());
            return row;
        }

        /// <summary>Chỉ nhận tệp chính người gợi ý đã tải lên, đúng loại đã khai: không gắn được URL lạ hay tệp của người khác.</summary>
        private async Task<List<RestaurantMedia>> ValidatedMediaAsync(List<RestaurantMediaInput>? input, string userId, DateTime now)
        {
            var items = input ?? new List<RestaurantMediaInput>();
            if (items.Any(m => m.MediaType is not ("Image" or "Video"))) throw ContentText.Invalid("Loại tệp phải là Image hoặc Video.");
            if (items.Count(m => m.MediaType == "Image") > 5 || items.Count(m => m.MediaType == "Video") > 1)
                throw ContentText.Invalid("Tối đa 5 ảnh và 1 video cho mỗi gợi ý.");
            if (items.Any(m => string.IsNullOrWhiteSpace(m.MediaUrl))) throw ContentText.Invalid("Ảnh hoặc video chưa tải lên xong.");

            var result = new List<RestaurantMedia>();
            foreach (var item in items)
            {
                var url = item.MediaUrl!.Trim();
                var type = item.MediaType!;
                var asset = await _media.FirstOrDefaultAsync(a => a.Url == url && a.OwnerId == userId && a.MediaType == type && !a.IsDeleted);
                if (asset == null) throw ContentText.Invalid("Ảnh hoặc video không hợp lệ, hãy tải lên lại.");
                result.Add(new RestaurantMedia { Id = ContentText.NewId(), MediaType = type, MediaUrl = url, UploadedBy = userId, CreatedAt = now });
            }
            return result;
        }

        public async Task<List<RestaurantSuggestionResponse>> ListMySuggestionsAsync(string userId)
        {
            var rows = (await _restaurants.FindAsync(r => r.CreatedBy == userId && !r.IsDeleted)).OrderByDescending(r => r.CreatedAt).ToList();
            var users = await UsersOfAsync(new[] { userId });
            var reviews = await ReviewsOfAsync(rows.Select(r => r.Id));
            return rows.Select(r =>
            {
                var row = new RestaurantSuggestionResponse();
                FillSuggestion(row, r, users, reviews);
                return row;
            }).ToList();
        }

        /* ---------------------------------------------------------------- admin */

        public async Task<List<AdminRestaurantResponse>> AdminListAsync(string? status, string? certified, string? source, string? search)
        {
            if (!string.IsNullOrWhiteSpace(status) && status is not (RestaurantStatuses.Pending or RestaurantStatuses.Approved or RestaurantStatuses.Rejected))
                throw ContentText.Invalid("Trạng thái quán không hợp lệ.");
            if (!string.IsNullOrWhiteSpace(certified) && certified is not ("certified" or "uncertified")) throw ContentText.Invalid("Bộ lọc chứng nhận không hợp lệ.");
            if (!string.IsNullOrWhiteSpace(source) && source is not ("user" or "admin")) throw ContentText.Invalid("Bộ lọc nguồn không hợp lệ.");

            IEnumerable<Restaurant> rows = await _restaurants.FindAsync(r => !r.IsDeleted);
            if (!string.IsNullOrWhiteSpace(status)) rows = rows.Where(r => r.Status == status);
            if (certified == "certified") rows = rows.Where(r => r.IsVeganCertified);
            if (certified == "uncertified") rows = rows.Where(r => !r.IsVeganCertified);
            if (source == "user") rows = rows.Where(r => !string.IsNullOrEmpty(r.CreatedBy));
            if (source == "admin") rows = rows.Where(r => string.IsNullOrEmpty(r.CreatedBy));

            var list = rows.OrderByDescending(r => r.CreatedAt).ToList();
            var users = await UsersOfAsync(list.SelectMany(r => r.Media.Select(m => m.UploadedBy).Append(r.CreatedBy)));
            var tokens = ContentText.Tokens(search);
            if (tokens.Count > 0)
            {
                list = list.Where(r => ContentText.Matches(tokens, r.Name, ContentText.FoldAddress(r.Address),
                    string.IsNullOrEmpty(r.CreatedBy) ? "Ban quản trị" : NameOf(r.CreatedBy, users))).ToList();
            }
            var reviews = await ReviewsOfAsync(list.Select(r => r.Id));
            return list.Select(r => MapAdmin(r, users, reviews)).ToList();
        }

        public async Task<AdminRestaurantResponse> AdminReviewAsync(string adminId, string id, ReviewRestaurantRequest request)
        {
            var decision = request.Decision?.Trim();
            if (decision is not ("Approve" or "Reject")) throw ContentText.Invalid("Quyết định phải là Approve hoặc Reject.");

            var current = ContentText.IsId(id) ? await _restaurants.FindByIdAsync(id) : null;
            if (current == null || current.IsDeleted) throw new NotFoundException(Gone);

            string? reason = null;
            if (decision == "Reject")
            {
                reason = request.Reason?.Trim();
                if (string.IsNullOrEmpty(reason)) throw new BadRequestException("Cần ghi lý do từ chối.", "reason_required");
                if (reason.Length > MaxReason) throw new BadRequestException($"Lý do tối đa {MaxReason} ký tự.", "reason_too_long");
            }

            var reviewer = await _audit.NameOfAsync(adminId);
            var status = decision == "Approve" ? RestaurantStatuses.Approved : RestaurantStatuses.Rejected;
            // Quán bị từ chối được gửi lại, nên chỉ quán còn hiệu lực mới giữ khoá chống trùng.
            var dedupeKey = decision == "Approve" ? ContentText.FoldedKey(current.Name, current.Address) : null;
            var (row, duplicate) = await _store.DecideAsync(id, status, reason, dedupeKey, reviewer, _clock.UtcNow);
            if (duplicate) throw new ConflictException("Đã có quán khác trùng tên và địa chỉ.", "duplicate");
            if (row == null) throw new NotFoundException(Gone);

            await _audit.LogAsync(reviewer, decision == "Approve" ? "duyệt quán" : "từ chối quán", row.Name, reason);
            return await MapAdminAsync(row);
        }

        public async Task<AdminRestaurantResponse> AdminSetCertifiedAsync(string adminId, string id, SetRestaurantCertifiedRequest request)
        {
            if (request.IsVeganCertified is not { } value) throw ContentText.Invalid("Thiếu isVeganCertified.");
            var current = ContentText.IsId(id) ? await _restaurants.FindByIdAsync(id) : null;
            if (current == null || current.IsDeleted) throw new NotFoundException(Gone);

            var row = await _store.SetCertifiedIfApprovedAsync(id, value, _clock.UtcNow)
                      ?? throw new ConflictException("Chỉ quán đã duyệt mới được chứng nhận.", "not_approved");
            await _audit.LogAsync(await _audit.NameOfAsync(adminId), value ? "cấp chứng nhận thuần chay" : "bỏ chứng nhận thuần chay", row.Name);
            return await MapAdminAsync(row);
        }

        public async Task AdminDeleteAsync(string adminId, string id)
        {
            var current = ContentText.IsId(id) ? await _restaurants.FindByIdAsync(id) : null;
            if (current == null || !await _store.SoftDeleteAsync(id, _clock.UtcNow)) throw new NotFoundException(Gone);
            await _audit.LogAsync(await _audit.NameOfAsync(adminId), "xoá quán", current.Name);
        }

        public async Task<List<RestaurantReviewResponse>> AdminListReviewsAsync(string id)
        {
            var current = ContentText.IsId(id) ? await _restaurants.FindByIdAsync(id) : null;
            if (current == null || current.IsDeleted) throw new NotFoundException(Gone);
            return await ReviewRowsAsync(id);
        }

        public async Task AdminDeleteReviewAsync(string adminId, string reviewId)
        {
            var review = ContentText.IsId(reviewId) ? await _reviews.FindByIdAsync(reviewId) : null;
            if (review == null || !await _store.SoftDeleteReviewAsync(reviewId, _clock.UtcNow))
                throw new NotFoundException("Đánh giá không còn tồn tại.");
            await _audit.LogAsync(await _audit.NameOfAsync(adminId), "xoá đánh giá quán", review.RestaurantId);
        }
    }
}
