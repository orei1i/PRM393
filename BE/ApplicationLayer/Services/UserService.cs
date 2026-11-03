using ApplicationLayer.DTOs.Users;
using ApplicationLayer.Interfaces;
using DomainLayer.Constants;
using DomainLayer.Entities;
using DomainLayer.Enums;
using DomainLayer.Exceptions;
using DomainLayer.Interfaces;
using Microsoft.Extensions.Caching.Memory;

namespace ApplicationLayer.Services
{
    /// <summary>
    /// Xử lý business logic liên quan đến User.
    /// </summary>
    public class UserService : IUserService
    {
        private readonly IGenericRepository<User> _userRepository;
        private readonly IGenericRepository<Post> _postRepository;
        private readonly IMemoryCache? _cache;
        private readonly IGenericRepository<PostSave>? _saveRepository;
        private readonly IGenericRepository<ChefApplication>? _chefApplications;

        public UserService(
            IGenericRepository<User> userRepository,
            IGenericRepository<Post> postRepository,
            IMemoryCache? cache = null,
            IGenericRepository<PostSave>? saveRepository = null,
            IGenericRepository<ChefApplication>? chefApplications = null)
        {
            _userRepository = userRepository;
            _postRepository = postRepository;
            _cache = cache;
            _saveRepository = saveRepository;
            _chefApplications = chefApplications;
        }

        public async Task<IEnumerable<UserResponse>> GetAllUsersAsync()
        {
            var users = await _userRepository.GetAllAsync();
            return users.Where(u => !u.IsDeleted).Select(MapToResponse);
        }

        public async Task<(IEnumerable<AdminUserResponse> Items, long TotalCount)> GetPagedUsersAsync(int page, int pageSize, string? search = null, string? role = null, string? status = null)
        {
            page = Math.Max(1, page);
            pageSize = Math.Clamp(pageSize, 1, 100);

            string? roleFilter = null;
            if (!string.IsNullOrWhiteSpace(role))
            {
                roleFilter = role.Trim().ToLowerInvariant() switch
                {
                    "admin" => "Admin",
                    "chef" => "Chef",
                    "user" => "User",
                    _ => throw new BadRequestException("Vai trò chỉ nhận Admin, Chef hoặc User.", "invalid_role")
                };
            }

            GeneralEnum.UserStatusEnum? statusFilter = null;
            if (!string.IsNullOrWhiteSpace(status))
            {
                if (!Enum.TryParse<GeneralEnum.UserStatusEnum>(status.Trim(), ignoreCase: true, out var parsed) || !Enum.IsDefined(parsed))
                {
                    throw new BadRequestException("Trạng thái chỉ nhận Active, Inactive, Locked hoặc Banned.", "invalid_status");
                }
                statusFilter = parsed;
            }

            var term = string.IsNullOrWhiteSpace(search) ? null : search.Trim().ToLowerInvariant();

            // Dòng cũ không có Status được tính là Active, giống cách đăng nhập đang đối xử với nó.
            var activeOnly = statusFilter == GeneralEnum.UserStatusEnum.Active;
            System.Linq.Expressions.Expression<Func<User, bool>> filter = u =>
                !u.IsDeleted &&
                (term == null || u.FullName.ToLower().Contains(term) || u.Email.ToLower().Contains(term) || u.Phone.Contains(term)) &&
                (roleFilter == null || u.Role == roleFilter) &&
                (statusFilter == null || u.Status == statusFilter || (activeOnly && u.Status == null));

            var totalCount = await _userRepository.CountAsync(filter);
            var users = (await _userRepository.FindPagedAsync(
                filter,
                page,
                pageSize,
                sortDesc: u => u.CreatedAt)).ToList();

            var ids = users.Select(u => u.Id).ToList();
            var posts = (await _postRepository.FindAsync(p => ids.Contains(p.UserId) && !p.IsDeleted))
                .GroupBy(p => p.UserId)
                .ToDictionary(g => g.Key, g => (Count: g.Count(), Reports: g.Sum(p => p.ReportCount)));

            return (users.Select(u => MapToAdminResponse(u, posts.TryGetValue(u.Id, out var c) ? c : (0, 0))).ToList(), totalCount);
        }

        public async Task<AdminUserResponse> ChangeRoleAsync(string id, string role, string currentUserId)
        {
            GuardSelf(id, currentUserId);
            var user = await RequireUserAsync(id);

            if (user.Role == "Chef")
            {
                throw new ConflictException("Vai trò Chuyên gia được cấp khi duyệt hồ sơ chuyên gia, không đổi ở đây.", "chef_role_locked");
            }

            if (user.Role != role)
            {
                user.Role = role;
                // Token cũ mang vai trò cũ: buộc đăng nhập lại.
                RevokeSessions(user);
                user.UpdatedAt = DateTime.UtcNow;
                await _userRepository.UpdateAsync(id, user);
                _cache?.Remove(UserCacheKeys.UserStatus(id));
            }

            return await MapAdminAsync(user);
        }

        public async Task<AdminUserResponse> ChangeStatusAsync(string id, string status, string? reason, string currentUserId)
        {
            GuardSelf(id, currentUserId);
            var user = await RequireUserAsync(id);

            var target = Enum.Parse<GeneralEnum.UserStatusEnum>(status);
            var blocks = target is GeneralEnum.UserStatusEnum.Locked or GeneralEnum.UserStatusEnum.Banned;

            user.Status = target;
            user.StatusReason = blocks && !string.IsNullOrWhiteSpace(reason) ? reason.Trim() : null;
            user.StatusChangedAt = DateTime.UtcNow;
            user.StatusChangedBy = currentUserId;
            user.UpdatedAt = DateTime.UtcNow;
            if (blocks)
            {
                RevokeSessions(user);
            }

            await _userRepository.UpdateAsync(id, user);

            // B54: có hiệu lực ngay, không đợi hết hạn cache.
            _cache?.Remove(UserCacheKeys.UserStatus(id));

            return await MapAdminAsync(user);
        }

        private static void GuardSelf(string id, string currentUserId)
        {
            if (id == currentUserId)
            {
                throw new ConflictException("Bạn không thể tự đổi quyền, khoá hoặc xoá tài khoản đang đăng nhập.", "self_action");
            }
        }

        private async Task<User> RequireUserAsync(string id)
        {
            var user = await _userRepository.FindByIdAsync(id);
            if (user == null || user.IsDeleted) throw new NotFoundException("Không tìm thấy người dùng.");
            return user;
        }

        private static void RevokeSessions(User user)
        {
            user.RefreshSessions = new List<RefreshSession>();
            user.RefreshTokenHash = null;
            user.RefreshTokenExpiresAt = null;
        }

        private async Task<AdminUserResponse> MapAdminAsync(User user)
        {
            var id = user.Id;
            var posts = (await _postRepository.FindAsync(p => p.UserId == id && !p.IsDeleted)).ToList();
            return MapToAdminResponse(user, (posts.Count, posts.Sum(p => p.ReportCount)));
        }

        public async Task<UserResponse?> GetUserByIdAsync(string id)
        {
            var user = await _userRepository.FindByIdAsync(id);
            if (user == null || user.IsDeleted) return null;
            return MapToResponse(user);
        }

        public async Task<UserResponse> UpdateUserAsync(string id, UpdateUserRequest request)
        {
            var user = await _userRepository.FindByIdAsync(id)
                       ?? throw new NotFoundException("Không tìm thấy người dùng.");

            if (user.IsDeleted)
                throw new NotFoundException("Không tìm thấy người dùng.");

            user.FullName = request.FullName;
            if (request.Phone != null) user.Phone = request.Phone;
            user.UpdatedAt = DateTime.UtcNow;

            await _userRepository.UpdateAsync(id, user);
            return MapToResponse(user);
        }

        public async Task<bool> DeleteUserAsync(string id, string? currentUserId = null)
        {
            if (!string.IsNullOrEmpty(currentUserId) && id == currentUserId)
            {
                throw new BadRequestException("Không thể tự xóa tài khoản của chính mình.", "self_action");
            }

            var user = await _userRepository.FindByIdAsync(id);
            if (user == null || user.IsDeleted) return false;

            if (user.Role == "Admin")
            {
                var adminCount = await _userRepository.CountAsync(u => u.Role == "Admin" && !u.IsDeleted);
                if (adminCount <= 1)
                {
                    throw new ConflictException("Không thể xóa Quản trị viên cuối cùng của hệ thống.");
                }
            }

            // Soft delete
            user.IsDeleted = true;
            user.DeletedAt = DateTime.UtcNow;
            user.UpdatedAt = DateTime.UtcNow;
            RevokeSessions(user);

            await _userRepository.UpdateAsync(id, user);

            // B54: Xóa cache trạng thái user ngay lập tức để token mất hiệu lực
            _cache?.Remove(UserCacheKeys.UserStatus(id));

            return true;
        }

        public async Task<UserProfileResponse> GetCurrentUserProfileAsync(string userId)
        {
            var user = await _userRepository.FindByIdAsync(userId);
            if (user == null || user.IsDeleted)
                throw new NotFoundException("Không tìm thấy người dùng.");

            if (user.Status == GeneralEnum.UserStatusEnum.Locked || user.Status == GeneralEnum.UserStatusEnum.Banned)
                throw new AccountLockedException(string.IsNullOrWhiteSpace(user.StatusReason)
                    ? "Tài khoản đang bị khoá. Liên hệ hỗ trợ."
                    : $"Tài khoản đang bị khoá. Lý do: {user.StatusReason}");

            var userPosts = await _postRepository.FindAsync(p => p.UserId == userId && !p.IsDeleted);
            var postList = userPosts.ToList();
            var totalPosts = postList.Count;
            var totalLikes = postList.Sum(p => p.LikeCount);

            var totalSaved = _saveRepository == null
                ? 0L
                : await _saveRepository.CountAsync(x => x.UserId == userId && !x.IsDeleted);

            var profile = MapToProfileResponse(user, totalPosts, totalLikes, (int)totalSaved);

            // App đọc trạng thái đơn chuyên gia ở đây; đơn mới nhất quyết định, vai trò Chef luôn là đã duyệt.
            if (_chefApplications != null && user.Role != "Chef")
            {
                var latest = (await _chefApplications.FindPagedAsync(a => a.UserId == userId && !a.IsDeleted, 1, 1, sortDesc: a => a.CreatedAt)).FirstOrDefault();
                if (latest != null)
                {
                    profile.ChefApplication = new ChefApplicationSummaryDto
                    {
                        Status = latest.Status,
                        RejectReason = latest.Status == ChefApplicationStatuses.Rejected ? latest.ReviewNote : null
                    };
                }
            }
            return profile;
        }

        // ─── Mapping helpers ──────────────────────────────────────────────────
        private static UserResponse MapToResponse(User user) => new()
        {
            Id        = user.Id,
            Email     = user.Email,
            FullName  = user.FullName,
            Phone     = user.Phone,
            Role      = user.Role,
            Status    = user.Status,
            AuthType  = user.AuthType,
            CreatedAt = user.CreatedAt
        };

        private static AdminUserResponse MapToAdminResponse(User user, (int Count, int Reports) posts) => new()
        {
            Id           = user.Id,
            Email        = user.Email,
            FullName     = user.FullName,
            Phone        = user.Phone,
            Role         = user.Role,
            Status       = user.Status ?? GeneralEnum.UserStatusEnum.Active,
            AuthType     = user.AuthType,
            CreatedAt    = user.CreatedAt,
            IsVerifiedChef = user.Role == "Chef",
            PostCount    = posts.Count,
            ReportCount  = posts.Reports,
            LastActiveAt = user.LastActiveAt,
            StatusReason = user.StatusReason
        };

        private static UserProfileResponse MapToProfileResponse(User user, int totalPosts = 0, int totalLikes = 0, int totalSaved = 0) => new()
        {
            Id        = user.Id,
            Email     = user.Email,
            FullName  = user.FullName,
            Phone     = user.Phone,
            Role      = user.Role,
            Status    = user.Status,
            AuthType  = user.AuthType,
            CreatedAt = user.CreatedAt,
            Stats     = new UserStatsDto
            {
                Posts = totalPosts,
                LikesReceived = totalLikes,
                Saved = totalSaved
            },
            ChefApplication = new ChefApplicationSummaryDto
            {
                Status = user.Role == "Chef" ? "approved" : "none",
                RejectReason = null
            }
        };
    }
}
