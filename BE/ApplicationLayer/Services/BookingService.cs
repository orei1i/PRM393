using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Commerce;
using ApplicationLayer.Interfaces;
using DomainLayer.Constants;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Helpers;
using DomainLayer.Interfaces;
using MongoDB.Bson;
using static DomainLayer.Enums.GeneralEnum;

namespace ApplicationLayer.Services
{
    /// <summary>
    /// Luồng đặt chuyên gia của thành viên và chuyên gia. Quyền: không phải hai bên của booking thì 404
    /// (không lộ booking có tồn tại), làm thao tác của bên kia thì 403 wrong_party.
    /// </summary>
    public class BookingService : IBookingService
    {
        private static readonly string[] MealSlots = { "breakfast", "snack_am", "lunch", "snack_pm", "dinner", "snack_late" };
        private static readonly string[] ComplaintReasons = { "not_as_agreed", "health_risk", "late_or_missing", "allergen", "other" };
        private static readonly string[] Adherences = { "All", "Partly", "None" };
        private static readonly Dictionary<string, string> AllergenLabels = new()
        {
            ["peanut"] = "Đậu phộng",
            ["tree_nut"] = "Hạt cây (điều, hạnh nhân…)",
            ["soy"] = "Đậu nành",
            ["gluten"] = "Gluten",
            ["sesame"] = "Mè",
            ["mustard"] = "Mù tạt",
            ["celery"] = "Cần tây"
        };

        private readonly IBookingEngine _engine;
        private readonly IBookingRepository _bookings;
        private readonly IGenericRepository<User> _users;
        private readonly IGenericRepository<HealthProfile> _health;
        private readonly IGenericRepository<Recipe> _recipes;
        private readonly IGenericRepository<ChefProfile> _profiles;
        private readonly IClock _clock;

        public BookingService(
            IBookingEngine engine,
            IBookingRepository bookings,
            IGenericRepository<User> users,
            IGenericRepository<HealthProfile> health,
            IGenericRepository<Recipe> recipes,
            IGenericRepository<ChefProfile> profiles,
            IClock clock)
        {
            _engine = engine;
            _bookings = bookings;
            _users = users;
            _health = health;
            _recipes = recipes;
            _profiles = profiles;
            _clock = clock;
        }

        private static BadRequestException Invalid(string message) => new(message, "validation");

        private static string PartyOf(ChefBooking b, string userId) =>
            b.MemberId == userId ? BookingParties.Member
            : b.ChefId == userId ? BookingParties.Chef
            : throw new NotFoundException(CommerceMessages.BookingNotFound);

        private static void Expect(ChefBooking b, string userId, string expected)
        {
            if (PartyOf(b, userId) != expected)
                throw new ForbiddenException(
                    expected == BookingParties.Chef ? "Chỉ chuyên gia của yêu cầu này làm được thao tác này." : "Chỉ thành viên đặt yêu cầu này làm được thao tác này.",
                    "wrong_party");
        }

        private async Task<ChefBooking> LoadAsync(string id) =>
            await _engine.LoadSettledAsync(id) ?? throw new NotFoundException(CommerceMessages.BookingNotFound);

        private async Task<BookingResponse> ViewAsync(ChefBooking b) => BookingMapper.Booking(b, await HealthOfAsync(b));

        private async Task<MemberHealthResponse?> HealthOfAsync(ChefBooking b)
        {
            if (!b.ShareHealthProfile || b.Audience != BookingAudiences.Self || !ObjectId.TryParse(b.MemberId, out _)) return null;
            var memberId = b.MemberId;
            var p = await _health.FirstOrDefaultAsync(h => h.UserId == memberId && !h.IsDeleted);
            if (p == null) return null;
            var year = int.Parse(VnTime.DateOf(_clock.UtcNow)[..4]);
            return new MemberHealthResponse
            {
                HeightCm = p.HeightCm,
                WeightKg = p.WeightKg,
                Bmi = p.Bmi,
                Gender = p.Gender,
                Age = p.BirthYear > 0 ? year - p.BirthYear : null,
                ActivityLevel = p.ActivityLevel,
                DailyKcalTarget = p.TargetCalories > 0 ? p.TargetCalories : null
            };
        }

        private async Task<List<BookingResponse>> ViewsAsync(List<ChefBooking> rows)
        {
            var result = new List<BookingResponse>(rows.Count);
            foreach (var b in rows) result.Add(await ViewAsync(b));
            return result;
        }

        private void RequireFutureStart(string? raw, out string startDate)
        {
            if (!VnTime.TryParseDate(raw, out startDate) || string.CompareOrdinal(startDate, VnTime.DateOf(_clock.UtcNow)) <= 0)
                throw Invalid("Ngày bắt đầu từ ngày mai trở đi.");
        }

        private static void RequirePlanDays(int? value)
        {
            if (value is not { } days || days < CommerceRules.MinPlanDays || days > CommerceRules.MaxPlanDays)
                throw Invalid($"Số ngày từ {CommerceRules.MinPlanDays} đến {CommerceRules.MaxPlanDays}.");
        }

        private static void RequireBookingType(string? value)
        {
            if (!BookingTypes.IsValid(value)) throw Invalid("Loại kế hoạch không hợp lệ.");
        }

        /* ---------------------------------------------------------------- tạo, đọc */

        public async Task<BookingResponse> CreateAsync(string userId, CreateBookingRequest request)
        {
            if (string.IsNullOrWhiteSpace(request.ChefId)) throw Invalid("Thiếu chuyên gia.");
            RequireBookingType(request.BookingType);
            RequirePlanDays(request.PlanDays);
            RequireFutureStart(request.StartDate, out var startDate);

            var audience = request.Audience ?? BookingAudiences.Self;
            if (audience is not (BookingAudiences.Self or BookingAudiences.Family)) throw Invalid("Đối tượng không hợp lệ.");
            var family = audience == BookingAudiences.Family;
            var needs = request.Needs?.Trim() ?? string.Empty;
            if (family)
            {
                if (request.FamilySize is not { } size || size < CommerceRules.MinFamilySize || size > CommerceRules.MaxFamilySize)
                    throw Invalid($"Số người từ {CommerceRules.MinFamilySize} đến {CommerceRules.MaxFamilySize}.");
            }
            else if (needs.Length < CommerceRules.MinNeeds)
            {
                throw Invalid($"Mô tả nhu cầu ít nhất {CommerceRules.MinNeeds} ký tự để chuyên gia hiểu bạn.");
            }
            if (needs.Length > CommerceRules.MaxNeeds) throw Invalid($"Tối đa {CommerceRules.MaxNeeds} ký tự.");
            if (request.BudgetPerDay is < 0) throw Invalid("Ngân sách không hợp lệ.");

            var pattern = request.MealPattern?.Select(s => s?.Trim() ?? string.Empty).Distinct().ToList() ?? new List<string>();
            if (pattern.Count == 0) throw Invalid("Chọn ít nhất 1 bữa.");
            if (pattern.Any(s => !MealSlots.Contains(s))) throw Invalid("Bữa ăn không hợp lệ.");
            pattern = MealSlots.Where(pattern.Contains).ToList();

            var allergies = (request.Allergies ?? new List<string>())
                .Select(a => a?.Trim() ?? string.Empty).Where(a => a.Length > 0).Distinct().Take(50).ToList();

            var (chef, profile) = await FindChefAsync(request.ChefId.Trim());
            if (chef.Id == userId) throw new ConflictException("Bạn không thể tự đặt chính mình.", "self_booking");
            if (profile != null)
            {
                if (!profile.AcceptingBookings) throw new ConflictException("Chuyên gia đang tạm ngưng nhận yêu cầu.", "not_accepting");
                if (request.PlanDays < profile.MinPlanDays || request.PlanDays > profile.MaxPlanDays)
                    throw Invalid($"{chef.FullName} nhận kế hoạch từ {profile.MinPlanDays} đến {profile.MaxPlanDays} ngày.");
            }
            var member = await _users.FindByIdAsync(userId) ?? throw new UnauthorizedException("Phiên đăng nhập không hợp lệ.");

            // Gia đình: không giữ dữ liệu cá nhân nào, kể cả khi app gửi lên.
            var share = !family && request.ShareHealthProfile == true;
            var now = _clock.UtcNow;
            var booking = new ChefBooking
            {
                Id = BookingLifecycle.NewId(),
                MemberId = userId,
                MemberName = member.FullName ?? string.Empty,
                MemberEmail = member.Email ?? string.Empty,
                ChefId = chef.Id,
                ChefName = chef.FullName ?? string.Empty,
                ChefEmail = chef.Email ?? string.Empty,
                BookingType = request.BookingType!,
                PlanDays = request.PlanDays!.Value,
                StartDate = startDate,
                Audience = audience,
                FamilySize = family ? request.FamilySize : null,
                Goal = share ? request.Goal?.Trim() : null,
                Allergies = allergies,
                MealPattern = pattern,
                BudgetPerDay = request.BudgetPerDay,
                Needs = needs,
                ShareHealthProfile = share,
                Status = BookingStatuses.Requested,
                CreatedAt = now,
                UpdatedAt = now
            };
            BookingLifecycle.Say(booking, BookingParties.System,
                $"{booking.MemberName} đã gửi yêu cầu thiết kế thực đơn {booking.PlanDays} ngày ({BookingTypes.Label(booking.BookingType).ToLowerInvariant()})" +
                $"{(family ? $" cho gia đình {booking.FamilySize} người" : string.Empty)}, bắt đầu {VnTime.DayMonth(startDate)}.", now);
            if (needs.Length > 0) BookingLifecycle.Say(booking, BookingParties.Member, needs, now);

            await _bookings.InsertAsync(booking);
            return await ViewAsync(booking);
        }

        /// <summary>
        /// chefId là id hồ sơ lấy từ GET /chefs. Vẫn nhận id user có vai trò Chef (booking.chef.id, chuyên gia chưa có hồ sơ);
        /// khi đó giới hạn của hồ sơ, nếu có, vẫn được áp dụng.
        /// </summary>
        private async Task<(User Chef, ChefProfile? Profile)> FindChefAsync(string chefId)
        {
            if (!ObjectId.TryParse(chefId, out _)) throw new NotFoundException("Chuyên gia không còn hoạt động.");

            var profile = await _profiles.FirstOrDefaultAsync(p => p.Id == chefId && !p.IsDeleted);
            var userId = profile?.UserId ?? chefId;
            var chef = await _users.FindByIdAsync(userId);
            if (chef == null || chef.IsDeleted || chef.Role != "Chef" || chef.Status is UserStatusEnum.Locked or UserStatusEnum.Banned)
                throw new NotFoundException("Chuyên gia không còn hoạt động.");

            profile ??= await _profiles.FirstOrDefaultAsync(p => p.UserId == userId && !p.IsDeleted);
            return (chef, profile);
        }

        public async Task<List<BookingResponse>> ListMineAsync(string userId)
        {
            await _engine.SettleDueAsync(userId);
            return await ViewsAsync(await _bookings.ListForMemberAsync(userId));
        }

        public async Task<List<BookingResponse>> ListForChefAsync(string userId, string? status = null)
        {
            await _engine.SettleDueAsync(userId);
            var rows = await _bookings.ListForChefAsync(userId);
            return await ViewsAsync(string.IsNullOrWhiteSpace(status) ? rows : rows.Where(b => b.Status == status).ToList());
        }

        public async Task<ComplaintResponse> GetComplaintAsync(string userId, string id)
        {
            var b = await LoadAsync(id);
            PartyOf(b, userId);
            return b.Complaint != null
                ? BookingMapper.Complaint(b, b.Complaint)
                : throw new NotFoundException("Yêu cầu này chưa có khiếu nại.");
        }

        public async Task<BookingResponse> GetAsync(string userId, string id)
        {
            var b = await LoadAsync(id);
            PartyOf(b, userId);
            return await ViewAsync(b);
        }

        /* ---------------------------------------------------------------- chat, đề xuất */

        public async Task<List<MessageResponse>> ListMessagesAsync(string userId, string id, DateTime? after)
        {
            var b = await LoadAsync(id);
            PartyOf(b, userId);
            var cutoff = after?.ToUniversalTime();
            return b.Messages
                .Where(m => cutoff == null || m.CreatedAt > cutoff)
                .OrderBy(m => m.CreatedAt)
                .Select(m => BookingMapper.Message(b, m))
                .ToList();
        }

        public async Task<MessageResponse> SendMessageAsync(string userId, string id, SendMessageRequest request)
        {
            BookingMessage? sent = null;
            var booking = await _engine.MutateAsync(id, (b, now) =>
            {
                var party = PartyOf(b, userId);
                var body = request.Body?.Trim() ?? string.Empty;
                var attachment = string.IsNullOrWhiteSpace(request.AttachmentUrl) ? null : request.AttachmentUrl.Trim();
                if (attachment == null && body.Length == 0) throw Invalid("Nhập tin nhắn.");
                if (body.Length > CommerceRules.MaxMessage) throw Invalid($"Tin nhắn tối đa {CommerceRules.MaxMessage} ký tự.");
                if (attachment != null && !CommerceText.IsMediaUrl(attachment)) throw Invalid("Tệp đính kèm không hợp lệ.");
                if (b.Status is BookingStatuses.Declined or BookingStatuses.Cancelled or BookingStatuses.Expired)
                    throw new ConflictException("Yêu cầu đã đóng, không nhắn thêm được.", "invalid_status");
                sent = BookingLifecycle.Say(b, party, body, now, null, attachment);
                b.UpdatedAt = now;
                return true;
            });
            return BookingMapper.Message(booking, sent!);
        }

        public async Task<BookingResponse> SendOfferAsync(string userId, string id, OfferRequest request)
        {
            var booking = await _engine.MutateAsync(id, (b, now) =>
            {
                var party = PartyOf(b, userId);
                RequirePlanDays(request.PlanDays);
                if (request.Price is not { } price || price < CommerceRules.MinPrice || price > CommerceRules.MaxPrice)
                    throw Invalid($"Giá từ {MoneyMath.Vnd(CommerceRules.MinPrice)} đến {MoneyMath.Vnd(CommerceRules.MaxPrice)}.");
                RequireFutureStart(request.StartDate, out var startDate);
                RequireBookingType(request.BookingType);
                var note = request.Note?.Trim() ?? string.Empty;
                if (note.Length > CommerceRules.MaxOfferNote) throw Invalid($"Lời nhắn tối đa {CommerceRules.MaxOfferNote} ký tự.");
                if (b.Status is not (BookingStatuses.Requested or BookingStatuses.Negotiating))
                    throw new ConflictException("Yêu cầu này không còn thoả thuận giá được.", "invalid_status");

                foreach (var open in b.Offers.Where(o => o.Status == OfferStatuses.Open))
                {
                    open.Status = OfferStatuses.Superseded;
                    open.RespondedAt = now;
                }
                var offer = new BookingOffer
                {
                    Id = BookingLifecycle.NewId(),
                    ProposedBy = party,
                    Price = price,
                    PlanDays = request.PlanDays!.Value,
                    BookingType = request.BookingType!,
                    StartDate = startDate,
                    Note = note,
                    Status = OfferStatuses.Open,
                    CreatedAt = now
                };
                b.Offers.Add(offer);
                b.Status = BookingStatuses.Negotiating;
                b.UpdatedAt = now;
                BookingLifecycle.Say(b, party, note.Length == 0 ? $"Đề xuất giá {MoneyMath.Vnd(price)}" : note, now, offer.Id);
                return true;
            });
            return await ViewAsync(booking);
        }

        public async Task<BookingResponse> RespondToOfferAsync(string userId, string id, string offerId, bool accept)
        {
            var booking = await _engine.MutateAsync(id, (b, now) =>
            {
                var party = PartyOf(b, userId);
                var offer = b.Offers.Count > 0 ? b.Offers[^1] : null;
                if (offer == null || offer.Id != offerId || offer.Status != OfferStatuses.Open)
                    throw new ConflictException("Đề xuất này không còn hiệu lực. Xem đề xuất mới nhất.", "offer_closed");
                if (offer.ProposedBy == party)
                    throw new ConflictException("Bên đưa ra đề xuất không tự đồng ý được.", "own_offer");
                var actorName = party == BookingParties.Chef ? b.ChefName : b.MemberName;
                if (!accept)
                {
                    offer.Status = OfferStatuses.Rejected;
                    offer.RespondedAt = now;
                    b.UpdatedAt = now;
                    BookingLifecycle.Say(b, BookingParties.System, $"{actorName} đã từ chối đề xuất {MoneyMath.Vnd(offer.Price)}.", now);
                    return true;
                }
                if (string.CompareOrdinal(offer.StartDate, VnTime.DateOf(now)) <= 0)
                    throw new ConflictException($"Ngày bắt đầu {VnTime.DayMonth(offer.StartDate)} đã qua. Hãy đề xuất lại ngày bắt đầu.", "start_date_passed");

                offer.Status = OfferStatuses.Accepted;
                offer.RespondedAt = now;
                b.PlanDays = offer.PlanDays;
                b.BookingType = offer.BookingType;
                b.StartDate = offer.StartDate;
                var endDate = VnTime.PlanEndDate(offer.StartDate, offer.PlanDays);
                var dueAt = VnTime.PaymentDueAt(now, offer.StartDate);
                b.Contract = new BookingContract
                {
                    Id = BookingLifecycle.NewId(),
                    OfferId = offer.Id,
                    Price = offer.Price,
                    PlanDays = offer.PlanDays,
                    BookingType = offer.BookingType,
                    StartDate = offer.StartDate,
                    EndDate = endDate,
                    DeliveryDueAt = VnTime.DeliveryDueAt(offer.BookingType, offer.StartDate, now),
                    ScopeText = ScopeText(b, offer),
                    PaymentDueAt = dueAt,
                    CreatedAt = now
                };
                b.Days = Enumerable.Range(1, offer.PlanDays)
                    .Select(i => new BookingPlanDay { DayIndex = i, Date = VnTime.AddDays(offer.StartDate, i - 1) })
                    .ToList();
                b.Order = new BookingOrder
                {
                    Id = BookingLifecycle.NewId(),
                    Amount = offer.Price,
                    Status = OrderStatuses.Pending,
                    CreatedAt = now
                };
                b.Status = BookingStatuses.AwaitingPayment;
                b.UpdatedAt = now;
                BookingLifecycle.Say(b, BookingParties.System,
                    $"{actorName} đã đồng ý đề xuất {MoneyMath.Vnd(offer.Price)}. Hồ sơ hợp đồng đã được tạo, thanh toán trước {VnTime.Stamp(dueAt)}.", now);
                return true;
            });
            return await ViewAsync(booking);
        }

        private static string ScopeText(ChefBooking b, BookingOffer offer)
        {
            var who = b.Audience == BookingAudiences.Family ? $"cho gia đình {b.FamilySize} người" : "theo hồ sơ và nhu cầu của thành viên";
            var avoid = b.Allergies.Count == 0 ? string.Empty
                : $", tránh hoàn toàn: {string.Join(", ", b.Allergies.Select(a => AllergenLabels.TryGetValue(a, out var label) ? label : a))}";
            return $"Thiết kế thực đơn chay {offer.PlanDays} ngày ({BookingTypes.Label(offer.BookingType).ToLowerInvariant()}) {who}: " +
                   $"{b.MealPattern.Count} bữa mỗi ngày, có định lượng và cách làm từng món{avoid}.";
        }

        /* ---------------------------------------------------------------- huỷ, từ chối */

        public async Task<BookingResponse> CancelAsync(string userId, string id, ReasonRequest request)
        {
            var booking = await _engine.MutateAsync(id, (b, now) =>
            {
                Expect(b, userId, BookingParties.Member);
                var reason = request.Reason?.Trim() ?? string.Empty;
                if (reason.Length < CommerceRules.MinCancelReason)
                    throw Invalid($"Cho chuyên gia biết lý do (ít nhất {CommerceRules.MinCancelReason} ký tự).");

                if (b.Escrow != null)
                {
                    BookingLifecycle.CancelPaid(b, reason, now);
                    return true;
                }
                CloseBeforePayment(b, now);
                b.Status = BookingStatuses.Cancelled;
                b.CancelReason = reason;
                BookingLifecycle.Say(b, BookingParties.System, $"{b.MemberName} đã huỷ yêu cầu: \"{reason}\"", now);
                return true;
            });
            return await ViewAsync(booking);
        }

        public async Task<BookingResponse> DeclineAsync(string userId, string id, ReasonRequest request)
        {
            var booking = await _engine.MutateAsync(id, (b, now) =>
            {
                Expect(b, userId, BookingParties.Chef);
                var reason = request.Reason?.Trim() ?? string.Empty;
                if (reason.Length < CommerceRules.MinDeclineReason)
                    throw Invalid($"Lý do cần ít nhất {CommerceRules.MinDeclineReason} ký tự.");
                CloseBeforePayment(b, now);
                b.Status = BookingStatuses.Declined;
                b.DeclineReason = reason;
                BookingLifecycle.Say(b, BookingParties.System, $"{b.ChefName} không đồng ý: \"{reason}\". Yêu cầu đã đóng, thành viên không bị trừ tiền.", now);
                return true;
            });
            return await ViewAsync(booking);
        }

        private static void CloseBeforePayment(ChefBooking b, DateTime now)
        {
            if (b.Status is not (BookingStatuses.Requested or BookingStatuses.Negotiating or BookingStatuses.AwaitingPayment))
                throw new ConflictException("Chỉ huỷ hoặc từ chối được trước khi thanh toán.", "invalid_status");
            foreach (var o in b.Offers.Where(o => o.Status == OfferStatuses.Open))
            {
                o.Status = OfferStatuses.Withdrawn;
                o.RespondedAt = now;
            }
            BookingLifecycle.CancelUnpaidOrder(b);
            b.UpdatedAt = now;
        }

        /* ---------------------------------------------------------------- kế hoạch */

        public async Task<List<PlanDayResponse>> GetPlanAsync(string userId, string id)
        {
            var b = await LoadAsync(id);
            var party = PartyOf(b, userId);
            return b.Days
                .Where(d => party == BookingParties.Chef || d.Status == PlanDayStatuses.Sent)
                .OrderBy(d => d.DayIndex)
                .Select(BookingMapper.PlanDay)
                .ToList();
        }

        private static BookingPlanDay DayOf(ChefBooking b, int dayIndex) =>
            b.Days.FirstOrDefault(d => d.DayIndex == dayIndex) ?? throw new NotFoundException($"Không có ngày {dayIndex} trong kế hoạch.");

        private static void ExpectPlanEditable(ChefBooking b)
        {
            if (b.Status is not (BookingStatuses.Active or BookingStatuses.Ended))
                throw new ConflictException("Chỉ soạn kế hoạch khi đã thanh toán và chưa có khiếu nại.", "invalid_status");
        }

        public async Task<PlanDayResponse> SavePlanDayAsync(string userId, string id, int dayIndex, PlanDayRequest request)
        {
            Expect(await LoadAsync(id), userId, BookingParties.Chef);
            var meals = await BuildMealsAsync(request);
            var note = string.IsNullOrWhiteSpace(request.ChefNote) ? null : request.ChefNote.Trim();
            if (note?.Length > CommerceRules.MaxMessage) throw Invalid($"Ghi chú tối đa {CommerceRules.MaxMessage} ký tự.");

            BookingPlanDay? saved = null;
            await _engine.MutateAsync(id, (b, now) =>
            {
                Expect(b, userId, BookingParties.Chef);
                ExpectPlanEditable(b);
                saved = DayOf(b, dayIndex);
                if (saved.Status == PlanDayStatuses.Sent) throw new ConflictException("Ngày này đã gửi cho thành viên.", "day_sent");
                saved.Meals = meals;
                saved.ChefNote = note;
                saved.Status = PlanDayStatuses.Draft;
                b.UpdatedAt = now;
                return true;
            });
            return BookingMapper.PlanDay(saved!);
        }

        private async Task<List<BookingPlanMeal>> BuildMealsAsync(PlanDayRequest request)
        {
            var result = new List<BookingPlanMeal>();
            foreach (var m in request.Meals ?? new List<PlanMealRequest>())
            {
                var slot = m.Slot?.Trim() ?? string.Empty;
                if (!MealSlots.Contains(slot)) throw Invalid("Bữa ăn không hợp lệ.");
                var recipe = m.Recipe;
                PlanRecipe dish;
                if (string.IsNullOrWhiteSpace(recipe?.Name) && !string.IsNullOrWhiteSpace(m.RecipeId))
                {
                    var stored = ObjectId.TryParse(m.RecipeId, out _) ? await _recipes.FindByIdAsync(m.RecipeId) : null;
                    if (stored == null || stored.IsDeleted) throw Invalid("Không tìm thấy món đã chọn.");
                    dish = new PlanRecipe
                    {
                        Id = stored.Id,
                        Name = stored.Name,
                        Calories = stored.Calories,
                        ProteinG = stored.ProteinG,
                        CarbsG = stored.CarbsG,
                        FatG = stored.FatG,
                        Ingredients = stored.Ingredients,
                        Instructions = string.Join("\n", stored.Instructions)
                    };
                }
                else
                {
                    var name = recipe?.Name?.Trim() ?? string.Empty;
                    if (name.Length < CommerceRules.MinDishName || name.Length > CommerceRules.MaxDishName)
                        throw Invalid($"Tên món từ {CommerceRules.MinDishName} đến {CommerceRules.MaxDishName} ký tự.");
                    dish = new PlanRecipe
                    {
                        Id = m.RecipeId ?? recipe?.Id,
                        Name = name,
                        Calories = recipe?.Calories,
                        ProteinG = recipe?.ProteinG,
                        CarbsG = recipe?.CarbsG,
                        FatG = recipe?.FatG,
                        Ingredients = recipe?.Ingredients?.Where(i => !string.IsNullOrWhiteSpace(i)).Select(i => i.Trim()).ToList() ?? new List<string>(),
                        Instructions = string.IsNullOrWhiteSpace(recipe?.Instructions) ? null : recipe.Instructions.Trim()
                    };
                }
                result.Add(new BookingPlanMeal { Slot = slot, Recipe = dish, Note = string.IsNullOrWhiteSpace(m.Note) ? null : m.Note.Trim() });
            }
            return result;
        }

        private static bool IsComplete(ChefBooking b, BookingPlanDay day) =>
            b.MealPattern.All(slot => day.Meals.Any(m => m.Slot == slot));

        public async Task<PlanDayResponse> SendPlanDayAsync(string userId, string id, int dayIndex)
        {
            BookingPlanDay? sent = null;
            await _engine.MutateAsync(id, (b, now) =>
            {
                Expect(b, userId, BookingParties.Chef);
                ExpectPlanEditable(b);
                if (b.BookingType != BookingTypes.DailyFeedback)
                    throw new ConflictException("Kế hoạch giao một lần: gửi toàn bộ khi đủ các ngày.", "one_shot");
                sent = DayOf(b, dayIndex);
                if (sent.Status == PlanDayStatuses.Sent) throw new ConflictException("Ngày này đã gửi cho thành viên.", "day_sent");
                if (dayIndex > 1 && DayOf(b, dayIndex - 1).Status != PlanDayStatuses.Sent)
                    throw new ConflictException($"Gửi ngày {dayIndex - 1} trước đã.", "previous_day_unsent");
                if (!IsComplete(b, sent)) throw new ConflictException($"Ngày {dayIndex} chưa đủ món cho các bữa.", "day_incomplete");
                sent.Status = PlanDayStatuses.Sent;
                sent.SentAt = now;
                b.UpdatedAt = now;
                BookingLifecycle.Say(b, BookingParties.System, $"{b.ChefName} đã gửi kế hoạch ngày {dayIndex} ({VnTime.DayMonth(sent.Date)}).", now);
                return true;
            });
            return BookingMapper.PlanDay(sent!);
        }

        public async Task<List<PlanDayResponse>> SendWholePlanAsync(string userId, string id)
        {
            var booking = await _engine.MutateAsync(id, (b, now) =>
            {
                Expect(b, userId, BookingParties.Chef);
                ExpectPlanEditable(b);
                if (b.BookingType != BookingTypes.OneShot)
                    throw new ConflictException("Kế hoạch có phản hồi: gửi từng ngày.", "daily");
                if (b.Days.All(d => d.Status == PlanDayStatuses.Sent)) throw new ConflictException("Kế hoạch đã gửi.", "day_sent");
                var missing = b.Days.Count(d => !IsComplete(b, d));
                if (missing > 0) throw new ConflictException($"Còn {missing} ngày chưa đủ món.", "day_incomplete");
                foreach (var d in b.Days.Where(d => d.Status != PlanDayStatuses.Sent))
                {
                    d.Status = PlanDayStatuses.Sent;
                    d.SentAt = now;
                }
                b.UpdatedAt = now;
                BookingLifecycle.Say(b, BookingParties.System, $"{b.ChefName} đã gửi toàn bộ kế hoạch {b.PlanDays} ngày.", now);
                return true;
            });
            return booking.Days.OrderBy(d => d.DayIndex).Select(BookingMapper.PlanDay).ToList();
        }

        public async Task<PlanDayResponse> SendFeedbackAsync(string userId, string id, int dayIndex, DayFeedbackRequest request)
        {
            BookingPlanDay? day = null;
            await _engine.MutateAsync(id, (b, now) =>
            {
                Expect(b, userId, BookingParties.Member);
                if (request.Rating is not { } rating || rating < 1 || rating > 5) throw Invalid("Chọn từ 1 đến 5 sao.");
                if (!Adherences.Contains(request.Adherence)) throw Invalid("Mức làm theo không hợp lệ.");
                var body = request.Body?.Trim() ?? string.Empty;
                if (body.Length > CommerceRules.MaxFeedbackBody) throw Invalid($"Góp ý tối đa {CommerceRules.MaxFeedbackBody} ký tự.");
                if (b.BookingType != BookingTypes.DailyFeedback)
                    throw new ConflictException("Chỉ kế hoạch có phản hồi mỗi ngày mới gửi phản hồi.", "one_shot");
                if (b.Status is not (BookingStatuses.Active or BookingStatuses.Ended))
                    throw new ConflictException("Kế hoạch không còn nhận phản hồi.", "invalid_status");
                day = DayOf(b, dayIndex);
                if (day.Status != PlanDayStatuses.Sent) throw new ConflictException("Chuyên gia chưa gửi ngày này.", "day_not_sent");
                if (string.CompareOrdinal(day.Date, VnTime.DateOf(now)) > 0)
                    throw new ConflictException($"Ngày này chưa diễn ra. Bạn phản hồi từ {VnTime.DayMonth(day.Date)} nhé.", "day_not_started");
                day.Feedback = new DayFeedback { Rating = rating, Adherence = request.Adherence!, Body = body, CreatedAt = now };
                b.UpdatedAt = now;
                BookingLifecycle.Say(b, BookingParties.System, $"{b.MemberName} đã phản hồi ngày {dayIndex}: {rating}★{(body.Length == 0 ? string.Empty : $" · {body}")}", now);
                return true;
            });
            return BookingMapper.PlanDay(day!);
        }

        /* ---------------------------------------------------------------- hoàn thành, khiếu nại */

        public async Task<BookingResponse> ConfirmCompletionAsync(string userId, string id)
        {
            var booking = await _engine.MutateAsync(id, (b, now) =>
            {
                Expect(b, userId, BookingParties.Chef);
                BookingLifecycle.ConfirmCompletion(b, now);
                return true;
            });
            return await ViewAsync(booking);
        }

        public async Task<BookingResponse> FileComplaintAsync(string userId, string id, ComplaintRequest request)
        {
            var booking = await _engine.MutateAsync(id, (b, now) =>
            {
                Expect(b, userId, BookingParties.Member);
                var description = request.Description?.Trim() ?? string.Empty;
                if (description.Length < CommerceRules.MinComplaintDescription) throw Invalid($"Mô tả chi tiết ít nhất {CommerceRules.MinComplaintDescription} ký tự.");
                if (description.Length > CommerceRules.MaxComplaintDescription) throw Invalid($"Tối đa {CommerceRules.MaxComplaintDescription} ký tự.");
                if (!ComplaintReasons.Contains(request.Reason)) throw Invalid("Lý do khiếu nại không hợp lệ.");
                if (request.RequestedOutcome is not ("FullRefund" or "PartialRefund")) throw Invalid("Yêu cầu hoàn tiền không hợp lệ.");

                var evidence = request.Evidence ?? new List<EvidenceRequest>();
                if (request.Reason == "health_risk" && evidence.All(e => e.Kind != "Link"))
                    throw Invalid("Hãy đính kèm nguồn (bài báo, tài liệu y khoa) chứng minh");
                if (evidence.Count == 0) throw Invalid("Thêm ít nhất 1 bằng chứng (liên kết nguồn hoặc ảnh).");
                if (evidence.Count(e => e.Kind == "Image") > CommerceRules.MaxEvidenceImages) throw Invalid($"Tối đa {CommerceRules.MaxEvidenceImages} ảnh.");
                foreach (var e in evidence)
                {
                    if (e.Kind is not ("Link" or "Image")) throw Invalid("Loại bằng chứng không hợp lệ.");
                    if (e.Kind == "Link" ? !CommerceText.IsHttpUrl(e.Url) : !CommerceText.IsMediaUrl(e.Url))
                        throw Invalid("Liên kết bằng chứng phải bắt đầu bằng http:// hoặc https://");
                }

                var price = b.Contract?.Price ?? 0;
                if (request.RequestedOutcome == "PartialRefund" && !MoneyMath.IsValidPartialRefund(request.RequestedAmount, price))
                    throw Invalid($"Số tiền muốn hoàn phải từ {MoneyMath.Vnd(CommerceRules.MinPartialRefund)} và nhỏ hơn giá hợp đồng {MoneyMath.Vnd(price)}.");

                if (b.Complaint != null) throw new ConflictException("Bạn đã gửi khiếu nại cho kế hoạch này.", "not_open");
                var escrow = b.Escrow;
                if (escrow?.ResolvedBy != null) throw new ConflictException("Ban quản trị đã xử lý khoản tiền này nên không khiếu nại được nữa.", "not_open");
                if (escrow == null || escrow.Status != EscrowStatuses.Held || (escrow.ReleaseAt is { } releaseAt && now >= releaseAt))
                    throw new ConflictException("Đã hết hạn khiếu nại, tiền đã được chuyển cho chuyên gia hoặc yêu cầu đã đóng.", "not_open");

                var complaintId = BookingLifecycle.NewId();
                b.Complaint = new BookingComplaint
                {
                    Id = complaintId,
                    Reason = request.Reason!,
                    Description = description,
                    RequestedOutcome = request.RequestedOutcome!,
                    RequestedAmount = request.RequestedOutcome == "FullRefund" ? price : request.RequestedAmount!.Value,
                    Status = ComplaintStatuses.Open,
                    CreatedAt = now,
                    Evidence = evidence.Select(e => new ComplaintEvidence
                    {
                        Id = BookingLifecycle.NewId(),
                        Kind = e.Kind!,
                        Url = e.Url!.Trim(),
                        Caption = string.IsNullOrWhiteSpace(e.Caption) ? null : e.Caption.Trim(),
                        SubmittedBy = BookingParties.Member,
                        CreatedAt = now
                    }).ToList()
                };
                // releaseAt giữ nguyên nhưng không chạy: Settle chỉ nhả tiền khi đang Held.
                escrow.Status = EscrowStatuses.Frozen;
                b.Status = BookingStatuses.Disputed;
                b.UpdatedAt = now;
                BookingLifecycle.Say(b, BookingParties.System, $"{b.MemberName} đã gửi khiếu nại. Tiền được tạm giữ đến khi Ban quản trị quyết định.", now);
                return true;
            });
            return await ViewAsync(booking);
        }

        public async Task<ComplaintResponse> RespondToComplaintAsync(string userId, string id, ComplaintChefResponseRequest request)
        {
            var booking = await _engine.MutateAsync(id, (b, now) =>
            {
                Expect(b, userId, BookingParties.Chef);
                var text = request.Text?.Trim() ?? string.Empty;
                if (text.Length < CommerceRules.MinChefResponse) throw Invalid($"Phản hồi cần ít nhất {CommerceRules.MinChefResponse} ký tự.");
                var links = request.Links ?? new List<EvidenceRequest>();
                if (links.Any(l => !CommerceText.IsHttpUrl(l.Url))) throw Invalid("Liên kết phải bắt đầu bằng http:// hoặc https://");
                var complaint = b.Complaint;
                if (complaint == null || complaint.Status != ComplaintStatuses.Open)
                    throw new ConflictException("Không có khiếu nại đang chờ xử lý.", "no_complaint");
                complaint.ChefResponse = text;
                complaint.ChefRespondedAt = now;
                complaint.Evidence.AddRange(links.Select(l => new ComplaintEvidence
                {
                    Id = BookingLifecycle.NewId(),
                    Kind = "Link",
                    Url = l.Url!.Trim(),
                    Caption = string.IsNullOrWhiteSpace(l.Caption) ? null : l.Caption.Trim(),
                    SubmittedBy = BookingParties.Chef,
                    CreatedAt = now
                }));
                b.UpdatedAt = now;
                BookingLifecycle.Say(b, BookingParties.Chef, text, now);
                return true;
            });
            return BookingMapper.Complaint(booking, booking.Complaint!);
        }
    }
}
