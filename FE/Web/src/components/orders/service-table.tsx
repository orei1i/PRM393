// src/components/orders/service-table.tsx
"use client";

import { Skeleton } from "@/components/ui/form-controls";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { formatNumber } from "@/lib/utils";
import type { AdminService } from "@/types/commerce";

import { formatVnd, ServiceTypeBadge } from "./order-badges";

export function ServiceTable({ services, isLoading }: { services: AdminService[] | undefined; isLoading: boolean }) {
  const totals = services?.reduce(
    (acc, s) => ({ orders: acc.orders + s.orderCount, paid: acc.paid + s.paidCount, revenue: acc.revenue + s.revenue }),
    { orders: 0, paid: 0, revenue: 0 },
  );

  return (
    <Table className="min-w-[920px]">
      <TableHeader>
        <TableRow className="hover:bg-transparent">
          <TableHead>Chuyên gia</TableHead>
          <TableHead className="w-[32%]">Dịch vụ</TableHead>
          <TableHead>Loại</TableHead>
          <TableHead className="text-right">Giá</TableHead>
          <TableHead className="text-right">Số đơn</TableHead>
          <TableHead className="text-right">Đã thanh toán</TableHead>
          <TableHead className="text-right">Doanh thu</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {isLoading
          ? Array.from({ length: 6 }, (_, i) => (
              <TableRow key={i}>
                <TableCell colSpan={7}>
                  <Skeleton className="h-8" />
                </TableCell>
              </TableRow>
            ))
          : services?.map((s, i) => {
              const firstOfChef = i === 0 || services[i - 1].chefId !== s.chefId;
              return (
                <TableRow key={s.id} className={firstOfChef && i > 0 ? "border-t-2" : undefined}>
                  <TableCell className={firstOfChef ? "font-semibold" : "text-muted-foreground"}>
                    {firstOfChef ? s.chefName : <span className="sr-only">{s.chefName}</span>}
                  </TableCell>
                  <TableCell className="whitespace-normal">
                    <span className="line-clamp-2 font-semibold">{s.title}</span>
                  </TableCell>
                  <TableCell>
                    <ServiceTypeBadge type={s.type} />
                  </TableCell>
                  <TableCell className="text-right font-mono tabular">{formatVnd(s.price)}</TableCell>
                  <TableCell className="text-right font-mono tabular">{formatNumber(s.orderCount)}</TableCell>
                  <TableCell className="text-right font-mono tabular">{formatNumber(s.paidCount)}</TableCell>
                  <TableCell className={s.revenue > 0 ? "text-right font-mono font-semibold tabular" : "text-right font-mono tabular text-muted-foreground"}>
                    {formatVnd(s.revenue)}
                  </TableCell>
                </TableRow>
              );
            })}
        {!isLoading && totals && services && services.length > 1 && (
          <TableRow className="border-t-2 bg-muted/40 hover:bg-muted/40">
            <TableCell colSpan={4} className="font-bold">
              Tổng ({formatNumber(services.length)} dịch vụ)
            </TableCell>
            <TableCell className="text-right font-mono font-bold tabular">{formatNumber(totals.orders)}</TableCell>
            <TableCell className="text-right font-mono font-bold tabular">{formatNumber(totals.paid)}</TableCell>
            <TableCell className="text-right font-mono font-bold tabular">{formatVnd(totals.revenue)}</TableCell>
          </TableRow>
        )}
      </TableBody>
    </Table>
  );
}
