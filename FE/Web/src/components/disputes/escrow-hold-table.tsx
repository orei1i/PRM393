// src/components/disputes/escrow-hold-table.tsx
"use client";

import Link from "next/link";
import { Scale } from "lucide-react";

import { InitialsAvatar } from "@/components/admin/initials-avatar";
import { formatVnd } from "@/components/orders/order-badges";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/form-controls";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { planSummary, type AdminEscrowHold } from "@/types/bookings";

import { EscrowStatusBadge, formatDateOnly, formatVnDateTime, timeLeft } from "./booking-badges";

export function EscrowHoldTable({
  holds,
  isLoading,
  onOpenComplaint,
}: {
  holds: AdminEscrowHold[] | undefined;
  isLoading: boolean;
  onOpenComplaint: (complaintId: string) => void;
}) {
  return (
    <Table className="min-w-[1080px]">
      <TableHeader>
        <TableRow className="hover:bg-transparent">
          <TableHead>Đặt chuyên gia</TableHead>
          <TableHead>Thành viên</TableHead>
          <TableHead>Chuyên gia</TableHead>
          <TableHead className="text-right">Số tiền</TableHead>
          <TableHead>Trạng thái</TableHead>
          <TableHead>Kết thúc kế hoạch</TableHead>
          <TableHead>Giải ngân</TableHead>
          <TableHead>
            <span className="sr-only">Thao tác</span>
          </TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {isLoading
          ? Array.from({ length: 5 }, (_, i) => (
              <TableRow key={i}>
                <TableCell colSpan={8}>
                  <Skeleton className="h-10" />
                </TableCell>
              </TableRow>
            ))
          : holds?.map((h) => {
              const complaintId = h.booking.complaintId;
              return (
                <TableRow key={h.id}>
                  <TableCell>
                    <span className="block font-mono text-xs font-semibold">{h.booking.id}</span>
                    <span className="block text-xs text-muted-foreground">{planSummary(h.booking)}</span>
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <InitialsAvatar name={h.booking.member.fullName} className="size-7 text-[10px]" />
                      <span className="max-w-36 truncate">{h.booking.member.fullName}</span>
                    </div>
                  </TableCell>
                  <TableCell>
                    <span className="block max-w-40 truncate">{h.booking.chef.fullName}</span>
                  </TableCell>
                  <TableCell className="text-right">
                    <span className="block font-mono font-semibold tabular">{formatVnd(h.amount)}</span>
                    {h.refundedAmount > 0 && (
                      <span className="block font-mono text-xs text-muted-foreground tabular">hoàn {formatVnd(h.refundedAmount)}</span>
                    )}
                  </TableCell>
                  <TableCell>
                    <EscrowStatusBadge status={h.status} />
                  </TableCell>
                  <TableCell className="whitespace-nowrap text-muted-foreground">
                    {h.booking.endDate ? formatDateOnly(h.booking.endDate) : "—"}
                    <span className="block text-xs">
                      đã giao {h.booking.deliveredDays}/{h.booking.planDays} ngày
                    </span>
                  </TableCell>
                  <TableCell className="whitespace-nowrap">
                    {h.status === "Held" ? (
                      <>
                        <span className="block">{formatVnDateTime(h.releaseAt)}</span>
                        <span className="block text-xs text-muted-foreground">tự động · {timeLeft(h.releaseAt)}</span>
                      </>
                    ) : h.status === "Frozen" ? (
                      <>
                        <span className="block text-destructive">Chờ quyết định</span>
                        <span className="block text-xs text-muted-foreground">hạn gốc {formatVnDateTime(h.releaseAt)}</span>
                      </>
                    ) : (
                      <>
                        <span className="block">{h.releasedAt ? formatVnDateTime(h.releasedAt) : "—"}</span>
                        <span className="block text-xs text-muted-foreground">
                          {h.resolvedBy ? `quyết định của ${h.resolvedBy}` : "tự động khi hết hạn khiếu nại"}
                        </span>
                      </>
                    )}
                  </TableCell>
                  <TableCell>
                    <div className="flex flex-wrap justify-end gap-1.5">
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
