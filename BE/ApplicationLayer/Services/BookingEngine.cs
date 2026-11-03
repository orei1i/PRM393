using System;
using System.Threading;
using System.Threading.Tasks;
using ApplicationLayer.Interfaces;
using DomainLayer.Constants;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Helpers;
using DomainLayer.Interfaces;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace ApplicationLayer.Services
{
    public class BookingEngine : IBookingEngine
    {
        /// <summary>
        /// Một yêu cầu đang chạy có thể đang ở giữa các bước của nó. Khoản trừ dở dang chỉ bị huỷ khi đã quá
        /// khoảng này, để job không giành việc của yêu cầu còn sống.
        /// </summary>
        public static readonly TimeSpan InFlightGrace = TimeSpan.FromMinutes(2);

        private const int MaxAttempts = 12;

        private readonly IBookingRepository _bookings;
        private readonly IWalletLedgerRepository _ledger;
        private readonly IWalletRepository _wallets;
        private readonly IWithdrawalRepository _withdrawals;
        private readonly IWalletLedgerService _ledgerService;
        private readonly IClock _clock;
        private readonly ICommerceFailpoints _failpoints;
        private readonly ILogger<BookingEngine> _logger;

        public BookingEngine(
            IBookingRepository bookings,
            IWalletLedgerRepository ledger,
            IWalletRepository wallets,
            IWithdrawalRepository withdrawals,
            IWalletLedgerService ledgerService,
            IClock clock,
            ICommerceFailpoints failpoints,
            ILogger<BookingEngine> logger)
        {
            _logger = logger;
            _bookings = bookings;
            _ledger = ledger;
            _wallets = wallets;
            _withdrawals = withdrawals;
            _ledgerService = ledgerService;
            _clock = clock;
            _failpoints = failpoints;
        }

        public async Task<ChefBooking?> LoadSettledAsync(string id)
        {
            for (var attempt = 0; attempt < MaxAttempts; attempt++)
            {
                var booking = await _bookings.GetAsync(id);
                if (booking == null) return null;
                if (!BookingLifecycle.Settle(booking, _clock.UtcNow))
                {
                    if (booking.Outbox.Count > 0) await _ledgerService.FlushOutboxAsync(booking);
                    return booking;
                }
                if (await _bookings.TryReplaceAsync(booking))
                {
                    _failpoints.Hit(CommerceFailpointNames.BookingAfterCommit);
                    await _ledgerService.FlushOutboxAsync(booking);
                    return booking;
                }
                await BackoffAsync(attempt);
            }
            throw Busy();
        }

        public async Task<ChefBooking> MutateAsync(string id, Func<ChefBooking, DateTime, bool> mutate)
        {
            for (var attempt = 0; attempt < MaxAttempts; attempt++)
            {
                var booking = await LoadSettledAsync(id) ?? throw new NotFoundException("Không tìm thấy yêu cầu đặt chuyên gia.");
                if (!mutate(booking, _clock.UtcNow)) return booking;
                if (await _bookings.TryReplaceAsync(booking))
                {
                    _failpoints.Hit(CommerceFailpointNames.BookingAfterCommit);
                    await _ledgerService.FlushOutboxAsync(booking);
                    return booking;
                }
                await BackoffAsync(attempt);
            }
            throw Busy();
        }

        public async Task SettleDueAsync(string? userId = null)
        {
            foreach (var id in await _bookings.ListDueIdsAsync(_clock.UtcNow, userId))
            {
                await SafelyAsync(() => LoadSettledAsync(id));
            }
        }

        public async Task ReconcileAsync(string? userId = null)
        {
            var now = _clock.UtcNow;
            var graceLimit = now - InFlightGrace;

            // Trạng thái booking đã đổi nhưng chưa ghi sổ.
            foreach (var id in await _bookings.ListIdsWithOutboxAsync(userId))
            {
                await SafelyAsync(() => LoadSettledAsync(id));
            }

            // Bút toán đã vào sổ nhưng chưa xong.
            foreach (var entry in await _ledger.ListUnappliedAsync(userId))
            {
                await SafelyAsync(async () =>
                {
                    if (await _wallets.ContainsEntryAsync(entry.UserId, entry.Id))
                    {
                        await _ledger.MarkAppliedAsync(entry.Id);
                    }
                    else if (!entry.IsDebit)
                    {
                        await _ledgerService.PostCreditAsync(entry);
                    }
                    else if (entry.CreatedAt <= graceLimit)
                    {
                        // Khoản trừ chưa xảy ra, và người dùng cũng chưa nhận được kết quả thành công.
                        await _ledger.VoidAsync(entry.Id);
                    }
                });
            }

            // Trả bằng ví: đã trừ tiền nhưng booking chưa nhận.
            foreach (var entry in await _ledger.ListOpenWalletPaymentsAsync(userId))
            {
                if (entry.CreatedAt <= graceLimit) await SafelyAsync(() => FinishWalletPaymentAsync(entry));
            }

            // Yêu cầu rút tiền chết giữa chừng.
            foreach (var request in await _withdrawals.ListUnfundedAsync(graceLimit, userId))
            {
                await SafelyAsync(async () =>
                {
                    var holdId = WalletLedgerEntry.IdForKey(LedgerKinds.WithdrawalKey(request.Id, LedgerKinds.WithdrawalHold));
                    if (await _wallets.ContainsEntryAsync(request.UserId, holdId))
                    {
                        await _ledger.MarkAppliedAsync(holdId);
                        await _withdrawals.MarkFundedAsync(request.Id);
                    }
                    else
                    {
                        await _ledger.VoidAsync(holdId);
                        await _withdrawals.DiscardAsync(request.Id, now);
                    }
                });
            }

            // Admin đã duyệt hoặc từ chối nhưng chưa ghi sổ.
            foreach (var request in await _withdrawals.ListUnpostedAsync(userId))
            {
                await SafelyAsync(() => _ledgerService.PostWithdrawalOutcomeAsync(request));
            }
        }

        /// <summary>Một khoản lỗi không được chặn các khoản khác; vòng sau sẽ làm lại. Chỉ ghi loại lỗi, không ghi nội dung.</summary>
        private async Task SafelyAsync(Func<Task> work)
        {
            try
            {
                await work();
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _logger.LogWarning("Một khoản chưa xử lý xong ({ErrorType}), sẽ làm lại ở vòng sau.", ex.GetType().Name);
            }
        }

        public async Task RunOnceAsync()
        {
            await SettleDueAsync();
            await ReconcileAsync();
        }

        public async Task<WalletPaymentOutcome> FinishWalletPaymentAsync(WalletLedgerEntry entry)
        {
            var outcome = WalletPaymentOutcome.Closed;
            await MutateAsync(entry.BookingId!, (b, now) =>
            {
                if (b.Escrow != null && b.Escrow.PaymentId == entry.PaymentId)
                {
                    outcome = WalletPaymentOutcome.Funded;
                    return false;
                }
                if (b.Status != BookingStatuses.AwaitingPayment || b.Order?.Status != OrderStatuses.Pending)
                {
                    outcome = WalletPaymentOutcome.Closed;
                    return false;
                }
                var payment = new BookingPayment
                {
                    Id = entry.PaymentId!,
                    Provider = PaymentProviderNames.Wallet,
                    TransactionRef = entry.TransactionRef ?? string.Empty,
                    Status = PaymentStatuses.Pending,
                    Amount = -entry.DeltaAvailable,
                    ExpiresAt = now,
                    CreatedAt = now
                };
                b.Order.Payments.Add(payment);
                BookingLifecycle.Fund(b, payment, now);
                outcome = WalletPaymentOutcome.Funded;
                return true;
            });

            if (outcome == WalletPaymentOutcome.Closed)
            {
                // Booking đã đóng, hoặc đã có khoản khác trả trước: trả lại tiền vừa trừ.
                var key = LedgerKinds.BookingKey(entry.BookingId!, LedgerKinds.WalletPaymentReversal);
                await _ledgerService.PostCreditAsync(new WalletLedgerEntry
                {
                    Id = WalletLedgerEntry.IdForKey(key),
                    IdempotencyKey = key,
                    UserId = entry.UserId,
                    Kind = LedgerKinds.WalletPaymentReversal,
                    Type = LedgerTypes.Refund,
                    BookingId = entry.BookingId,
                    OrderId = entry.OrderId,
                    PaymentId = entry.PaymentId,
                    TransactionRef = entry.TransactionRef,
                    PlanTitle = entry.PlanTitle,
                    CounterpartName = entry.CounterpartName,
                    DeltaAvailable = -entry.DeltaAvailable,
                    Note = "Hoàn do yêu cầu đã đóng trước khi thanh toán xong",
                    OccurredAt = _clock.UtcNow,
                    CreatedAt = _clock.UtcNow
                });
            }
            await _ledger.MarkSagaDoneAsync(entry.Id);
            return outcome;
        }

        private static Task BackoffAsync(int attempt) => Task.Delay(Random.Shared.Next(5, 20 + attempt * 15));

        private static ConflictException Busy() =>
            new("Hệ thống đang bận với yêu cầu này, vui lòng thử lại.", "conflict_retry");
    }

    /// <summary>Job nền: đến hẹn thì áp quy tắc thời gian và dọn việc dở dang. Quy tắc nằm ở <see cref="BookingEngine"/>.</summary>
    public class CommerceSettlementHostedService : BackgroundService
    {
        private readonly IServiceScopeFactory _scopes;
        private readonly IConfiguration _configuration;
        private readonly ILogger<CommerceSettlementHostedService> _logger;

        public CommerceSettlementHostedService(IServiceScopeFactory scopes, IConfiguration configuration, ILogger<CommerceSettlementHostedService> logger)
        {
            _scopes = scopes;
            _configuration = configuration;
            _logger = logger;
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            if (!_configuration.GetValue("Commerce:SettlementEnabled", true)) return;
            var interval = TimeSpan.FromSeconds(Math.Max(1, _configuration.GetValue("Commerce:SettlementIntervalSeconds", 60)));
            var firstDelay = interval < TimeSpan.FromSeconds(5) ? interval : TimeSpan.FromSeconds(5);

            try
            {
                await Task.Delay(firstDelay, stoppingToken);
                while (!stoppingToken.IsCancellationRequested)
                {
                    try
                    {
                        using var scope = _scopes.CreateScope();
                        await scope.ServiceProvider.GetRequiredService<IBookingEngine>().RunOnceAsync();
                    }
                    catch (Exception ex) when (ex is not OperationCanceledException)
                    {
                        // Chỉ ghi loại lỗi: nội dung lỗi Mongo có thể chứa thông tin kết nối.
                        _logger.LogWarning("Vòng xử lý tiền không chạy xong ({ErrorType}), sẽ thử lại ở vòng sau.", ex.GetType().Name);
                    }
                    await Task.Delay(interval, stoppingToken);
                }
            }
            catch (OperationCanceledException)
            {
                // Máy chủ đang dừng.
            }
        }
    }
}
