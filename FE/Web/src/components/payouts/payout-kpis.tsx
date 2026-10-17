// src/components/payouts/payout-kpis.tsx
"use client";

import type { UseQueryResult } from "@tanstack/react-query";
import { HandCoins, Hourglass, Percent, Wallet } from "lucide-react";

import { formatVnd } from "@/components/orders/order-badges";
import { MetricCard } from "@/components/telemetry/metric-card";
import { Button } from "@/components/ui/button";
import { describeError } from "@/lib/api_error";
import { formatNumber, formatPercent } from "@/lib/utils";
import { ESCROW_HOLD_DAYS, type PayoutSummary } from "@/types/payouts";

/** "tháng 10, 2026" */
const monthVi = new Intl.DateTimeFormat("vi-VN", { month: "2-digit", year: "numeric" });

export function PayoutKpis({ summary }: { summary: UseQueryResult<PayoutSummary> }) {
  const data = summary.data;
  const loading = summary.isLoading;
  return (
    <section aria-label="Chỉ số ví chuyên gia" className="flex flex-col gap-3">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard
          label="Số dư có thể rút"
          value={data ? formatVnd(data.totalAvailable) : "–"}
          hint={data ? `Tổng ví chuyên gia · ${formatVnd(data.totalProcessing)} đang xử lý rút` : undefined}
          icon={Wallet}
          loading={loading}
        />
        <MetricCard
          label="Đang giữ"
          value={data ? formatVnd(data.totalPending) : "–"}
          hint={
            data
              ? `Đến ${ESCROW_HOLD_DAYS} ngày sau khi kế hoạch kết thúc · tạm giữ do khiếu nại ${formatVnd(data.totalFrozen)}`
              : `Đến ${ESCROW_HOLD_DAYS} ngày sau khi kế hoạch kết thúc`
          }
          icon={Hourglass}
          loading={loading}
        />
        <MetricCard
          label="Đã chi trả tháng này"
          value={data ? formatVnd(data.paidOutThisMonth) : "–"}
          hint={data ? `${formatNumber(data.paidOutThisMonthCount)} lệnh chuyển · ${monthVi.format(new Date())}` : undefined}
          icon={HandCoins}
          loading={loading}
        />
        <MetricCard
          label="Phí nền tảng thu được"
          value={data ? formatVnd(data.platformFee) : "–"}
          hint={
            data
              ? `${formatPercent(data.feeRate)} × ${formatVnd(data.releasedGross)} từ ${formatNumber(data.releasedCount)} khoản đã giải ngân`
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
