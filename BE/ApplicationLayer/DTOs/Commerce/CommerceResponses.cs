using System;
using System.Collections.Generic;

namespace ApplicationLayer.DTOs.Commerce
{
    public class PersonResponse
    {
        public string Id { get; set; } = string.Empty;
        public string FullName { get; set; } = string.Empty;
        public string Email { get; set; } = string.Empty;
    }

    public class OfferResponse
    {
        public string Id { get; set; } = string.Empty;
        public string ProposedBy { get; set; } = string.Empty;
        public long Price { get; set; }
        public int PlanDays { get; set; }
        public string BookingType { get; set; } = string.Empty;
        public string StartDate { get; set; } = string.Empty;
        public string Note { get; set; } = string.Empty;
        public string Status { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
        public DateTime? RespondedAt { get; set; }
    }

    public class ContractResponse
    {
        public string Id { get; set; } = string.Empty;
        public string BookingId { get; set; } = string.Empty;
        public string OfferId { get; set; } = string.Empty;
        public long Price { get; set; }
        public int PlanDays { get; set; }
        public string BookingType { get; set; } = string.Empty;
        public string StartDate { get; set; } = string.Empty;
        public string EndDate { get; set; } = string.Empty;
        public DateTime DeliveryDueAt { get; set; }
        public string DailySendCutoff { get; set; } = string.Empty;
        public string FeedbackCutoff { get; set; } = string.Empty;
        public string ScopeText { get; set; } = string.Empty;
        public double FeeRate { get; set; }
        public int HoldDays { get; set; }
        public DateTime PaymentDueAt { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class EscrowResponse
    {
        public string Id { get; set; } = string.Empty;
        public string BookingId { get; set; } = string.Empty;
        public string PaymentId { get; set; } = string.Empty;
        public long Amount { get; set; }
        public string Status { get; set; } = string.Empty;
        public DateTime HeldAt { get; set; }
        public DateTime? CompletedAt { get; set; }
        public DateTime? ReleaseAt { get; set; }
        public DateTime? ReleasedAt { get; set; }
        public long ReleasedAmount { get; set; }
        public long FeeAmount { get; set; }
        public long RefundedAmount { get; set; }
        public DateTime? RefundedAt { get; set; }
        public string? ResolvedBy { get; set; }
        public string? ResolutionNote { get; set; }
    }

    public class EvidenceResponse
    {
        public string Id { get; set; } = string.Empty;
        public string Kind { get; set; } = string.Empty;
        public string Url { get; set; } = string.Empty;
        public string? Caption { get; set; }
        public string SubmittedBy { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
    }

    public class ComplaintResponse
    {
        public string Id { get; set; } = string.Empty;
        public string BookingId { get; set; } = string.Empty;
        public string Reason { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public string RequestedOutcome { get; set; } = string.Empty;
        public long RequestedAmount { get; set; }
        public string Status { get; set; } = string.Empty;
        public List<EvidenceResponse> Evidence { get; set; } = new();
        public string? ChefResponse { get; set; }
        public DateTime? ChefRespondedAt { get; set; }
        public string? Decision { get; set; }
        public long? RefundAmount { get; set; }
        public string? AdminNote { get; set; }
        public string? DecidedBy { get; set; }
        public DateTime? DecidedAt { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class MemberHealthResponse
    {
        public double? HeightCm { get; set; }
        public double? WeightKg { get; set; }
        public double? Bmi { get; set; }
        public string? Gender { get; set; }
        public int? Age { get; set; }
        public string? ActivityLevel { get; set; }
        public int? DailyKcalTarget { get; set; }
    }

    public class BookingResponse
    {
        public string Id { get; set; } = string.Empty;
        public PersonResponse Member { get; set; } = new();
        public PersonResponse Chef { get; set; } = new();
        public string BookingType { get; set; } = string.Empty;
        public int PlanDays { get; set; }
        public string StartDate { get; set; } = string.Empty;
        public string Audience { get; set; } = string.Empty;
        public int? FamilySize { get; set; }
        public string? Goal { get; set; }
        public List<string> Allergies { get; set; } = new();
        public List<string> MealPattern { get; set; } = new();
        public long? BudgetPerDay { get; set; }
        public string Needs { get; set; } = string.Empty;
        public bool ShareHealthProfile { get; set; }
        public string Status { get; set; } = string.Empty;
        public int DeliveredDays { get; set; }
        public DateTime? CompletedAt { get; set; }
        public bool AutoCompleted { get; set; }
        public OfferResponse? CurrentOffer { get; set; }
        public ContractResponse? Contract { get; set; }
        public EscrowResponse? Escrow { get; set; }
        public ComplaintResponse? Complaint { get; set; }
        public string? PaymentOrderId { get; set; }
        public string? DeclineReason { get; set; }
        public string? CancelReason { get; set; }
        public MemberHealthResponse? MemberHealth { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime UpdatedAt { get; set; }
    }

    public class BookingRefResponse
    {
        public string Id { get; set; } = string.Empty;
        public PersonResponse Member { get; set; } = new();
        public PersonResponse Chef { get; set; } = new();
        public string BookingType { get; set; } = string.Empty;
        public int PlanDays { get; set; }
        public string StartDate { get; set; } = string.Empty;
        public string? EndDate { get; set; }
        public string Audience { get; set; } = string.Empty;
        public int? FamilySize { get; set; }
        public List<string> Allergies { get; set; } = new();
        public string Status { get; set; } = string.Empty;
        public int DeliveredDays { get; set; }
        public DateTime? CompletedAt { get; set; }
        public bool AutoCompleted { get; set; }
        public string? ComplaintId { get; set; }
        public string? PaymentOrderId { get; set; }
    }

    public class PlanRecipeResponse
    {
        public string? Id { get; set; }
        public string Name { get; set; } = string.Empty;
        public int? Calories { get; set; }
        public double? ProteinG { get; set; }
        public double? CarbsG { get; set; }
        public double? FatG { get; set; }
        public List<string> Ingredients { get; set; } = new();
        public string? Instructions { get; set; }
    }

    public class PlanMealResponse
    {
        public string Slot { get; set; } = string.Empty;
        public PlanRecipeResponse Recipe { get; set; } = new();
        public string? Note { get; set; }
    }

    public class DayFeedbackResponse
    {
        public int Rating { get; set; }
        public string Adherence { get; set; } = string.Empty;
        public string Body { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
    }

    public class PlanDayResponse
    {
        public int DayIndex { get; set; }
        public string Date { get; set; } = string.Empty;
        public string? Status { get; set; }
        public string? ChefNote { get; set; }
        public DateTime? SentAt { get; set; }
        public List<PlanMealResponse> Meals { get; set; } = new();
        public DayFeedbackResponse? Feedback { get; set; }
    }

    public class MessageResponse
    {
        public string Id { get; set; } = string.Empty;
        public string? SenderId { get; set; }
        public string SenderRole { get; set; } = string.Empty;
        public string Kind { get; set; } = string.Empty;
        public string Body { get; set; } = string.Empty;
        public string? OfferId { get; set; }
        public OfferResponse? Offer { get; set; }
        public string? AttachmentUrl { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class PaymentResponse
    {
        public string Id { get; set; } = string.Empty;
        public string OrderId { get; set; } = string.Empty;
        public string Provider { get; set; } = string.Empty;
        public string TransactionRef { get; set; } = string.Empty;
        public string? QrCodeUrl { get; set; }
        public string Status { get; set; } = string.Empty;
        public DateTime? PaidAt { get; set; }
        public long Amount { get; set; }
        public DateTime? ExpiresAt { get; set; }
        public DateTime? CreatedAt { get; set; }
    }

    public class OrderBookingResponse
    {
        public string Id { get; set; } = string.Empty;
        public string ChefId { get; set; } = string.Empty;
        public string ChefName { get; set; } = string.Empty;
        public string BookingType { get; set; } = string.Empty;
        public int PlanDays { get; set; }
        public string StartDate { get; set; } = string.Empty;
        public string? EndDate { get; set; }
        public string Status { get; set; } = string.Empty;
        public DateTime? CompletedAt { get; set; }
        public bool AutoCompleted { get; set; }
        public string Audience { get; set; } = string.Empty;
        public int? FamilySize { get; set; }
        public List<string> Allergies { get; set; } = new();
    }

    public class OrderResponse
    {
        public string Id { get; set; } = string.Empty;
        public string UserId { get; set; } = string.Empty;
        public string BookingId { get; set; } = string.Empty;
        public long Amount { get; set; }
        public string Status { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
        public OrderBookingResponse Booking { get; set; } = new();
        public PaymentResponse? Payment { get; set; }
        public EscrowResponse? Escrow { get; set; }
    }

    public class AdminOrderBookingResponse : OrderBookingResponse
    {
        public PersonResponse Chef { get; set; } = new();
        public int DeliveredDays { get; set; }
        public string? ComplaintId { get; set; }
    }

    public class OrderResolutionResponse
    {
        public string Action { get; set; } = string.Empty;
        public string Note { get; set; } = string.Empty;
        public string By { get; set; } = string.Empty;
        public DateTime At { get; set; }
        public string? ComplaintId { get; set; }
    }

    public class AdminOrderResponse
    {
        public string Id { get; set; } = string.Empty;
        public string UserId { get; set; } = string.Empty;
        public PersonResponse Buyer { get; set; } = new();
        public string BookingId { get; set; } = string.Empty;
        public AdminOrderBookingResponse Booking { get; set; } = new();
        public long Amount { get; set; }
        public string Status { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
        public List<PaymentResponse> Payments { get; set; } = new();
        public EscrowResponse? Escrow { get; set; }
        public long RefundedAmount { get; set; }
        public OrderResolutionResponse? Resolution { get; set; }
    }

    public class AdminComplaintResponse : ComplaintResponse
    {
        public BookingResponse Booking { get; set; } = new();
        public List<PlanDayResponse> PlanDays { get; set; } = new();
        public List<MessageResponse> Messages { get; set; } = new();
    }

    public class AdminEscrowHoldResponse : EscrowResponse
    {
        public bool IsStuck { get; set; }
        public BookingRefResponse Booking { get; set; } = new();
    }

    public class EscrowSummaryResponse
    {
        public long TotalHeld { get; set; }
        public int TotalHeldCount { get; set; }
        public long ReleasingSoon { get; set; }
        public int ReleasingSoonCount { get; set; }
        public long AwaitingCompletion { get; set; }
        public int AwaitingCompletionCount { get; set; }
        public long StuckAmount { get; set; }
        public int StuckCount { get; set; }
        public long Frozen { get; set; }
        public int FrozenCount { get; set; }
        public long FeeThisMonth { get; set; }
        public long ReleasedThisMonth { get; set; }
        public int ReleasedThisMonthCount { get; set; }
        public long RefundedThisMonth { get; set; }
        public int OpenComplaints { get; set; }
        public double FeeRate { get; set; }
        public int HoldDays { get; set; }
    }

    public class CommerceSummaryResponse
    {
        public long Revenue { get; set; }
        public long RefundedAmount { get; set; }
        public long PendingAmount { get; set; }
        public int TotalOrders { get; set; }
        public Dictionary<string, int> ByStatus { get; set; } = new();
        public long HeldAmount { get; set; }
        public int HeldCount { get; set; }
    }

    public class BankAccountResponse
    {
        public string BankName { get; set; } = string.Empty;
        public string AccountNumber { get; set; } = string.Empty;
        public string AccountHolder { get; set; } = string.Empty;
    }

    public class WalletResponse
    {
        public long Available { get; set; }
        public long Pending { get; set; }
        public long Frozen { get; set; }
        public long Withdrawn { get; set; }
        public long Processing { get; set; }
        public double FeeRate { get; set; }
        public int HoldDays { get; set; }
        public BankAccountResponse? BankAccount { get; set; }
    }

    public class WalletTransactionResponse
    {
        public string Id { get; set; } = string.Empty;
        public string Type { get; set; } = string.Empty;
        public string Status { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
        public long Net { get; set; }
        public string? BookingId { get; set; }
        public string? OrderId { get; set; }
        public string? TransactionRef { get; set; }
        public string? PlanTitle { get; set; }
        /// <summary>App đọc memberName, Web đọc counterpartName: cùng một giá trị.</summary>
        public string? MemberName { get; set; }
        public string? CounterpartName { get; set; }
        public string? Note { get; set; }
        public long? Gross { get; set; }
        public long? Fee { get; set; }
        public DateTime? ReleaseAt { get; set; }
        public string? ComplaintId { get; set; }
        public string? BankName { get; set; }
    }

    /// <summary>Route của app: phẳng, số tài khoản đã che.</summary>
    public class WithdrawalResponse
    {
        public string Id { get; set; } = string.Empty;
        public long Amount { get; set; }
        public string Status { get; set; } = string.Empty;
        public string BankName { get; set; } = string.Empty;
        public string AccountNumber { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
        public DateTime? ProcessedAt { get; set; }
        public string? Reason { get; set; }
    }

    /// <summary>Route admin: lồng, số tài khoản đầy đủ.</summary>
    public class AdminWithdrawalResponse
    {
        public string Id { get; set; } = string.Empty;
        public string UserId { get; set; } = string.Empty;
        public string Role { get; set; } = string.Empty;
        public PersonResponse User { get; set; } = new();
        public long Amount { get; set; }
        public string Status { get; set; } = string.Empty;
        public BankAccountResponse BankAccount { get; set; } = new();
        public DateTime CreatedAt { get; set; }
        public DateTime? ProcessedAt { get; set; }
        public string? ProcessedBy { get; set; }
        public string? TransactionRef { get; set; }
        public string? Reason { get; set; }
    }

    public class AdminWalletResponse
    {
        public string UserId { get; set; } = string.Empty;
        public string Role { get; set; } = string.Empty;
        public PersonResponse User { get; set; } = new();
        public long Available { get; set; }
        public long Pending { get; set; }
        public long Frozen { get; set; }
        public long Processing { get; set; }
        public long Withdrawn { get; set; }
        public long GrossSales { get; set; }
        public long FeeTotal { get; set; }
        public long RefundTotal { get; set; }
        public long WalletPaymentTotal { get; set; }
        public BankAccountResponse? BankAccount { get; set; }
        public DateTime? LastWithdrawalAt { get; set; }
    }

    public class PayoutSummaryResponse
    {
        public long TotalAvailable { get; set; }
        public Dictionary<string, long> AvailableByRole { get; set; } = new();
        public long TotalPending { get; set; }
        public long TotalFrozen { get; set; }
        public long TotalProcessing { get; set; }
        public long PaidOutThisMonth { get; set; }
        public int PaidOutThisMonthCount { get; set; }
        public long PlatformFee { get; set; }
        public long ReleasedGross { get; set; }
        public int ReleasedCount { get; set; }
        public double FeeRate { get; set; }
        public Dictionary<string, int> ByStatus { get; set; } = new();
        public Dictionary<string, Dictionary<string, int>> ByRole { get; set; } = new();
        public int AwaitingApproval { get; set; }
        public long AwaitingApprovalAmount { get; set; }
    }
}
