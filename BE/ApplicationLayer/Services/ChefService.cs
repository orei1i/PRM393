using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Content;
using ApplicationLayer.Interfaces;
using DomainLayer.Constants;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Helpers;
using DomainLayer.Interfaces;
using Microsoft.Extensions.Caching.Memory;
using static DomainLayer.Enums.GeneralEnum;

namespace ApplicationLayer.Services
{
    /// <summary>Danh bạ và hồ sơ chuyên gia, đơn xin làm chuyên gia.</summary>
    public class ChefService : IChefService
    {
        private const long MinDayPrice = 30_000;
        private const long MaxDayPrice = 5_000_000;
        private const int MinBio = 50;
        private const int MaxBio = 1000;
        private const string NoProfile = "Chưa có hồ sơ chuyên gia.";
        private const string ChefGone = "Chuyên gia không còn hoạt động.";

        private readonly IGenericRepository<ChefProfile> _profiles;
        private readonly IGenericRepository<ChefApplication> _applications;
        private readonly IGenericRepository<User> _users;
        private readonly IGenericRepository<Post> _posts;
        private readonly IChefRepository _store;
        private readonly IAdminAuditService _audit;
        private readonly IMemoryCache _cache;
        private readonly IClock _clock;

        public ChefService(
            IGenericRepository<ChefProfile> profiles,
            IGenericRepository<ChefApplication> applications,
            IGenericRepository<User> users,
            IGenericRepository<Post> posts,
            IChefRepository store,
            IAdminAuditService audit,
            IMemoryCache cache,
            IClock clock)
        {
            _profiles = profiles;
            _applications = applications;
            _users = users;
            _posts = posts;
            _store = store;
            _audit = audit;
            _cache = cache;
            _clock = clock;
        }

        private static bool IsActiveChef(User? user) =>
            user is { IsDeleted: false, Role: "Chef" } && user.Status is not (UserStatusEnum.Locked or UserStatusEnum.Banned);

        private static string HeadlineOf(ChefProfile p) =>
            p.YearsExperience > 0 ? $"{p.Specialty} · {p.YearsExperience} năm kinh nghiệm" : p.Specialty;

        private static ChefResponse Map(ChefProfile p, User user, ChefStats? stats, bool detail) => new()
        {
            Id = p.Id,
            UserId = p.UserId,
            FullName = user.FullName ?? string.Empty,
            Headline = HeadlineOf(p),
            Specialty = p.Specialty,
            Rating = stats?.Rating ?? 0,
            ReviewCount = stats?.ReviewCount ?? 0,
            YearsExperience = p.YearsExperience,
            City = p.City,
            ConsultCount = stats?.ConsultCount ?? 0,
            PricePerDay = p.PricePerDay,
            FeedbackPricePerDay = p.FeedbackPricePerDay,
            MinPlanDays = p.MinPlanDays,
            MaxPlanDays = p.MaxPlanDays,
            AcceptingBookings = p.AcceptingBookings,
            Bio = detail ? p.Bio : null,
            Certificates = detail ? p.Certificates : null
        };

        private static ChefProfileResponse MapProfile(ChefProfile p) => new()
        {
            Id = p.Id,
            UserId = p.UserId,
            Specialty = p.Specialty,
            Bio = p.Bio,
            PricePerDay = p.PricePerDay,
            FeedbackPricePerDay = p.FeedbackPricePerDay,
            MinPlanDays = p.MinPlanDays,
            MaxPlanDays = p.MaxPlanDays,
            AcceptingBookings = p.AcceptingBookings
        };

        /* ---------------------------------------------------------------- danh bạ */

        public async Task<List<ChefResponse>> ListAsync(string? q, string? specialty)
        {
            var profiles = (await _profiles.FindAsync(p => !p.IsDeleted)).ToList();
            var userIds = profiles.Select(p => p.UserId).ToList();
            var users = (await _users.FindAsync(u => userIds.Contains(u.Id))).ToDictionary(u => u.Id);
            var active = profiles.Where(p => users.TryGetValue(p.UserId, out var u) && IsActiveChef(u)).ToList();

            var query = ContentText.Tokens(q);
            if (query.Count > 0)
                active = active.Where(p => ContentText.Matches(query, users[p.UserId].FullName, p.Specialty, p.City, HeadlineOf(p))).ToList();
            var wantedSpecialty = ContentText.Tokens(specialty);
            if (wantedSpecialty.Count > 0)
                active = active.Where(p => ContentText.Matches(wantedSpecialty, p.Specialty)).ToList();

            var stats = await _store.GetStatsAsync(active.Select(p => p.UserId).ToList());
            return active
                .Select(p => Map(p, users[p.UserId], stats.GetValueOrDefault(p.UserId), detail: false))
                .OrderByDescending(c => c.Rating)
                .ThenByDescending(c => c.ConsultCount)
                .ThenBy(c => c.FullName, StringComparer.Ordinal)
                .ToList();
        }

        public async Task<ChefResponse> GetAsync(string id)
        {
            if (!ContentText.IsId(id)) throw new NotFoundException(ChefGone);
            // booking.chef.id là id user nên app có thể mở hồ sơ bằng cả hai loại id.
            var profile = await _profiles.FirstOrDefaultAsync(p => p.Id == id && !p.IsDeleted)
                          ?? await _profiles.FirstOrDefaultAsync(p => p.UserId == id && !p.IsDeleted);
            if (profile == null) throw new NotFoundException(ChefGone);
            var user = await _users.FindByIdAsync(profile.UserId);
            if (!IsActiveChef(user)) throw new NotFoundException(ChefGone);
            var stats = await _store.GetStatsAsync(new[] { profile.UserId });
            return Map(profile, user!, stats.GetValueOrDefault(profile.UserId), detail: true);
        }

        public async Task<ChefProfileResponse> GetMyProfileAsync(string userId)
        {
            var profile = await _profiles.FirstOrDefaultAsync(p => p.UserId == userId && !p.IsDeleted);
            return profile == null ? throw new NotFoundException(NoProfile) : MapProfile(profile);
        }

        public async Task<ChefProfileResponse> SaveMyProfileAsync(string userId, SaveChefProfileRequest request)
        {
            var specialty = request.Specialty?.Trim() ?? string.Empty;
            if (specialty.Length == 0 || specialty.Length > 120) throw ContentText.Invalid("Chọn chuyên môn chính.");
            var bio = request.Bio?.Trim() ?? string.Empty;
            if (bio.Length < MinBio || bio.Length > MaxBio) throw ContentText.Invalid($"Giới thiệu từ {MinBio} đến {MaxBio} ký tự.");
            if (request.PricePerDay is not { } price || price < MinDayPrice || price > MaxDayPrice)
                throw ContentText.Invalid($"Giá mỗi ngày từ {MoneyMath.Vnd(MinDayPrice)} đến {MoneyMath.Vnd(MaxDayPrice)}.");
            if (request.FeedbackPricePerDay is not { } feedback || feedback < MinDayPrice || feedback > MaxDayPrice)
                throw ContentText.Invalid($"Giá có phản hồi từ {MoneyMath.Vnd(MinDayPrice)} đến {MoneyMath.Vnd(MaxDayPrice)}.");
            if (feedback < price) throw ContentText.Invalid("Giá có phản hồi không thấp hơn giá mỗi ngày.");
            if (request.MinPlanDays is not { } min || request.MaxPlanDays is not { } max) throw ContentText.Invalid("Nhập số ngày tối thiểu và tối đa.");
            if (min < CommerceRules.MinPlanDays || max > CommerceRules.MaxPlanDays)
                throw ContentText.Invalid($"Số ngày từ {CommerceRules.MinPlanDays} đến {CommerceRules.MaxPlanDays}.");
            if (min > max) throw ContentText.Invalid("Số ngày tối thiểu không được lớn hơn tối đa.");
            if (request.AcceptingBookings is not { } accepting) throw ContentText.Invalid("Thiếu trạng thái nhận yêu cầu.");

            var saved = await _store.UpsertProfileAsync(new ChefProfile
            {
                UserId = userId,
                Specialty = specialty,
                Bio = bio,
                PricePerDay = price,
                FeedbackPricePerDay = feedback,
                MinPlanDays = min,
                MaxPlanDays = max,
                AcceptingBookings = accepting
            }, _clock.UtcNow);
            return MapProfile(saved);
        }

        /* ---------------------------------------------------------------- đơn xin làm chuyên gia */

        public async Task<ChefApplicationResponse> SubmitApplicationAsync(string userId, SubmitChefApplicationRequest request)
        {
            var specialties = (request.Specialties ?? new List<string>())
                .Select(s => s?.Trim() ?? string.Empty).Where(s => s.Length > 0).Distinct().ToList();
            if (specialties.Count == 0 || specialties.Count > 10 || specialties.Any(s => s.Length > 120)) throw ContentText.Invalid("Chọn từ 1 đến 10 chuyên môn.");
            if (request.YearsExperience is not { } years || years < 0 || years > 60) throw ContentText.Invalid("Số năm kinh nghiệm không hợp lệ.");
            var city = request.City?.Trim() ?? string.Empty;
            if (city.Length == 0 || city.Length > 100) throw ContentText.Invalid("Nhập thành phố.");
            var bio = request.Bio?.Trim() ?? string.Empty;
            if (bio.Length < MinBio || bio.Length > MaxBio) throw ContentText.Invalid($"Giới thiệu từ {MinBio} đến {MaxBio} ký tự.");
            var certificates = (request.Certificates ?? new List<string>())
                .Select(c => c?.Trim() ?? string.Empty).Where(c => c.Length > 0).Distinct().ToList();
            if (certificates.Count == 0 || certificates.Count > 10 || certificates.Any(c => c.Length > 200)) throw ContentText.Invalid("Cần từ 1 đến 10 chứng chỉ.");

            // Xét theo vai trò trong DB, không theo token: token có thể đã cũ sau khi được duyệt.
            var user = await _users.FindByIdAsync(userId);
            if (user == null || user.IsDeleted) throw new UnauthorizedException("Phiên đăng nhập không hợp lệ.");
            if (user.Role == "Admin") throw new ForbiddenException("Tài khoản quản trị không nộp hồ sơ chuyên gia.", "not_member");
            if (user.Role == "Chef") throw new ConflictException("Bạn đã là chuyên gia.", "already_chef");

            var now = _clock.UtcNow;
            var application = new ChefApplication
            {
                Id = ContentText.NewId(),
                UserId = userId,
                Specialties = specialties,
                YearsExperience = years,
                City = city,
                Bio = bio,
                Certificates = certificates.Select(c => new ChefCertificate { Name = c }).ToList(),
                Status = ChefApplicationStatuses.Pending,
                CreatedAt = now
            };
            if (!await _store.TryInsertApplicationAsync(application))
                throw new ConflictException("Bạn đã có hồ sơ đang chờ duyệt.", "already_pending");
            return await MapApplicationAsync(application, user);
        }

        public async Task<ChefApplicationStatusResponse> GetMyApplicationAsync(string userId)
        {
            var mine = await _applications.FindPagedAsync(a => a.UserId == userId && !a.IsDeleted, 1, 1, sortDesc: a => a.CreatedAt);
            var latest = mine.FirstOrDefault();
            return latest == null
                ? new ChefApplicationStatusResponse()
                : new ChefApplicationStatusResponse
                {
                    Status = latest.Status,
                    RejectReason = latest.Status == ChefApplicationStatuses.Rejected ? latest.ReviewNote : null
                };
        }

        private async Task<ChefApplicationResponse> MapApplicationAsync(ChefApplication a, User? user)
        {
            user ??= await _users.FindByIdAsync(a.UserId);
            var live = user is { IsDeleted: false };
            var userId = a.UserId;
            return new ChefApplicationResponse
            {
                Id = a.Id,
                UserId = a.UserId,
                FullName = live ? user!.FullName ?? string.Empty : "Thành viên",
                Email = live ? user!.Email ?? string.Empty : string.Empty,
                City = a.City,
                Specialties = a.Specialties,
                YearsExperience = a.YearsExperience,
                Bio = a.Bio,
                Certificates = a.Certificates.Select(c => new ChefCertificateResponse { Name = c.Name, FileUrl = c.FileUrl }).ToList(),
                MemberSince = user?.CreatedAt,
                PostCount = await _posts.CountAsync(p => p.UserId == userId && !p.IsDeleted),
                SubmittedAt = a.CreatedAt,
                Status = a.Status,
                ReviewNote = a.ReviewNote,
                ReviewedBy = a.ReviewedBy,
                ReviewedAt = a.ReviewedAt
            };
        }

        public async Task<List<ChefApplicationResponse>> ListApplicationsAsync(string? status)
        {
            var wanted = status?.Trim().ToLowerInvariant();
            if (!string.IsNullOrEmpty(wanted)
                && wanted is not (ChefApplicationStatuses.Pending or ChefApplicationStatuses.Approved or ChefApplicationStatuses.Rejected))
                throw ContentText.Invalid("Trạng thái hồ sơ không hợp lệ.");

            var rows = string.IsNullOrEmpty(wanted)
                ? await _applications.FindAsync(a => !a.IsDeleted)
                : await _applications.FindAsync(a => !a.IsDeleted && a.Status == wanted);
            var result = new List<ChefApplicationResponse>();
            foreach (var row in rows.OrderByDescending(a => a.CreatedAt)) result.Add(await MapApplicationAsync(row, null));
            return result;
        }

        public async Task<Dictionary<string, long>> CountApplicationsAsync() => new()
        {
            [ChefApplicationStatuses.Pending] = await _applications.CountAsync(a => !a.IsDeleted && a.Status == ChefApplicationStatuses.Pending),
            [ChefApplicationStatuses.Approved] = await _applications.CountAsync(a => !a.IsDeleted && a.Status == ChefApplicationStatuses.Approved),
            [ChefApplicationStatuses.Rejected] = await _applications.CountAsync(a => !a.IsDeleted && a.Status == ChefApplicationStatuses.Rejected)
        };

        public async Task<ChefApplicationResponse> ReviewApplicationAsync(string adminId, string id, ReviewChefApplicationRequest request)
        {
            var decision = request.Decision?.Trim();
            if (decision is not (ChefApplicationStatuses.Approved or ChefApplicationStatuses.Rejected))
                throw ContentText.Invalid("Quyết định phải là approved hoặc rejected.");
            var note = request.Note?.Trim();
            if (string.IsNullOrEmpty(note)) note = null;
            if (decision == ChefApplicationStatuses.Rejected && note == null) throw new BadRequestException("Cần ghi lý do từ chối.", "note_required");
            if (note is { Length: > 1000 }) throw ContentText.Invalid("Ghi chú tối đa 1000 ký tự.");

            var current = ContentText.IsId(id) ? await _applications.FindByIdAsync(id) : null;
            if (current == null || current.IsDeleted) throw new NotFoundException("Hồ sơ không còn tồn tại.");
            if (current.Status != ChefApplicationStatuses.Pending)
                throw new ConflictException("Hồ sơ đã được người khác xử lý.", "already_reviewed");

            var user = await _users.FindByIdAsync(current.UserId);
            if (decision == ChefApplicationStatuses.Approved
                && (user == null || user.IsDeleted || user.Status is UserStatusEnum.Locked or UserStatusEnum.Banned))
                throw new ConflictException("Người nộp hồ sơ không còn hoạt động.", "applicant_inactive");

            var reviewer = await _audit.NameOfAsync(adminId);
            var now = _clock.UtcNow;
            var decided = await _store.TryDecideApplicationAsync(id, decision, note, reviewer, now)
                          ?? throw new ConflictException("Hồ sơ đã được người khác xử lý.", "already_reviewed");

            if (decision == ChefApplicationStatuses.Approved)
            {
                try
                {
                    await _store.CreateProfileIfMissingAsync(new ChefProfile
                    {
                        Id = ContentText.NewId(),
                        UserId = decided.UserId,
                        Specialty = decided.Specialties.FirstOrDefault() ?? string.Empty,
                        Bio = decided.Bio,
                        YearsExperience = decided.YearsExperience,
                        City = decided.City,
                        Certificates = decided.Certificates.Select(c => c.Name).ToList(),
                        CreatedAt = now
                    });
                    await _store.GrantChefRoleAsync(decided.UserId, now);
                    // Middleware so vai trò trong token với bản cache: bỏ cache để token Chef mới dùng được ngay.
                    _cache.Remove(UserCacheKeys.UserStatus(decided.UserId));
                }
                catch (Exception)
                {
                    // Không để hồ sơ "đã duyệt" mà người đó chưa thành chuyên gia: mở lại để duyệt lần nữa.
                    await _store.RevertToPendingAsync(id);
                    throw;
                }
            }

            await _audit.LogAsync(reviewer, decision == ChefApplicationStatuses.Approved ? "duyệt chuyên gia" : "từ chối hồ sơ chuyên gia", user?.FullName ?? decided.UserId, note);
            return await MapApplicationAsync(decided, await _users.FindByIdAsync(decided.UserId));
        }
    }
}
