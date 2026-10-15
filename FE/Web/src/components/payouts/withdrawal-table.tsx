// src/components/payouts/withdrawal-table.tsx
"use client";

import { InitialsAvatar } from "@/components/admin/initials-avatar";
import { dateTimeVi, formatDateTime, formatVnd } from "@/components/orders/order-badges";
import { Skeleton } from "@/components/ui/form-controls";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { maskAccountNumber } from "@/lib/payouts_api";
import { formatAge } from "@/lib/utils";
import type { WithdrawalRequest, WithdrawalStatus } from "@/types/payouts";

import { ApprovalRuleBadge, WithdrawalStatusBadge } from "./payout-badges";

const LAST_COLUMN: Record<WithdrawalStatus, string> = {
  Processing: "Tình trạng",
  Completed: "Mã giao dịch",
  Rejected: "Lý do từ chối",
};

function LastCell({ w }: { w: WithdrawalRequest }) {
  if (w.status === "Processing") {
    return w.requiresApproval ? (
      <span className="text-sm">
        <span className="font-semibold text-ochre-text">Chờ duyệt</span>
        <span className="block text-xs text-muted-foreground">đã chờ {formatAge(w.createdAt)}</span>
      </span>
    ) : (
      <span className="text-sm">
        <span className="font-semibold">Tự động chuyển</span>
        <span className="block text-xs text-muted-foreground">{w.autoApproveAt ? `lúc ${formatDateTime(w.autoApproveAt)}` : "sắp chuyển"}</span>
      </span>
    );
  }
  if (w.status === "Completed") {
    return (
      <span className="text-sm">
        <span className="font-mono text-xs font-semibold">{w.transactionRef ?? "—"}</span>
        <span className="block text-xs text-muted-foreground">
          {w.processedAt ? formatDateTime(w.processedAt) : ""} · {w.processedBy ?? "Tự động"}
        </span>
      </span>
    );
  }
  return <span className="line-clamp-2 text-sm text-muted-foreground">{w.reason ?? "—"}</span>;
}

export function WithdrawalTable({
  status,
  withdrawals,
  isLoading,
  selectedId,
  onSelect,
}: {
  status: WithdrawalStatus;
  withdrawals: WithdrawalRequest[] | undefined;
  isLoading: boolean;
  selectedId: string | null;
  onSelect: (withdrawal: WithdrawalRequest) => void;
}) {
  return (
    <Table className="min-w-[960px]">
      <TableHeader>
        <TableRow className="hover:bg-transparent">
          <TableHead>Chuyên gia</TableHead>
          <TableHead className="text-right">Số tiền</TableHead>
          <TableHead>Duyệt</TableHead>
          <TableHead>Tài khoản nhận</TableHead>
          <TableHead>Gửi lúc</TableHead>
          <TableHead>Trạng thái</TableHead>
          <TableHead className="w-[24%]">{LAST_COLUMN[status]}</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {isLoading
          ? Array.from({ length: 5 }, (_, i) => (
              <TableRow key={i}>
                <TableCell colSpan={7}>
                  <Skeleton className="h-10" />
                </TableCell>
              </TableRow>
            ))
          : withdrawals?.map((w) => (
              <TableRow
                key={w.id}
                data-state={w.id === selectedId ? "selected" : undefined}
                tabIndex={0}
                onClick={() => onSelect(w)}
                onKeyDown={(e) => {
                  if (e.target === e.currentTarget && (e.key === "Enter" || e.key === " ")) {
                    e.preventDefault();
                    onSelect(w);
                  }
                }}
                className="cursor-pointer"
                aria-label={`Mở yêu cầu rút ${formatVnd(w.amount)} của ${w.chef.fullName}`}
              >
                <TableCell>
                  <div className="flex items-center gap-2">
                    <InitialsAvatar name={w.chef.fullName} className="size-8" />
                    <span className="min-w-0">
                      <span className="block max-w-48 truncate font-semibold">{w.chef.fullName}</span>
                      <span className="block font-mono text-xs text-muted-foreground">{w.id}</span>
                    </span>
                  </div>
                </TableCell>
                <TableCell className="text-right font-mono font-semibold tabular">{formatVnd(w.amount)}</TableCell>
                <TableCell>
                  <ApprovalRuleBadge requiresApproval={w.requiresApproval} />
                </TableCell>
                <TableCell>
                  <span className="block font-semibold">{w.bankAccount.bankName || "—"}</span>
                  <span className="block font-mono text-xs text-muted-foreground">{maskAccountNumber(w.bankAccount.accountNumber)}</span>
                </TableCell>
                <TableCell className="text-muted-foreground">{dateTimeVi.format(new Date(w.createdAt))}</TableCell>
                <TableCell>
                  <WithdrawalStatusBadge status={w.status} />
                </TableCell>
                <TableCell className="whitespace-normal">
                  <LastCell w={w} />
                </TableCell>
              </TableRow>
            ))}
      </TableBody>
    </Table>
  );
}
