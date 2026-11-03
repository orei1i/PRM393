using System;
using System.Linq;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Commerce;
using ApplicationLayer.Interfaces;
using DomainLayer.Constants;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Helpers;
using DomainLayer.Interfaces;

namespace ApplicationLayer.Services
{
    /// <summary>
    /// Đơn và thanh toán. Không có webhook: chưa có cổng thật nên không tự đặt ra secret nào, và không có route
    /// không xác thực nào đánh dấu đơn đã trả. Cách trả tiền hiện có: bằng ví, hoặc cổng Sandbox do Admin xác nhận.
    /// </summary>
    public class OrderPaymentService : IOrderPaymentService
    {
        private readonly IBookingEngine _engine;
        private readonly IBookingRepository _bookings;
        private readonly IWalletLedgerService _ledgerService;
        private readonly IWalletLedgerRepository _ledger;
        private readonly IPaymentProvider _provider;
        private readonly IClock _clock;
        private readonly ICommerceFailpoints _failpoints;

        public OrderPaymentService(
            IBookingEngine engine,
            IBookingRepository bookings,
            IWalletLedgerService ledgerService,
            IWalletLedgerRepository ledger,
            IPaymentProvider provider,
            IClock clock,
            ICommerceFailpoints failpoints)
        {
            _engine = engine;
            _bookings = bookings;
            _ledgerService = ledgerService;
            _ledger = ledger;
            _provider = provider;
            _clock = clock;
            _failpoints = failpoints;
        }

        private static ConflictException NotAwaitingPayment(ChefBooking b) => new(
            b.Status == BookingStatuses.Expired ? "Đã quá hạn thanh toán. Gửi yêu cầu mới cho chuyên gia nhé." : "Yêu cầu này không còn chờ thanh toán.",
            "not_awaiting_payment");

        private async Task<ChefBooking> LoadBuyersOrderAsync(string userId, string orderId)
        {
            var found = await _bookings.FindByOrderIdAsync(orderId);
            if (found == null || found.MemberId != userId) throw new NotFoundException(CommerceMessages.OrderNotFound);
            return await _engine.LoadSettledAsync(found.Id) ?? throw new NotFoundException(CommerceMessages.OrderNotFound);
        }

        public async Task<OrderResponse> StartBookingPaymentAsync(string userId, string bookingId)
        {
            var b = await _engine.LoadSettledAsync(bookingId) ?? throw new NotFoundException(CommerceMessages.BookingNotFound);
            if (b.MemberId != userId)
            {
                if (b.ChefId == userId) throw new ForbiddenException("Chỉ thành viên đặt yêu cầu này làm được thao tác này.", "wrong_party");
                throw new NotFoundException(CommerceMessages.BookingNotFound);
            }
            b = await EnsureOpenQrAsync(b);
            return BookingMapper.Order(b, _clock.UtcNow);
        }

        public async Task<OrderResponse> GetOrderAsync(string userId, string orderId)
        {
            var b = await LoadBuyersOrderAsync(userId, orderId);
            return BookingMapper.Order(b, _clock.UtcNow);
        }

        public async Task<PaymentResponse> RenewPaymentAsync(string userId, string orderId)
        {
            var b = await LoadBuyersOrderAsync(userId, orderId);
            b = await EnsureOpenQrAsync(b);
            var now = _clock.UtcNow;
            return BookingMapper.Payment(b.Order!, b.Order!.Payments[^1], now);
        }

        public async Task<PaymentResponse> GetPaymentAsync(string userId, string paymentId)
        {
            var found = await _bookings.FindByPaymentIdAsync(paymentId);
            if (found == null || found.MemberId != userId) throw new NotFoundException(CommerceMessages.PaymentNotFound);
            var b = await _engine.LoadSettledAsync(found.Id) ?? throw new NotFoundException(CommerceMessages.PaymentNotFound);
            var order = b.Order!;
            var payment = order.Payments.First(p => p.Id == paymentId);
            return BookingMapper.Payment(order, payment, _clock.UtcNow);
        }

        /// <summary>QR đang mở thì dùng lại, nên bấm đúp không tạo thêm giao dịch. Một QR không sống quá hạn thanh toán.</summary>
        private async Task<ChefBooking> EnsureOpenQrAsync(ChefBooking b)
        {
            if (b.Status != BookingStatuses.AwaitingPayment || b.Order?.Status != OrderStatuses.Pending) throw NotAwaitingPayment(b);
            if (HasOpenQr(b, _clock.UtcNow)) return b;
            if (!_provider.IsConfigured)
                throw new ServiceUnavailableException(CommerceMessages.NoPaymentProvider, "payment_unavailable");

            var now = _clock.UtcNow;
            var ttl = TimeSpan.FromMinutes(CommerceRules.QrTtlMinutes);
            var left = b.Contract!.PaymentDueAt - now;
            if (left < ttl) ttl = left;
            var expiresAt = now + ttl;
            var session = await _provider.OpenAsync(b.Order.Id, b.Order.Amount, expiresAt);

            return await _engine.MutateAsync(b.Id, (fresh, at) =>
            {
                if (fresh.Status != BookingStatuses.AwaitingPayment || fresh.Order?.Status != OrderStatuses.Pending) throw NotAwaitingPayment(fresh);
                if (HasOpenQr(fresh, at)) return false;
                foreach (var stale in fresh.Order.Payments.Where(p => p.Status == PaymentStatuses.Pending)) stale.Status = PaymentStatuses.Expired;
                fresh.Order.Payments.Add(new BookingPayment
                {
                    Id = BookingLifecycle.NewId(),
                    Provider = _provider.Name,
                    TransactionRef = session.TransactionRef,
                    QrCodeUrl = session.QrCodeUrl,
                    Status = PaymentStatuses.Pending,
                    Amount = fresh.Order.Amount,
                    ExpiresAt = expiresAt,
                    CreatedAt = at
                });
                fresh.UpdatedAt = at;
                return true;
            });
        }

        private static bool HasOpenQr(ChefBooking b, DateTime now)
        {
            var latest = b.Order!.Payments.Count > 0 ? b.Order.Payments[^1] : null;
            return latest != null && BookingMapper.EffectivePaymentStatus(latest, now) == PaymentStatuses.Pending;
        }

        /// <summary>
        /// Trả nguyên giá từ ví. Thứ tự: trừ ví có điều kiện (khoá riêng theo booking) rồi mới đổi booking.
        /// Bấm đúp hoặc gọi lại đi vào cùng một bút toán nên chỉ trừ một lần; chết giữa hai bước thì job làm nốt.
        /// </summary>
        public async Task<OrderResponse> PayWithWalletAsync(string userId, string orderId)
        {
            var b = await LoadBuyersOrderAsync(userId, orderId);
            if (b.Status != BookingStatuses.AwaitingPayment || b.Order!.Status != OrderStatuses.Pending) throw NotAwaitingPayment(b);

            var now = _clock.UtcNow;
            var key = LedgerKinds.BookingKey(b.Id, LedgerKinds.WalletPayment);
            var entry = new WalletLedgerEntry
            {
                Id = WalletLedgerEntry.IdForKey(key),
                IdempotencyKey = key,
                UserId = userId,
                Kind = LedgerKinds.WalletPayment,
                Type = LedgerTypes.Payment,
                BookingId = b.Id,
                OrderId = b.Order.Id,
                PaymentId = BookingLifecycle.NewId(),
                TransactionRef = CommerceText.NewTransactionRef(now),
                PlanTitle = BookingLifecycle.PlanTitle(b.PlanDays, b.BookingType),
                CounterpartName = b.ChefName,
                DeltaAvailable = -b.Order.Amount,
                OccurredAt = now,
                CreatedAt = now
            };

            if (!await _ledgerService.TryDebitAsync(entry))
                throw new ConflictException("Số dư ví không đủ để thanh toán.", "insufficient_balance");
            _failpoints.Hit(CommerceFailpointNames.WalletPayAfterDebit);

            // Có thể yêu cầu khác đã ghi bút toán này trước: dùng đúng paymentId đã lưu.
            var stored = await _ledger.GetAsync(entry.Id) ?? entry;
            var outcome = await _engine.FinishWalletPaymentAsync(stored);
            b = await _engine.LoadSettledAsync(b.Id) ?? b;
            if (outcome == WalletPaymentOutcome.Closed) throw NotAwaitingPayment(b);
            return BookingMapper.Order(b, _clock.UtcNow);
        }

        /// <summary>Chỉ cổng Sandbox, không có tiền thật. buyerId null là Admin (quyền kiểm tra ở controller).</summary>
        public async Task<PaymentResponse> SandboxConfirmAsync(string paymentId, bool success, string? buyerId = null)
        {
            if (_provider.Name != PaymentProviderNames.Sandbox) throw new NotFoundException(CommerceMessages.PaymentNotFound);
            var found = await _bookings.FindByPaymentIdAsync(paymentId) ?? throw new NotFoundException(CommerceMessages.PaymentNotFound);
            if (buyerId != null && found.MemberId != buyerId) throw new NotFoundException(CommerceMessages.PaymentNotFound);

            var booking = await _engine.MutateAsync(found.Id, (b, now) =>
            {
                var order = b.Order!;
                var payment = order.Payments.First(p => p.Id == paymentId);
                if (payment.Provider != PaymentProviderNames.Sandbox)
                    throw new ConflictException("Giao dịch này không thuộc cổng thử nghiệm.", "not_sandbox");
                if (payment.Status == PaymentStatuses.Paid) return false;

                var effective = BookingMapper.EffectivePaymentStatus(payment, now);
                if (!success)
                {
                    if (effective != PaymentStatuses.Pending) return false;
                    payment.Status = PaymentStatuses.Failed;
                    b.UpdatedAt = now;
                    return true;
                }

                if (b.Status == BookingStatuses.AwaitingPayment && order.Status == OrderStatuses.Pending)
                {
                    if (effective == PaymentStatuses.Expired) throw new ConflictException("Mã QR đã hết hạn.", "payment_expired");
                    if (effective == PaymentStatuses.Failed) throw new ConflictException("Giao dịch này đã thất bại, hãy tạo mã mới.", "payment_failed");
                    BookingLifecycle.Fund(b, payment, now);
                    return true;
                }

                // Tiền về khi booking đã đóng hoặc đã có khoản khác trả: hoàn vào ví, khoá theo từng thanh toán.
                BookingLifecycle.RefundLatePayment(b, payment, now);
                return true;
            });

            var result = booking.Order!.Payments.First(p => p.Id == paymentId);
            return BookingMapper.Payment(booking.Order, result, _clock.UtcNow);
        }
    }
}
