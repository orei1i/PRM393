// src/components/disputes/booking-badges.tsx
// Badges, VN-time formatters and the step list shared by /disputes and the /orders drawer.
// Booking dates follow Asia/Ho_Chi_Minh; a hold's release date is 7 days after the contract completes.
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

import { formatVnd } from "@/components/orders/order-badges";
import { Badge } from "@/components/ui/badge";
import { cn, dateFormat } from "@/lib/utils";
import {
  AUTO_COMPLETE_DAYS,
  autoCompleteAt,
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
  type EscrowHold,
  type EscrowStatus,
  vnDateOf,
} from "@/types/bookings";

const TZ = "Asia/Ho_Chi_Minh";
const dateTimeVn = dateFormat({ timeZone: TZ, hour: "2-digit", minute: "2-digit", day: "2-digit", month: "2-digit", year: "numeric" });
const dateVn = dateFormat({ timeZone: TZ, day: "2-digit", month: "2-digit", year: "numeric" });
const weekdayVn = dateFormat({ timeZone: TZ, weekday: "long" });

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
  if (Number.isNaN(ms)) return "—";
  if (ms <= 0) return "đã đến hạn";
  const hours = Math.floor(ms / 3_600_000);
  if (hours < 1) return `còn ${Math.max(1, Math.round(ms / 60_000))} phút`;
  if (hours < 48) return `còn ${hours} giờ`;
  return `còn ${Math.floor(hours / 24)} ngày`;
}

/** Who has the money right now, in one line. Every page that shows a hold uses this. */
export function moneyLocation(e: Pick<EscrowHold, "status" | "releaseAt" | "releasedAmount" | "feeAmount" | "refundedAmount">) {
  switch (e.status) {
    case "Held":
      return e.releaseAt ? `VeganLife giữ đến ${formatVnDateTime(e.releaseAt)}` : "VeganLife giữ, chờ chuyên gia xác nhận hoàn thành";
    case "Frozen":
      return "VeganLife tạm giữ, chờ quyết định khiếu nại";
    case "Released":
      return `Ví chuyên gia ${formatVnd(e.releasedAmount - e.feeAmount)} · phí ${formatVnd(e.feeAmount)}`;
    case "Refunded":
      return `Ví thành viên ${formatVnd(e.refundedAmount)}`;
    case "PartiallyRefunded":
      return `Ví thành viên ${formatVnd(e.refundedAmount)} · ví chuyên gia ${formatVnd(e.releasedAmount - e.feeAmount)}`;
  }
}

/** "Xác nhận 14:05 17/10/2026" / "Hệ thống tự hoàn tất 23:59 17/10/2026". */
export const completionLabel = (completedAt: string, autoCompleted: boolean) =>
  `${autoCompleted ? "Hệ thống tự hoàn tất" : "Xác nhận"} ${formatVnDateTime(completedAt)}`;

export const AUTO_COMPLETE_RULE = `Chuyên gia không xác nhận sau ${AUTO_COMPLETE_DAYS} ngày kể từ ngày kết thúc kế hoạch`;

/** "Ban quản trị xử lý 14:05 17/10/2026": a stuck hold decided with no complaint. */
export const adminResolvedLabel = (at: string) => `Ban quản trị xử lý ${formatVnDateTime(at)}`;

/**
 * Where an uncompleted hold stands. A chef may confirm only with every day delivered and today on or
 * after the plan's end; without confirmation the system completes it at endDate 23:59 + 3 days, unless
 * days were missing at that moment. Those are the holds `attention` flags for an admin: days still missing,
 * or every day delivered but some after the moment (the chef can still confirm those).
 */
export function completionHint(b: { deliveredDays: number; planDays: number; endDate: DateOnly | null }, frozen: boolean, now = Date.now()) {
  const none = { text: "Chuyên gia chưa xác nhận", attention: false };
  if (frozen) return { text: "Chưa xác nhận · khiếu nại chặn tự hoàn tất", attention: false };
  if (!b.endDate) return none;
  const missing = b.planDays - b.deliveredDays;
  const reachedEnd = vnDateOf(now) >= b.endDate;
  const autoAt = autoCompleteAt(b.endDate);
  if (missing > 0) {
    if (Date.parse(autoAt) <= now) return { text: `Thiếu ${missing} ngày nên không tự hoàn tất · cần Ban quản trị xem xét`, attention: true };
    return { text: reachedEnd ? `Chưa xác nhận được: còn thiếu ${missing} ngày` : `Chưa xác nhận được: cần giao đủ ngày và tới ${formatDateOnly(b.endDate)}`, attention: false };
  }
  if (!reachedEnd) return { text: `Đã giao đủ · xác nhận được từ ${formatDateOnly(b.endDate)}`, attention: false };
  // Still uncompleted past the moment with every day in: the last of them came after it.
  if (Date.parse(autoAt) <= now) return { text: `Giao đủ sau ${formatVnDateTime(autoAt)} nên không tự hoàn tất · cần Ban quản trị xem xét`, attention: true };
  return { text: `Chuyên gia chưa xác nhận · hệ thống tự hoàn tất lúc ${formatVnDateTime(autoAt)}`, attention: false };
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
