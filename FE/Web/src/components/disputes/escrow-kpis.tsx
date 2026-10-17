// src/components/disputes/escrow-kpis.tsx
"use client";

import type { UseQueryResult } from "@tanstack/react-query";
import { CalendarClock, Lock, Percent, Snowflake } from "lucide-react";

import { formatVnd } from "@/components/orders/order-badges";
import { MetricCard } from "@/components/telemetry/metric-card";
import { Button } from "@/components/ui/button";
import { describeError } from "@/lib/api_error";
import { formatNumber, formatPercent } from "@/lib/utils";
import type { EscrowSummary } from "@/types/bookings";

export function EscrowKpis({ summary }: { summary: UseQueryResult<EscrowSummary> }) {
  const data = summary.data;
  const loading = summary.isLoading;
  return (
    <section aria-label="Chỉ số tiền đang giữ" className="flex flex-col gap-3">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard
          label="Tiền đang giữ"
          value={data ? formatVnd(data.totalHeld) : "–"}
          hint={data ? `${formatNumber(data.totalHeldCount)} khoản · gồm cả tiền tạm giữ` : undefined}
          icon={Lock}
          loading={loading}
        />
        <MetricCard
          label={`Sẽ giải ngân trong ${data?.holdDays ?? 3} ngày`}
          value={data ? formatVnd(data.releasingSoon) : "–"}
          hint={data ? `${formatNumber(data.releasingSoonCount)} khoản tự chuyển cho chuyên gia nếu không có khiếu nại` : undefined}
          icon={CalendarClock}
          loading={loading}
        />
        <MetricCard
          label="Đang tạm giữ do khiếu nại"
          value={data ? formatVnd(data.frozen) : "–"}
          hint={data ? `${formatNumber(data.frozenCount)} khoản · ${formatNumber(data.openComplaints)} khiếu nại chờ xử lý` : undefined}
          icon={Snowflake}
          loading={loading}
        />
        <MetricCard
          label="Phí nền tảng tháng này"
          value={data ? formatVnd(data.feeThisMonth) : "–"}
          hint={
            data
              ? `${formatPercent(data.feeRate)} × ${formatVnd(data.releasedThisMonth)} đã giải ngân · hoàn ${formatVnd(data.refundedThisMonth)}`
              : undefined
          }
          icon={Percent}
          loading={loading}
        />
      </div>
      {summary.isError && (
        <div role="alert" className="flex flex-wrap items-center gap-3 rounded-lg border border-destructive/30 px-4 py-2 text-sm">
          <span className="font-semibold">Chưa tải được chỉ số.</span>
          <span className="text-muted-foreground">{describeError(summary.error)}</span>
          <Button size="sm" variant="outline" className="sm:ml-auto" onClick={() => summary.refetch()}>
            Thử lại
          </Button>
        </div>
      )}
    </section>
  );
}
