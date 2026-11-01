// src/components/payouts/withdrawals-panel.tsx
"use client";

import * as React from "react";
import { HandCoins, Search } from "lucide-react";

import { EmptyState, ErrorState } from "@/components/admin/states";
import { formatVnd } from "@/components/orders/order-badges";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input, NativeSelect } from "@/components/ui/form-controls";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useWithdrawals } from "@/lib/hooks/use-payouts";
import { formatNumber } from "@/lib/utils";
import {
  WALLET_ROLE_LABEL,
  WALLET_ROLES,
  WITHDRAWAL_STATUS_LABEL,
  WITHDRAWAL_STATUSES,
  type PayoutSummary,
  type WalletRoleFilter,
  type WithdrawalRequest,
  type WithdrawalStatus,
} from "@/types/payouts";

import { WithdrawalDrawer } from "./withdrawal-drawer";
import { WithdrawalTable } from "./withdrawal-table";

const EMPTY: Record<WithdrawalStatus, { title: string; description: string }> = {
  Processing: {
    title: "Không còn yêu cầu chờ duyệt",
    description: "Yêu cầu rút tiền chuyên gia và thành viên gửi từ ứng dụng sẽ xuất hiện ở đây.",
  },
  Completed: { title: "Chưa có lệnh chuyển nào", description: "Yêu cầu Ban quản trị đã duyệt và chuyển khoản nằm ở đây." },
  Rejected: { title: "Chưa có yêu cầu bị từ chối", description: "Yêu cầu bị từ chối kèm lý do gửi cho người yêu cầu nằm ở đây." },
};

export function WithdrawalsPanel({ summary }: { summary: PayoutSummary | undefined }) {
  const [status, setStatus] = React.useState<WithdrawalStatus>("Processing");
  const [role, setRole] = React.useState<WalletRoleFilter>("all");
  const [searchInput, setSearchInput] = React.useState("");
  const search = React.useDeferredValue(searchInput);
  const [selected, setSelected] = React.useState<WithdrawalRequest | null>(null);

  const query = React.useMemo(() => ({ status, role, search }), [status, role, search]);
  const withdrawals = useWithdrawals(query);

  // Keep the drawer in sync with refetched / optimistically patched rows.
  const selectedId = selected?.id ?? null;
  React.useEffect(() => {
    if (!selectedId || !withdrawals.data) return;
    const fresh = withdrawals.data.find((w) => w.id === selectedId);
    if (fresh) setSelected((current) => (current && current !== fresh ? fresh : current));
  }, [withdrawals.data, selectedId]);

  const filtered = search.trim().length > 0 || role !== "all";
  const total = withdrawals.data?.reduce((s, w) => s + w.amount, 0) ?? 0;
  const tabCount = (s: WithdrawalStatus) => (role === "all" ? summary?.byStatus[s] : summary?.byRole[role][s]);
  const countOf = (s: WithdrawalStatus) => {
    const n = tabCount(s);
    return n === undefined ? "–" : formatNumber(n);
  };

  return (
    <Card className="gap-0 py-0">
      <div className="flex flex-wrap items-center gap-3 border-b p-4">
        <Tabs value={status} onValueChange={(v) => setStatus(v as WithdrawalStatus)} className="w-full min-w-0 max-w-full lg:w-auto">
          <TabsList className="max-w-full justify-start overflow-x-auto" aria-label="Lọc theo trạng thái yêu cầu">
            {WITHDRAWAL_STATUSES.map((s) => (
              <TabsTrigger key={s} value={s}>
                {WITHDRAWAL_STATUS_LABEL[s]}
                <span className="rounded-full bg-muted px-1.5 font-mono text-[11px] tabular">{countOf(s)}</span>
              </TabsTrigger>
            ))}
          </TabsList>
        </Tabs>
        <NativeSelect
          aria-label="Lọc theo vai trò"
          value={role}
          onChange={(e) => setRole(e.target.value as WalletRoleFilter)}
          className="w-full sm:w-44 lg:ml-auto"
        >
          <option value="all">Mọi vai trò</option>
          {WALLET_ROLES.map((r) => (
            <option key={r} value={r}>
              {WALLET_ROLE_LABEL[r]}
            </option>
          ))}
        </NativeSelect>
        <div className="relative w-full sm:w-72">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
          <Input
            type="search"
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            placeholder="Tên, ngân hàng, mã GD…"
            title="Tìm theo tên người yêu cầu, ngân hàng hoặc mã giao dịch"
            aria-label="Tìm yêu cầu rút tiền"
            className="pl-9"
          />
        </div>
        <p className="w-full text-sm text-muted-foreground" aria-live="polite">
          {withdrawals.data
            ? `${formatNumber(withdrawals.data.length)} yêu cầu · ${formatVnd(total)}`
            : withdrawals.isError ? "" : "Đang tải…"}
        </p>
      </div>

      {withdrawals.isError && !withdrawals.data ? (
        <ErrorState error={withdrawals.error} onRetry={() => withdrawals.refetch()} title="Chưa tải được yêu cầu rút tiền" />
      ) : withdrawals.data?.length === 0 ? (
        <EmptyState
          icon={HandCoins}
          title={filtered ? "Không có yêu cầu khớp bộ lọc" : EMPTY[status].title}
          description={filtered ? "Thử vai trò, tên, ngân hàng hoặc mã giao dịch khác." : EMPTY[status].description}
          action={
            filtered ? (
              <Button
                variant="outline"
                onClick={() => {
                  setSearchInput("");
                  setRole("all");
                }}
              >
                Xoá bộ lọc
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
