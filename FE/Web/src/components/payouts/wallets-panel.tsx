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
import { Input, NativeSelect, Skeleton } from "@/components/ui/form-controls";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useWallets } from "@/lib/hooks/use-payouts";
import { maskAccountNumber } from "@/lib/payouts_api";
import { cn, formatNumber, formatPercent } from "@/lib/utils";
import { ESCROW_HOLD_DAYS, PLATFORM_FEE_RATE, WALLET_ROLE_LABEL, WALLET_ROLES, type WalletRoleFilter } from "@/types/payouts";

import { WalletRoleBadge } from "./payout-badges";

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

export function WalletsPanel({ initialSearch = "" }: { initialSearch?: string }) {
  const wallets = useWallets();
  const [searchInput, setSearchInput] = React.useState(initialSearch);
  const search = React.useDeferredValue(searchInput);
  const [role, setRole] = React.useState<WalletRoleFilter>("all");

  const rows = React.useMemo(() => {
    const q = fold(search.trim());
    return wallets.data
      ?.filter((w) => role === "all" || w.role === role)
      .filter((w) => !q || fold(`${w.user.fullName} ${w.user.email} ${w.bankAccount?.bankName ?? ""}`).includes(q));
  }, [wallets.data, search, role]);

  const missingBank = rows?.filter((w) => !w.bankAccount).length ?? 0;
  const filtered = search.trim().length > 0 || role !== "all";

  return (
    <Card className="gap-0 py-0">
      <div className="flex flex-wrap items-center gap-3 border-b p-4">
        <div className="relative w-full sm:w-72">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
          <Input
            type="search"
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            placeholder="Tìm tên, ngân hàng…"
            aria-label="Tìm ví"
            className="pl-9"
          />
        </div>
        <NativeSelect aria-label="Lọc ví theo vai trò" value={role} onChange={(e) => setRole(e.target.value as WalletRoleFilter)} className="w-full sm:w-44">
          <option value="all">Mọi vai trò</option>
          {WALLET_ROLES.map((r) => (
            <option key={r} value={r}>
              {WALLET_ROLE_LABEL[r]}
            </option>
          ))}
        </NativeSelect>
        <p className="w-full text-sm text-muted-foreground" aria-live="polite">
          {wallets.data
            ? `${formatNumber(rows?.length ?? 0)} ví${missingBank ? ` · ${formatNumber(missingBank)} chưa thêm tài khoản ngân hàng` : ""}. ` +
              `Chuyên gia: có thể rút = tiền đã giải ngân − phí ${formatPercent(PLATFORM_FEE_RATE)} − đã rút − chờ duyệt rút; đang giữ = VeganLife giữ đến ${ESCROW_HOLD_DAYS} ngày sau khi hoàn thành. ` +
              `Thành viên: có thể rút = tiền được hoàn − đã trả bằng ví − đã rút − chờ duyệt rút.`
            : wallets.isError ? "" : "Đang tải…"}
        </p>
      </div>

      {wallets.isError && !wallets.data ? (
        <ErrorState error={wallets.error} onRetry={() => wallets.refetch()} title="Chưa tải được ví" />
      ) : rows?.length === 0 ? (
        <EmptyState
          icon={Wallet}
          title={filtered ? "Không có ví khớp bộ lọc" : "Chưa có ví nào"}
          description={filtered ? "Thử vai trò, tên hoặc ngân hàng khác." : "Ví được tạo khi chuyên gia có lượt đặt được thanh toán, hoặc khi thành viên được hoàn tiền."}
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
        <Table className="min-w-[1160px]">
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              <TableHead>Chủ ví</TableHead>
              <TableHead className="text-right">Có thể rút</TableHead>
              <TableHead className="text-right">Chờ duyệt rút</TableHead>
              <TableHead className="text-right">Đang giữ</TableHead>
              <TableHead className="text-right">Tạm giữ do khiếu nại</TableHead>
              <TableHead className="text-right">Đã rút</TableHead>
              <TableHead className="text-right">Nguồn tiền</TableHead>
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
                  <TableRow key={`${w.role}_${w.userId}`}>
                    <TableCell>
                      <div className="flex items-center gap-2">
                        <InitialsAvatar name={w.user.fullName} className="size-8" />
                        <span className="min-w-0">
                          <span className="block max-w-48 truncate font-semibold">{w.user.fullName}</span>
                          <span className="block max-w-48 truncate text-xs text-muted-foreground">{w.user.email}</span>
                          <span className="mt-1 block">
                            <WalletRoleBadge role={w.role} />
                          </span>
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
                      {w.role === "chef" ? (
                        <>
                          <span className="block font-mono tabular">{formatVnd(w.grossSales)}</span>
                          <span className="block font-mono text-xs text-muted-foreground tabular">phí {formatVnd(w.feeTotal)}</span>
                          {w.refundTotal > 0 && <span className="block font-mono text-xs text-muted-foreground tabular">được hoàn {formatVnd(w.refundTotal)}</span>}
                          {w.walletPaymentTotal > 0 && <span className="block font-mono text-xs text-muted-foreground tabular">đã trả bằng ví {formatVnd(w.walletPaymentTotal)}</span>}
                        </>
                      ) : (
                        <>
                          <span className="block font-mono tabular">{formatVnd(w.refundTotal)}</span>
                          <span className="block text-xs text-muted-foreground">tiền được hoàn</span>
                          {w.walletPaymentTotal > 0 && <span className="block font-mono text-xs text-muted-foreground tabular">đã trả bằng ví {formatVnd(w.walletPaymentTotal)}</span>}
                        </>
                      )}
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
