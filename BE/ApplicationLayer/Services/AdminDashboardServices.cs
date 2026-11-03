using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Content;
using ApplicationLayer.Interfaces;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Helpers;
using DomainLayer.Interfaces;
using Microsoft.Extensions.Configuration;

namespace ApplicationLayer.Services
{
    /// <summary>Trang tổng quan và danh mục. Mọi con số đều đếm từ DB; không có dữ liệu thì là 0 hoặc mảng rỗng.</summary>
    public class AdminDashboardService : IAdminDashboardService
    {
        private const string CatalogGone = "Mục không còn tồn tại.";
        private static readonly string[] Kinds = { "category", "diet_tag", "allergen", "specialty" };
        private static readonly Regex CodePattern = new("^[a-z0-9_]{2,40}$", RegexOptions.Compiled);

        private static readonly Dictionary<string, string> MealLabels = new()
        {
            ["breakfast"] = "Bữa sáng",
            ["lunch"] = "Bữa trưa",
            ["dinner"] = "Bữa tối",
            ["snack_am"] = "Bữa phụ sáng",
            ["snack_pm"] = "Bữa phụ chiều",
            ["snack_late"] = "Bữa phụ tối"
        };

        private static readonly Dictionary<string, string> DietLabels = new()
        {
            ["quick"] = "Nhanh gọn",
            ["high_protein"] = "Giàu đạm",
            ["high_fiber"] = "Giàu chất xơ",
            ["low_sodium"] = "Ít muối",
            ["whole_food"] = "Thực phẩm nguyên chất",
            ["seasonal"] = "Đang mùa",
            ["gluten_free"] = "Không gluten"
        };

        private readonly IGenericRepository<User> _users;
        private readonly IGenericRepository<Post> _posts;
        private readonly IGenericRepository<Comment> _comments;
        private readonly IGenericRepository<AiLog> _aiLogs;
        private readonly IGenericRepository<ModerationFlag> _flags;
        private readonly IGenericRepository<ChefApplication> _applications;
        private readonly IGenericRepository<VideoExtraction> _videos;
        private readonly IGenericRepository<AdminAuditLog> _audits;
        private readonly IGenericRepository<CatalogItem> _catalog;
        private readonly IGenericRepository<Recipe> _recipes;
        private readonly IGenericRepository<Ingredient> _ingredients;
        private readonly IGenericRepository<ChefProfile> _profiles;
        private readonly IAdminContentRepository _store;
        private readonly IAdminAuditService _audit;
        private readonly IClock _clock;

        public AdminDashboardService(
            IGenericRepository<User> users,
            IGenericRepository<Post> posts,
            IGenericRepository<Comment> comments,
            IGenericRepository<AiLog> aiLogs,
            IGenericRepository<ModerationFlag> flags,
            IGenericRepository<ChefApplication> applications,
            IGenericRepository<VideoExtraction> videos,
            IGenericRepository<AdminAuditLog> audits,
            IGenericRepository<CatalogItem> catalog,
            IGenericRepository<Recipe> recipes,
            IGenericRepository<Ingredient> ingredients,
            IGenericRepository<ChefProfile> profiles,
            IAdminContentRepository store,
            IAdminAuditService audit,
            IClock clock)
        {
            _users = users;
            _posts = posts;
            _comments = comments;
            _aiLogs = aiLogs;
            _flags = flags;
            _applications = applications;
            _videos = videos;
            _audits = audits;
            _catalog = catalog;
            _recipes = recipes;
            _ingredients = ingredients;
            _profiles = profiles;
            _store = store;
            _audit = audit;
            _clock = clock;
        }

        /* ---------------------------------------------------------------- tổng quan */

        public async Task<OverviewResponse> GetOverviewAsync()
        {
            var now = _clock.UtcNow;
            var day = now.AddDays(-1);
            var twoDays = now.AddDays(-2);
            var week = now.AddDays(-7);
            var twoWeeks = now.AddDays(-14);

            var newUsers = await _users.CountAsync(u => !u.IsDeleted && u.CreatedAt >= week && u.CreatedAt <= now);
            var previousUsers = await _users.CountAsync(u => !u.IsDeleted && u.CreatedAt >= twoWeeks && u.CreatedAt < week);
            var posts24h = await _posts.CountAsync(p => !p.IsDeleted && p.CreatedAt >= day && p.CreatedAt <= now);
            var postsBefore = await _posts.CountAsync(p => !p.IsDeleted && p.CreatedAt >= twoDays && p.CreatedAt < day);
            // Embedding do nạp tài liệu sinh ra, không phải câu hỏi của người dùng.
            var ai24h = await _aiLogs.CountAsync(a => a.TaskType != "Embedding" && a.CreatedAt >= day && a.CreatedAt <= now);
            var aiBefore = await _aiLogs.CountAsync(a => a.TaskType != "Embedding" && a.CreatedAt >= twoDays && a.CreatedAt < day);
            var active = await ActiveUsersAsync(day, now);
            var activeBefore = await ActiveUsersAsync(twoDays, day);

            return new OverviewResponse
            {
                TotalUsers = await _users.CountAsync(u => !u.IsDeleted),
                NewUsers7d = newUsers,
                NewUsersDelta = ContentText.Delta(newUsers, previousUsers),
                ActiveUsers24h = active,
                ActiveDelta = ContentText.Delta(active, activeBefore),
                Posts24h = posts24h,
                PostsDelta = ContentText.Delta(posts24h, postsBefore),
                AiQueries24h = ai24h,
                AiQueriesDelta = ContentText.Delta(ai24h, aiBefore),
                Pending = new OverviewPending
                {
                    AiFlags = await _flags.CountAsync(f => !f.IsDeleted && f.Status != "resolved"),
                    ChefApplications = await _applications.CountAsync(a => !a.IsDeleted && a.Status == ChefApplicationStatuses.Pending),
                    ReportedContent = await _posts.CountAsync(p => !p.IsDeleted && p.ReportCount > 0),
                    FailedVideos = await _videos.CountAsync(v => !v.IsDeleted && v.Status == VideoAiStatuses.Failed),
                    PendingPosts = await _posts.CountAsync(p => !p.IsDeleted && p.Status == "Pending")
                },
                SignupsDaily = await SignupsDailyAsync(now),
                ContentMix = new List<OverviewContentMix>
                {
                    new() { Kind = "recipe", Count = await _posts.CountAsync(p => !p.IsDeleted && p.Status == "Published" && p.Type == "recipe") },
                    new() { Kind = "discussion", Count = await _posts.CountAsync(p => !p.IsDeleted && p.Status == "Published" && p.Type == "discussion") }
                },
                RecentActions = (await _audits.FindPagedAsync(a => !a.IsDeleted, 1, 6, sortDesc: a => a.CreatedAt))
                    .Select(a => new OverviewAction { Id = a.Id, At = a.CreatedAt, Actor = a.Actor, Action = a.Action, Target = a.Target })
                    .ToList()
            };
        }

        /// <summary>BE chưa ghi lần truy cập cuối: "hoạt động" là có đăng bài, bình luận hoặc gọi AI trong khoảng đó.</summary>
        private async Task<long> ActiveUsersAsync(DateTime from, DateTime to)
        {
            var ids = new HashSet<string>();
            foreach (var p in await _posts.FindAsync(x => x.CreatedAt >= from && x.CreatedAt < to)) ids.Add(p.UserId);
            foreach (var c in await _comments.FindAsync(x => x.CreatedAt >= from && x.CreatedAt < to)) ids.Add(c.UserId);
            foreach (var a in await _aiLogs.FindAsync(x => x.CreatedAt >= from && x.CreatedAt < to && x.UserId != null)) ids.Add(a.UserId!);
            return ids.Count;
        }

        private async Task<List<OverviewDailyCount>> SignupsDailyAsync(DateTime now)
        {
            const int days = 14;
            var today = VnTime.DateOf(now);
            var dates = Enumerable.Range(0, days).Select(i => VnTime.AddDays(today, i - days + 1)).ToList();
            var from = VnTime.At(dates[0], 0, 0);
            var counts = (await _users.FindAsync(u => !u.IsDeleted && u.CreatedAt >= from && u.CreatedAt <= now))
                .GroupBy(u => VnTime.DateOf(u.CreatedAt))
                .ToDictionary(g => g.Key, g => g.Count());
            return dates.Select(d => new OverviewDailyCount { Date = d, Count = counts.GetValueOrDefault(d) }).ToList();
        }

        /* ---------------------------------------------------------------- danh mục */

        private static void RequireKind(string? kind)
        {
            if (kind == null || !Kinds.Contains(kind)) throw ContentText.Invalid("Nhóm danh mục không hợp lệ.");
        }

        private static string SpecialtyCode(string specialty) =>
            string.Join('_', ContentText.Tokens(specialty)).ToLowerInvariant();

        /// <summary>Số tham chiếu thật theo từng mã: món, nguyên liệu, bài viết hoặc hồ sơ chuyên gia đang dùng.</summary>
        private async Task<Dictionary<string, (int Count, string Label)>> UsageAsync(string kind)
        {
            var usage = new Dictionary<string, (int Count, string Label)>(StringComparer.OrdinalIgnoreCase);
            void Add(string? code, string label)
            {
                if (string.IsNullOrWhiteSpace(code)) return;
                usage[code] = (usage.TryGetValue(code, out var v) ? v.Count + 1 : 1, label);
            }

            var recipes = (await _recipes.FindAsync(r => !r.IsDeleted)).ToList();
            switch (kind)
            {
                case "category":
                    foreach (var meal in recipes.SelectMany(r => r.MealTypes)) Add(meal, MealLabels.GetValueOrDefault(meal, meal));
                    break;
                case "diet_tag":
                    foreach (var tag in recipes.SelectMany(r => r.DietTags)) Add(tag, DietLabels.GetValueOrDefault(tag, tag));
                    break;
                case "allergen":
                    foreach (var id in AllergyMatcher.StandardAllergenIds) usage[id] = (0, AllergyMatcher.StandardAllergenLabels.GetValueOrDefault(id, id));
                    foreach (var a in recipes.SelectMany(r => r.Allergens)) Add(a, AllergyMatcher.StandardAllergenLabels.GetValueOrDefault(a, a));
                    foreach (var a in (await _ingredients.FindAsync(i => !i.IsDeleted)).SelectMany(i => i.Allergens)) Add(a, AllergyMatcher.StandardAllergenLabels.GetValueOrDefault(a, a));
                    break;
                case "specialty":
                    foreach (var p in await _profiles.FindAsync(x => !x.IsDeleted)) Add(SpecialtyCode(p.Specialty), p.Specialty);
                    break;
            }
            return usage;
        }

        private static CatalogItemResponse Map(CatalogItem c, int usage) => new()
        {
            Id = c.Id,
            Kind = c.Kind,
            Code = c.Code,
            Label = c.Label,
            Active = c.Active,
            UsageCount = usage,
            CvLabel = c.CvLabel
        };

        public async Task<List<CatalogItemResponse>> ListCatalogAsync(string? kind)
        {
            RequireKind(kind);
            var usage = await UsageAsync(kind!);
            var now = _clock.UtcNow;
            // Mục đang được dùng trong dữ liệu thật mà chưa có trong danh mục thì thêm vào, nhãn đã sửa giữ nguyên.
            foreach (var (code, value) in usage) await _store.EnsureCatalogItemAsync(kind!, code, value.Label, now);

            var rows = await _catalog.FindAsync(c => c.Kind == kind && !c.IsDeleted);
            return rows
                .OrderBy(c => c.Label, StringComparer.Ordinal)
                .Select(c => Map(c, usage.TryGetValue(c.Code, out var u) ? u.Count : 0))
                .ToList();
        }

        public async Task<CatalogItemResponse> CreateCatalogItemAsync(string adminId, CreateCatalogItemRequest request)
        {
            RequireKind(request.Kind);
            var code = request.Code?.Trim() ?? string.Empty;
            if (!CodePattern.IsMatch(code)) throw ContentText.Invalid("Mã gồm 2–40 ký tự: chữ thường, số và dấu gạch dưới.");
            var label = request.Label?.Trim() ?? string.Empty;
            if (label.Length < 2 || label.Length > 80) throw ContentText.Invalid("Tên hiển thị từ 2 đến 80 ký tự.");
            var cvLabel = string.IsNullOrWhiteSpace(request.CvLabel) ? null : request.CvLabel.Trim();
            if (cvLabel is { Length: > 80 }) throw ContentText.Invalid("Nhãn nhận diện tối đa 80 ký tự.");

            var item = new CatalogItem
            {
                Id = ContentText.NewId(),
                Kind = request.Kind!,
                Code = code,
                Label = label,
                CvLabel = cvLabel,
                Active = true,
                CreatedAt = _clock.UtcNow
            };
            if (!await _store.TryInsertCatalogItemAsync(item))
                throw new ConflictException($"Mã \"{code}\" đã tồn tại trong nhóm này.", "duplicate_code");

            await _audit.LogAsync(await _audit.NameOfAsync(adminId), "thêm mục danh mục", label);
            return Map(item, (await UsageAsync(item.Kind)).TryGetValue(code, out var u) ? u.Count : 0);
        }

        private async Task<CatalogItem> LoadItemAsync(string id)
        {
            var item = ContentText.IsId(id) ? await _catalog.FindByIdAsync(id) : null;
            return item == null || item.IsDeleted ? throw new NotFoundException(CatalogGone) : item;
        }

        public async Task<CatalogItemResponse> PatchCatalogItemAsync(string adminId, string id, PatchCatalogItemRequest request)
        {
            var item = await LoadItemAsync(id);
            if (request.Label != null)
            {
                var label = request.Label.Trim();
                if (label.Length < 2 || label.Length > 80) throw ContentText.Invalid("Tên hiển thị từ 2 đến 80 ký tự.");
                item.Label = label;
            }
            if (request.Active is { } active) item.Active = active;
            if (request.CvLabel != null)
            {
                if (request.CvLabel.Trim().Length > 80) throw ContentText.Invalid("Nhãn nhận diện tối đa 80 ký tự.");
                item.CvLabel = string.IsNullOrWhiteSpace(request.CvLabel) ? null : request.CvLabel.Trim();
            }
            item.UpdatedAt = _clock.UtcNow;
            await _catalog.UpdateAsync(id, item);
            await _audit.LogAsync(await _audit.NameOfAsync(adminId), "sửa mục danh mục", item.Label);
            return Map(item, (await UsageAsync(item.Kind)).TryGetValue(item.Code, out var u) ? u.Count : 0);
        }

        public async Task DeleteCatalogItemAsync(string adminId, string id)
        {
            var item = await LoadItemAsync(id);
            if ((await UsageAsync(item.Kind)).TryGetValue(item.Code, out var u) && u.Count > 0)
                throw new ConflictException("Mục đang được sử dụng: hãy tắt thay vì xoá.", "in_use");
            item.IsDeleted = true;
            item.DeletedAt = _clock.UtcNow;
            item.UpdatedAt = item.DeletedAt;
            await _catalog.UpdateAsync(id, item);
            await _audit.LogAsync(await _audit.NameOfAsync(adminId), "xoá mục danh mục", item.Label);
        }
    }

    /// <summary>
    /// Hàng đợi cờ kiểm duyệt AI. BE chưa có pipeline tạo cờ nên hàng đợi thật là rỗng;
    /// không tự sinh cờ. Báo cáo của người dùng nằm ở trang bài viết.
    /// </summary>
    public class ModerationService : IModerationService
    {
        private const int MinNote = 10;
        private static readonly string[] Statuses = { "pending", "escalated", "resolved" };
        private static readonly string[] Actions = { "approve", "reject", "warn" };

        private readonly IGenericRepository<ModerationFlag> _flags;
        private readonly IGenericRepository<Post> _posts;
        private readonly IGenericRepository<User> _users;
        private readonly IAdminContentRepository _store;
        private readonly IPostService _postService;
        private readonly IAdminAuditService _audit;
        private readonly IClock _clock;

        public ModerationService(
            IGenericRepository<ModerationFlag> flags,
            IGenericRepository<Post> posts,
            IGenericRepository<User> users,
            IAdminContentRepository store,
            IPostService postService,
            IAdminAuditService audit,
            IClock clock)
        {
            _flags = flags;
            _posts = posts;
            _users = users;
            _store = store;
            _postService = postService;
            _audit = audit;
            _clock = clock;
        }

        public async Task<List<FlagResponse>> ListFlagsAsync(string? status, string? category, string? search)
        {
            if (!string.IsNullOrWhiteSpace(status) && !Statuses.Contains(status)) throw ContentText.Invalid("Trạng thái cờ không hợp lệ.");

            IEnumerable<ModerationFlag> rows = await _flags.FindAsync(f => !f.IsDeleted);
            if (!string.IsNullOrWhiteSpace(status)) rows = rows.Where(f => f.Status == status);
            if (!string.IsNullOrWhiteSpace(category)) rows = rows.Where(f => f.PrimaryCategory == category);
            var list = rows.OrderByDescending(f => f.CreatedAt).ToList();
            if (list.Count == 0) return new List<FlagResponse>();

            var postIds = list.Select(f => f.PostId).Distinct().ToList();
            var posts = (await _posts.FindAsync(p => postIds.Contains(p.Id))).ToDictionary(p => p.Id);
            var authorIds = posts.Values.Select(p => p.UserId).Distinct().ToList();
            var authors = (await _users.FindAsync(u => authorIds.Contains(u.Id))).ToDictionary(u => u.Id);

            var tokens = ContentText.Tokens(search);
            if (tokens.Count > 0)
            {
                list = list.Where(f =>
                {
                    posts.TryGetValue(f.PostId, out var p);
                    return ContentText.Matches(tokens, f.Reason, p?.Title, p?.Body, p == null ? null : authors.GetValueOrDefault(p.UserId)?.FullName);
                }).ToList();
            }
            return list.Select(f => Map(f, posts.GetValueOrDefault(f.PostId), authors)).ToList();
        }

        private static FlagResponse Map(ModerationFlag f, Post? p, Dictionary<string, User> authors) => new()
        {
            Id = f.Id,
            PostId = f.PostId,
            Status = f.Status,
            PrimaryCategory = f.PrimaryCategory,
            Confidence = f.Confidence,
            ToxicityScore = f.ToxicityScore,
            Scores = f.Scores.Select(s => new FlagScoreResponse { Category = s.Category, Score = s.Score }).ToList(),
            Reason = f.Reason,
            Spans = f.Spans.Select(s => new FlagSpanResponse { Start = s.Start, End = s.End, Category = s.Category }).ToList(),
            SuggestedAction = f.SuggestedAction,
            PolicyRef = f.PolicyRef,
            ModelVersion = f.ModelVersion,
            LatencyMs = f.LatencyMs,
            TraceId = f.TraceId,
            CreatedAt = f.CreatedAt,
            Post = p == null ? null : new FlagPostResponse
            {
                Id = p.Id,
                Type = p.MediaType == "Video" ? "video" : "post",
                Author = new FlagAuthorResponse
                {
                    Id = p.UserId,
                    DisplayName = authors.TryGetValue(p.UserId, out var a) && !a.IsDeleted ? a.FullName ?? "Thành viên" : "Thành viên",
                    JoinedAt = authors.GetValueOrDefault(p.UserId)?.CreatedAt
                },
                Text = string.IsNullOrWhiteSpace(p.Title) ? p.Body : $"{p.Title}\n{p.Body}",
                Media = string.IsNullOrEmpty(p.MediaUrl) ? new List<FlagMediaResponse>() : new List<FlagMediaResponse> { new() { Url = p.MediaUrl, Alt = p.Title } },
                IngredientTags = p.Tags,
                CreatedAt = p.CreatedAt,
                Stats = new FlagStatsResponse { Likes = Math.Max(0, p.LikeCount), Comments = Math.Max(0, p.CommentCount) },
                ReportCount = p.ReportCount,
                Visibility = p.IsDeleted || p.Status == "Rejected" ? "removed" : p.Status == "Published" ? "visible" : "auto_hidden"
            }
        };

        public async Task<Dictionary<string, long>> CountFlagsAsync() => new()
        {
            ["pending"] = await _flags.CountAsync(f => !f.IsDeleted && f.Status == "pending"),
            ["escalated"] = await _flags.CountAsync(f => !f.IsDeleted && f.Status == "escalated"),
            ["resolved"] = await _flags.CountAsync(f => !f.IsDeleted && f.Status == "resolved")
        };

        public async Task DecideAsync(string adminId, string id, ModerationDecisionRequest request)
        {
            var action = request.Action?.Trim();
            if (action == null || !Actions.Contains(action)) throw ContentText.Invalid("Hành động phải là approve, reject hoặc warn.");
            var note = request.Note?.Trim() ?? string.Empty;
            if (note.Length < MinNote) throw new BadRequestException($"Ghi chú cần ít nhất {MinNote} ký tự.", "note_too_short");

            var current = ContentText.IsId(id) ? await _flags.FindByIdAsync(id) : null;
            if (current == null || current.IsDeleted) throw new NotFoundException("Cờ không còn tồn tại.");

            var actor = await _audit.NameOfAsync(adminId);
            var decided = await _store.TryDecideFlagAsync(id, action, note, actor, _clock.UtcNow)
                          ?? throw new ConflictException("Cờ này đã được xử lý.", "already_decided");

            if (action == "reject")
            {
                try
                {
                    await _postService.ModeratePostAsync(decided.PostId, "Reject", note);
                }
                catch (NotFoundException)
                {
                    // Bài đã bị xoá: quyết định vẫn được ghi.
                }
            }
            await _audit.LogAsync(actor, $"xử lý cờ kiểm duyệt: {action}", decided.PostId, note);
        }
    }

    /// <summary>Số liệu AI đọc từ AiLogs do GeminiClient ghi. Không có log thì mọi số là 0.</summary>
    public class AdminAiService : IAdminAiService
    {
        private const int MinNote = 10;
        private static readonly string[] Tasks = { "moderation", "meal_plan", "chatbot", "vision_scan" };
        private static readonly Regex SecretInUrl = new(@"(key|token|secret)=[^&\s]+", RegexOptions.IgnoreCase | RegexOptions.Compiled);

        private readonly IGenericRepository<AiLog> _logs;
        private readonly IGenericRepository<AiLogLabel> _labels;
        private readonly IGenericRepository<AiModelConfig> _models;
        private readonly IGenericRepository<ModerationFlag> _flags;
        private readonly IAdminContentRepository _store;
        private readonly IAdminAuditService _audit;
        private readonly IClock _clock;
        private readonly string _llmModel;

        public AdminAiService(
            IGenericRepository<AiLog> logs,
            IGenericRepository<AiLogLabel> labels,
            IGenericRepository<AiModelConfig> models,
            IGenericRepository<ModerationFlag> flags,
            IAdminContentRepository store,
            IAdminAuditService audit,
            IClock clock,
            IConfiguration configuration)
        {
            _logs = logs;
            _labels = labels;
            _models = models;
            _flags = flags;
            _store = store;
            _audit = audit;
            _clock = clock;
            _llmModel = configuration["Gemini:Model"] ?? "gemini-2.5-flash";
        }

        private static string TaskOf(string taskType)
        {
            var t = taskType.ToLowerInvariant();
            if (t.Contains("vision")) return "vision_scan";
            if (t.Contains("mealplan") || t.Contains("meal_plan")) return "meal_plan";
            if (t.Contains("chat") || t.Contains("rag")) return "chatbot";
            if (t.Contains("moderation")) return "moderation";
            return "other";
        }

        private static TimeSpan RangeOf(string? range) => range switch
        {
            "1h" => TimeSpan.FromHours(1),
            "24h" or null or "" => TimeSpan.FromHours(24),
            "7d" => TimeSpan.FromDays(7),
            _ => throw ContentText.Invalid("Khoảng thời gian phải là 1h, 24h hoặc 7d.")
        };

        private static double Percentile95(IReadOnlyCollection<long> values)
        {
            if (values.Count == 0) return 0;
            var ordered = values.OrderBy(v => v).ToList();
            return ordered[Math.Min(ordered.Count - 1, (int)Math.Ceiling(ordered.Count * 0.95) - 1)];
        }

        private static double Rate(int part, int total) => total == 0 ? 0 : Math.Round(part / (double)total, 4);
        private static double Mean(IEnumerable<AiLog> rows) => rows.Any() ? Math.Round(rows.Average(r => r.LatencyMs), 1) : 0;

        public async Task<TelemetryResponse> GetTelemetryAsync(string? range)
        {
            var span = RangeOf(range);
            var now = _clock.UtcNow;
            var from = now - span;
            var before = from - span;
            var rows = (await _logs.FindAsync(l => l.CreatedAt >= before && l.CreatedAt <= now)).ToList();
            var current = rows.Where(l => l.CreatedAt >= from).ToList();
            var previous = rows.Where(l => l.CreatedAt < from).ToList();

            var errorRate = Rate(current.Count(l => !l.Success), current.Count);
            var previousErrorRate = Rate(previous.Count(l => !l.Success), previous.Count);
            var avg = Mean(current);

            return new TelemetryResponse
            {
                Range = string.IsNullOrEmpty(range) ? "24h" : range,
                TotalCalls = current.Count,
                AvgLatencyMs = avg,
                P95LatencyMs = Percentile95(current.Select(l => l.LatencyMs).ToList()),
                FlagRate = 0, // Không có pipeline kiểm duyệt nên không có lượt gắn cờ.
                ErrorRate = errorRate,
                TotalTokens = current.Sum(l => (long)l.PromptTokens + l.CandidatesTokens),
                Delta = new TelemetryDelta
                {
                    TotalCalls = ContentText.Delta(current.Count, previous.Count),
                    AvgLatencyMs = ContentText.Delta(avg, Mean(previous)),
                    FlagRate = 0,
                    ErrorRate = ContentText.Delta(errorRate, previousErrorRate)
                },
                ByTask = current
                    .GroupBy(l => TaskOf(l.TaskType))
                    .Where(g => Tasks.Contains(g.Key))
                    .OrderByDescending(g => g.Count())
                    .Select(g => new TaskTelemetryResponse
                    {
                        Task = g.Key,
                        Calls = g.Count(),
                        AvgLatencyMs = Mean(g),
                        P95LatencyMs = Percentile95(g.Select(l => l.LatencyMs).ToList()),
                        ErrorRate = Rate(g.Count(l => !l.Success), g.Count())
                    })
                    .ToList()
            };
        }

        private static AiLogResponse MapLog(AiLog l, AiLogLabel? label) => new()
        {
            Id = l.Id,
            Timestamp = l.CreatedAt,
            Task = TaskOf(l.TaskType),
            Model = l.Model,
            LatencyMs = l.LatencyMs,
            InputTokens = l.PromptTokens,
            OutputTokens = l.CandidatesTokens,
            Status = l.Success ? "success" : "error",
            Detail = l.Success ? "ok" : SecretInUrl.Replace(l.ErrorMessage ?? "Lỗi không rõ", "$1=***"),
            TraceId = l.Id,
            RefType = l.ScanId == null ? null : "scan",
            RefId = l.ScanId,
            Label = label == null ? null : new AiLogLabelResponse { Verdict = label.Verdict, Note = label.Note, By = label.By, At = label.At }
        };

        public async Task<List<AiLogResponse>> ListLogsAsync(string? task, int? limit)
        {
            if (!string.IsNullOrWhiteSpace(task) && !Tasks.Contains(task)) throw ContentText.Invalid("Tác vụ AI không hợp lệ.");
            var take = Math.Clamp(limit ?? 50, 1, 200);

            // Tên tác vụ lưu khác tên hiển thị nên lọc sau khi đọc; đọc dư để vẫn đủ số dòng khi có lọc.
            var rows = (await _logs.FindPagedAsync(l => !l.IsDeleted, 1, string.IsNullOrWhiteSpace(task) ? take : 2000, sortDesc: l => l.CreatedAt))
                .Where(l => string.IsNullOrWhiteSpace(task) || TaskOf(l.TaskType) == task)
                .Take(take)
                .ToList();

            var ids = rows.Select(l => l.Id).ToList();
            var labels = (await _labels.FindAsync(x => ids.Contains(x.LogId))).ToDictionary(x => x.LogId);
            return rows.Select(l => MapLog(l, labels.GetValueOrDefault(l.Id))).ToList();
        }

        private async Task<AiLog> LoadLogAsync(string id)
        {
            var log = ContentText.IsId(id) ? await _logs.FindByIdAsync(id) : null;
            return log == null || log.IsDeleted ? throw new NotFoundException("Không tìm thấy nhật ký AI.") : log;
        }

        public async Task<AiLogResponse> GetLogAsync(string id)
        {
            var log = await LoadLogAsync(id);
            return MapLog(log, await _labels.FirstOrDefaultAsync(x => x.LogId == id));
        }

        public async Task<AiLogResponse> LabelLogAsync(string adminId, string id, LabelAiLogRequest request)
        {
            var verdict = request.Verdict?.Trim();
            if (verdict is not ("correct" or "incorrect")) throw ContentText.Invalid("Nhãn phải là correct hoặc incorrect.");
            var note = string.IsNullOrWhiteSpace(request.Note) ? null : request.Note.Trim();
            if (note is { Length: > 500 }) throw ContentText.Invalid("Ghi chú tối đa 500 ký tự.");

            var log = await LoadLogAsync(id);
            var actor = await _audit.NameOfAsync(adminId);
            var label = await _store.UpsertLogLabelAsync(id, verdict, note, actor, _clock.UtcNow);
            await _audit.LogAsync(actor, $"gán nhãn nhật ký AI: {verdict}", TaskOf(log.TaskType));
            return MapLog(log, label);
        }

        /* ---------------------------------------------------------------- mô hình */

        private IEnumerable<AiModelConfig> Defaults()
        {
            yield return new AiModelConfig { Task = "chatbot", Name = "Chatbot dinh dưỡng", ActiveVersion = _llmModel, AvailableVersions = new List<string> { _llmModel }, Enabled = true, Fallback = "Trả lời bị tắt, app báo chưa dùng được chatbot" };
            yield return new AiModelConfig { Task = "vision_scan", Name = "Quét nguyên liệu", ActiveVersion = _llmModel, AvailableVersions = new List<string> { _llmModel }, Enabled = true, Fallback = "Người dùng nhập nguyên liệu thủ công" };
            yield return new AiModelConfig { Task = "meal_plan", Name = "Gợi ý thực đơn", ActiveVersion = "rule-based", AvailableVersions = new List<string> { "rule-based" }, Enabled = true, Fallback = "Người dùng tự lên thực đơn" };
            yield return new AiModelConfig { Task = "moderation", Name = "Kiểm duyệt nội dung", ActiveVersion = "none", AvailableVersions = new List<string>(), Enabled = false, Threshold = null, Fallback = "Admin duyệt thủ công" };
        }

        private static AiModelResponse MapModel(AiModelConfig m) => new()
        {
            Id = m.Id,
            Task = m.Task,
            Name = m.Name,
            ActiveVersion = m.ActiveVersion,
            AvailableVersions = m.AvailableVersions,
            Enabled = m.Enabled,
            Threshold = m.Threshold,
            Fallback = m.Fallback,
            UpdatedAt = m.UpdatedAt ?? m.CreatedAt,
            UpdatedBy = m.UpdatedBy,
            // Kiểm duyệt AI chưa có pipeline. Phiên bản: mỗi tác vụ chỉ có một lựa chọn nên không có gì để chọn.
            RuntimeEnforced = m.Task is AiModelGate.Chatbot or AiModelGate.VisionScan or AiModelGate.MealPlan
        };

        public async Task<List<AiModelResponse>> ListModelsAsync()
        {
            var now = _clock.UtcNow;
            foreach (var model in Defaults()) await _store.EnsureAiModelAsync(model, now);
            var rows = await _models.FindAsync(m => !m.IsDeleted);
            return rows.OrderBy(m => Array.IndexOf(Tasks, m.Task)).Select(MapModel).ToList();
        }

        public async Task<AiModelResponse> PatchModelAsync(string adminId, string id, PatchAiModelRequest request)
        {
            var note = request.Note?.Trim() ?? string.Empty;
            if (note.Length < MinNote) throw new BadRequestException($"Ghi chú cần ít nhất {MinNote} ký tự.", "note_too_short");

            var model = ContentText.IsId(id) ? await _models.FindByIdAsync(id) : null;
            if (model == null || model.IsDeleted) throw new NotFoundException("Không tìm thấy mô hình AI.");

            if (request.Enabled == true && model.Task == "moderation")
                throw new ConflictException("BE chưa có pipeline kiểm duyệt AI nên chưa bật được.", "no_pipeline");
            if (request.Threshold is { } threshold)
            {
                if (model.Task is not ("moderation" or "vision_scan")) throw new BadRequestException("Tác vụ này không dùng ngưỡng.", "threshold_not_supported");
                if (threshold < 0.5 || threshold > 0.99) throw new BadRequestException("Ngưỡng từ 0,5 đến 0,99.", "invalid_threshold");
                model.Threshold = threshold;
            }
            if (request.ActiveVersion != null)
            {
                if (!model.AvailableVersions.Contains(request.ActiveVersion)) throw new BadRequestException("Phiên bản không có sẵn.", "invalid_version");
                model.ActiveVersion = request.ActiveVersion;
            }
            if (request.Enabled is { } enabled) model.Enabled = enabled;

            var actor = await _audit.NameOfAsync(adminId);
            model.UpdatedAt = _clock.UtcNow;
            model.UpdatedBy = actor;
            await _models.UpdateAsync(id, model);
            await _audit.LogAsync(actor, "đổi cấu hình mô hình AI", model.Name, note);
            return MapModel(model);
        }

        /* ---------------------------------------------------------------- độ chính xác */

        public async Task<AiMetricsResponse> GetMetricsAsync(string? range)
        {
            var from = _clock.UtcNow - RangeOf(range);
            var decided = (await _flags.FindAsync(f => !f.IsDeleted && f.Status == "resolved" && f.DecidedAt >= from)).ToList();
            var confirmed = decided.Count(f => f.Action != "approve");
            var minutes = decided.Where(f => f.DecidedAt.HasValue).Select(f => (f.DecidedAt!.Value - f.CreatedAt).TotalMinutes).OrderBy(m => m).ToList();

            var labels = (await _labels.FindAsync(l => l.At >= from)).ToList();
            var logIds = labels.Select(l => l.LogId).Distinct().ToList();
            var logs = logIds.Count == 0 ? new Dictionary<string, AiLog>() : (await _logs.FindAsync(l => logIds.Contains(l.Id))).ToDictionary(l => l.Id);

            return new AiMetricsResponse
            {
                Range = string.IsNullOrEmpty(range) ? "24h" : range,
                Moderation = new ModerationMetrics
                {
                    Decided = decided.Count,
                    Confirmed = confirmed,
                    Overridden = decided.Count - confirmed,
                    Precision = Rate(confirmed, decided.Count),
                    OverrideRate = Rate(decided.Count - confirmed, decided.Count),
                    Pending = await _flags.CountAsync(f => !f.IsDeleted && f.Status != "resolved"),
                    MedianDecisionMinutes = minutes.Count == 0 ? 0 : Math.Round(minutes[minutes.Count / 2], 1),
                    ByCategory = decided
                        .GroupBy(f => f.PrimaryCategory)
                        .Select(g => new ModerationCategoryMetric { Category = g.Key, Decided = g.Count(), Precision = Rate(g.Count(f => f.Action != "approve"), g.Count()) })
                        .ToList()
                },
                Labeled = labels
                    .Where(l => logs.ContainsKey(l.LogId))
                    .GroupBy(l => TaskOf(logs[l.LogId].TaskType))
                    .Where(g => Tasks.Contains(g.Key))
                    .Select(g => new LabeledMetric
                    {
                        Task = g.Key,
                        Labeled = g.Count(),
                        Correct = g.Count(l => l.Verdict == "correct"),
                        Accuracy = Rate(g.Count(l => l.Verdict == "correct"), g.Count())
                    })
                    .ToList()
            };
        }
    }
}
