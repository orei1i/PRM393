// src/components/disputes/resolve-hold-dialog.tsx
"use client";

import * as React from "react";
import { Gavel, Info } from "lucide-react";
import { toast } from "sonner";

import { formatVnd } from "@/components/orders/order-badges";
import { Button } from "@/components/ui/button";
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogTitle } from "@/components/ui/dialog";
import { Input, Label, Textarea } from "@/components/ui/form-controls";
import { ApiError, describeError } from "@/lib/api_error";
import { useResolveHold } from "@/lib/hooks/use-bookings";
import { cn, formatPercent } from "@/lib/utils";
import {
  COMPLAINT_DECISION_LABEL,
  COMPLAINT_DECISIONS,
  decisionErrors,
  decisionOutcome,
  MIN_DECISION_NOTE,
  MIN_PARTIAL_REFUND,
  type AdminEscrowHold,
  type ComplaintDecision,
} from "@/types/bookings";
import { PLATFORM_FEE_RATE } from "@/types/payouts";

import { completionHint } from "./booking-badges";

const ENDS: Record<ComplaintDecision, string> = {
  ReleaseToChef: "Đặt chuyên gia chuyển sang Hoàn tất.",
  RefundMember: "Đặt chuyên gia bị huỷ, lý do là ghi chú bên dưới.",
  Split: "Đặt chuyên gia chuyển sang Hoàn tất.",
};

/** "500.000" / "500000đ" → 500000; empty → undefined. */
const parseAmount = (text: string) => {
  const digits = text.replace(/\D/g, "");
  return digits ? Number(digits) : undefined;
};

/** Keyed by hold: each one starts from an empty form. */
export function ResolveHoldDialog({ hold, onOpenChange }: { hold: AdminEscrowHold | null; onOpenChange: (open: boolean) => void }) {
  return hold ? <Form key={hold.id} hold={hold} onOpenChange={onOpenChange} /> : null;
}

function Form({ hold, onOpenChange }: { hold: AdminEscrowHold; onOpenChange: (open: boolean) => void }) {
  const resolve = useResolveHold();
  const ids = React.useId();
  const [decision, setDecision] = React.useState<ComplaintDecision | null>(null);
  const [amountText, setAmountText] = React.useState("");
  const [note, setNote] = React.useState("");
  const [attempted, setAttempted] = React.useState(false);

  const b = hold.booking;
  const price = hold.amount;
  const refundAmount = decision === "Split" ? parseAmount(amountText) : undefined;
  const errors = decisionErrors({ decision, refundAmount, note }, price);
  const valid = Object.keys(errors).length === 0;
  const out = decision && (decision !== "Split" || refundAmount !== undefined) ? decisionOutcome(price, decision, refundAmount) : null;

  /** What this choice pays each side, shown on the choice itself. */
  function pays(d: ComplaintDecision) {
    if (d === "Split") {
      const x = decision === "Split" && !errors.refundAmount ? refundAmount : undefined;
      if (x === undefined) return `${b.member.fullName} nhận số tiền bạn nhập, ${b.chef.fullName} nhận phần còn lại × ${formatPercent(1 - PLATFORM_FEE_RATE)}.`;
    }
    const o = decisionOutcome(price, d, d === "Split" ? refundAmount : undefined);
    return `${b.member.fullName} nhận ${formatVnd(o.refund)} · ${b.chef.fullName} nhận ${formatVnd(o.chefNet)} · phí ${formatVnd(o.fee)}.`;
  }

  function submit(e: React.FormEvent) {
    e.preventDefault();
    setAttempted(true);
    if (!valid || !decision || resolve.isPending) return;
    resolve.mutate(
      { holdId: hold.id, decision, refundAmount, note: note.trim() },
      {
        onSuccess: () => {
          const result = decisionOutcome(price, decision, refundAmount);
          toast.success("Đã xử lý khoản giữ tiền", {
            description:
              decision === "ReleaseToChef"
                ? `Chuyển ${formatVnd(result.chefNet)} vào ví ${b.chef.fullName} (sau phí).`
                : decision === "RefundMember"
                  ? `Hoàn ${formatVnd(result.refund)} vào ví ${b.member.fullName}.`
                  : `Hoàn ${formatVnd(result.refund)} vào ví thành viên · ${formatVnd(result.chefNet)} vào ví chuyên gia.`,
          });
          onOpenChange(false);
        },
        onError: (err) => {
          if (err instanceof ApiError && err.status === 409) {
            toast.error("Khoản này không còn kẹt", { description: describeError(err) });
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
      open
      onOpenChange={(next) => {
        if (resolve.isPending) return;
        onOpenChange(next);
      }}
    >
      <DialogContent className="max-h-[calc(100dvh-2rem)] max-w-lg overflow-y-auto">
        <DialogTitle>Xử lý khoản giữ tiền kẹt</DialogTitle>
        <DialogDescription>{completionHint(b, false).text}. Không có khiếu nại đang mở.</DialogDescription>

        <dl className="grid grid-cols-2 gap-x-4 gap-y-2 rounded-lg border p-3 text-sm">
          <Fact label="Thành viên" value={b.member.fullName} />
          <Fact label="Chuyên gia" value={b.chef.fullName} />
          <Fact label="Giá hợp đồng" value={formatVnd(price)} mono />
          <Fact label="Đã giao" value={`${b.deliveredDays}/${b.planDays} ngày`} />
        </dl>

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
                  onChange={() => setDecision(d)}
                  disabled={resolve.isPending}
                  className="mt-0.5 size-4 shrink-0 accent-primary"
                />
                <span className="min-w-0">
                  <span className="block font-semibold">{COMPLAINT_DECISION_LABEL[d]}</span>
                  <span className="block text-xs text-foreground">{pays(d)}</span>
                  <span className="block text-xs text-muted-foreground">{ENDS[d]}</span>
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
                disabled={resolve.isPending}
              />
              <p id={`${ids}-amount-hint`} className={cn("text-xs", amountError ? "text-destructive" : "text-muted-foreground")}>
                {amountError ?? `${refundAmount !== undefined ? formatVnd(refundAmount) : "—"} · từ ${formatVnd(MIN_PARTIAL_REFUND)} đến dưới ${formatVnd(price)}`}
              </p>
            </div>
          )}

          {out && (
            <section aria-label="Xem trước phân chia" aria-live="polite" className="flex flex-col gap-1 rounded-lg border bg-muted/50 p-3 text-sm">
              <p>
                Ví {b.member.fullName} nhận <b className="font-mono tabular">{formatVnd(out.refund)}</b>
              </p>
              <p>
                Ví {b.chef.fullName} nhận ({formatVnd(price)} − {formatVnd(out.refund)}) × {formatPercent(1 - PLATFORM_FEE_RATE)} ={" "}
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
              placeholder="VD: Chuyên gia giao 5/7 ngày rồi ngừng, hai bên không phản hồi. Hoàn phần 2 ngày chưa giao."
              aria-invalid={noteError ? true : undefined}
              aria-describedby={`${ids}-note-hint`}
              disabled={resolve.isPending}
            />
            <p id={`${ids}-note-hint`} className={cn("flex justify-between gap-3 text-xs", noteError ? "text-destructive" : "text-muted-foreground")}>
              <span>{noteError ?? `Thành viên và chuyên gia đều thấy ghi chú này · tối thiểu ${MIN_DECISION_NOTE} ký tự`}</span>
              <span className="font-mono tabular">{note.trim().length}</span>
            </p>
          </div>

          <p className="flex gap-2 rounded-lg border border-ochre-border bg-ochre-soft px-3 py-2 text-xs text-ochre-text">
            <Info className="mt-0.5 size-3.5 shrink-0" aria-hidden />
            Sau khi lưu, chuyên gia không xác nhận được và thành viên không khiếu nại được nữa. Quyết định là cuối cùng và không sửa được.
          </p>

          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="outline" disabled={resolve.isPending}>
                Quay lại
              </Button>
            </DialogClose>
            <Button type="submit" disabled={resolve.isPending || (attempted && !valid)}>
              <Gavel aria-hidden />
              {resolve.isPending ? "Đang lưu…" : decision ? COMPLAINT_DECISION_LABEL[decision] : "Lưu quyết định"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function Fact({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="min-w-0">
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className={cn("break-words font-semibold", mono && "font-mono tabular")}>{value}</dd>
    </div>
  );
}
