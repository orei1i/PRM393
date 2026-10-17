// src/components/orders/order-badges.tsx
// Money/date formatters and status badges shared by the orders table and drawer (formatVnd is
// also used by /payouts, /ads and /disputes).
import { Ban, ChefHat, CircleCheck, CircleX, Hourglass, RotateCcw, Timer, Undo2 } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { ORDER_STATUS_LABEL, ORDER_TYPE_LABEL, PAYMENT_STATUS_LABEL, type OrderStatus, type PaymentStatus } from "@/types/commerce";

const vnd = new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND", maximumFractionDigits: 0 });

/** 350000 → "350.000 ₫" */
export const formatVnd = (amount: number) => vnd.format(amount);

export const dateVi = new Intl.DateTimeFormat("vi-VN", { day: "2-digit", month: "2-digit", year: "numeric" });
export const dateTimeVi = new Intl.DateTimeFormat("vi-VN", {
  hour: "2-digit",
  minute: "2-digit",
  day: "2-digit",
  month: "2-digit",
  year: "numeric",
});
export const formatDateTime = (iso: string) => dateTimeVi.format(new Date(iso));

/** The only order type left: a chef meal-plan booking payment. */
export function OrderTypeBadge() {
  return (
    <Badge variant="outline">
      <ChefHat aria-hidden />
      {ORDER_TYPE_LABEL}
    </Badge>
  );
}

export function OrderStatusBadge({ status }: { status: OrderStatus }) {
  switch (status) {
    case "Pending":
      return (
        <Badge variant="ochre">
          <Hourglass aria-hidden />
          {ORDER_STATUS_LABEL[status]}
        </Badge>
      );
    case "Paid":
      return (
        <Badge variant="sprout">
          <CircleCheck aria-hidden />
          {ORDER_STATUS_LABEL[status]}
        </Badge>
      );
    case "Cancelled":
      return (
        <Badge variant="secondary">
          <Ban aria-hidden />
          {ORDER_STATUS_LABEL[status]}
        </Badge>
      );
    case "Refunded":
      return (
        <Badge variant="ai">
          <RotateCcw aria-hidden />
          {ORDER_STATUS_LABEL[status]}
        </Badge>
      );
    case "PartiallyRefunded":
      return (
        <Badge variant="ai">
          <Undo2 aria-hidden />
          {ORDER_STATUS_LABEL[status]}
        </Badge>
      );
  }
}

export function PaymentStatusBadge({ status }: { status: PaymentStatus }) {
  switch (status) {
    case "Pending":
      return (
        <Badge variant="ochre">
          <Hourglass aria-hidden />
          {PAYMENT_STATUS_LABEL[status]}
        </Badge>
      );
    case "Paid":
      return (
        <Badge variant="sprout">
          <CircleCheck aria-hidden />
          {PAYMENT_STATUS_LABEL[status]}
        </Badge>
      );
    case "Failed":
      return (
        <Badge variant="outline" className="border-destructive/40 text-destructive">
          <CircleX aria-hidden />
          {PAYMENT_STATUS_LABEL[status]}
        </Badge>
      );
    case "Expired":
      return (
        <Badge variant="secondary">
          <Timer aria-hidden />
          {PAYMENT_STATUS_LABEL[status]}
        </Badge>
      );
    case "Refunded":
      return (
        <Badge variant="ai">
          <RotateCcw aria-hidden />
          {PAYMENT_STATUS_LABEL[status]}
        </Badge>
      );
  }
}
