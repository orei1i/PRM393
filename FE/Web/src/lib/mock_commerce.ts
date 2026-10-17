// src/lib/mock_commerce.ts
// Booking payments for /orders. Orders, PaymentOS payments and the escrow they fund live in
// mock_bookings.ts (one store, so a complaint decision on /disputes or an expired QR shows up
// here at once); this module filters, sorts and adds the admin "Huỷ đơn" for unpaid orders.
// Refunds are complaint decisions on /disputes now.
// QA: `#fail` in the search box or the cancel note → 503. Cancelling a non-pending order → 409.
import type { AdminSession } from "@/types/admin";
import type { AdminOrder, CommerceSummary, OrderActionInput, OrderQuery, OrderStatus } from "@/types/commerce";
import { ORDER_STATUSES } from "@/types/commerce";
import { MIN_AUDIT_NOTE_LENGTH } from "@/types/moderation";

import { ApiError } from "./api_error";
import { logAction } from "./mock_admin";
import { allOrders, cancelOrder } from "./mock_bookings";
import { sleep } from "./mock_data";

const fold = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[Đđ]/g, "d").toLowerCase();

const failIfAsked = (text: string, what: string) => {
  if (text.toLowerCase().includes("#fail")) {
    throw new ApiError(`Máy chủ đang bận, chưa ${what}. Thử lại sau.`, 503, "unavailable");
  }
};

/** GET /admin/orders?status=&search= */
export async function listOrders(query: OrderQuery): Promise<AdminOrder[]> {
  await sleep(450);
  failIfAsked(query.search, "tải được đơn hàng");
  const q = fold(query.search.trim());
  return allOrders()
    .filter((o) => query.status === "all" || o.status === query.status)
    .filter(
      (o) =>
        !q ||
        fold(
          [o.id, o.bookingId, o.buyer.fullName, o.buyer.email, o.booking.chefName, o.booking.complaintId ?? "", ...o.payments.map((p) => p.transactionRef)].join(" "),
        ).includes(q),
    )
    .sort((x, y) => y.createdAt.localeCompare(x.createdAt));
}

/** GET /admin/orders/{id} */
export async function getOrder(id: string): Promise<AdminOrder> {
  await sleep(300);
  const order = allOrders().find((o) => o.id === id);
  if (!order) throw new ApiError("Đơn hàng không còn tồn tại.", 404, "not_found");
  return order;
}

/** GET /admin/commerce/summary */
export async function getSummary(): Promise<CommerceSummary> {
  await sleep(300);
  const list = allOrders();
  const byStatus = Object.fromEntries(ORDER_STATUSES.map((s) => [s, 0])) as Record<OrderStatus, number>;
  let revenue = 0;
  let refundedAmount = 0;
  let pendingAmount = 0;
  let heldAmount = 0;
  let heldCount = 0;
  for (const o of list) {
    byStatus[o.status] += 1;
    if (o.status === "Paid" || o.status === "PartiallyRefunded" || o.status === "Refunded") revenue += o.amount - o.refundedAmount;
    refundedAmount += o.refundedAmount;
    if (o.status === "Pending") pendingAmount += o.amount;
    if (o.escrow && (o.escrow.status === "Held" || o.escrow.status === "Frozen")) {
      heldAmount += o.escrow.amount;
      heldCount += 1;
    }
  }
  return { revenue, refundedAmount, pendingAmount, totalOrders: list.length, byStatus, heldAmount, heldCount };
}

/** POST /admin/orders/{id}/cancel { note } — Pending only: QR codes close, the booking is cancelled. */
export async function applyOrderAction(input: OrderActionInput, session: AdminSession | null): Promise<AdminOrder> {
  await sleep(700);
  const note = input.note.trim();
  if (note.length < MIN_AUDIT_NOTE_LENGTH) {
    throw new ApiError(`Ghi chú cần ít nhất ${MIN_AUDIT_NOTE_LENGTH} ký tự.`, 400, "note_too_short");
  }
  failIfAsked(note, "huỷ được đơn");
  const actor = session?.fullName ?? "Quản trị viên";
  const order = cancelOrder(input.orderId, note, actor);
  logAction(actor, "huỷ đơn đặt chuyên gia", `${order.id} · ${order.buyer.fullName} → ${order.booking.chefName}`);
  return order;
}
