// src/types/bookings.ts
// Chef meal-plan bookings, escrow holds and complaints for /disputes ("Khiếu nại & giữ tiền").
// The same shapes are used by the mobile P5 package (FE/Mobile lib/features/booking); seed ids
// are aligned (b_ma_tam_nego, b_tram_tam, cp_tram_tam…) but the two mocks are separate stores.
//
// Flow: member request → chat + offers (negotiation) → contract (immutable) → PaymentOS QR →
// money held in escrow → chef delivers the N-day plan → hold until plan end + 3 days →
// no complaint: released to the chef wallet minus the 10% fee. A complaint (evidence required)
// freezes the hold until an admin decides here: release to the chef, full refund or partial
// refund to the member's ORIGINAL payment method (PaymentOS refund, no member wallet).
//
// ┌ For the BE team: NOT in the 26-table SQL design. Proposed tables (snake_case → camelCase):
// │ chef_bookings        id, member_id, chef_id, booking_type (OneShot | DailyFeedback), plan_days, start_date,
// │                      goal, allergies_snapshot, meal_pattern, budget_per_day NULL, needs, share_health_profile BIT,
// │                      status, decline_reason NULL, cancel_reason NULL, created_at, updated_at
// │ booking_offers       id, booking_id, proposed_by, price, plan_days, booking_type, start_date, note,
// │                      status (Open | Accepted | Rejected | Superseded | Withdrawn), created_at, responded_at
// │ booking_messages     id, booking_id, sender_id NULL (system), kind (Text | Offer | System | Attachment), body,
// │                      offer_id NULL, attachment_url NULL, created_at, read_at
// │ booking_contracts    id, booking_id UNIQUE, offer_id, price, plan_days, booking_type, start_date, end_date,
// │                      delivery_due_at, daily_send_cutoff ("06:00"), feedback_cutoff ("21:00"), scope_text,
// │                      fee_rate (0.10), hold_days (3), payment_due_at (+48 h), created_at   — immutable
// │ booking_plan_days    id, booking_id, day_index, date, status (Draft | Sent), chef_note, sent_at, updated_at
// │ booking_plan_meals   id, plan_day_id, meal_type (6 slots), recipe_id (recipes.created_by = chef), note
// │ booking_day_feedback id, plan_day_id UNIQUE, member_id, rating 1–5, adherence (All | Partly | None), body,
// │                      created_at, updated_at, chef_seen_at
// │ escrow_holds         id, booking_id UNIQUE, payment_id, amount, status (Held | Frozen | Released | Refunded |
// │                      PartiallyRefunded), held_at, release_at (end_date 23:59 Asia/Ho_Chi_Minh + 3 days),
// │                      released_at, released_amount, fee_amount, refunded_amount, resolved_by, resolution_note
// │ booking_complaints   id, booking_id UNIQUE, member_id, reason, description, requested_outcome
// │                      (FullRefund | PartialRefund), requested_amount, status (Open | Resolved), chef_response,
// │                      chef_responded_at, decision (ReleaseToChef | RefundMember | Split), refund_amount,
// │                      decided_by, decided_at, admin_note, created_at
// │ complaint_evidence   id, complaint_id, submitted_by, kind (Link | Image), url, caption, created_at
// │ orders.booking_id INT NULL (orders.service_id becomes nullable); wallet_transactions.booking_id.
// └ services, consultations, access grants and chef_meal_suggestions are deprecated.
//
// Wire samples (ids are INT on the BE, strings in the clients):
//
// BookingDto — GET /bookings/{id} (app), nested in every admin response below
// { "id": "b_tram_tam",
//   "member": { "id": "u_ngoc_tram", "fullName": "Ngọc Trâm", "email": "ngoctram.k17@gmail.com" },
//   "chef":   { "id": "u_chef_tam",  "fullName": "Lê Quang Tâm", "email": "tam.chefchay@gmail.com" },
//   "bookingType": "OneShot", "planDays": 7, "startDate": "2026-10-10",
//   "goal": "eat_clean", "allergies": ["peanut"], "mealPattern": ["breakfast","lunch","dinner"],
//   "budgetPerDay": 90000, "needs": "…", "shareHealthProfile": true,
//   "status": "Disputed", "deliveredDays": 7,
//   "currentOffer": OfferDto | null,
//   "contract": ContractDto | null,
//   "escrow": { "id": "eh_604", "bookingId": "b_tram_tam", "paymentId": "pay_…", "amount": 1050000,
//               "status": "Frozen", "heldAt": "…", "releaseAt": "2026-10-19T16:59:00.000Z",
//               "releasedAt": null, "releasedAmount": 0, "feeAmount": 0, "refundedAmount": 0,
//               "resolvedBy": null, "resolutionNote": null } | null,
//   "complaint": ComplaintDto | null, "paymentOrderId": "ord_604",
//   "declineReason": null, "cancelReason": null, "createdAt": "…", "updatedAt": "…" }
//
// OfferDto     { "id", "proposedBy": "chef" | "member", "price": 1500000, "planDays": 10,
//                "bookingType": "DailyFeedback", "startDate": "2026-10-20", "note": "…",
//                "status": "Open", "createdAt": "…", "respondedAt": null }
// ContractDto  { "id", "bookingId", "offerId", "price", "planDays", "bookingType", "startDate", "endDate",
//                "deliveryDueAt", "dailySendCutoff": "06:00", "feedbackCutoff": "21:00", "scopeText",
//                "feeRate": 0.1, "holdDays": 3, "paymentDueAt", "createdAt" }
// ComplaintDto { "id": "cp_tram_tam", "bookingId": "b_tram_tam", "reason": "health_risk", "description": "…",
//                "requestedOutcome": "PartialRefund", "requestedAmount": 500000, "status": "Open",
//                "evidence": [{ "id", "kind": "Link" | "Image", "url", "caption", "submittedBy": "member" | "chef",
//                               "createdAt" }],
//                "chefResponse": "…" | null, "chefRespondedAt": "…" | null,
//                "decision": null | "ReleaseToChef" | "RefundMember" | "Split", "refundAmount": null | 300000,
//                "adminNote": null, "decidedBy": null, "decidedAt": null, "createdAt": "…" }
// PlanDayDto   { "dayIndex": 1, "date": "2026-10-10", "status": "Sent", "chefNote": "…", "sentAt": "…",
//                "meals": [{ "slot": "breakfast", "recipe": { "id": "rc_…", "name": "…", "calories": 420 }, "note": "…" }],
//                "feedback": { "rating": 4, "adherence": "Partly", "body": "…", "createdAt": "…" } | null }
// MessageDto   { "id", "senderId": "u_chef_tam" | null, "senderRole": "member" | "chef" | "system",
//                "kind": "Text" | "Offer" | "System" | "Attachment", "body", "offerId": null, "offer": OfferDto | null,
//                "attachmentUrl": null, "createdAt" }
//
// Admin (this console):
// GET  /admin/complaints?status=Open|Resolved&search=  → AdminComplaintDto[] (planDays / messages omitted)
// GET  /admin/complaints/{id}                          → AdminComplaintDto (with planDays and messages)
// POST /admin/complaints/{id}/decision { decision, refundAmount?, note } → AdminComplaintDto
//      400 note_too_short (< 20) | invalid_refund_amount ; 409 already_decided ; 503 (#fail in the mock)
// GET  /admin/escrow/summary                           → EscrowSummary
// GET  /admin/escrow/holds?status=active|Held|Frozen|Released|Refunded|PartiallyRefunded&search= → AdminEscrowHold[]
// AdminComplaintDto = ComplaintDto + { "booking": BookingDto (its "complaint" is null), "planDays": [...], "messages": [...] }
// AdminEscrowHold   = EscrowHoldDto + { "booking": BookingRef }
import type { ISODateString } from "./moderation";
import { ESCROW_HOLD_DAYS, PLATFORM_FEE_RATE } from "./payouts";

/** "2026-10-17" — a calendar day in Asia/Ho_Chi_Minh. */
export type DateOnly = string;

/* ---------------------------------------------------------------- rules */

export const MIN_PLAN_DAYS = 3;
export const MAX_PLAN_DAYS = 30;
export const MIN_BOOKING_PRICE = 100_000;
export const MAX_BOOKING_PRICE = 50_000_000;
/** Admin decision note (stored in the audit log and shown to both parties). */
export const MIN_DECISION_NOTE = 20;
/** Smallest partial refund (VND); it must also stay below the contract price. */
export const MIN_PARTIAL_REFUND = 1_000;
/** Member pays within this window after accepting an offer, otherwise the booking expires. */
export const PAYMENT_WINDOW_HOURS = 48;

/** Asia/Ho_Chi_Minh is UTC+7 all year (no DST). */
const VN_OFFSET_MS = 7 * 60 * 60_000;

/** The Vietnamese calendar day of an instant: vnDateOf(Date.now()) → "2026-10-17". */
export const vnDateOf = (ms: number): DateOnly => new Date(ms + VN_OFFSET_MS).toISOString().slice(0, 10);

/** "2026-10-31" + 1 → "2026-11-01". */
export function addDays(date: DateOnly, days: number): DateOnly {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

/** An instant at a VN wall-clock time: vnTime("2026-10-20", "06:00") → 2026-10-19T23:00:00.000Z. */
export const vnTime = (date: DateOnly, hhmm: string): ISODateString => new Date(`${date}T${hhmm}:00+07:00`).toISOString();

/** endDate = startDate + planDays − 1 */
export const planEndDate = (startDate: DateOnly, planDays: number): DateOnly => addDays(startDate, planDays - 1);

/** releaseAt = endDate 23:59 (Asia/Ho_Chi_Minh) + holdDays. */
export const escrowReleaseAt = (endDate: DateOnly, holdDays = ESCROW_HOLD_DAYS): ISODateString => vnTime(addDays(endDate, holdDays), "23:59");

/* ---------------------------------------------------------------- enums */

export const BOOKING_TYPES = ["OneShot", "DailyFeedback"] as const;
export type BookingType = (typeof BOOKING_TYPES)[number];

export const BOOKING_TYPE_LABEL: Record<BookingType, string> = {
  OneShot: "Giao trọn kế hoạch một lần",
  DailyFeedback: "Có phản hồi mỗi ngày",
};

export const BOOKING_STATUSES = [
  "Requested",
  "Negotiating",
  "AwaitingPayment",
  "Active",
  "Ended",
  "Disputed",
  "Completed",
  "Resolved",
  "Declined",
  "Cancelled",
  "Expired",
] as const;
export type BookingStatus = (typeof BOOKING_STATUSES)[number];

export const BOOKING_STATUS_LABEL: Record<BookingStatus, string> = {
  Requested: "Chờ báo giá",
  Negotiating: "Đang thoả thuận giá",
  AwaitingPayment: "Chờ thanh toán",
  Active: "Đang thực hiện",
  Ended: "Đã kết thúc · chờ giải ngân",
  Disputed: "Đang khiếu nại",
  Completed: "Hoàn tất",
  Resolved: "Đã xử lý khiếu nại",
  Declined: "Chuyên gia từ chối",
  Cancelled: "Đã huỷ",
  Expired: "Quá hạn thanh toán",
};

export const OFFER_STATUSES = ["Open", "Accepted", "Rejected", "Superseded", "Withdrawn"] as const;
export type OfferStatus = (typeof OFFER_STATUSES)[number];

export const OFFER_STATUS_LABEL: Record<OfferStatus, string> = {
  Open: "Đang chờ trả lời",
  Accepted: "Đã đồng ý",
  Rejected: "Bị từ chối",
  Superseded: "Đã có đề xuất mới",
  Withdrawn: "Đã rút lại",
};

export type BookingParty = "member" | "chef";

export const ESCROW_STATUSES = ["Held", "Frozen", "Released", "Refunded", "PartiallyRefunded"] as const;
export type EscrowStatus = (typeof ESCROW_STATUSES)[number];

export const ESCROW_STATUS_LABEL: Record<EscrowStatus, string> = {
  Held: "Đang giữ",
  Frozen: "Tạm giữ do khiếu nại",
  Released: "Đã chuyển cho chuyên gia",
  Refunded: "Đã hoàn cho thành viên",
  PartiallyRefunded: "Hoàn một phần",
};

export const COMPLAINT_REASONS = ["not_as_agreed", "health_risk", "late_or_missing", "allergen", "other"] as const;
export type ComplaintReason = (typeof COMPLAINT_REASONS)[number];

/** Same wording as the mobile complaint form. */
export const COMPLAINT_REASON_LABEL: Record<ComplaintReason, string> = {
  not_as_agreed: "Kế hoạch không đúng yêu cầu đã thoả thuận",
  health_risk: "Có nội dung ảnh hưởng sức khoẻ",
  late_or_missing: "Giao trễ hoặc thiếu ngày",
  allergen: "Có món chứa chất tôi dị ứng",
  other: "Khác",
};

/** Short form for table cells. */
export const COMPLAINT_REASON_SHORT: Record<ComplaintReason, string> = {
  not_as_agreed: "Không đúng thoả thuận",
  health_risk: "Ảnh hưởng sức khoẻ",
  late_or_missing: "Giao trễ / thiếu ngày",
  allergen: "Chất gây dị ứng",
  other: "Khác",
};

export const REQUESTED_OUTCOMES = ["FullRefund", "PartialRefund"] as const;
export type RequestedOutcome = (typeof REQUESTED_OUTCOMES)[number];

export const REQUESTED_OUTCOME_LABEL: Record<RequestedOutcome, string> = {
  FullRefund: "Hoàn toàn bộ",
  PartialRefund: "Hoàn một phần",
};

export const COMPLAINT_STATUSES = ["Open", "Resolved"] as const;
export type ComplaintStatus = (typeof COMPLAINT_STATUSES)[number];

export const COMPLAINT_STATUS_LABEL: Record<ComplaintStatus, string> = {
  Open: "Chờ xử lý",
  Resolved: "Đã xử lý",
};

export const COMPLAINT_DECISIONS = ["ReleaseToChef", "RefundMember", "Split"] as const;
export type ComplaintDecision = (typeof COMPLAINT_DECISIONS)[number];

export const COMPLAINT_DECISION_LABEL: Record<ComplaintDecision, string> = {
  ReleaseToChef: "Chuyển toàn bộ cho chuyên gia",
  RefundMember: "Hoàn toàn bộ cho thành viên",
  Split: "Hoàn một phần",
};

export const EVIDENCE_KINDS = ["Link", "Image"] as const;
export type EvidenceKind = (typeof EVIDENCE_KINDS)[number];

export const MEAL_SLOTS = ["breakfast", "snack_am", "lunch", "snack_pm", "dinner", "snack_late"] as const;
export type MealSlot = (typeof MEAL_SLOTS)[number];

export const MEAL_SLOT_LABEL: Record<MealSlot, string> = {
  breakfast: "Bữa sáng",
  snack_am: "Phụ sáng",
  lunch: "Bữa trưa",
  snack_pm: "Phụ chiều",
  dinner: "Bữa tối",
  snack_late: "Phụ tối",
};

export const PLAN_DAY_STATUSES = ["Draft", "Sent"] as const;
export type PlanDayStatus = (typeof PLAN_DAY_STATUSES)[number];

export const ADHERENCE_VALUES = ["All", "Partly", "None"] as const;
export type Adherence = (typeof ADHERENCE_VALUES)[number];

export const ADHERENCE_LABEL: Record<Adherence, string> = {
  All: "Làm theo đầy đủ",
  Partly: "Làm theo một phần",
  None: "Không làm theo",
};

export const MESSAGE_KINDS = ["Text", "Offer", "System", "Attachment"] as const;
export type MessageKind = (typeof MESSAGE_KINDS)[number];

/**
 * Booking goal codes. The app sends the health-profile goal codes
 * (`lose_weight`, `maintain`, `lean_muscle`, `gain_weight`) plus
 * `eat_clean`; `gain_muscle` is an older alias of `lean_muscle`.
 */
export const BOOKING_GOAL_LABEL: Record<string, string> = {
  lose_weight: "Giảm cân",
  maintain: "Giữ cân",
  lean_muscle: "Tăng cơ",
  gain_muscle: "Tăng cơ",
  gain_weight: "Tăng cân",
  eat_clean: "Ăn lành mạnh",
};

/* ---------------------------------------------------------------- rows */

export interface BookingPerson {
  id: string;
  fullName: string;
  email: string;
}

export interface BookingOffer {
  id: string;
  proposedBy: BookingParty;
  price: number;
  planDays: number;
  bookingType: BookingType;
  startDate: DateOnly;
  note: string;
  status: OfferStatus;
  createdAt: ISODateString;
  respondedAt: ISODateString | null;
}

/** booking_contracts — the accepted offer, frozen. */
export interface BookingContract {
  id: string;
  bookingId: string;
  offerId: string;
  price: number;
  planDays: number;
  bookingType: BookingType;
  startDate: DateOnly;
  endDate: DateOnly;
  /** OneShot: max(startDate 00:00, paidAt + 24 h). DailyFeedback: day 1 at dailySendCutoff. */
  deliveryDueAt: ISODateString;
  /** DailyFeedback: day N is due at this VN time on day N. */
  dailySendCutoff: string;
  /** DailyFeedback: the member's feedback for day N is expected before this VN time. */
  feedbackCutoff: string;
  scopeText: string;
  feeRate: number;
  holdDays: number;
  paymentDueAt: ISODateString;
  createdAt: ISODateString;
}

export interface EscrowHold {
  id: string;
  bookingId: string;
  paymentId: string;
  /** = contract price (gross). */
  amount: number;
  status: EscrowStatus;
  heldAt: ISODateString;
  releaseAt: ISODateString;
  releasedAt: ISODateString | null;
  /** Gross that went to the chef (before the fee). */
  releasedAmount: number;
  feeAmount: number;
  /** Sent back to the member's original payment method. */
  refundedAmount: number;
  /** Admin name, or null for the automatic release. */
  resolvedBy: string | null;
  resolutionNote: string | null;
}

export interface ComplaintEvidence {
  id: string;
  kind: EvidenceKind;
  url: string;
  caption: string | null;
  submittedBy: BookingParty;
  createdAt: ISODateString;
}

export interface Complaint {
  id: string;
  bookingId: string;
  reason: ComplaintReason;
  description: string;
  requestedOutcome: RequestedOutcome;
  /** = contract price for FullRefund. */
  requestedAmount: number;
  status: ComplaintStatus;
  evidence: ComplaintEvidence[];
  chefResponse: string | null;
  chefRespondedAt: ISODateString | null;
  decision: ComplaintDecision | null;
  /** Amount returned to the member (0 for ReleaseToChef). */
  refundAmount: number | null;
  adminNote: string | null;
  decidedBy: string | null;
  decidedAt: ISODateString | null;
  createdAt: ISODateString;
}

export interface PlanMeal {
  slot: MealSlot;
  recipe: { id: string; name: string; calories: number | null };
  note: string | null;
}

export interface DayFeedback {
  rating: number;
  adherence: Adherence;
  body: string;
  createdAt: ISODateString;
}

export interface PlanDay {
  dayIndex: number;
  date: DateOnly;
  status: PlanDayStatus;
  chefNote: string | null;
  sentAt: ISODateString | null;
  meals: PlanMeal[];
  feedback: DayFeedback | null;
}

export interface BookingMessage {
  id: string;
  senderId: string | null;
  senderRole: BookingParty | "system";
  kind: MessageKind;
  body: string;
  offerId: string | null;
  /** Joined offer for Offer messages (computed by BE). */
  offer: BookingOffer | null;
  attachmentUrl: string | null;
  createdAt: ISODateString;
}

/** BookingDto (shared with the app). */
export interface Booking {
  id: string;
  member: BookingPerson;
  chef: BookingPerson;
  bookingType: BookingType;
  planDays: number;
  startDate: DateOnly;
  goal: string;
  allergies: string[];
  mealPattern: MealSlot[];
  budgetPerDay: number | null;
  needs: string;
  shareHealthProfile: boolean;
  status: BookingStatus;
  /** Plan days with status Sent. */
  deliveredDays: number;
  currentOffer: BookingOffer | null;
  contract: BookingContract | null;
  escrow: EscrowHold | null;
  complaint: Complaint | null;
  paymentOrderId: string | null;
  declineReason: string | null;
  cancelReason: string | null;
  createdAt: ISODateString;
  updatedAt: ISODateString;
}

/** Compact booking joined into escrow-hold rows. */
export interface BookingRef {
  id: string;
  member: BookingPerson;
  chef: BookingPerson;
  bookingType: BookingType;
  planDays: number;
  startDate: DateOnly;
  endDate: DateOnly | null;
  status: BookingStatus;
  deliveredDays: number;
  complaintId: string | null;
  paymentOrderId: string | null;
}

/** GET /admin/complaints[/{id}] */
export interface AdminComplaint extends Complaint {
  booking: Booking;
  /** Detail only (empty in list responses). */
  planDays: PlanDay[];
  /** Detail only: the read-only chat transcript, oldest first. */
  messages: BookingMessage[];
}

export interface AdminEscrowHold extends EscrowHold {
  booking: BookingRef;
}

/** GET /admin/escrow/summary */
export interface EscrowSummary {
  /** Held + Frozen. */
  totalHeld: number;
  totalHeldCount: number;
  /** Held (no complaint) with releaseAt within the next ESCROW_HOLD_DAYS days. */
  releasingSoon: number;
  releasingSoonCount: number;
  frozen: number;
  frozenCount: number;
  /** Fee of releases (full or split) whose releasedAt falls in the current month (server time zone). */
  feeThisMonth: number;
  releasedThisMonth: number;
  releasedThisMonthCount: number;
  refundedThisMonth: number;
  openComplaints: number;
  feeRate: number;
  holdDays: number;
}

/* ---------------------------------------------------------------- queries */

export interface ComplaintQuery {
  status: ComplaintStatus;
  /** Complaint / booking id, member, chef or reason. */
  search: string;
}

/** "active" = Held + Frozen. */
export type EscrowHoldFilter = EscrowStatus | "active" | "all";

export interface EscrowHoldQuery {
  status: EscrowHoldFilter;
  search: string;
}

/** POST /admin/complaints/{id}/decision */
export interface ComplaintDecisionInput {
  complaintId: string;
  decision: ComplaintDecision;
  /** Split only: 1.000 ≤ refundAmount < price. */
  refundAmount?: number;
  note: string;
}

/* ---------------------------------------------------------------- decision math */

export interface DecisionOutcome {
  /** Back to the member's original payment method. */
  refund: number;
  /** Released to the chef before the fee: price − refund. */
  chefGross: number;
  fee: number;
  /** What lands in "Có thể rút": chefGross − fee. */
  chefNet: number;
}

/** Money split of a decision. Same rounding as the wallet (fee to whole đồng). */
export function decisionOutcome(price: number, decision: ComplaintDecision, refundAmount?: number | null): DecisionOutcome {
  const refund = decision === "RefundMember" ? price : decision === "Split" ? Math.max(0, Math.min(price, refundAmount ?? 0)) : 0;
  const chefGross = price - refund;
  const fee = Math.round(chefGross * PLATFORM_FEE_RATE);
  return { refund, chefGross, fee, chefNet: chefGross - fee };
}

export type DecisionErrors = Partial<Record<"decision" | "refundAmount" | "note", string>>;

const vndText = new Intl.NumberFormat("vi-VN");

/** Field errors for the decision form (empty = valid). Same rules as the server (400). */
export function decisionErrors(
  input: { decision: ComplaintDecision | null; refundAmount?: number; note: string },
  price: number,
): DecisionErrors {
  const errors: DecisionErrors = {};
  if (!input.decision) errors.decision = "Chọn cách xử lý.";
  if (input.decision === "Split") {
    const x = input.refundAmount;
    if (x === undefined || !Number.isInteger(x)) errors.refundAmount = "Nhập số tiền hoàn (đồng).";
    else if (x < MIN_PARTIAL_REFUND) errors.refundAmount = `Hoàn tối thiểu ${vndText.format(MIN_PARTIAL_REFUND)}đ.`;
    else if (x >= price) errors.refundAmount = `Phải nhỏ hơn giá hợp đồng ${vndText.format(price)}đ — hoàn toàn bộ thì chọn “Hoàn toàn bộ cho thành viên”.`;
  }
  if (input.note.trim().length < MIN_DECISION_NOTE) errors.note = `Ghi chú cần ít nhất ${MIN_DECISION_NOTE} ký tự.`;
  return errors;
}

/** "10 ngày · Có phản hồi mỗi ngày" */
export const planSummary = (b: Pick<Booking, "planDays" | "bookingType">) => `${b.planDays} ngày · ${BOOKING_TYPE_LABEL[b.bookingType]}`;
