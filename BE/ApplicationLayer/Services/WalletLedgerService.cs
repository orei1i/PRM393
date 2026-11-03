using System.Linq;
using System.Threading.Tasks;
using ApplicationLayer.Interfaces;
using DomainLayer.Constants;
using DomainLayer.Entities;
using DomainLayer.Helpers;
using DomainLayer.Interfaces;
using Microsoft.Extensions.Logging;

namespace ApplicationLayer.Services
{
    /// <summary>
    /// Không có transaction nhiều document, nên chuyển tiền đi theo thứ tự cố định:
    /// 1. ghi bút toán vào sổ, khoá chống trùng là (booking, loại): bản thứ hai bị Mongo từ chối;
    /// 2. một lần ghi nguyên tử trên ví: đổi số dư và thêm id bút toán, có điều kiện id chưa có và không âm;
    /// 3. đánh dấu bút toán đã áp dụng.
    /// Chết ở đâu thì job làm tiếp từ đó (<see cref="BookingEngine.ReconcileAsync"/>), và làm lại cũng không cộng hai lần.
    /// </summary>
    public class WalletLedgerService : IWalletLedgerService
    {
        private readonly IWalletLedgerRepository _ledger;
        private readonly IWalletRepository _wallets;
        private readonly IBookingRepository _bookings;
        private readonly IWithdrawalRepository _withdrawals;
        private readonly IClock _clock;
        private readonly ICommerceFailpoints _failpoints;
        private readonly ILogger<WalletLedgerService> _logger;

        public WalletLedgerService(
            IWalletLedgerRepository ledger,
            IWalletRepository wallets,
            IBookingRepository bookings,
            IWithdrawalRepository withdrawals,
            IClock clock,
            ICommerceFailpoints failpoints,
            ILogger<WalletLedgerService> logger)
        {
            _ledger = ledger;
            _wallets = wallets;
            _bookings = bookings;
            _withdrawals = withdrawals;
            _clock = clock;
            _failpoints = failpoints;
            _logger = logger;
        }

        public async Task PostCreditAsync(WalletLedgerEntry entry)
        {
            var inserted = await _ledger.TryInsertAsync(entry);
            _failpoints.Hit(CommerceFailpointNames.LedgerAfterInsert);
            var current = inserted ? entry : await _ledger.GetAsync(entry.Id) ?? entry;
            if (current.Applied) return;

            await _wallets.EnsureAsync(current.UserId, _clock.UtcNow);
            var result = await _wallets.TryApplyAsync(current, _clock.UtcNow);
            _failpoints.Hit(CommerceFailpointNames.LedgerAfterApply);
            if (result == WalletApplyResult.Insufficient)
            {
                // Chỉ xảy ra nếu sổ sai lệch: để lại chưa áp dụng cho vòng sau, không tự sửa tiền.
                _logger.LogError("Bút toán {EntryId} không áp dụng được vào ví {UserId}.", current.Id, current.UserId);
                return;
            }
            await _ledger.MarkAppliedAsync(current.Id);
        }

        public async Task<bool> TryDebitAsync(WalletLedgerEntry entry)
        {
            var inserted = await _ledger.TryInsertAsync(entry);
            _failpoints.Hit(CommerceFailpointNames.LedgerAfterInsert);
            var current = inserted ? entry : await _ledger.GetAsync(entry.Id) ?? entry;
            if (current.Applied) return true;
            if (current.Voided) await _ledger.ReviveAsync(current.Id);

            await _wallets.EnsureAsync(current.UserId, _clock.UtcNow);
            var result = await _wallets.TryApplyAsync(current, _clock.UtcNow);
            _failpoints.Hit(CommerceFailpointNames.LedgerAfterApply);
            if (result == WalletApplyResult.Insufficient)
            {
                await _ledger.VoidAsync(current.Id);
                return false;
            }
            await _ledger.MarkAppliedAsync(current.Id);
            return true;
        }

        public async Task FlushOutboxAsync(ChefBooking booking)
        {
            foreach (var intent in booking.Outbox.ToList())
            {
                await PostCreditAsync(FromIntent(booking, intent));
                await _bookings.RemoveOutboxEntryAsync(booking.Id, intent.Key);
                booking.Outbox.Remove(intent);
                booking.Version++;
            }
        }

        public async Task PostWithdrawalOutcomeAsync(WithdrawalRequest request)
        {
            var completed = request.Status == WithdrawalStatuses.Completed;
            var kind = completed ? LedgerKinds.WithdrawalComplete : LedgerKinds.WithdrawalReject;
            var key = LedgerKinds.WithdrawalKey(request.Id, kind);
            await PostCreditAsync(new WalletLedgerEntry
            {
                Id = WalletLedgerEntry.IdForKey(key),
                IdempotencyKey = key,
                UserId = request.UserId,
                Kind = kind,
                Type = LedgerTypes.Withdrawal,
                WithdrawalId = request.Id,
                DeltaProcessing = -request.Amount,
                DeltaWithdrawn = completed ? request.Amount : 0,
                DeltaAvailable = completed ? 0 : request.Amount,
                OccurredAt = request.ProcessedAt ?? _clock.UtcNow,
                CreatedAt = _clock.UtcNow
            });
            await _withdrawals.MarkPostedAsync(request.Id);
        }

        private WalletLedgerEntry FromIntent(ChefBooking b, LedgerIntent intent) => new()
        {
            Id = WalletLedgerEntry.IdForKey(intent.Key),
            IdempotencyKey = intent.Key,
            UserId = intent.UserId,
            Kind = intent.Kind,
            Type = intent.Type,
            BookingId = b.Id,
            OrderId = b.Order?.Id,
            ComplaintId = intent.ComplaintId,
            PaymentId = intent.PaymentId,
            TransactionRef = intent.TransactionRef,
            PlanTitle = BookingLifecycle.PlanTitle(b.PlanDays, b.BookingType),
            CounterpartName = intent.CounterpartName,
            Gross = intent.Gross,
            Fee = intent.Fee,
            DeltaAvailable = intent.Net,
            Note = intent.Note,
            OccurredAt = intent.OccurredAt,
            CreatedAt = _clock.UtcNow
        };
    }
}
