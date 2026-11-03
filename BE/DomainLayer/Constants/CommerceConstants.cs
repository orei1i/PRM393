namespace DomainLayer.Constants
{
    /// <summary>Số liệu nghiệp vụ của đặt chuyên gia, giữ tiền và ví. Cùng giá trị với FE (types/bookings.ts, types/payouts.ts).</summary>
    public static class CommerceRules
    {
        public const int HoldDays = 7;
        public const double FeeRate = 0.1;
        public const int AutoCompleteDays = 3;
        public const int PaymentWindowHours = 48;
        public const int QrTtlMinutes = 15;
        public const int ReleasingSoonDays = 3;

        public const int MinPlanDays = 3;
        public const int MaxPlanDays = 30;
        public const int MinFamilySize = 2;
        public const int MaxFamilySize = 20;
        public const long MinPrice = 100_000;
        public const long MaxPrice = 50_000_000;
        public const int MaxOfferNote = 300;
        public const int MaxMessage = 1000;
        public const int MinNeeds = 20;
        public const int MaxNeeds = 2000;
        public const int MinDeclineReason = 10;
        public const int MinCancelReason = 5;
        public const int MinComplaintDescription = 30;
        public const int MaxComplaintDescription = 3000;
        public const int MaxEvidenceImages = 5;
        public const int MinChefResponse = 20;
        public const int MaxFeedbackBody = 500;
        public const int MinDishName = 3;
        public const int MaxDishName = 120;
        public const int MinDecisionNote = 20;
        public const int MinAuditNote = 10;
        public const long MinPartialRefund = 1_000;
        public const long MinWithdrawal = 100_000;
        public const int MinTransferRef = 6;
        public const int MaxTransferRef = 40;
        public const string DailySendCutoff = "06:00";
        public const string FeedbackCutoff = "21:00";
        public const int SendCutoffHour = 6;
    }

    public static class BookingStatuses
    {
        public const string Requested = "Requested";
        public const string Negotiating = "Negotiating";
        public const string AwaitingPayment = "AwaitingPayment";
        public const string Active = "Active";
        public const string Ended = "Ended";
        public const string Disputed = "Disputed";
        public const string Completed = "Completed";
        public const string Resolved = "Resolved";
        public const string Declined = "Declined";
        public const string Cancelled = "Cancelled";
        public const string Expired = "Expired";
    }

    public static class BookingTypes
    {
        public const string OneShot = "OneShot";
        public const string DailyFeedback = "DailyFeedback";
        public static bool IsValid(string? v) => v is OneShot or DailyFeedback;
        public static string Label(string v) => v == OneShot ? "Giao trọn kế hoạch một lần" : "Có phản hồi mỗi ngày";
    }

    public static class BookingAudiences
    {
        public const string Self = "Self";
        public const string Family = "Family";
    }

    public static class BookingParties
    {
        public const string Member = "member";
        public const string Chef = "chef";
        public const string System = "system";
    }

    public static class OfferStatuses
    {
        public const string Open = "Open";
        public const string Accepted = "Accepted";
        public const string Rejected = "Rejected";
        public const string Superseded = "Superseded";
        public const string Withdrawn = "Withdrawn";
    }

    public static class EscrowStatuses
    {
        public const string Held = "Held";
        public const string Frozen = "Frozen";
        public const string Released = "Released";
        public const string Refunded = "Refunded";
        public const string PartiallyRefunded = "PartiallyRefunded";
    }

    public static class ComplaintStatuses
    {
        public const string Open = "Open";
        public const string Resolved = "Resolved";
    }

    public static class PlanDayStatuses
    {
        public const string Draft = "Draft";
        public const string Sent = "Sent";
    }

    public static class OrderStatuses
    {
        public const string Pending = "Pending";
        public const string Paid = "Paid";
        public const string Cancelled = "Cancelled";
        public const string Refunded = "Refunded";
        public const string PartiallyRefunded = "PartiallyRefunded";
    }

    public static class PaymentStatuses
    {
        public const string Pending = "Pending";
        public const string Paid = "Paid";
        public const string Failed = "Failed";
        public const string Expired = "Expired";
    }

    public static class PaymentProviderNames
    {
        public const string Wallet = "Wallet";
        /// <summary>Chỉ để thử nghiệm: không có tiền thật đi qua.</summary>
        public const string Sandbox = "Sandbox";
    }

    public static class ComplaintDecisions
    {
        public const string ReleaseToChef = "ReleaseToChef";
        public const string RefundMember = "RefundMember";
        public const string Split = "Split";
        public static bool IsValid(string? v) => v is ReleaseToChef or RefundMember or Split;
        public static string Label(string v) => v switch
        {
            ReleaseToChef => "Chuyển toàn bộ cho chuyên gia",
            RefundMember => "Hoàn toàn bộ cho thành viên",
            _ => "Hoàn một phần"
        };
    }

    public static class WithdrawalStatuses
    {
        public const string Processing = "Processing";
        public const string Completed = "Completed";
        public const string Rejected = "Rejected";
    }

    public static class WalletRoles
    {
        public const string Member = "member";
        public const string Chef = "chef";
    }

    public static class LedgerTypes
    {
        public const string Income = "Income";
        public const string Refund = "Refund";
        public const string Payment = "Payment";
        public const string Withdrawal = "Withdrawal";
    }

    /// <summary>Loại bút toán; cùng với id booking/rút tiền tạo thành khoá chống trả hai lần.</summary>
    public static class LedgerKinds
    {
        public const string Income = "income";
        public const string Refund = "refund";
        public const string WalletPayment = "wallet_payment";
        public const string WalletPaymentReversal = "wallet_payment_reversal";
        public const string LateRefund = "late_refund";
        public const string WithdrawalHold = "withdrawal_hold";
        public const string WithdrawalComplete = "withdrawal_complete";
        public const string WithdrawalReject = "withdrawal_reject";

        public static string BookingKey(string bookingId, string kind) => $"booking:{bookingId}:{kind}";
        public static string WithdrawalKey(string withdrawalId, string kind) => $"withdrawal:{withdrawalId}:{kind}";
    }
}
