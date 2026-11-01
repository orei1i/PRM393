// src/types/payouts.ts
// Wallets and withdrawals for /payouts. Both sides of a booking have a wallet: the chef's collects
// released earnings, the member's collects refunds (complaint decisions, cancelling after paying) and
// can pay a booking in full. Either can ask to withdraw to a bank account, and an admin approves or
// rejects every request under the same rules.
// Earlier versions mirrored the mobile chef wallet (FE/Mobile lib/features/chef_studio) with an
// automatic payout up to 5.000.000đ; that is gone: every request now waits for an admin.
//
// ┌ For the BE team: NONE of this exists in the 26-table SQL design. Proposed tables:
// │ bank_accounts        user_id (PK, FK users), bank_name, account_number, account_holder, updated_at
// │ wallets              user_id (PK), available, pending (held), frozen, processing, withdrawn, updated_at
// │                      (a cache: every figure can be recomputed from wallet_transactions)
// │ wallet_transactions  id, user_id, type (Income | Refund | Payment | Withdrawal), status (Held | Frozen | Available |
// │                      Reversed | Processing | Completed | Rejected), booking_id NULL, order_id NULL,
// │                      withdrawal_id NULL, gross NULL, fee NULL, net (signed), note NULL,
// │                      release_at NULL, released_at NULL, created_at
// │ Income rows (chef) follow the booking's escrow hold (types/bookings.ts): Held → Frozen (complaint) →
// │ Available (released, full or split) or Reversed (fully refunded to the member).
// │ Refund rows (member) are created Available when a complaint decision or a cancellation refunds the member.
// │ Payment rows (member) are created Completed, with a negative net, when a booking is paid from the wallet.
// │ withdrawal_requests  id, user_id, role (member | chef), amount, bank_name, account_number, account_holder,
// │                      status (Processing | Completed | Rejected), transaction_ref NULL, reason NULL,
// │                      processed_by NULL (FK users), processed_at NULL, created_at
// └ Wire names are camelCase of these columns (plan D2); joined fields are "computed by BE".
import type { ISODateString } from "./moderation";

/* ---------------------------------------------------------------- rules */

/** Platform fee taken from every sale. Business placeholder (same as the mobile `kPlatformFeeRate`). */
export const PLATFORM_FEE_RATE = 0.1;

/**
 * Booking money stays on the platform until this many days after the chef confirms the work is
 * done (the complaint window). A complaint freezes it until an admin decides on /disputes.
 */
export const ESCROW_HOLD_DAYS = 7;

/** /disputes KPI "Sẽ giải ngân trong N ngày". */
export const RELEASING_SOON_DAYS = 3;

/** Smallest withdrawal anyone can request (VND). */
export const MIN_WITHDRAWAL = 100_000;

/** Bank transfer reference typed by the admin when approving a request. */
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

/** Same words as BookingParty, so a booking's sides read the same in both modules. */
export const WALLET_ROLES = ["member", "chef"] as const;
export type WalletRole = (typeof WALLET_ROLES)[number];
export type WalletRoleFilter = WalletRole | "all";

export const WALLET_ROLE_LABEL: Record<WalletRole, string> = {
  member: "Thành viên",
  chef: "Chuyên gia",
};

export const WITHDRAWAL_STATUSES = ["Processing", "Completed", "Rejected"] as const;
export type WithdrawalStatus = (typeof WITHDRAWAL_STATUSES)[number];

export const WITHDRAWAL_STATUS_LABEL: Record<WithdrawalStatus, string> = {
  Processing: "Chờ duyệt",
  Completed: "Đã chuyển",
  Rejected: "Bị từ chối",
};

export const LEDGER_ENTRY_TYPES = ["Income", "Refund", "Payment", "Withdrawal"] as const;
export type LedgerEntryType = (typeof LEDGER_ENTRY_TYPES)[number];

export const LEDGER_ENTRY_TYPE_LABEL: Record<LedgerEntryType, string> = {
  Income: "Thu nhập",
  Refund: "Hoàn tiền",
  Payment: "Thanh toán bằng ví",
  Withdrawal: "Rút tiền",
};

/**
 * Earnings: Held → Available after the hold (Frozen while a complaint is open; Reversed when fully
 * refunded). Refunds: Available at once. Wallet payments: Completed at once. Withdrawals: Processing → Completed / Rejected. Legacy
 * "Pending" reads as Held.
 */
export const LEDGER_STATUSES = ["Held", "Frozen", "Available", "Reversed", "Processing", "Completed", "Rejected"] as const;
export type LedgerStatus = (typeof LEDGER_STATUSES)[number];

export const LEDGER_STATUS_LABEL: Record<LedgerStatus, string> = {
  Held: "Đang giữ",
  Frozen: "Tạm giữ do khiếu nại",
  Available: "Có thể rút",
  Reversed: "Đã hoàn",
  Processing: "Chờ duyệt",
  Completed: "Đã chuyển",
  Rejected: "Bị từ chối",
};

/* ---------------------------------------------------------------- rows */

export interface WalletOwner {
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

/** withdrawal_requests + joined user. */
export interface WithdrawalRequest {
  id: string;
  userId: string;
  role: WalletRole;
  /** Computed by BE (join users). */
  user: WalletOwner;
  amount: number;
  status: WithdrawalStatus;
  /** Snapshot of the user's bank account when the request was made. */
  bankAccount: BankAccount;
  createdAt: ISODateString;
  processedAt: ISODateString | null;
  /** Admin who approved / rejected it (computed by BE). */
  processedBy: string | null;
  /** Bank transfer reference, set when Completed. */
  transactionRef: string | null;
  /** Rejection reason, shown to the user in the app. */
  reason: string | null;
}

/** Same figures as the mobile `WalletDto`, per user. */
export interface UserWallet {
  userId: string;
  role: WalletRole;
  user: WalletOwner;
  /** "Có thể rút": released earnings or refunds minus completed withdrawals and requests waiting for approval. */
  available: number;
  /** "Đang giữ": net of bookings still on the platform (chef only; members have no claim until a decision). */
  pending: number;
  /** "Tạm giữ do khiếu nại": net of holds frozen by an open complaint (chef only). */
  frozen: number;
  /** Requests in "Chờ duyệt" (already out of `available`). */
  processing: number;
  /** "Đã rút": completed withdrawals. */
  withdrawn: number;
  /** Chef: gross of paid bookings (minus refunds) and the platform fee taken from them. 0 for members. */
  grossSales: number;
  feeTotal: number;
  /** Total refunded to this wallet. A chef who booked another chef can have some too (one wallet per user). */
  refundTotal: number;
  /** Bookings paid from this wallet (already out of `available`). */
  walletPaymentTotal: number;
  bankAccount: BankAccount | null;
  lastWithdrawalAt: ISODateString | null;
}

/** wallet_transactions, newest first. Same shape as the mobile `WalletTransactionDto`. */
export interface WalletTransaction {
  id: string;
  type: LedgerEntryType;
  status: LedgerStatus;
  createdAt: ISODateString;
  /** Signed: income and refunds are positive, wallet payments and withdrawals negative. */
  net: number;
  bookingId: string | null;
  orderId: string | null;
  transactionRef: string | null;
  /** "Thực đơn 10 ngày · Có phản hồi mỗi ngày" (computed by BE from the contract). */
  planTitle: string | null;
  /** The other side of the booking: the member on a chef's row, the chef on a member's. */
  counterpartName: string | null;
  gross: number | null;
  fee: number | null;
  /** Held rows: when the money reaches the chef's wallet if nobody complains; null until the contract completes. */
  releaseAt: ISODateString | null;
  /** The complaint behind a Frozen or Refund row (opens /disputes). */
  complaintId: string | null;
  /** Withdrawals: "Vietcombank •••• 6789". */
  bankName: string | null;
  /** Rejection reason / admin note / refund note. */
  note: string | null;
}

/** GET /admin/payouts/summary */
export interface PayoutSummary {
  /** Sum of "Có thể rút" over every wallet. */
  totalAvailable: number;
  availableByRole: Record<WalletRole, number>;
  /** Sum of "Đang giữ" (net of bookings on the platform). */
  totalPending: number;
  /** Sum of "Tạm giữ do khiếu nại". */
  totalFrozen: number;
  /** Sum of requests in "Chờ duyệt". */
  totalProcessing: number;
  /** Completed withdrawals whose processedAt falls in the current month (server time zone). */
  paidOutThisMonth: number;
  paidOutThisMonthCount: number;
  /** PLATFORM_FEE_RATE × gross released from escrow (full or split releases). */
  platformFee: number;
  releasedGross: number;
  releasedCount: number;
  feeRate: number;
  byStatus: Record<WithdrawalStatus, number>;
  byRole: Record<WalletRole, Record<WithdrawalStatus, number>>;
  /** Requests in "Chờ duyệt": the admin queue. */
  awaitingApproval: number;
  awaitingApprovalAmount: number;
}

export interface WithdrawalQuery {
  status: WithdrawalStatus;
  role: WalletRoleFilter;
  /** Request id, user, bank or transfer reference. */
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
