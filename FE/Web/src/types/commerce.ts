// src/types/commerce.ts
// Orders and PaymentOS payments for /orders. Since the chef business moved to N-day meal-plan
// bookings, the only order type is a booking payment ("Đặt chuyên gia"): accepting an offer
// creates the contract and an orders row with booking_id; the paid money goes into escrow
// (types/bookings.ts). Services, consultations and access grants are deprecated.
// Wire values follow the SQL enums.
import type { BookingStatus, BookingType, DateOnly, EscrowHold } from "./bookings";
import type { ISODateString } from "./moderation";

/* ---------------------------------------------------------------- enums */

/** "Hoàn một phần" comes from a Split complaint decision on /disputes (proposed enum value). */
export const ORDER_STATUSES = ["Pending", "Paid", "Cancelled", "Refunded", "PartiallyRefunded"] as const;
export type OrderStatus = (typeof ORDER_STATUSES)[number];

export const ORDER_STATUS_LABEL: Record<OrderStatus, string> = {
  Pending: "Chờ thanh toán",
  Paid: "Đã thanh toán",
  Cancelled: "Đã huỷ",
  Refunded: "Đã hoàn tiền",
  PartiallyRefunded: "Hoàn một phần",
};

/** The single order type left (shown in the "Loại" column). */
export const ORDER_TYPE_LABEL = "Đặt chuyên gia";

export const PAYMENT_PROVIDERS = ["PaymentOS"] as const;
export type PaymentProvider = (typeof PAYMENT_PROVIDERS)[number];

export const PAYMENT_STATUSES = ["Pending", "Paid", "Failed", "Expired", "Refunded"] as const;
export type PaymentStatus = (typeof PAYMENT_STATUSES)[number];

export const PAYMENT_STATUS_LABEL: Record<PaymentStatus, string> = {
  Pending: "Chờ thanh toán",
  Paid: "Đã thanh toán",
  Failed: "Thất bại",
  Expired: "Hết hạn",
  Refunded: "Đã hoàn tiền",
};

/* ---------------------------------------------------------------- rows */

/** payments (+ proposed expires_at / created_at). `amount` = orders.amount. */
export interface Payment {
  id: string;
  orderId: string;
  provider: PaymentProvider;
  transactionRef: string;
  qrCodeUrl: string | null;
  status: PaymentStatus;
  amount: number;
  paidAt: ISODateString | null;
  expiresAt: ISODateString | null;
  createdAt: ISODateString | null;
}

/**
 * How the order was closed. `cancel`: an admin cancelled an unpaid order here.
 * `refund` / `partial_refund` / `release`: a complaint decision on /disputes (`complaintId`).
 */
export type OrderResolutionAction = "cancel" | "refund" | "partial_refund" | "release";

export interface OrderResolution {
  action: OrderResolutionAction;
  note: string;
  by: string;
  at: ISODateString;
  complaintId: string | null;
}

/** Joined booking (computed by BE from chef_bookings + booking_contracts + users). */
export interface OrderBooking {
  id: string;
  chefId: string;
  chefName: string;
  bookingType: BookingType;
  planDays: number;
  startDate: DateOnly;
  endDate: DateOnly;
  status: BookingStatus;
  /** Plan days already sent by the chef. */
  deliveredDays: number;
  complaintId: string | null;
}

export interface AdminOrder {
  id: string;
  userId: string;
  /** Computed by BE (join users). */
  buyer: { id: string; fullName: string; email: string };
  bookingId: string;
  booking: OrderBooking;
  /** = contract price (VND). */
  amount: number;
  status: OrderStatus;
  createdAt: ISODateString;
  /** Oldest first; a new QR after Expired/Failed adds a row. */
  payments: Payment[];
  /** The escrow hold funded by this order; null until paid. */
  escrow: EscrowHold | null;
  /** Sent back to the member (full or partial). */
  refundedAmount: number;
  resolution: OrderResolution | null;
}

export interface OrderQuery {
  status: OrderStatus | "all";
  /** Order id, booking id, transaction ref, member or chef. */
  search: string;
}

/** Refunds are complaint decisions on /disputes now; only an unpaid order can be cancelled here. */
export type OrderAction = "cancel";

/**
 * POST /admin/orders/{id}/cancel { note } — note ≥ 10 chars, Pending only (409 `not_pending`).
 * Closes the open QR codes and cancels the booking (the member can request again).
 */
export interface OrderActionInput {
  orderId: string;
  action: OrderAction;
  note: string;
}

/** GET /admin/commerce/summary */
export interface CommerceSummary {
  /** Collected from paid booking orders minus refunds. */
  revenue: number;
  refundedAmount: number;
  pendingAmount: number;
  totalOrders: number;
  byStatus: Record<OrderStatus, number>;
  /** Money still in escrow (Held + Frozen). */
  heldAmount: number;
  heldCount: number;
}
