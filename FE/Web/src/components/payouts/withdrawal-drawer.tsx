// src/components/payouts/withdrawal-drawer.tsx
"use client";

import * as React from "react";
import { Ban, Landmark, ReceiptText, Send } from "lucide-react";
import { toast } from "sonner";

import { InitialsAvatar } from "@/components/admin/initials-avatar";
import { formatDateTime, formatVnd } from "@/components/orders/order-badges";
import { Button } from "@/components/ui/button";
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogTitle } from "@/components/ui/dialog";
import { Input, Label, Skeleton, Textarea } from "@/components/ui/form-controls";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { describeError } from "@/lib/api_error";
import { useChefWallets, useWalletLedger, useWithdrawalAction } from "@/lib/hooks/use-payouts";
import { maskAccountNumber } from "@/lib/payouts_api";
import { cn } from "@/lib/utils";
import { MIN_AUDIT_NOTE_LENGTH } from "@/types/moderation";
import {
  AUTO_APPROVE_LIMIT,
  LEDGER_ENTRY_TYPE_LABEL,
  TRANSFER_REF_MAX,
  TRANSFER_REF_MIN,
  type WalletTransaction,
  type WithdrawalAction,
  type WithdrawalRequest,
} from "@/types/payouts";

import { ApprovalRuleBadge, BankAccountNumber, formatSignedVnd, LedgerStatusBadge, WithdrawalStatusBadge } from "./payout-badges";

export function WithdrawalDrawer({
  withdrawal,
  onOpenChange,
  onWithdrawalChange,
}: {
  withdrawal: WithdrawalRequest | null;
  onOpenChange: (open: boolean) => void;
  onWithdrawalChange: (withdrawal: WithdrawalRequest) => void;
}) {
  return (
    <Sheet open={withdrawal !== null} onOpenChange={onOpenChange}>
      <SheetContent className="gap-0 overflow-y-auto sm:max-w-lg">
        {withdrawal && <Detail key={withdrawal.id} withdrawal={withdrawal} onWithdrawalChange={onWithdrawalChange} />}
      </SheetContent>
    </Sheet>
  );
}

/** Client-side mirror of the server rule (which also rejects anything but letters, digits and . _ / -). */
const refLooksOk = (ref: string) => new RegExp(`^\\S{${TRANSFER_REF_MIN},${TRANSFER_REF_MAX}}$`).test(ref.trim());

function Detail({ withdrawal: w, onWithdrawalChange }: { withdrawal: WithdrawalRequest; onWithdrawalChange: (w: WithdrawalRequest) => void }) {
  const act = useWithdrawalAction();
  const wallets = useChefWallets();
  const ledger = useWalletLedger(w.chefId);
  const wallet = wallets.data?.find((x) => x.chefId === w.chefId) ?? null;

  const [action, setAction] = React.useState<WithdrawalAction>("complete");
  const [dialogOpen, setDialogOpen] = React.useState(false);
  const [transactionRef, setTransactionRef] = React.useState("");
  const [reason, setReason] = React.useState("");
  const ids = React.useId();

  const refOk = refLooksOk(transactionRef);
  const reasonOk = reason.trim().length >= MIN_AUDIT_NOTE_LENGTH;
  const canSubmit = action === "complete" ? refOk : reasonOk;

  function openDialog(next: WithdrawalAction) {
    setAction(next);
    setTransactionRef("");
    setReason("");
    setDialogOpen(true);
  }

  function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!canSubmit || act.isPending) return;
    const input =
      action === "complete"
        ? { withdrawalId: w.id, action, transactionRef: transactionRef.trim() }
        : { withdrawalId: w.id, action, reason: reason.trim() };
    act.mutate(input, {
      onSuccess: (updated) => {
        toast.success(action === "complete" ? "Đã ghi nhận chuyển tiền" : "Đã từ chối yêu cầu rút tiền", {
          description: `${updated.chef.fullName} · ${formatVnd(updated.amount)}`,
        });
        setDialogOpen(false);
        onWithdrawalChange(updated);
      },
      onError: (err) =>
        toast.error(action === "complete" ? "Chưa ghi nhận được chuyển tiền" : "Chưa từ chối được yêu cầu", { description: describeError(err) }),
    });
  }

  return (
    <>
      <SheetHeader className="border-b">
        <div className="flex flex-wrap gap-1.5">
          <WithdrawalStatusBadge status={w.status} />
          <ApprovalRuleBadge requiresApproval={w.requiresApproval} />
        </div>
        <SheetTitle className="mt-2 font-mono text-2xl leading-snug tabular">{formatVnd(w.amount)}</SheetTitle>
        <SheetDescription>
          Yêu cầu <span className="font-mono">{w.id}</span> · gửi lúc {formatDateTime(w.createdAt)}
        </SheetDescription>
      </SheetHeader>

      <div className="flex flex-col gap-6 p-5">
        <div className="flex min-w-0 items-center gap-3 text-sm">
          <InitialsAvatar name={w.chef.fullName} />
          <div className="min-w-0">
            <p className="text-xs text-muted-foreground">Chuyên gia</p>
            <p className="truncate font-semibold">{w.chef.fullName}</p>
            {w.chef.email && <p className="truncate text-xs text-muted-foreground">{w.chef.email}</p>}
          </div>
        </div>

        <dl className="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
          <Info
            label="Quy tắc duyệt"
            value={w.requiresApproval ? `Trên ${formatVnd(AUTO_APPROVE_LIMIT)} — Ban quản trị duyệt` : `Tối đa ${formatVnd(AUTO_APPROVE_LIMIT)} — tự động`}
          />
          {w.status === "Processing" ? (
            <Info label="Tự động chuyển" value={w.autoApproveAt ? formatDateTime(w.autoApproveAt) : "Không — chờ duyệt"} />
          ) : (
            <Info label={w.status === "Completed" ? "Chuyển lúc" : "Từ chối lúc"} value={w.processedAt ? formatDateTime(w.processedAt) : "—"} />
          )}
          {w.status !== "Processing" && <Info label="Người xử lý" value={w.processedBy ?? "Tự động (hệ thống)"} />}
          {w.status === "Completed" && <Info label="Mã giao dịch" value={w.transactionRef ?? "—"} mono />}
          {w.status === "Rejected" && (
            <div className="col-span-2 min-w-0">
              <dt className="text-xs text-muted-foreground">Lý do từ chối (chuyên gia thấy trong ứng dụng)</dt>
              <dd className="whitespace-pre-wrap break-words font-semibold">{w.reason ?? "—"}</dd>
            </div>
          )}
        </dl>

        <section aria-labelledby={`${ids}-bank`} className="flex flex-col gap-2">
          <h3 id={`${ids}-bank`} className="flex items-center gap-2 text-sm font-bold">
            <Landmark className="size-4 text-muted-foreground" aria-hidden />
            Tài khoản nhận
          </h3>
          <dl className="grid grid-cols-2 gap-x-4 gap-y-2 rounded-lg border p-3 text-sm">
            <Info label="Ngân hàng" value={w.bankAccount.bankName || "—"} />
            <Info label="Chủ tài khoản" value={w.bankAccount.accountHolder || "—"} />
            <div className="col-span-2 min-w-0">
              <dt className="text-xs text-muted-foreground">Số tài khoản</dt>
              <dd>
                <BankAccountNumber number={w.bankAccount.accountNumber} />
              </dd>
            </div>
          </dl>
        </section>

        <section aria-labelledby={`${ids}-wallet`} className="flex flex-col gap-2">
          <h3 id={`${ids}-wallet`} className="text-sm font-bold">
            Ví hiện tại
          </h3>
          {wallets.isError && !wallets.data ? (
            <p className="rounded-lg bg-muted px-3 py-2 text-sm text-muted-foreground">Chưa tải được ví: {describeError(wallets.error)}</p>
          ) : !wallets.data ? (
            <Skeleton className="h-20" />
          ) : !wallet ? (
            <p className="rounded-lg bg-muted px-3 py-2 text-sm text-muted-foreground">Không tìm thấy ví của chuyên gia này.</p>
          ) : (
            <>
              <dl className="grid grid-cols-2 gap-x-4 gap-y-2 rounded-lg border p-3 text-sm">
                <Info label="Có thể rút" value={formatVnd(wallet.available)} mono />
                <Info label="Đang xử lý rút" value={formatVnd(wallet.processing)} mono />
                <Info label="Đang chờ (giữ)" value={formatVnd(wallet.pending)} mono />
                <Info label="Đã rút" value={formatVnd(wallet.withdrawn)} mono />
              </dl>
              {w.status === "Processing" && (
                <p className="text-xs text-muted-foreground">
                  Số tiền yêu cầu đang được giữ trong “Đang xử lý rút”. Nếu từ chối, {formatVnd(w.amount)} trở lại số dư có thể rút (
                  {formatVnd(wallet.available + w.amount)}).
                </p>
              )}
            </>
          )}
        </section>

        <section aria-labelledby={`${ids}-ledger`} className="flex flex-col gap-2">
          <h3 id={`${ids}-ledger`} className="flex items-center gap-2 text-sm font-bold">
            <ReceiptText className="size-4 text-muted-foreground" aria-hidden />
            Sổ ví gần đây
          </h3>
          {ledger.isError && !ledger.data ? (
            <div className="flex flex-wrap items-center gap-2 rounded-lg bg-muted px-3 py-2 text-sm">
              <span className="text-muted-foreground">Chưa tải được sổ ví: {describeError(ledger.error)}</span>
              <Button size="sm" variant="outline" onClick={() => ledger.refetch()}>
                Thử lại
              </Button>
            </div>
          ) : ledger.isLoading ? (
            <>
              <Skeleton className="h-12" />
              <Skeleton className="h-12" />
              <Skeleton className="h-12" />
            </>
          ) : ledger.data?.length === 0 ? (
            <p className="rounded-lg bg-muted px-3 py-2 text-sm text-muted-foreground">Chưa có giao dịch nào trong ví.</p>
          ) : (
            <ul className="flex flex-col divide-y rounded-lg border text-sm">
              {ledger.data?.map((t) => <LedgerLine key={t.id} t={t} highlight={t.id === `tx_wd_${w.id}`} />)}
            </ul>
          )}
        </section>

        <section className="flex flex-col gap-2 rounded-lg border p-3">
          <h3 className="text-sm font-bold">Xử lý yêu cầu</h3>
          {w.status === "Processing" ? (
            <>
              <p className="text-xs text-muted-foreground">
                {w.requiresApproval
                  ? "Chuyển khoản qua ngân hàng trước, rồi xác nhận kèm mã giao dịch. Từ chối khi thông tin tài khoản sai hoặc có dấu hiệu bất thường."
                  : "Yêu cầu nhỏ được chi trả tự động. Bạn vẫn có thể xác nhận thủ công hoặc từ chối nếu phát hiện bất thường."}
              </p>
              <div className="flex flex-wrap gap-2">
                <Button size="sm" disabled={act.isPending} onClick={() => openDialog("complete")}>
                  <Send aria-hidden />
                  Đánh dấu đã chuyển
                </Button>
                <Button size="sm" variant="destructive" disabled={act.isPending} onClick={() => openDialog("reject")}>
                  <Ban aria-hidden />
                  Từ chối
                </Button>
              </div>
            </>
          ) : (
            <p className="text-sm text-muted-foreground">
              Yêu cầu đã {w.status === "Completed" ? "được chuyển tiền" : "bị từ chối"} — không còn thao tác nào.
            </p>
          )}
        </section>
      </div>

      <Dialog open={dialogOpen} onOpenChange={(open) => !act.isPending && setDialogOpen(open)}>
        <DialogContent>
          <DialogTitle>{action === "complete" ? "Xác nhận đã chuyển tiền?" : "Từ chối yêu cầu rút tiền?"}</DialogTitle>
          <DialogDescription>
            {w.chef.fullName} · {formatVnd(w.amount)} → {w.bankAccount.bankName} {maskAccountNumber(w.bankAccount.accountNumber)}
          </DialogDescription>
          <form className="flex flex-col gap-4" onSubmit={submit}>
            <ul className="list-disc space-y-1 pl-5 text-sm">
              {action === "complete" ? (
                <>
                  <li>Yêu cầu chuyển sang “Đã chuyển”, số tiền cộng vào “Đã rút”</li>
                  <li>Chuyên gia thấy mã giao dịch trong ứng dụng</li>
                </>
              ) : (
                <>
                  <li>{formatVnd(w.amount)} trở lại số dư có thể rút của chuyên gia</li>
                  <li>Chuyên gia thấy lý do trong ứng dụng và có thể gửi lại</li>
                </>
              )}
            </ul>
            {action === "complete" ? (
              <>
                <p className="rounded-lg border border-ochre-border bg-ochre-soft px-3 py-2 text-xs text-ochre-text">
                  Chỉ ghi nhận — hãy chuyển khoản qua ngân hàng trước khi xác nhận.
                </p>
                <div className="flex flex-col gap-1.5">
                  <Label htmlFor={`${ids}-ref`}>
                    Mã giao dịch ngân hàng <span className="text-destructive">(bắt buộc)</span>
                  </Label>
                  <Input
                    id={`${ids}-ref`}
                    value={transactionRef}
                    onChange={(e) => setTransactionRef(e.target.value)}
                    placeholder="VD: FT26288123456"
                    autoComplete="off"
                    spellCheck={false}
                    className="font-mono"
                    aria-describedby={`${ids}-ref-hint`}
                    aria-invalid={transactionRef.length > 0 && !refOk ? true : undefined}
                    disabled={act.isPending}
                  />
                  <p id={`${ids}-ref-hint`} className="flex justify-between gap-3 text-xs text-muted-foreground">
                    <span>
                      Mã tham chiếu trên biên lai chuyển khoản · {TRANSFER_REF_MIN}–{TRANSFER_REF_MAX} ký tự, không có khoảng trắng
                    </span>
                    <span className="font-mono tabular">{transactionRef.trim().length}</span>
                  </p>
                </div>
              </>
            ) : (
              <div className="flex flex-col gap-1.5">
                <Label htmlFor={`${ids}-reason`}>
                  Lý do từ chối <span className="text-destructive">(bắt buộc)</span>
                </Label>
                <Textarea
                  id={`${ids}-reason`}
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  placeholder="VD: Tên chủ tài khoản không khớp hồ sơ chuyên gia, nhờ cập nhật tài khoản rồi gửi lại."
                  aria-describedby={`${ids}-reason-hint`}
                  aria-invalid={reason.length > 0 && !reasonOk ? true : undefined}
                  disabled={act.isPending}
                />
                <p id={`${ids}-reason-hint`} className="flex justify-between gap-3 text-xs text-muted-foreground">
                  <span>Gửi cho chuyên gia và lưu vào nhật ký quản trị · tối thiểu {MIN_AUDIT_NOTE_LENGTH} ký tự</span>
                  <span className="font-mono tabular">{reason.trim().length}</span>
                </p>
              </div>
            )}
            <DialogFooter>
              <DialogClose asChild>
                <Button type="button" variant="outline" disabled={act.isPending}>
                  Quay lại
                </Button>
              </DialogClose>
              <Button type="submit" variant={action === "complete" ? "default" : "destructive"} disabled={!canSubmit || act.isPending}>
                {act.isPending ? "Đang lưu…" : action === "complete" ? "Xác nhận đã chuyển" : "Từ chối yêu cầu"}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </>
  );
}

function LedgerLine({ t, highlight }: { t: WalletTransaction; highlight: boolean }) {
  const detail =
    t.type === "Withdrawal" ? (t.bankName ?? "Rút về ngân hàng") : [t.serviceTitle, t.buyerName].filter(Boolean).join(" · ") || "—";
  return (
    <li className={cn("flex flex-col gap-1 px-3 py-2.5", highlight && "bg-ai-soft")}>
      <div className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1">
        <span className="font-semibold">
          {LEDGER_ENTRY_TYPE_LABEL[t.type]}
          {highlight && <span className="ml-1 text-xs font-normal text-muted-foreground">(yêu cầu này)</span>}
        </span>
        <span className={cn("font-mono font-semibold tabular", t.net > 0 ? "text-sprout-text" : t.net < 0 && "text-foreground")}>
          {formatSignedVnd(t.net)}
        </span>
      </div>
      <p className="line-clamp-1 break-all text-xs text-muted-foreground">{detail}</p>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="font-mono text-xs text-muted-foreground">{formatDateTime(t.createdAt)}</span>
        <LedgerStatusBadge status={t.status} />
      </div>
      {t.type === "Income" && t.gross !== null && t.fee !== null && (
        <p className="text-xs text-muted-foreground">
          {formatVnd(t.gross)} − phí {formatVnd(t.fee)}
        </p>
      )}
    </li>
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
