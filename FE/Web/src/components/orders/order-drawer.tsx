// src/components/orders/order-drawer.tsx
"use client";

import * as React from "react";
import { Ban, CircleCheck, CircleDashed, CircleX, ExternalLink, Hourglass, Minus, QrCode, RotateCcw } from "lucide-react";
import { toast } from "sonner";

import { InitialsAvatar } from "@/components/admin/initials-avatar";
import { Button } from "@/components/ui/button";
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogTitle } from "@/components/ui/dialog";
import { Label, Textarea } from "@/components/ui/form-controls";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { describeError } from "@/lib/api_error";
import { useOrderAction } from "@/lib/hooks/use-commerce";
import { cn } from "@/lib/utils";
import { SERVICE_TYPE_LABEL, type AdminOrder, type OrderAction } from "@/types/commerce";
import { MIN_AUDIT_NOTE_LENGTH } from "@/types/moderation";

import {
  ConsultationStatusBadge,
  dateVi,
  formatDateTime,
  formatVnd,
  GrantStatusBadge,
  OrderStatusBadge,
  PaymentStatusBadge,
  ServiceTypeBadge,
} from "./order-badges";
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

type StepState = "done" | "current" | "failed" | "upcoming" | "skipped" | "closed";

interface Step {
  label: string;
  state: StepState;
  detail: string;
  at?: string | null;
}

function buildTimeline(order: AdminOrder): Step[] {
  const payment = latestPayment(order);
  const paid = order.payments.find((p) => p.paidAt !== null) ?? null;
  const steps: Step[] = [{ label: "Tạo đơn", state: "done", detail: `${order.buyer.fullName} đặt ${formatVnd(order.amount)}`, at: order.createdAt }];

  // Thanh toán
  if (paid && (order.status === "Paid" || order.status === "Refunded")) {
    steps.push({ label: "Thanh toán", state: "done", detail: `PaymentOS · ${paid.transactionRef}`, at: paid.paidAt });
  } else if (order.status === "Pending") {
    const detail =
      payment?.status === "Pending"
        ? `Đang chờ quét mã QR${payment.expiresAt ? ` · hết hạn lúc ${formatDateTime(payment.expiresAt)}` : ""}`
        : payment?.status === "Failed"
          ? "Lần thanh toán gần nhất thất bại — người mua có thể thử lại"
          : "Mã QR đã hết hạn — người mua có thể tạo mã mới";
    steps.push({ label: "Thanh toán", state: "current", detail });
  } else {
    steps.push({ label: "Thanh toán", state: "failed", detail: "Chưa thanh toán — đơn đã huỷ" });
  }

  // Cấp quyền
  const grant = order.accessGrant;
  if (grant) {
    const until = grant.expiresAt ? dateVi.format(new Date(grant.expiresAt)) : "không giới hạn";
    steps.push(
      grant.status === "Revoked"
        ? { label: "Cấp quyền", state: "failed", detail: "Đã thu hồi khi hoàn tiền", at: grant.grantedAt }
        : grant.status === "Expired"
          ? { label: "Cấp quyền", state: "done", detail: `Đã hết hạn (${until})`, at: grant.grantedAt }
          : { label: "Cấp quyền", state: "done", detail: `Hiệu lực đến ${until}`, at: grant.grantedAt },
    );
  } else {
    steps.push(
      order.status === "Pending"
        ? { label: "Cấp quyền", state: "upcoming", detail: "Tự động cấp khi thanh toán thành công" }
        : { label: "Cấp quyền", state: "skipped", detail: "Không cấp quyền" },
    );
  }

  // Tư vấn
  const c = order.consultation;
  if (order.service.type !== "Consult" || !c) {
    steps.push({ label: "Tư vấn", state: "skipped", detail: `Không áp dụng cho ${SERVICE_TYPE_LABEL[order.service.type].toLowerCase()}` });
  } else {
    const when = `Lịch hẹn ${formatDateTime(c.startAt)}`;
    const state: StepState =
      c.status === "Completed"
        ? "done"
        : c.status === "InProgress"
          ? "current"
          : c.status === "Declined" || c.status === "Cancelled"
            ? "failed"
            : "upcoming";
    const detail =
      c.status === "Completed"
        ? `Đã hoàn thành · ${when}`
        : c.status === "InProgress"
          ? `Đang tư vấn · ${when}`
          : c.status === "Declined"
            ? `Chuyên gia từ chối · ${when}`
            : c.status === "Cancelled"
              ? `Đã huỷ · ${when}`
              : c.status === "Confirmed"
                ? `Chuyên gia đã xác nhận · ${when}`
                : c.status === "Pending"
                  ? `Chờ chuyên gia xác nhận · ${when}`
                  : `Giữ chỗ chờ thanh toán · ${when}`;
    steps.push({ label: "Tư vấn", state, detail });
  }

  // Kết thúc
  if (order.status === "Refunded") {
    steps.push({
      label: "Hoàn tiền",
      state: "closed",
      detail: order.resolution
        ? `${order.resolution.by}: “${order.resolution.note}”`
        : c?.status === "Declined"
          ? "Tự động khi chuyên gia từ chối lịch hẹn"
          : "Hoàn tiền theo yêu cầu huỷ của người mua",
      at: order.resolution?.at,
    });
  } else if (order.status === "Cancelled") {
    steps.push({
      label: "Huỷ đơn",
      state: "closed",
      detail: order.resolution ? `${order.resolution.by}: “${order.resolution.note}”` : "Người mua huỷ hoặc mã QR hết hạn",
      at: order.resolution?.at,
    });
  }
  return steps;
}

const STEP_ICON: Record<StepState, { icon: typeof CircleCheck; tone: string; sr: string }> = {
  done: { icon: CircleCheck, tone: "text-sprout-text", sr: "Đã xong" },
  current: { icon: Hourglass, tone: "text-ochre-text", sr: "Đang chờ" },
  failed: { icon: CircleX, tone: "text-destructive", sr: "Không thành công" },
  upcoming: { icon: CircleDashed, tone: "text-muted-foreground", sr: "Sắp tới" },
  skipped: { icon: Minus, tone: "text-muted-foreground", sr: "Không áp dụng" },
  closed: { icon: RotateCcw, tone: "text-ai-text", sr: "Đã đóng" },
};

function Timeline({ order }: { order: AdminOrder }) {
  const steps = buildTimeline(order);
  return (
    <ol className="flex flex-col">
      {steps.map((step, i) => {
        const { icon: Icon, tone, sr } = STEP_ICON[step.state];
        const Closed = step.label === "Huỷ đơn" ? Ban : Icon;
        return (
          <li key={step.label} className="relative flex gap-3 pb-4 last:pb-0">
            {i < steps.length - 1 && <span aria-hidden className="absolute left-[9px] top-6 bottom-0 w-px bg-border" />}
            <Closed className={cn("mt-0.5 size-5 shrink-0", tone)} aria-hidden />
            <div className="min-w-0 flex-1">
              <p className={cn("text-sm font-semibold", step.state === "skipped" && "text-muted-foreground")}>
                {step.label}
                <span className="sr-only"> — {sr}</span>
              </p>
              <p className="break-words text-sm text-muted-foreground">{step.detail}</p>
              {step.at && <p className="font-mono text-xs text-muted-foreground">{formatDateTime(step.at)}</p>}
            </div>
          </li>
        );
      })}
    </ol>
  );
}

/* ----------------------------------------------------------------- detail */

const ACTION_COPY: Record<OrderAction, { title: string; button: string; busy: string; toast: string; effects: string[]; placeholder: string }> = {
  refund: {
    title: "Hoàn tiền đơn hàng?",
    button: "Hoàn tiền",
    busy: "Đang cập nhật…",
    toast: "Đã chuyển đơn sang “Đã hoàn tiền”",
    effects: ["Đơn và thanh toán chuyển sang “Đã hoàn tiền”", "Quyền truy cập bị thu hồi", "Lịch tư vấn chưa diễn ra bị huỷ"],
    placeholder: "VD: Chuyên gia ốm, không thể tư vấn đúng lịch. Đã thống nhất hoàn tiền với khách.",
  },
  cancel: {
    title: "Huỷ đơn hàng?",
    button: "Huỷ đơn",
    busy: "Đang huỷ…",
    toast: "Đã huỷ đơn hàng",
    effects: ["Đơn chuyển sang “Đã huỷ”", "Mã QR đang mở hết hiệu lực", "Khung giờ tư vấn đang giữ được trả lại"],
    placeholder: "VD: Khách đặt nhầm gói và yêu cầu huỷ qua hotline.",
  },
};

function Detail({ order, onOrderChange }: { order: AdminOrder; onOrderChange: (order: AdminOrder) => void }) {
  const act = useOrderAction();
  const [action, setAction] = React.useState<OrderAction>("refund");
  const [dialogOpen, setDialogOpen] = React.useState(false);
  const [note, setNote] = React.useState("");
  const noteId = React.useId();
  const noteOk = note.trim().length >= MIN_AUDIT_NOTE_LENGTH;
  const copy = ACTION_COPY[action];

  function openDialog(next: OrderAction) {
    setAction(next);
    setNote("");
    setDialogOpen(true);
  }

  function submit() {
    if (!noteOk) return;
    act.mutate(
      { orderId: order.id, action, note: note.trim() },
      {
        onSuccess: (updated) => {
          toast.success(ACTION_COPY[action].toast, {
            description: action === "refund" ? "Nhớ hoàn tiền thủ công cho khách qua PaymentOS." : undefined,
          });
          setDialogOpen(false);
          setNote("");
          onOrderChange(updated);
        },
        onError: (e) => toast.error(action === "refund" ? "Chưa hoàn tiền được" : "Chưa huỷ được đơn", { description: describeError(e) }),
      },
    );
  }

  const grant = order.accessGrant;
  const consultation = order.consultation;

  return (
    <>
      <SheetHeader className="border-b">
        <div className="flex flex-wrap gap-1.5">
          <OrderStatusBadge status={order.status} />
          <ServiceTypeBadge type={order.service.type} />
        </div>
        <SheetTitle className="mt-2 leading-snug">{order.service.title}</SheetTitle>
        <SheetDescription>
          Mã đơn <span className="font-mono">{order.id}</span> · tạo lúc {formatDateTime(order.createdAt)}
        </SheetDescription>
      </SheetHeader>

      <div className="flex flex-col gap-6 p-5">
        <dl className="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
          <div className="col-span-2 flex min-w-0 items-center gap-3">
            <InitialsAvatar name={order.buyer.fullName} />
            <div className="min-w-0">
              <dt className="text-xs text-muted-foreground">Người mua</dt>
              <dd className="truncate font-semibold">{order.buyer.fullName}</dd>
              {order.buyer.email && <dd className="truncate text-xs text-muted-foreground">{order.buyer.email}</dd>}
            </div>
          </div>
          <Info label="Chuyên gia" value={order.service.chefName} />
          <Info label="Số tiền" value={formatVnd(order.amount)} mono />
        </dl>

        <section aria-labelledby={`${noteId}-timeline`} className="flex flex-col gap-3">
          <h3 id={`${noteId}-timeline`} className="text-sm font-bold">
            Tiến trình
          </h3>
          <Timeline order={order} />
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

        <section aria-labelledby={`${noteId}-grant`} className="flex flex-col gap-2">
          <h3 id={`${noteId}-grant`} className="text-sm font-bold">
            Quyền truy cập
          </h3>
          {grant ? (
            <div className="flex flex-col gap-2 rounded-lg border p-3 text-sm">
              <GrantStatusBadge status={grant.status} />
              <dl className="grid grid-cols-2 gap-x-4 gap-y-2">
                <Info label="Cấp lúc" value={formatDateTime(grant.grantedAt)} />
                <Info label="Hết hạn" value={grant.expiresAt ? formatDateTime(grant.expiresAt) : "Không giới hạn"} />
              </dl>
            </div>
          ) : (
            <p className="rounded-lg bg-muted px-3 py-2 text-sm text-muted-foreground">
              {order.status === "Pending" ? "Quyền truy cập được cấp ngay khi thanh toán thành công." : "Đơn không được cấp quyền truy cập."}
            </p>
          )}
        </section>

        {consultation && (
          <section aria-labelledby={`${noteId}-consult`} className="flex flex-col gap-2">
            <h3 id={`${noteId}-consult`} className="text-sm font-bold">
              Lịch tư vấn
            </h3>
            <div className="flex flex-col gap-2 rounded-lg border p-3 text-sm">
              <ConsultationStatusBadge status={consultation.status} />
              <dl className="grid grid-cols-2 gap-x-4 gap-y-2">
                <Info label="Bắt đầu" value={formatDateTime(consultation.startAt)} />
                <Info label="Thời lượng" value={consultation.durationMinutes ? `${consultation.durationMinutes} phút` : "—"} />
                <Info label="Mã lịch hẹn" value={consultation.id} mono />
              </dl>
            </div>
          </section>
        )}

        <section className="flex flex-col gap-2 rounded-lg border p-3">
          <h3 className="text-sm font-bold">Xử lý đơn</h3>
          {order.status === "Paid" ? (
            <>
              <p className="text-xs text-muted-foreground">
                Chỉ cập nhật trạng thái — hoàn tiền thực hiện thủ công qua PaymentOS.
              </p>
              <Button size="sm" variant="destructive" className="w-fit" disabled={act.isPending} onClick={() => openDialog("refund")}>
                <RotateCcw aria-hidden />
                Hoàn tiền
              </Button>
            </>
          ) : order.status === "Pending" ? (
            <>
              <p className="text-xs text-muted-foreground">Đơn chưa thanh toán. Huỷ để đóng mã QR và trả lại khung giờ đang giữ.</p>
              <Button size="sm" variant="destructive" className="w-fit" disabled={act.isPending} onClick={() => openDialog("cancel")}>
                <Ban aria-hidden />
                Huỷ đơn
              </Button>
            </>
          ) : (
            <p className="text-sm text-muted-foreground">
              Đơn đã {order.status === "Refunded" ? "hoàn tiền" : "huỷ"} — không còn thao tác nào.
            </p>
          )}
        </section>
      </div>

      <Dialog open={dialogOpen} onOpenChange={(open) => !act.isPending && setDialogOpen(open)}>
        <DialogContent>
          <DialogTitle>{copy.title}</DialogTitle>
          <DialogDescription>
            {order.id} · {order.service.title} · {formatVnd(order.amount)}
          </DialogDescription>
          <ul className="list-disc space-y-1 pl-5 text-sm">
            {copy.effects.map((e) => (
              <li key={e}>{e}</li>
            ))}
          </ul>
          {action === "refund" && (
            <p className="rounded-lg border border-ochre-border bg-ochre-soft px-3 py-2 text-xs text-ochre-text">
              Chỉ cập nhật trạng thái — hoàn tiền thực hiện thủ công qua PaymentOS.
            </p>
          )}
          <div className="flex flex-col gap-1.5">
            <Label htmlFor={noteId}>
              Ghi chú <span className="text-destructive">(bắt buộc)</span>
            </Label>
            <Textarea
              id={noteId}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder={copy.placeholder}
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
              {act.isPending ? copy.busy : copy.button}
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
