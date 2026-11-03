using System;

namespace DomainLayer.Interfaces
{
    /// <summary>Đồng hồ tiêm được, để kiểm thử đúng các mốc thời gian.</summary>
    public interface IClock
    {
        DateTime UtcNow { get; }
    }

    /// <summary>
    /// Điểm dừng cho kiểm thử: bản thật không làm gì; bản kiểm thử ném lỗi tại một điểm để mô phỏng
    /// máy chủ chết giữa hai lần ghi.
    /// </summary>
    public interface ICommerceFailpoints
    {
        void Hit(string name);
    }

    public static class CommerceFailpointNames
    {
        public const string BookingAfterCommit = "booking.after_commit";
        public const string LedgerAfterInsert = "ledger.after_insert";
        public const string LedgerAfterApply = "ledger.after_apply";
        public const string WalletPayAfterDebit = "wallet_pay.after_debit";
        public const string WithdrawalAfterInsert = "withdrawal.after_insert";
        public const string WithdrawalAfterDebit = "withdrawal.after_debit";
        public const string WithdrawalAfterDecision = "withdrawal.after_decision";
    }
}
