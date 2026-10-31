// src/lib/commerce_api.ts
// Booking payment orders (PaymentOS) for /orders. Remote responses are normalised: INT ids →
// strings, enum values matched case-insensitively, single `payment` → `payments`, booking either
// nested or flat (`bookingId` + `chefName`…).
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
import { ORDER_STATUSES, PAYMENT_STATUSES } from "@/types/commerce";

import { qs, request } from "./api_client";
import { isMock } from "./backend_modules";
import { readSession } from "./auth";
import { normalizeEscrow } from "./bookings_api";
import { readId } from "./ids";
import * as mock from "./mock_commerce";

/** Case-insensitive, ignores spaces and underscores; unknown → fallback. */
function pick<T extends string>(values: readonly T[], raw: unknown, fallback: T): T {
  if (typeof raw !== "string") return fallback;
  const key = (s: string) => s.replace(/[\s_]/g, "").toLowerCase();
  return values.find((v) => key(v) === key(raw)) ?? fallback;
}

const num = (raw: unknown, fallback = 0) => {
  const n = typeof raw === "number" ? raw : typeof raw === "string" ? Number(raw) : NaN;
  return Number.isFinite(n) ? n : fallback;
};

const optString = (raw: unknown) => (typeof raw === "string" && raw ? raw : null);

type Raw = Record<string, unknown>;
const obj = (raw: unknown): Raw | null => (raw && typeof raw === "object" && !Array.isArray(raw) ? (raw as Raw) : null);

const RESOLUTION_ACTIONS: readonly OrderResolutionAction[] = ["cancel", "refund", "partial_refund", "release"];

export function normalizePayment(raw: Raw, orderId = ""): Payment {
  return {
    id: readId(raw.id),
    orderId: readId(raw.orderId ?? orderId),
    provider: "PaymentOS",
    transactionRef: String(raw.transactionRef ?? ""),
    qrCodeUrl: optString(raw.qrCodeUrl),
    status: pick<PaymentStatus>(PAYMENT_STATUSES, raw.status, "Pending"),
    amount: num(raw.amount),
    paidAt: optString(raw.paidAt),
    expiresAt: optString(raw.expiresAt),
    createdAt: optString(raw.createdAt),
  };
}

export function normalizeOrder(raw: Raw): AdminOrder {
  const id = readId(raw.id);
  const booking = obj(raw.booking) ?? {};
  const buyer = obj(raw.buyer) ?? obj(raw.user) ?? {};
  const rawPayments = Array.isArray(raw.payments) ? raw.payments : obj(raw.payment) ? [raw.payment] : [];
  const escrow = obj(raw.escrow);
  const resolution = obj(raw.resolution);
  const action = RESOLUTION_ACTIONS.find((a) => a === resolution?.action) ?? null;
  return {
    id,
    userId: readId(raw.userId ?? buyer.id),
    buyer: {
      id: readId(buyer.id ?? raw.userId),
      fullName: String(buyer.fullName ?? buyer.name ?? "Người dùng"),
      email: String(buyer.email ?? ""),
    },
    bookingId: readId(raw.bookingId ?? booking.id),
    booking: {
      id: readId(booking.id ?? raw.bookingId),
      chefId: readId(booking.chefId ?? obj(booking.chef)?.id),
      chefName: String(booking.chefName ?? obj(booking.chef)?.fullName ?? ""),
      bookingType: pick<BookingType>(BOOKING_TYPES, booking.bookingType, "OneShot"),
      planDays: num(booking.planDays),
      startDate: String(booking.startDate ?? "").slice(0, 10),
      endDate: String(booking.endDate ?? "").slice(0, 10),
      status: pick<BookingStatus>(BOOKING_STATUSES, booking.status, "AwaitingPayment"),
      deliveredDays: num(booking.deliveredDays),
      complaintId: booking.complaintId === null || booking.complaintId === undefined ? null : readId(booking.complaintId),
    },
    amount: num(raw.amount),
    status: pick<OrderStatus>(ORDER_STATUSES, raw.status, "Pending"),
    createdAt: optString(raw.createdAt) ?? new Date(0).toISOString(),
    payments: rawPayments
      .map((p) => obj(p))
      .filter((p): p is Raw => p !== null)
      .map((p) => normalizePayment(p, id))
      .sort((a, b) => (a.createdAt ?? "").localeCompare(b.createdAt ?? "")),
    escrow: escrow ? normalizeEscrow(escrow) : null,
    refundedAmount: num(raw.refundedAmount),
    resolution:
      resolution && action
        ? {
            action,
            note: String(resolution.note ?? ""),
            by: String(resolution.by ?? ""),
            at: optString(resolution.at) ?? new Date(0).toISOString(),
            complaintId: resolution.complaintId === null || resolution.complaintId === undefined ? null : readId(resolution.complaintId),
          }
        : null,
  };
}

export const commerceApi = {
  /** GET /admin/orders?status=&search= */
  async listOrders(query: OrderQuery): Promise<AdminOrder[]> {
    if (isMock("commerce")) return mock.listOrders(query);
    const raw = await request<Raw[]>(`/admin/orders?${qs({ status: query.status === "all" ? undefined : query.status, search: query.search })}`);
    return raw.map(normalizeOrder);
  },

  /** GET /admin/orders/{id} */
  async getOrder(id: string): Promise<AdminOrder> {
    if (isMock("commerce")) return mock.getOrder(id);
    return normalizeOrder(await request<Raw>(`/admin/orders/${encodeURIComponent(id)}`));
  },

  /** POST /admin/orders/{id}/cancel { note } — unpaid orders only. */
  async act(input: OrderActionInput): Promise<AdminOrder> {
    if (isMock("commerce")) return mock.applyOrderAction(input, readSession());
    return normalizeOrder(
      await request<Raw>(`/admin/orders/${encodeURIComponent(input.orderId)}/${input.action}`, {
        method: "POST",
        body: JSON.stringify({ note: input.note }),
      }),
    );
  },

  /** GET /admin/commerce/summary */
  async summary(): Promise<CommerceSummary> {
    if (isMock("commerce")) return mock.getSummary();
    const raw = await request<Partial<CommerceSummary> & { byStatus?: Partial<Record<OrderStatus, number>> }>("/admin/commerce/summary");
    return {
      revenue: num(raw.revenue),
      refundedAmount: num(raw.refundedAmount),
      pendingAmount: num(raw.pendingAmount),
      totalOrders: num(raw.totalOrders),
      byStatus: Object.fromEntries(ORDER_STATUSES.map((s) => [s, num(raw.byStatus?.[s])])) as Record<OrderStatus, number>,
      heldAmount: num(raw.heldAmount),
      heldCount: num(raw.heldCount),
    };
  },
};
