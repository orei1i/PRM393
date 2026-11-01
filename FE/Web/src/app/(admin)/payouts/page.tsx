// src/app/(admin)/payouts/page.tsx
"use client";

import * as React from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
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
import { ESCROW_HOLD_DAYS, MIN_WITHDRAWAL, PLATFORM_FEE_RATE } from "@/types/payouts";

type PageTab = "withdrawals" | "wallets";

export default function PayoutsPage() {
  return (
    <React.Suspense fallback={null}>
      <PayoutsScreen />
    </React.Suspense>
  );
}

/** `?tab=wallets&q=<tên>` comes from the user drawer on /users. */
function PayoutsScreen() {
  const params = useSearchParams();
  const initialSearch = params.get("q") ?? "";
  const [tab, setTab] = React.useState<PageTab>(params.get("tab") === "wallets" ? "wallets" : "withdrawals");
  const qc = useQueryClient();
  const fetching = useIsFetching({ queryKey: payoutKeys.all }) > 0;
  const summary = usePayoutSummary();
  const awaiting = summary.data?.awaitingApproval ?? 0;

  return (
    <div className="flex flex-col gap-6">
      <PageHeader
        title="Ví & rút tiền"
        description="Ví của chuyên gia (thu nhập từ lượt đặt, sau phí nền tảng) và của thành viên (tiền được hoàn), cùng yêu cầu rút về tài khoản ngân hàng."
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
          Phí nền tảng {formatPercent(PLATFORM_FEE_RATE)} mỗi lượt đặt. Tiền nằm ở VeganLife đến {ESCROW_HOLD_DAYS} ngày sau khi hợp đồng hoàn thành (chuyên gia xác nhận hoặc hệ thống tự hoàn tất)
          rồi mới vào ví chuyên gia; khiếu nại làm khoản đó “Tạm giữ” đến khi có quyết định ở{" "}
          <Link href="/disputes" className="font-semibold text-primary underline-offset-4 hover:underline">
            Khiếu nại &amp; giữ tiền
          </Link>
          , tiền hoàn vào ví thành viên. Cả hai bên đều rút được (tối thiểu {formatVnd(MIN_WITHDRAWAL)}), và{" "}
          <b className="text-foreground">mọi yêu cầu đều chờ Ban quản trị chuyển khoản rồi duyệt</b>.
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
          <TabsTrigger value="wallets">Ví</TabsTrigger>
        </TabsList>
        <TabsContent value="withdrawals" className="min-w-0">
          <WithdrawalsPanel summary={summary.data} />
        </TabsContent>
        <TabsContent value="wallets" className="min-w-0">
          <WalletsPanel initialSearch={initialSearch} />
        </TabsContent>
      </Tabs>
    </div>
  );
}
