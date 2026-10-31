// src/components/disputes/complaint-drawer.tsx
"use client";

import * as React from "react";
import Link from "next/link";
import { Gavel, MessageSquareText, NotebookText, Receipt, Star } from "lucide-react";

import { ErrorState } from "@/components/admin/states";
import { InitialsAvatar } from "@/components/admin/initials-avatar";
import { formatVnd } from "@/components/orders/order-badges";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/form-controls";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { useComplaint } from "@/lib/hooks/use-bookings";
import { cn, formatPercent } from "@/lib/utils";
import {
  ADHERENCE_LABEL,
  BOOKING_GOAL_LABEL,
  BOOKING_TYPE_LABEL,
  COMPLAINT_REASON_LABEL,
  decisionOutcome,
  MEAL_SLOT_LABEL,
  allergenLabel,
  OFFER_STATUS_LABEL,
  REQUESTED_OUTCOME_LABEL,
  type AdminComplaint,
  type BookingMessage,
  type PlanDay,
} from "@/types/bookings";

import {
  BookingStatusBadge,
  ComplaintReasonBadge,
  ComplaintStatusBadge,
  DecisionBadge,
  EscrowStatusBadge,
  formatDateOnly,
  formatPlanDay,
  formatVnDateTime,
  StepList,
  timeLeft,
  type Step,
} from "./booking-badges";
import { ComplaintDecisionDialog } from "./complaint-decision-dialog";
import { EvidenceList } from "./evidence-list";

export function ComplaintDrawer({
  complaintId,
  initial,
  onOpenChange,
}: {
  complaintId: string | null;
  /** The list row, shown while the detail (plan days + chat) loads. */
  initial: AdminComplaint | null;
  onOpenChange: (open: boolean) => void;
}) {
  return (
    <Sheet open={complaintId !== null} onOpenChange={onOpenChange}>
      <SheetContent className="gap-0 overflow-y-auto sm:max-w-xl">
        {complaintId && <Detail key={complaintId} complaintId={complaintId} initial={initial} />}
      </SheetContent>
    </Sheet>
  );
}

/* ---------------------------------------------------------------- escrow timeline */

function escrowSteps(c: AdminComplaint): Step[] {
  const { booking } = c;
  const contract = booking.contract;
  const escrow = booking.escrow;
  const steps: Step[] = [];
  if (!contract || !escrow) return steps;
  steps.push({ label: "Đã thanh toán · Đang giữ", state: "done", detail: `${formatVnd(escrow.amount)} qua PaymentOS, VeganLife giữ tiền`, at: escrow.heldAt });
  const endAt = Date.parse(`${contract.endDate}T23:59:00+07:00`);
  const ended = endAt <= Date.now();
  steps.push({
    label: "Kết thúc kế hoạch",
    state: ended ? "done" : "current",
    detail: `${formatDateOnly(contract.endDate)} · đã giao ${booking.deliveredDays}/${contract.planDays} ngày`,
  });
  steps.push({
    label: "Khiếu nại · Tạm giữ",
    state: c.status === "Open" ? "frozen" : "done",
    detail: `${COMPLAINT_REASON_LABEL[c.reason]} — tiền bị tạm giữ đến khi Ban quản trị quyết định`,
    at: c.createdAt,
  });
  steps.push({
    label: "Hết hạn khiếu nại",
    state: "skipped",
    detail: `Hạn gốc ${formatVnDateTime(escrow.releaseAt)} (${contract.holdDays} ngày sau khi kết thúc) — không tự giải ngân khi có khiếu nại`,
  });
  if (c.status === "Resolved" && c.decision) {
    const out = decisionOutcome(contract.price, c.decision, c.refundAmount);
    steps.push({
      label: c.decision === "ReleaseToChef" ? "Chuyển cho chuyên gia" : c.decision === "RefundMember" ? "Hoàn tiền" : "Hoàn một phần & chuyển phần còn lại",
      state: c.decision === "ReleaseToChef" ? "done" : "closed",
      detail:
        c.decision === "ReleaseToChef"
          ? `Chuyên gia nhận ${formatVnd(out.chefNet)} (phí ${formatVnd(out.fee)})`
          : c.decision === "RefundMember"
            ? `Hoàn ${formatVnd(out.refund)} về phương thức thanh toán ban đầu`
            : `Hoàn ${formatVnd(out.refund)} cho thành viên · chuyên gia nhận ${formatVnd(out.chefNet)} (phí ${formatVnd(out.fee)})`,
      at: c.decidedAt,
    });
  } else {
    steps.push({ label: "Chuyển cho chuyên gia / Hoàn tiền", state: "upcoming", detail: "Chờ quyết định của Ban quản trị" });
  }
  return steps;
}

/* ---------------------------------------------------------------- detail */

function Detail({ complaintId, initial }: { complaintId: string; initial: AdminComplaint | null }) {
  const query = useComplaint(complaintId, initial);
  const [deciding, setDeciding] = React.useState(false);
  const ids = React.useId();
  const c = query.data;

  if (!c) {
    return query.isError ? (
      <>
        <SheetTitle className="sr-only">Chưa tải được khiếu nại</SheetTitle>
        <ErrorState error={query.error} onRetry={() => query.refetch()} title="Chưa tải được khiếu nại" />
      </>
    ) : (
      <div className="flex flex-col gap-4 p-5" aria-busy="true">
        <SheetTitle className="sr-only">Đang tải khiếu nại</SheetTitle>
        <Skeleton className="h-6 w-40" />
        <Skeleton className="h-8 w-3/4" />
        <Skeleton className="h-24" />
        <Skeleton className="h-40" />
      </div>
    );
  }

  const { booking } = c;
  const contract = booking.contract;
  const escrow = booking.escrow;
  const price = contract?.price ?? escrow?.amount ?? 0;
  // List rows carry no plan days / chat: show skeletons until the detail arrives, a retry if it fails.
  const detailMissing = c.messages.length === 0 && c.planDays.length === 0;
  const detailLoading = query.isPlaceholderData || (query.isFetching && detailMissing);
  const detailFailed = query.isError && detailMissing;
  const memberEvidence = c.evidence.filter((e) => e.submittedBy === "member");
  const chefEvidence = c.evidence.filter((e) => e.submittedBy === "chef");

  return (
    <>
      <SheetHeader className="border-b">
        <div className="flex flex-wrap gap-1.5">
          <ComplaintStatusBadge status={c.status} />
          <ComplaintReasonBadge reason={c.reason} />
          {escrow && <EscrowStatusBadge status={escrow.status} />}
        </div>
        <SheetTitle className="mt-2 leading-snug">
          {booking.member.fullName} khiếu nại {booking.chef.fullName}
        </SheetTitle>
        <SheetDescription>
          Mã <span className="font-mono">{c.id}</span> · đặt chuyên gia <span className="font-mono">{booking.id}</span> · gửi lúc{" "}
          {formatVnDateTime(c.createdAt)}
        </SheetDescription>
      </SheetHeader>

      <div className="flex flex-col gap-6 p-5">
        <dl className="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
          <PersonInfo label="Thành viên" name={booking.member.fullName} email={booking.member.email} />
          <PersonInfo label="Chuyên gia" name={booking.chef.fullName} email={booking.chef.email} verified />
          <Info label="Giá hợp đồng" value={formatVnd(price)} mono />
          <Info
            label="Thành viên yêu cầu"
            value={`${REQUESTED_OUTCOME_LABEL[c.requestedOutcome]}${c.requestedOutcome === "PartialRefund" ? ` ${formatVnd(c.requestedAmount)}` : ""}`}
          />
        </dl>

        {/* Decision */}
        {c.status === "Open" ? (
          <section className="flex flex-col gap-2 rounded-lg border border-ochre-border bg-ochre-soft p-3">
            <h3 className="text-sm font-bold text-ochre-text">Chờ Ban quản trị quyết định</h3>
            <p className="text-xs text-ochre-text">
              {escrow ? `${formatVnd(escrow.amount)} đang bị tạm giữ. ` : ""}Đọc bằng chứng, phản hồi của chuyên gia và kế hoạch đã giao trước khi quyết định.
            </p>
            <Button size="sm" className="w-fit" onClick={() => setDeciding(true)}>
              <Gavel aria-hidden />
              Ra quyết định
            </Button>
          </section>
        ) : (
          c.decision && (
            <section aria-labelledby={`${ids}-decision`} className="flex flex-col gap-2 rounded-lg border p-3 text-sm">
              <h3 id={`${ids}-decision`} className="text-sm font-bold">
                Quyết định
              </h3>
              <DecisionBadge decision={c.decision} />
              <DecisionNumbers price={price} c={c} />
              {c.adminNote && <p className="whitespace-pre-wrap break-words rounded-lg bg-muted px-3 py-2">“{c.adminNote}”</p>}
              <p className="text-xs text-muted-foreground">
                {c.decidedBy ?? "Quản trị viên"}
                {c.decidedAt ? ` · ${formatVnDateTime(c.decidedAt)}` : ""}
              </p>
            </section>
          )
        )}

        {/* Complaint */}
        <section aria-labelledby={`${ids}-complaint`} className="flex flex-col gap-2">
          <h3 id={`${ids}-complaint`} className="text-sm font-bold">
            Nội dung khiếu nại
          </h3>
          <p className="text-xs font-semibold text-muted-foreground">{COMPLAINT_REASON_LABEL[c.reason]}</p>
          <p className="whitespace-pre-wrap break-words rounded-lg bg-muted px-4 py-3 text-sm leading-relaxed">{c.description}</p>
        </section>

        <section aria-labelledby={`${ids}-evidence`} className="flex flex-col gap-2">
          <h3 id={`${ids}-evidence`} className="text-sm font-bold">
            Bằng chứng của thành viên ({memberEvidence.length})
          </h3>
          <EvidenceList evidence={memberEvidence} emptyText="Thành viên chưa đính kèm bằng chứng." />
        </section>

        <section aria-labelledby={`${ids}-chef`} className="flex flex-col gap-2">
          <h3 id={`${ids}-chef`} className="text-sm font-bold">
            Phản hồi của chuyên gia
          </h3>
          {c.chefResponse ? (
            <div className="flex flex-col gap-1 rounded-lg border p-3 text-sm">
              <p className="whitespace-pre-wrap break-words leading-relaxed">{c.chefResponse}</p>
              {c.chefRespondedAt && <p className="text-xs text-muted-foreground">{formatVnDateTime(c.chefRespondedAt)}</p>}
            </div>
          ) : (
            <p className="rounded-lg bg-muted px-3 py-2 text-sm text-muted-foreground">Chuyên gia chưa phản hồi khiếu nại này.</p>
          )}
          {chefEvidence.length > 0 && <EvidenceList evidence={chefEvidence} />}
        </section>

        {/* Contract */}
        {contract && (
          <section aria-labelledby={`${ids}-contract`} className="flex flex-col gap-2">
            <h3 id={`${ids}-contract`} className="flex items-center gap-2 text-sm font-bold">
              <Receipt className="size-4 text-muted-foreground" aria-hidden />
              Hồ sơ hợp đồng
            </h3>
            <div className="flex flex-col gap-3 rounded-lg border p-3 text-sm">
              <p className="break-words leading-relaxed">{contract.scopeText}</p>
              <dl className="grid grid-cols-2 gap-x-4 gap-y-2">
                <Info label="Hình thức" value={BOOKING_TYPE_LABEL[contract.bookingType]} />
                <Info label="Số ngày" value={`${contract.planDays} ngày`} />
                <Info label="Bắt đầu – kết thúc" value={`${formatDateOnly(contract.startDate)} – ${formatDateOnly(contract.endDate)}`} />
                <Info label="Giá" value={formatVnd(contract.price)} mono />
                <Info label="Phí nền tảng" value={`${formatPercent(contract.feeRate)} · ${formatVnd(Math.round(contract.price * contract.feeRate))}`} />
                <Info label="Hạn giao" value={formatVnDateTime(contract.deliveryDueAt)} />
                {contract.bookingType === "DailyFeedback" && (
                  <Info label="Gửi mỗi ngày / phản hồi" value={`trước ${contract.dailySendCutoff} / trước ${contract.feedbackCutoff}`} />
                )}
                <Info label="Mục tiêu" value={BOOKING_GOAL_LABEL[booking.goal] ?? booking.goal} />
              </dl>
              {escrow && (
                <p className="text-xs text-muted-foreground">
                  Tiền được VeganLife giữ đến {formatVnDateTime(escrow.releaseAt)} ({contract.holdDays} ngày sau khi kết thúc kế hoạch)
                  {escrow.status === "Held" ? ` · ${timeLeft(escrow.releaseAt)}` : ""}.
                </p>
              )}
              <details className="text-xs">
                <summary className="cursor-pointer font-semibold text-muted-foreground">Nhu cầu ban đầu của thành viên</summary>
                <p className="mt-1 whitespace-pre-wrap break-words leading-relaxed">{booking.needs}</p>
                <p className="mt-1 text-muted-foreground">
                  Dị ứng: {booking.allergies.length ? booking.allergies.map(allergenLabel).join(", ") : "không"} · Bữa:{" "}
                  {booking.mealPattern.map((s) => MEAL_SLOT_LABEL[s]).join(", ")}
                  {booking.budgetPerDay ? ` · Ngân sách đi chợ ${formatVnd(booking.budgetPerDay)}/ngày` : ""}
                </p>
              </details>
            </div>
          </section>
        )}

        <section aria-labelledby={`${ids}-timeline`} className="flex flex-col gap-3">
          <h3 id={`${ids}-timeline`} className="text-sm font-bold">
            Giữ tiền
          </h3>
          <StepList steps={escrowSteps(c)} />
          <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
            <BookingStatusBadge status={booking.status} />
            {booking.paymentOrderId && (
              <Link
                href={`/orders?open=${encodeURIComponent(booking.paymentOrderId)}`}
                className="font-semibold text-primary underline-offset-4 hover:underline focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
              >
                Xem đơn thanh toán {booking.paymentOrderId}
              </Link>
            )}
          </div>
        </section>

        {/* Plan days */}
        <section aria-labelledby={`${ids}-plan`} className="flex flex-col gap-2">
          <h3 id={`${ids}-plan`} className="flex items-center gap-2 text-sm font-bold">
            <NotebookText className="size-4 text-muted-foreground" aria-hidden />
            Kế hoạch đã giao ({booking.deliveredDays}/{booking.planDays} ngày)
          </h3>
          {detailLoading ? (
            <Skeleton className="h-32" />
          ) : detailFailed ? (
            <InlineRetry onRetry={() => query.refetch()} />
          ) : (
            <PlanDays days={c.planDays} />
          )}
        </section>

        {/* Chat */}
        <section aria-labelledby={`${ids}-chat`} className="flex flex-col gap-2">
          <h3 id={`${ids}-chat`} className="flex items-center gap-2 text-sm font-bold">
            <MessageSquareText className="size-4 text-muted-foreground" aria-hidden />
            Trao đổi (chỉ xem)
          </h3>
          {detailLoading ? (
            <Skeleton className="h-40" />
          ) : detailFailed ? (
            <InlineRetry onRetry={() => query.refetch()} />
          ) : (
            <Transcript messages={c.messages} memberId={booking.member.id} />
          )}
        </section>
      </div>

      <ComplaintDecisionDialog complaint={c} open={deciding} onOpenChange={setDeciding} />
    </>
  );
}

function DecisionNumbers({ price, c }: { price: number; c: AdminComplaint }) {
  if (!c.decision) return null;
  const out = decisionOutcome(price, c.decision, c.refundAmount);
  return (
    <dl className="grid grid-cols-3 gap-x-4 gap-y-2">
      <Info label="Hoàn thành viên" value={formatVnd(out.refund)} mono />
      <Info label="Chuyên gia nhận" value={formatVnd(out.chefNet)} mono />
      <Info label="Phí nền tảng" value={formatVnd(out.fee)} mono />
    </dl>
  );
}

function PlanDays({ days }: { days: PlanDay[] }) {
  if (days.length === 0) return <p className="rounded-lg bg-muted px-3 py-2 text-sm text-muted-foreground">Chưa có ngày nào trong kế hoạch.</p>;
  return (
    <ul className="flex max-h-96 flex-col divide-y overflow-y-auto rounded-lg border text-sm" tabIndex={0} aria-label="Các ngày trong kế hoạch">
      {days.map((d) => (
        <li key={d.dayIndex} className="flex flex-col gap-1 px-3 py-2.5">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <span className="font-semibold">
              Ngày {d.dayIndex} · {formatPlanDay(d.date)}
            </span>
            <Badge variant={d.status === "Sent" ? "sprout" : "secondary"}>{d.status === "Sent" ? "Đã gửi" : d.meals.length ? "Nháp" : "Chưa soạn"}</Badge>
          </div>
          {d.meals.length > 0 && (
            <ul className="flex flex-col gap-0.5 text-xs text-muted-foreground">
              {d.meals.map((m) => (
                <li key={m.slot} className="break-words">
                  <span className="font-semibold text-foreground">{MEAL_SLOT_LABEL[m.slot]}:</span> {m.recipe.name}
                  {m.recipe.calories ? ` · ${m.recipe.calories} kcal` : ""}
                  {m.note ? <span className="italic"> — {m.note}</span> : null}
                </li>
              ))}
            </ul>
          )}
          {d.chefNote && <p className="text-xs italic text-muted-foreground">Ghi chú: {d.chefNote}</p>}
          {d.feedback && (
            <p className="flex flex-wrap items-center gap-1 text-xs">
              <span className="inline-flex items-center gap-0.5 font-semibold" aria-label={`${d.feedback.rating} trên 5 sao`}>
                {d.feedback.rating}
                <Star className="size-3 fill-current text-ochre" aria-hidden />
              </span>
              <span className="text-muted-foreground">· {ADHERENCE_LABEL[d.feedback.adherence]} · “{d.feedback.body}”</span>
            </p>
          )}
        </li>
      ))}
    </ul>
  );
}

function Transcript({ messages, memberId }: { messages: BookingMessage[]; memberId: string }) {
  if (messages.length === 0) return <p className="rounded-lg bg-muted px-3 py-2 text-sm text-muted-foreground">Chưa có tin nhắn.</p>;
  return (
    <ol className="flex max-h-[28rem] flex-col gap-2 overflow-y-auto rounded-lg border bg-muted/30 p-3 text-sm" tabIndex={0} aria-label="Lịch sử trao đổi">
      {messages.map((m) => {
        if (m.senderRole === "system") {
          return (
            <li key={m.id} className="mx-auto max-w-[90%] text-center text-xs text-muted-foreground">
              <span className="break-words">{m.body}</span>
              <span className="block font-mono text-[11px]">{formatVnDateTime(m.createdAt)}</span>
            </li>
          );
        }
        const mine = m.senderId === memberId || m.senderRole === "member";
        return (
          <li key={m.id} className={cn("flex max-w-[85%] flex-col gap-1", mine ? "self-start" : "self-end items-end")}>
            <span className="text-[11px] font-semibold text-muted-foreground">{mine ? "Thành viên" : "Chuyên gia"}</span>
            <div className={cn("rounded-xl px-3 py-2", mine ? "bg-card border" : "bg-secondary text-secondary-foreground")}>
              {m.kind === "Offer" && m.offer && (
                <p className="mb-1 text-xs font-bold">
                  Đề xuất giá · {formatVnd(m.offer.price)} · {m.offer.planDays} ngày · {BOOKING_TYPE_LABEL[m.offer.bookingType]} · bắt đầu{" "}
                  {formatDateOnly(m.offer.startDate).slice(0, 5)} · {OFFER_STATUS_LABEL[m.offer.status]}
                </p>
              )}
              <p className="whitespace-pre-wrap break-words">{m.body}</p>
            </div>
            <span className="font-mono text-[11px] text-muted-foreground">{formatVnDateTime(m.createdAt)}</span>
          </li>
        );
      })}
    </ol>
  );
}

function InlineRetry({ onRetry }: { onRetry: () => void }) {
  return (
    <div className="flex flex-wrap items-center gap-2 rounded-lg bg-muted px-3 py-2 text-sm">
      <span className="text-muted-foreground">Chưa tải được chi tiết.</span>
      <Button size="sm" variant="outline" onClick={onRetry}>
        Thử lại
      </Button>
    </div>
  );
}

function PersonInfo({ label, name, email, verified }: { label: string; name: string; email: string; verified?: boolean }) {
  return (
    <div className="col-span-2 flex min-w-0 items-center gap-3 sm:col-span-1">
      <InitialsAvatar name={name} verified={verified} />
      <div className="min-w-0">
        <dt className="text-xs text-muted-foreground">{label}</dt>
        <dd className="truncate font-semibold">{name}</dd>
        {email && <dd className="truncate text-xs text-muted-foreground">{email}</dd>}
      </div>
    </div>
  );
}

function Info({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="min-w-0">
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className={cn("break-words font-semibold", mono && "font-mono tabular")}>{value}</dd>
    </div>
  );
}
