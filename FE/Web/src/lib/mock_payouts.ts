// src/lib/mock_payouts.ts
// In-memory chef wallets and withdrawal requests for /payouts.
//
// Earnings are derived at read time from the orders in mock_commerce.ts (read-only) with
// the mobile wallet rules (wallet_rules.dart): 10% platform fee; Course / VIP Menu money is
// released 7 days after payment, a Consult when it is Completed; a refund reverses it. A refund
// made on /orders therefore shows up in the chef's wallet straight away.
//
// Mirrors the mobile mock (MockCommerceDb): Lê Quang Tâm's bank account (Vietcombank
// 0071000456789, LE QUANG TAM) and his two past withdrawals (2.000.000đ rejected,
// 1.000.000đ paid). The web order seeds lack two of Tâm's older package sales that the mobile
// mock has (Gia Hân's VIP menu, Quốc Việt's course — the datasets are independent, plan D13),
// so they are seeded here as wallet-only income. Before his seeded 5.100.000đ request Tâm's
// wallet equals the mobile one: có thể rút 5.462.000đ · đang chờ 1.521.000đ · đã rút 1.000.000đ.
// That request is above 5.000.000đ, so it waits for an admin and holds the amount in
// "Đang xử lý" (có thể rút 362.000đ until it is completed; rejecting it gives 5.462.000đ back).
//
// Requests ≤ 5.000.000đ pay out on their own at `autoApproveAt` (settled lazily on read, like
// the mobile mock). Thu Hà's seeded 400.000đ request does so a few minutes after page load.
// QA: `#fail` in the transfer reference, the rejection reason or the search box → 503.
import type { AdminSession } from "@/types/admin";
import type { AdminOrder } from "@/types/commerce";
import { MIN_AUDIT_NOTE_LENGTH } from "@/types/moderation";
import type {
  BankAccount,
  ChefWallet,
  LedgerStatus,
  PayoutChef,
  PayoutSummary,
  WalletTransaction,
  WithdrawalActionInput,
  WithdrawalQuery,
  WithdrawalRequest,
  WithdrawalStatus,
} from "@/types/payouts";
import {
  AUTO_APPROVE_LIMIT,
  PACKAGE_HOLD_DAYS,
  PLATFORM_FEE_RATE,
  platformFee,
  TRANSFER_REF_MAX,
  TRANSFER_REF_MIN,
  WITHDRAWAL_STATUSES,
} from "@/types/payouts";

import { ApiError } from "./api_error";
import { logAction } from "./mock_admin";
import { listOrders } from "./mock_commerce";
import { sleep } from "./mock_data";

const MIN = 60_000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;
const NOW = Date.now();
const iso = (ms: number) => new Date(ms).toISOString();

/** Mock only: small requests pay out this long after they are made (the mobile mock uses 10 s). */
const AUTO_PAYOUT_DELAY = 5 * MIN;

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

/* ---------------------------------------------------------------- chefs */

const CHEFS: Record<string, PayoutChef> = {
  u_chef_tam: { id: "u_chef_tam", fullName: "Lê Quang Tâm", email: "tam.chefchay@gmail.com" },
  u_thu_ha: { id: "u_thu_ha", fullName: "ThS. DD Phạm Thu Hà", email: "thuha.dinhduong@gmail.com" },
  u_chef_chau: { id: "u_chef_chau", fullName: "Tôn Nữ Minh Châu", email: "minhchau.hue@gmail.com" },
  u_chef_khoa: { id: "u_chef_khoa", fullName: "Nguyễn Đăng Khoa", email: "khoa.fitvegan@gmail.com" },
  u_chef_lan: { id: "u_chef_lan", fullName: "Võ Thị Ngọc Lan", email: "ngoclan.anddam@gmail.com" },
  u_chef_minh: { id: "u_chef_minh", fullName: "Trần Quốc Minh", email: "quocminh.thucduong@gmail.com" },
};

/** bank_accounts. Lan and Minh have not added one yet. */
const bankAccounts = new Map<string, BankAccount>([
  ["u_chef_tam", { bankName: "Vietcombank", accountNumber: "0071000456789", accountHolder: "LE QUANG TAM" }],
  ["u_thu_ha", { bankName: "Techcombank", accountNumber: "19034567891012", accountHolder: "PHAM THU HA" }],
  ["u_chef_chau", { bankName: "BIDV", accountNumber: "31410001234567", accountHolder: "TON NU MINH CHAU" }],
  ["u_chef_khoa", { bankName: "MB Bank", accountNumber: "0801234567890", accountHolder: "NGUYEN DANG KHOA" }],
]);

/* ---------------------------------------------------------- withdrawals */

let bankRefSeq = 120;
/** Bank transfer reference of an automatic payout: "FT" + yyMMdd + 6 digits. */
const autoRef = (at: number) => `FT${yymmdd(at)}${String(++bankRefSeq).padStart(6, "0")}`;

interface Spec {
  id: string;
  chefId: keyof typeof CHEFS;
  amount: number;
  created: number;
  status: WithdrawalStatus;
  /** Completed / Rejected: minutes after the request. */
  processedAfterMin?: number;
  processedBy?: string;
  reason?: string;
}

function build(spec: Spec): WithdrawalRequest {
  const account = bankAccounts.get(spec.chefId);
  if (!account) throw new Error(`mock_payouts: ${spec.chefId} has no bank account`);
  const requiresApproval = spec.amount > AUTO_APPROVE_LIMIT;
  const processedAt = spec.status === "Processing" ? null : spec.created + (spec.processedAfterMin ?? 5) * MIN;
  return {
    id: spec.id,
    chefId: spec.chefId,
    chef: { ...CHEFS[spec.chefId] },
    amount: spec.amount,
    status: spec.status,
    bankAccount: { ...account },
    createdAt: iso(spec.created),
    requiresApproval,
    autoApproveAt: requiresApproval ? null : iso(spec.created + AUTO_PAYOUT_DELAY),
    processedAt: processedAt === null ? null : iso(processedAt),
    processedBy: spec.processedBy ?? null,
    transactionRef: spec.status === "Completed" && processedAt !== null ? autoRef(processedAt) : null,
    reason: spec.reason ?? null,
  };
}

const withdrawals: WithdrawalRequest[] = (
  [
    // Lê Quang Tâm — the first two mirror the mobile seeds (wd_tam_1, wd_tam_2).
    {
      id: "wd_tam_1",
      chefId: "u_chef_tam",
      amount: 2_000_000,
      created: NOW - 30 * DAY,
      status: "Rejected",
      processedAfterMin: 1,
      reason: "Số dư có thể rút lúc gửi yêu cầu chưa đủ 2.000.000đ.",
    },
    { id: "wd_tam_2", chefId: "u_chef_tam", amount: 1_000_000, created: NOW - 17 * DAY, status: "Completed", processedAfterMin: 120 },
    { id: "wd_tam_3", chefId: "u_chef_tam", amount: 5_100_000, created: NOW - 3 * HOUR - 12 * MIN, status: "Processing" },
    // ThS. DD Phạm Thu Hà
    {
      id: "wd_ha_1",
      chefId: "u_thu_ha",
      amount: 600_000,
      created: NOW - 20 * DAY,
      status: "Rejected",
      processedAfterMin: 3,
      processedBy: "Trần Thu Hằng",
      reason: "Ngân hàng báo sai tên chủ tài khoản. Tiền đã trở lại ví, nhờ chuyên gia cập nhật tài khoản nhận.",
    },
    { id: "wd_ha_2", chefId: "u_thu_ha", amount: 1_000_000, created: thisMonth(2), status: "Completed" },
    { id: "wd_ha_3", chefId: "u_thu_ha", amount: 400_000, created: NOW - 2 * MIN, status: "Processing" },
    // Tôn Nữ Minh Châu
    {
      id: "wd_chau_1",
      chefId: "u_chef_chau",
      amount: 800_000,
      created: NOW - 12 * DAY,
      status: "Rejected",
      processedAfterMin: 4,
      processedBy: "Lê Minh Quân",
      reason: "Tên chủ tài khoản không khớp hồ sơ chuyên gia. Đã nhờ chuyên gia cập nhật trước khi gửi lại.",
    },
    { id: "wd_chau_2", chefId: "u_chef_chau", amount: 1_200_000, created: thisMonth(3), status: "Completed" },
  ] satisfies Spec[]
).map(build);

/** Automatic payout of small requests, applied lazily on every read and write. */
function settle(now: number) {
  for (const w of withdrawals) {
    if (w.status !== "Processing" || w.autoApproveAt === null) continue;
    const at = Date.parse(w.autoApproveAt);
    if (at > now) continue;
    w.status = "Completed";
    w.processedAt = w.autoApproveAt;
    w.processedBy = null;
    w.transactionRef = autoRef(at);
  }
}

const copy = (w: WithdrawalRequest): WithdrawalRequest => ({ ...w, chef: { ...w.chef }, bankAccount: { ...w.bankAccount } });

/* ------------------------------------------------------------- earnings */

interface Earning {
  chefId: string;
  orderId: string;
  serviceTitle: string;
  buyerName: string;
  transactionRef: string;
  gross: number;
  paidAt: number;
  status: Extract<LedgerStatus, "Pending" | "Available" | "Reversed">;
  refundedAt: number | null;
}

/** Older sales of Tâm that only the mobile mock has (see the header). */
const WALLET_ONLY_SALES: Omit<Earning, "status" | "refundedAt">[] = [
  {
    chefId: "u_chef_tam",
    orderId: "od_tam_vip_han",
    serviceTitle: "Thực đơn VIP 30 ngày cho gia đình",
    buyerName: "Gia Hân",
    gross: 1_500_000,
    paidAt: NOW - 25 * DAY,
    transactionRef: `VL${yymmdd(NOW - 25 * DAY)}9001`,
  },
  {
    chefId: "u_chef_tam",
    orderId: "od_tam_course_viet",
    serviceTitle: "Khoá meal prep chay 4 tuần",
    buyerName: "Quốc Việt",
    gross: 990_000,
    paidAt: NOW - 40 * DAY,
    transactionRef: `VL${yymmdd(NOW - 40 * DAY)}9002`,
  },
];

const ALL_ORDERS = { status: "all", type: "all", search: "" } as const;

function earningsFrom(orders: AdminOrder[], now: number): Earning[] {
  const list: Earning[] = WALLET_ONLY_SALES.map((s) => ({
    ...s,
    status: s.paidAt + PACKAGE_HOLD_DAYS * DAY <= now ? "Available" : "Pending",
    refundedAt: null,
  }));
  for (const o of orders) {
    if (o.status !== "Paid" && o.status !== "Refunded") continue;
    const paid = o.payments.find((p) => p.paidAt !== null);
    if (!paid?.paidAt) continue;
    const paidAt = Date.parse(paid.paidAt);
    const c = o.consultation;
    const releasedAt =
      o.service.type === "Consult"
        ? c?.status === "Completed"
          ? Date.parse(c.startAt) + (c.durationMinutes ?? 60) * MIN
          : null
        : paidAt + PACKAGE_HOLD_DAYS * DAY;
    list.push({
      chefId: o.service.chefId,
      orderId: o.id,
      serviceTitle: o.service.title,
      buyerName: o.buyer.fullName,
      transactionRef: paid.transactionRef,
      gross: o.amount,
      paidAt,
      status: o.status === "Refunded" ? "Reversed" : releasedAt !== null && releasedAt <= now ? "Available" : "Pending",
      refundedAt: o.status === "Refunded" ? (o.resolution ? Date.parse(o.resolution.at) : Math.min(now, paidAt + DAY)) : null,
    });
  }
  return list;
}

const net = (e: Pick<Earning, "gross">) => e.gross - platformFee(e.gross);
const sum = (values: number[]) => values.reduce((a, b) => a + b, 0);

function walletOf(chefId: string, earnings: Earning[]): ChefWallet {
  const mine = earnings.filter((e) => e.chefId === chefId);
  const live = mine.filter((e) => e.status !== "Reversed");
  const requests = withdrawals.filter((w) => w.chefId === chefId);
  const released = sum(mine.filter((e) => e.status === "Available").map(net));
  const completed = requests.filter((w) => w.status === "Completed");
  const withdrawn = sum(completed.map((w) => w.amount));
  const processing = sum(requests.filter((w) => w.status === "Processing").map((w) => w.amount));
  const lastPaid = completed.map((w) => w.processedAt ?? w.createdAt).sort().at(-1) ?? null;
  const account = bankAccounts.get(chefId);
  return {
    chefId,
    chef: { ...CHEFS[chefId] },
    available: released - withdrawn - processing,
    pending: sum(mine.filter((e) => e.status === "Pending").map(net)),
    processing,
    withdrawn,
    grossSales: sum(live.map((e) => e.gross)),
    feeTotal: sum(live.map((e) => platformFee(e.gross))),
    bankAccount: account ? { ...account } : null,
    lastWithdrawalAt: lastPaid,
  };
}

/* ----------------------------------------------------------------- reads */

const fold = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[Đđ]/g, "d").toLowerCase();
const hasFail = (text: string) => text.toLowerCase().includes("#fail");
const unavailable = (what: string) => new ApiError(`Máy chủ đang bận, chưa ${what}. Thử lại sau.`, 503, "unavailable");

const maskAccount = (number: string) => (number.length <= 4 ? number : `•••• ${number.slice(-4)}`);

export async function listWithdrawals(query: WithdrawalQuery): Promise<WithdrawalRequest[]> {
  await sleep(400);
  if (hasFail(query.search)) throw unavailable("tải được yêu cầu rút tiền");
  settle(Date.now());
  const q = fold(query.search.trim());
  return withdrawals
    .filter((w) => w.status === query.status)
    .filter(
      (w) =>
        !q ||
        fold(
          [w.id, w.chef.fullName, w.chef.email, w.bankAccount.bankName, w.bankAccount.accountNumber, w.bankAccount.accountHolder, w.transactionRef ?? ""].join(" "),
        ).includes(q),
    )
    .sort((a, b) =>
      query.status === "Processing"
        ? // The admin queue first (needs approval), then oldest first.
          Number(b.requiresApproval) - Number(a.requiresApproval) || a.createdAt.localeCompare(b.createdAt)
        : (b.processedAt ?? b.createdAt).localeCompare(a.processedAt ?? a.createdAt),
    )
    .map(copy);
}

export async function listChefWallets(): Promise<ChefWallet[]> {
  const [orders] = await Promise.all([listOrders(ALL_ORDERS), sleep(150)]);
  const now = Date.now();
  settle(now);
  const earnings = earningsFrom(orders, now);
  return Object.keys(CHEFS)
    .map((id) => walletOf(id, earnings))
    .sort((a, b) => b.available + b.processing - (a.available + a.processing) || a.chef.fullName.localeCompare(b.chef.fullName, "vi"));
}

export async function listWalletTransactions(chefId: string, limit: number): Promise<WalletTransaction[]> {
  if (!CHEFS[chefId]) {
    await sleep(200);
    throw new ApiError("Không tìm thấy ví của chuyên gia.", 404, "not_found");
  }
  const [orders] = await Promise.all([listOrders(ALL_ORDERS), sleep(150)]);
  const now = Date.now();
  settle(now);
  const rows: WalletTransaction[] = [];
  for (const e of earningsFrom(orders, now).filter((x) => x.chefId === chefId)) {
    const common = { orderId: e.orderId, transactionRef: e.transactionRef, serviceTitle: e.serviceTitle, buyerName: e.buyerName, bankName: null, note: null };
    rows.push({ id: `tx_in_${e.orderId}`, type: "Income", status: e.status, createdAt: iso(e.paidAt), gross: e.gross, fee: platformFee(e.gross), net: net(e), ...common });
    if (e.refundedAt !== null) {
      rows.push({
        id: `tx_rf_${e.orderId}`,
        type: "Refund",
        status: "Reversed",
        createdAt: iso(e.refundedAt),
        gross: -e.gross,
        fee: -platformFee(e.gross),
        net: -net(e),
        ...common,
      });
    }
  }
  for (const w of withdrawals.filter((x) => x.chefId === chefId)) {
    rows.push({
      id: `tx_wd_${w.id}`,
      type: "Withdrawal",
      status: w.status,
      createdAt: w.createdAt,
      net: -w.amount,
      orderId: null,
      transactionRef: w.transactionRef,
      serviceTitle: null,
      buyerName: null,
      gross: null,
      fee: null,
      bankName: `${w.bankAccount.bankName} ${maskAccount(w.bankAccount.accountNumber)}`,
      note: w.reason,
    });
  }
  return rows.sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, Math.max(1, limit));
}

export async function getPayoutSummary(): Promise<PayoutSummary> {
  const [orders] = await Promise.all([listOrders(ALL_ORDERS), sleep(150)]);
  const now = Date.now();
  settle(now);
  const earnings = earningsFrom(orders, now);
  const wallets = Object.keys(CHEFS).map((id) => walletOf(id, earnings));
  const monthStart = new Date(new Date(now).getFullYear(), new Date(now).getMonth(), 1).getTime();
  const paidThisMonth = withdrawals.filter((w) => w.status === "Completed" && w.processedAt !== null && Date.parse(w.processedAt) >= monthStart);
  const awaiting = withdrawals.filter((w) => w.status === "Processing" && w.requiresApproval);
  const paidOrders = orders.filter((o) => o.status === "Paid");
  const paidGross = sum(paidOrders.map((o) => o.amount));
  const byStatus = Object.fromEntries(WITHDRAWAL_STATUSES.map((s) => [s, withdrawals.filter((w) => w.status === s).length])) as Record<
    WithdrawalStatus,
    number
  >;
  return {
    totalAvailable: sum(wallets.map((w) => w.available)),
    totalPending: sum(wallets.map((w) => w.pending)),
    totalProcessing: sum(wallets.map((w) => w.processing)),
    paidOutThisMonth: sum(paidThisMonth.map((w) => w.amount)),
    paidOutThisMonthCount: paidThisMonth.length,
    platformFee: sum(paidOrders.map((o) => platformFee(o.amount))),
    paidGross,
    paidOrderCount: paidOrders.length,
    feeRate: PLATFORM_FEE_RATE,
    autoApproveLimit: AUTO_APPROVE_LIMIT,
    byStatus,
    awaitingApproval: awaiting.length,
    awaitingApprovalAmount: sum(awaiting.map((w) => w.amount)),
  };
}

/* ---------------------------------------------------------------- writes */

const TRANSFER_REF_PATTERN = new RegExp(`^[A-Za-z0-9._/-]{${TRANSFER_REF_MIN},${TRANSFER_REF_MAX}}$`);

/**
 * Complete (Processing only): Completed with the admin's bank transfer reference.
 * Reject (Processing only): Rejected with a reason ≥ 10 chars; the amount returns to "Có thể rút".
 */
export async function applyWithdrawalAction(input: WithdrawalActionInput, session: AdminSession | null): Promise<WithdrawalRequest> {
  await sleep(700);
  const now = Date.now();
  settle(now);
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
    logAction(actor, "xác nhận đã chuyển tiền rút", `${w.chef.fullName} · ${vnd(w.amount)} · ${w.transactionRef}`);
  } else {
    w.status = "Rejected";
    w.reason = input.reason.trim();
    logAction(actor, "từ chối yêu cầu rút tiền", `${w.chef.fullName} · ${vnd(w.amount)}`);
  }
  return copy(w);
}
