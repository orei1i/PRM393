// src/components/orders/order-drawer.tsx
"use client";

import * as React from "react";
import Link from "next/link";
import { Ban, ExternalLink, QrCode, Scale } from "lucide-react";
import { toast } from "sonner";

import { InitialsAvatar } from "@/components/admin/initials-avatar";
import { EscrowStatusBadge, formatDateOnly, formatVnDateTime, StepList, timeLeft, type Step } from "@/components/disputes/booking-badges";
import { Button } from "@/components/ui/button";
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogTitle } from "@/components/ui/dialog";
import { Label, Textarea } from "@/components/ui/form-controls";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { describeError } from "@/lib/api_error";
import { useOrderAction } from "@/lib/hooks/use-commerce";
import { cn } from "@/lib/utils";
import { BOOKING_STATUS_LABEL, BOOKING_TYPE_LABEL, PAYMENT_WINDOW_HOURS } from "@/types/bookings";
import type { AdminOrder } from "@/types/commerce";
import { MIN_AUDIT_NOTE_LENGTH } from "@/types/moderation";

import { formatDateTime, formatVnd, OrderStatusBadge, OrderTypeBadge, PaymentStatusBadge } from "./order-badges";
import { latestPayment } from "./order-table";

export function OrderDrawer({
  order,
  onOpenChange,
  onOrderChange,
}: {
  order: AdminOrder | null;
  onOpenChange: (open: boolean) => void;
  onOrderChange: (order: AdminOrder) => void;
}) {
  return (
    <Sheet open={order !== null} onOpenChange={onOpenChange}>
      <SheetContent className="gap-0 overflow-y-auto sm:max-w-lg">
        {order && <Detail key={order.id} order={order} onOrderChange={onOrderChange} />}
      </SheetContent>
    </Sheet>
  );
}

/* --------------------------------------------------------------- timeline */

/** Tạo hợp đồng → Thanh toán → Giữ tiền → Giao kế hoạch → Giải ngân / Hoàn tiền */
function buildTimeline(order: AdminOrder): Step[] {
  const payment = latestPayment(order);
  const paid = order.payments.find((p) => p.paidAt !== null) ?? null;
  const escrow = order.escrow;
  const b = order.booking;
  const steps: Step[] = [
    {
      label: "Tạo hợp đồng",
      state: "done",
      detail: `${order.buyer.fullName} đồng ý ${formatVnd(order.amount)} · ${b.planDays} ngày · ${BOOKING_TYPE_LABEL[b.bookingType].toLowerCase()}`,
      at: order.createdAt,
    },
  ];

  // Thanh toán
  if (paid) {
    steps.push({ label: "Thanh toán", state: "done", detail: `PaymentOS · ${paid.transactionRef}`, at: paid.paidAt });
  } else if (order.status === "Pending") {
    const detail =
      payment?.status === "Pending"
        ? `Đang chờ quét mã QR${payment.expiresAt ? ` · mã hết hạn lúc ${formatDateTime(payment.expiresAt)}` : ""}`
        : payment?.status === "Failed"
          ? "Lần thanh toán gần nhất thất bại — thành viên có thể thử lại"
          : `Mã QR đã hết hạn — thành viên có thể tạo mã mới trong ${PAYMENT_WINDOW_HOURS} giờ sau khi đồng ý giá`;
    steps.push({ label: "Thanh toán", state: "current", detail });
  } else {
    steps.push({
      label: "Thanh toán",
      state: "failed",
      detail: order.resolution?.action === "cancel" ? "Chưa thanh toán — Ban quản trị đã huỷ đơn" : `Quá hạn thanh toán ${PAYMENT_WINDOW_HOURS} giờ`,
    });
  }

  // Giữ tiền
  if (escrow) {
    steps.push({
      label: "Giữ tiền",
      state: escrow.status === "Held" ? "current" : escrow.status === "Frozen" ? "frozen" : "done",
      detail:
        escrow.status === "Frozen"
          ? "Tạm giữ do khiếu nại — chờ Ban quản trị quyết định"
          : `VeganLife giữ đến ${formatVnDateTime(escrow.releaseAt)} (3 ngày sau khi kết thúc kế hoạch)`,
      at: escrow.heldAt,
    });
  } else {
    steps.push({ label: "Giữ tiền", state: order.status === "Pending" ? "upcoming" : "skipped", detail: "Bắt đầu giữ khi thanh toán thành công" });
  }

  // Giao kế hoạch
  if (escrow) {
    const all = b.deliveredDays >= b.planDays;
    steps.push({
      label: "Giao kế hoạch",
      state: all ? "done" : "current",
      detail: `Đã giao ${b.deliveredDays}/${b.planDays} ngày · ${formatDateOnly(b.startDate)} – ${formatDateOnly(b.endDate)}`,
    });
  } else {
    steps.push({ label: "Giao kế hoạch", state: order.status === "Pending" ? "upcoming" : "skipped", detail: `${b.planDays} ngày từ ${formatDateOnly(b.startDate)}` });
  }

  // Giải ngân / Hoàn tiền
  const r = order.resolution;
  if (escrow?.status === "Released") {
    steps.push({
      label: "Giải ngân",
      state: "done",
      detail: r?.action === "release" ? `Theo quyết định khiếu nại của ${r.by}` : `Tự động khi hết hạn khiếu nại · chuyên gia nhận ${formatVnd(escrow.releasedAmount - escrow.feeAmount)}`,
      at: escrow.releasedAt,
    });
  } else if (escrow?.status === "Refunded" || escrow?.status === "PartiallyRefunded") {
    steps.push({
      label: escrow.status === "Refunded" ? "Hoàn tiền" : "Hoàn một phần & giải ngân",
      state: "closed",
      detail: `Hoàn ${formatVnd(escrow.refundedAmount)} về phương thức thanh toán ban đầu${
        escrow.releasedAmount > 0 ? ` · chuyên gia nhận ${formatVnd(escrow.releasedAmount - escrow.feeAmount)}` : ""
      }${r ? ` · ${r.by}: “${r.note}”` : ""}`,
      at: r?.at ?? escrow.releasedAt,
    });
  } else if (escrow) {
    steps.push({
      label: "Giải ngân / Hoàn tiền",
      state: "upcoming",
      detail: escrow.status === "Frozen" ? "Theo quyết định khiếu nại" : `Tự động chuyển cho chuyên gia ${timeLeft(escrow.releaseAt)} nếu không có khiếu nại`,
    });
  } else if (order.status === "Cancelled") {
    steps.push({ label: "Huỷ đơn", state: "closed", detail: r ? `${r.by}: “${r.note}”` : "Thành viên không thanh toán kịp", at: r?.at });
  } else {
    steps.push({ label: "Giải ngân / Hoàn tiền", state: "upcoming", detail: "Sau khi kế hoạch kết thúc và hết hạn khiếu nại" });
  }
  return steps;
}

/* ----------------------------------------------------------------- detail */

function Detail({ order, onOrderChange }: { order: AdminOrder; onOrderChange: (order: AdminOrder) => void }) {
  const act = useOrderAction();
  const [dialogOpen, setDialogOpen] = React.useState(false);
  const [note, setNote] = React.useState("");
  const noteId = React.useId();
  const noteOk = note.trim().length >= MIN_AUDIT_NOTE_LENGTH;
  const escrow = order.escrow;

  function submit() {
    if (!noteOk) return;
    act.mutate(
      { orderId: order.id, action: "cancel", note: note.trim() },
      {
        onSuccess: (updated) => {
          toast.success("Đã huỷ đơn hàng", { description: "Mã QR đang mở hết hiệu lực, yêu cầu đặt chuyên gia bị huỷ." });
          setDialogOpen(false);
          setNote("");
          onOrderChange(updated);
        },
        onError: (e) => toast.error("Chưa huỷ được đơn", { description: describeError(e) }),
      },
    );
  }

  return (
    <>
      <SheetHeader className="border-b">
        <div className="flex flex-wrap gap-1.5">
          <OrderStatusBadge status={order.status} />
          <OrderTypeBadge />
        </div>
        <SheetTitle className="mt-2 leading-snug">
          Thực đơn {order.booking.planDays} ngày · {order.booking.chefName}
        </SheetTitle>
        <SheetDescription>
          Mã đơn <span className="font-mono">{order.id}</span> · đặt chuyên gia <span className="font-mono">{order.bookingId}</span> · tạo lúc{" "}
          {formatDateTime(order.createdAt)}
        </SheetDescription>
      </SheetHeader>

      <div className="flex flex-col gap-6 p-5">
        <dl className="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
          <div className="col-span-2 flex min-w-0 items-center gap-3">
            <InitialsAvatar name={order.buyer.fullName} />
            <div className="min-w-0">
              <dt className="text-xs text-muted-foreground">Thành viên</dt>
              <dd className="truncate font-semibold">{order.buyer.fullName}</dd>
              {order.buyer.email && <dd className="truncate text-xs text-muted-foreground">{order.buyer.email}</dd>}
            </div>
          </div>
          <Info label="Chuyên gia" value={order.booking.chefName} />
          <Info label="Số tiền" value={formatVnd(order.amount)} mono />
          <Info label="Hình thức" value={BOOKING_TYPE_LABEL[order.booking.bookingType]} />
          <Info label="Trạng thái đặt" value={BOOKING_STATUS_LABEL[order.booking.status]} />
          {order.refundedAmount > 0 && <Info label="Đã hoàn thành viên" value={formatVnd(order.refundedAmount)} mono />}
        </dl>

        <section aria-labelledby={`${noteId}-timeline`} className="flex flex-col gap-3">
          <h3 id={`${noteId}-timeline`} className="text-sm font-bold">
            Tiến trình
          </h3>
          <StepList steps={buildTimeline(order)} />
        </section>

        <section aria-labelledby={`${noteId}-escrow`} className="flex flex-col gap-2">
          <h3 id={`${noteId}-escrow`} className="text-sm font-bold">
            Giữ tiền & khiếu nại
          </h3>
          {escrow ? (
            <div className="flex flex-col gap-2 rounded-lg border p-3 text-sm">
              <EscrowStatusBadge status={escrow.status} />
              <dl className="grid grid-cols-2 gap-x-4 gap-y-2">
                <Info label="Bắt đầu giữ" value={formatVnDateTime(escrow.heldAt)} />
                <Info label="Hạn giữ" value={formatVnDateTime(escrow.releaseAt)} />
                <Info label="Chuyển chuyên gia" value={formatVnd(escrow.releasedAmount - escrow.feeAmount)} mono />
                <Info label="Phí nền tảng" value={formatVnd(escrow.feeAmount)} mono />
              </dl>
              <Button asChild size="sm" variant={order.booking.complaintId ? "warn" : "outline"} className="w-fit">
                <Link href={`/disputes?booking=${encodeURIComponent(order.bookingId)}`}>
                  <Scale aria-hidden />
                  {order.booking.complaintId ? "Xem khiếu nại" : "Xem ở Khiếu nại & giữ tiền"}
                </Link>
              </Button>
            </div>
          ) : (
            <p className="rounded-lg bg-muted px-3 py-2 text-sm text-muted-foreground">
              {order.status === "Pending" ? "Tiền được giữ ngay khi thanh toán thành công." : "Đơn không phát sinh khoản giữ tiền."}
            </p>
          )}
        </section>

        <section aria-labelledby={`${noteId}-payments`} className="flex flex-col gap-2">
          <h3 id={`${noteId}-payments`} className="text-sm font-bold">
            Thanh toán ({order.payments.length})
          </h3>
          {order.payments.length === 0 ? (
            <p className="rounded-lg bg-muted px-3 py-2 text-sm text-muted-foreground">Chưa tạo mã thanh toán.</p>
          ) : (
            <ul className="flex flex-col gap-2">
              {[...order.payments].reverse().map((p) => (
                <li key={p.id} className="flex flex-col gap-1.5 rounded-lg border p-3 text-sm">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <span className="font-semibold">{p.provider}</span>
                    <PaymentStatusBadge status={p.status} />
                  </div>
                  <p className="font-mono text-xs break-all">{p.transactionRef}</p>
                  <p className="text-xs text-muted-foreground">
                    {formatVnd(p.amount)}
                    {p.createdAt && ` · tạo ${formatDateTime(p.createdAt)}`}
                    {p.paidAt
                      ? ` · thanh toán ${formatDateTime(p.paidAt)}`
                      : p.expiresAt && (p.status === "Pending" || p.status === "Expired")
                        ? ` · ${p.status === "Pending" ? "hết hạn lúc" : "hết hạn"} ${formatDateTime(p.expiresAt)}`
                        : ""}
                  </p>
                  {p.qrCodeUrl && (
                    <Button asChild size="sm" variant="outline" className="w-fit">
                      <a href={p.qrCodeUrl} target="_blank" rel="noopener noreferrer">
                        <QrCode aria-hidden />
                        Mở mã QR
                        <ExternalLink aria-hidden />
                      </a>
                    </Button>
                  )}
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="flex flex-col gap-2 rounded-lg border p-3">
          <h3 className="text-sm font-bold">Xử lý đơn</h3>
          {order.status === "Pending" ? (
            <>
              <p className="text-xs text-muted-foreground">Đơn chưa thanh toán. Huỷ để đóng mã QR; yêu cầu đặt chuyên gia cũng bị huỷ.</p>
              <Button size="sm" variant="destructive" className="w-fit" disabled={act.isPending} onClick={() => setDialogOpen(true)}>
                <Ban aria-hidden />
                Huỷ đơn
              </Button>
            </>
          ) : (
            <p className="text-sm text-muted-foreground">
              {order.status === "Cancelled"
                ? "Đơn đã huỷ — không còn thao tác nào."
                : "Hoàn tiền chỉ thực hiện qua quyết định khiếu nại ở “Khiếu nại & giữ tiền”."}
            </p>
          )}
        </section>
      </div>

      <Dialog open={dialogOpen} onOpenChange={(open) => !act.isPending && setDialogOpen(open)}>
        <DialogContent>
          <DialogTitle>Huỷ đơn hàng?</DialogTitle>
          <DialogDescription>
            {order.id} · {order.buyer.fullName} → {order.booking.chefName} · {formatVnd(order.amount)}
          </DialogDescription>
          <ul className="list-disc space-y-1 pl-5 text-sm">
            <li>Đơn chuyển sang “Đã huỷ”</li>
            <li>Mã QR đang mở hết hiệu lực</li>
            <li>Yêu cầu đặt chuyên gia bị huỷ; thành viên có thể gửi yêu cầu mới</li>
          </ul>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor={noteId}>
              Ghi chú <span className="text-destructive">(bắt buộc)</span>
            </Label>
            <Textarea
              id={noteId}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="VD: Thành viên báo đặt nhầm chuyên gia và yêu cầu huỷ qua hotline."
              aria-describedby={`${noteId}-hint`}
              aria-invalid={note.length > 0 && !noteOk ? true : undefined}
              disabled={act.isPending}
            />
            <p id={`${noteId}-hint`} className="flex justify-between gap-3 text-xs text-muted-foreground">
              <span>Lưu vào nhật ký quản trị · tối thiểu {MIN_AUDIT_NOTE_LENGTH} ký tự</span>
              <span className="font-mono tabular">{note.trim().length}</span>
            </p>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" disabled={act.isPending}>
                Quay lại
              </Button>
            </DialogClose>
            <Button variant="destructive" disabled={!noteOk || act.isPending} onClick={submit}>
              {act.isPending ? "Đang huỷ…" : "Huỷ đơn"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

function Info({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="min-w-0">
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className={cn("break-words font-semibold", mono && "font-mono")}>{value}</dd>
    </div>
  );
}
