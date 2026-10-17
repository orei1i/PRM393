// src/components/orders/commerce-kpis.tsx
"use client";

import type { UseQueryResult } from "@tanstack/react-query";
import { Hourglass, Lock, RotateCcw, Wallet } from "lucide-react";

import { Button } from "@/components/ui/button";
import { MetricCard } from "@/components/telemetry/metric-card";
import { describeError } from "@/lib/api_error";
import { formatNumber } from "@/lib/utils";
import type { CommerceSummary } from "@/types/commerce";

import { formatVnd } from "./order-badges";

export function CommerceKpis({ summary }: { summary: UseQueryResult<CommerceSummary> }) {
  const data = summary.data;
  const loading = summary.isLoading;
  return (
    <section aria-label="Chỉ số kinh doanh" className="flex flex-col gap-3">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard
          label="Doanh thu đã thu"
          value={data ? formatVnd(data.revenue) : "–"}
          hint={data ? `${formatNumber(data.byStatus.Paid + data.byStatus.PartiallyRefunded)} đơn đã thanh toán · đã trừ hoàn tiền` : undefined}
          icon={Wallet}
          loading={loading}
        />
        <MetricCard
          label="Đơn chờ thanh toán"
          value={data ? formatNumber(data.byStatus.Pending) : "–"}
          hint={data ? `${formatVnd(data.pendingAmount)} đang chờ quét QR` : undefined}
          icon={Hourglass}
          loading={loading}
        />
        <MetricCard
          label="Đã hoàn tiền"
          value={data ? formatVnd(data.refundedAmount) : "–"}
          hint={data ? `${formatNumber(data.byStatus.Refunded)} hoàn toàn bộ · ${formatNumber(data.byStatus.PartiallyRefunded)} hoàn một phần` : undefined}
          icon={RotateCcw}
          loading={loading}
        />
        <MetricCard
          label="Đang giữ (chờ giải ngân)"
          value={data ? formatVnd(data.heldAmount) : "–"}
          hint={data ? `${formatNumber(data.heldCount)} đơn · gồm cả tiền tạm giữ do khiếu nại` : undefined}
          icon={Lock}
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
