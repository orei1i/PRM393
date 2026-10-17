// src/components/disputes/booking-badges.tsx
// Badges, VN-time formatters and the step list shared by /disputes and the /orders drawer.
// Booking dates follow Asia/Ho_Chi_Minh (the escrow rule is "end date 23:59 VN + 3 days").
import {
  Ban,
  CircleCheck,
  CircleDashed,
  CircleX,
  Gavel,
  Hourglass,
  Lock,
  Minus,
  RotateCcw,
  Scale,
  Snowflake,
  TriangleAlert,
  Undo2,
  Wallet,
} from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
import {
  BOOKING_STATUS_LABEL,
  BOOKING_TYPE_LABEL,
  COMPLAINT_DECISION_LABEL,
  COMPLAINT_REASON_SHORT,
  COMPLAINT_STATUS_LABEL,
  ESCROW_STATUS_LABEL,
  type BookingStatus,
  type BookingType,
  type ComplaintDecision,
  type ComplaintReason,
  type ComplaintStatus,
  type DateOnly,
  type EscrowStatus,
} from "@/types/bookings";

const TZ = "Asia/Ho_Chi_Minh";
const dateTimeVn = new Intl.DateTimeFormat("vi-VN", { timeZone: TZ, hour: "2-digit", minute: "2-digit", day: "2-digit", month: "2-digit", year: "numeric" });
const dateVn = new Intl.DateTimeFormat("vi-VN", { timeZone: TZ, day: "2-digit", month: "2-digit", year: "numeric" });
const weekdayVn = new Intl.DateTimeFormat("vi-VN", { timeZone: TZ, weekday: "long" });

/** ISO → "14:05 17/10/2026" (VN time). */
export const formatVnDateTime = (iso: string) => dateTimeVn.format(new Date(iso));
/** ISO → "17/10/2026" (VN date). */
export const formatVnDate = (iso: string) => dateVn.format(new Date(iso));
/** "2026-10-20" → "20/10/2026". */
export const formatDateOnly = (d: DateOnly) => (d ? `${d.slice(8, 10)}/${d.slice(5, 7)}/${d.slice(0, 4)}` : "—");
/** "2026-10-20" → "Thứ Ba 20/10". */
export function formatPlanDay(d: DateOnly) {
  if (!d) return "—";
  const weekday = weekdayVn.format(new Date(`${d}T12:00:00+07:00`));
  return `${weekday.charAt(0).toUpperCase()}${weekday.slice(1)} ${d.slice(8, 10)}/${d.slice(5, 7)}`;
}

/** "còn 2 ngày" / "còn 5 giờ" / "đã qua" until an instant. */
export function timeLeft(iso: string, now = Date.now()) {
  const ms = Date.parse(iso) - now;
  if (ms <= 0) return "đã đến hạn";
  const hours = Math.floor(ms / 3_600_000);
  if (hours < 1) return `còn ${Math.max(1, Math.round(ms / 60_000))} phút`;
  if (hours < 48) return `còn ${hours} giờ`;
  return `còn ${Math.floor(hours / 24)} ngày`;
}

export function BookingTypeBadge({ type }: { type: BookingType }) {
  return <Badge variant="outline">{BOOKING_TYPE_LABEL[type]}</Badge>;
}

export function BookingStatusBadge({ status }: { status: BookingStatus }) {
  const tone =
    status === "Disputed"
      ? "ochre"
      : status === "Active" || status === "Completed"
        ? "sprout"
        : status === "Resolved" || status === "Ended"
          ? "ai"
          : status === "Declined" || status === "Cancelled" || status === "Expired"
            ? "secondary"
            : "outline";
  const Icon =
    status === "Disputed"
      ? Scale
      : status === "Completed"
        ? CircleCheck
        : status === "Resolved"
          ? Gavel
          : status === "Declined" || status === "Cancelled" || status === "Expired"
            ? Ban
            : Hourglass;
  return (
    <Badge variant={tone}>
      <Icon aria-hidden />
      {BOOKING_STATUS_LABEL[status]}
    </Badge>
  );
}

export function EscrowStatusBadge({ status }: { status: EscrowStatus }) {
  switch (status) {
    case "Held":
      return (
        <Badge variant="ochre">
          <Lock aria-hidden />
          {ESCROW_STATUS_LABEL[status]}
        </Badge>
      );
    case "Frozen":
      return (
        <Badge variant="outline" className="border-destructive/40 text-destructive">
          <Snowflake aria-hidden />
          {ESCROW_STATUS_LABEL[status]}
        </Badge>
      );
    case "Released":
      return (
        <Badge variant="sprout">
          <Wallet aria-hidden />
          {ESCROW_STATUS_LABEL[status]}
        </Badge>
      );
    case "Refunded":
      return (
        <Badge variant="ai">
          <RotateCcw aria-hidden />
          {ESCROW_STATUS_LABEL[status]}
        </Badge>
      );
    case "PartiallyRefunded":
      return (
        <Badge variant="ai">
          <Undo2 aria-hidden />
          {ESCROW_STATUS_LABEL[status]}
        </Badge>
      );
  }
}

export function ComplaintStatusBadge({ status }: { status: ComplaintStatus }) {
  return status === "Open" ? (
    <Badge variant="ochre">
      <Hourglass aria-hidden />
      {COMPLAINT_STATUS_LABEL[status]}
    </Badge>
  ) : (
    <Badge variant="sprout">
      <Gavel aria-hidden />
      {COMPLAINT_STATUS_LABEL[status]}
    </Badge>
  );
}

export function ComplaintReasonBadge({ reason }: { reason: ComplaintReason }) {
  return (
    <Badge variant={reason === "health_risk" || reason === "allergen" ? "ochre" : "outline"}>
      {(reason === "health_risk" || reason === "allergen") && <TriangleAlert aria-hidden />}
      {COMPLAINT_REASON_SHORT[reason]}
    </Badge>
  );
}

export function DecisionBadge({ decision }: { decision: ComplaintDecision }) {
  const Icon = decision === "ReleaseToChef" ? Wallet : decision === "RefundMember" ? RotateCcw : Undo2;
  return (
    <Badge variant={decision === "ReleaseToChef" ? "sprout" : "ai"}>
      <Icon aria-hidden />
      {COMPLAINT_DECISION_LABEL[decision]}
    </Badge>
  );
}

/* ---------------------------------------------------------------- steps */

export type StepState = "done" | "current" | "failed" | "upcoming" | "skipped" | "closed" | "frozen";

export interface Step {
  label: string;
  state: StepState;
  detail: string;
  at?: string | null;
}

const STEP_ICON: Record<StepState, { icon: typeof CircleCheck; tone: string; sr: string }> = {
  done: { icon: CircleCheck, tone: "text-sprout-text", sr: "Đã xong" },
  current: { icon: Hourglass, tone: "text-ochre-text", sr: "Đang diễn ra" },
  failed: { icon: CircleX, tone: "text-destructive", sr: "Không thành công" },
  upcoming: { icon: CircleDashed, tone: "text-muted-foreground", sr: "Sắp tới" },
  skipped: { icon: Minus, tone: "text-muted-foreground", sr: "Không áp dụng" },
  closed: { icon: RotateCcw, tone: "text-ai-text", sr: "Đã đóng" },
  frozen: { icon: Snowflake, tone: "text-destructive", sr: "Đang tạm giữ" },
};

/** Vertical timeline; state is conveyed by icon + screen-reader text, never colour alone. */
export function StepList({ steps }: { steps: Step[] }) {
  return (
    <ol className="flex flex-col">
      {steps.map((step, i) => {
        const { icon: Icon, tone, sr } = STEP_ICON[step.state];
        return (
          <li key={`${step.label}-${i}`} className="relative flex gap-3 pb-4 last:pb-0">
            {i < steps.length - 1 && <span aria-hidden className="absolute left-[9px] top-6 bottom-0 w-px bg-border" />}
            <Icon className={cn("mt-0.5 size-5 shrink-0", tone)} aria-hidden />
            <div className="min-w-0 flex-1">
              <p className={cn("text-sm font-semibold", (step.state === "skipped" || step.state === "upcoming") && "text-muted-foreground")}>
                {step.label}
                <span className="sr-only"> — {sr}</span>
              </p>
              <p className="break-words text-sm text-muted-foreground">{step.detail}</p>
              {step.at && <p className="font-mono text-xs text-muted-foreground">{formatVnDateTime(step.at)}</p>}
            </div>
          </li>
        );
      })}
    </ol>
  );
}
