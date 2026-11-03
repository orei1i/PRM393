using System;
using System.Collections.Generic;
using MongoDB.Bson.Serialization.Attributes;

namespace DomainLayer.Entities
{
    /// <summary>
    /// Một booking cùng mọi thứ gắn với nó (đề xuất, hợp đồng, đơn, thanh toán, giữ tiền, khiếu nại,
    /// kế hoạch, chat) nằm trong MỘT document. Mongo local là standalone nên không có transaction nhiều
    /// document: gom lại thì mỗi bước đổi trạng thái là một lần ghi nguyên tử, có điều kiện theo Version.
    /// </summary>
    [BsonIgnoreExtraElements]
    public class ChefBooking : BaseEntity
    {
        /// <summary>Compare-and-swap: mọi lần ghi phải khớp Version đã đọc.</summary>
        public long Version { get; set; }

        public string MemberId { get; set; } = string.Empty;
        public string MemberName { get; set; } = string.Empty;
        public string MemberEmail { get; set; } = string.Empty;

        /// <summary>Id user của chuyên gia.</summary>
        public string ChefId { get; set; } = string.Empty;
        public string ChefName { get; set; } = string.Empty;
        public string ChefEmail { get; set; } = string.Empty;

        public string BookingType { get; set; } = string.Empty;
        public int PlanDays { get; set; }
        public string StartDate { get; set; } = string.Empty;
        public string Audience { get; set; } = "Self";
        public int? FamilySize { get; set; }
        public string? Goal { get; set; }
        public List<string> Allergies { get; set; } = new();
        public List<string> MealPattern { get; set; } = new();
        public long? BudgetPerDay { get; set; }
        public string Needs { get; set; } = string.Empty;
        public bool ShareHealthProfile { get; set; }

        public string Status { get; set; } = string.Empty;
        public DateTime? CompletedAt { get; set; }
        public bool AutoCompleted { get; set; }
        public string? DeclineReason { get; set; }
        public string? CancelReason { get; set; }

        public List<BookingOffer> Offers { get; set; } = new();
        public BookingContract? Contract { get; set; }
        public EscrowHold? Escrow { get; set; }
        public BookingComplaint? Complaint { get; set; }
        public BookingOrder? Order { get; set; }
        public List<BookingPlanDay> Days { get; set; } = new();
        public List<BookingMessage> Messages { get; set; } = new();

        /// <summary>
        /// Việc ghi sổ ví còn nợ. Ghi cùng lần với trạng thái giữ tiền, nên nếu máy chủ chết ngay sau đó thì
        /// job vẫn biết phải cộng cho ai bao nhiêu.
        /// </summary>
        public List<LedgerIntent> Outbox { get; set; } = new();
    }

    public class BookingOffer
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

    public class BookingContract
    {
        public string Id { get; set; } = string.Empty;
        public string OfferId { get; set; } = string.Empty;
        public long Price { get; set; }
        public int PlanDays { get; set; }
        public string BookingType { get; set; } = string.Empty;
        public string StartDate { get; set; } = string.Empty;
        public string EndDate { get; set; } = string.Empty;
        public DateTime DeliveryDueAt { get; set; }
        public string ScopeText { get; set; } = string.Empty;
        public DateTime PaymentDueAt { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class EscrowHold
    {
        public string Id { get; set; } = string.Empty;
        public string PaymentId { get; set; } = string.Empty;
        public long Amount { get; set; }
        public string Status { get; set; } = string.Empty;
        public DateTime HeldAt { get; set; }
        /// <summary>Lưu để job truy vấn theo chỉ mục: 23:59 VN của ngày kết thúc + 3.</summary>
        public DateTime AutoCompleteAt { get; set; }
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

    public class BookingComplaint
    {
        public string Id { get; set; } = string.Empty;
        public string Reason { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public string RequestedOutcome { get; set; } = string.Empty;
        public long RequestedAmount { get; set; }
        public string Status { get; set; } = string.Empty;
        public List<ComplaintEvidence> Evidence { get; set; } = new();
        public string? ChefResponse { get; set; }
        public DateTime? ChefRespondedAt { get; set; }
        public string? Decision { get; set; }
        public long? RefundAmount { get; set; }
        public string? AdminNote { get; set; }
        public string? DecidedBy { get; set; }
        public DateTime? DecidedAt { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class ComplaintEvidence
    {
        public string Id { get; set; } = string.Empty;
        public string Kind { get; set; } = string.Empty;
        public string Url { get; set; } = string.Empty;
        public string? Caption { get; set; }
        public string SubmittedBy { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
    }

    public class BookingPlanDay
    {
        public int DayIndex { get; set; }
        public string Date { get; set; } = string.Empty;
        /// <summary>null: chưa soạn; Draft; Sent.</summary>
        public string? Status { get; set; }
        public string? ChefNote { get; set; }
        public DateTime? SentAt { get; set; }
        public List<BookingPlanMeal> Meals { get; set; } = new();
        public DayFeedback? Feedback { get; set; }
    }

    public class BookingPlanMeal
    {
        public string Slot { get; set; } = string.Empty;
        public PlanRecipe Recipe { get; set; } = new();
        public string? Note { get; set; }
    }

    public class PlanRecipe
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

    public class DayFeedback
    {
        public int Rating { get; set; }
        public string Adherence { get; set; } = string.Empty;
        public string Body { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
    }

    public class BookingMessage
    {
        public string Id { get; set; } = string.Empty;
        public string? SenderId { get; set; }
        public string SenderRole { get; set; } = string.Empty;
        public string Kind { get; set; } = string.Empty;
        public string Body { get; set; } = string.Empty;
        public string? OfferId { get; set; }
        public string? AttachmentUrl { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class BookingOrder
    {
        public string Id { get; set; } = string.Empty;
        public long Amount { get; set; }
        public string Status { get; set; } = string.Empty;
        public long RefundedAmount { get; set; }
        public DateTime CreatedAt { get; set; }
        public List<BookingPayment> Payments { get; set; } = new();
        public OrderResolution? Resolution { get; set; }
    }

    public class BookingPayment
    {
        public string Id { get; set; } = string.Empty;
        public string Provider { get; set; } = string.Empty;
        public string TransactionRef { get; set; } = string.Empty;
        public string? QrCodeUrl { get; set; }
        public string Status { get; set; } = string.Empty;
        public long Amount { get; set; }
        public DateTime? PaidAt { get; set; }
        public DateTime? ExpiresAt { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class OrderResolution
    {
        public string Action { get; set; } = string.Empty;
        public string Note { get; set; } = string.Empty;
        public string By { get; set; } = string.Empty;
        public DateTime At { get; set; }
        public string? ComplaintId { get; set; }
    }

    /// <summary>Một khoản cộng vào ví còn chờ ghi sổ.</summary>
    public class LedgerIntent
    {
        public string Key { get; set; } = string.Empty;
        public string Kind { get; set; } = string.Empty;
        public string Type { get; set; } = string.Empty;
        public string UserId { get; set; } = string.Empty;
        public long? Gross { get; set; }
        public long? Fee { get; set; }
        public long Net { get; set; }
        public string? Note { get; set; }
        public string? ComplaintId { get; set; }
        public string? PaymentId { get; set; }
        public string? TransactionRef { get; set; }
        public string? CounterpartName { get; set; }
        public DateTime OccurredAt { get; set; }
    }
}
