// src/components/payouts/withdrawals-panel.tsx
"use client";

import * as React from "react";
import { HandCoins, Search } from "lucide-react";

import { EmptyState, ErrorState } from "@/components/admin/states";
import { formatVnd } from "@/components/orders/order-badges";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/form-controls";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useWithdrawals } from "@/lib/hooks/use-payouts";
import { formatNumber } from "@/lib/utils";
import { WITHDRAWAL_STATUS_LABEL, WITHDRAWAL_STATUSES, type PayoutSummary, type WithdrawalRequest, type WithdrawalStatus } from "@/types/payouts";

import { WithdrawalDrawer } from "./withdrawal-drawer";
import { WithdrawalTable } from "./withdrawal-table";

const EMPTY: Record<WithdrawalStatus, { title: string; description: string }> = {
  Processing: {
    title: "Không còn yêu cầu đang xử lý",
    description: "Yêu cầu rút tiền chuyên gia gửi từ ứng dụng sẽ xuất hiện ở đây.",
  },
  Completed: { title: "Chưa có lệnh chuyển nào", description: "Yêu cầu đã chi trả (tự động hoặc do Ban quản trị xác nhận) nằm ở đây." },
  Rejected: { title: "Chưa có yêu cầu bị từ chối", description: "Yêu cầu bị từ chối kèm lý do gửi cho chuyên gia nằm ở đây." },
};

export function WithdrawalsPanel({ summary }: { summary: PayoutSummary | undefined }) {
  const [status, setStatus] = React.useState<WithdrawalStatus>("Processing");
  const [searchInput, setSearchInput] = React.useState("");
  const search = React.useDeferredValue(searchInput);
  const [selected, setSelected] = React.useState<WithdrawalRequest | null>(null);

  const query = React.useMemo(() => ({ status, search }), [status, search]);
  const withdrawals = useWithdrawals(query);

  // Keep the drawer in sync with refetched / optimistically patched rows.
  const selectedId = selected?.id ?? null;
  React.useEffect(() => {
    if (!selectedId || !withdrawals.data) return;
    const fresh = withdrawals.data.find((w) => w.id === selectedId);
    if (fresh) setSelected((current) => (current && current !== fresh ? fresh : current));
  }, [withdrawals.data, selectedId]);

  const filtered = search.trim().length > 0;
  const total = withdrawals.data?.reduce((s, w) => s + w.amount, 0) ?? 0;
  const awaiting = withdrawals.data?.filter((w) => w.status === "Processing" && w.requiresApproval).length ?? 0;

  return (
    <Card className="gap-0 py-0">
      <div className="flex flex-wrap items-center gap-3 border-b p-4">
        <Tabs value={status} onValueChange={(v) => setStatus(v as WithdrawalStatus)} className="w-full min-w-0 max-w-full lg:w-auto">
          <TabsList className="max-w-full justify-start overflow-x-auto" aria-label="Lọc theo trạng thái yêu cầu">
            {WITHDRAWAL_STATUSES.map((s) => (
              <TabsTrigger key={s} value={s}>
                {WITHDRAWAL_STATUS_LABEL[s]}
                <span className="rounded-full bg-muted px-1.5 font-mono text-[11px] tabular">
                  {summary ? formatNumber(summary.byStatus[s]) : "–"}
                </span>
              </TabsTrigger>
            ))}
          </TabsList>
        </Tabs>
        <div className="relative w-full sm:w-80 lg:ml-auto">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
          <Input
            type="search"
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            placeholder="Chuyên gia, ngân hàng, mã GD…"
            title="Tìm theo chuyên gia, ngân hàng hoặc mã giao dịch"
            aria-label="Tìm yêu cầu rút tiền"
            className="pl-9"
          />
        </div>
        <p className="w-full text-sm text-muted-foreground" aria-live="polite">
          {withdrawals.data
            ? `${formatNumber(withdrawals.data.length)} yêu cầu · ${formatVnd(total)}${
                status === "Processing" && awaiting ? ` · ${formatNumber(awaiting)} cần Ban quản trị duyệt` : ""
              }`
            : "Đang tải…"}
        </p>
      </div>

      {withdrawals.isError && !withdrawals.data ? (
        <ErrorState error={withdrawals.error} onRetry={() => withdrawals.refetch()} title="Chưa tải được yêu cầu rút tiền" />
      ) : withdrawals.data?.length === 0 ? (
        <EmptyState
          icon={HandCoins}
          title={filtered ? "Không có yêu cầu khớp từ khoá" : EMPTY[status].title}
          description={filtered ? "Thử tên chuyên gia, ngân hàng hoặc mã giao dịch khác." : EMPTY[status].description}
          action={
            filtered ? (
              <Button variant="outline" onClick={() => setSearchInput("")}>
                Xoá từ khoá
              </Button>
            ) : undefined
          }
        />
      ) : (
        // Dim only while a new tab / search loads, not on the 30 s background poll.
        <div className={withdrawals.isPlaceholderData ? "opacity-60 transition-opacity" : undefined}>
          <WithdrawalTable
            status={status}
            withdrawals={withdrawals.data}
            isLoading={withdrawals.isLoading}
            selectedId={selectedId}
            onSelect={setSelected}
          />
        </div>
      )}

      <WithdrawalDrawer withdrawal={selected} onOpenChange={(open) => !open && setSelected(null)} onWithdrawalChange={setSelected} />
    </Card>
  );
}
