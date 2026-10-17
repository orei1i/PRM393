// src/components/orders/order-table.tsx
"use client";

import { InitialsAvatar } from "@/components/admin/initials-avatar";
import { Skeleton } from "@/components/ui/form-controls";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { planSummary } from "@/types/bookings";
import type { AdminOrder } from "@/types/commerce";

import { dateTimeVi, formatVnd, OrderStatusBadge, OrderTypeBadge, PaymentStatusBadge } from "./order-badges";

/** The payment that decides the order's state: the newest attempt. */
export const latestPayment = (order: AdminOrder) => order.payments[order.payments.length - 1] ?? null;

export function OrderTable({
  orders,
  isLoading,
  selectedId,
  onSelect,
}: {
  orders: AdminOrder[] | undefined;
  isLoading: boolean;
  selectedId: string | null;
  onSelect: (order: AdminOrder) => void;
}) {
  return (
    <Table className="min-w-[1080px]">
      <TableHeader>
        <TableRow className="hover:bg-transparent">
          <TableHead>Mã đơn</TableHead>
          <TableHead>Thành viên</TableHead>
          <TableHead className="w-[24%]">Loại · đặt chuyên gia</TableHead>
          <TableHead>Chuyên gia</TableHead>
          <TableHead className="text-right">Số tiền</TableHead>
          <TableHead>Trạng thái</TableHead>
          <TableHead>Thanh toán</TableHead>
          <TableHead>Ngày tạo</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {isLoading
          ? Array.from({ length: 8 }, (_, i) => (
              <TableRow key={i}>
                <TableCell colSpan={8}>
                  <Skeleton className="h-10" />
                </TableCell>
              </TableRow>
            ))
          : orders?.map((order) => {
              const payment = latestPayment(order);
              return (
                <TableRow
                  key={order.id}
                  data-state={order.id === selectedId ? "selected" : undefined}
                  tabIndex={0}
                  onClick={() => onSelect(order)}
                  onKeyDown={(e) => {
                    if (e.target === e.currentTarget && (e.key === "Enter" || e.key === " ")) {
                      e.preventDefault();
                      onSelect(order);
                    }
                  }}
                  className="cursor-pointer"
                  aria-label={`Mở đơn ${order.id} của ${order.buyer.fullName}`}
                >
                  <TableCell className="font-mono text-xs font-semibold">{order.id}</TableCell>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <InitialsAvatar name={order.buyer.fullName} className="size-8" />
                      <span className="max-w-40 truncate font-semibold">{order.buyer.fullName}</span>
                    </div>
                  </TableCell>
                  <TableCell className="whitespace-normal">
                    <OrderTypeBadge />
                    <span className="mt-1 block text-xs">
                      <span className="font-mono font-semibold">{order.booking.id}</span>
                      <span className="text-muted-foreground"> · {planSummary(order.booking)}</span>
                    </span>
                  </TableCell>
                  <TableCell className="text-muted-foreground">{order.booking.chefName}</TableCell>
                  <TableCell className="text-right">
                    <span className="block font-mono font-semibold tabular">{formatVnd(order.amount)}</span>
                    {order.refundedAmount > 0 && (
                      <span className="block font-mono text-xs text-muted-foreground tabular">hoàn {formatVnd(order.refundedAmount)}</span>
                    )}
                  </TableCell>
                  <TableCell>
                    <OrderStatusBadge status={order.status} />
                  </TableCell>
                  <TableCell>
                    {payment ? (
                      <div className="flex flex-col gap-1">
                        <PaymentStatusBadge status={payment.status} />
                        <span className="font-mono text-xs text-muted-foreground">{payment.transactionRef}</span>
                      </div>
                    ) : (
                      <span className="text-muted-foreground">—</span>
                    )}
                  </TableCell>
                  <TableCell className="text-muted-foreground">{dateTimeVi.format(new Date(order.createdAt))}</TableCell>
                </TableRow>
              );
            })}
      </TableBody>
    </Table>
  );
}
