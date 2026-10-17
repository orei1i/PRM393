// src/app/(admin)/orders/page.tsx
"use client";

import * as React from "react";
import { useIsFetching, useQueryClient } from "@tanstack/react-query";
import { RefreshCw } from "lucide-react";

import { PageHeader } from "@/components/admin/page-header";
import { CommerceKpis } from "@/components/orders/commerce-kpis";
import { OrdersPanel } from "@/components/orders/orders-panel";
import { Button } from "@/components/ui/button";
import { commerceKeys, useCommerceSummary } from "@/lib/hooks/use-commerce";

export default function OrdersPage() {
  const qc = useQueryClient();
  const fetching = useIsFetching({ queryKey: commerceKeys.all }) > 0;
  const summary = useCommerceSummary();

  return (
    <div className="flex flex-col gap-6">
      <PageHeader
        title="Đơn hàng & thanh toán"
        description="Thanh toán đặt chuyên gia thiết kế thực đơn qua PaymentOS. Tiền được giữ đến khi hết hạn khiếu nại; hoàn tiền xử lý ở “Khiếu nại & giữ tiền”."
        actions={
          <Button variant="outline" onClick={() => qc.invalidateQueries({ queryKey: commerceKeys.all })} disabled={fetching}>
            <RefreshCw className={fetching ? "animate-spin" : undefined} aria-hidden />
            Làm mới
          </Button>
        }
      />

      <CommerceKpis summary={summary} />

      {/* useSearchParams (?open=) needs a Suspense boundary for the static prerender. */}
      <React.Suspense fallback={null}>
        <OrdersPanel summary={summary.data} />
      </React.Suspense>
    </div>
  );
}
