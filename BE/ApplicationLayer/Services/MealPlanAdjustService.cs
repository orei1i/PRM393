using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.MealPlan;
using ApplicationLayer.Interfaces;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Helpers;
using DomainLayer.Interfaces;

namespace ApplicationLayer.Services
{
    /// <summary>
    /// "Chỉnh thực đơn": đọc yêu cầu theo quy tắc rồi đề xuất món thay từ danh mục, không gọi AI.
    /// Món đề xuất luôn thuần chay và không trùng dị ứng; lúc áp dụng kiểm tra lại lần nữa.
    /// </summary>
    public class MealPlanAdjustService : IMealPlanAdjustService
    {
        private const int MaxChangesPerDay = 3;
        private const int MaxChangesPerWeek = 7;

        private readonly IGenericRepository<MealPlan> _planRepo;
        private readonly IGenericRepository<Recipe> _recipeRepo;
        private readonly IGenericRepository<HealthProfile> _profileRepo;
        private readonly IGenericRepository<MealPlanAdjustment> _adjustRepo;
        private readonly IGenericRepository<ChefBooking> _bookingRepo;

        public MealPlanAdjustService(
            IGenericRepository<MealPlan> planRepo,
            IGenericRepository<Recipe> recipeRepo,
            IGenericRepository<HealthProfile> profileRepo,
            IGenericRepository<MealPlanAdjustment> adjustRepo,
            IGenericRepository<ChefBooking> bookingRepo)
        {
            _planRepo = planRepo;
            _recipeRepo = recipeRepo;
            _profileRepo = profileRepo;
            _adjustRepo = adjustRepo;
            _bookingRepo = bookingRepo;
        }

        private sealed record Intent(string Label, Func<Recipe, MealSlotItem, bool> Improves, Func<Recipe, double> Rank, string? Excluded = null);

        public async Task<PlanAdjustmentResponse> ProposeAsync(string userId, AdjustPlanRequest request)
        {
            var message = request.Message?.Trim() ?? string.Empty;
            if (message.Length < 2 || message.Length > 500)
            {
                throw new BadRequestException("Yêu cầu phải có từ 2 đến 500 ký tự.", "invalid_message");
            }

            var scope = request.Scope?.Trim().ToLowerInvariant();
            if (scope != "day" && scope != "week")
            {
                throw new BadRequestException("scope chỉ nhận day hoặc week.", "invalid_scope");
            }

            var plan = await CurrentPlanAsync(userId);

            List<MealPlanDay> days;
            if (scope == "day")
            {
                var day = plan.Days.FirstOrDefault(d => d.Date == request.Date);
                if (day == null)
                {
                    throw new BadRequestException("Ngày này không nằm trong thực đơn tuần hiện tại.", "invalid_date");
                }
                days = new List<MealPlanDay> { day };
            }
            else
            {
                days = plan.Days;
            }

            var intent = ReadIntent(message);
            var changes = new List<PlanAdjustmentChange>();
            var targets = new Dictionary<string, Recipe>();
            var sources = new Dictionary<string, RecipeResponse>();
            var reply = "Mình chưa hiểu cần chỉnh gì. Thử nói rõ hơn, ví dụ: ít tinh bột hơn, nhiều đạm hơn, ít calo hơn, nấu nhanh hơn, hoặc không ăn nấm.";

            if (intent != null)
            {
                var allergies = await AllergiesOfAsync(userId);
                var safe = (await _recipeRepo.FindAsync(r => !r.IsDeleted && r.IsVegan && (r.CreatedBy == null || r.CreatedBy == userId)))
                    .Where(r => IsSafe(r, allergies) && !Mentions(r, intent.Excluded))
                    .OrderBy(intent.Rank)
                    .ToList();

                var limit = scope == "day" ? MaxChangesPerDay : MaxChangesPerWeek;
                foreach (var day in days)
                {
                    var used = day.Meals.Values.Select(m => m.RecipeId).ToHashSet();
                    foreach (var (slot, meal) in day.Meals.OrderBy(m => SlotOrder(m.Key)))
                    {
                        if (changes.Count >= limit) break;

                        var pick = safe.FirstOrDefault(r =>
                            r.Id != meal.RecipeId &&
                            !used.Contains(r.Id) &&
                            FitsSlot(r, slot) &&
                            intent.Improves(r, meal));
                        if (pick == null) continue;

                        used.Add(pick.Id);
                        var id = $"c{changes.Count + 1}";
                        changes.Add(new PlanAdjustmentChange
                        {
                            Id = id,
                            Date = day.Date,
                            Slot = slot,
                            Action = "replace",
                            FromRecipeId = meal.RecipeId,
                            FromName = meal.Name,
                            FromCalories = meal.Calories,
                            ToRecipeId = pick.Id,
                            KcalDelta = (int)Math.Round((pick.Calories - meal.Calories) * meal.Portion)
                        });
                        targets[id] = pick;
                        sources[id] = new RecipeResponse
                        {
                            Id = meal.RecipeId ?? string.Empty,
                            Name = meal.Name,
                            Calories = meal.Calories,
                            ProteinG = meal.ProteinG,
                            CarbsG = meal.CarbsG,
                            FatG = meal.FatG,
                            FiberG = meal.FiberG,
                            Allergens = meal.Allergens,
                            DietTags = meal.DietTags,
                            PrepMinutes = meal.PrepMinutes,
                            ImageUrl = meal.ImageUrl
                        };
                    }
                }

                reply = changes.Any()
                    ? $"Mình đề xuất {changes.Count} thay đổi để {intent.Label}. Bạn chọn những món muốn đổi nhé."
                    : $"Thực đơn hiện tại đã khá phù hợp để {intent.Label}, mình chưa tìm được món nào tốt hơn.";
            }

            var proposal = new MealPlanAdjustment
            {
                UserId = userId,
                PlanId = plan.Id,
                Message = message,
                Reply = reply,
                Changes = changes,
                CreatedAt = DateTime.UtcNow
            };
            await _adjustRepo.CreateAsync(proposal);

            return new PlanAdjustmentResponse
            {
                ProposalId = proposal.Id,
                Reply = reply,
                Changes = changes.Select(c => new PlanChangeResponse
                {
                    Id = c.Id,
                    Date = c.Date,
                    Slot = c.Slot,
                    Action = c.Action,
                    From = sources[c.Id],
                    To = MealPlanService.MapToRecipeResponse(targets[c.Id]),
                    KcalDelta = c.KcalDelta
                }).ToList()
            };
        }

        public async Task<MealPlanResponse> ApplyAsync(string userId, string proposalId, ApplyAdjustmentRequest request)
        {
            var proposal = await _adjustRepo.FindByIdAsync(proposalId);
            if (proposal == null || proposal.IsDeleted || proposal.UserId != userId)
            {
                throw new NotFoundException("Không tìm thấy đề xuất.");
            }
            if (proposal.AppliedAt != null)
            {
                throw new ConflictException("Đề xuất này đã được áp dụng.", "already_applied");
            }

            var ids = (request.ChangeIds ?? new List<string>()).Distinct().ToList();
            if (!ids.Any())
            {
                throw new BadRequestException("Chưa chọn thay đổi nào.", "no_changes");
            }

            var selected = new List<PlanAdjustmentChange>();
            foreach (var id in ids)
            {
                var change = proposal.Changes.FirstOrDefault(c => c.Id == id);
                if (change == null)
                {
                    throw new BadRequestException("Có thay đổi không thuộc đề xuất này.", "invalid_change");
                }
                selected.Add(change);
            }

            var plan = await _planRepo.FindByIdAsync(proposal.PlanId);
            if (plan == null || plan.IsDeleted || plan.UserId != userId)
            {
                throw new ConflictException("Thực đơn đã thay đổi, vui lòng tạo đề xuất mới.", "plan_changed");
            }

            var allergies = await AllergiesOfAsync(userId);
            var replacements = new List<(MealPlanDay Day, PlanAdjustmentChange Change, Recipe Recipe, double Portion)>();
            foreach (var change in selected)
            {
                var day = plan.Days.FirstOrDefault(d => d.Date == change.Date);
                MealSlotItem? current = null;
                if (day == null || !day.Meals.TryGetValue(change.Slot, out current) || current.RecipeId != change.FromRecipeId)
                {
                    throw new ConflictException("Thực đơn đã thay đổi, vui lòng tạo đề xuất mới.", "plan_changed");
                }

                var recipe = await _recipeRepo.FindByIdAsync(change.ToRecipeId ?? string.Empty);
                if (recipe == null || !RecipeRules.CanSee(recipe, userId) || !IsSafe(recipe, allergies))
                {
                    // Món vừa bị xoá, hoặc người dùng vừa thêm dị ứng sau khi có đề xuất.
                    throw new ConflictException("Thực đơn đã thay đổi, vui lòng tạo đề xuất mới.", "plan_changed");
                }
                replacements.Add((day, change, recipe, current.Portion));
            }

            foreach (var (day, change, recipe, portion) in replacements)
            {
                day.Meals[change.Slot] = MealPlanService.MapToMealSlotItem(recipe, "ai", portion);
            }
            plan.UpdatedAt = DateTime.UtcNow;
            await _planRepo.UpdateAsync(plan.Id, plan);

            proposal.AppliedAt = DateTime.UtcNow;
            await _adjustRepo.UpdateAsync(proposal.Id, proposal);

            return MealPlanService.MapToResponse(plan, allergies);
        }

        /// <summary>Món từ các ngày kế hoạch chuyên gia đã gửi cho người này, mới gửi trước.</summary>
        public async Task<IEnumerable<ChefSuggestionResponse>> GetChefSuggestionsAsync(string userId)
        {
            var bookings = await _bookingRepo.FindAsync(b => b.MemberId == userId && !b.IsDeleted);

            var rows = new List<ChefSuggestionResponse>();
            foreach (var booking in bookings)
            {
                foreach (var day in booking.Days.Where(d => d.Status == "Sent"))
                {
                    foreach (var meal in day.Meals)
                    {
                        var recipe = meal.Recipe;
                        rows.Add(new ChefSuggestionResponse
                        {
                            Id = StableId($"{booking.Id}:{day.DayIndex}:{meal.Slot}"),
                            ChefId = booking.ChefId,
                            ChefName = booking.ChefName,
                            Note = meal.Note ?? day.ChefNote,
                            Slot = meal.Slot,
                            TargetDate = day.Date,
                            CreatedAt = day.SentAt,
                            Recipe = new RecipeResponse
                            {
                                Id = recipe.Id ?? StableId($"{booking.Id}:{day.DayIndex}:{meal.Slot}:recipe"),
                                Name = recipe.Name,
                                Calories = recipe.Calories ?? 0,
                                ProteinG = recipe.ProteinG,
                                CarbsG = recipe.CarbsG,
                                FatG = recipe.FatG,
                                // Món chuyên gia tự nhập không có nhãn dị ứng: suy ra để app vẫn cảnh báo được.
                                Allergens = AllergyMatcher.DetectAllergens((recipe.Ingredients ?? new List<string>()).Append(recipe.Name)),
                                Ingredients = recipe.Ingredients ?? new List<string>(),
                                Instructions = string.IsNullOrWhiteSpace(recipe.Instructions)
                                    ? new List<string>()
                                    : new List<string> { recipe.Instructions }
                            }
                        });
                    }
                }
            }

            return rows.OrderByDescending(r => r.CreatedAt).Take(100).ToList();
        }

        private static string StableId(string text) =>
            Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text))).ToLowerInvariant()[..24];

        private async Task<MealPlan> CurrentPlanAsync(string userId)
        {
            var monday = MealPlanService.CurrentMondayString();
            var plan = await _planRepo.FirstOrDefaultAsync(x => x.UserId == userId && x.StartDate == monday && !x.IsDeleted);
            return plan ?? throw new NotFoundException("Bạn chưa có thực đơn cho tuần này.");
        }

        private async Task<List<string>> AllergiesOfAsync(string userId)
        {
            var profile = await _profileRepo.FirstOrDefaultAsync(p => p.UserId == userId && !p.IsDeleted);
            return profile?.Allergies ?? new List<string>();
        }

        private static bool IsSafe(Recipe recipe, List<string> allergies) =>
            !AllergyMatcher.FindConflicts(recipe.Allergens, recipe.Ingredients.Concat(new[] { recipe.Name }), allergies).Any();

        private static bool Mentions(Recipe recipe, string? excluded)
        {
            if (string.IsNullOrEmpty(excluded)) return false;
            return recipe.Ingredients.Concat(new[] { recipe.Name })
                .Any(t => AllergyMatcher.NormalizeForSearch(t).Contains(AllergyMatcher.NormalizeForSearch(excluded)));
        }

        private static bool FitsSlot(Recipe recipe, string slot) =>
            !recipe.MealTypes.Any() || recipe.MealTypes.Contains(slot) ||
            (slot.StartsWith("snack") && recipe.MealTypes.Any(t => t.StartsWith("snack")));

        private static int SlotOrder(string slot) => slot switch
        {
            "breakfast" => 0,
            "snack_am" => 1,
            "lunch" => 2,
            "snack_pm" => 3,
            "dinner" => 4,
            _ => 5
        };

        private static Intent? ReadIntent(string message)
        {
            var text = AllergyMatcher.NormalizeForSearch(message);
            bool Says(params string[] phrases) => phrases.Any(p => text.Contains($" {p} "));

            var excluded = ReadExcluded(text);
            if (excluded != null)
            {
                return new Intent(
                    $"bỏ {excluded}",
                    (recipe, meal) => AllergyMatcher.NormalizeForSearch(meal.Name).Contains(AllergyMatcher.NormalizeForSearch(excluded)),
                    recipe => 0,
                    excluded);
            }

            if (Says("it tinh bot", "giam tinh bot", "bot tinh bot", "low carb", "it carb", "giam carb", "it com"))
            {
                return new Intent("giảm tinh bột", (r, m) => r.CarbsG.HasValue && m.CarbsG.HasValue && r.CarbsG < m.CarbsG, r => r.CarbsG ?? double.MaxValue);
            }
            if (Says("nhieu dam", "tang dam", "giau dam", "them dam", "protein", "nhieu protein", "tang protein"))
            {
                return new Intent("tăng đạm", (r, m) => r.ProteinG.HasValue && m.ProteinG.HasValue && r.ProteinG > m.ProteinG, r => -(r.ProteinG ?? 0));
            }
            if (Says("nhieu calo", "tang calo", "them calo", "tang can", "an nhieu", "no hon", "nhieu nang luong"))
            {
                return new Intent("tăng năng lượng", (r, m) => r.Calories > m.Calories, r => -r.Calories);
            }
            if (Says("it calo", "giam calo", "bot calo", "giam can", "an it", "nhe bung", "an nhe", "nhe hon"))
            {
                return new Intent("giảm năng lượng", (r, m) => r.Calories < m.Calories, r => r.Calories);
            }
            if (Says("nhanh", "nau nhanh", "de lam", "de nau", "it thoi gian", "don gian"))
            {
                return new Intent("nấu nhanh hơn", (r, m) => r.PrepMinutes.HasValue && (!m.PrepMinutes.HasValue || r.PrepMinutes < m.PrepMinutes), r => r.PrepMinutes ?? int.MaxValue);
            }
            return null;
        }

        /// <summary>"không ăn nấm, ít mặn" lấy ra "nấm" (không dấu, tới dấu phẩy hoặc hết câu).</summary>
        private static string? ReadExcluded(string foldedWords)
        {
            foreach (var cue in new[] { " khong an ", " khong muon an ", " bo mon ", " khong co ", " tranh ", " bo " })
            {
                var at = foldedWords.IndexOf(cue, StringComparison.Ordinal);
                if (at < 0) continue;
                var rest = foldedWords[(at + cue.Length)..].Trim();
                var words = rest.Split(' ', StringSplitOptions.RemoveEmptyEntries).Take(3).ToArray();
                if (words.Length > 0) return string.Join(" ", words);
            }
            return null;
        }
    }
}
