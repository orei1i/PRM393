// src/components/disputes/escrow-kpis.tsx
"use client";

import type { UseQueryResult } from "@tanstack/react-query";
import { CalendarClock, Lock, Percent, Snowflake, TriangleAlert } from "lucide-react";

import { formatVnd } from "@/components/orders/order-badges";
import { MetricCard } from "@/components/telemetry/metric-card";
import { Button } from "@/components/ui/button";
import { describeError } from "@/lib/api_error";
import { formatNumber, formatPercent } from "@/lib/utils";
import type { EscrowSummary } from "@/types/bookings";
import { RELEASING_SOON_DAYS } from "@/types/payouts";

export function EscrowKpis({ summary, onShowStuck }: { summary: UseQueryResult<EscrowSummary>; onShowStuck: () => void }) {
  const data = summary.data;
  const loading = summary.isLoading;
  return (
    <section aria-label="Chỉ số tiền đang giữ" className="flex flex-col gap-3">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-5">
        <MetricCard
          label="Tiền đang giữ"
          value={data ? formatVnd(data.totalHeld) : "–"}
          hint={
            data
              ? `${formatNumber(data.totalHeldCount)} khoản · gồm cả tiền tạm giữ · ${formatNumber(data.awaitingCompletionCount)} chờ chuyên gia xác nhận`
              : undefined
          }
          icon={Lock}
          loading={loading}
        />
        <MetricCard
          label={`Sẽ giải ngân trong ${RELEASING_SOON_DAYS} ngày`}
          value={data ? formatVnd(data.releasingSoon) : "–"}
          hint={data ? `${formatNumber(data.releasingSoonCount)} khoản tự vào ví chuyên gia nếu không có khiếu nại` : undefined}
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
          label="Kẹt, cần Ban quản trị xử lý"
          value={data ? formatVnd(data.stuckAmount) : "–"}
          hint={data ? `${formatNumber(data.stuckCount)} khoản quá hạn tự hoàn tất, không có khiếu nại` : undefined}
          icon={TriangleAlert}
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
      {data && data.stuckCount > 0 && (
        <div className="flex flex-wrap items-center gap-3 rounded-lg border border-ochre-border bg-ochre-soft px-4 py-2 text-sm text-ochre-text">
          <TriangleAlert className="size-4 shrink-0" aria-hidden />
          <span className="min-w-0 flex-1">
            <b>{formatNumber(data.stuckCount)} khoản</b> ({formatVnd(data.stuckAmount)}) không có đường ra nếu chuyên gia không xác nhận và thành viên không khiếu nại.
          </span>
          <Button size="sm" variant="outline" onClick={onShowStuck}>
            Xem khoản kẹt
          </Button>
        </div>
      )}
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
