using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Commerce;
using ApplicationLayer.Interfaces;
using DomainLayer.Constants;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Helpers;
using DomainLayer.Interfaces;
using MongoDB.Bson;

namespace ApplicationLayer.Services
{
    /// <summary>Các trang Web admin /disputes, /orders, /payouts. Quyền Admin kiểm tra ở controller.</summary>
    public class AdminMoneyService : IAdminMoneyService
    {
        private static readonly Regex TransferRef = new($@"^[A-Za-z0-9._/-]{{{CommerceRules.MinTransferRef},{CommerceRules.MaxTransferRef}}}$", RegexOptions.Compiled);
        private static readonly string[] OrderStatusNames = { OrderStatuses.Pending, OrderStatuses.Paid, OrderStatuses.Cancelled, OrderStatuses.Refunded, OrderStatuses.PartiallyRefunded };
        private static readonly string[] WithdrawalStatusNames = { WithdrawalStatuses.Processing, WithdrawalStatuses.Completed, WithdrawalStatuses.Rejected };
        private static readonly Dictionary<string, string> ReasonLabels = new()
        {
            ["not_as_agreed"] = "Không đúng thoả thuận",
            ["health_risk"] = "Ảnh hưởng sức khoẻ",
            ["late_or_missing"] = "Giao trễ / thiếu ngày",
            ["allergen"] = "Chất gây dị ứng",
            ["other"] = "Khác"
        };

        private readonly IBookingEngine _engine;
        private readonly IBookingRepository _bookings;
        private readonly IWalletRepository _wallets;
        private readonly IWalletLedgerRepository _ledger;
        private readonly IWalletLedgerService _ledgerService;
        private readonly IWithdrawalRepository _withdrawals;
        private readonly IGenericRepository<User> _users;
        private readonly IClock _clock;
        private readonly ICommerceFailpoints _failpoints;

        public AdminMoneyService(
            IBookingEngine engine,
            IBookingRepository bookings,
            IWalletRepository wallets,
            IWalletLedgerRepository ledger,
            IWalletLedgerService ledgerService,
            IWithdrawalRepository withdrawals,
            IGenericRepository<User> users,
            IClock clock,
            ICommerceFailpoints failpoints)
        {
            _engine = engine;
            _bookings = bookings;
            _wallets = wallets;
            _ledger = ledger;
            _ledgerService = ledgerService;
            _withdrawals = withdrawals;
            _users = users;
            _clock = clock;
            _failpoints = failpoints;
        }

        private async Task<string> ActorNameAsync(string adminId)
        {
            var admin = ObjectId.TryParse(adminId, out _) ? await _users.FindByIdAsync(adminId) : null;
            return string.IsNullOrWhiteSpace(admin?.FullName) ? "Quản trị viên" : admin.FullName;
        }

        private static bool Matches(string query, params string?[] fields)
        {
            if (query.Length == 0) return true;
            return CommerceText.Fold(string.Join(" ", fields)).Contains(query, StringComparison.Ordinal);
        }

        private static string Query(string? search) => CommerceText.Fold(search?.Trim());

        /// <summary>Theo thứ tự 400 rồi mới tới trạng thái; thông báo giống form của Web.</summary>
        private static string ValidateDecision(AdminDecisionRequest request, long price)
        {
            if (!ComplaintDecisions.IsValid(request.Decision)) throw new BadRequestException("Chọn cách xử lý.", "validation");
            if (request.Decision == ComplaintDecisions.Split && !MoneyMath.IsValidPartialRefund(request.RefundAmount, price))
                throw new BadRequestException($"Số tiền hoàn phải từ {MoneyMath.Vnd(CommerceRules.MinPartialRefund)} và nhỏ hơn giá hợp đồng {MoneyMath.Vnd(price)}.", "invalid_refund_amount");
            var note = request.Note?.Trim() ?? string.Empty;
            if (note.Length < CommerceRules.MinDecisionNote)
                throw new BadRequestException($"Ghi chú cần ít nhất {CommerceRules.MinDecisionNote} ký tự.", "note_too_short");
            return note;
        }

        /* ---------------------------------------------------------------- khiếu nại */

        public async Task<List<AdminComplaintResponse>> ListComplaintsAsync(string? status, string? search)
        {
            await _engine.SettleDueAsync();
            var q = Query(search);
            var rows = (await _bookings.ListWithComplaintAsync())
                .Where(b => string.IsNullOrWhiteSpace(status) || b.Complaint!.Status == status)
                .Where(b => Matches(q, b.Complaint!.Id, b.Id, b.Order?.Id, b.MemberName, b.MemberEmail, b.ChefName,
                    ReasonLabels.GetValueOrDefault(b.Complaint!.Reason, b.Complaint!.Reason)));
            // Đang mở: cũ trước (hàng đợi). Đã xử lý: quyết định mới trước.
            rows = status == ComplaintStatuses.Open
                ? rows.OrderBy(b => b.Complaint!.CreatedAt)
                : rows.OrderByDescending(b => b.Complaint!.DecidedAt ?? b.Complaint!.CreatedAt);
            return rows.Select(b => BookingMapper.AdminComplaint(b, false)).ToList();
        }

        public async Task<AdminComplaintResponse> GetComplaintAsync(string id)
        {
            var b = await LoadByComplaintAsync(id);
            return BookingMapper.AdminComplaint(b, true);
        }

        private async Task<ChefBooking> LoadByComplaintAsync(string id)
        {
            var found = await _bookings.FindByComplaintIdAsync(id) ?? throw new NotFoundException("Khiếu nại không còn tồn tại.");
            return await _engine.LoadSettledAsync(found.Id) ?? throw new NotFoundException("Khiếu nại không còn tồn tại.");
        }

        public async Task<AdminComplaintResponse> DecideComplaintAsync(string adminId, string id, AdminDecisionRequest request)
        {
            var found = await LoadByComplaintAsync(id);
            var note = ValidateDecision(request, found.Contract?.Price ?? 0);
            var actor = await ActorNameAsync(adminId);

            var booking = await _engine.MutateAsync(found.Id, (b, now) =>
            {
                var complaint = b.Complaint!;
                if (complaint.Status != ComplaintStatuses.Open)
                    throw new ConflictException($"Khiếu nại đã được {complaint.DecidedBy ?? "quản trị viên khác"} xử lý trước đó.", "already_decided");
                BookingLifecycle.ApplyComplaintDecision(b, request.Decision!, request.RefundAmount, note, actor, now);
                return true;
            });
            return BookingMapper.AdminComplaint(booking, true);
        }

        /* ---------------------------------------------------------------- giữ tiền */

        public async Task<EscrowSummaryResponse> GetEscrowSummaryAsync()
        {
            await _engine.SettleDueAsync();
            var now = _clock.UtcNow;
            var monthStart = VnTime.MonthStart(now);
            var rows = await _bookings.ListWithEscrowAsync();
            var holds = rows.Select(b => b.Escrow!).ToList();
            var active = holds.Where(e => e.Status is EscrowStatuses.Held or EscrowStatuses.Frozen).ToList();
            var frozen = holds.Where(e => e.Status == EscrowStatuses.Frozen).ToList();
            var soonLimit = now.AddDays(CommerceRules.ReleasingSoonDays);
            var soon = holds.Where(e => e.Status == EscrowStatuses.Held && e.ReleaseAt is { } r && r <= soonLimit).ToList();
            var awaiting = holds.Where(e => e.Status == EscrowStatuses.Held && e.ReleaseAt == null).ToList();
            var stuck = rows.Where(b => BookingLifecycle.IsStuck(b, now)).ToList();
            var releasedThisMonth = holds.Where(e => e.ReleasedAt is { } r && r >= monthStart && e.ReleasedAmount > 0).ToList();
            var complaints = await _bookings.ListWithComplaintAsync();
            return new EscrowSummaryResponse
            {
                TotalHeld = active.Sum(e => e.Amount),
                TotalHeldCount = active.Count,
                ReleasingSoon = soon.Sum(e => e.Amount),
                ReleasingSoonCount = soon.Count,
                AwaitingCompletion = awaiting.Sum(e => e.Amount),
                AwaitingCompletionCount = awaiting.Count,
                StuckAmount = stuck.Sum(b => b.Escrow!.Amount),
                StuckCount = stuck.Count,
                Frozen = frozen.Sum(e => e.Amount),
                FrozenCount = frozen.Count,
                FeeThisMonth = releasedThisMonth.Sum(e => e.FeeAmount),
                ReleasedThisMonth = releasedThisMonth.Sum(e => e.ReleasedAmount),
                ReleasedThisMonthCount = releasedThisMonth.Count,
                RefundedThisMonth = holds.Where(e => e.RefundedAt is { } r && r >= monthStart).Sum(e => e.RefundedAmount),
                OpenComplaints = complaints.Count(b => b.Complaint!.Status == ComplaintStatuses.Open),
                FeeRate = CommerceRules.FeeRate,
                HoldDays = CommerceRules.HoldDays
            };
        }

        public async Task<List<AdminEscrowHoldResponse>> ListHoldsAsync(string? status, string? search)
        {
            await _engine.SettleDueAsync();
            var now = _clock.UtcNow;
            var q = Query(search);
            static bool IsActive(EscrowHold e) => e.Status is EscrowStatuses.Held or EscrowStatuses.Frozen;
            return (await _bookings.ListWithEscrowAsync())
                .Where(b => string.IsNullOrWhiteSpace(status) || status == "all"
                    || (status == "active" ? IsActive(b.Escrow!)
                        : status == "stuck" ? BookingLifecycle.IsStuck(b, now)
                        : b.Escrow!.Status == status))
                .Where(b => Matches(q, b.Id, b.Order?.Id, b.Complaint?.Id, b.Escrow!.Id, b.MemberName, b.MemberEmail, b.ChefName))
                .OrderByDescending(b => IsActive(b.Escrow!))
                // Đang giữ: sắp chuyển trước, chưa có ngày chuyển xuống cuối. Đã đóng: mới đóng trước.
                .ThenBy(b => IsActive(b.Escrow!) ? b.Escrow!.ReleaseAt ?? DateTime.MaxValue : DateTime.MaxValue)
                .ThenByDescending(b => b.Escrow!.ReleasedAt ?? b.Escrow!.RefundedAt ?? b.Escrow!.HeldAt)
                .Select(b => BookingMapper.Hold(b, now))
                .ToList();
        }

        public async Task<EscrowResponse> ResolveHoldAsync(string adminId, string id, AdminDecisionRequest request)
        {
            var found = await _bookings.FindByEscrowIdAsync(id) ?? throw new NotFoundException("Khoản giữ tiền không còn tồn tại.");
            var note = ValidateDecision(request, found.Contract?.Price ?? 0);
            var actor = await ActorNameAsync(adminId);

            var booking = await _engine.MutateAsync(found.Id, (b, now) =>
            {
                if (!BookingLifecycle.IsStuck(b, now))
                    throw new ConflictException(
                        b.Escrow!.ResolvedBy != null ? $"Khoản này đã được {b.Escrow.ResolvedBy} xử lý trước đó." : "Khoản này không còn chờ Ban quản trị xử lý.",
                        "not_stuck");
                BookingLifecycle.ResolveHold(b, request.Decision!, request.RefundAmount, note, actor, now);
                return true;
            });
            return BookingMapper.Escrow(booking, booking.Escrow!);
        }

        /* ---------------------------------------------------------------- đơn */

        public async Task<CommerceSummaryResponse> GetCommerceSummaryAsync()
        {
            await _engine.SettleDueAsync();
            var rows = await _bookings.ListWithOrderAsync();
            var byStatus = OrderStatusNames.ToDictionary(s => s, _ => 0);
            long revenue = 0, refunded = 0, pending = 0, held = 0;
            var heldCount = 0;
            foreach (var b in rows)
            {
                var o = b.Order!;
                byStatus[o.Status] = byStatus.GetValueOrDefault(o.Status) + 1;
                if (o.Status is OrderStatuses.Paid or OrderStatuses.PartiallyRefunded or OrderStatuses.Refunded) revenue += o.Amount - o.RefundedAmount;
                refunded += o.RefundedAmount;
                if (o.Status == OrderStatuses.Pending) pending += o.Amount;
                if (b.Escrow?.Status is EscrowStatuses.Held or EscrowStatuses.Frozen)
                {
                    held += b.Escrow.Amount;
                    heldCount++;
                }
            }
            return new CommerceSummaryResponse
            {
                Revenue = revenue,
                RefundedAmount = refunded,
                PendingAmount = pending,
                TotalOrders = rows.Count,
                ByStatus = byStatus,
                HeldAmount = held,
                HeldCount = heldCount
            };
        }

        public async Task<List<AdminOrderResponse>> ListOrdersAsync(string? status, string? search)
        {
            await _engine.SettleDueAsync();
            var now = _clock.UtcNow;
            var q = Query(search);
            return (await _bookings.ListWithOrderAsync())
                .Where(b => string.IsNullOrWhiteSpace(status) || status == "all" || b.Order!.Status == status)
                .Where(b => Matches(q, new[] { b.Order!.Id, b.Id, b.MemberName, b.MemberEmail, b.ChefName, b.Complaint?.Id }
                    .Concat(b.Order.Payments.Select(p => p.TransactionRef)).ToArray()))
                .OrderByDescending(b => b.Order!.CreatedAt)
                .Select(b => BookingMapper.AdminOrder(b, now))
                .ToList();
        }

        private async Task<ChefBooking> LoadByOrderAsync(string id)
        {
            var found = await _bookings.FindByOrderIdAsync(id) ?? throw new NotFoundException("Đơn hàng không còn tồn tại.");
            return await _engine.LoadSettledAsync(found.Id) ?? throw new NotFoundException("Đơn hàng không còn tồn tại.");
        }

        public async Task<AdminOrderResponse> GetOrderAsync(string id)
        {
            var b = await LoadByOrderAsync(id);
            return BookingMapper.AdminOrder(b, _clock.UtcNow);
        }

        public async Task<AdminOrderResponse> CancelOrderAsync(string adminId, string id, AdminOrderCancelRequest request)
        {
            var note = request.Note?.Trim() ?? string.Empty;
            if (note.Length < CommerceRules.MinAuditNote)
                throw new BadRequestException($"Ghi chú cần ít nhất {CommerceRules.MinAuditNote} ký tự.", "note_too_short");
            var found = await LoadByOrderAsync(id);
            var actor = await ActorNameAsync(adminId);

            var booking = await _engine.MutateAsync(found.Id, (b, now) =>
            {
                var order = b.Order!;
                if (order.Status != OrderStatuses.Pending || b.Status != BookingStatuses.AwaitingPayment)
                    throw new ConflictException("Chỉ huỷ được đơn đang chờ thanh toán.", "not_pending");
                BookingLifecycle.CancelUnpaidOrder(b);
                order.Resolution = new OrderResolution { Action = "cancel", Note = note, By = actor, At = now };
                b.Status = BookingStatuses.Cancelled;
                b.CancelReason = note;
                b.UpdatedAt = now;
                BookingLifecycle.Say(b, BookingParties.System, $"Ban quản trị đã huỷ đơn thanh toán: \"{note}\"", now);
                return true;
            });
            return BookingMapper.AdminOrder(booking, _clock.UtcNow);
        }

        /* ---------------------------------------------------------------- rút tiền */

        public async Task<List<AdminWithdrawalResponse>> ListWithdrawalsAsync(string? status, string? role, string? search)
        {
            await _engine.ReconcileAsync();
            var q = Query(search);
            var rows = (await _withdrawals.ListAllAsync())
                .Where(w => string.IsNullOrWhiteSpace(status) || w.Status == status)
                .Where(w => string.IsNullOrWhiteSpace(role) || role == "all" || w.Role == role)
                .Where(w => Matches(q, w.Id, w.UserName, w.UserEmail, w.BankName, w.AccountNumber, w.AccountHolder, w.TransactionRef));
            // Chờ duyệt: cũ trước. Còn lại: xử lý mới trước.
            return rows
                .OrderByDescending(w => w.Status == WithdrawalStatuses.Processing)
                .ThenBy(w => w.Status == WithdrawalStatuses.Processing ? w.CreatedAt : DateTime.MaxValue)
                .ThenByDescending(w => w.ProcessedAt ?? w.CreatedAt)
                .Select(BookingMapper.AdminWithdrawal)
                .ToList();
        }

        private async Task<AdminWithdrawalResponse> DecideWithdrawalAsync(string adminId, string id, string status, string? transactionRef, string? reason)
        {
            var actor = await ActorNameAsync(adminId);
            var decided = await _withdrawals.TryDecideAsync(id, status, actor, _clock.UtcNow, transactionRef, reason);
            if (decided == null)
            {
                var current = await _withdrawals.GetAsync(id) ?? throw new NotFoundException("Yêu cầu rút tiền không còn tồn tại.");
                throw new ConflictException(
                    current.Status == WithdrawalStatuses.Completed ? "Yêu cầu đã được chuyển tiền trước đó." : "Yêu cầu đã bị từ chối trước đó.",
                    "already_processed");
            }
            _failpoints.Hit(CommerceFailpointNames.WithdrawalAfterDecision);
            await _ledgerService.PostWithdrawalOutcomeAsync(decided);
            return BookingMapper.AdminWithdrawal(decided);
        }

        public Task<AdminWithdrawalResponse> CompleteWithdrawalAsync(string adminId, string id, WithdrawalCompleteRequest request)
        {
            var reference = request.TransactionRef?.Trim() ?? string.Empty;
            if (!TransferRef.IsMatch(reference))
                throw new BadRequestException($"Mã giao dịch gồm {CommerceRules.MinTransferRef}–{CommerceRules.MaxTransferRef} ký tự: chữ, số và . _ / -", "invalid_transaction_ref");
            return DecideWithdrawalAsync(adminId, id, WithdrawalStatuses.Completed, reference, null);
        }

        public Task<AdminWithdrawalResponse> RejectWithdrawalAsync(string adminId, string id, WithdrawalRejectRequest request)
        {
            var reason = request.Reason?.Trim() ?? string.Empty;
            if (reason.Length < CommerceRules.MinAuditNote)
                throw new BadRequestException($"Lý do cần ít nhất {CommerceRules.MinAuditNote} ký tự.", "reason_too_short");
            return DecideWithdrawalAsync(adminId, id, WithdrawalStatuses.Rejected, null, reason);
        }

        /* ---------------------------------------------------------------- ví */

        /// <summary>Mọi chuyên gia, cộng thành viên có tiền hoàn, trả bằng ví hoặc yêu cầu rút. Mỗi user một dòng.</summary>
        private async Task<List<AdminWalletResponse>> BuildWalletsAsync()
        {
            var escrows = await _bookings.ListWithEscrowAsync();
            var ledger = await _ledger.ListByTypesAsync(LedgerTypes.Refund, LedgerTypes.Payment);
            var withdrawals = await _withdrawals.ListAllAsync();
            var wallets = (await _wallets.ListAsync()).ToDictionary(w => w.Id);
            var chefs = (await _users.FindAsync(u => u.Role == "Chef" && !u.IsDeleted)).ToList();

            var memberIds = ledger.Where(e => e.Applied).Select(e => e.UserId)
                .Concat(withdrawals.Select(w => w.UserId))
                .Distinct()
                .Where(id => chefs.All(c => c.Id != id))
                .ToList();
            var members = memberIds.Count == 0
                ? new List<User>()
                : (await _users.FindAsync(u => memberIds.Contains(u.Id))).ToList();

            var rows = new List<AdminWalletResponse>();
            foreach (var user in chefs.Concat(members))
            {
                wallets.TryGetValue(user.Id, out var wallet);
                var isChef = user.Role == "Chef";
                var mine = escrows.Where(b => b.ChefId == user.Id).Select(b => b.Escrow!).ToList();
                var live = mine.Where(e => e.Status != EscrowStatuses.Refunded).ToList();
                var mineLedger = ledger.Where(e => e.UserId == user.Id && e.Applied).ToList();
                rows.Add(new AdminWalletResponse
                {
                    UserId = user.Id,
                    Role = isChef ? WalletRoles.Chef : WalletRoles.Member,
                    User = new PersonResponse { Id = user.Id, FullName = user.FullName ?? string.Empty, Email = user.Email ?? string.Empty },
                    Available = wallet?.Available ?? 0,
                    Processing = wallet?.Processing ?? 0,
                    Withdrawn = wallet?.Withdrawn ?? 0,
                    Pending = isChef ? mine.Where(e => e.Status == EscrowStatuses.Held).Sum(e => MoneyMath.Net(e.Amount)) : 0,
                    Frozen = isChef ? mine.Where(e => e.Status == EscrowStatuses.Frozen).Sum(e => MoneyMath.Net(e.Amount)) : 0,
                    GrossSales = isChef ? live.Sum(GrossOf) : 0,
                    FeeTotal = isChef ? live.Sum(e => e.Status is EscrowStatuses.Released or EscrowStatuses.PartiallyRefunded ? e.FeeAmount : MoneyMath.Fee(e.Amount)) : 0,
                    RefundTotal = mineLedger.Where(e => e.Type == LedgerTypes.Refund).Sum(e => e.DeltaAvailable),
                    WalletPaymentTotal = -mineLedger.Where(e => e.Type == LedgerTypes.Payment).Sum(e => e.DeltaAvailable),
                    BankAccount = BookingMapper.Bank(wallet?.BankAccount),
                    LastWithdrawalAt = withdrawals
                        .Where(w => w.UserId == user.Id && w.Status == WithdrawalStatuses.Completed)
                        .Select(w => w.ProcessedAt ?? w.CreatedAt)
                        .OrderByDescending(d => d)
                        .Select(d => (DateTime?)d)
                        .FirstOrDefault()
                });
            }
            return rows;
        }

        private static long GrossOf(EscrowHold e) =>
            e.Status is EscrowStatuses.Released or EscrowStatuses.PartiallyRefunded ? e.ReleasedAmount : e.Amount;

        public async Task<List<AdminWalletResponse>> ListWalletsAsync()
        {
            await _engine.RunOnceAsync();
            return (await BuildWalletsAsync())
                .OrderByDescending(w => w.Available + w.Processing)
                .ThenBy(w => CommerceText.Fold(w.User.FullName), StringComparer.Ordinal)
                .ToList();
        }

        public async Task<List<WalletTransactionResponse>> ListWalletTransactionsAsync(string userId, int? limit)
        {
            await _engine.RunOnceAsync();
            var user = ObjectId.TryParse(userId, out _) ? await _users.FindByIdAsync(userId) : null;
            if (user == null || user.IsDeleted) throw new NotFoundException("Không tìm thấy ví của người dùng.");
            var rows = BookingMapper.Transactions(
                await _bookings.ListWithEscrowAsync(userId),
                await _ledger.ListForUserAsync(userId),
                await _withdrawals.ListForUserAsync(userId));
            return rows.Take(Math.Clamp(limit ?? 8, 1, 200)).ToList();
        }

        public async Task<PayoutSummaryResponse> GetPayoutSummaryAsync()
        {
            await _engine.RunOnceAsync();
            var now = _clock.UtcNow;
            var monthStart = VnTime.MonthStart(now);
            var wallets = await BuildWalletsAsync();
            var withdrawals = await _withdrawals.ListAllAsync();
            var released = (await _bookings.ListWithEscrowAsync())
                .Select(b => b.Escrow!)
                .Where(e => e.Status is EscrowStatuses.Released or EscrowStatuses.PartiallyRefunded)
                .ToList();
            var paidThisMonth = withdrawals.Where(w => w.Status == WithdrawalStatuses.Completed && w.ProcessedAt is { } p && p >= monthStart).ToList();
            var awaiting = withdrawals.Where(w => w.Status == WithdrawalStatuses.Processing).ToList();

            Dictionary<string, int> Counts(IEnumerable<WithdrawalRequest> list)
            {
                var items = list.ToList();
                return WithdrawalStatusNames.ToDictionary(s => s, s => items.Count(w => w.Status == s));
            }

            return new PayoutSummaryResponse
            {
                TotalAvailable = wallets.Sum(w => w.Available),
                AvailableByRole = new Dictionary<string, long>
                {
                    [WalletRoles.Member] = wallets.Where(w => w.Role == WalletRoles.Member).Sum(w => w.Available),
                    [WalletRoles.Chef] = wallets.Where(w => w.Role == WalletRoles.Chef).Sum(w => w.Available)
                },
                TotalPending = wallets.Sum(w => w.Pending),
                TotalFrozen = wallets.Sum(w => w.Frozen),
                TotalProcessing = wallets.Sum(w => w.Processing),
                PaidOutThisMonth = paidThisMonth.Sum(w => w.Amount),
                PaidOutThisMonthCount = paidThisMonth.Count,
                PlatformFee = released.Sum(e => e.FeeAmount),
                ReleasedGross = released.Sum(e => e.ReleasedAmount),
                ReleasedCount = released.Count,
                FeeRate = CommerceRules.FeeRate,
                ByStatus = Counts(withdrawals),
                ByRole = new Dictionary<string, Dictionary<string, int>>
                {
                    [WalletRoles.Member] = Counts(withdrawals.Where(w => w.Role == WalletRoles.Member)),
                    [WalletRoles.Chef] = Counts(withdrawals.Where(w => w.Role == WalletRoles.Chef))
                },
                AwaitingApproval = awaiting.Count,
                AwaitingApprovalAmount = awaiting.Sum(w => w.Amount)
            };
        }
    }
}
