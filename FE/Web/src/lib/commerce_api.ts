// src/lib/commerce_api.ts
// Orders, PaymentOS payments, access grants and per-chef services for /orders.
// Remote responses are normalised: INT ids → strings, enum values matched
// case-insensitively ("VipMenu" / "VIP_MENU" → "VIP Menu"), single `payment` → `payments`.
import type {
  AccessGrant,
  AdminOrder,
  AdminService,
  CommerceSummary,
  ConsultationStatus,
  GrantStatus,
  OrderAction,
  OrderActionInput,
  OrderQuery,
  OrderStatus,
  Payment,
  PaymentStatus,
  ServiceQuery,
  ServiceType,
} from "@/types/commerce";
import { CONSULTATION_STATUSES, GRANT_STATUSES, ORDER_STATUSES, PAYMENT_STATUSES, SERVICE_TYPES } from "@/types/commerce";

import { qs, request, USE_MOCK_DATA } from "./api_client";
import { readSession } from "./auth";
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

export function normalizeGrant(raw: Raw): AccessGrant {
  return {
    id: readId(raw.id),
    paymentId: readId(raw.paymentId),
    grantedAt: optString(raw.grantedAt) ?? new Date(0).toISOString(),
    expiresAt: optString(raw.expiresAt),
    status: pick<GrantStatus>(GRANT_STATUSES, raw.status, "Active"),
  };
}

export function normalizeOrder(raw: Raw): AdminOrder {
  const id = readId(raw.id);
  const service = obj(raw.service) ?? {};
  const buyer = obj(raw.buyer) ?? obj(raw.user) ?? {};
  const rawPayments = Array.isArray(raw.payments) ? raw.payments : obj(raw.payment) ? [raw.payment] : [];
  const grant = obj(raw.accessGrant);
  const consultation = obj(raw.consultation);
  const resolution = obj(raw.resolution);
  const rawAction = resolution?.action;
  const resolutionAction: OrderAction | null = rawAction === "refund" || rawAction === "cancel" ? rawAction : null;
  return {
    id,
    userId: readId(raw.userId ?? buyer.id),
    buyer: {
      id: readId(buyer.id ?? raw.userId),
      fullName: String(buyer.fullName ?? buyer.name ?? "Người dùng"),
      email: String(buyer.email ?? ""),
    },
    serviceId: readId(raw.serviceId ?? service.id),
    service: {
      id: readId(service.id ?? raw.serviceId),
      title: String(service.title ?? ""),
      type: pick<ServiceType>(SERVICE_TYPES, service.type, "Consult"),
      chefId: readId(service.chefId),
      chefName: String(service.chefName ?? ""),
    },
    amount: num(raw.amount),
    status: pick<OrderStatus>(ORDER_STATUSES, raw.status, "Pending"),
    createdAt: optString(raw.createdAt) ?? new Date(0).toISOString(),
    payments: rawPayments
      .map((p) => obj(p))
      .filter((p): p is Raw => p !== null)
      .map((p) => normalizePayment(p, id))
      .sort((a, b) => (a.createdAt ?? "").localeCompare(b.createdAt ?? "")),
    accessGrant: grant ? normalizeGrant(grant) : null,
    consultation: consultation
      ? {
          id: readId(consultation.id),
          startAt: optString(consultation.startAt) ?? new Date(0).toISOString(),
          status: pick<ConsultationStatus>(CONSULTATION_STATUSES, consultation.status, "Pending"),
          durationMinutes: consultation.durationMinutes === undefined || consultation.durationMinutes === null ? null : num(consultation.durationMinutes),
        }
      : null,
    resolution:
      resolution && resolutionAction
        ? {
            action: resolutionAction,
            note: String(resolution.note ?? ""),
            by: String(resolution.by ?? ""),
            at: optString(resolution.at) ?? new Date(0).toISOString(),
          }
        : null,
  };
}

export function normalizeService(raw: Raw): AdminService {
  return {
    id: readId(raw.id),
    chefId: readId(raw.chefId),
    chefName: String(raw.chefName ?? ""),
    title: String(raw.title ?? ""),
    type: pick<ServiceType>(SERVICE_TYPES, raw.type, "Consult"),
    price: num(raw.price),
    orderCount: num(raw.orderCount),
    paidCount: num(raw.paidCount),
    revenue: num(raw.revenue),
  };
}

export const commerceApi = {
  /** GET /admin/orders?status=&type=&search= */
  async listOrders(query: OrderQuery): Promise<AdminOrder[]> {
    if (USE_MOCK_DATA) return mock.listOrders(query);
    const raw = await request<Raw[]>(
      `/admin/orders?${qs({
        status: query.status === "all" ? undefined : query.status,
        type: query.type === "all" ? undefined : query.type,
        search: query.search,
      })}`,
    );
    return raw.map(normalizeOrder);
  },

  /** GET /admin/orders/{id} */
  async getOrder(id: string): Promise<AdminOrder> {
    if (USE_MOCK_DATA) return mock.getOrder(id);
    return normalizeOrder(await request<Raw>(`/admin/orders/${encodeURIComponent(id)}`));
  },

  /** POST /admin/orders/{id}/refund | /cancel { note } — status change only, no money moves. */
  async act(input: OrderActionInput): Promise<AdminOrder> {
    if (USE_MOCK_DATA) return mock.applyOrderAction(input, readSession());
    return normalizeOrder(
      await request<Raw>(`/admin/orders/${encodeURIComponent(input.orderId)}/${input.action}`, {
        method: "POST",
        body: JSON.stringify({ note: input.note }),
      }),
    );
  },

  /** GET /admin/services?chefId=&search= — with order count, paid count and revenue per service. */
  async listServices(query: ServiceQuery): Promise<AdminService[]> {
    if (USE_MOCK_DATA) return mock.listServices(query);
    const raw = await request<Raw[]>(
      `/admin/services?${qs({ chefId: query.chefId === "all" ? undefined : query.chefId, search: query.search })}`,
    );
    return raw.map(normalizeService);
  },

  /** GET /admin/commerce/summary */
  async summary(): Promise<CommerceSummary> {
    if (USE_MOCK_DATA) return mock.getSummary();
    const raw = await request<Partial<CommerceSummary> & { byStatus?: Partial<Record<OrderStatus, number>> }>("/admin/commerce/summary");
    return {
      revenue: num(raw.revenue),
      refundedAmount: num(raw.refundedAmount),
      pendingAmount: num(raw.pendingAmount),
      totalOrders: num(raw.totalOrders),
      byStatus: Object.fromEntries(ORDER_STATUSES.map((s) => [s, num(raw.byStatus?.[s])])) as Record<OrderStatus, number>,
      activeGrants: num(raw.activeGrants),
    };
  },
};
