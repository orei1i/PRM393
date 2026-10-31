// src/lib/bookings_api.ts
// Complaints and escrow holds of chef meal-plan bookings for /disputes ("Khiếu nại & giữ tiền").
// Remote rows are normalised: INT ids → strings, enum values matched case-insensitively,
// nested people either `{ id, fullName }` or flat `memberId` / `memberName`, missing lists → [].
//
// | Method | Path                                   | Body / notes                                                    |
// |--------|----------------------------------------|-----------------------------------------------------------------|
// | GET    | /admin/complaints?status=&search=      | AdminComplaint[] (status Open | Resolved; no planDays/messages) |
// | GET    | /admin/complaints/{id}                 | AdminComplaint with planDays + messages (read-only transcript)  |
// | POST   | /admin/complaints/{id}/decision        | { decision, refundAmount?, note } → AdminComplaint              |
// |        |                                        | 400 note_too_short / invalid_refund_amount, 409 already_decided |
// | GET    | /admin/escrow/summary                  | EscrowSummary                                                   |
// | GET    | /admin/escrow/holds?status=&search=    | AdminEscrowHold[] (status: active = Held + Frozen, or one value)|
//
// Money moves on the BE (PaymentOS refund to the original payment method / chef wallet credit).
// Wire samples and the proposed tables are in src/types/bookings.ts.
import type {
  Adherence,
  AdminComplaint,
  AdminEscrowHold,
  Booking,
  BookingContract,
  BookingMessage,
  BookingOffer,
  BookingParty,
  BookingPerson,
  BookingRef,
  BookingStatus,
  BookingType,
  Complaint,
  ComplaintDecision,
  ComplaintDecisionInput,
  ComplaintEvidence,
  ComplaintQuery,
  ComplaintReason,
  ComplaintStatus,
  EscrowHold,
  EscrowHoldQuery,
  EscrowStatus,
  EscrowSummary,
  EvidenceKind,
  MealSlot,
  MessageKind,
  OfferStatus,
  PlanDay,
  PlanDayStatus,
  RequestedOutcome,
} from "@/types/bookings";
import {
  ADHERENCE_VALUES,
  BOOKING_STATUSES,
  BOOKING_TYPES,
  COMPLAINT_DECISIONS,
  COMPLAINT_REASONS,
  COMPLAINT_STATUSES,
  ESCROW_STATUSES,
  EVIDENCE_KINDS,
  MEAL_SLOTS,
  MESSAGE_KINDS,
  OFFER_STATUSES,
  PLAN_DAY_STATUSES,
  REQUESTED_OUTCOMES,
} from "@/types/bookings";
import { ESCROW_HOLD_DAYS, PLATFORM_FEE_RATE } from "@/types/payouts";

import { qs, request } from "./api_client";
import { isMock } from "./backend_modules";
import { readSession } from "./auth";
import { readId } from "./ids";
import * as mock from "./mock_bookings";

type Raw = Record<string, unknown>;
const obj = (raw: unknown): Raw | null => (raw && typeof raw === "object" && !Array.isArray(raw) ? (raw as Raw) : null);
const list = (raw: unknown): Raw[] => (Array.isArray(raw) ? raw.map(obj).filter((x): x is Raw => x !== null) : []);

/** Case-insensitive, ignores spaces and underscores; unknown → fallback. */
function pick<T extends string>(values: readonly T[], raw: unknown, fallback: T): T {
  if (typeof raw !== "string") return fallback;
  const key = (s: string) => s.replace(/[\s_-]/g, "").toLowerCase();
  return values.find((v) => key(v) === key(raw)) ?? fallback;
}

const num = (raw: unknown, fallback = 0) => {
  const n = typeof raw === "number" ? raw : typeof raw === "string" && raw.trim() !== "" ? Number(raw) : NaN;
  return Number.isFinite(n) ? n : fallback;
};
const optNum = (raw: unknown) => (raw === null || raw === undefined || raw === "" ? null : num(raw));
const optString = (raw: unknown) => (typeof raw === "string" && raw ? raw : null);
const isoOr = (raw: unknown) => optString(raw) ?? new Date(0).toISOString();
/** "2026-10-20T00:00:00" → "2026-10-20" */
const dateOnly = (raw: unknown) => (typeof raw === "string" ? raw.slice(0, 10) : "");
const party = (raw: unknown): BookingParty => (typeof raw === "string" && raw.toLowerCase() === "member" ? "member" : "chef");

function readPerson(raw: unknown, fallbackId?: unknown, fallbackName?: unknown): BookingPerson {
  const p = obj(raw);
  return {
    id: readId(p?.id ?? fallbackId),
    fullName: String(p?.fullName ?? p?.name ?? fallbackName ?? "Người dùng"),
    email: String(p?.email ?? ""),
  };
}

export function normalizeOffer(raw: Raw): BookingOffer {
  return {
    id: readId(raw.id),
    proposedBy: party(raw.proposedBy),
    price: num(raw.price),
    planDays: num(raw.planDays),
    bookingType: pick<BookingType>(BOOKING_TYPES, raw.bookingType, "OneShot"),
    startDate: dateOnly(raw.startDate),
    note: String(raw.note ?? ""),
    status: pick<OfferStatus>(OFFER_STATUSES, raw.status, "Open"),
    createdAt: isoOr(raw.createdAt),
    respondedAt: optString(raw.respondedAt),
  };
}

export function normalizeContract(raw: Raw): BookingContract {
  return {
    id: readId(raw.id),
    bookingId: readId(raw.bookingId),
    offerId: readId(raw.offerId),
    price: num(raw.price),
    planDays: num(raw.planDays),
    bookingType: pick<BookingType>(BOOKING_TYPES, raw.bookingType, "OneShot"),
    startDate: dateOnly(raw.startDate),
    endDate: dateOnly(raw.endDate),
    deliveryDueAt: isoOr(raw.deliveryDueAt),
    dailySendCutoff: String(raw.dailySendCutoff ?? "06:00"),
    feedbackCutoff: String(raw.feedbackCutoff ?? "21:00"),
    scopeText: String(raw.scopeText ?? ""),
    feeRate: num(raw.feeRate, PLATFORM_FEE_RATE),
    holdDays: num(raw.holdDays, ESCROW_HOLD_DAYS),
    paymentDueAt: isoOr(raw.paymentDueAt),
    createdAt: isoOr(raw.createdAt),
  };
}

export function normalizeEscrow(raw: Raw): EscrowHold {
  return {
    id: readId(raw.id),
    bookingId: readId(raw.bookingId),
    paymentId: readId(raw.paymentId),
    amount: num(raw.amount),
    status: pick<EscrowStatus>(ESCROW_STATUSES, raw.status, "Held"),
    heldAt: isoOr(raw.heldAt),
    releaseAt: isoOr(raw.releaseAt),
    releasedAt: optString(raw.releasedAt),
    releasedAmount: num(raw.releasedAmount),
    feeAmount: num(raw.feeAmount),
    refundedAmount: num(raw.refundedAmount),
    resolvedBy: optString(raw.resolvedBy) ?? optString(obj(raw.resolvedBy)?.fullName),
    resolutionNote: optString(raw.resolutionNote),
  };
}

function normalizeEvidence(raw: Raw): ComplaintEvidence {
  return {
    id: readId(raw.id),
    kind: pick<EvidenceKind>(EVIDENCE_KINDS, raw.kind, "Link"),
    url: String(raw.url ?? ""),
    caption: optString(raw.caption),
    submittedBy: party(raw.submittedBy ?? raw.submittedByRole ?? "member"),
    createdAt: isoOr(raw.createdAt),
  };
}

export function normalizeComplaint(raw: Raw): Complaint {
  const decision = raw.decision === null || raw.decision === undefined ? null : pick<ComplaintDecision>(COMPLAINT_DECISIONS, raw.decision, "ReleaseToChef");
  return {
    id: readId(raw.id),
    bookingId: readId(raw.bookingId),
    reason: pick<ComplaintReason>(COMPLAINT_REASONS, raw.reason, "other"),
    description: String(raw.description ?? ""),
    requestedOutcome: pick<RequestedOutcome>(REQUESTED_OUTCOMES, raw.requestedOutcome, "FullRefund"),
    requestedAmount: num(raw.requestedAmount),
    status: pick<ComplaintStatus>(COMPLAINT_STATUSES, raw.status, "Open"),
    evidence: list(raw.evidence).map(normalizeEvidence),
    chefResponse: optString(raw.chefResponse),
    chefRespondedAt: optString(raw.chefRespondedAt),
    decision,
    refundAmount: optNum(raw.refundAmount),
    adminNote: optString(raw.adminNote),
    decidedBy: optString(raw.decidedBy) ?? optString(obj(raw.decidedBy)?.fullName),
    decidedAt: optString(raw.decidedAt),
    createdAt: isoOr(raw.createdAt),
  };
}

function normalizePlanDay(raw: Raw): PlanDay {
  const feedback = obj(raw.feedback);
  return {
    dayIndex: num(raw.dayIndex),
    date: dateOnly(raw.date),
    status: pick<PlanDayStatus>(PLAN_DAY_STATUSES, raw.status, "Draft"),
    chefNote: optString(raw.chefNote),
    sentAt: optString(raw.sentAt),
    meals: list(raw.meals).map((m) => {
      const recipe = obj(m.recipe) ?? {};
      return {
        slot: pick<MealSlot>(MEAL_SLOTS, m.slot ?? m.mealType, "lunch"),
        recipe: { id: readId(recipe.id ?? m.recipeId), name: String(recipe.name ?? m.recipeName ?? "Món ăn"), calories: optNum(recipe.calories) },
        note: optString(m.note),
      };
    }),
    feedback: feedback
      ? {
          rating: Math.min(5, Math.max(1, Math.round(num(feedback.rating, 1)))),
          adherence: pick<Adherence>(ADHERENCE_VALUES, feedback.adherence, "Partly"),
          body: String(feedback.body ?? ""),
          createdAt: isoOr(feedback.createdAt),
        }
      : null,
  };
}

function normalizeMessage(raw: Raw): BookingMessage {
  const offer = obj(raw.offer);
  const role = typeof raw.senderRole === "string" ? raw.senderRole.toLowerCase() : raw.senderId === null || raw.senderId === undefined ? "system" : "member";
  return {
    id: readId(raw.id),
    senderId: raw.senderId === null || raw.senderId === undefined ? null : readId(raw.senderId),
    senderRole: role === "system" ? "system" : party(role),
    kind: pick<MessageKind>(MESSAGE_KINDS, raw.kind, "Text"),
    body: String(raw.body ?? ""),
    offerId: raw.offerId === null || raw.offerId === undefined ? null : readId(raw.offerId),
    offer: offer ? normalizeOffer(offer) : null,
    attachmentUrl: optString(raw.attachmentUrl),
    createdAt: isoOr(raw.createdAt),
  };
}

export function normalizeBooking(raw: Raw): Booking {
  const offer = obj(raw.currentOffer);
  const contract = obj(raw.contract);
  const escrow = obj(raw.escrow);
  const complaint = obj(raw.complaint);
  return {
    id: readId(raw.id),
    member: readPerson(raw.member, raw.memberId, raw.memberName),
    chef: readPerson(raw.chef, raw.chefId, raw.chefName),
    bookingType: pick<BookingType>(BOOKING_TYPES, raw.bookingType, "OneShot"),
    planDays: num(raw.planDays),
    startDate: dateOnly(raw.startDate),
    goal: String(raw.goal ?? ""),
    allergies: Array.isArray(raw.allergies) ? raw.allergies.map((a) => String(obj(a)?.name ?? a)) : [],
    mealPattern: Array.isArray(raw.mealPattern) ? raw.mealPattern.map((s) => pick<MealSlot>(MEAL_SLOTS, s, "lunch")) : [],
    budgetPerDay: optNum(raw.budgetPerDay),
    needs: String(raw.needs ?? ""),
    shareHealthProfile: raw.shareHealthProfile !== false,
    status: pick<BookingStatus>(BOOKING_STATUSES, raw.status, "Requested"),
    deliveredDays: num(raw.deliveredDays),
    currentOffer: offer ? normalizeOffer(offer) : null,
    contract: contract ? normalizeContract(contract) : null,
    escrow: escrow ? normalizeEscrow(escrow) : null,
    complaint: complaint ? normalizeComplaint(complaint) : null,
    paymentOrderId: raw.paymentOrderId === null || raw.paymentOrderId === undefined ? null : readId(raw.paymentOrderId),
    declineReason: optString(raw.declineReason),
    cancelReason: optString(raw.cancelReason),
    createdAt: isoOr(raw.createdAt),
    updatedAt: isoOr(raw.updatedAt ?? raw.createdAt),
  };
}

export function normalizeAdminComplaint(raw: Raw): AdminComplaint {
  return {
    ...normalizeComplaint(raw),
    booking: normalizeBooking(obj(raw.booking) ?? {}),
    planDays: list(raw.planDays).map(normalizePlanDay).sort((a, b) => a.dayIndex - b.dayIndex),
    messages: list(raw.messages)
      .map(normalizeMessage)
      .sort((a, b) => a.createdAt.localeCompare(b.createdAt)),
  };
}

function normalizeBookingRef(raw: Raw): BookingRef {
  return {
    id: readId(raw.id),
    member: readPerson(raw.member, raw.memberId, raw.memberName),
    chef: readPerson(raw.chef, raw.chefId, raw.chefName),
    bookingType: pick<BookingType>(BOOKING_TYPES, raw.bookingType, "OneShot"),
    planDays: num(raw.planDays),
    startDate: dateOnly(raw.startDate),
    endDate: optString(raw.endDate)?.slice(0, 10) ?? null,
    status: pick<BookingStatus>(BOOKING_STATUSES, raw.status, "Active"),
    deliveredDays: num(raw.deliveredDays),
    complaintId: raw.complaintId === null || raw.complaintId === undefined ? null : readId(raw.complaintId),
    paymentOrderId: raw.paymentOrderId === null || raw.paymentOrderId === undefined ? null : readId(raw.paymentOrderId),
  };
}

export function normalizeHold(raw: Raw): AdminEscrowHold {
  return { ...normalizeEscrow(raw), booking: normalizeBookingRef(obj(raw.booking) ?? {}) };
}

export const bookingsApi = {
  /** GET /admin/complaints?status=&search= */
  async listComplaints(query: ComplaintQuery): Promise<AdminComplaint[]> {
    if (isMock("bookings")) return mock.listComplaints(query);
    const raw = await request<Raw[]>(`/admin/complaints?${qs({ status: query.status, search: query.search })}`);
    return raw.map(normalizeAdminComplaint);
  },

  /** GET /admin/complaints/{id} */
  async getComplaint(id: string): Promise<AdminComplaint> {
    if (isMock("bookings")) return mock.getComplaint(id);
    return normalizeAdminComplaint(await request<Raw>(`/admin/complaints/${encodeURIComponent(id)}`));
  },

  /** POST /admin/complaints/{id}/decision { decision, refundAmount?, note } */
  async decide(input: ComplaintDecisionInput): Promise<AdminComplaint> {
    if (isMock("bookings")) return mock.decideComplaint(input, readSession());
    return normalizeAdminComplaint(
      await request<Raw>(`/admin/complaints/${encodeURIComponent(input.complaintId)}/decision`, {
        method: "POST",
        body: JSON.stringify({
          decision: input.decision,
          refundAmount: input.decision === "Split" ? input.refundAmount : undefined,
          note: input.note,
        }),
      }),
    );
  },

  /** GET /admin/escrow/summary */
  async summary(): Promise<EscrowSummary> {
    if (isMock("bookings")) return mock.getEscrowSummary();
    const raw = await request<Raw>("/admin/escrow/summary");
    return {
      totalHeld: num(raw.totalHeld),
      totalHeldCount: num(raw.totalHeldCount),
      releasingSoon: num(raw.releasingSoon),
      releasingSoonCount: num(raw.releasingSoonCount),
      frozen: num(raw.frozen),
      frozenCount: num(raw.frozenCount),
      feeThisMonth: num(raw.feeThisMonth),
      releasedThisMonth: num(raw.releasedThisMonth),
      releasedThisMonthCount: num(raw.releasedThisMonthCount),
      refundedThisMonth: num(raw.refundedThisMonth),
      openComplaints: num(raw.openComplaints),
      feeRate: num(raw.feeRate, PLATFORM_FEE_RATE),
      holdDays: num(raw.holdDays, ESCROW_HOLD_DAYS),
    };
  },

  /** GET /admin/escrow/holds?status=&search= */
  async listHolds(query: EscrowHoldQuery): Promise<AdminEscrowHold[]> {
    if (isMock("bookings")) return mock.listEscrowHolds(query);
    const raw = await request<Raw[]>(`/admin/escrow/holds?${qs({ status: query.status === "all" ? undefined : query.status, search: query.search })}`);
    return raw.map(normalizeHold);
  },
};
