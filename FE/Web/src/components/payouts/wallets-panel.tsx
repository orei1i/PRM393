// src/components/payouts/wallets-panel.tsx
"use client";

import * as React from "react";
import Link from "next/link";
import { Search, Wallet } from "lucide-react";

import { EmptyState, ErrorState } from "@/components/admin/states";
import { InitialsAvatar } from "@/components/admin/initials-avatar";
import { dateVi, formatVnd } from "@/components/orders/order-badges";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input, Skeleton } from "@/components/ui/form-controls";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useChefWallets } from "@/lib/hooks/use-payouts";
import { maskAccountNumber } from "@/lib/payouts_api";
import { cn, formatNumber, formatPercent } from "@/lib/utils";
import { ESCROW_HOLD_DAYS, PLATFORM_FEE_RATE } from "@/types/payouts";

const fold = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[Đđ]/g, "d").toLowerCase();

function Money({ value, strong, tone }: { value: number; strong?: boolean; tone?: "ochre" | "muted" }) {
  return (
    <span
      className={cn(
        "font-mono tabular",
        strong && "font-semibold",
        value === 0 ? "text-muted-foreground" : tone === "ochre" ? "text-ochre-text" : tone === "muted" && "text-muted-foreground",
      )}
    >
      {formatVnd(value)}
    </span>
  );
}

export function WalletsPanel() {
  const wallets = useChefWallets();
  const [searchInput, setSearchInput] = React.useState("");
  const search = React.useDeferredValue(searchInput);

  const rows = React.useMemo(() => {
    const q = fold(search.trim());
    return wallets.data?.filter((w) => !q || fold(`${w.chef.fullName} ${w.chef.email} ${w.bankAccount?.bankName ?? ""}`).includes(q));
  }, [wallets.data, search]);

  const missingBank = wallets.data?.filter((w) => !w.bankAccount).length ?? 0;

  return (
    <Card className="gap-0 py-0">
      <div className="flex flex-wrap items-center gap-3 border-b p-4">
        <div className="relative w-full sm:w-72">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
          <Input
            type="search"
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            placeholder="Tìm chuyên gia, ngân hàng…"
            aria-label="Tìm ví chuyên gia"
            className="pl-9"
          />
        </div>
        <p className="w-full text-sm text-muted-foreground" aria-live="polite">
          {wallets.data
            ? `${formatNumber(rows?.length ?? 0)} ví${missingBank ? ` · ${formatNumber(missingBank)} chuyên gia chưa thêm tài khoản ngân hàng` : ""}. ` +
              `Có thể rút = tiền đã giải ngân − phí ${formatPercent(PLATFORM_FEE_RATE)} − đã rút − đang xử lý rút. ` +
              `Đang giữ: chưa hết ${ESCROW_HOLD_DAYS} ngày sau khi kế hoạch kết thúc.`
            : "Đang tải…"}
        </p>
      </div>

      {wallets.isError && !wallets.data ? (
        <ErrorState error={wallets.error} onRetry={() => wallets.refetch()} title="Chưa tải được ví chuyên gia" />
      ) : rows?.length === 0 ? (
        <EmptyState
          icon={Wallet}
          title={search.trim() ? "Không có ví khớp từ khoá" : "Chưa có ví chuyên gia"}
          description={search.trim() ? "Thử tên chuyên gia hoặc ngân hàng khác." : "Ví được tạo khi chuyên gia có lượt đặt đầu tiên được thanh toán."}
          action={
            search.trim() ? (
              <Button variant="outline" onClick={() => setSearchInput("")}>
                Xoá từ khoá
              </Button>
            ) : undefined
          }
        />
      ) : (
        <Table className="min-w-[1160px]">
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              <TableHead>Chuyên gia</TableHead>
              <TableHead className="text-right">Có thể rút</TableHead>
              <TableHead className="text-right">Đang xử lý rút</TableHead>
              <TableHead className="text-right">Đang giữ</TableHead>
              <TableHead className="text-right">Tạm giữ do khiếu nại</TableHead>
              <TableHead className="text-right">Đã rút</TableHead>
              <TableHead className="text-right">Doanh thu · phí</TableHead>
              <TableHead>Tài khoản nhận</TableHead>
              <TableHead>Chi trả gần nhất</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {wallets.isLoading
              ? Array.from({ length: 5 }, (_, i) => (
                  <TableRow key={i}>
                    <TableCell colSpan={9}>
                      <Skeleton className="h-10" />
                    </TableCell>
                  </TableRow>
                ))
              : rows?.map((w) => (
                  <TableRow key={w.chefId}>
                    <TableCell>
                      <div className="flex items-center gap-2">
                        <InitialsAvatar name={w.chef.fullName} className="size-8" />
                        <span className="min-w-0">
                          <span className="block max-w-48 truncate font-semibold">{w.chef.fullName}</span>
                          <span className="block max-w-48 truncate text-xs text-muted-foreground">{w.chef.email}</span>
                        </span>
                      </div>
                    </TableCell>
                    <TableCell className="text-right">
                      <Money value={w.available} strong />
                    </TableCell>
                    <TableCell className="text-right">
                      <Money value={w.processing} tone="ochre" />
                    </TableCell>
                    <TableCell className="text-right">
                      <Money value={w.pending} />
                    </TableCell>
                    <TableCell className="text-right">
                      {w.frozen > 0 ? (
                        <Link
                          href="/disputes"
                          className="font-mono text-destructive tabular underline-offset-4 hover:underline focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
                        >
                          {formatVnd(w.frozen)}
                        </Link>
                      ) : (
                        <Money value={0} />
                      )}
                    </TableCell>
                    <TableCell className="text-right">
                      <Money value={w.withdrawn} />
                    </TableCell>
                    <TableCell className="text-right">
                      <span className="block font-mono tabular">{formatVnd(w.grossSales)}</span>
                      <span className="block font-mono text-xs text-muted-foreground tabular">phí {formatVnd(w.feeTotal)}</span>
                    </TableCell>
                    <TableCell>
                      {w.bankAccount ? (
                        <>
                          <span className="block font-semibold">{w.bankAccount.bankName}</span>
                          <span className="block font-mono text-xs text-muted-foreground">{maskAccountNumber(w.bankAccount.accountNumber)}</span>
                        </>
                      ) : (
                        <span className="text-ochre-text">Chưa thêm tài khoản</span>
                      )}
                    </TableCell>
                    <TableCell className="text-muted-foreground">
                      {w.lastWithdrawalAt ? dateVi.format(new Date(w.lastWithdrawalAt)) : "—"}
                    </TableCell>
                  </TableRow>
                ))}
          </TableBody>
        </Table>
      )}
    </Card>
  );
}
