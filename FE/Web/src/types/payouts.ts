// src/types/payouts.ts
// Chef wallets and withdrawals for /payouts. Business rules and wire shapes mirror the
// mobile chef wallet (FE/Mobile lib/features/chef_studio: domain/wallet_rules.dart,
// data/models/wallet_models.dart).
//
// ┌ For the BE team: NONE of this exists in the 26-table SQL design. Proposed tables:
// │ bank_accounts        chef_id (PK, FK chef_profiles), bank_name, account_number, account_holder, updated_at
// │ wallets              chef_id (PK), available, pending (held), frozen, processing, withdrawn, updated_at
// │                      (a cache: every figure can be recomputed from wallet_transactions)
// │ wallet_transactions  id, chef_id, type (Income | Refund | Withdrawal), status (Held | Frozen | Available |
// │                      Reversed | Processing | Completed | Rejected), booking_id NULL, order_id NULL,
// │                      withdrawal_id NULL, gross NULL, fee NULL, net (signed), note NULL,
// │                      release_at NULL, released_at NULL, created_at
// │ Income rows follow the booking's escrow hold (types/bookings.ts): Held → Frozen (complaint) →
// │ Available (released, full or split) or Reversed (fully refunded to the member).
// │ withdrawal_requests  id, chef_id, amount, bank_name, account_number, account_holder,
// │                      status (Processing | Completed | Rejected), auto_approve_at NULL,
// │                      transaction_ref NULL, reason NULL, processed_by NULL (FK users),
// │                      processed_at NULL, created_at
// └ Wire names are camelCase of these columns (plan D2); joined fields are "computed by BE".
import type { ISODateString } from "./moderation";

/* ---------------------------------------------------------------- rules */

/** Platform fee taken from every sale. Business placeholder (same as the mobile `kPlatformFeeRate`). */
export const PLATFORM_FEE_RATE = 0.1;

/**
 * Booking money stays in escrow until the plan's end date 23:59 (Asia/Ho_Chi_Minh) + this many days
 * (the complaint window). A complaint freezes it until an admin decides on /disputes.
 */
export const ESCROW_HOLD_DAYS = 3;

/** Smallest withdrawal a chef can request (VND). */
export const MIN_WITHDRAWAL = 100_000;

/** Requests up to this amount are paid out automatically; bigger ones wait for an admin. */
export const AUTO_APPROVE_LIMIT = 5_000_000;

/** Bank transfer reference typed by the admin when marking a request as paid. */
export const TRANSFER_REF_MIN = 6;
export const TRANSFER_REF_MAX = 40;

/** Fee on `gross`, rounded to whole đồng. */
export const platformFee = (gross: number) => Math.round(gross * PLATFORM_FEE_RATE);

/** Banks offered in the mobile bank-account form. */
export const VIETNAM_BANKS = [
  "Vietcombank",
  "VietinBank",
  "BIDV",
  "Agribank",
  "Techcombank",
  "MB Bank",
  "ACB",
  "VPBank",
  "TPBank",
  "Sacombank",
] as const;

/* ---------------------------------------------------------------- enums */

export const WITHDRAWAL_STATUSES = ["Processing", "Completed", "Rejected"] as const;
export type WithdrawalStatus = (typeof WITHDRAWAL_STATUSES)[number];

export const WITHDRAWAL_STATUS_LABEL: Record<WithdrawalStatus, string> = {
  Processing: "Đang xử lý",
  Completed: "Đã chuyển",
  Rejected: "Bị từ chối",
};

export const LEDGER_ENTRY_TYPES = ["Income", "Refund", "Withdrawal"] as const;
export type LedgerEntryType = (typeof LEDGER_ENTRY_TYPES)[number];

export const LEDGER_ENTRY_TYPE_LABEL: Record<LedgerEntryType, string> = {
  Income: "Thu nhập",
  Refund: "Hoàn tiền",
  Withdrawal: "Rút tiền",
};

/**
 * Earnings: Held → Available after the hold (Frozen while a complaint is open; Reversed when fully
 * refunded). Withdrawals: Processing → Completed / Rejected. Legacy "Pending" reads as Held.
 */
export const LEDGER_STATUSES = ["Held", "Frozen", "Available", "Reversed", "Processing", "Completed", "Rejected"] as const;
export type LedgerStatus = (typeof LEDGER_STATUSES)[number];

export const LEDGER_STATUS_LABEL: Record<LedgerStatus, string> = {
  Held: "Đang giữ",
  Frozen: "Tạm giữ do khiếu nại",
  Available: "Có thể rút",
  Reversed: "Đã hoàn",
  Processing: "Đang xử lý",
  Completed: "Đã chuyển",
  Rejected: "Bị từ chối",
};

/* ---------------------------------------------------------------- rows */

export interface PayoutChef {
  id: string;
  fullName: string;
  email: string;
}

/** bank_accounts. The admin API returns the full number; the console masks it until "Hiện số". */
export interface BankAccount {
  bankName: string;
  accountNumber: string;
  accountHolder: string;
}

/** withdrawal_requests + joined chef. */
export interface WithdrawalRequest {
  id: string;
  chefId: string;
  /** Computed by BE (join chef_profiles + users). */
  chef: PayoutChef;
  amount: number;
  status: WithdrawalStatus;
  /** Snapshot of the chef's bank account when the request was made. */
  bankAccount: BankAccount;
  createdAt: ISODateString;
  /** Computed by BE: amount > AUTO_APPROVE_LIMIT. */
  requiresApproval: boolean;
  /** Automatic payout time of a small request; null when an admin has to approve it. */
  autoApproveAt: ISODateString | null;
  processedAt: ISODateString | null;
  /** Admin who completed / rejected it (computed by BE); null = automatic. */
  processedBy: string | null;
  /** Bank transfer reference, set when Completed. */
  transactionRef: string | null;
  /** Rejection reason, shown to the chef in the app. */
  reason: string | null;
}

/** Same figures as the mobile `WalletDto`, per chef. */
export interface ChefWallet {
  chefId: string;
  chef: PayoutChef;
  /** "Có thể rút": released earnings minus fees, completed withdrawals and requests still processing. */
  available: number;
  /** "Đang giữ": net of bookings still in escrow (until plan end + ESCROW_HOLD_DAYS). */
  pending: number;
  /** "Tạm giữ do khiếu nại": net of holds frozen by an open complaint. */
  frozen: number;
  /** Requests in "Đang xử lý" (already out of `available`). */
  processing: number;
  /** "Đã rút": completed withdrawals. */
  withdrawn: number;
  /** Gross of paid bookings (minus refunds) and the platform fee taken from them. */
  grossSales: number;
  feeTotal: number;
  bankAccount: BankAccount | null;
  lastWithdrawalAt: ISODateString | null;
}

/** wallet_transactions, newest first. Same shape as the mobile `WalletTransactionDto`. */
export interface WalletTransaction {
  id: string;
  type: LedgerEntryType;
  status: LedgerStatus;
  createdAt: ISODateString;
  /** Signed: refunds and withdrawals are negative. */
  net: number;
  bookingId: string | null;
  orderId: string | null;
  transactionRef: string | null;
  /** "Thực đơn 10 ngày · Có phản hồi mỗi ngày" (computed by BE from the contract). */
  planTitle: string | null;
  memberName: string | null;
  gross: number | null;
  fee: number | null;
  /** Held rows: when the escrow is released if nobody complains. */
  releaseAt: ISODateString | null;
  /** Frozen rows: the complaint holding the money (opens /disputes). */
  complaintId: string | null;
  /** Withdrawals: "Vietcombank •••• 6789". */
  bankName: string | null;
  /** Rejection reason / admin note / refund note. */
  note: string | null;
}

/** GET /admin/payouts/summary */
export interface PayoutSummary {
  /** Sum of "Có thể rút" over every chef wallet. */
  totalAvailable: number;
  /** Sum of "Đang giữ" (net of bookings in escrow). */
  totalPending: number;
  /** Sum of "Tạm giữ do khiếu nại". */
  totalFrozen: number;
  /** Sum of requests in "Đang xử lý". */
  totalProcessing: number;
  /** Completed withdrawals whose processedAt falls in the current month (server time zone). */
  paidOutThisMonth: number;
  paidOutThisMonthCount: number;
  /** PLATFORM_FEE_RATE × gross released from escrow (full or split releases). */
  platformFee: number;
  releasedGross: number;
  releasedCount: number;
  feeRate: number;
  autoApproveLimit: number;
  byStatus: Record<WithdrawalStatus, number>;
  /** Processing requests above AUTO_APPROVE_LIMIT: the admin queue. */
  awaitingApproval: number;
  awaitingApprovalAmount: number;
}

export interface WithdrawalQuery {
  status: WithdrawalStatus;
  /** Request id, chef, bank or transfer reference. */
  search: string;
}

export type WithdrawalAction = "complete" | "reject";

/**
 * POST /admin/withdrawals/{id}/complete { transactionRef } — Processing only (409 otherwise).
 * POST /admin/withdrawals/{id}/reject { reason } — reason ≥ 10 chars; the amount returns to "Có thể rút".
 */
export type WithdrawalActionInput =
  | { withdrawalId: string; action: "complete"; transactionRef: string }
  | { withdrawalId: string; action: "reject"; reason: string };
