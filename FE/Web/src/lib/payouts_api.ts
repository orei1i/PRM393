// src/lib/payouts_api.ts
// Chef wallets, withdrawal requests and payout KPIs for /payouts.
// Remote responses are normalised: INT ids → strings, enum values matched
// case-insensitively, bank account either nested or flat (bankName / accountNumber / accountHolder).
//
// | Method | Path                                              | Body / notes                                      |
// |--------|---------------------------------------------------|---------------------------------------------------|
// | GET    | /admin/payouts/summary                            | PayoutSummary                                     |
// | GET    | /admin/withdrawals?status=&search=                | WithdrawalRequest[] (status: Processing, Completed, Rejected) |
// | POST   | /admin/withdrawals/{id}/complete                  | { transactionRef } → WithdrawalRequest; 409 unless Processing |
// | POST   | /admin/withdrawals/{id}/reject                    | { reason } (≥ 10 chars) → WithdrawalRequest; 409 unless Processing |
// | GET    | /admin/chef-wallets                               | ChefWallet[]                                      |
// | GET    | /admin/chef-wallets/{chefId}/transactions?limit=  | WalletTransaction[], newest first (drawer ledger) |
//
// Rules (mirrored from the mobile wallet): booking money is held in escrow until the plan's end
// date + 3 days (ESCROW_HOLD_DAYS), frozen while a complaint is open, then released at net 90%
// (fee 10%); requests ≤ 5.000.000đ are paid out automatically, bigger ones wait for an admin.
// All of it needs new tables (see types/payouts.ts and types/bookings.ts).
import type {
  BankAccount,
  ChefWallet,
  LedgerEntryType,
  LedgerStatus,
  PayoutChef,
  PayoutSummary,
  WalletTransaction,
  WithdrawalActionInput,
  WithdrawalQuery,
  WithdrawalRequest,
  WithdrawalStatus,
} from "@/types/payouts";
import { AUTO_APPROVE_LIMIT, LEDGER_ENTRY_TYPES, LEDGER_STATUSES, PLATFORM_FEE_RATE, WITHDRAWAL_STATUSES } from "@/types/payouts";

import { qs, request, USE_MOCK_DATA } from "./api_client";
import { readSession } from "./auth";
import { readId } from "./ids";
import * as mock from "./mock_payouts";

type Raw = Record<string, unknown>;
const obj = (raw: unknown): Raw | null => (raw && typeof raw === "object" && !Array.isArray(raw) ? (raw as Raw) : null);

/** Case-insensitive, ignores spaces and underscores; unknown → fallback. */
function pick<T extends string>(values: readonly T[], raw: unknown, fallback: T): T {
  if (typeof raw !== "string") return fallback;
  const key = (s: string) => s.replace(/[\s_]/g, "").toLowerCase();
  return values.find((v) => key(v) === key(raw)) ?? fallback;
}

const num = (raw: unknown, fallback = 0) => {
  const n = typeof raw === "number" ? raw : typeof raw === "string" ? Number(raw) : NaN;
  return Number.isFinite(n) ? n : fallback;
};

const optNum = (raw: unknown) => (raw === null || raw === undefined || raw === "" ? null : num(raw));
const optString = (raw: unknown) => (typeof raw === "string" && raw ? raw : null);

/** "0071000456789" → "•••• 6789" */
export const maskAccountNumber = (number: string) => (number.length <= 4 ? number : `•••• ${number.slice(-4)}`);

function readChef(raw: unknown, fallbackId: unknown): PayoutChef {
  const c = obj(raw) ?? {};
  return {
    id: readId(c.id ?? fallbackId),
    fullName: String(c.fullName ?? c.name ?? "Chuyên gia"),
    email: String(c.email ?? ""),
  };
}

function readBankAccount(raw: Raw): BankAccount | null {
  const source = obj(raw.bankAccount) ?? raw;
  const number = source.accountNumber;
  if (number === undefined || number === null || number === "") return null;
  return {
    bankName: String(source.bankName ?? ""),
    accountNumber: String(number),
    accountHolder: String(source.accountHolder ?? ""),
  };
}

export function normalizeWithdrawal(raw: Raw): WithdrawalRequest {
  const amount = num(raw.amount);
  return {
    id: readId(raw.id),
    chefId: readId(raw.chefId ?? obj(raw.chef)?.id),
    chef: readChef(raw.chef, raw.chefId),
    amount,
    status: pick<WithdrawalStatus>(WITHDRAWAL_STATUSES, raw.status, "Processing"),
    bankAccount: readBankAccount(raw) ?? { bankName: "", accountNumber: "", accountHolder: "" },
    createdAt: optString(raw.createdAt) ?? new Date(0).toISOString(),
    requiresApproval: typeof raw.requiresApproval === "boolean" ? raw.requiresApproval : amount > AUTO_APPROVE_LIMIT,
    autoApproveAt: optString(raw.autoApproveAt),
    processedAt: optString(raw.processedAt),
    processedBy: optString(raw.processedBy) ?? optString(obj(raw.processedBy)?.fullName),
    transactionRef: optString(raw.transactionRef),
    reason: optString(raw.reason),
  };
}

export function normalizeWallet(raw: Raw): ChefWallet {
  return {
    chefId: readId(raw.chefId ?? obj(raw.chef)?.id),
    chef: readChef(raw.chef, raw.chefId),
    available: num(raw.available),
    pending: num(raw.pending ?? raw.held),
    frozen: num(raw.frozen),
    processing: num(raw.processing),
    withdrawn: num(raw.withdrawn),
    grossSales: num(raw.grossSales),
    feeTotal: num(raw.feeTotal),
    bankAccount: readBankAccount(raw),
    lastWithdrawalAt: optString(raw.lastWithdrawalAt),
  };
}

/** Legacy "Pending" (before escrow) reads as "Held". */
const readLedgerStatus = (raw: unknown) =>
  typeof raw === "string" && raw.toLowerCase() === "pending" ? "Held" : pick<LedgerStatus>(LEDGER_STATUSES, raw, "Held");

const optId = (raw: unknown) => (raw === undefined || raw === null || raw === "" ? null : readId(raw));

export function normalizeTransaction(raw: Raw): WalletTransaction {
  return {
    id: readId(raw.id),
    type: pick<LedgerEntryType>(LEDGER_ENTRY_TYPES, raw.type, "Income"),
    status: readLedgerStatus(raw.status),
    createdAt: optString(raw.createdAt) ?? new Date(0).toISOString(),
    net: num(raw.net),
    bookingId: optId(raw.bookingId),
    orderId: optId(raw.orderId),
    transactionRef: optString(raw.transactionRef),
    planTitle: optString(raw.planTitle) ?? optString(raw.serviceTitle),
    memberName: optString(raw.memberName) ?? optString(raw.buyerName),
    gross: optNum(raw.gross),
    fee: optNum(raw.fee),
    releaseAt: optString(raw.releaseAt),
    complaintId: optId(raw.complaintId),
    bankName: optString(raw.bankName),
    note: optString(raw.note),
  };
}

export const payoutsApi = {
  /** GET /admin/payouts/summary */
  async summary(): Promise<PayoutSummary> {
    if (USE_MOCK_DATA) return mock.getPayoutSummary();
    const raw = await request<Raw>("/admin/payouts/summary");
    const byStatus = obj(raw.byStatus) ?? {};
    return {
      totalAvailable: num(raw.totalAvailable),
      totalPending: num(raw.totalPending ?? raw.totalHeld),
      totalFrozen: num(raw.totalFrozen),
      totalProcessing: num(raw.totalProcessing),
      paidOutThisMonth: num(raw.paidOutThisMonth),
      paidOutThisMonthCount: num(raw.paidOutThisMonthCount),
      platformFee: num(raw.platformFee),
      releasedGross: num(raw.releasedGross ?? raw.paidGross),
      releasedCount: num(raw.releasedCount ?? raw.paidOrderCount),
      feeRate: num(raw.feeRate, PLATFORM_FEE_RATE),
      autoApproveLimit: num(raw.autoApproveLimit, AUTO_APPROVE_LIMIT),
      byStatus: Object.fromEntries(WITHDRAWAL_STATUSES.map((s) => [s, num(byStatus[s])])) as Record<WithdrawalStatus, number>,
      awaitingApproval: num(raw.awaitingApproval),
      awaitingApprovalAmount: num(raw.awaitingApprovalAmount),
    };
  },

  /** GET /admin/withdrawals?status=&search= */
  async listWithdrawals(query: WithdrawalQuery): Promise<WithdrawalRequest[]> {
    if (USE_MOCK_DATA) return mock.listWithdrawals(query);
    const raw = await request<Raw[]>(`/admin/withdrawals?${qs({ status: query.status, search: query.search })}`);
    return raw.map(normalizeWithdrawal);
  },

  /** POST /admin/withdrawals/{id}/complete { transactionRef } | /reject { reason } */
  async act(input: WithdrawalActionInput): Promise<WithdrawalRequest> {
    if (USE_MOCK_DATA) return mock.applyWithdrawalAction(input, readSession());
    const body = input.action === "complete" ? { transactionRef: input.transactionRef } : { reason: input.reason };
    return normalizeWithdrawal(
      await request<Raw>(`/admin/withdrawals/${encodeURIComponent(input.withdrawalId)}/${input.action}`, {
        method: "POST",
        body: JSON.stringify(body),
      }),
    );
  },

  /** GET /admin/chef-wallets */
  async wallets(): Promise<ChefWallet[]> {
    if (USE_MOCK_DATA) return mock.listChefWallets();
    const raw = await request<Raw[]>("/admin/chef-wallets");
    return raw.map(normalizeWallet);
  },

  /** GET /admin/chef-wallets/{chefId}/transactions?limit= — newest first. */
  async transactions(chefId: string, limit = 8): Promise<WalletTransaction[]> {
    if (USE_MOCK_DATA) return mock.listWalletTransactions(chefId, limit);
    const raw = await request<Raw[]>(`/admin/chef-wallets/${encodeURIComponent(chefId)}/transactions?${qs({ limit })}`);
    return raw.map(normalizeTransaction).sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  },
};
