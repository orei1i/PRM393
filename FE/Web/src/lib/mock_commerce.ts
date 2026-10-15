// src/lib/mock_commerce.ts
// In-memory orders / payments / access_grants / services for /orders.
// Ids and titles mirror the mobile commerce seeds where they overlap: Lê Quang Tâm's
// services (svc_tam_*), Minh Anh's orders (cs_seed_1, cs_seed_2, the pending VIP Menu
// of Thu Hà, Tâm's paid course) and Tâm's bookings (Hoàng Nam, Thảo Vy, Ngọc Trâm, Đức Huy).
// Payment and grant expiry are derived at read time, so a QR created a few minutes
// ago turns "Hết hạn" on its own while the page is open.
import type { AdminSession } from "@/types/admin";
import type {
  AccessGrant,
  AdminOrder,
  AdminService,
  CommerceSummary,
  ConsultationStatus,
  OrderAction,
  OrderActionInput,
  OrderQuery,
  OrderStatus,
  Payment,
  PaymentStatus,
  ServiceQuery,
  ServiceType,
} from "@/types/commerce";
import { ORDER_STATUSES } from "@/types/commerce";
import { MIN_AUDIT_NOTE_LENGTH } from "@/types/moderation";

import { ApiError } from "./api_error";
import { logAction } from "./mock_admin";
import { sleep } from "./mock_data";

const MIN = 60_000;
const DAY = 24 * 60 * MIN;
const NOW = Date.now();
const iso = (ms: number) => new Date(ms).toISOString();
const minutesAgo = (m: number) => NOW - m * MIN;
const daysAgo = (d: number) => NOW - d * DAY;

/** Local wall-clock time `days` from today, e.g. atLocal(2, 19, 30) = the day after tomorrow at 19:30. */
function atLocal(days: number, hour: number, minute = 0) {
  const d = new Date(NOW);
  d.setDate(d.getDate() + days);
  d.setHours(hour, minute, 0, 0);
  return d.getTime();
}

const QR_BASE = "https://pay.veganlife.vn/mock/qr";
const QR_TTL_MIN = 15;
/** access_grants rule (BE business rule, mirrored from the mobile mock). */
const GRANT_DAYS: Record<Exclude<ServiceType, "Consult">, number> = { Course: 180, "VIP Menu": 30 };

/* ---------------------------------------------------------------- people */

const PEOPLE = {
  u_me: ["Minh Anh", "minhanh.nguyen@gmail.com"],
  u_hoang_nam: ["Hoàng Nam", "hoangnam.dev@gmail.com"],
  u_thao_vy: ["Thảo Vy", "thaovy.nguyen@gmail.com"],
  u_ngoc_tram: ["Ngọc Trâm", "ngoctram.k17@gmail.com"],
  u_duc_huy: ["Đức Huy", "duchuy.q9@gmail.com"],
  u_bep_may: ["Bếp Chay Nhà Mây", "bepchaynhamay@gmail.com"],
  u_new_1: ["Phan Gia Bảo", "giabao.chef@gmail.com"],
  u_new_2: ["Lý Thanh Trúc", "thanhtruc.dietitian@gmail.com"],
  u_new_3: ["Đỗ Hải Yến", "haiyen.mebe@gmail.com"],
  u_gen_0: ["Nguyễn Thị An", "nguyen.thi.an0@gmail.com"],
  u_gen_1: ["Vũ Ngọc Linh", "vu.ngoc.linh1@gmail.com"],
  u_gen_2: ["Dương Bảo Chi", "duong.bao.chi2@gmail.com"],
  u_gen_3: ["Phan Thu Phúc", "phan.thu.phuc3@gmail.com"],
  u_gen_4: ["Ngô Minh Giang", "ngo.minh.giang4@gmail.com"],
  u_gen_6: ["Hồ Quốc Khánh", "ho.quoc.khanh6@gmail.com"],
} as const satisfies Record<string, readonly [string, string]>;
type PersonId = keyof typeof PEOPLE;

/* -------------------------------------------------------------- services */

interface ServiceRow {
  id: string;
  chefId: string;
  chefName: string;
  title: string;
  type: ServiceType;
  price: number;
  durationMinutes: number | null;
}

const CHEFS = {
  u_chef_tam: "Lê Quang Tâm",
  u_thu_ha: "ThS. DD Phạm Thu Hà",
  u_chef_chau: "Tôn Nữ Minh Châu",
  u_chef_khoa: "Nguyễn Đăng Khoa",
  u_chef_lan: "Võ Thị Ngọc Lan",
  u_chef_minh: "Trần Quốc Minh",
} as const;

function svc(id: string, chefId: keyof typeof CHEFS, title: string, type: ServiceType, price: number, durationMinutes: number | null = null): ServiceRow {
  return { id, chefId, chefName: CHEFS[chefId], title, type, price, durationMinutes };
}

const services: ServiceRow[] = [
  svc("svc_tam_consult", "u_chef_tam", "Tư vấn thực đơn gia đình 7 ngày", "Consult", 350_000, 60),
  svc("svc_tam_course", "u_chef_tam", "Khoá meal prep chay 4 tuần", "Course", 990_000),
  svc("svc_tam_vip", "u_chef_tam", "Thực đơn VIP 30 ngày cho gia đình", "VIP Menu", 1_500_000),
  svc("svc_ha_quick", "u_thu_ha", "Tư vấn nhanh 30 phút", "Consult", 450_000, 30),
  svc("svc_ha_plan", "u_thu_ha", "Đánh giá dinh dưỡng & kế hoạch 4 tuần", "Consult", 850_000, 75),
  svc("svc_ha_vip", "u_thu_ha", "Thực đơn VIP giảm cân lành mạnh 30 ngày", "VIP Menu", 1_200_000),
  svc("svc_chau_party", "u_chef_chau", "Lên thực đơn tiệc chay 10 món", "Consult", 900_000, 90),
  svc("svc_chau_class", "u_chef_chau", "Lớp nấu chay Huế 1 kèm 1", "Consult", 500_000, 120),
  svc("svc_chau_course", "u_chef_chau", "Khoá chay cung đình Huế online 6 buổi", "Course", 1_800_000),
  svc("svc_khoa_macro", "u_chef_khoa", "Tính macro & thực đơn tăng cơ", "Consult", 300_000, 45),
  svc("svc_khoa_course", "u_chef_khoa", "Khoá tăng cơ thuần chay 8 tuần", "Course", 1_290_000),
  svc("svc_lan_baby", "u_chef_lan", "Thực đơn ăn dặm 4 tuần", "Consult", 400_000, 60),
  svc("svc_lan_vip", "u_chef_lan", "Thực đơn VIP mẹ bầu 30 ngày", "VIP Menu", 950_000),
  svc("svc_minh_ferment", "u_chef_minh", "Lên men tại nhà cho người mới", "Consult", 280_000, 60),
  svc("svc_minh_course", "u_chef_minh", "Khoá thực dưỡng căn bản 4 tuần", "Course", 690_000),
];

const findService = (id: string) => {
  const s = services.find((x) => x.id === id);
  if (!s) throw new Error(`mock_commerce: unknown service ${id}`);
  return s;
};

/* ---------------------------------------------------------------- orders */

const pad2 = (n: number) => String(n).padStart(2, "0");
const refSeqByDay = new Map<string, number>();

/** transactionRef = "VL" + yyMMdd + 4-digit daily sequence (same rule as the mobile mock). */
function nextRef(at: number) {
  const d = new Date(at);
  const day = `${String(d.getFullYear()).slice(2)}${pad2(d.getMonth() + 1)}${pad2(d.getDate())}`;
  const seq = (refSeqByDay.get(day) ?? 0) + 1;
  refSeqByDay.set(day, seq);
  return `VL${day}${String(seq).padStart(4, "0")}`;
}

let paymentSeq = 900;
let grantSeq = 70;

function makePayment(orderId: string, at: number, amount: number, status: PaymentStatus, paidAt: number | null = null): Payment {
  const ref = nextRef(at);
  return {
    id: `pay_${++paymentSeq}`,
    orderId,
    provider: "PaymentOS",
    transactionRef: ref,
    qrCodeUrl: `${QR_BASE}/${ref}.png`,
    status,
    amount,
    paidAt: paidAt === null ? null : iso(paidAt),
    expiresAt: iso(at + QR_TTL_MIN * MIN),
    createdAt: iso(at),
  };
}

interface Spec {
  id: string;
  buyer: PersonId;
  service: string;
  status: OrderStatus;
  created: number;
  /** Consult only: appointment time and consultation status. */
  start?: number;
  consult?: ConsultationStatus;
  consultId?: string;
  /** An earlier payment attempt that failed or expired before the current one. */
  retry?: "Failed" | "Expired";
  /** Cancelled orders: the last payment failed (default: the QR expired). */
  lastPayment?: "Failed";
  resolution?: { action: OrderAction; note: string; by: string; afterMin: number };
}

function build(spec: Spec): AdminOrder {
  const service = findService(spec.service);
  const [fullName, email] = PEOPLE[spec.buyer];
  const amount = service.price;
  const payments: Payment[] = [];
  let payAt = spec.created + MIN / 2;
  if (spec.retry) {
    payments.push(makePayment(spec.id, payAt, amount, spec.retry));
    payAt = Math.min(spec.created + 20 * MIN, NOW - 3 * MIN);
  }

  let grant: AccessGrant | null = null;
  const paidAt = payAt + 2 * MIN;
  switch (spec.status) {
    case "Paid":
    case "Refunded": {
      const payment = makePayment(spec.id, payAt, amount, spec.status === "Paid" ? "Paid" : "Refunded", paidAt);
      payments.push(payment);
      const expiresAt =
        service.type === "Consult" ? (spec.start ?? paidAt) + DAY : paidAt + GRANT_DAYS[service.type] * DAY;
      grant = {
        id: `ag_${++grantSeq}`,
        paymentId: payment.id,
        grantedAt: iso(paidAt),
        expiresAt: iso(expiresAt),
        status: spec.status === "Paid" ? "Active" : "Revoked",
      };
      break;
    }
    case "Pending":
      payments.push(makePayment(spec.id, payAt, amount, "Pending"));
      break;
    case "Cancelled":
      payments.push(makePayment(spec.id, payAt, amount, spec.lastPayment ?? "Expired"));
      break;
  }

  const defaultConsult: Record<OrderStatus, ConsultationStatus> = {
    Pending: "AwaitingPayment",
    Paid: "Pending",
    Cancelled: "Cancelled",
    Refunded: "Cancelled",
  };

  return {
    id: spec.id,
    userId: spec.buyer,
    buyer: { id: spec.buyer, fullName, email },
    serviceId: service.id,
    service: { id: service.id, title: service.title, type: service.type, chefId: service.chefId, chefName: service.chefName },
    amount,
    status: spec.status,
    createdAt: iso(spec.created),
    payments,
    accessGrant: grant,
    consultation:
      service.type === "Consult"
        ? {
            id: spec.consultId ?? `cs_${spec.id.replace(/^ord_/, "")}`,
            startAt: iso(spec.start ?? spec.created + 3 * DAY),
            status: spec.consult ?? defaultConsult[spec.status],
            durationMinutes: service.durationMinutes,
          }
        : null,
    resolution: spec.resolution
      ? { action: spec.resolution.action, note: spec.resolution.note, by: spec.resolution.by, at: iso(spec.created + spec.resolution.afterMin * MIN) }
      : null,
  };
}

const SPECS: Spec[] = [
  // Minh Anh (mirrors the mobile buyer seeds)
  { id: "ord_501", buyer: "u_me", service: "svc_ha_plan", status: "Paid", created: daysAgo(1), start: atLocal(2, 19, 30), consult: "Confirmed", consultId: "cs_seed_1" },
  { id: "ord_502", buyer: "u_me", service: "svc_tam_consult", status: "Paid", created: daysAgo(13), start: atLocal(-10, 9), consult: "Completed", consultId: "cs_seed_2" },
  { id: "ord_503", buyer: "u_me", service: "svc_ha_vip", status: "Pending", created: minutesAgo(6) },
  { id: "ord_504", buyer: "u_me", service: "svc_tam_course", status: "Paid", created: daysAgo(20) },
  // Lê Quang Tâm (mirrors the chef-studio seeds)
  { id: "ord_505", buyer: "u_hoang_nam", service: "svc_tam_consult", status: "Paid", created: minutesAgo(180), start: atLocal(2, 14), consult: "Pending" },
  { id: "ord_506", buyer: "u_thao_vy", service: "svc_tam_consult", status: "Paid", created: daysAgo(2), start: NOW + 10 * MIN, consult: "Confirmed" },
  { id: "ord_507", buyer: "u_ngoc_tram", service: "svc_tam_consult", status: "Paid", created: daysAgo(12), start: atLocal(-10, 19, 30), consult: "Completed" },
  { id: "ord_508", buyer: "u_duc_huy", service: "svc_tam_course", status: "Paid", created: daysAgo(6) },
  { id: "ord_509", buyer: "u_new_1", service: "svc_tam_vip", status: "Paid", created: daysAgo(45) },
  { id: "ord_510", buyer: "u_new_2", service: "svc_tam_vip", status: "Paid", created: daysAgo(8) },
  { id: "ord_511", buyer: "u_gen_0", service: "svc_tam_consult", status: "Refunded", created: daysAgo(5), start: atLocal(1, 9), consult: "Declined" },
  { id: "ord_512", buyer: "u_gen_1", service: "svc_tam_consult", status: "Cancelled", created: daysAgo(4), start: atLocal(-1, 19, 30) },
  { id: "ord_513", buyer: "u_bep_may", service: "svc_tam_course", status: "Pending", created: minutesAgo(25), retry: "Failed" },
  // ThS. DD Phạm Thu Hà
  { id: "ord_514", buyer: "u_hoang_nam", service: "svc_ha_quick", status: "Paid", created: daysAgo(9), start: atLocal(-7, 20), consult: "Completed" },
  { id: "ord_515", buyer: "u_new_3", service: "svc_ha_plan", status: "Paid", created: daysAgo(1), start: atLocal(3, 9), consult: "Pending" },
  { id: "ord_516", buyer: "u_gen_2", service: "svc_ha_vip", status: "Paid", created: daysAgo(15) },
  {
    id: "ord_517",
    buyer: "u_gen_3",
    service: "svc_ha_quick",
    status: "Refunded",
    created: daysAgo(6),
    start: atLocal(-2, 14),
    consult: "Cancelled",
    resolution: { action: "refund", note: "Khách báo trùng lịch công tác, chuyên gia đồng ý hoàn tiền.", by: "Lê Minh Quân", afterMin: 26 * 60 },
  },
  {
    id: "ord_518",
    buyer: "u_gen_4",
    service: "svc_ha_vip",
    status: "Cancelled",
    created: daysAgo(2),
    resolution: { action: "cancel", note: "Khách đặt nhầm gói, yêu cầu huỷ để đặt lại gói khác.", by: "Trần Thu Hằng", afterMin: 40 },
  },
  { id: "ord_519", buyer: "u_thao_vy", service: "svc_ha_plan", status: "Pending", created: minutesAgo(120), start: atLocal(4, 19, 30) },
  // Tôn Nữ Minh Châu
  { id: "ord_520", buyer: "u_new_2", service: "svc_chau_party", status: "Paid", created: daysAgo(4), start: atLocal(5, 19, 30), consult: "Confirmed" },
  { id: "ord_521", buyer: "u_gen_6", service: "svc_chau_course", status: "Paid", created: daysAgo(30) },
  { id: "ord_522", buyer: "u_duc_huy", service: "svc_chau_class", status: "Paid", created: daysAgo(3), start: NOW - 20 * MIN, consult: "InProgress" },
  { id: "ord_523", buyer: "u_ngoc_tram", service: "svc_chau_course", status: "Cancelled", created: daysAgo(1), lastPayment: "Failed" },
  // Nguyễn Đăng Khoa
  { id: "ord_524", buyer: "u_hoang_nam", service: "svc_khoa_course", status: "Paid", created: daysAgo(50) },
  { id: "ord_525", buyer: "u_gen_1", service: "svc_khoa_macro", status: "Paid", created: daysAgo(2), start: atLocal(1, 19, 30), consult: "Pending" },
  { id: "ord_526", buyer: "u_new_1", service: "svc_khoa_macro", status: "Refunded", created: daysAgo(3), start: atLocal(2, 9), consult: "Declined" },
  { id: "ord_527", buyer: "u_gen_2", service: "svc_khoa_course", status: "Pending", created: minutesAgo(8) },
  // Võ Thị Ngọc Lan
  { id: "ord_528", buyer: "u_new_3", service: "svc_lan_vip", status: "Paid", created: daysAgo(10) },
  { id: "ord_529", buyer: "u_gen_0", service: "svc_lan_baby", status: "Paid", created: daysAgo(20), start: atLocal(-18, 9), consult: "Completed" },
  // Trần Quốc Minh (svc_minh_course has no orders yet)
  { id: "ord_530", buyer: "u_gen_4", service: "svc_minh_ferment", status: "Paid", created: daysAgo(7), start: atLocal(-5, 14), consult: "Completed" },
  { id: "ord_531", buyer: "u_gen_6", service: "svc_minh_ferment", status: "Cancelled", created: daysAgo(9), start: atLocal(-6, 9), retry: "Expired" },
];

const orders: AdminOrder[] = SPECS.map(build);

/* ----------------------------------------------------------------- reads */

const fold = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[Đđ]/g, "d").toLowerCase();

const isPast = (at: string | null, now: number) => at !== null && Date.parse(at) < now;

/** Copy of a stored order with time-derived statuses (QR expiry, grant expiry). */
function view(o: AdminOrder, now = Date.now()): AdminOrder {
  return {
    ...o,
    buyer: { ...o.buyer },
    service: { ...o.service },
    payments: o.payments.map((p) => ({ ...p, status: p.status === "Pending" && isPast(p.expiresAt, now) ? "Expired" : p.status })),
    accessGrant: o.accessGrant && {
      ...o.accessGrant,
      status: o.accessGrant.status === "Active" && isPast(o.accessGrant.expiresAt, now) ? "Expired" : o.accessGrant.status,
    },
    consultation: o.consultation && { ...o.consultation },
    resolution: o.resolution && { ...o.resolution },
  };
}

const failIfAsked = (text: string, what: string) => {
  if (text.toLowerCase().includes("#fail")) {
    throw new ApiError(`Máy chủ đang bận, chưa ${what}. Thử lại sau.`, 503, "unavailable");
  }
};

export async function listOrders(query: OrderQuery): Promise<AdminOrder[]> {
  await sleep(450);
  failIfAsked(query.search, "tải được đơn hàng");
  const q = fold(query.search.trim());
  return orders
    .filter((o) => query.status === "all" || o.status === query.status)
    .filter((o) => query.type === "all" || o.service.type === query.type)
    .filter(
      (o) =>
        !q ||
        fold(
          [o.id, o.buyer.fullName, o.buyer.email, o.service.chefName, o.service.title, ...o.payments.map((p) => p.transactionRef)].join(" "),
        ).includes(q),
    )
    .sort((x, y) => y.createdAt.localeCompare(x.createdAt))
    .map((o) => view(o));
}

export async function getOrder(id: string): Promise<AdminOrder> {
  await sleep(300);
  const order = orders.find((o) => o.id === id);
  if (!order) throw new ApiError("Đơn hàng không còn tồn tại.", 404, "not_found");
  return view(order);
}

export async function getSummary(): Promise<CommerceSummary> {
  await sleep(300);
  const now = Date.now();
  const byStatus = Object.fromEntries(ORDER_STATUSES.map((s) => [s, 0])) as Record<OrderStatus, number>;
  let revenue = 0;
  let refundedAmount = 0;
  let pendingAmount = 0;
  let activeGrants = 0;
  for (const o of orders) {
    byStatus[o.status] += 1;
    if (o.status === "Paid") revenue += o.amount;
    if (o.status === "Refunded") refundedAmount += o.amount;
    if (o.status === "Pending") pendingAmount += o.amount;
    if (o.accessGrant?.status === "Active" && !isPast(o.accessGrant.expiresAt, now)) activeGrants += 1;
  }
  return { revenue, refundedAmount, pendingAmount, totalOrders: orders.length, byStatus, activeGrants };
}

export async function listServices(query: ServiceQuery): Promise<AdminService[]> {
  await sleep(400);
  failIfAsked(query.search, "tải được danh sách dịch vụ");
  const q = fold(query.search.trim());
  return services
    .filter((s) => query.chefId === "all" || s.chefId === query.chefId)
    .filter((s) => !q || fold(`${s.title} ${s.chefName}`).includes(q))
    .map((s) => {
      const mine = orders.filter((o) => o.serviceId === s.id);
      const paid = mine.filter((o) => o.status === "Paid");
      return {
        id: s.id,
        chefId: s.chefId,
        chefName: s.chefName,
        title: s.title,
        type: s.type,
        price: s.price,
        orderCount: mine.length,
        paidCount: paid.length,
        revenue: paid.reduce((sum, o) => sum + o.amount, 0),
      };
    })
    .sort((x, y) => x.chefName.localeCompare(y.chefName, "vi") || y.revenue - x.revenue || x.title.localeCompare(y.title, "vi"));
}

/* ---------------------------------------------------------------- writes */

/**
 * Refund (Paid only): order Refunded, paid payment Refunded, grant Revoked, consultation
 * Cancelled (a Completed one stays Completed). Cancel (Pending only): order Cancelled,
 * open QR codes Expired, consultation Cancelled. Status change only — no money moves.
 */
export async function applyOrderAction(input: OrderActionInput, session: AdminSession | null): Promise<AdminOrder> {
  await sleep(700);
  const note = input.note.trim();
  if (note.length < MIN_AUDIT_NOTE_LENGTH) {
    throw new ApiError(`Ghi chú cần ít nhất ${MIN_AUDIT_NOTE_LENGTH} ký tự.`, 400, "note_too_short");
  }
  failIfAsked(note, input.action === "refund" ? "hoàn tiền được đơn" : "huỷ được đơn");
  const order = orders.find((o) => o.id === input.orderId);
  if (!order) throw new ApiError("Đơn hàng không còn tồn tại.", 404, "not_found");

  const now = Date.now();
  const actor = session?.fullName ?? "Quản trị viên";
  if (input.action === "refund") {
    if (order.status !== "Paid") {
      throw new ApiError("Chỉ hoàn tiền được đơn đang ở trạng thái “Đã thanh toán”.", 409, "not_paid");
    }
    order.status = "Refunded";
    for (const p of order.payments) if (p.status === "Paid") p.status = "Refunded";
    if (order.accessGrant) order.accessGrant.status = "Revoked";
    if (order.consultation && order.consultation.status !== "Completed") order.consultation.status = "Cancelled";
  } else {
    if (order.status !== "Pending") {
      throw new ApiError("Chỉ huỷ được đơn đang chờ thanh toán.", 409, "not_pending");
    }
    order.status = "Cancelled";
    for (const p of order.payments) if (p.status === "Pending") p.status = "Expired";
    if (order.consultation) order.consultation.status = "Cancelled";
  }
  order.resolution = { action: input.action, note, by: actor, at: iso(now) };
  logAction(actor, input.action === "refund" ? "hoàn tiền đơn hàng" : "huỷ đơn hàng", `${order.id} · ${order.service.title}`);
  return view(order, now);
}
