// src/components/payouts/payout-badges.tsx
// Status / role badges and the masked bank account number shared by the
// withdrawal table, drawer and wallets tab.
"use client";

import * as React from "react";
import { Ban, ChefHat, CircleCheck, Eye, EyeOff, Hourglass, Lock, RotateCcw, Snowflake, UserRound, Wallet } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { formatVnd } from "@/components/orders/order-badges";
import { maskAccountNumber } from "@/lib/payouts_api";
import { cn } from "@/lib/utils";
import {
  LEDGER_STATUS_LABEL,
  WALLET_ROLE_LABEL,
  WITHDRAWAL_STATUS_LABEL,
  type LedgerStatus,
  type WalletRole,
  type WithdrawalStatus,
} from "@/types/payouts";

export function WithdrawalStatusBadge({ status }: { status: WithdrawalStatus }) {
  switch (status) {
    case "Processing":
      return (
        <Badge variant="ochre">
          <Hourglass aria-hidden />
          {WITHDRAWAL_STATUS_LABEL[status]}
        </Badge>
      );
    case "Completed":
      return (
        <Badge variant="sprout">
          <CircleCheck aria-hidden />
          {WITHDRAWAL_STATUS_LABEL[status]}
        </Badge>
      );
    case "Rejected":
      return (
        <Badge variant="outline" className="border-destructive/40 text-destructive">
          <Ban aria-hidden />
          {WITHDRAWAL_STATUS_LABEL[status]}
        </Badge>
      );
  }
}

/** Whose wallet: "Chuyên gia" (earnings) or "Thành viên" (refunds). */
export function WalletRoleBadge({ role }: { role: WalletRole }) {
  const Icon = role === "chef" ? ChefHat : UserRound;
  return (
    <Badge variant={role === "chef" ? "ai" : "outline"}>
      <Icon aria-hidden />
      {WALLET_ROLE_LABEL[role]}
    </Badge>
  );
}

export function LedgerStatusBadge({ status, label }: { status: LedgerStatus; label?: string }) {
  if (status === "Frozen") {
    return (
      <Badge variant="outline" className="border-destructive/40 text-destructive">
        <Snowflake aria-hidden />
        {LEDGER_STATUS_LABEL[status]}
      </Badge>
    );
  }
  const variant =
    status === "Available" || status === "Completed"
      ? "sprout"
      : status === "Held" || status === "Processing"
        ? "ochre"
        : status === "Reversed"
          ? "ai"
          : "secondary";
  const Icon =
    status === "Available"
      ? Wallet
      : status === "Completed"
        ? CircleCheck
        : status === "Reversed"
          ? RotateCcw
          : status === "Rejected"
            ? Ban
            : status === "Held"
              ? Lock
              : Hourglass;
  return (
    <Badge variant={variant}>
      <Icon aria-hidden />
      {label ?? LEDGER_STATUS_LABEL[status]}
    </Badge>
  );
}

/** "0071000456789" → "0071 0004 5678 9" */
const groupDigits = (number: string) => number.replace(/(.{4})(?=.)/g, "$1 ");

/** Masked by default ("•••• 6789"); the eye button reveals the full number for the transfer. */
export function BankAccountNumber({ number, className }: { number: string; className?: string }) {
  const [revealed, setRevealed] = React.useState(false);
  if (!number) return <span className="text-muted-foreground">—</span>;
  return (
    <span className={cn("inline-flex items-center gap-1", className)}>
      <span className="font-mono font-semibold tabular break-all">{revealed ? groupDigits(number) : maskAccountNumber(number)}</span>
      <Button
        type="button"
        size="icon"
        variant="ghost"
        className="size-7"
        aria-pressed={revealed}
        aria-label={revealed ? "Ẩn số tài khoản" : "Hiện số tài khoản"}
        title={revealed ? "Ẩn số tài khoản" : "Hiện số tài khoản"}
        onClick={() => setRevealed((v) => !v)}
      >
        {revealed ? <EyeOff aria-hidden /> : <Eye aria-hidden />}
      </Button>
    </span>
  );
}

/** Signed VND for ledger lines: "+315.000 ₫" / "−1.000.000 ₫". */
export function formatSignedVnd(amount: number) {
  if (amount === 0) return formatVnd(0);
  return `${amount > 0 ? "+" : "−"}${formatVnd(Math.abs(amount))}`;
}
