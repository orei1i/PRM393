using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Commerce;
using DomainLayer.Entities;

namespace ApplicationLayer.Interfaces
{
    /// <summary>Sổ cái: mọi thay đổi số dư ví đều đi qua đây, mỗi bút toán đúng một lần.</summary>
    public interface IWalletLedgerService
    {
        Task PostCreditAsync(WalletLedgerEntry entry);
        /// <summary>false: không đủ số dư, bút toán bị vô hiệu, ví không đổi.</summary>
        Task<bool> TryDebitAsync(WalletLedgerEntry entry);
        Task FlushOutboxAsync(ChefBooking booking);
        Task PostWithdrawalOutcomeAsync(WithdrawalRequest request);
    }

    public enum WalletPaymentOutcome
    {
        Funded,
        Closed
    }

    /// <summary>Đọc và ghi booking có quy tắc thời gian, và dọn những việc dở dang sau khi máy chủ chết.</summary>
    public interface IBookingEngine
    {
        /// <summary>Booking sau khi đã áp quy tắc thời gian. null: không có.</summary>
        Task<ChefBooking?> LoadSettledAsync(string id);

        /// <summary>
        /// Đọc, áp quy tắc thời gian, chạy <paramref name="mutate"/>, ghi có điều kiện theo Version.
        /// Có người ghi trước thì đọc lại và chạy lại từ đầu, nên điều kiện nghiệp vụ luôn xét trên dữ liệu mới nhất.
        /// mutate trả false nghĩa là không cần ghi.
        /// </summary>
        Task<ChefBooking> MutateAsync(string id, Func<ChefBooking, DateTime, bool> mutate);

        Task SettleDueAsync(string? userId = null);
        Task ReconcileAsync(string? userId = null);

        /// <summary>Một vòng job: áp quy tắc thời gian rồi dọn việc dở dang. Chạy lại bao nhiêu lần cũng không đổi kết quả.</summary>
        Task RunOnceAsync();

        Task<WalletPaymentOutcome> FinishWalletPaymentAsync(WalletLedgerEntry entry);
    }

    public record PaymentSession(string TransactionRef, string? QrCodeUrl);

    /// <summary>
    /// Cổng thanh toán. Hiện chỉ có Sandbox (không có tiền thật); chưa có PaymentOS/MoMo/VNPay thật vì thiếu
    /// thông tin tích hợp. Không có cổng thì route thanh toán trả 503.
    /// </summary>
    public interface IPaymentProvider
    {
        bool IsConfigured { get; }
        string Name { get; }
        Task<PaymentSession> OpenAsync(string orderId, long amount, DateTime expiresAt);
    }

    public interface IBookingService
    {
        Task<BookingResponse> CreateAsync(string userId, CreateBookingRequest request);
        Task<List<BookingResponse>> ListMineAsync(string userId);
        Task<BookingResponse> GetAsync(string userId, string id);
        Task<List<MessageResponse>> ListMessagesAsync(string userId, string id, DateTime? after);
        Task<MessageResponse> SendMessageAsync(string userId, string id, SendMessageRequest request);
        Task<BookingResponse> SendOfferAsync(string userId, string id, OfferRequest request);
        Task<BookingResponse> RespondToOfferAsync(string userId, string id, string offerId, bool accept);
        Task<BookingResponse> CancelAsync(string userId, string id, ReasonRequest request);
        Task<List<PlanDayResponse>> GetPlanAsync(string userId, string id);
        Task<PlanDayResponse> SendFeedbackAsync(string userId, string id, int dayIndex, DayFeedbackRequest request);
        Task<BookingResponse> FileComplaintAsync(string userId, string id, ComplaintRequest request);
        Task<ComplaintResponse> GetComplaintAsync(string userId, string id);

        Task<List<BookingResponse>> ListForChefAsync(string userId, string? status = null);
        Task<BookingResponse> DeclineAsync(string userId, string id, ReasonRequest request);
        Task<BookingResponse> ConfirmCompletionAsync(string userId, string id);
        Task<PlanDayResponse> SavePlanDayAsync(string userId, string id, int dayIndex, PlanDayRequest request);
        Task<PlanDayResponse> SendPlanDayAsync(string userId, string id, int dayIndex);
        Task<List<PlanDayResponse>> SendWholePlanAsync(string userId, string id);
        Task<ComplaintResponse> RespondToComplaintAsync(string userId, string id, ComplaintChefResponseRequest request);
    }

    public interface IOrderPaymentService
    {
        Task<OrderResponse> StartBookingPaymentAsync(string userId, string bookingId);
        Task<OrderResponse> GetOrderAsync(string userId, string orderId);
        Task<PaymentResponse> RenewPaymentAsync(string userId, string orderId);
        Task<PaymentResponse> GetPaymentAsync(string userId, string paymentId);
        Task<OrderResponse> PayWithWalletAsync(string userId, string orderId);
        Task<PaymentResponse> SandboxConfirmAsync(string paymentId, bool success, string? buyerId = null);
    }

    public interface IWalletService
    {
        Task<WalletResponse> GetWalletAsync(string userId, string role);
        Task<List<WalletTransactionResponse>> ListTransactionsAsync(string userId, int? limit, string? month);
        Task<BankAccountResponse> SaveBankAccountAsync(string userId, BankAccountRequest request);
        Task<List<WithdrawalResponse>> ListWithdrawalsAsync(string userId);
        Task<WithdrawalResponse> RequestWithdrawalAsync(string userId, string role, WithdrawalCreateRequest request);
    }

    public interface IAdminMoneyService
    {
        Task<List<AdminComplaintResponse>> ListComplaintsAsync(string? status, string? search);
        Task<AdminComplaintResponse> GetComplaintAsync(string id);
        Task<AdminComplaintResponse> DecideComplaintAsync(string adminId, string id, AdminDecisionRequest request);
        Task<EscrowSummaryResponse> GetEscrowSummaryAsync();
        Task<List<AdminEscrowHoldResponse>> ListHoldsAsync(string? status, string? search);
        Task<EscrowResponse> ResolveHoldAsync(string adminId, string id, AdminDecisionRequest request);
        Task<CommerceSummaryResponse> GetCommerceSummaryAsync();
        Task<List<AdminOrderResponse>> ListOrdersAsync(string? status, string? search);
        Task<AdminOrderResponse> GetOrderAsync(string id);
        Task<AdminOrderResponse> CancelOrderAsync(string adminId, string id, AdminOrderCancelRequest request);
        Task<List<AdminWithdrawalResponse>> ListWithdrawalsAsync(string? status, string? role, string? search);
        Task<AdminWithdrawalResponse> CompleteWithdrawalAsync(string adminId, string id, WithdrawalCompleteRequest request);
        Task<AdminWithdrawalResponse> RejectWithdrawalAsync(string adminId, string id, WithdrawalRejectRequest request);
        Task<List<AdminWalletResponse>> ListWalletsAsync();
        Task<List<WalletTransactionResponse>> ListWalletTransactionsAsync(string userId, int? limit);
        Task<PayoutSummaryResponse> GetPayoutSummaryAsync();
    }
}
