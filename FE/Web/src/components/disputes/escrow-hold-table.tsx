// src/components/disputes/escrow-hold-table.tsx
"use client";

import Link from "next/link";
import { Gavel, Scale, TriangleAlert } from "lucide-react";

import { InitialsAvatar } from "@/components/admin/initials-avatar";
import { formatVnd } from "@/components/orders/order-badges";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/form-controls";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { cn } from "@/lib/utils";
import { autoCompleteAt, familySummary, planSummary, type AdminEscrowHold } from "@/types/bookings";

import { adminResolvedLabel, completionHint, completionLabel, EscrowStatusBadge, formatDateOnly, formatVnDateTime, moneyLocation, timeLeft } from "./booking-badges";

export function EscrowHoldTable({
  holds,
  isLoading,
  onOpenComplaint,
  onResolve,
}: {
  holds: AdminEscrowHold[] | undefined;
  isLoading: boolean;
  onOpenComplaint: (complaintId: string) => void;
  onResolve: (hold: AdminEscrowHold) => void;
}) {
  return (
    <Table className="min-w-[1120px]">
      <TableHeader>
        <TableRow className="hover:bg-transparent">
          <TableHead>Đặt chuyên gia</TableHead>
          <TableHead>Thành viên → chuyên gia</TableHead>
          <TableHead className="text-right">Số tiền</TableHead>
          <TableHead>Tiền đang ở</TableHead>
          <TableHead>Kế hoạch · xác nhận</TableHead>
          <TableHead>Hạn giữ</TableHead>
          <TableHead className="bg-card xl:sticky xl:right-0">
            <span className="sr-only">Thao tác</span>
          </TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {isLoading
          ? Array.from({ length: 5 }, (_, i) => (
              <TableRow key={i}>
                <TableCell colSpan={7}>
                  <Skeleton className="h-10" />
                </TableCell>
              </TableRow>
            ))
          : holds?.map((h) => {
              const complaintId = h.booking.complaintId;
              const hint = completionHint(h.booking, h.status === "Frozen");
              // A member's cancellation leaves resolvedBy null; an admin's refund also cancels the booking.
              const memberCancelled = h.booking.status === "Cancelled" && !h.resolvedBy;
              const adminResolved = !complaintId && !!h.resolvedBy;
              const decidedAt = h.releasedAt ?? h.refundedAt ?? "";
              return (
                <TableRow key={h.id}>
                  <TableCell>
                    <span className="block font-mono text-xs font-semibold">{h.booking.id}</span>
                    <span className="block text-xs text-muted-foreground">{planSummary(h.booking)}</span>
                    {h.booking.audience === "Family" && <span className="block text-xs font-semibold text-foreground">{familySummary(h.booking)}</span>}
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <InitialsAvatar name={h.booking.member.fullName} className="size-7 text-[10px]" />
                      <span className="min-w-0">
                        <span className="block max-w-40 truncate">{h.booking.member.fullName}</span>
                        <span className="block max-w-40 truncate text-xs text-muted-foreground">→ {h.booking.chef.fullName}</span>
                      </span>
                    </div>
                  </TableCell>
                  <TableCell className="text-right">
                    <span className="block font-mono font-semibold tabular">{formatVnd(h.amount)}</span>
                    {h.refundedAmount > 0 && (
                      <span className="block font-mono text-xs text-muted-foreground tabular">hoàn {formatVnd(h.refundedAmount)}</span>
                    )}
                  </TableCell>
                  <TableCell className="max-w-56 whitespace-normal">
                    <EscrowStatusBadge status={h.status} />
                    <span className="mt-1 block text-xs text-muted-foreground">
                      {h.isStuck ? "VeganLife giữ, quá hạn tự hoàn tất, chờ Ban quản trị" : moneyLocation(h)}
                    </span>
                  </TableCell>
                  <TableCell className="max-w-64 whitespace-normal text-muted-foreground">
                    Kết thúc {h.booking.endDate ? formatDateOnly(h.booking.endDate) : "—"} · giao {h.booking.deliveredDays}/{h.booking.planDays}
                    <span className="block text-xs">
                      {adminResolved ? (
                        <>
                          {adminResolvedLabel(decidedAt)}
                          {h.resolutionNote && <span className="block break-words">“{h.resolutionNote}”</span>}
                        </>
                      ) : h.completedAt ? (
                        completionLabel(h.completedAt, h.booking.autoCompleted)
                      ) : h.status === "Held" || h.status === "Frozen" ? (
                        <span className={cn(hint.attention ? "inline-flex items-start gap-1 font-semibold text-destructive" : "text-ochre-text")}>
                          {hint.attention && <TriangleAlert className="mt-0.5 size-3.5 shrink-0" aria-hidden />}
                          {hint.text}
                        </span>
                      ) : (
                        "Không có xác nhận"
                      )}
                    </span>
                  </TableCell>
                  <TableCell className="whitespace-nowrap">
                    {h.status === "Held" && h.releaseAt ? (
                      <>
                        <span className="block">{formatVnDateTime(h.releaseAt)}</span>
                        <span className="block text-xs text-muted-foreground">tự động · {timeLeft(h.releaseAt)}</span>
                      </>
                    ) : h.status === "Held" ? (
                      <>
                        <span className="block text-muted-foreground">Chưa có ngày</span>
                        <span className="block text-xs text-muted-foreground">
                          {h.isStuck && h.booking.endDate ? `quá hạn từ ${formatVnDateTime(autoCompleteAt(h.booking.endDate))}` : "tính từ lúc hoàn thành"}
                        </span>
                      </>
                    ) : h.status === "Frozen" ? (
                      <>
                        <span className="block text-destructive">Chờ quyết định</span>
                        <span className="block text-xs text-muted-foreground">
                          {h.releaseAt ? `hạn gốc ${formatVnDateTime(h.releaseAt)}` : "chưa xác nhận hoàn thành"}
                        </span>
                      </>
                    ) : (
                      <>
                        <span className="block">{formatVnDateTime(decidedAt)}</span>
                        <span className="block text-xs text-muted-foreground">
                          {memberCancelled ? "thành viên huỷ sau khi thanh toán" : h.resolvedBy ? `quyết định của ${h.resolvedBy}` : "tự động khi hết hạn giữ"}
                        </span>
                      </>
                    )}
                  </TableCell>
                  <TableCell className="bg-card xl:sticky xl:right-0">
                    <div className="flex flex-wrap justify-end gap-1.5">
                      {h.isStuck && (
                        <Button size="sm" variant="warn" onClick={() => onResolve(h)} aria-label={`Xử lý khoản giữ tiền ${h.booking.id}`}>
                          <Gavel aria-hidden />
                          Xử lý
                        </Button>
                      )}
                      {complaintId && (
                        <Button size="sm" variant={h.status === "Frozen" ? "warn" : "outline"} onClick={() => onOpenComplaint(complaintId)}>
                          <Scale aria-hidden />
                          Khiếu nại
                        </Button>
                      )}
                      {h.booking.paymentOrderId && (
                        <Button asChild size="sm" variant="ghost">
                          <Link href={`/orders?open=${encodeURIComponent(h.booking.paymentOrderId)}`} aria-label={`Mở đơn thanh toán ${h.booking.paymentOrderId}`}>
                            {h.booking.paymentOrderId}
                          </Link>
                        </Button>
                      )}
                    </div>
                  </TableCell>
                </TableRow>
              );
            })}
      </TableBody>
    </Table>
  );
}
