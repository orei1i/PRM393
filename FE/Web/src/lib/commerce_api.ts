// src/lib/commerce_api.ts
// Booking payment orders (PaymentOS) for /orders. Remote responses are normalised: INT ids →
// strings, enum values matched case-insensitively, single `payment` → `payments`, booking either
// nested or flat (`bookingId` + `chefName`…), no `provider` → PaymentOS (`Sandbox` stays itself:
// it must never read as a real gateway).
//
// | Method | Path                              | Body / notes                                              |
// |--------|-----------------------------------|-----------------------------------------------------------|
// | GET    | /admin/commerce/summary           | CommerceSummary                                           |
// | GET    | /admin/orders?status=&search=     | AdminOrder[] (booking payments only)                      |
// | GET    | /admin/orders/{id}                | AdminOrder                                                |
// | POST   | /admin/orders/{id}/cancel         | { note } (≥ 10 chars) → AdminOrder; 409 `not_pending`     |
//
// Refunds moved to complaint decisions (POST /admin/complaints/{id}/decision, bookings_api.ts).
// The services endpoints (/admin/services) are gone.
import type { BookingStatus, BookingType } from "@/types/bookings";
import { BOOKING_STATUSES, BOOKING_TYPES } from "@/types/bookings";
import type {
  AdminOrder,
  CommerceSummary,
  OrderActionInput,
  OrderQuery,
  OrderResolutionAction,
  OrderStatus,
  Payment,
  PaymentStatus,
} from "@/types/commerce";
import { ORDER_STATUSES, PAYMENT_PROVIDERS, PAYMENT_STATUSES } from "@/types/commerce";

import { qs, requestList, requestObject } from "./api_client";
import { isMock } from "./backend_modules";
import { readSession } from "./auth";
import { normalizeEscrow, readAllergies, readAudience } from "./bookings_api";
import { readId } from "./ids";
import * as mock from "./mock_commerce";
import { counts, dateOnly, hasId, isoOr, num, obj, objects, optIso, optText, pick, text, type Raw } from "./wire";

const RESOLUTION_ACTIONS: readonly OrderResolutionAction[] = ["cancel", "refund", "partial_refund", "release", "member_cancel", "admin_resolve"];

export function normalizePayment(raw: Raw, orderId = ""): Payment {
  return {
    id: readId(raw.id),
    orderId: readId(raw.orderId ?? orderId),
    provider: pick(PAYMENT_PROVIDERS, raw.provider, "PaymentOS"),
    transactionRef: text(raw.transactionRef),
    qrCodeUrl: optText(raw.qrCodeUrl),
    status: pick<PaymentStatus>(PAYMENT_STATUSES, raw.status, "Pending"),
    amount: num(raw.amount),
    paidAt: optIso(raw.paidAt),
    expiresAt: optIso(raw.expiresAt),
    createdAt: optIso(raw.createdAt),
  };
}

export function normalizeOrder(raw: Raw): AdminOrder {
  const id = readId(raw.id);
  const booking = obj(raw.booking) ?? {};
  const buyer = obj(raw.buyer) ?? obj(raw.user) ?? {};
  const rawPayments = Array.isArray(raw.payments) ? raw.payments : obj(raw.payment) ? [raw.payment] : [];
  const chef = obj(booking.chef);
  const escrow = obj(raw.escrow);
  const resolution = obj(raw.resolution);
  const action = RESOLUTION_ACTIONS.find((a) => a === resolution?.action) ?? null;
  return {
    id,
    userId: readId(raw.userId ?? buyer.id),
    buyer: {
      id: readId(buyer.id ?? raw.userId),
      fullName: text(buyer.fullName ?? buyer.name, "Người dùng"),
      email: text(buyer.email),
    },
    bookingId: readId(raw.bookingId ?? booking.id),
    booking: {
      id: readId(booking.id ?? raw.bookingId),
      chefId: readId(booking.chefId ?? chef?.id),
      chefName: text(booking.chefName ?? chef?.fullName),
      bookingType: pick<BookingType>(BOOKING_TYPES, booking.bookingType, "OneShot"),
      planDays: num(booking.planDays),
      startDate: dateOnly(booking.startDate),
      endDate: dateOnly(booking.endDate),
      ...readAudience(booking),
      allergies: readAllergies(booking.allergies),
      status: pick<BookingStatus>(BOOKING_STATUSES, booking.status, "AwaitingPayment"),
      deliveredDays: num(booking.deliveredDays),
      completedAt: optIso(booking.completedAt),
      autoCompleted: booking.autoCompleted === true,
      complaintId: booking.complaintId === null || booking.complaintId === undefined ? null : readId(booking.complaintId),
    },
    amount: num(raw.amount),
    status: pick<OrderStatus>(ORDER_STATUSES, raw.status, "Pending"),
    createdAt: isoOr(raw.createdAt),
    payments: objects(rawPayments)
      .map((p) => normalizePayment(p, id))
      .sort((a, b) => (a.createdAt ?? "").localeCompare(b.createdAt ?? "")),
    escrow: escrow ? normalizeEscrow(escrow) : null,
    refundedAmount: num(raw.refundedAmount),
    resolution:
      resolution && action
        ? {
            action,
            note: text(resolution.note),
            by: text(resolution.by),
            at: isoOr(resolution.at),
            complaintId: resolution.complaintId === null || resolution.complaintId === undefined ? null : readId(resolution.complaintId),
          }
        : null,
  };
}

export const commerceApi = {
  /** GET /admin/orders?status=&search= */
  async listOrders(query: OrderQuery): Promise<AdminOrder[]> {
    if (isMock("commerce")) return mock.listOrders(query);
    const raw = await requestList(`/admin/orders?${qs({ status: query.status === "all" ? undefined : query.status, search: query.search })}`);
    return raw.map(normalizeOrder).filter(hasId);
  },

  /** GET /admin/orders/{id} */
  async getOrder(id: string): Promise<AdminOrder> {
    if (isMock("commerce")) return mock.getOrder(id);
    return normalizeOrder(await requestObject(`/admin/orders/${encodeURIComponent(id)}`));
  },

  /** POST /admin/orders/{id}/cancel { note } — unpaid orders only. */
  async act(input: OrderActionInput): Promise<AdminOrder> {
    if (isMock("commerce")) return mock.applyOrderAction(input, readSession());
    return normalizeOrder(
      await requestObject(`/admin/orders/${encodeURIComponent(input.orderId)}/${input.action}`, {
        method: "POST",
        body: JSON.stringify({ note: input.note }),
      }),
    );
  },

  /** GET /admin/commerce/summary */
  async summary(): Promise<CommerceSummary> {
    if (isMock("commerce")) return mock.getSummary();
    const raw = await requestObject("/admin/commerce/summary");
    return {
      revenue: num(raw.revenue),
      refundedAmount: num(raw.refundedAmount),
      pendingAmount: num(raw.pendingAmount),
      totalOrders: num(raw.totalOrders),
      byStatus: counts(ORDER_STATUSES, raw.byStatus),
      heldAmount: num(raw.heldAmount),
      heldCount: num(raw.heldCount),
    };
  },
};
