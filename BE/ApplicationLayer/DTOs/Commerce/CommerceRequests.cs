using System.Collections.Generic;

namespace ApplicationLayer.DTOs.Commerce
{
    // Trường nào cũng cho phép null và được kiểm tra trong service: lỗi phải trả đúng mã máy đọc của FE
    // (note_too_short, invalid_refund_amount, validation...), DataAnnotations chỉ trả được validation_error.

    public class CreateBookingRequest
    {
        public string? ChefId { get; set; }
        public string? BookingType { get; set; }
        public int? PlanDays { get; set; }
        public string? StartDate { get; set; }
        public string? Audience { get; set; }
        public int? FamilySize { get; set; }
        public string? Goal { get; set; }
        public List<string>? Allergies { get; set; }
        public List<string>? MealPattern { get; set; }
        public long? BudgetPerDay { get; set; }
        public string? Needs { get; set; }
        public bool? ShareHealthProfile { get; set; }
    }

    public class SendMessageRequest
    {
        public string? Body { get; set; }
        public string? AttachmentUrl { get; set; }
    }

    public class OfferRequest
    {
        public long? Price { get; set; }
        public int? PlanDays { get; set; }
        public string? BookingType { get; set; }
        public string? StartDate { get; set; }
        public string? Note { get; set; }
    }

    public class ReasonRequest
    {
        public string? Reason { get; set; }
    }

    public class DayFeedbackRequest
    {
        public int? Rating { get; set; }
        public string? Adherence { get; set; }
        public string? Body { get; set; }
    }

    public class EvidenceRequest
    {
        public string? Kind { get; set; }
        public string? Url { get; set; }
        public string? Caption { get; set; }
    }

    public class ComplaintRequest
    {
        public string? Reason { get; set; }
        public string? Description { get; set; }
        public string? RequestedOutcome { get; set; }
        public long? RequestedAmount { get; set; }
        public List<EvidenceRequest>? Evidence { get; set; }
    }

    public class ComplaintChefResponseRequest
    {
        public string? Text { get; set; }
        public List<EvidenceRequest>? Links { get; set; }
    }

    public class PlanRecipeRequest
    {
        public string? Id { get; set; }
        public string? Name { get; set; }
        public int? Calories { get; set; }
        public double? ProteinG { get; set; }
        public double? CarbsG { get; set; }
        public double? FatG { get; set; }
        public List<string>? Ingredients { get; set; }
        public string? Instructions { get; set; }
    }

    public class PlanMealRequest
    {
        public string? Slot { get; set; }
        public string? RecipeId { get; set; }
        public PlanRecipeRequest? Recipe { get; set; }
        public string? Note { get; set; }
    }

    public class PlanDayRequest
    {
        public string? ChefNote { get; set; }
        public List<PlanMealRequest>? Meals { get; set; }
    }

    public class BankAccountRequest
    {
        public string? BankName { get; set; }
        public string? AccountNumber { get; set; }
        public string? AccountHolder { get; set; }
    }

    public class WithdrawalCreateRequest
    {
        public long? Amount { get; set; }
    }

    public class AdminDecisionRequest
    {
        public string? Decision { get; set; }
        public long? RefundAmount { get; set; }
        public string? Note { get; set; }
    }

    public class AdminOrderCancelRequest
    {
        public string? Note { get; set; }
    }

    public class WithdrawalCompleteRequest
    {
        public string? TransactionRef { get; set; }
    }

    public class WithdrawalRejectRequest
    {
        public string? Reason { get; set; }
    }

    public class SandboxConfirmRequest
    {
        public bool Success { get; set; } = true;
    }
}
