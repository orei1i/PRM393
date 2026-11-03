using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using DomainLayer.Entities;

namespace DomainLayer.Interfaces
{
    public interface IBookingRepository
    {
        Task InsertAsync(ChefBooking booking);
        Task<ChefBooking?> GetAsync(string id);
        Task<ChefBooking?> FindByOrderIdAsync(string orderId);
        Task<ChefBooking?> FindByPaymentIdAsync(string paymentId);
        Task<ChefBooking?> FindByEscrowIdAsync(string escrowId);
        Task<ChefBooking?> FindByComplaintIdAsync(string complaintId);

        /// <summary>Ghi đè khi Version còn khớp, rồi tăng Version. false: có người ghi trước.</summary>
        Task<bool> TryReplaceAsync(ChefBooking booking);

        Task RemoveOutboxEntryAsync(string bookingId, string key);

        /// <summary>Các danh sách dưới đây bỏ phần chat để nhẹ, chỉ dùng để đọc.</summary>
        Task<List<ChefBooking>> ListForMemberAsync(string memberId);
        Task<List<ChefBooking>> ListForChefAsync(string chefId);
        Task<List<ChefBooking>> ListWithEscrowAsync(string? chefId = null);
        Task<List<ChefBooking>> ListWithComplaintAsync();
        Task<List<ChefBooking>> ListWithOrderAsync();

        /// <summary>Id các booking đã tới hạn một quy tắc thời gian; userId khác null thì chỉ lấy của người đó.</summary>
        Task<List<string>> ListDueIdsAsync(DateTime now, string? userId = null);
        Task<List<string>> ListIdsWithOutboxAsync(string? userId = null);
    }

    public enum WalletApplyResult
    {
        Applied,
        AlreadyApplied,
        Insufficient
    }

    public interface IWalletRepository
    {
        Task<Wallet?> GetAsync(string userId);
        Task EnsureAsync(string userId, DateTime now);
        /// <summary>Một lần ghi nguyên tử: cộng số dư, thêm id bút toán; không cho số dư âm.</summary>
        Task<WalletApplyResult> TryApplyAsync(WalletLedgerEntry entry, DateTime now);
        Task<bool> ContainsEntryAsync(string userId, string entryId);
        Task SaveBankAccountAsync(string userId, WalletBankAccount account, DateTime now);
        Task<List<Wallet>> ListAsync();
    }

    public interface IWalletLedgerRepository
    {
        /// <summary>false: khoá đã tồn tại.</summary>
        Task<bool> TryInsertAsync(WalletLedgerEntry entry);
        Task<WalletLedgerEntry?> GetAsync(string id);
        Task MarkAppliedAsync(string id);
        Task VoidAsync(string id);
        Task ReviveAsync(string id);
        Task MarkSagaDoneAsync(string id);
        Task<List<WalletLedgerEntry>> ListUnappliedAsync(string? userId = null);
        Task<List<WalletLedgerEntry>> ListOpenWalletPaymentsAsync(string? userId = null);
        Task<List<WalletLedgerEntry>> ListForUserAsync(string userId);
        Task<List<WalletLedgerEntry>> ListByTypesAsync(params string[] types);
    }

    public interface IWithdrawalRepository
    {
        /// <summary>false: trùng DedupeKey.</summary>
        Task<bool> TryInsertAsync(WithdrawalRequest request);
        Task<WithdrawalRequest?> GetAsync(string id);
        Task<WithdrawalRequest?> FindByDedupeKeyAsync(string key);
        Task<WithdrawalRequest?> FindRecentAsync(string userId, long amount, DateTime since);
        Task MarkFundedAsync(string id);
        Task DiscardAsync(string id, DateTime now);
        /// <summary>Chỉ thành công khi đang Processing và đã giữ tiền: chỉ một admin thắng.</summary>
        Task<WithdrawalRequest?> TryDecideAsync(string id, string status, string actor, DateTime now, string? transactionRef, string? reason);
        Task MarkPostedAsync(string id);
        Task<List<WithdrawalRequest>> ListUnfundedAsync(DateTime createdBefore, string? userId = null);
        Task<List<WithdrawalRequest>> ListUnpostedAsync(string? userId = null);
        Task<List<WithdrawalRequest>> ListForUserAsync(string userId);
        Task<List<WithdrawalRequest>> ListAllAsync();
    }
}
