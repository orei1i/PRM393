// src/lib/payouts_api.ts
// Wallets (chefs and members), withdrawal requests and payout KPIs for /payouts.
// Remote responses are normalised: INT ids → strings, enum values matched
// case-insensitively, bank account either nested or flat (bankName / accountNumber / accountHolder),
// `chefId` / `chef` (the older chef-only shape) read as a chef's `userId` / `user`.
//
// | Method | Path                                         | Body / notes                                      |
// |--------|----------------------------------------------|---------------------------------------------------|
// | GET    | /admin/payouts/summary                       | PayoutSummary                                     |
// | GET    | /admin/withdrawals?status=&role=&search=     | WithdrawalRequest[] (status: Processing, Completed, Rejected; role: member, chef) |
// | POST   | /admin/withdrawals/{id}/complete             | { transactionRef } → WithdrawalRequest; 409 unless Processing |
// | POST   | /admin/withdrawals/{id}/reject               | { reason } (≥ 10 chars) → WithdrawalRequest; 409 unless Processing |
// | GET    | /admin/wallets                               | UserWallet[]: every chef and every member with a refund or a request |
// | GET    | /admin/wallets/{userId}/transactions?limit=  | WalletTransaction[], newest first (drawer ledger) |
//
// Rules: booking money is held by the platform until 7 days (ESCROW_HOLD_DAYS) after the chef
// confirms completion, frozen while a complaint is open, then released to the chef's wallet at net
// 90% (fee 10%); a refund goes to the member's wallet, which can also pay a booking in full (a negative
// `Payment` ledger row); every withdrawal waits for an admin.
// All of it needs new tables (see types/payouts.ts and types/bookings.ts).
import type {
  BankAccount,
  LedgerEntryType,
  LedgerStatus,
  PayoutSummary,
  UserWallet,
  WalletOwner,
  WalletRole,
  WalletTransaction,
  WithdrawalActionInput,
  WithdrawalQuery,
  WithdrawalRequest,
  WithdrawalStatus,
} from "@/types/payouts";
import { LEDGER_ENTRY_TYPES, LEDGER_STATUSES, PLATFORM_FEE_RATE, WALLET_ROLES, WITHDRAWAL_STATUSES } from "@/types/payouts";

import { qs, requestList, requestObject } from "./api_client";
import { isMock } from "./backend_modules";
import { readSession } from "./auth";
import { readId } from "./ids";
import * as mock from "./mock_payouts";
import { counts as countsOf, hasId, isoOr, num, obj, optIso, optNum, optText, pick, text, type Raw } from "./wire";

const optString = optText;

/** "0071000456789" → "•••• 6789" */
export const maskAccountNumber = (number: string) => (number.length <= 4 ? number : `•••• ${number.slice(-4)}`);

function readOwner(raw: unknown, fallbackId: unknown, role: WalletRole): WalletOwner {
  const c = obj(raw) ?? {};
  return {
    id: readId(c.id ?? fallbackId),
    fullName: text(c.fullName ?? c.name, role === "chef" ? "Chuyên gia" : "Thành viên"),
    email: text(c.email),
  };
}

/** A row with the older `chefId` / `chef` and no `role` is a chef's. */
const readRole = (raw: Raw): WalletRole => pick<WalletRole>(WALLET_ROLES, raw.role, raw.chefId !== undefined || raw.chef !== undefined ? "chef" : "member");

function readBankAccount(raw: Raw): BankAccount | null {
  const source = obj(raw.bankAccount) ?? raw;
  const number = text(source.accountNumber);
  if (!number) return null;
  return {
    bankName: text(source.bankName),
    accountNumber: number,
    accountHolder: text(source.accountHolder),
  };
}

export function normalizeWithdrawal(raw: Raw): WithdrawalRequest {
  const role = readRole(raw);
  const userId = raw.userId ?? raw.chefId;
  const user = raw.user ?? raw.chef;
  return {
    id: readId(raw.id),
    userId: readId(userId ?? obj(user)?.id),
    role,
    user: readOwner(user, userId, role),
    amount: num(raw.amount),
    status: pick<WithdrawalStatus>(WITHDRAWAL_STATUSES, raw.status, "Processing"),
    bankAccount: readBankAccount(raw) ?? { bankName: "", accountNumber: "", accountHolder: "" },
    createdAt: isoOr(raw.createdAt),
    processedAt: optIso(raw.processedAt),
    processedBy: optString(raw.processedBy) ?? optString(obj(raw.processedBy)?.fullName),
    transactionRef: optString(raw.transactionRef),
    reason: optString(raw.reason),
  };
}

export function normalizeWallet(raw: Raw): UserWallet {
  const role = readRole(raw);
  const userId = raw.userId ?? raw.chefId;
  const user = raw.user ?? raw.chef;
  return {
    userId: readId(userId ?? obj(user)?.id),
    role,
    user: readOwner(user, userId, role),
    available: num(raw.available),
    pending: num(raw.pending ?? raw.held),
    frozen: num(raw.frozen),
    processing: num(raw.processing),
    withdrawn: num(raw.withdrawn),
    grossSales: num(raw.grossSales),
    feeTotal: num(raw.feeTotal),
    refundTotal: num(raw.refundTotal),
    walletPaymentTotal: num(raw.walletPaymentTotal),
    bankAccount: readBankAccount(raw),
    lastWithdrawalAt: optIso(raw.lastWithdrawalAt),
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
    createdAt: isoOr(raw.createdAt),
    net: num(raw.net),
    bookingId: optId(raw.bookingId),
    orderId: optId(raw.orderId),
    transactionRef: optString(raw.transactionRef),
    planTitle: optString(raw.planTitle) ?? optString(raw.serviceTitle),
    counterpartName: optString(raw.counterpartName) ?? optString(raw.memberName) ?? optString(raw.chefName),
    gross: optNum(raw.gross),
    fee: optNum(raw.fee),
    releaseAt: optIso(raw.releaseAt),
    complaintId: optId(raw.complaintId),
    bankName: optString(raw.bankName),
    note: optString(raw.note),
  };
}

export const payoutsApi = {
  /** GET /admin/payouts/summary */
  async summary(): Promise<PayoutSummary> {
    if (isMock("payouts")) return mock.getPayoutSummary();
    const raw = await requestObject("/admin/payouts/summary");
    const counts = (source: unknown) => countsOf(WITHDRAWAL_STATUSES, source);
    const byRole = obj(raw.byRole) ?? {};
    const availableByRole = obj(raw.availableByRole) ?? {};
    return {
      totalAvailable: num(raw.totalAvailable),
      availableByRole: { member: num(availableByRole.member), chef: num(availableByRole.chef) },
      totalPending: num(raw.totalPending ?? raw.totalHeld),
      totalFrozen: num(raw.totalFrozen),
      totalProcessing: num(raw.totalProcessing),
      paidOutThisMonth: num(raw.paidOutThisMonth),
      paidOutThisMonthCount: num(raw.paidOutThisMonthCount),
      platformFee: num(raw.platformFee),
      releasedGross: num(raw.releasedGross ?? raw.paidGross),
      releasedCount: num(raw.releasedCount ?? raw.paidOrderCount),
      feeRate: num(raw.feeRate, PLATFORM_FEE_RATE),
      byStatus: counts(raw.byStatus),
      byRole: { member: counts(byRole.member), chef: counts(byRole.chef) },
      awaitingApproval: num(raw.awaitingApproval),
      awaitingApprovalAmount: num(raw.awaitingApprovalAmount),
    };
  },

  /** GET /admin/withdrawals?status=&role=&search= */
  async listWithdrawals(query: WithdrawalQuery): Promise<WithdrawalRequest[]> {
    if (isMock("payouts")) return mock.listWithdrawals(query);
    const raw = await requestList(`/admin/withdrawals?${qs({ status: query.status, role: query.role === "all" ? undefined : query.role, search: query.search })}`);
    return raw.map(normalizeWithdrawal).filter(hasId);
  },

  /** POST /admin/withdrawals/{id}/complete { transactionRef } | /reject { reason } */
  async act(input: WithdrawalActionInput): Promise<WithdrawalRequest> {
    if (isMock("payouts")) return mock.applyWithdrawalAction(input, readSession());
    const body = input.action === "complete" ? { transactionRef: input.transactionRef } : { reason: input.reason };
    return normalizeWithdrawal(
      await requestObject(`/admin/withdrawals/${encodeURIComponent(input.withdrawalId)}/${input.action}`, {
        method: "POST",
        body: JSON.stringify(body),
      }),
    );
  },

  /** GET /admin/wallets */
  async wallets(): Promise<UserWallet[]> {
    if (isMock("payouts")) return mock.listWallets();
    const raw = await requestList("/admin/wallets");
    return raw.map(normalizeWallet).filter((w) => w.userId !== "");
  },

  /** GET /admin/wallets/{userId}/transactions?limit= — newest first. */
  async transactions(userId: string, limit = 8): Promise<WalletTransaction[]> {
    if (isMock("payouts")) return mock.listWalletTransactions(userId, limit);
    const raw = await requestList(`/admin/wallets/${encodeURIComponent(userId)}/transactions?${qs({ limit })}`);
    return raw.map(normalizeTransaction).filter(hasId).sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  },
};
