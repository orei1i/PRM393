// src/components/orders/order-badges.tsx
// Money/date formatters and status badges shared by the orders table, drawer and services tab.
import {
  Ban,
  CalendarCheck,
  CircleCheck,
  CircleDashed,
  CircleX,
  Crown,
  GraduationCap,
  Hourglass,
  KeyRound,
  MessagesSquare,
  RotateCcw,
  Timer,
} from "lucide-react";

import { Badge } from "@/components/ui/badge";
import {
  CONSULTATION_STATUS_LABEL,
  GRANT_STATUS_LABEL,
  ORDER_STATUS_LABEL,
  PAYMENT_STATUS_LABEL,
  SERVICE_TYPE_LABEL,
  type ConsultationStatus,
  type GrantStatus,
  type OrderStatus,
  type PaymentStatus,
  type ServiceType,
} from "@/types/commerce";

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

export function ServiceTypeBadge({ type }: { type: ServiceType }) {
  const Icon = type === "Consult" ? MessagesSquare : type === "Course" ? GraduationCap : Crown;
  return (
    <Badge variant="outline">
      <Icon aria-hidden />
      {SERVICE_TYPE_LABEL[type]}
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

export function GrantStatusBadge({ status }: { status: GrantStatus }) {
  switch (status) {
    case "Active":
      return (
        <Badge variant="sprout">
          <KeyRound aria-hidden />
          {GRANT_STATUS_LABEL[status]}
        </Badge>
      );
    case "Expired":
      return (
        <Badge variant="secondary">
          <Timer aria-hidden />
          {GRANT_STATUS_LABEL[status]}
        </Badge>
      );
    case "Revoked":
      return (
        <Badge variant="outline" className="border-destructive/40 text-destructive">
          <Ban aria-hidden />
          {GRANT_STATUS_LABEL[status]}
        </Badge>
      );
  }
}

export function ConsultationStatusBadge({ status }: { status: ConsultationStatus }) {
  const variant =
    status === "AwaitingPayment" || status === "Pending"
      ? "ochre"
      : status === "Confirmed" || status === "Completed"
        ? "sprout"
        : status === "InProgress"
          ? "ai"
          : "secondary";
  const Icon =
    status === "Completed" || status === "Confirmed"
      ? CalendarCheck
      : status === "Declined" || status === "Cancelled"
        ? Ban
        : status === "InProgress"
          ? MessagesSquare
          : status === "AwaitingPayment"
            ? CircleDashed
            : Hourglass;
  return (
    <Badge variant={variant}>
      <Icon aria-hidden />
      {CONSULTATION_STATUS_LABEL[status]}
    </Badge>
  );
}
