// src/app/(admin)/payouts/page.tsx
"use client";

import * as React from "react";
import Link from "next/link";
import { useIsFetching, useQueryClient } from "@tanstack/react-query";
import { Info, RefreshCw } from "lucide-react";

import { PageHeader } from "@/components/admin/page-header";
import { formatVnd } from "@/components/orders/order-badges";
import { PayoutKpis } from "@/components/payouts/payout-kpis";
import { WalletsPanel } from "@/components/payouts/wallets-panel";
import { WithdrawalsPanel } from "@/components/payouts/withdrawals-panel";
import { Button } from "@/components/ui/button";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { payoutKeys, usePayoutSummary } from "@/lib/hooks/use-payouts";
import { formatPercent } from "@/lib/utils";
import { AUTO_APPROVE_LIMIT, ESCROW_HOLD_DAYS, PLATFORM_FEE_RATE } from "@/types/payouts";

type PageTab = "withdrawals" | "wallets";

export default function PayoutsPage() {
  const [tab, setTab] = React.useState<PageTab>("withdrawals");
  const qc = useQueryClient();
  const fetching = useIsFetching({ queryKey: payoutKeys.all }) > 0;
  const summary = usePayoutSummary();
  const awaiting = summary.data?.awaitingApproval ?? 0;

  return (
    <div className="flex flex-col gap-6">
      <PageHeader
        title="Ví & rút tiền chuyên gia"
        description="Thu nhập của chuyên gia từ lượt đặt thiết kế thực đơn (sau phí nền tảng) và yêu cầu rút về tài khoản ngân hàng."
        actions={
          <Button variant="outline" onClick={() => qc.invalidateQueries({ queryKey: payoutKeys.all })} disabled={fetching}>
            <RefreshCw className={fetching ? "animate-spin" : undefined} aria-hidden />
            Làm mới
          </Button>
        }
      />

      <PayoutKpis summary={summary} />

      <p className="flex gap-2.5 rounded-lg border bg-card px-4 py-3 text-sm text-muted-foreground">
        <Info className="mt-0.5 size-4 shrink-0" aria-hidden />
        <span>
          Phí nền tảng {formatPercent(PLATFORM_FEE_RATE)} mỗi lượt đặt. Tiền được giữ đến {ESCROW_HOLD_DAYS} ngày sau khi kế hoạch kết thúc
          rồi mới vào “Có thể rút”; khiếu nại làm khoản đó “Tạm giữ” đến khi có quyết định ở{" "}
          <Link href="/disputes" className="font-semibold text-primary underline-offset-4 hover:underline">
            Khiếu nại &amp; giữ tiền
          </Link>
          . Yêu cầu rút <b className="text-foreground">tối đa {formatVnd(AUTO_APPROVE_LIMIT)}</b> được chi trả
          tự động; <b className="text-foreground">trên {formatVnd(AUTO_APPROVE_LIMIT)}</b> chờ Ban quản trị chuyển khoản rồi xác nhận.
        </span>
      </p>

      <Tabs value={tab} onValueChange={(v) => setTab(v as PageTab)} className="gap-4">
        <TabsList className="max-w-full justify-start overflow-x-auto">
          <TabsTrigger value="withdrawals">
            Yêu cầu rút tiền
            {awaiting > 0 && (
              <span className="rounded-full bg-ochre-soft px-1.5 font-mono text-[11px] text-ochre-text tabular">
                {awaiting}
                <span className="sr-only"> chờ duyệt</span>
              </span>
            )}
          </TabsTrigger>
          <TabsTrigger value="wallets">Ví chuyên gia</TabsTrigger>
        </TabsList>
        <TabsContent value="withdrawals" className="min-w-0">
          <WithdrawalsPanel summary={summary.data} />
        </TabsContent>
        <TabsContent value="wallets" className="min-w-0">
          <WalletsPanel />
        </TabsContent>
      </Tabs>
    </div>
  );
}
