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

namespace ApplicationLayer.Services
{
    /// <summary>Ví của user. Mỗi user một ví, route thành viên và chuyên gia đọc cùng số dư.</summary>
    public class WalletService : IWalletService
    {
        /// <summary>Cùng người, cùng số tiền trong khoảng này được xem là bấm đúp: trả lại yêu cầu đã có.</summary>
        private const int DedupeSeconds = 10;

        private static readonly Regex AccountNumber = new(@"^\d{6,19}$", RegexOptions.Compiled);

        private readonly IBookingEngine _engine;
        private readonly IBookingRepository _bookings;
        private readonly IWalletRepository _wallets;
        private readonly IWalletLedgerRepository _ledger;
        private readonly IWalletLedgerService _ledgerService;
        private readonly IWithdrawalRepository _withdrawals;
        private readonly IGenericRepository<User> _users;
        private readonly IClock _clock;
        private readonly ICommerceFailpoints _failpoints;

        public WalletService(
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

        private async Task CatchUpAsync(string userId)
        {
            await _engine.SettleDueAsync(userId);
            await _engine.ReconcileAsync(userId);
        }

        public async Task<WalletResponse> GetWalletAsync(string userId, string role)
        {
            await CatchUpAsync(userId);
            var wallet = await _wallets.GetAsync(userId);
            long pending = 0, frozen = 0;
            if (role == WalletRoles.Chef)
            {
                var rows = await _bookings.ListWithEscrowAsync(userId);
                pending = rows.Where(b => b.Escrow!.Status == EscrowStatuses.Held).Sum(b => MoneyMath.Net(b.Escrow!.Amount));
                frozen = rows.Where(b => b.Escrow!.Status == EscrowStatuses.Frozen).Sum(b => MoneyMath.Net(b.Escrow!.Amount));
            }
            return new WalletResponse
            {
                Available = wallet?.Available ?? 0,
                Pending = pending,
                Frozen = frozen,
                Withdrawn = wallet?.Withdrawn ?? 0,
                Processing = wallet?.Processing ?? 0,
                FeeRate = CommerceRules.FeeRate,
                HoldDays = CommerceRules.HoldDays,
                BankAccount = BookingMapper.Bank(wallet?.BankAccount)
            };
        }

        public async Task<List<WalletTransactionResponse>> ListTransactionsAsync(string userId, int? limit, string? month)
        {
            await CatchUpAsync(userId);
            IEnumerable<WalletTransactionResponse> rows = BookingMapper.Transactions(
                await _bookings.ListWithEscrowAsync(userId),
                await _ledger.ListForUserAsync(userId),
                await _withdrawals.ListForUserAsync(userId));
            if (!string.IsNullOrWhiteSpace(month)) rows = rows.Where(r => VnTime.MonthOf(r.CreatedAt) == month.Trim());
            if (limit is { } n) rows = rows.Take(Math.Clamp(n, 1, 200));
            return rows.ToList();
        }

        public async Task<BankAccountResponse> SaveBankAccountAsync(string userId, BankAccountRequest request)
        {
            var bank = request.BankName?.Trim() ?? string.Empty;
            var number = request.AccountNumber?.Replace(" ", string.Empty) ?? string.Empty;
            var holder = request.AccountHolder?.Trim() ?? string.Empty;
            if (bank.Length == 0) throw new BadRequestException("Chọn ngân hàng.", "validation");
            if (!AccountNumber.IsMatch(number)) throw new BadRequestException("Số tài khoản gồm 6–19 chữ số.", "validation");
            if (holder.Length < 3) throw new BadRequestException("Nhập tên chủ tài khoản.", "validation");

            var account = new WalletBankAccount { BankName = bank, AccountNumber = number, AccountHolder = holder.ToUpperInvariant() };
            await _wallets.SaveBankAccountAsync(userId, account, _clock.UtcNow);
            return BookingMapper.Bank(account)!;
        }

        public async Task<List<WithdrawalResponse>> ListWithdrawalsAsync(string userId)
        {
            await CatchUpAsync(userId);
            return (await _withdrawals.ListForUserAsync(userId)).Select(BookingMapper.Withdrawal).ToList();
        }

        /// <summary>
        /// Thứ tự: tạo yêu cầu (chưa hiện), trừ available sang processing có điều kiện, rồi mới hiện. Chết giữa chừng
        /// thì job xem bút toán đã áp dụng chưa: rồi thì cho hiện, chưa thì bỏ, không có tiền nào kẹt lại.
        /// </summary>
        public async Task<WithdrawalResponse> RequestWithdrawalAsync(string userId, string role, WithdrawalCreateRequest request)
        {
            await CatchUpAsync(userId);
            var wallet = await _wallets.GetAsync(userId);
            var account = wallet?.BankAccount ?? throw new ConflictException("Thêm tài khoản ngân hàng trước khi rút tiền.", "no_bank_account");
            if (request.Amount is not { } amount || amount < CommerceRules.MinWithdrawal)
                throw new BadRequestException($"Số tiền rút tối thiểu {MoneyMath.Vnd(CommerceRules.MinWithdrawal)}.", "amount_too_small");
            if (amount > wallet.Available) throw new ConflictException("Số tiền vượt quá số dư có thể rút.", "insufficient_balance");

            var now = _clock.UtcNow;
            var existing = await _withdrawals.FindRecentAsync(userId, amount, now.AddSeconds(-DedupeSeconds));
            if (existing is { Funded: true }) return BookingMapper.Withdrawal(existing);

            var target = existing;
            if (target == null)
            {
                var user = await _users.FindByIdAsync(userId);
                var bucket = new DateTimeOffset(now).ToUnixTimeSeconds() / DedupeSeconds;
                var candidate = new WithdrawalRequest
                {
                    Id = BookingLifecycle.NewId(),
                    UserId = userId,
                    UserName = user?.FullName ?? string.Empty,
                    UserEmail = user?.Email ?? string.Empty,
                    Role = role,
                    Amount = amount,
                    Status = WithdrawalStatuses.Processing,
                    BankName = account.BankName,
                    AccountNumber = account.AccountNumber,
                    AccountHolder = account.AccountHolder,
                    DedupeKey = $"{userId}:{amount}:{bucket}",
                    CreatedAt = now,
                    UpdatedAt = now
                };
                target = await _withdrawals.TryInsertAsync(candidate)
                    ? candidate
                    : await _withdrawals.FindByDedupeKeyAsync(candidate.DedupeKey) ?? candidate;
            }
            _failpoints.Hit(CommerceFailpointNames.WithdrawalAfterInsert);

            var key = LedgerKinds.WithdrawalKey(target.Id, LedgerKinds.WithdrawalHold);
            var debited = await _ledgerService.TryDebitAsync(new WalletLedgerEntry
            {
                Id = WalletLedgerEntry.IdForKey(key),
                IdempotencyKey = key,
                UserId = userId,
                Kind = LedgerKinds.WithdrawalHold,
                Type = LedgerTypes.Withdrawal,
                WithdrawalId = target.Id,
                DeltaAvailable = -amount,
                DeltaProcessing = amount,
                OccurredAt = now,
                CreatedAt = now
            });
            if (!debited)
            {
                await _withdrawals.DiscardAsync(target.Id, now);
                throw new ConflictException("Số tiền vượt quá số dư có thể rút.", "insufficient_balance");
            }
            _failpoints.Hit(CommerceFailpointNames.WithdrawalAfterDebit);

            await _withdrawals.MarkFundedAsync(target.Id);
            target.Funded = true;
            return BookingMapper.Withdrawal(target);
        }
    }
}
