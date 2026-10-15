// src/types/commerce.ts
// Commerce: services (per chef), orders, payments (PaymentOS), access_grants and the
// consultation linked to a Consult order. Wire values follow the SQL enums (plan D5).
import type { ISODateString } from "./moderation";

/* ---------------------------------------------------------------- enums */

export const SERVICE_TYPES = ["Consult", "Course", "VIP Menu"] as const;
export type ServiceType = (typeof SERVICE_TYPES)[number];

export const SERVICE_TYPE_LABEL: Record<ServiceType, string> = {
  Consult: "Tư vấn 1–1",
  Course: "Khoá học",
  "VIP Menu": "Thực đơn VIP",
};

export const ORDER_STATUSES = ["Pending", "Paid", "Cancelled", "Refunded"] as const;
export type OrderStatus = (typeof ORDER_STATUSES)[number];

export const ORDER_STATUS_LABEL: Record<OrderStatus, string> = {
  Pending: "Chờ thanh toán",
  Paid: "Đã thanh toán",
  Cancelled: "Đã huỷ",
  Refunded: "Đã hoàn tiền",
};

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

export const GRANT_STATUSES = ["Active", "Expired", "Revoked"] as const;
export type GrantStatus = (typeof GRANT_STATUSES)[number];

export const GRANT_STATUS_LABEL: Record<GrantStatus, string> = {
  Active: "Đang hiệu lực",
  Expired: "Hết hạn",
  Revoked: "Đã thu hồi",
};

export const CONSULTATION_STATUSES = [
  "AwaitingPayment",
  "Pending",
  "Confirmed",
  "InProgress",
  "Completed",
  "Declined",
  "Cancelled",
] as const;
export type ConsultationStatus = (typeof CONSULTATION_STATUSES)[number];

export const CONSULTATION_STATUS_LABEL: Record<ConsultationStatus, string> = {
  AwaitingPayment: "Chờ thanh toán",
  Pending: "Chờ chuyên gia xác nhận",
  Confirmed: "Đã xác nhận",
  InProgress: "Đang tư vấn",
  Completed: "Đã hoàn thành",
  Declined: "Chuyên gia từ chối",
  Cancelled: "Đã huỷ",
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

/** access_grants. A grant past `expiresAt` reads as Expired; a refund sets Revoked. */
export interface AccessGrant {
  id: string;
  paymentId: string;
  grantedAt: ISODateString;
  expiresAt: ISODateString | null;
  status: GrantStatus;
}

export interface OrderConsultation {
  id: string;
  startAt: ISODateString;
  status: ConsultationStatus;
  durationMinutes: number | null;
}

/** How an admin closed the order. Computed by BE from the audit log (proposed); null otherwise. */
export interface OrderResolution {
  action: OrderAction;
  note: string;
  by: string;
  at: ISODateString;
}

export interface AdminOrder {
  id: string;
  userId: string;
  /** Computed by BE (join users). */
  buyer: { id: string; fullName: string; email: string };
  serviceId: string;
  /** Computed by BE (join services + chef_profiles + users). */
  service: { id: string; title: string; type: ServiceType; chefId: string; chefName: string };
  /** Snapshot of the price at order time (VND). */
  amount: number;
  status: OrderStatus;
  createdAt: ISODateString;
  /** Oldest first; a new QR after Expired/Failed adds a row. */
  payments: Payment[];
  accessGrant: AccessGrant | null;
  consultation: OrderConsultation | null;
  resolution: OrderResolution | null;
}

export interface OrderQuery {
  status: OrderStatus | "all";
  type: ServiceType | "all";
  /** Order id, transaction ref, buyer, chef or service. */
  search: string;
}

export type OrderAction = "refund" | "cancel";

/**
 * POST /admin/orders/{id}/refund | /cancel { note } — note ≥ 10 chars.
 * Refund: Paid only (409 otherwise). Cancel: Pending only (409 otherwise).
 * Status change only — no money moves (refunds are done manually in PaymentOS).
 */
export interface OrderActionInput {
  orderId: string;
  action: OrderAction;
  note: string;
}

/** services + per-service aggregates computed by BE. */
export interface AdminService {
  id: string;
  chefId: string;
  chefName: string;
  title: string;
  type: ServiceType;
  price: number;
  /** All orders, any status. */
  orderCount: number;
  /** Orders currently Paid. */
  paidCount: number;
  /** Sum of `amount` over Paid orders (refunds excluded). */
  revenue: number;
}

export interface ServiceQuery {
  chefId: string | "all";
  search: string;
}

/** GET /admin/commerce/summary */
export interface CommerceSummary {
  /** Sum over Paid orders: collected minus refunded. */
  revenue: number;
  refundedAmount: number;
  pendingAmount: number;
  totalOrders: number;
  byStatus: Record<OrderStatus, number>;
  /** access_grants Active and not past expiresAt. */
  activeGrants: number;
}
