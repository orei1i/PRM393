// src/components/disputes/complaint-decision-dialog.tsx
"use client";

import * as React from "react";
import { Gavel, Info } from "lucide-react";
import { toast } from "sonner";

import { formatVnd } from "@/components/orders/order-badges";
import { Button } from "@/components/ui/button";
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogTitle } from "@/components/ui/dialog";
import { Input, Label, Textarea } from "@/components/ui/form-controls";
import { ApiError, describeError } from "@/lib/api_error";
import { useComplaintDecision } from "@/lib/hooks/use-bookings";
import { cn, formatPercent } from "@/lib/utils";
import {
  COMPLAINT_DECISION_LABEL,
  COMPLAINT_DECISIONS,
  decisionErrors,
  decisionOutcome,
  MIN_DECISION_NOTE,
  MIN_PARTIAL_REFUND,
  REQUESTED_OUTCOME_LABEL,
  type AdminComplaint,
  type ComplaintDecision,
} from "@/types/bookings";
import { PLATFORM_FEE_RATE } from "@/types/payouts";

const HINT: Record<ComplaintDecision, string> = {
  ReleaseToChef: "Khiếu nại không có cơ sở. Chuyên gia nhận toàn bộ, trừ phí nền tảng.",
  RefundMember: "Hoàn toàn bộ về phương thức thanh toán ban đầu của thành viên. Chuyên gia không nhận tiền.",
  Split: "Hoàn một phần cho thành viên, phần còn lại chuyển cho chuyên gia (trừ phí).",
};

/** "500.000" / "500000đ" → 500000; empty → undefined. */
const parseAmount = (text: string) => {
  const digits = text.replace(/\D/g, "");
  return digits ? Number(digits) : undefined;
};

export function ComplaintDecisionDialog({
  complaint,
  open,
  onOpenChange,
}: {
  complaint: AdminComplaint;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const decide = useComplaintDecision();
  const ids = React.useId();
  const [decision, setDecision] = React.useState<ComplaintDecision | null>(null);
  const [amountText, setAmountText] = React.useState("");
  const [note, setNote] = React.useState("");
  const [attempted, setAttempted] = React.useState(false);

  const price = complaint.booking.contract?.price ?? complaint.booking.escrow?.amount ?? 0;
  const refundAmount = decision === "Split" ? parseAmount(amountText) : undefined;
  const errors = decisionErrors({ decision, refundAmount, note }, price);
  const valid = Object.keys(errors).length === 0;
  const out = decision && (decision !== "Split" || refundAmount !== undefined) ? decisionOutcome(price, decision, refundAmount) : null;
  const requestedPartial = complaint.requestedOutcome === "PartialRefund" && complaint.requestedAmount < price;

  function reset() {
    setDecision(null);
    setAmountText("");
    setNote("");
    setAttempted(false);
  }

  function choose(next: ComplaintDecision) {
    setDecision(next);
    if (next === "Split" && !amountText && requestedPartial) setAmountText(String(complaint.requestedAmount));
  }

  function submit(e: React.FormEvent) {
    e.preventDefault();
    setAttempted(true);
    if (!valid || !decision || decide.isPending) return;
    decide.mutate(
      { complaintId: complaint.id, decision, refundAmount, note: note.trim() },
      {
        onSuccess: (updated) => {
          const result = decisionOutcome(price, decision, refundAmount);
          toast.success("Đã lưu quyết định", {
            description:
              decision === "ReleaseToChef"
                ? `Chuyển ${formatVnd(result.chefNet)} vào ví ${updated.booking.chef.fullName} (sau phí).`
                : decision === "RefundMember"
                  ? `Hoàn ${formatVnd(result.refund)} cho ${updated.booking.member.fullName} qua PaymentOS.`
                  : `Hoàn ${formatVnd(result.refund)} cho thành viên · chuyên gia nhận ${formatVnd(result.chefNet)}.`,
          });
          reset();
          onOpenChange(false);
        },
        onError: (err) => {
          if (err instanceof ApiError && err.status === 409) {
            toast.error("Khiếu nại đã được xử lý", { description: describeError(err) });
            reset();
            onOpenChange(false);
            return;
          }
          toast.error("Chưa lưu được quyết định", { description: describeError(err) });
        },
      },
    );
  }

  const showError = (field: keyof typeof errors) => (attempted ? errors[field] : undefined);
  const amountError = decision === "Split" && (attempted || amountText !== "") ? errors.refundAmount : undefined;
  const noteError = attempted || note.trim().length >= MIN_DECISION_NOTE ? errors.note : undefined;

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        if (decide.isPending) return;
        if (!next) reset();
        onOpenChange(next);
      }}
    >
      <DialogContent className="max-h-[calc(100dvh-2rem)] max-w-lg overflow-y-auto">
        <DialogTitle>Quyết định khiếu nại</DialogTitle>
        <DialogDescription>
          {complaint.booking.member.fullName} → {complaint.booking.chef.fullName} · giá hợp đồng {formatVnd(price)} · thành viên yêu cầu{" "}
          {REQUESTED_OUTCOME_LABEL[complaint.requestedOutcome].toLowerCase()}
          {complaint.requestedOutcome === "PartialRefund" ? ` ${formatVnd(complaint.requestedAmount)}` : ""}
        </DialogDescription>

        <form className="flex flex-col gap-4" onSubmit={submit} noValidate>
          <fieldset className="flex flex-col gap-2" aria-describedby={showError("decision") ? `${ids}-decision-error` : undefined}>
            <legend className="mb-2 text-sm font-semibold">Cách xử lý</legend>
            {COMPLAINT_DECISIONS.map((d) => (
              <label
                key={d}
                className={cn(
                  "flex cursor-pointer gap-3 rounded-lg border p-3 text-sm transition-colors has-[:focus-visible]:ring-[3px] has-[:focus-visible]:ring-ring/40",
                  decision === d ? "border-primary bg-secondary" : "hover:bg-accent",
                )}
              >
                <input
                  type="radio"
                  name={`${ids}-decision`}
                  value={d}
                  checked={decision === d}
                  onChange={() => choose(d)}
                  disabled={decide.isPending}
                  className="mt-0.5 size-4 shrink-0 accent-primary"
                />
                <span className="min-w-0">
                  <span className="block font-semibold">{COMPLAINT_DECISION_LABEL[d]}</span>
                  <span className="block text-xs text-muted-foreground">{HINT[d]}</span>
                </span>
              </label>
            ))}
            {showError("decision") && (
              <p id={`${ids}-decision-error`} className="text-xs text-destructive">
                {errors.decision}
              </p>
            )}
          </fieldset>

          {decision === "Split" && (
            <div className="flex flex-col gap-1.5">
              <Label htmlFor={`${ids}-amount`}>
                Số tiền hoàn cho thành viên <span className="text-destructive">(bắt buộc)</span>
              </Label>
              <Input
                id={`${ids}-amount`}
                inputMode="numeric"
                autoComplete="off"
                value={amountText}
                onChange={(e) => setAmountText(e.target.value.replace(/\D/g, ""))}
                placeholder="VD: 300000"
                className="font-mono"
                aria-invalid={amountError ? true : undefined}
                aria-describedby={`${ids}-amount-hint`}
                disabled={decide.isPending}
              />
              <p id={`${ids}-amount-hint`} className={cn("text-xs", amountError ? "text-destructive" : "text-muted-foreground")}>
                {amountError ??
                  `${refundAmount !== undefined ? formatVnd(refundAmount) : "—"} · từ ${formatVnd(MIN_PARTIAL_REFUND)} đến dưới ${formatVnd(price)}`}
              </p>
              {requestedPartial && refundAmount !== complaint.requestedAmount && (
                <Button
                  type="button"
                  size="sm"
                  variant="outline"
                  className="w-fit"
                  onClick={() => setAmountText(String(complaint.requestedAmount))}
                  disabled={decide.isPending}
                >
                  Dùng số tiền thành viên yêu cầu ({formatVnd(complaint.requestedAmount)})
                </Button>
              )}
            </div>
          )}

          {out && (
            <section aria-label="Xem trước phân chia" aria-live="polite" className="flex flex-col gap-1 rounded-lg border bg-muted/50 p-3 text-sm">
              <p>
                Thành viên nhận lại <b className="font-mono tabular">{formatVnd(out.refund)}</b>
              </p>
              <p>
                Chuyên gia nhận ({formatVnd(price)} − {formatVnd(out.refund)}) × {formatPercent(1 - PLATFORM_FEE_RATE)} ={" "}
                <b className="font-mono tabular">{formatVnd(out.chefNet)}</b>
              </p>
              <p>
                Phí nền tảng <b className="font-mono tabular">{formatVnd(out.fee)}</b>
              </p>
            </section>
          )}

          <div className="flex flex-col gap-1.5">
            <Label htmlFor={`${ids}-note`}>
              Ghi chú quyết định <span className="text-destructive">(bắt buộc)</span>
            </Label>
            <Textarea
              id={`${ids}-note`}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="VD: Kế hoạch ngày 4 và 6 có bưởi dù thành viên đã khai đang dùng thuốc huyết áp. Hoàn phần 2 ngày bị ảnh hưởng."
              aria-invalid={noteError ? true : undefined}
              aria-describedby={`${ids}-note-hint`}
              disabled={decide.isPending}
            />
            <p id={`${ids}-note-hint`} className={cn("flex justify-between gap-3 text-xs", noteError ? "text-destructive" : "text-muted-foreground")}>
              <span>{noteError ?? `Thành viên và chuyên gia đều thấy ghi chú này · tối thiểu ${MIN_DECISION_NOTE} ký tự`}</span>
              <span className="font-mono tabular">{note.trim().length}</span>
            </p>
          </div>

          <p className="flex gap-2 rounded-lg border border-ochre-border bg-ochre-soft px-3 py-2 text-xs text-ochre-text">
            <Info className="mt-0.5 size-3.5 shrink-0" aria-hidden />
            Hoàn tiền trả về phương thức thanh toán ban đầu qua PaymentOS. Quyết định là cuối cùng và không sửa được.
          </p>

          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="outline" disabled={decide.isPending}>
                Quay lại
              </Button>
            </DialogClose>
            <Button type="submit" disabled={decide.isPending || (attempted && !valid)}>
              <Gavel aria-hidden />
              {decide.isPending ? "Đang lưu…" : decision ? COMPLAINT_DECISION_LABEL[decision] : "Lưu quyết định"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
