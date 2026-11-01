// src/lib/mock_payouts.ts
// In-memory wallets and withdrawal requests for /payouts, for chefs and members alike.
//
// Wallets are derived at read time from the escrow holds of chef bookings (mock_bookings.ts,
// read-only). A chef's booking is "Đang giữ" until ESCROW_HOLD_DAYS (7) days after the chef confirms
// completion, "Tạm giữ do khiếu nại" while a complaint is open, then "Có thể rút" at net 90%
// (10% platform fee) — or "Đã hoàn" when an admin refunds it in full on /disputes (a split releases
// price − refund). A refund lands in the member's wallet as "Có thể rút". A decision on /disputes
// therefore shows up in both wallets straight away. So does an admin's decision on a stuck hold: the
// same rows, only the note differs.
//
// Chef seeds mirror the mobile mock (MockCommerceDb): Lê Quang Tâm's Vietcombank 0071000456789
// (LE QUANG TAM), his 2.000.000đ rejected and 1.000.000đ paid withdrawals. Tâm's released bookings
// (b_ma_tam_done 900.000đ + b_han_tam_done 6.000.000đ → net 6.210.000đ) minus 1.000.000đ withdrawn
// give 5.210.000đ; his seeded 5.100.000đ request holds the amount in "Chờ duyệt" (có thể rút
// 110.000đ until it is decided; rejecting it gives 5.210.000đ back). Đang giữ 2.214.000đ (Thảo Vy,
// Bảo Châu, Minh Anh) · tạm giữ 945.000đ (Ngọc Trâm, cp_tram_tam).
//
// Member seeds are web-only: Phan Gia Bảo was refunded 1.330.000đ (cp_bao_chau), withdrew 200.000đ
// and waits on 1.000.000đ (wd_bao_2), leaving 130.000đ. Đức Huy was refunded 400.000đ (cp_huy_ha)
// and had his 400.000đ request rejected. Đỗ Hải Yến cancelled after paying (980.000đ back) and paid
// her next booking from the wallet (600.000đ), leaving 380.000đ, of which 300.000đ waits in wd_yen_1.
// A member has a wallet once it has a refund, a wallet payment or a request.
//
// Every request waits for an admin; nothing pays out on its own.
// QA: `#fail` in the transfer reference, the rejection reason or the search box → 503.
import type { AdminSession } from "@/types/admin";
import { MIN_AUDIT_NOTE_LENGTH } from "@/types/moderation";
import type {
  BankAccount,
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
import { PLATFORM_FEE_RATE, platformFee, TRANSFER_REF_MAX, TRANSFER_REF_MIN, WALLET_ROLES, WITHDRAWAL_STATUSES } from "@/types/payouts";

import { ApiError } from "./api_error";
import { logAction } from "./mock_admin";
import { escrowLedger, MEMBERS, type EscrowLedgerEntry } from "./mock_bookings";
import { sleep } from "./mock_data";

const MIN = 60_000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;
const NOW = Date.now();
const iso = (ms: number) => new Date(ms).toISOString();

/** A moment about `days` ago that still falls in the current month (seeds for "Đã chi trả tháng này"). */
function thisMonth(days: number) {
  const d = new Date(NOW);
  const monthStart = new Date(d.getFullYear(), d.getMonth(), 1).getTime();
  return Math.max(NOW - days * DAY, monthStart + (NOW - monthStart) / 3);
}

const vndText = new Intl.NumberFormat("vi-VN");
const vnd = (n: number) => `${vndText.format(n)}đ`;

const pad2 = (n: number) => String(n).padStart(2, "0");
const yymmdd = (ms: number) => {
  const d = new Date(ms);
  return `${String(d.getFullYear()).slice(2)}${pad2(d.getMonth() + 1)}${pad2(d.getDate())}`;
};

/* ---------------------------------------------------------------- owners */

const CHEFS: Record<string, WalletOwner> = {
  u_chef_tam: { id: "u_chef_tam", fullName: "Lê Quang Tâm", email: "tam.chefchay@gmail.com" },
  u_thu_ha: { id: "u_thu_ha", fullName: "ThS. DD Phạm Thu Hà", email: "thuha.dinhduong@gmail.com" },
  u_chef_chau: { id: "u_chef_chau", fullName: "Tôn Nữ Minh Châu", email: "minhchau.hue@gmail.com" },
  u_chef_khoa: { id: "u_chef_khoa", fullName: "Nguyễn Đăng Khoa", email: "khoa.fitvegan@gmail.com" },
  u_chef_lan: { id: "u_chef_lan", fullName: "Võ Thị Ngọc Lan", email: "ngoclan.anddam@gmail.com" },
  u_chef_minh: { id: "u_chef_minh", fullName: "Trần Quốc Minh", email: "quocminh.thucduong@gmail.com" },
};

const memberOwner = (id: string): WalletOwner | undefined => (MEMBERS as Record<string, WalletOwner>)[id];
const ownerOf = (userId: string, role: WalletRole): WalletOwner => (role === "chef" ? CHEFS[userId] : memberOwner(userId)) ?? { id: userId, fullName: "Người dùng", email: "" };

/** bank_accounts. Lan, Minh and most members have not added one yet. */
const bankAccounts = new Map<string, BankAccount>([
  ["u_chef_tam", { bankName: "Vietcombank", accountNumber: "0071000456789", accountHolder: "LE QUANG TAM" }],
  ["u_thu_ha", { bankName: "Techcombank", accountNumber: "19034567891012", accountHolder: "PHAM THU HA" }],
  ["u_chef_chau", { bankName: "BIDV", accountNumber: "31410001234567", accountHolder: "TON NU MINH CHAU" }],
  ["u_chef_khoa", { bankName: "MB Bank", accountNumber: "0801234567890", accountHolder: "NGUYEN DANG KHOA" }],
  ["u_new_1", { bankName: "ACB", accountNumber: "24681012", accountHolder: "PHAN GIA BAO" }],
  ["u_duc_huy", { bankName: "TPBank", accountNumber: "04567891234", accountHolder: "NGUYEN DUC HUY" }],
  ["u_new_3", { bankName: "MB Bank", accountNumber: "9704221234", accountHolder: "DO HAI YEN" }],
]);

/* ---------------------------------------------------------- withdrawals */

let bankRefSeq = 120;
/** Bank transfer reference of a seeded payout: "FT" + yyMMdd + 6 digits. */
const seedRef = (at: number) => `FT${yymmdd(at)}${String(++bankRefSeq).padStart(6, "0")}`;

interface Spec {
  id: string;
  userId: string;
  role: WalletRole;
  amount: number;
  created: number;
  status: WithdrawalStatus;
  /** Completed / Rejected: minutes after the request. */
  processedAfterMin?: number;
  processedBy?: string;
  reason?: string;
}

function build(spec: Spec): WithdrawalRequest {
  const account = bankAccounts.get(spec.userId);
  if (!account) throw new Error(`mock_payouts: ${spec.userId} has no bank account`);
  const processedAt = spec.status === "Processing" ? null : spec.created + (spec.processedAfterMin ?? 60) * MIN;
  return {
    id: spec.id,
    userId: spec.userId,
    role: spec.role,
    user: { ...ownerOf(spec.userId, spec.role) },
    amount: spec.amount,
    status: spec.status,
    bankAccount: { ...account },
    createdAt: iso(spec.created),
    processedAt: processedAt === null ? null : iso(processedAt),
    processedBy: processedAt === null ? null : (spec.processedBy ?? "Lê Minh Quân"),
    transactionRef: spec.status === "Completed" && processedAt !== null ? seedRef(processedAt) : null,
    reason: spec.reason ?? null,
  };
}

const withdrawals: WithdrawalRequest[] = (
  [
    // Lê Quang Tâm — the first two mirror the mobile seeds (wd_tam_1, wd_tam_2).
    {
      id: "wd_tam_1",
      userId: "u_chef_tam",
      role: "chef",
      amount: 2_000_000,
      created: NOW - 30 * DAY,
      status: "Rejected",
      processedAfterMin: 90,
      reason: "Số dư có thể rút lúc gửi yêu cầu chưa đủ 2.000.000đ.",
    },
    { id: "wd_tam_2", userId: "u_chef_tam", role: "chef", amount: 1_000_000, created: NOW - 17 * DAY, status: "Completed", processedAfterMin: 120 },
    { id: "wd_tam_3", userId: "u_chef_tam", role: "chef", amount: 5_100_000, created: NOW - 3 * HOUR - 12 * MIN, status: "Processing" },
    // ThS. DD Phạm Thu Hà
    {
      id: "wd_ha_1",
      userId: "u_thu_ha",
      role: "chef",
      amount: 600_000,
      created: NOW - 20 * DAY,
      status: "Rejected",
      processedAfterMin: 3,
      processedBy: "Trần Thu Hằng",
      reason: "Ngân hàng báo sai tên chủ tài khoản. Tiền đã trở lại ví, nhờ chuyên gia cập nhật tài khoản nhận.",
    },
    { id: "wd_ha_2", userId: "u_thu_ha", role: "chef", amount: 1_000_000, created: thisMonth(2), status: "Completed" },
    { id: "wd_ha_3", userId: "u_thu_ha", role: "chef", amount: 400_000, created: NOW - 2 * MIN, status: "Processing" },
    // Tôn Nữ Minh Châu
    {
      id: "wd_chau_1",
      userId: "u_chef_chau",
      role: "chef",
      amount: 800_000,
      created: NOW - 12 * DAY,
      status: "Rejected",
      processedAfterMin: 4,
      processedBy: "Lê Minh Quân",
      reason: "Tên chủ tài khoản không khớp hồ sơ chuyên gia. Đã nhờ chuyên gia cập nhật trước khi gửi lại.",
    },
    { id: "wd_chau_2", userId: "u_chef_chau", role: "chef", amount: 1_200_000, created: thisMonth(3), status: "Completed" },
    // Members: refunds from complaint decisions (b_bao_chau decided 9 days ago, b_huy_ha 6).
    { id: "wd_bao_1", userId: "u_new_1", role: "member", amount: 200_000, created: thisMonth(4), status: "Completed", processedBy: "Trần Thu Hằng" },
    { id: "wd_bao_2", userId: "u_new_1", role: "member", amount: 1_000_000, created: NOW - 5 * HOUR, status: "Processing" },
    { id: "wd_yen_1", userId: "u_new_3", role: "member", amount: 300_000, created: NOW - 30 * MIN, status: "Processing" },
    {
      id: "wd_huy_1",
      userId: "u_duc_huy",
      role: "member",
      amount: 400_000,
      created: NOW - 2 * DAY,
      status: "Rejected",
      processedAfterMin: 30,
      processedBy: "Lê Minh Quân",
      reason: "Tên chủ tài khoản không khớp tên thành viên. Tiền đã trở lại ví, nhờ cập nhật tài khoản nhận rồi gửi lại.",
    },
  ] satisfies Spec[]
).map(build);

const copy = (w: WithdrawalRequest): WithdrawalRequest => ({ ...w, user: { ...w.user }, bankAccount: { ...w.bankAccount } });

/* ------------------------------------------------------------- earnings */

interface Earning {
  chefId: string;
  bookingId: string;
  orderId: string | null;
  planTitle: string;
  memberName: string;
  transactionRef: string | null;
  /** What the chef earns on: contract price, or price − refund after a split decision. */
  gross: number;
  fee: number;
  status: Extract<LedgerStatus, "Held" | "Frozen" | "Available" | "Reversed">;
  /** When the money became available (release) or was held (payment). */
  at: number;
  releaseAt: string | null;
  complaintId: string | null;
  note: string | null;
}

function earningOf(e: EscrowLedgerEntry): Earning {
  const common = {
    chefId: e.chefId,
    bookingId: e.bookingId,
    orderId: e.orderId,
    planTitle: e.planTitle,
    memberName: e.memberName,
    transactionRef: e.transactionRef,
    releaseAt: e.releaseAt,
    complaintId: e.complaintId,
  };
  switch (e.status) {
    case "Held":
      return {
        ...common,
        gross: e.amount,
        fee: platformFee(e.amount),
        status: "Held",
        at: Date.parse(e.heldAt),
        note: e.autoCompleted ? "Hệ thống tự hoàn tất vì chuyên gia không xác nhận" : e.releaseAt ? null : "VeganLife đang giữ, chờ chuyên gia xác nhận hoàn thành",
      };
    case "Frozen":
      return { ...common, gross: e.amount, fee: platformFee(e.amount), status: "Frozen", at: Date.parse(e.heldAt), note: null };
    case "Released":
      return {
        ...common,
        gross: e.releasedAmount,
        fee: e.feeAmount,
        status: "Available",
        at: Date.parse(e.releasedAt ?? e.heldAt),
        note: e.complaintId
          ? "Giải ngân theo quyết định khiếu nại"
          : e.adminResolved
            ? "Giải ngân theo quyết định của Ban quản trị"
            : e.autoCompleted
              ? "Hệ thống tự hoàn tất vì chuyên gia không xác nhận"
              : null,
      };
    case "PartiallyRefunded":
      return {
        ...common,
        gross: e.releasedAmount,
        fee: e.feeAmount,
        status: "Available",
        at: Date.parse(e.releasedAt ?? e.decidedAt ?? e.heldAt),
        note: `Hoàn ${vnd(e.refundedAmount)} vào ví thành viên theo quyết định ${e.adminResolved ? "của Ban quản trị" : "khiếu nại"}`,
      };
    case "Refunded":
      return {
        ...common,
        gross: e.amount,
        fee: platformFee(e.amount),
        status: "Reversed",
        at: Date.parse(e.refundedAt ?? e.heldAt),
        note: e.cancelled ? `Thành viên huỷ sau khi thanh toán, đã hoàn ${vnd(e.refundedAmount)} vào ví thành viên` : `Đã hoàn toàn bộ ${vnd(e.refundedAmount)} vào ví thành viên`,
      };
  }
}

const net = (e: Pick<Earning, "gross" | "fee">) => e.gross - e.fee;
const sum = (values: number[]) => values.reduce((a, b) => a + b, 0);

function walletOf(userId: string, role: WalletRole, ledger: EscrowLedgerEntry[]): UserWallet {
  const requests = withdrawals.filter((w) => w.userId === userId && w.role === role);
  const completed = requests.filter((w) => w.status === "Completed");
  const withdrawn = sum(completed.map((w) => w.amount));
  const processing = sum(requests.filter((w) => w.status === "Processing").map((w) => w.amount));
  const lastPaid = completed.map((w) => w.processedAt ?? w.createdAt).sort().at(-1) ?? null;
  const account = bankAccounts.get(userId);
  const shared = {
    userId,
    role,
    user: { ...ownerOf(userId, role) },
    processing,
    withdrawn,
    bankAccount: account ? { ...account } : null,
    lastWithdrawalAt: lastPaid,
  };
  if (role === "member") {
    const mine = ledger.filter((e) => e.memberId === userId);
    const refundTotal = sum(mine.map((e) => e.refundedAmount));
    const walletPaymentTotal = sum(mine.filter((e) => e.walletPaid).map((e) => e.amount));
    return { ...shared, available: refundTotal - walletPaymentTotal - withdrawn - processing, pending: 0, frozen: 0, grossSales: 0, feeTotal: 0, refundTotal, walletPaymentTotal };
  }
  const mine = ledger.filter((e) => e.chefId === userId).map(earningOf);
  const live = mine.filter((e) => e.status !== "Reversed");
  return {
    ...shared,
    available: sum(mine.filter((e) => e.status === "Available").map(net)) - withdrawn - processing,
    pending: sum(mine.filter((e) => e.status === "Held").map(net)),
    frozen: sum(mine.filter((e) => e.status === "Frozen").map(net)),
    grossSales: sum(live.map((e) => e.gross)),
    feeTotal: sum(live.map((e) => e.fee)),
    refundTotal: 0,
    walletPaymentTotal: 0,
  };
}

/** Every chef, plus every member with a refund, a wallet payment or a request. */
function allWallets(ledger: EscrowLedgerEntry[]): UserWallet[] {
  const memberIds = new Set<string>([
    ...ledger.filter((e) => e.refundedAmount > 0 || e.walletPaid).map((e) => e.memberId),
    ...withdrawals.filter((w) => w.role === "member").map((w) => w.userId),
  ]);
  return [...Object.keys(CHEFS).map((id) => walletOf(id, "chef", ledger)), ...[...memberIds].map((id) => walletOf(id, "member", ledger))];
}

/* ----------------------------------------------------------------- reads */

const fold = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[Đđ]/g, "d").toLowerCase();
const hasFail = (text: string) => text.toLowerCase().includes("#fail");
const unavailable = (what: string) => new ApiError(`Máy chủ đang bận, chưa ${what}. Thử lại sau.`, 503, "unavailable");

const maskAccount = (number: string) => (number.length <= 4 ? number : `•••• ${number.slice(-4)}`);

export async function listWithdrawals(query: WithdrawalQuery): Promise<WithdrawalRequest[]> {
  await sleep(400);
  if (hasFail(query.search)) throw unavailable("tải được yêu cầu rút tiền");
  const q = fold(query.search.trim());
  return withdrawals
    .filter((w) => w.status === query.status && (query.role === "all" || w.role === query.role))
    .filter(
      (w) =>
        !q ||
        fold(
          [w.id, w.user.fullName, w.user.email, w.bankAccount.bankName, w.bankAccount.accountNumber, w.bankAccount.accountHolder, w.transactionRef ?? ""].join(" "),
        ).includes(q),
    )
    .sort((a, b) =>
      query.status === "Processing" ? a.createdAt.localeCompare(b.createdAt) : (b.processedAt ?? b.createdAt).localeCompare(a.processedAt ?? a.createdAt),
    )
    .map(copy);
}

export async function listWallets(): Promise<UserWallet[]> {
  await sleep(300);
  return allWallets(escrowLedger(Date.now())).sort(
    (a, b) => b.available + b.processing - (a.available + a.processing) || a.user.fullName.localeCompare(b.user.fullName, "vi"),
  );
}

export async function listWalletTransactions(userId: string, limit: number): Promise<WalletTransaction[]> {
  const ledger = escrowLedger(Date.now());
  const isChef = CHEFS[userId] !== undefined;
  if (!isChef && !memberOwner(userId)) {
    await sleep(200);
    throw new ApiError("Không tìm thấy ví của người dùng.", 404, "not_found");
  }
  await sleep(300);
  const rows: WalletTransaction[] = [];
  if (isChef) {
    for (const e of ledger.filter((x) => x.chefId === userId).map(earningOf)) {
      rows.push({
        id: `tx_in_${e.bookingId}`,
        type: "Income",
        status: e.status,
        createdAt: iso(e.at),
        gross: e.gross,
        fee: e.fee,
        net: net(e),
        bookingId: e.bookingId,
        orderId: e.orderId,
        transactionRef: e.transactionRef,
        planTitle: e.planTitle,
        counterpartName: e.memberName,
        releaseAt: e.status === "Held" ? e.releaseAt : null,
        complaintId: e.complaintId,
        bankName: null,
        note: e.note,
      });
    }
  } else {
    for (const e of ledger.filter((x) => x.memberId === userId && x.refundedAmount > 0)) {
      rows.push({
        id: `tx_rf_${e.bookingId}`,
        type: "Refund",
        status: "Available",
        createdAt: e.refundedAt ?? e.heldAt,
        gross: null,
        fee: null,
        net: e.refundedAmount,
        bookingId: e.bookingId,
        orderId: e.orderId,
        transactionRef: e.transactionRef,
        planTitle: e.planTitle,
        counterpartName: e.chefName,
        releaseAt: null,
        complaintId: e.complaintId,
        bankName: null,
        note: e.cancelled ? "Hoàn do thành viên huỷ sau khi thanh toán" : e.adminResolved ? "Hoàn theo quyết định của Ban quản trị" : "Hoàn theo quyết định khiếu nại",
      });
    }
    for (const e of ledger.filter((x) => x.memberId === userId && x.walletPaid)) {
      rows.push({
        id: `tx_pay_${e.bookingId}`,
        type: "Payment",
        status: "Completed",
        createdAt: e.heldAt,
        gross: null,
        fee: null,
        net: -e.amount,
        bookingId: e.bookingId,
        orderId: e.orderId,
        transactionRef: e.transactionRef,
        planTitle: e.planTitle,
        counterpartName: e.chefName,
        releaseAt: null,
        complaintId: null,
        bankName: null,
        note: null,
      });
    }
  }
  for (const w of withdrawals.filter((x) => x.userId === userId)) {
    rows.push({
      id: `tx_wd_${w.id}`,
      type: "Withdrawal",
      status: w.status,
      createdAt: w.createdAt,
      net: -w.amount,
      bookingId: null,
      orderId: null,
      transactionRef: w.transactionRef,
      planTitle: null,
      counterpartName: null,
      gross: null,
      fee: null,
      releaseAt: null,
      complaintId: null,
      bankName: `${w.bankAccount.bankName} ${maskAccount(w.bankAccount.accountNumber)}`,
      note: w.reason,
    });
  }
  return rows.sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, Math.max(1, limit));
}

const countByStatus = (list: WithdrawalRequest[]) =>
  Object.fromEntries(WITHDRAWAL_STATUSES.map((s) => [s, list.filter((w) => w.status === s).length])) as Record<WithdrawalStatus, number>;

export async function getPayoutSummary(): Promise<PayoutSummary> {
  await sleep(300);
  const now = Date.now();
  const ledger = escrowLedger(now);
  const earnings = ledger.map(earningOf);
  const wallets = allWallets(ledger);
  const monthStart = new Date(new Date(now).getFullYear(), new Date(now).getMonth(), 1).getTime();
  const paidThisMonth = withdrawals.filter((w) => w.status === "Completed" && w.processedAt !== null && Date.parse(w.processedAt) >= monthStart);
  const awaiting = withdrawals.filter((w) => w.status === "Processing");
  const released = earnings.filter((e) => e.status === "Available");
  const availableOf = (role: WalletRole) => sum(wallets.filter((w) => w.role === role).map((w) => w.available));
  return {
    totalAvailable: sum(wallets.map((w) => w.available)),
    availableByRole: { chef: availableOf("chef"), member: availableOf("member") },
    totalPending: sum(wallets.map((w) => w.pending)),
    totalFrozen: sum(wallets.map((w) => w.frozen)),
    totalProcessing: sum(wallets.map((w) => w.processing)),
    paidOutThisMonth: sum(paidThisMonth.map((w) => w.amount)),
    paidOutThisMonthCount: paidThisMonth.length,
    platformFee: sum(released.map((e) => e.fee)),
    releasedGross: sum(released.map((e) => e.gross)),
    releasedCount: released.length,
    feeRate: PLATFORM_FEE_RATE,
    byStatus: countByStatus(withdrawals),
    byRole: Object.fromEntries(WALLET_ROLES.map((r) => [r, countByStatus(withdrawals.filter((w) => w.role === r))])) as PayoutSummary["byRole"],
    awaitingApproval: awaiting.length,
    awaitingApprovalAmount: sum(awaiting.map((w) => w.amount)),
  };
}

/* ---------------------------------------------------------------- writes */

const TRANSFER_REF_PATTERN = new RegExp(`^[A-Za-z0-9._/-]{${TRANSFER_REF_MIN},${TRANSFER_REF_MAX}}$`);

/**
 * Approve (Processing only): Completed with the admin's bank transfer reference.
 * Reject (Processing only): Rejected with a reason ≥ 10 chars; the amount returns to "Có thể rút".
 */
export async function applyWithdrawalAction(input: WithdrawalActionInput, session: AdminSession | null): Promise<WithdrawalRequest> {
  await sleep(700);
  const now = Date.now();
  const actor = session?.fullName ?? "Quản trị viên";

  if (input.action === "complete") {
    const ref = input.transactionRef.trim();
    if (hasFail(ref)) throw unavailable("ghi nhận được lệnh chuyển");
    if (!TRANSFER_REF_PATTERN.test(ref)) {
      throw new ApiError(
        `Mã giao dịch gồm ${TRANSFER_REF_MIN}–${TRANSFER_REF_MAX} ký tự: chữ, số và . _ / -`,
        400,
        "invalid_transaction_ref",
      );
    }
  } else {
    const reason = input.reason.trim();
    if (reason.length < MIN_AUDIT_NOTE_LENGTH) {
      throw new ApiError(`Lý do cần ít nhất ${MIN_AUDIT_NOTE_LENGTH} ký tự.`, 400, "reason_too_short");
    }
    if (hasFail(reason)) throw unavailable("từ chối được yêu cầu");
  }

  const w = withdrawals.find((x) => x.id === input.withdrawalId);
  if (!w) throw new ApiError("Yêu cầu rút tiền không còn tồn tại.", 404, "not_found");
  if (w.status !== "Processing") {
    throw new ApiError(
      w.status === "Completed" ? "Yêu cầu đã được chuyển tiền trước đó." : "Yêu cầu đã bị từ chối trước đó.",
      409,
      "already_processed",
    );
  }

  w.processedAt = iso(now);
  w.processedBy = actor;
  if (input.action === "complete") {
    w.status = "Completed";
    w.transactionRef = input.transactionRef.trim();
    logAction(actor, "duyệt yêu cầu rút tiền", `${w.user.fullName} · ${vnd(w.amount)} · ${w.transactionRef}`);
  } else {
    w.status = "Rejected";
    w.reason = input.reason.trim();
    logAction(actor, "từ chối yêu cầu rút tiền", `${w.user.fullName} · ${vnd(w.amount)}`);
  }
  return copy(w);
}
