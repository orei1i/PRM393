// src/lib/mock_bookings.ts
// In-memory chef meal-plan bookings for /disputes, and the source of truth that /orders
// (mock_commerce.ts) and /payouts (mock_payouts.ts) derive from: offers, contracts, booking
// orders + PaymentOS payments, escrow holds, plan days, chat and complaints.
//
// Seed ids mirror the mobile MockBookingDb (plan P5): Minh Anh (u_me) — b_ma_tam_nego (Tâm,
// 10 ngày có phản hồi, chef offer 1.500.000đ open), b_ma_thuha_active (Thu Hà, 7 ngày giao một
// lần, paid, all days sent, day 3 is today), b_ma_tam_done (Tâm, 5 ngày, released 2 days ago).
// Lê Quang Tâm (u_chef_tam) — b_nam_tam_req (Hoàng Nam, Requested), b_vy_tam_active (Thảo Vy,
// today's day still a draft), b_tram_tam + cp_tram_tam (Ngọc Trâm, health_risk, 1 link + 1 image,
// Frozen), b_han_tam_done (Gia Hân, released). Other chefs' rows are web-only (the stores are
// independent, only ids are aligned).
//
// Dates are relative to "today" in Asia/Ho_Chi_Minh, so the seeds keep their meaning on any day.
// Rules are evaluated lazily on every read (like the mobile mock clock): an unpaid booking past
// paymentDueAt expires; a Held escrow past releaseAt with no open complaint is released to the
// chef (net 90%); a Frozen one stays frozen until an admin decides.
//
// QA: `#fail` in the decision note, the complaint / hold search box → 503 (toast + rollback).
// Deciding `cp_qa_409` → 409 `already_decided` (simulates another admin deciding first; the
// row then shows as "Đã xử lý"). Note < 20 chars → 400. A partial refund ≥ price → 400.
import type { AdminSession } from "@/types/admin";
import type {
  AdminComplaint,
  AdminEscrowHold,
  Adherence,
  Booking,
  BookingContract,
  BookingMessage,
  BookingOffer,
  BookingParty,
  BookingPerson,
  BookingRef,
  BookingStatus,
  BookingType,
  Complaint,
  ComplaintDecision,
  ComplaintDecisionInput,
  ComplaintQuery,
  ComplaintReason,
  DateOnly,
  EscrowHold,
  EscrowHoldQuery,
  EscrowStatus,
  EscrowSummary,
  EvidenceKind,
  MealSlot,
  PlanDay,
  PlanMeal,
  RequestedOutcome,
} from "@/types/bookings";
import {
  addDays,
  BOOKING_TYPE_LABEL,
  COMPLAINT_DECISION_LABEL,
  COMPLAINT_REASON_LABEL,
  COMPLAINT_REASON_SHORT,
  decisionErrors,
  decisionOutcome,
  escrowReleaseAt,
  PAYMENT_WINDOW_HOURS,
  planEndDate,
  vnDateOf,
  vnTime,
} from "@/types/bookings";
import type { AdminOrder, OrderResolution, OrderStatus, Payment, PaymentStatus } from "@/types/commerce";
import type { ISODateString } from "@/types/moderation";
import { ESCROW_HOLD_DAYS, PLATFORM_FEE_RATE, platformFee } from "@/types/payouts";

import { ApiError } from "./api_error";
import { logAction } from "./mock_admin";
import { sleep } from "./mock_data";

const MIN = 60_000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;
const NOW = Date.now();
const TODAY = vnDateOf(NOW);
const iso = (ms: number) => new Date(ms).toISOString();
/** VN calendar day `offset` days from today. */
const dayOf = (offset: number): DateOnly => addDays(TODAY, offset);
/** ms of a VN wall-clock time `offset` days from today. */
const atVn = (offset: number, hhmm: string) => Date.parse(vnTime(dayOf(offset), hhmm));

const vndText = new Intl.NumberFormat("vi-VN");
const vnd = (n: number) => `${vndText.format(n)}đ`;
const vnDateTime = new Intl.DateTimeFormat("vi-VN", {
  timeZone: "Asia/Ho_Chi_Minh",
  hour: "2-digit",
  minute: "2-digit",
  day: "2-digit",
  month: "2-digit",
  year: "numeric",
});
const when = (ms: number | string) => vnDateTime.format(new Date(ms));
const ddmm = (d: DateOnly) => `${d.slice(8, 10)}/${d.slice(5, 7)}`;

/* ---------------------------------------------------------------- people */

const person = (id: string, fullName: string, email: string): BookingPerson => ({ id, fullName, email });

const MEMBERS = {
  u_me: person("u_me", "Minh Anh", "minhanh.nguyen@gmail.com"),
  u_hoang_nam: person("u_hoang_nam", "Hoàng Nam", "hoangnam.dev@gmail.com"),
  u_thao_vy: person("u_thao_vy", "Thảo Vy", "thaovy.nguyen@gmail.com"),
  u_ngoc_tram: person("u_ngoc_tram", "Ngọc Trâm", "ngoctram.k17@gmail.com"),
  u_duc_huy: person("u_duc_huy", "Đức Huy", "duchuy.q9@gmail.com"),
  u_gia_han: person("u_gia_han", "Gia Hân", "giahan.tran@gmail.com"),
  u_new_1: person("u_new_1", "Phan Gia Bảo", "giabao.chef@gmail.com"),
  u_new_3: person("u_new_3", "Đỗ Hải Yến", "haiyen.mebe@gmail.com"),
  u_gen_0: person("u_gen_0", "Nguyễn Thị An", "nguyen.thi.an0@gmail.com"),
  u_gen_1: person("u_gen_1", "Vũ Ngọc Linh", "vu.ngoc.linh1@gmail.com"),
  u_gen_2: person("u_gen_2", "Dương Bảo Chi", "duong.bao.chi2@gmail.com"),
  u_gen_4: person("u_gen_4", "Ngô Minh Giang", "ngo.minh.giang4@gmail.com"),
  u_gen_6: person("u_gen_6", "Hồ Quốc Khánh", "ho.quoc.khanh6@gmail.com"),
};

/** Same ids / emails as mock_payouts.ts. */
const CHEFS = {
  u_chef_tam: person("u_chef_tam", "Lê Quang Tâm", "tam.chefchay@gmail.com"),
  u_thu_ha: person("u_thu_ha", "ThS. DD Phạm Thu Hà", "thuha.dinhduong@gmail.com"),
  u_chef_chau: person("u_chef_chau", "Tôn Nữ Minh Châu", "minhchau.hue@gmail.com"),
  u_chef_khoa: person("u_chef_khoa", "Nguyễn Đăng Khoa", "khoa.fitvegan@gmail.com"),
  u_chef_lan: person("u_chef_lan", "Võ Thị Ngọc Lan", "ngoclan.anddam@gmail.com"),
  u_chef_minh: person("u_chef_minh", "Trần Quốc Minh", "quocminh.thucduong@gmail.com"),
};

/* ---------------------------------------------------------------- dishes */

type Dish = [id: string, name: string, kcal: number];

/** Chef recipes used to fill plan days (no peanut, sesame or grapefruit unless a seed overrides it). */
const DISHES: Record<MealSlot, Dish[]> = {
  breakfast: [
    ["rc_xoi_dau_xanh", "Xôi đậu xanh nước cốt dừa", 380],
    ["rc_banh_mi_nam", "Bánh mì chay pate nấm", 420],
    ["rc_yen_mach_chuoi", "Yến mạch sữa đậu nành chuối", 350],
    ["rc_pho_chay", "Phở chay nấm hương", 450],
    ["rc_chao_bi_do", "Cháo yến mạch bí đỏ", 300],
  ],
  snack_am: [
    ["rc_sua_hat_dieu", "Sữa hạt điều", 160],
    ["rc_trai_cay", "Đĩa trái cây theo mùa", 120],
  ],
  lunch: [
    ["rc_com_dau_hu_sot_ca", "Cơm gạo lứt đậu hũ sốt cà", 620],
    ["rc_bun_rieu_chay", "Bún riêu chay", 540],
    ["rc_com_tam_chay", "Cơm tấm chay sườn đậu", 650],
    ["rc_mi_quang_chay", "Mì Quảng chay", 580],
    ["rc_bun_xao_nam", "Bún xào rau củ nấm", 520],
  ],
  snack_pm: [
    ["rc_che_dau_den", "Chè đậu đen ít đường", 180],
    ["rc_sua_chua_dua", "Sữa chua dừa hạt chia", 150],
    ["rc_khoai_lang", "Khoai lang luộc", 130],
  ],
  dinner: [
    ["rc_lau_nam", "Lẩu nấm chay", 480],
    ["rc_dau_hu_sot_ca", "Đậu hũ sốt cà chua + cơm", 520],
    ["rc_canh_rong_bien", "Canh rong biển đậu hũ non + cơm", 450],
    ["rc_rau_cu_xao_nam", "Rau củ xào nấm đùi gà + gạo lứt", 510],
    ["rc_ca_ri_chay", "Cà ri chay khoai lang", 560],
  ],
  snack_late: [
    ["rc_sua_dau_nanh", "Sữa đậu nành ấm", 130],
    ["rc_chuoi_hap", "Chuối hấp nước cốt dừa", 140],
  ],
};

const FEEDBACK: [rating: number, adherence: Adherence, body: string][] = [
  [5, "All", "Bữa sáng làm kịp trong 10 phút, rất ổn."],
  [4, "Partly", "Mình đổi bữa trưa vì đi công tác, phần còn lại làm đủ."],
  [4, "All", "Món canh hơi nhạt, còn lại ngon."],
  [3, "Partly", "Hôm nay bận nên chỉ làm được bữa tối."],
  [5, "All", "Rất hợp khẩu vị, cả nhà ăn hết."],
  [4, "None", "Ăn cỗ cưới nên không theo được, mai làm lại."],
];

/* ---------------------------------------------------------------- seeds */

type MemberKey = keyof typeof MEMBERS;
type ChefKey = keyof typeof CHEFS;

interface ComplaintSeed {
  id: string;
  reason: ComplaintReason;
  description: string;
  outcome: RequestedOutcome;
  /** PartialRefund only. */
  amount?: number;
  at: number;
  evidence: [kind: EvidenceKind, url: string, caption: string | null, by?: BookingParty][];
  chefResponse?: [text: string, afterMin: number];
  decision?: { decision: ComplaintDecision; refund?: number; note: string; by: string; at: number };
}

interface Seed {
  id: string;
  member: MemberKey;
  chef: ChefKey;
  type: BookingType;
  days: number;
  /** Start date, days from today (VN). */
  start: number;
  /** Seeded status; the lazy rules may move it on read. */
  status: BookingStatus;
  goal: string;
  allergies: string[];
  pattern: MealSlot[];
  budget: number | null;
  needs: string;
  created: number;
  /** [by, price, note, minutes after the request]; the last one is Open (no contract) or Accepted. */
  offers?: [by: BookingParty, price: number, note: string, afterMin: number][];
  chat?: [by: BookingParty, afterMin: number, text: string][];
  orderId?: string;
  /** AwaitingPayment: when the current QR was created. */
  qrAt?: number;
  /** A failed / expired payment attempt before the one that counts. */
  retry?: "Failed" | "Expired";
  /** OneShot: hours after deliveryDueAt the plan was sent (late delivery). */
  sentLateHours?: number;
  /** Number of plan days sent (default: by date). */
  delivered?: number;
  /** DailyFeedback: today's day is still a draft. */
  todayDraft?: boolean;
  /** Day index → [rating, adherence, body]. */
  feedbackOverrides?: Record<number, [number, Adherence, string]>;
  /** "4:breakfast" → a specific dish for that day and slot. */
  overrides?: Record<string, { name: string; kcal: number; note?: string }>;
  /** Day i > N repeats day ((i − 1) % N) + 1 (lazy chef). */
  repeatAfter?: number;
  dayNotes?: Record<number, string>;
  scope?: string;
  complaint?: ComplaintSeed;
}

const MA_NEEDS =
  "Mình muốn giảm khoảng 3 kg trong tháng, bữa sáng cần làm nhanh dưới 15 phút vì đi làm sớm. Dị ứng đậu phộng, không ăn được hành sống.";

const SEEDS: Seed[] = [
  /* ------------------------------------------------ Minh Anh (u_me) */
  {
    id: "b_ma_tam_nego",
    member: "u_me",
    chef: "u_chef_tam",
    type: "DailyFeedback",
    days: 10,
    start: 3,
    status: "Negotiating",
    goal: "lose_weight",
    allergies: ["peanut"],
    pattern: ["breakfast", "lunch", "dinner"],
    budget: 80_000,
    needs: MA_NEEDS,
    created: NOW - 26 * HOUR,
    chat: [
      ["chef", 50, "Chào Minh Anh, mình đọc hồ sơ rồi. Bạn ăn được nấm và đậu hũ hằng ngày không, hay cần đổi bớt?"],
      ["member", 95, "Mình ăn được hết nha anh, chỉ cần tránh đậu phộng thôi."],
    ],
    offers: [["chef", 1_500_000, "10 ngày có phản hồi mỗi ngày: mình điều chỉnh thực đơn theo góp ý mỗi tối. Giá đã gồm danh sách đi chợ theo tuần.", 140]],
  },
  {
    id: "b_ma_thuha_active",
    member: "u_me",
    chef: "u_thu_ha",
    type: "OneShot",
    days: 7,
    start: -2,
    status: "Active",
    goal: "lose_weight",
    allergies: ["peanut"],
    pattern: ["breakfast", "lunch", "snack_pm", "dinner"],
    budget: 70_000,
    needs: "Cần thực đơn 7 ngày giảm cân lành mạnh khoảng 1.600 kcal/ngày, bữa sáng dưới 15 phút, có bữa phụ chiều vì mình hay đói lúc 4 giờ. Dị ứng đậu phộng.",
    created: atVn(-6, "08:40"),
    offers: [["chef", 840_000, "7 ngày × 120.000đ, giao trọn kế hoạch trước ngày bắt đầu, kèm bảng kcal từng bữa.", 180]],
    chat: [["member", 265, "Dạ em đồng ý ạ, em thanh toán luôn."]],
    orderId: "ord_601",
    dayNotes: { 1: "Uống đủ 2 lít nước, bữa phụ chiều có thể đổi sang 1 quả táo.", 3: "Hôm nay nhiều rau xanh, nhớ chuẩn bị canh từ tối hôm trước." },
  },
  {
    id: "b_ma_tam_done",
    member: "u_me",
    chef: "u_chef_tam",
    type: "DailyFeedback",
    days: 5,
    start: -9,
    status: "Completed",
    goal: "eat_clean",
    allergies: ["peanut"],
    pattern: ["breakfast", "lunch", "dinner"],
    budget: 60_000,
    needs: "Thử ăn chay 5 ngày cho quen, món dễ nấu trong bếp nhỏ ở chung cư, không dùng lò nướng.",
    created: atVn(-13, "19:10"),
    offers: [["chef", 900_000, "5 ngày có phản hồi mỗi ngày, 180.000đ/ngày.", 60]],
    orderId: "ord_602",
  },
  /* ------------------------------------------------ Lê Quang Tâm (u_chef_tam) */
  {
    id: "b_nam_tam_req",
    member: "u_hoang_nam",
    chef: "u_chef_tam",
    type: "OneShot",
    days: 14,
    start: 5,
    status: "Requested",
    goal: "gain_muscle",
    allergies: [],
    pattern: ["breakfast", "lunch", "snack_pm", "dinner"],
    budget: 100_000,
    needs: "Mình tập gym 4 buổi/tuần, cần thực đơn chay 14 ngày đủ đạm (khoảng 120 g/ngày), ưu tiên món nấu sẵn được cho 2 ngày.",
    created: NOW - 3 * HOUR,
  },
  {
    id: "b_vy_tam_active",
    member: "u_thao_vy",
    chef: "u_chef_tam",
    type: "DailyFeedback",
    days: 7,
    start: -2,
    status: "Active",
    goal: "eat_clean",
    allergies: [],
    pattern: ["breakfast", "lunch", "dinner"],
    budget: 90_000,
    needs: "Muốn ăn chay thanh đạm 7 ngày sau Tết, ít dầu mỡ, nhiều canh. Mỗi tối mình sẽ góp ý để anh chỉnh ngày hôm sau.",
    created: atVn(-5, "10:05"),
    offers: [
      ["chef", 1_400_000, "7 ngày có phản hồi mỗi ngày, 200.000đ/ngày vì có thêm canh mỗi bữa.", 70],
      ["member", 1_200_000, "Anh giảm giúp em chút được không ạ, em sinh viên.", 130],
      ["chef", 1_260_000, "Mình để 180.000đ/ngày như giá niêm yết nhé.", 190],
    ],
    orderId: "ord_603",
    todayDraft: true,
    feedbackOverrides: { 2: [4, "Partly", "Bữa tối hơi nhiều dầu, mai anh cho em món hấp nhé."] },
  },
  {
    id: "b_tram_tam",
    member: "u_ngoc_tram",
    chef: "u_chef_tam",
    type: "OneShot",
    days: 7,
    start: -7,
    status: "Disputed",
    goal: "eat_clean",
    allergies: ["peanut"],
    pattern: ["breakfast", "lunch", "dinner"],
    budget: 90_000,
    needs:
      "Mình đang uống thuốc huyết áp (nhóm chẹn kênh canxi) theo đơn bác sĩ, cần thực đơn ít muối và tránh hoàn toàn bưởi, nước ép bưởi. Ưu tiên món dễ nấu sau giờ làm.",
    created: atVn(-12, "09:15"),
    offers: [["chef", 1_050_000, "7 ngày × 150.000đ, giao trọn kế hoạch trước ngày bắt đầu, ít muối theo yêu cầu.", 120]],
    orderId: "ord_604",
    overrides: {
      "4:breakfast": { name: "Gỏi bưởi chay + nước ép bưởi", kcal: 280, note: "Có thể thay bưởi bằng cam nếu đang dùng thuốc." },
      "6:breakfast": { name: "Sinh tố bưởi hồng chuối", kcal: 260 },
    },
    complaint: {
      id: "cp_tram_tam",
      reason: "health_risk",
      description:
        "Ngày 4 và ngày 6 có gỏi bưởi, nước ép bưởi và sinh tố bưởi dù mình đã ghi rõ đang dùng thuốc huyết áp và cần tránh bưởi. Bưởi có thể làm tăng nồng độ một số thuốc huyết áp trong máu. Mình phải tự đổi món 2 ngày đó.",
      outcome: "PartialRefund",
      amount: 500_000,
      at: NOW - 5 * HOUR,
      evidence: [
        [
          "Link",
          "https://www.fda.gov/consumers/consumer-updates/grapefruit-juice-and-some-drugs-dont-mix",
          "FDA: Nước ép bưởi và một số loại thuốc không nên dùng chung",
        ],
        ["Image", "https://res.cloudinary.com/veganlife/image/upload/v1/complaints/cp_tram_tam_ngay4.jpg", "Ảnh chụp kế hoạch ngày 4"],
      ],
      chefResponse: [
        "Ở ngày 4 tôi có ghi chú thay bưởi bằng cam nếu đang dùng thuốc, nhưng đồng ý là nên bỏ hẳn vì chị đã khai từ đầu. Ngày 6 là sơ suất của tôi. Tôi đồng ý hoàn 300.000đ cho 2 ngày bị ảnh hưởng.",
        180,
      ],
    },
  },
  {
    id: "b_han_tam_done",
    member: "u_gia_han",
    chef: "u_chef_tam",
    type: "DailyFeedback",
    days: 30,
    start: -53,
    status: "Completed",
    goal: "maintain",
    allergies: [],
    pattern: ["breakfast", "lunch", "dinner"],
    budget: 250_000,
    needs: "Thực đơn chay 30 ngày cho cả gia đình 4 người (2 bé tiểu học), mỗi tối mình góp ý để anh chỉnh. Cần danh sách đi chợ theo tuần.",
    created: atVn(-58, "20:30"),
    offers: [
      ["chef", 6_000_000, "Thực đơn cho 4 người, 200.000đ/ngày, có phản hồi mỗi ngày.", 90],
      ["member", 5_500_000, "Anh xem bớt chút được không ạ?", 300],
      ["chef", 6_000_000, "Mình giữ 6.000.000đ nhưng tặng thêm danh sách đi chợ theo tuần và món ăn vặt cho bé.", 420],
    ],
    orderId: "ord_605",
  },
  /* ------------------------------------------------ ThS. DD Phạm Thu Hà (web-only rows) */
  {
    id: "b_chi_ha_done",
    member: "u_gen_2",
    chef: "u_thu_ha",
    type: "OneShot",
    days: 14,
    start: -26,
    status: "Completed",
    goal: "lose_weight",
    allergies: [],
    pattern: ["breakfast", "lunch", "dinner"],
    budget: 60_000,
    needs: "Thực đơn 14 ngày giảm cân sau sinh (đã cai sữa), khoảng 1.500 kcal/ngày, món dễ mua ở chợ.",
    created: atVn(-31, "14:00"),
    offers: [["chef", 1_680_000, "14 ngày × 120.000đ, giao trọn một lần kèm bảng kcal.", 100]],
    orderId: "ord_606",
  },
  {
    id: "b_huy_ha",
    member: "u_duc_huy",
    chef: "u_thu_ha",
    type: "OneShot",
    days: 10,
    start: -14,
    status: "Resolved",
    goal: "maintain",
    allergies: [],
    pattern: ["breakfast", "lunch", "dinner"],
    budget: 50_000,
    needs: "Sinh viên ở trọ, cần thực đơn chay 10 ngày rẻ (dưới 50.000đ/ngày) nấu bằng nồi cơm điện.",
    created: atVn(-19, "21:00"),
    offers: [["chef", 1_200_000, "10 ngày × 120.000đ, giao trọn trước ngày bắt đầu.", 80]],
    orderId: "ord_607",
    sentLateHours: 66,
    complaint: {
      id: "cp_huy_ha",
      reason: "late_or_missing",
      description:
        "Hợp đồng ghi giao trọn kế hoạch trước ngày bắt đầu nhưng đến tối ngày 3 mình mới nhận được. 3 ngày đầu mình phải tự lo bữa, có nhắn nhưng chuyên gia không trả lời.",
      outcome: "PartialRefund",
      amount: 360_000,
      at: atVn(-11, "22:10"),
      evidence: [["Image", "https://res.cloudinary.com/veganlife/image/upload/v1/complaints/cp_huy_ha_tin_nhan.jpg", "Tin nhắn hỏi kế hoạch ngày 1 và ngày 2"]],
      chefResponse: ["Tôi bị ốm 2 ngày nên gửi trễ, đã xin lỗi bạn. Đồng ý hoàn phần 3 ngày đầu.", 300],
      decision: {
        decision: "Split",
        refund: 400_000,
        note: "Kế hoạch giao trễ khoảng 2 ngày so với hạn trong hợp đồng, 3/10 ngày đầu thành viên tự lo bữa. Hoàn 400.000đ (làm tròn), phần còn lại chuyển cho chuyên gia.",
        by: "Lê Minh Quân",
        at: atVn(-6, "10:20"),
      },
    },
  },
  /* ------------------------------------------------ Tôn Nữ Minh Châu */
  {
    id: "b_bao_chau",
    member: "u_new_1",
    chef: "u_chef_chau",
    type: "DailyFeedback",
    days: 7,
    start: -16,
    status: "Resolved",
    goal: "eat_clean",
    allergies: ["sesame"],
    pattern: ["breakfast", "lunch", "dinner"],
    budget: 100_000,
    needs: "Muốn thử món chay Huế 7 ngày. Dị ứng mè (vừng) nặng, đã từng phải đi cấp cứu.",
    created: atVn(-20, "16:45"),
    offers: [["chef", 1_330_000, "7 ngày có phản hồi mỗi ngày, 190.000đ/ngày, toàn món Huế.", 110]],
    orderId: "ord_608",
    delivered: 5,
    overrides: {
      "2:dinner": { name: "Đậu hũ chiên sốt mè rang", kcal: 540 },
      "5:lunch": { name: "Bún trộn sốt mè đen kiểu Huế", kcal: 600 },
    },
    complaint: {
      id: "cp_bao_chau",
      reason: "allergen",
      description: "Mình đã khai dị ứng mè khi đặt và trong hồ sơ sức khoẻ, nhưng ngày 2 có đậu hũ sốt mè rang và ngày 5 có bún trộn sốt mè đen. May mình đọc kỹ trước khi nấu.",
      outcome: "FullRefund",
      at: atVn(-12, "20:15"),
      evidence: [
        ["Image", "https://res.cloudinary.com/veganlife/image/upload/v1/complaints/cp_bao_chau_ngay2.jpg", "Ngày 2: đậu hũ chiên sốt mè rang"],
        ["Image", "https://res.cloudinary.com/veganlife/image/upload/v1/complaints/cp_bao_chau_ngay5.jpg", "Ngày 5: bún trộn sốt mè đen"],
        ["Link", "https://www.foodallergy.org/living-food-allergies/food-allergy-essentials/common-allergens/sesame", "FARE: thông tin về dị ứng mè"],
      ],
      chefResponse: ["Tôi nhầm hồ sơ với một khách khác, thành thật xin lỗi bạn. Đồng ý hoàn tiền.", 240],
      decision: {
        decision: "RefundMember",
        note: "Thành viên đã khai dị ứng mè khi đặt và trong hồ sơ sức khoẻ; ngày 2 và ngày 5 đều có sốt mè. Rủi ro sức khoẻ nghiêm trọng nên hoàn toàn bộ.",
        by: "Trần Thu Hằng",
        at: atVn(-9, "15:40"),
      },
    },
  },
  {
    id: "b_yen_chau_done",
    member: "u_new_3",
    chef: "u_chef_chau",
    type: "DailyFeedback",
    days: 10,
    start: -18,
    status: "Completed",
    goal: "maintain",
    allergies: [],
    pattern: ["breakfast", "snack_am", "lunch", "snack_pm", "dinner"],
    budget: 120_000,
    needs: "Mẹ bầu 5 tháng ăn chay, cần đủ sắt và canxi, chia 5 bữa nhỏ. Thích vị Huế nhưng bớt cay.",
    created: atVn(-22, "09:30"),
    offers: [["chef", 1_800_000, "10 ngày có phản hồi mỗi ngày, 5 bữa nhỏ, 180.000đ/ngày.", 75]],
    orderId: "ord_609",
  },
  /* ------------------------------------------------ Nguyễn Đăng Khoa */
  {
    id: "b_an_khoa",
    member: "u_gen_0",
    chef: "u_chef_khoa",
    type: "OneShot",
    days: 14,
    start: -10,
    status: "Disputed",
    goal: "gain_muscle",
    allergies: [],
    pattern: ["breakfast", "lunch", "snack_pm", "dinner"],
    budget: 120_000,
    needs: "Tập gym 5 buổi/tuần, cần khoảng 2.400 kcal và 140 g đạm mỗi ngày, không dùng whey. Muốn đa dạng món, không lặp quá 2 lần mỗi tuần.",
    created: atVn(-14, "18:20"),
    offers: [["chef", 2_100_000, "14 ngày × 150.000đ, 2.400 kcal và 140 g đạm mỗi ngày, giao trọn một lần.", 95]],
    orderId: "ord_610",
    repeatAfter: 7,
    complaint: {
      id: "cp_an_khoa",
      reason: "not_as_agreed",
      description:
        "Hợp đồng ghi 2.400 kcal và 140 g đạm mỗi ngày nhưng mình tính lại các ngày chỉ khoảng 1.600–1.700 kcal, đạm dưới 80 g. Ngày 8 đến ngày 14 lặp lại y hệt ngày 1 đến ngày 7. Mình đã nhắn 2 lần nhưng chưa được sửa.",
      outcome: "FullRefund",
      at: NOW - 2 * DAY - 3 * HOUR,
      evidence: [
        ["Image", "https://res.cloudinary.com/veganlife/image/upload/v1/complaints/cp_an_khoa_bang_tinh.jpg", "Bảng tính kcal và đạm 7 ngày đầu"],
        ["Image", "https://res.cloudinary.com/veganlife/image/upload/v1/complaints/cp_an_khoa_ngay8.jpg", "Ngày 8 giống hệt ngày 1"],
        ["Link", "https://fdc.nal.usda.gov/", "Nguồn số liệu dinh dưỡng: USDA FoodData Central"],
      ],
    },
  },
  {
    id: "b_giang_khoa_active",
    member: "u_gen_4",
    chef: "u_chef_khoa",
    type: "OneShot",
    days: 14,
    start: -5,
    status: "Active",
    goal: "gain_muscle",
    allergies: ["soy"],
    pattern: ["breakfast", "lunch", "dinner", "snack_late"],
    budget: 110_000,
    needs: "Tăng cơ cho người mới tập, dị ứng đậu nành nên cần nguồn đạm khác (đậu gà, đậu lăng, seitan). Khoảng 2.200 kcal/ngày.",
    created: atVn(-9, "11:00"),
    offers: [["chef", 1_960_000, "14 ngày × 140.000đ, không đậu nành, giao trọn một lần.", 85]],
    orderId: "ord_611",
    retry: "Failed",
    overrides: {
      "1:snack_late": { name: "Sữa yến mạch ấm", kcal: 140 },
      "2:snack_late": { name: "Chuối hấp nước cốt dừa", kcal: 140 },
    },
  },
  /* ------------------------------------------------ Võ Thị Ngọc Lan */
  {
    id: "b_linh_lan",
    member: "u_gen_1",
    chef: "u_chef_lan",
    type: "DailyFeedback",
    days: 7,
    start: -7,
    status: "Ended",
    goal: "eat_clean",
    allergies: [],
    pattern: ["breakfast", "lunch", "dinner"],
    budget: 80_000,
    needs: "Thực đơn chay 7 ngày cho mẹ bỉm sữa đang cho con bú, cần lợi sữa và đủ chất.",
    created: atVn(-11, "13:30"),
    offers: [["chef", 1_190_000, "7 ngày có phản hồi mỗi ngày, 170.000đ/ngày, món lợi sữa.", 65]],
    orderId: "ord_612",
  },
  /* ------------------------------------------------ Trần Quốc Minh */
  {
    id: "b_khanh_minh_qa",
    member: "u_gen_6",
    chef: "u_chef_minh",
    type: "OneShot",
    days: 5,
    start: -6,
    status: "Disputed",
    goal: "eat_clean",
    allergies: [],
    pattern: ["breakfast", "lunch", "dinner"],
    budget: 60_000,
    needs: "Thực đơn thực dưỡng 5 ngày cho người mới, có hướng dẫn tự làm dưa cải và tương miso tại nhà.",
    created: atVn(-10, "08:00"),
    offers: [["chef", 600_000, "5 ngày × 120.000đ, kèm hướng dẫn lên men.", 50]],
    orderId: "ord_613",
    complaint: {
      id: "cp_qa_409",
      reason: "other",
      description:
        "(Bản ghi thử nghiệm QA) Kế hoạch thiếu phần hướng dẫn lên men như đã thoả thuận. Khi bấm quyết định, máy chủ mô phỏng sẽ báo 409 vì một quản trị viên khác đã xử lý trước.",
      outcome: "PartialRefund",
      amount: 200_000,
      at: NOW - 26 * HOUR,
      evidence: [["Link", "https://example.com/veganlife-qa/bang-chung", "Liên kết thử nghiệm"]],
      chefResponse: ["Hướng dẫn lên men nằm trong ghi chú ngày 1, tôi đã gửi lại qua chat.", 120],
    },
  },
  /* ------------------------------------------------ unpaid orders */
  {
    id: "b_vy_ha_pay",
    member: "u_thao_vy",
    chef: "u_thu_ha",
    type: "OneShot",
    days: 7,
    start: 4,
    status: "AwaitingPayment",
    goal: "maintain",
    allergies: [],
    pattern: ["breakfast", "lunch", "dinner"],
    budget: 70_000,
    needs: "Thực đơn 7 ngày cho mẹ mình (62 tuổi, tiểu đường type 2), ít đường, nhiều rau, món mềm dễ nhai.",
    created: NOW - 5 * HOUR,
    offers: [["chef", 910_000, "7 ngày × 130.000đ, có lưu ý chỉ số đường huyết từng món.", 150]],
    orderId: "ord_614",
    qrAt: NOW - 6 * MIN,
  },
  {
    id: "b_huy_minh_expired",
    member: "u_duc_huy",
    chef: "u_chef_minh",
    type: "OneShot",
    days: 3,
    start: -1,
    status: "Expired",
    goal: "eat_clean",
    allergies: [],
    pattern: ["lunch", "dinner"],
    budget: 50_000,
    needs: "Muốn thử thực dưỡng 3 ngày cuối tuần, chỉ cần bữa trưa và tối.",
    created: atVn(-6, "17:00"),
    offers: [["chef", 450_000, "3 ngày × 150.000đ.", 60]],
    orderId: "ord_615",
  },
];

/** Deciding this complaint returns 409: "another admin" decides it first. */
const QA_409_COMPLAINT = "cp_qa_409";

/* ---------------------------------------------------------------- rows */

interface BookingRow {
  id: string;
  member: BookingPerson;
  chef: BookingPerson;
  bookingType: BookingType;
  planDays: number;
  startDate: DateOnly;
  goal: string;
  allergies: string[];
  mealPattern: MealSlot[];
  budgetPerDay: number | null;
  needs: string;
  shareHealthProfile: boolean;
  status: BookingStatus;
  offers: BookingOffer[];
  contract: BookingContract | null;
  escrow: EscrowHold | null;
  complaint: Complaint | null;
  days: PlanDay[];
  messages: BookingMessage[];
  orderId: string | null;
  declineReason: string | null;
  cancelReason: string | null;
  createdAt: ISODateString;
  updatedAt: ISODateString;
}

interface OrderRow {
  id: string;
  bookingId: string;
  createdAt: ISODateString;
  /** Oldest first. */
  payments: Payment[];
  /** Set when an admin cancels the unpaid order on /orders. */
  cancelled: OrderResolution | null;
}

const orders = new Map<string, OrderRow>();

/* ---------------------------------------------------------------- payments */

const QR_BASE = "https://pay.veganlife.vn/mock/qr";
const QR_TTL_MIN = 15;
const pad2 = (n: number) => String(n).padStart(2, "0");
const refSeqByDay = new Map<string, number>();

/** transactionRef = "VL" + yyMMdd + 4-digit daily sequence (same rule as the mobile mock). */
function nextRef(at: number) {
  const d = new Date(at + 7 * HOUR);
  const day = `${String(d.getUTCFullYear()).slice(2)}${pad2(d.getUTCMonth() + 1)}${pad2(d.getUTCDate())}`;
  const seq = (refSeqByDay.get(day) ?? 0) + 1;
  refSeqByDay.set(day, seq);
  return `VL${day}${String(seq).padStart(4, "0")}`;
}

let paymentSeq = 900;

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

/* ---------------------------------------------------------------- builders */

const PAID_STATUSES: readonly BookingStatus[] = ["Active", "Ended", "Disputed", "Completed", "Resolved"];
const hash = (s: string) => [...s].reduce((sum, ch) => sum + ch.charCodeAt(0), 0);

function say(row: BookingRow, senderRole: BookingParty | "system", body: string, at: number, offer: BookingOffer | null = null) {
  row.messages.push({
    id: `msg_${row.id}_${row.messages.length + 1}`,
    senderId: senderRole === "member" ? row.member.id : senderRole === "chef" ? row.chef.id : null,
    senderRole,
    kind: offer ? "Offer" : senderRole === "system" ? "System" : "Text",
    body,
    offerId: offer?.id ?? null,
    offer,
    attachmentUrl: null,
    createdAt: iso(at),
  });
}

function mealsFor(seed: Seed, dayIndex: number, partial: boolean): PlanMeal[] {
  const source = seed.repeatAfter && dayIndex > seed.repeatAfter ? ((dayIndex - 1) % seed.repeatAfter) + 1 : dayIndex;
  const slots = partial ? seed.pattern.slice(0, Math.max(1, seed.pattern.length - 1)) : seed.pattern;
  const h = hash(seed.id);
  return slots.map((slot, k): PlanMeal => {
    const o = seed.overrides?.[`${source}:${slot}`];
    if (o) return { slot, recipe: { id: `rc_${seed.id}_${source}_${slot}`, name: o.name, calories: o.kcal }, note: o.note ?? null };
    const pool = DISHES[slot];
    const [id, name, kcal] = pool[(source + k + h) % pool.length];
    return { slot, recipe: { id, name, calories: kcal }, note: null };
  });
}

function buildDays(seed: Seed, row: BookingRow, paidAt: number, deliveryDueAt: number) {
  const oneShot = seed.type === "OneShot";
  const oneShotSentAt = seed.sentLateHours
    ? deliveryDueAt + seed.sentLateHours * HOUR
    : Math.max(paidAt + 2 * HOUR, deliveryDueAt - 6 * HOUR);
  // DailyFeedback: a day is sent the evening before (or earlier for today) unless today is a draft.
  const byDate = Array.from({ length: seed.days }, (_, i) => seed.start + i).filter((offset) => offset < 0 || (offset === 0 && !seed.todayDraft)).length;
  const delivered = seed.delivered ?? (oneShot ? (oneShotSentAt <= NOW ? seed.days : 0) : byDate);
  const h = hash(seed.id);

  for (let i = 1; i <= seed.days; i++) {
    const offset = seed.start + i - 1;
    const date = dayOf(offset);
    let sentAt: number | null = null;
    if (i <= delivered) sentAt = oneShot ? oneShotSentAt : Math.max(paidAt + HOUR, atVn(offset - 1, "20:30"));
    const sent = sentAt !== null && sentAt <= NOW;
    const draft = !sent && offset === 0 && !!seed.todayDraft;
    const fbSeed = seed.feedbackOverrides?.[i] ?? FEEDBACK[(i + h) % FEEDBACK.length];
    const feedbackAt = atVn(offset, "20:00");
    row.days.push({
      dayIndex: i,
      date,
      status: sent ? "Sent" : "Draft",
      chefNote: sent ? (seed.dayNotes?.[i] ?? null) : null,
      sentAt: sent && sentAt !== null ? iso(sentAt) : null,
      meals: sent || draft ? mealsFor(seed, i, draft) : [],
      feedback:
        !oneShot && sent && feedbackAt <= NOW
          ? { rating: fbSeed[0], adherence: fbSeed[1], body: fbSeed[2], createdAt: iso(feedbackAt) }
          : null,
    });
    if (!oneShot && sent && sentAt !== null) {
      say(row, "system", `${row.chef.fullName} đã gửi kế hoạch ngày ${i} (${ddmm(date)}).`, sentAt);
      if (feedbackAt <= NOW) say(row, "system", `${row.member.fullName} đã phản hồi ngày ${i}: ${fbSeed[0]}★ · ${fbSeed[2]}`, feedbackAt);
    }
  }
  if (oneShot && delivered > 0 && oneShotSentAt <= NOW) {
    say(row, "chef", `Mình đã gửi toàn bộ kế hoạch ${seed.days} ngày, bạn xem tab Kế hoạch nhé. Có gì chưa rõ cứ nhắn mình.`, oneShotSentAt);
  }
}

const decisionDetail = (decision: ComplaintDecision, price: number, refund: number) => {
  const out = decisionOutcome(price, decision, refund);
  if (decision === "ReleaseToChef") return `chuyên gia nhận ${vnd(out.chefNet)} sau phí`;
  if (decision === "RefundMember") return `hoàn ${vnd(out.refund)} về phương thức thanh toán ban đầu`;
  return `hoàn ${vnd(out.refund)} cho thành viên, chuyên gia nhận ${vnd(out.chefNet)} sau phí`;
};

/** Settles a complaint: escrow, booking and order follow the decision. Shared by seeds and the admin action. */
function applyDecision(row: BookingRow, decision: ComplaintDecision, refundAmount: number | undefined, note: string, actor: string, at: number) {
  const complaint = row.complaint;
  const escrow = row.escrow;
  const contract = row.contract;
  if (!complaint || !escrow || !contract) return;
  const out = decisionOutcome(contract.price, decision, refundAmount);
  complaint.status = "Resolved";
  complaint.decision = decision;
  complaint.refundAmount = out.refund;
  complaint.adminNote = note;
  complaint.decidedBy = actor;
  complaint.decidedAt = iso(at);
  escrow.status = decision === "ReleaseToChef" ? "Released" : decision === "RefundMember" ? "Refunded" : "PartiallyRefunded";
  escrow.releasedAt = out.chefGross > 0 ? iso(at) : null;
  escrow.releasedAmount = out.chefGross;
  escrow.feeAmount = out.fee;
  escrow.refundedAmount = out.refund;
  escrow.resolvedBy = actor;
  escrow.resolutionNote = note;
  row.status = "Resolved";
  row.updatedAt = iso(at);
  if (decision === "RefundMember" && row.orderId) {
    for (const p of orders.get(row.orderId)?.payments ?? []) if (p.status === "Paid") p.status = "Refunded";
  }
  say(row, "system", `Ban quản trị đã quyết định: ${COMPLAINT_DECISION_LABEL[decision]} — ${decisionDetail(decision, contract.price, out.refund)}. Ghi chú: “${note}”`, at);
}

/** Automatic release at releaseAt (no complaint): net 90% to the chef wallet. */
function autoRelease(row: BookingRow) {
  const escrow = row.escrow;
  if (!escrow) return;
  const at = Date.parse(escrow.releaseAt);
  escrow.status = "Released";
  escrow.releasedAt = escrow.releaseAt;
  escrow.releasedAmount = escrow.amount;
  escrow.feeAmount = platformFee(escrow.amount);
  escrow.resolvedBy = null;
  escrow.resolutionNote = null;
  if (row.status === "Active" || row.status === "Ended") row.status = "Completed";
  row.updatedAt = escrow.releaseAt;
  say(row, "system", `Hết hạn khiếu nại — đã chuyển ${vnd(escrow.amount - escrow.feeAmount)} cho chuyên gia (sau phí ${PLATFORM_FEE_RATE * 100}%).`, at);
}

function buildComplaint(row: BookingRow, c: ComplaintSeed) {
  const contract = row.contract;
  const escrow = row.escrow;
  if (!contract || !escrow) throw new Error(`mock_bookings: ${row.id} needs a paid contract for ${c.id}`);
  row.complaint = {
    id: c.id,
    bookingId: row.id,
    reason: c.reason,
    description: c.description,
    requestedOutcome: c.outcome,
    requestedAmount: c.outcome === "FullRefund" ? contract.price : (c.amount ?? 0),
    status: "Open",
    evidence: c.evidence.map(([kind, url, caption, by = "member"], i) => ({
      id: `ev_${c.id}_${i + 1}`,
      kind,
      url,
      caption,
      submittedBy: by,
      createdAt: iso(c.at),
    })),
    chefResponse: c.chefResponse?.[0] ?? null,
    chefRespondedAt: c.chefResponse ? iso(c.at + c.chefResponse[1] * MIN) : null,
    decision: null,
    refundAmount: null,
    adminNote: null,
    decidedBy: null,
    decidedAt: null,
    createdAt: iso(c.at),
  };
  escrow.status = "Frozen";
  row.status = "Disputed";
  row.updatedAt = iso(c.at);
  say(row, "system", `${row.member.fullName} đã gửi khiếu nại: “${COMPLAINT_REASON_LABEL[c.reason]}”. Tiền được tạm giữ đến khi Ban quản trị quyết định.`, c.at);
  if (c.chefResponse) say(row, "chef", c.chefResponse[0], c.at + c.chefResponse[1] * MIN);
  if (c.decision) applyDecision(row, c.decision.decision, c.decision.refund, c.decision.note, c.decision.by, c.decision.at);
}

const scopeOf = (seed: Seed) =>
  `Thiết kế thực đơn chay ${seed.days} ngày (${BOOKING_TYPE_LABEL[seed.type].toLowerCase()}) theo hồ sơ và nhu cầu của thành viên: ` +
  `${seed.pattern.length} bữa mỗi ngày, có định lượng và cách làm từng món` +
  `${seed.allergies.length ? `, tránh hoàn toàn: ${seed.allergies.join(", ")}` : ""}.`;

function build(seed: Seed): BookingRow {
  const member = MEMBERS[seed.member];
  const chef = CHEFS[seed.chef];
  const startDate = dayOf(seed.start);
  const endDate = planEndDate(startDate, seed.days);
  const row: BookingRow = {
    id: seed.id,
    member,
    chef,
    bookingType: seed.type,
    planDays: seed.days,
    startDate,
    goal: seed.goal,
    allergies: [...seed.allergies],
    mealPattern: [...seed.pattern],
    budgetPerDay: seed.budget,
    needs: seed.needs,
    shareHealthProfile: true,
    status: seed.status,
    offers: [],
    contract: null,
    escrow: null,
    complaint: null,
    days: [],
    messages: [],
    orderId: null,
    declineReason: null,
    cancelReason: null,
    createdAt: iso(seed.created),
    updatedAt: iso(seed.created),
  };

  say(
    row,
    "system",
    `${member.fullName} đã gửi yêu cầu thiết kế thực đơn ${seed.days} ngày (${BOOKING_TYPE_LABEL[seed.type].toLowerCase()}), bắt đầu ${ddmm(startDate)}.`,
    seed.created,
  );
  say(row, "member", seed.needs, seed.created + MIN);
  for (const [by, after, text] of seed.chat ?? []) say(row, by, text, seed.created + after * MIN);

  const offers = seed.offers ?? [];
  const hasContract = offers.length > 0 && seed.status !== "Requested" && seed.status !== "Negotiating" && seed.status !== "Declined";
  const lastOfferAt = offers.length ? seed.created + offers[offers.length - 1][3] * MIN : seed.created;
  const contractAt = lastOfferAt + 90 * MIN;
  offers.forEach(([by, price, note, after], i) => {
    const last = i === offers.length - 1;
    const createdAt = seed.created + after * MIN;
    const offer: BookingOffer = {
      id: `of_${seed.id}_${i + 1}`,
      proposedBy: by,
      price,
      planDays: seed.days,
      bookingType: seed.type,
      startDate,
      note,
      status: !last ? "Superseded" : hasContract ? "Accepted" : "Open",
      createdAt: iso(createdAt),
      respondedAt: !last ? iso(seed.created + offers[i + 1][3] * MIN) : hasContract ? iso(contractAt) : null,
    };
    row.offers.push(offer);
    say(row, by, note, createdAt, offer);
    row.updatedAt = offer.createdAt;
  });
  if (!hasContract) return row;

  const accepted = row.offers[row.offers.length - 1];
  const price = accepted.price;
  const acceptor = accepted.proposedBy === "chef" ? member : chef;
  const paymentDueAt = contractAt + PAYMENT_WINDOW_HOURS * HOUR;
  const paid = PAID_STATUSES.includes(seed.status);
  const qrAt = paid ? contractAt + 40 * MIN : (seed.qrAt ?? contractAt + 10 * MIN);
  const paidAt = qrAt + 2 * MIN;
  const startMs = Date.parse(vnTime(startDate, "00:00"));
  const deliveryDueAt = seed.type === "OneShot" ? Math.max(startMs, (paid ? paidAt : contractAt) + DAY) : Date.parse(vnTime(startDate, "06:00"));

  row.contract = {
    id: `ct_${seed.id}`,
    bookingId: seed.id,
    offerId: accepted.id,
    price,
    planDays: seed.days,
    bookingType: seed.type,
    startDate,
    endDate,
    deliveryDueAt: iso(deliveryDueAt),
    dailySendCutoff: "06:00",
    feedbackCutoff: "21:00",
    scopeText: seed.scope ?? scopeOf(seed),
    feeRate: PLATFORM_FEE_RATE,
    holdDays: ESCROW_HOLD_DAYS,
    paymentDueAt: iso(paymentDueAt),
    createdAt: iso(contractAt),
  };
  row.updatedAt = iso(contractAt);
  say(row, "system", `${acceptor.fullName} đã đồng ý đề xuất ${vnd(price)}. Hồ sơ hợp đồng đã được tạo — thanh toán trước ${when(paymentDueAt)}.`, contractAt);

  if (!seed.orderId) throw new Error(`mock_bookings: ${seed.id} needs an orderId`);
  const order: OrderRow = { id: seed.orderId, bookingId: seed.id, createdAt: iso(contractAt), payments: [], cancelled: null };
  orders.set(order.id, order);
  row.orderId = order.id;
  if (seed.retry) order.payments.push(makePayment(order.id, qrAt - 25 * MIN, price, seed.retry));

  if (!paid) {
    order.payments.push(makePayment(order.id, qrAt, price, seed.status === "Expired" ? "Expired" : "Pending"));
    if (seed.status === "Expired") {
      row.updatedAt = iso(paymentDueAt);
      say(row, "system", `Quá hạn thanh toán ${PAYMENT_WINDOW_HOURS} giờ — yêu cầu đã hết hiệu lực. Thành viên có thể gửi yêu cầu mới.`, paymentDueAt);
    }
    return row;
  }

  const payment = makePayment(order.id, qrAt, price, "Paid", paidAt);
  order.payments.push(payment);
  const releaseAt = escrowReleaseAt(endDate);
  row.escrow = {
    id: `eh_${order.id.replace(/^ord_/, "")}`,
    bookingId: seed.id,
    paymentId: payment.id,
    amount: price,
    status: "Held",
    heldAt: iso(paidAt),
    releaseAt,
    releasedAt: null,
    releasedAmount: 0,
    feeAmount: 0,
    refundedAmount: 0,
    resolvedBy: null,
    resolutionNote: null,
  };
  row.updatedAt = iso(paidAt);
  say(row, "system", `Đã thanh toán ${vnd(price)} qua PaymentOS. VeganLife giữ tiền đến ${when(releaseAt)} (${ESCROW_HOLD_DAYS} ngày sau khi kết thúc kế hoạch).`, paidAt);
  buildDays(seed, row, paidAt, deliveryDueAt);
  if (seed.complaint) buildComplaint(row, seed.complaint);
  if (seed.status === "Completed") autoRelease(row);
  return row;
}

const bookings: BookingRow[] = SEEDS.map(build);
for (const row of bookings) {
  // Events generated "in the future" relative to page load are dropped; transcript oldest first.
  row.messages = row.messages.filter((m) => Date.parse(m.createdAt) <= NOW).sort((a, b) => a.createdAt.localeCompare(b.createdAt));
  row.messages.forEach((m, i) => (m.id = `msg_${row.id}_${i + 1}`));
}

/* ---------------------------------------------------------------- lazy rules */

/** Applied on every read and write (mock clock = wall clock). */
function settle(now: number) {
  for (const row of bookings) {
    const contract = row.contract;
    if (row.status === "AwaitingPayment" && contract && Date.parse(contract.paymentDueAt) < now) {
      row.status = "Expired";
      row.updatedAt = contract.paymentDueAt;
      say(row, "system", `Quá hạn thanh toán ${PAYMENT_WINDOW_HOURS} giờ — yêu cầu đã hết hiệu lực.`, Date.parse(contract.paymentDueAt));
    }
    if (row.status === "Active" && contract && Date.parse(vnTime(addDays(contract.endDate, 1), "00:00")) <= now) {
      row.status = "Ended";
    }
    const escrow = row.escrow;
    if (escrow && escrow.status === "Held" && Date.parse(escrow.releaseAt) <= now && row.complaint?.status !== "Open") {
      autoRelease(row);
    }
  }
}

/* ---------------------------------------------------------------- views */

const fold = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[Đđ]/g, "d").toLowerCase();
const hasFail = (text: string) => text.toLowerCase().includes("#fail");
const unavailable = (what: string) => new ApiError(`Máy chủ đang bận, chưa ${what}. Thử lại sau.`, 503, "unavailable");

const deliveredOf = (row: BookingRow) => row.days.filter((d) => d.status === "Sent").length;

function bookingView(row: BookingRow): Booking {
  return structuredClone({
    id: row.id,
    member: row.member,
    chef: row.chef,
    bookingType: row.bookingType,
    planDays: row.planDays,
    startDate: row.startDate,
    goal: row.goal,
    allergies: row.allergies,
    mealPattern: row.mealPattern,
    budgetPerDay: row.budgetPerDay,
    needs: row.needs,
    shareHealthProfile: row.shareHealthProfile,
    status: row.status,
    deliveredDays: deliveredOf(row),
    currentOffer: row.offers[row.offers.length - 1] ?? null,
    contract: row.contract,
    escrow: row.escrow,
    complaint: row.complaint,
    paymentOrderId: row.orderId,
    declineReason: row.declineReason,
    cancelReason: row.cancelReason,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  });
}

function bookingRef(row: BookingRow): BookingRef {
  return structuredClone({
    id: row.id,
    member: row.member,
    chef: row.chef,
    bookingType: row.bookingType,
    planDays: row.planDays,
    startDate: row.startDate,
    endDate: row.contract?.endDate ?? null,
    status: row.status,
    deliveredDays: deliveredOf(row),
    complaintId: row.complaint?.id ?? null,
    paymentOrderId: row.orderId,
  });
}

function complaintView(row: BookingRow, detail: boolean): AdminComplaint {
  const complaint = row.complaint;
  if (!complaint) throw new Error(`mock_bookings: ${row.id} has no complaint`);
  return {
    ...structuredClone(complaint),
    booking: { ...bookingView(row), complaint: null },
    planDays: detail ? structuredClone(row.days) : [],
    messages: detail ? structuredClone(row.messages) : [],
  };
}

const withComplaint = () => bookings.filter((b): b is BookingRow & { complaint: Complaint } => b.complaint !== null);

/* ---------------------------------------------------------------- admin reads */

/** GET /admin/complaints?status=&search= — Open: oldest first (queue); Resolved: latest decision first. */
export async function listComplaints(query: ComplaintQuery): Promise<AdminComplaint[]> {
  await sleep(400);
  if (hasFail(query.search)) throw unavailable("tải được danh sách khiếu nại");
  settle(Date.now());
  const q = fold(query.search.trim());
  return withComplaint()
    .filter((b) => b.complaint.status === query.status)
    .filter(
      (b) =>
        !q ||
        fold(
          [b.complaint.id, b.id, b.orderId ?? "", b.member.fullName, b.member.email, b.chef.fullName, COMPLAINT_REASON_SHORT[b.complaint.reason]].join(" "),
        ).includes(q),
    )
    .sort((x, y) =>
      query.status === "Open"
        ? x.complaint.createdAt.localeCompare(y.complaint.createdAt)
        : (y.complaint.decidedAt ?? "").localeCompare(x.complaint.decidedAt ?? ""),
    )
    .map((b) => complaintView(b, false));
}

/** GET /admin/complaints/{id} — with plan days and the chat transcript. */
export async function getComplaint(id: string): Promise<AdminComplaint> {
  await sleep(350);
  settle(Date.now());
  const row = withComplaint().find((b) => b.complaint.id === id);
  if (!row) throw new ApiError("Khiếu nại không còn tồn tại.", 404, "not_found");
  return complaintView(row, true);
}

const isActiveHold = (s: EscrowStatus) => s === "Held" || s === "Frozen";

/** GET /admin/escrow/holds?status=&search= — active holds by release date, closed ones latest first. */
export async function listEscrowHolds(query: EscrowHoldQuery): Promise<AdminEscrowHold[]> {
  await sleep(400);
  if (hasFail(query.search)) throw unavailable("tải được danh sách tiền đang giữ");
  settle(Date.now());
  const q = fold(query.search.trim());
  return bookings
    .filter((b): b is BookingRow & { escrow: EscrowHold } => b.escrow !== null)
    .filter((b) => (query.status === "all" ? true : query.status === "active" ? isActiveHold(b.escrow.status) : b.escrow.status === query.status))
    .filter(
      (b) =>
        !q || fold([b.id, b.orderId ?? "", b.complaint?.id ?? "", b.escrow.id, b.member.fullName, b.chef.fullName].join(" ")).includes(q),
    )
    .sort((x, y) => {
      const xa = isActiveHold(x.escrow.status);
      const ya = isActiveHold(y.escrow.status);
      if (xa !== ya) return xa ? -1 : 1;
      return xa
        ? x.escrow.releaseAt.localeCompare(y.escrow.releaseAt)
        : (y.escrow.releasedAt ?? y.complaint?.decidedAt ?? y.escrow.heldAt).localeCompare(x.escrow.releasedAt ?? x.complaint?.decidedAt ?? x.escrow.heldAt);
    })
    .map((b) => ({ ...structuredClone(b.escrow), booking: bookingRef(b) }));
}

/** First instant of the current month in Asia/Ho_Chi_Minh. */
const vnMonthStart = (now: number) => Date.parse(vnTime(`${vnDateOf(now).slice(0, 8)}01`, "00:00"));

/** GET /admin/escrow/summary */
export async function getEscrowSummary(): Promise<EscrowSummary> {
  await sleep(250);
  const now = Date.now();
  settle(now);
  const monthStart = vnMonthStart(now);
  const holds = bookings.map((b) => b.escrow).filter((e): e is EscrowHold => e !== null);
  const sum = (list: EscrowHold[], pick: (e: EscrowHold) => number) => list.reduce((s, e) => s + pick(e), 0);
  const active = holds.filter((e) => isActiveHold(e.status));
  const frozen = holds.filter((e) => e.status === "Frozen");
  const soon = holds.filter((e) => e.status === "Held" && Date.parse(e.releaseAt) <= now + ESCROW_HOLD_DAYS * DAY);
  const releasedThisMonth = holds.filter((e) => e.releasedAt !== null && Date.parse(e.releasedAt) >= monthStart && e.releasedAmount > 0);
  const refundedThisMonth = bookings.filter(
    (b) => b.escrow && b.escrow.refundedAmount > 0 && b.complaint?.decidedAt && Date.parse(b.complaint.decidedAt) >= monthStart,
  );
  return {
    totalHeld: sum(active, (e) => e.amount),
    totalHeldCount: active.length,
    releasingSoon: sum(soon, (e) => e.amount),
    releasingSoonCount: soon.length,
    frozen: sum(frozen, (e) => e.amount),
    frozenCount: frozen.length,
    feeThisMonth: sum(releasedThisMonth, (e) => e.feeAmount),
    releasedThisMonth: sum(releasedThisMonth, (e) => e.releasedAmount),
    releasedThisMonthCount: releasedThisMonth.length,
    refundedThisMonth: refundedThisMonth.reduce((s, b) => s + (b.escrow?.refundedAmount ?? 0), 0),
    openComplaints: withComplaint().filter((b) => b.complaint.status === "Open").length,
    feeRate: PLATFORM_FEE_RATE,
    holdDays: ESCROW_HOLD_DAYS,
  };
}

/* ---------------------------------------------------------------- admin writes */

/**
 * POST /admin/complaints/{id}/decision { decision, refundAmount?, note }.
 * ReleaseToChef: escrow Released (chef nets 90%). RefundMember: Refunded in full to the original
 * payment method. Split: refundAmount back to the member, (price − refundAmount) × 90% to the chef.
 */
export async function decideComplaint(input: ComplaintDecisionInput, session: AdminSession | null): Promise<AdminComplaint> {
  await sleep(700);
  const now = Date.now();
  settle(now);
  const note = input.note.trim();
  const row = withComplaint().find((b) => b.complaint.id === input.complaintId);
  if (!row || !row.contract) throw new ApiError("Khiếu nại không còn tồn tại.", 404, "not_found");
  const errors = decisionErrors({ decision: input.decision, refundAmount: input.refundAmount, note }, row.contract.price);
  if (errors.decision) throw new ApiError(errors.decision, 400, "validation");
  if (errors.refundAmount) throw new ApiError(errors.refundAmount, 400, "invalid_refund_amount");
  if (errors.note) throw new ApiError(errors.note, 400, "note_too_short");
  if (hasFail(note)) throw unavailable("lưu được quyết định");

  if (row.complaint.id === QA_409_COMPLAINT && row.complaint.status === "Open") {
    applyDecision(
      row,
      "ReleaseToChef",
      undefined,
      "Chuyên gia đã gửi lại hướng dẫn lên men qua chat, thành viên xác nhận đã nhận đủ nên giữ nguyên thanh toán.",
      "Lê Minh Quân",
      now - 40_000,
    );
  }
  if (row.complaint.status !== "Open") {
    throw new ApiError(
      `Khiếu nại đã được ${row.complaint.decidedBy ?? "quản trị viên khác"} xử lý lúc ${row.complaint.decidedAt ? when(row.complaint.decidedAt) : "trước đó"}.`,
      409,
      "already_decided",
    );
  }

  const actor = session?.fullName ?? "Quản trị viên";
  applyDecision(row, input.decision, input.refundAmount, note, actor, now);
  const out = decisionOutcome(row.contract.price, input.decision, input.refundAmount);
  logAction(
    actor,
    "quyết định khiếu nại",
    `${row.complaint.id} · ${COMPLAINT_DECISION_LABEL[input.decision]}${out.refund > 0 ? ` · hoàn ${vnd(out.refund)}` : ""}`,
  );
  return complaintView(row, true);
}

/* ---------------------------------------------------------------- orders (read by mock_commerce) */

function orderView(order: OrderRow, now: number): AdminOrder {
  const row = bookings.find((b) => b.id === order.bookingId);
  if (!row || !row.contract) throw new Error(`mock_bookings: order ${order.id} has no booking`);
  const escrow = row.escrow;
  let status: OrderStatus;
  if (order.cancelled) status = "Cancelled";
  else if (escrow) status = escrow.status === "Refunded" ? "Refunded" : escrow.status === "PartiallyRefunded" ? "PartiallyRefunded" : "Paid";
  else if (row.status === "Expired" || row.status === "Cancelled") status = "Cancelled";
  else status = "Pending";

  const complaint = row.complaint;
  const resolution: OrderResolution | null =
    order.cancelled ??
    (complaint?.status === "Resolved" && complaint.decision
      ? {
          action: complaint.decision === "ReleaseToChef" ? "release" : complaint.decision === "RefundMember" ? "refund" : "partial_refund",
          note: complaint.adminNote ?? "",
          by: complaint.decidedBy ?? "",
          at: complaint.decidedAt ?? row.updatedAt,
          complaintId: complaint.id,
        }
      : null);

  return {
    id: order.id,
    userId: row.member.id,
    buyer: { ...row.member },
    bookingId: row.id,
    booking: {
      id: row.id,
      chefId: row.chef.id,
      chefName: row.chef.fullName,
      bookingType: row.bookingType,
      planDays: row.planDays,
      startDate: row.contract.startDate,
      endDate: row.contract.endDate,
      status: row.status,
      deliveredDays: deliveredOf(row),
      complaintId: complaint?.id ?? null,
    },
    amount: row.contract.price,
    status,
    createdAt: order.createdAt,
    payments: order.payments.map((p) => ({
      ...p,
      status: p.status === "Pending" && p.expiresAt !== null && Date.parse(p.expiresAt) < now ? "Expired" : p.status,
    })),
    escrow: escrow ? { ...escrow } : null,
    refundedAmount: escrow?.refundedAmount ?? 0,
    resolution: resolution && { ...resolution },
  };
}

/** Every booking order, time-derived statuses applied. */
export function allOrders(now = Date.now()): AdminOrder[] {
  settle(now);
  return [...orders.values()].map((o) => orderView(o, now));
}

/**
 * Admin cancel of an unpaid booking order (validation of the note is done by the caller).
 * Pending only: open QR codes expire and the booking is cancelled.
 */
export function cancelOrder(orderId: string, note: string, actor: string, now = Date.now()): AdminOrder {
  settle(now);
  const order = orders.get(orderId);
  if (!order) throw new ApiError("Đơn hàng không còn tồn tại.", 404, "not_found");
  if (orderView(order, now).status !== "Pending") {
    throw new ApiError("Chỉ huỷ được đơn đang chờ thanh toán.", 409, "not_pending");
  }
  const row = bookings.find((b) => b.id === order.bookingId);
  order.cancelled = { action: "cancel", note, by: actor, at: iso(now), complaintId: null };
  for (const p of order.payments) if (p.status === "Pending") p.status = "Expired";
  if (row) {
    row.status = "Cancelled";
    row.cancelReason = note;
    row.updatedAt = iso(now);
    say(row, "system", `Ban quản trị đã huỷ đơn thanh toán: “${note}”`, now);
  }
  return orderView(order, now);
}

/* ---------------------------------------------------------------- wallet feed (read by mock_payouts) */

export interface EscrowLedgerEntry {
  chefId: string;
  bookingId: string;
  orderId: string | null;
  memberName: string;
  planTitle: string;
  transactionRef: string | null;
  amount: number;
  heldAt: ISODateString;
  status: EscrowStatus;
  releaseAt: ISODateString;
  releasedAt: ISODateString | null;
  releasedAmount: number;
  feeAmount: number;
  refundedAmount: number;
  complaintId: string | null;
  decidedAt: ISODateString | null;
}

/** One entry per paid booking: what the chef wallet ledger is derived from. */
export function escrowLedger(now = Date.now()): EscrowLedgerEntry[] {
  settle(now);
  return bookings
    .filter((b): b is BookingRow & { escrow: EscrowHold } => b.escrow !== null)
    .map((b) => {
      const order = b.orderId ? orders.get(b.orderId) : undefined;
      const paid = order?.payments.find((p) => p.paidAt !== null);
      return {
        chefId: b.chef.id,
        bookingId: b.id,
        orderId: b.orderId,
        memberName: b.member.fullName,
        planTitle: `Thực đơn ${b.planDays} ngày · ${BOOKING_TYPE_LABEL[b.bookingType]}`,
        transactionRef: paid?.transactionRef ?? null,
        amount: b.escrow.amount,
        heldAt: b.escrow.heldAt,
        status: b.escrow.status,
        releaseAt: b.escrow.releaseAt,
        releasedAt: b.escrow.releasedAt,
        releasedAmount: b.escrow.releasedAmount,
        feeAmount: b.escrow.feeAmount,
        refundedAmount: b.escrow.refundedAmount,
        complaintId: b.complaint?.id ?? null,
        decidedAt: b.complaint?.decidedAt ?? null,
      };
    });
}
