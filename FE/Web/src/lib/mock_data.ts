// src/lib/mock_data.ts
// In-memory mock backend with realistic latency. Used when NEXT_PUBLIC_USE_MOCK_DATA !== "false".
import type {
  AiFlag,
  AiLog,
  AiLogDetail,
  AiLogLabel,
  AiLogLabelInput,
  AiLogQuery,
  AiTaskType,
  Author,
  CategoryScore,
  ContentType,
  FlagCategory,
  FlagQueueQuery,
  FlagSpan,
  FlagStatus,
  ModerationAction,
  ModerationDecision,
  ModerationDecisionInput,
  Post,
  TelemetryRange,
  TelemetrySummary,
} from "@/types/moderation";
import { MIN_AUDIT_NOTE_LENGTH } from "@/types/moderation";

import { ApiError } from "./api_error";

/* ---------------------------------------------------------------- helpers */

/** Deterministic PRNG so the seed data is stable between reloads. */
function mulberry32(seed: number) {
  let a = seed;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = mulberry32(42);
const between = (min: number, max: number) => Math.round(min + rand() * (max - min));

export const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms + Math.random() * 250));

const minutesAgo = (m: number) => new Date(Date.now() - m * 60_000).toISOString();
const traceId = () => Math.floor(rand() * 0xffffff).toString(16).padStart(6, "0");

function spansFor(text: string, phrases: [string, FlagCategory][]): FlagSpan[] {
  return phrases
    .map(([phrase, category]) => {
      const start = text.toLowerCase().indexOf(phrase.toLowerCase());
      return start < 0 ? null : { start, end: start + phrase.length, category };
    })
    .filter((s): s is FlagSpan => s !== null)
    .sort((a, b) => a.start - b.start);
}

function author(id: string, displayName: string, handle: string, priorWarnings = 0): Author {
  return { id, displayName, handle, priorWarnings, avatarUrl: null, joinedAt: minutesAgo(60 * 24 * between(20, 400)) };
}

function post(
  id: string,
  type: ContentType,
  a: Author,
  text: string,
  extra: Partial<Pick<Post, "media" | "ingredientTags" | "reportCount" | "visibility">> & { ageMin: number },
): Post {
  return {
    id,
    type,
    author: a,
    text,
    media: extra.media ?? [],
    ingredientTags: extra.ingredientTags ?? [],
    createdAt: minutesAgo(extra.ageMin),
    stats: { likes: between(3, 400), comments: between(0, 60), reach: between(200, 6000) },
    reportCount: extra.reportCount ?? between(0, 4),
    visibility: extra.visibility ?? "visible",
  };
}

function scores(primary: FlagCategory, confidence: number, others: Partial<Record<FlagCategory, number>>): CategoryScore[] {
  const all: Record<FlagCategory, number> = {
    health_misinformation: 0.02,
    harassment: 0.02,
    toxicity: 0.03,
    spam_promo: 0.04,
    not_vegan: 0.01,
    copyright: 0.01,
    ...others,
    [primary]: confidence,
  };
  return (Object.entries(all) as [FlagCategory, number][])
    .map(([category, score]) => ({ category, score }))
    .sort((a, b) => b.score - a.score);
}

/* ------------------------------------------------------------------ flags */

interface SeedFlag {
  id: string;
  status: FlagStatus;
  post: Post;
  primary: FlagCategory;
  confidence: number;
  toxicity: number;
  others?: Partial<Record<FlagCategory, number>>;
  reason: string;
  phrases: [string, FlagCategory][];
  suggested: ModerationAction;
  policy: string;
  ageMin: number;
}

function buildFlag(s: SeedFlag): AiFlag {
  return {
    id: s.id,
    postId: s.post.id,
    post: s.post,
    status: s.status,
    primaryCategory: s.primary,
    confidence: s.confidence,
    toxicityScore: s.toxicity,
    scores: scores(s.primary, s.confidence, s.others ?? {}),
    reason: s.reason,
    spans: spansFor(s.post.text, s.phrases),
    suggestedAction: s.suggested,
    policyRef: s.policy,
    modelVersion: "moderation-v3",
    latencyMs: between(280, 620),
    traceId: traceId(),
    createdAt: minutesAgo(s.ageMin),
  };
}

const greenbowl = author("u_greenbowl", "Green Bowl HN", "greenbowl.hn", 1);
const linh = author("u_linh", "Linh Cooks", "linh.cooks");
const minh = author("u_minh", "Minh Vegan", "minh.vegan", 2);
const bepchay = author("u_bepchay", "Bếp Chay Sài Gòn", "bepchay.sg");
const an = author("u_an", "An Eats", "an.eats");
const quynh = author("u_quynh", "Quỳnh Kitchen", "quynh.kitchen");
const thao = author("u_thao", "Thảo Mộc", "thaomoc.daily", 1);

const seed: SeedFlag[] = [
  {
    id: "flag_1001",
    status: "pending",
    post: post(
      "post_9001",
      "post",
      greenbowl,
      "Ăn sống thuần chay chữa khỏi tiểu đường type 2 trong 30 ngày. Hãy ngưng thuốc metformin và thử detox nước ép 3 ngày của mình trước! Link ở bio.",
      { ageMin: 134, reportCount: 6, visibility: "auto_hidden", media: [{ url: "", alt: "3 chai nước ép cần tây" }], ingredientTags: ["cần tây", "gừng", "chanh"] },
    ),
    primary: "health_misinformation",
    confidence: 0.91,
    toxicity: 0.06,
    others: { spam_promo: 0.48 },
    reason: "Khuyên người đọc ngưng thuốc điều trị đã được kê đơn và hứa hẹn chữa khỏi bệnh.",
    phrases: [
      ["chữa khỏi tiểu đường type 2 trong 30 ngày", "health_misinformation"],
      ["ngưng thuốc metformin", "health_misinformation"],
      ["Link ở bio", "spam_promo"],
    ],
    suggested: "reject",
    policy: "§4.2 Tuyên bố y tế",
    ageMin: 134,
  },
  {
    id: "flag_1002",
    status: "pending",
    post: post("post_9002", "comment", linh, "Không ai cần món đậu lăng nhạt nhẽo của bạn đâu, biến đi cho rảnh.", { ageMin: 112, reportCount: 3 }),
    primary: "harassment",
    confidence: 0.84,
    toxicity: 0.79,
    others: { toxicity: 0.79 },
    reason: "Bình luận công kích cá nhân, yêu cầu người khác rời cộng đồng.",
    phrases: [["biến đi cho rảnh", "harassment"], ["nhạt nhẽo", "toxicity"]],
    suggested: "warn",
    policy: "§2.1 Tôn trọng thành viên",
    ageMin: 112,
  },
  {
    id: "flag_1003",
    status: "pending",
    post: post(
      "post_9003",
      "video",
      minh,
      "Nhập mã GREEN50 tại shop thực phẩm chức năng của mình để giảm 50%, inbox ngay để được tư vấn liều dùng!",
      { ageMin: 80, media: [{ url: "", alt: "Video 0:42 giới thiệu sản phẩm" }] },
    ),
    primary: "spam_promo",
    confidence: 0.77,
    toxicity: 0.04,
    others: { health_misinformation: 0.31 },
    reason: "Quảng cáo bán hàng kèm tư vấn liều dùng thực phẩm chức năng.",
    phrases: [["Nhập mã GREEN50", "spam_promo"], ["inbox ngay", "spam_promo"], ["tư vấn liều dùng", "health_misinformation"]],
    suggested: "reject",
    policy: "§5.1 Quảng cáo",
    ageMin: 80,
  },
  {
    id: "flag_1004",
    status: "pending",
    post: post(
      "post_9004",
      "recipe",
      bepchay,
      "Nước chấm chay chuẩn vị: 3 muỗng nước mắm, 2 muỗng đường, tỏi ớt băm, vắt thêm chanh.",
      { ageMin: 58, ingredientTags: ["nước mắm", "đường", "tỏi", "ớt", "chanh"] },
    ),
    primary: "not_vegan",
    confidence: 0.69,
    toxicity: 0.01,
    reason: "Công thức gắn nhãn chay nhưng dùng nước mắm (từ cá).",
    phrases: [["nước mắm", "not_vegan"]],
    suggested: "warn",
    policy: "§3.4 Nhãn thuần chay",
    ageMin: 58,
  },
  {
    id: "flag_1005",
    status: "pending",
    post: post("post_9005", "post", an, "Mấy người ăn thịt đúng là ngu, nói chuyện với họ chỉ phí thời gian.", { ageMin: 31, reportCount: 2 }),
    primary: "toxicity",
    confidence: 0.73,
    toxicity: 0.73,
    others: { harassment: 0.41 },
    reason: "Xúc phạm một nhóm người dựa trên lựa chọn ăn uống.",
    phrases: [["đúng là ngu", "toxicity"]],
    suggested: "warn",
    policy: "§2.3 Ngôn từ xúc phạm",
    ageMin: 31,
  },
  {
    id: "flag_1006",
    status: "pending",
    post: post(
      "post_9006",
      "video",
      quynh,
      "Video nấu phở chay mình tải lại từ kênh của người khác, mọi người xem cho vui nha.",
      { ageMin: 12, media: [{ url: "", alt: "Video 12:48 nấu phở chay" }] },
    ),
    primary: "copyright",
    confidence: 0.58,
    toxicity: 0.02,
    reason: "Người đăng cho biết video được tải lại từ kênh khác, có thể chưa xin phép.",
    phrases: [["tải lại từ kênh của người khác", "copyright"]],
    suggested: "approve",
    policy: "§6.1 Bản quyền",
    ageMin: 12,
  },
  {
    id: "flag_1007",
    status: "escalated",
    post: post(
      "post_9007",
      "post",
      thao,
      "Uống giấm táo mỗi sáng thay cho thuốc huyết áp, mình đã ngưng thuốc 2 tuần rồi mà vẫn khoẻ.",
      { ageMin: 300, reportCount: 9, visibility: "auto_hidden" },
    ),
    primary: "health_misinformation",
    confidence: 0.88,
    toxicity: 0.03,
    reason: "Chia sẻ việc tự ngưng thuốc huyết áp, có thể khiến người khác làm theo.",
    phrases: [["thay cho thuốc huyết áp", "health_misinformation"], ["ngưng thuốc 2 tuần", "health_misinformation"]],
    suggested: "reject",
    policy: "§4.2 Tuyên bố y tế",
    ageMin: 300,
  },
];

const flags: AiFlag[] = seed.map(buildFlag);
const decisions: ModerationDecision[] = [];

/**
 * Live moderation decisions (flag queue + pending-post reviews) feeding the
 * accuracy metrics on /ai-models. `upheld` = the admin agreed with the flag.
 */
export interface DecisionSample {
  category: FlagCategory;
  upheld: boolean;
  minutesToDecide: number;
  decidedAt: string;
}

const decisionSamples: DecisionSample[] = [];

export function recordDecisionSample(sample: DecisionSample) {
  decisionSamples.unshift(sample);
  decisionSamples.splice(500);
}

export function getDecisionSamples(): DecisionSample[] {
  return decisionSamples.map((s) => ({ ...s }));
}

export function getOpenFlagCount(): number {
  return flags.filter((f) => f.status !== "resolved").length;
}

export async function listFlags(query: FlagQueueQuery): Promise<AiFlag[]> {
  await sleep(450);
  const search = query.search?.trim().toLowerCase();
  return flags
    .filter((f) => f.status === query.status)
    .filter((f) => !query.category || query.category === "all" || f.primaryCategory === query.category)
    .filter(
      (f) =>
        !search ||
        f.post.text.toLowerCase().includes(search) ||
        f.post.author.handle.toLowerCase().includes(search) ||
        f.reason.toLowerCase().includes(search),
    )
    .sort((a, b) => a.createdAt.localeCompare(b.createdAt)) // oldest first (SLA)
    .map((f) => structuredClone(f));
}

export async function getFlagCounts(): Promise<Record<FlagStatus, number>> {
  await sleep(150);
  return {
    pending: flags.filter((f) => f.status === "pending").length,
    escalated: flags.filter((f) => f.status === "escalated").length,
    resolved: flags.filter((f) => f.status === "resolved").length,
  };
}

export async function decide(input: ModerationDecisionInput): Promise<ModerationDecision> {
  await sleep(700);
  if (input.note.trim().length < MIN_AUDIT_NOTE_LENGTH) {
    throw new ApiError(`Ghi chú kiểm duyệt cần ít nhất ${MIN_AUDIT_NOTE_LENGTH} ký tự.`, 400, "note_too_short");
  }
  if (input.note.includes("#fail")) {
    throw new ApiError("Máy chủ kiểm duyệt đang bận. Quyết định chưa được lưu.", 503, "unavailable");
  }
  const flag = flags.find((f) => f.id === input.flagId);
  if (!flag) throw new ApiError("Không tìm thấy mục cần duyệt.", 404, "not_found");
  if (flag.status === "resolved") throw new ApiError("Mục này đã được người khác xử lý.", 409, "already_resolved");

  flag.status = "resolved";
  flag.post.visibility = input.action === "reject" ? "removed" : "visible";

  const decision: ModerationDecision = {
    ...input,
    id: `dec_${Date.now()}`,
    postId: flag.postId,
    adminId: "admin_01",
    adminName: "Quản trị viên",
    modelVersion: flag.modelVersion,
    scoresSnapshot: flag.scores,
    decidedAt: new Date().toISOString(),
  };
  decisions.unshift(decision);
  recordDecisionSample({
    category: flag.primaryCategory,
    upheld: input.action !== "approve",
    minutesToDecide: Math.max(1, Math.round((Date.now() - new Date(flag.createdAt).getTime()) / 60_000)),
    decidedAt: decision.decidedAt,
  });
  return decision;
}

/* ---------------------------------------------------------------- ai_logs */

/**
 * Generator settings driven by /ai-models (mock_ai_models.ts calls
 * `configureGenerator`): a disabled task stops producing logs, `version`
 * becomes the log's `model`, and `threshold` decides moderation flags
 * (score ≥ threshold) and which vision labels count.
 */
export interface GeneratorSettings {
  enabled: boolean;
  version: string;
  threshold: number | null;
}

const generator: Record<AiTaskType, GeneratorSettings> = {
  moderation: { enabled: true, version: "moderation-v3", threshold: 0.6 },
  chatbot: { enabled: true, version: "llm-primary@v14", threshold: null },
  meal_plan: { enabled: true, version: "llm-primary@v14", threshold: null },
  vision_scan: { enabled: true, version: "vision-v2", threshold: 0.7 },
};

export function configureGenerator(task: AiTaskType, settings: Partial<GeneratorSettings>) {
  generator[task] = { ...generator[task], ...settings };
}

const TASK_WEIGHTS: [AiTaskType, number][] = [
  ["chatbot", 0.55],
  ["moderation", 0.25],
  ["meal_plan", 0.12],
  ["vision_scan", 0.08],
];

/** Weighted pick among enabled tasks; null when every model is turned off. */
function pickTask(): AiTaskType | null {
  const enabled = TASK_WEIGHTS.filter(([task]) => generator[task].enabled);
  const total = enabled.reduce((s, [, w]) => s + w, 0);
  if (total === 0) return null;
  let r = Math.random() * total;
  for (const [task, w] of enabled) {
    if ((r -= w) <= 0) return task;
  }
  return enabled[enabled.length - 1][0];
}

/** Posts the moderation calls point at. Ids mirror mock_admin.ts content so `/content?open=` works. */
const MODERATION_REFS: { id: string; text: string; category: FlagCategory; risky: boolean }[] = [
  { id: "p_detox", risky: true, category: "health_misinformation", text: "Uống nước ép cần tây 7 ngày, mình đã ngưng thuốc tiểu đường!\nBác sĩ bảo phải uống thuốc suốt đời nhưng nước ép cần tây đã chữa khỏi cho mình…" },
  { id: "p_flan", risky: true, category: "not_vegan", text: "Bánh flan chay mềm mịn (dùng trứng gà ta cho béo)\nMình thêm 2 lòng đỏ trứng gà ta để bánh mịn hơn…" },
  { id: "p_detox_tea", risky: true, category: "spam_promo", text: "Trà detox thảo mộc giảm mỡ bụng — inbox Zalo nhận ưu đãi\nCam kết hoàn tiền nếu không giảm 5 kg trong 2 tuần." },
  { id: "p_iq", risky: true, category: "health_misinformation", text: "Ăn chay lâu năm có làm giảm trí nhớ không?\nĐọc trên mạng thấy bảo ăn chay thiếu B12 dễ giảm trí nhớ…" },
  { id: "p_bun_rieu", risky: false, category: "not_vegan", text: "Bún riêu chay cà chua đậu hũ — nước dùng ngọt từ củ quả\nNguyên liệu (4 người): 6 quả cà chua, 2 bìa đậu hũ, 300 g nấm rơm…" },
  { id: "p_b12", risky: false, category: "health_misinformation", text: "Mới ăn chay 3 tuần, nên bổ sung B12 thế nào?\nMình ăn chay trường được 3 tuần, hay bị mệt buổi chiều…" },
  { id: "p_dam_thuc_vat", risky: false, category: "spam_promo", text: "5 nguồn đạm thực vật rẻ mà chợ nào cũng có\nĐậu hũ, đậu xanh nguyên vỏ, đậu phộng, mè đen và tàu hũ ky…" },
  { id: "p_video_lau", risky: false, category: "copyright", text: "Lẩu nấm chay 15 phút cho ngày mưa\nNước lẩu từ nấm đông cô và củ cải…" },
  { id: "p_dau_hu_sot_ca", risky: false, category: "not_vegan", text: "Đậu hũ sốt cà chua kiểu Bắc — 15 phút\nRán vàng 2 bìa đậu, xào 3 quả cà chua với hành lá…" },
];

const CHAT_SAMPLES: { q: string; a: string }[] = [
  {
    q: "Ăn chay trường có cần uống thêm B12 không? Mình nữ, 25 tuổi, ăn chay được 1 năm.",
    a: "Có. Thực vật gần như không cung cấp vitamin B12, nên người ăn thuần chay cần bổ sung đều đặn bằng viên uống hoặc thực phẩm tăng cường (sữa hạt, ngũ cốc có bổ sung B12) [1]. Bạn nên xét nghiệm B12 định kỳ và hỏi bác sĩ về liều phù hợp [2].",
  },
  {
    q: "Gợi ý bữa sáng chay khoảng 25 g đạm, nấu dưới 15 phút?",
    a: "Bạn có thể kết hợp: 1 ly sữa đậu nành không đường (~7 g đạm), 2 lát bánh mì nguyên cám phết bơ đậu phộng (~10 g), 100 g đậu hũ non áp chảo (~8 g). Tổng khoảng 25 g đạm, nấu trong 10 phút [1].",
  },
  {
    q: "Ăn đậu hũ mỗi ngày có ảnh hưởng nội tiết không?",
    a: "Ở mức 2–3 phần đậu nành mỗi ngày, các nghiên cứu hiện có không cho thấy ảnh hưởng xấu tới nội tiết ở người khoẻ mạnh [1]. Nếu bạn đang điều trị bệnh tuyến giáp, hãy uống thuốc cách bữa ăn có đậu nành ít nhất 4 giờ và hỏi bác sĩ [2].",
  },
  {
    q: "Người tiền tiểu đường ăn chay nên chọn tinh bột nào?",
    a: "Ưu tiên tinh bột nguyên hạt và ít tinh chế: gạo lứt, yến mạch nguyên hạt, khoai lang, các loại đậu. Ghép cùng rau và đạm thực vật để đường huyết tăng chậm hơn [1]. Đây là thông tin tham khảo, không thay cho chỉ định của bác sĩ.",
  },
];

const MEAL_PLAN_SAMPLES: { input: string; output: string }[] = [
  {
    input: "Hồ sơ: nữ, 24 tuổi, 158 cm, 52 kg (BMI 20,8) · Mục tiêu: Giữ cân · Dị ứng: đậu phộng\nYêu cầu: thực đơn 7 ngày, khoảng 1.800 kcal/ngày, ưu tiên món Việt.",
    output: "Thứ 2 — Sáng: Yến mạch sữa hạt điều (420 kcal) · Trưa: Cơm gạo lứt, đậu hũ sốt cà (610 kcal) · Tối: Bún riêu chay (520 kcal)\nThứ 3 — Sáng: Xôi đậu xanh (450 kcal) · Trưa: Phở chay nấm (560 kcal) · Tối: Canh bí đỏ, cơm lứt (540 kcal)\n…\nTrung bình 1.790 kcal/ngày · đạm 68 g · không chứa đậu phộng.",
  },
  {
    input: "Hồ sơ: nam, 31 tuổi, 172 cm, 78 kg (BMI 26,4) · Mục tiêu: Giảm cân · Dị ứng: không\nYêu cầu: thực đơn 7 ngày, khoảng 1.900 kcal/ngày, nhiều đạm.",
    output: "Thứ 2 — Sáng: Bánh mì nguyên cám, trứng đậu hũ non (480 kcal) · Trưa: Cơm lứt, tempeh kho (640 kcal) · Tối: Salad đậu gà, súp nấm (520 kcal)\n…\nTrung bình 1.880 kcal/ngày · đạm 96 g.",
  },
];

const VISION_LABELS = ["cà chua", "đậu hũ", "nấm rơm", "cải thìa", "hành lá", "cà rốt", "bông cải xanh", "ớt chuông", "chanh", "gừng"];

/** Data needed to rebuild a log's input/output text on demand. */
interface LogExtra {
  seed: number;
  score?: number;
  category?: FlagCategory;
  labels?: { name: string; confidence: number }[];
}

const extras = new Map<string, LogExtra>();
const logLabels = new Map<string, AiLogLabel & { task: AiTaskType }>();

function makeLog(at: Date): AiLog | null {
  const task = pickTask();
  if (!task) return null;
  const { version, threshold } = generator[task];
  const seedN = Math.floor(Math.random() * 1e6);
  const id = `log_${at.getTime()}_${seedN}`;
  const trace = Math.floor(Math.random() * 0xffffff).toString(16).padStart(6, "0");
  const roll = Math.random();
  const base = { id, timestamp: at.toISOString(), task, model: version, traceId: trace };

  switch (task) {
    case "chatbot": {
      extras.set(id, { seed: seedN });
      const ref = { refType: "chat_session", refId: `cs_${1000 + (seedN % 900)}` };
      if (roll < 0.015) {
        return { ...base, ...ref, latencyMs: 12000, inputTokens: 2100, outputTokens: 0, status: "error", detail: "timeout → fallback" };
      }
      const cites = 1 + (seedN % 3);
      return { ...base, ...ref, latencyMs: 900 + Math.round(Math.random() * 2800), inputTokens: 1400 + Math.round(Math.random() * 900), outputTokens: 200 + Math.round(Math.random() * 400), status: "success", detail: `ok · ${cites} trích dẫn` };
    }
    case "moderation": {
      const risky = roll < 0.12;
      const score = risky ? 0.5 + Math.random() * 0.48 : Math.random() * 0.3;
      const flagged = score >= (threshold ?? 0.6);
      const pool = MODERATION_REFS.filter((r) => r.risky === risky);
      const target = pool[seedN % pool.length];
      extras.set(id, { seed: seedN, score, category: target.category });
      return { ...base, refType: "post", refId: target.id, latencyMs: 250 + Math.round(Math.random() * 500), inputTokens: 300 + Math.round(Math.random() * 500), outputTokens: 24, status: flagged ? "warning" : "success", detail: flagged ? `gắn cờ · ${score.toFixed(2)}` : `sạch · ${score.toFixed(2)}`, flagged };
    }
    case "meal_plan": {
      extras.set(id, { seed: seedN });
      const failed = roll < 0.02;
      return { ...base, refType: "meal_plan", refId: `mp_${2000 + (seedN % 900)}`, latencyMs: 4000 + Math.round(Math.random() * 6000), inputTokens: 2000 + Math.round(Math.random() * 800), outputTokens: 900 + Math.round(Math.random() * 700), status: failed ? "error" : "success", detail: failed ? "invalid_json → retry" : "ok · 7 ngày" };
    }
    case "vision_scan": {
      const lowLight = roll < 0.05;
      const start = seedN % VISION_LABELS.length;
      const labels = lowLight
        ? []
        : Array.from({ length: 7 }, (_, i) => ({
            name: VISION_LABELS[(start + i) % VISION_LABELS.length],
            confidence: Number((0.98 - i * 0.06 - Math.random() * 0.04).toFixed(2)),
          }));
      extras.set(id, { seed: seedN, labels });
      const detected = labels.filter((l) => l.confidence >= (threshold ?? 0.7)).length;
      return { ...base, refType: "user_ingredients", refId: `ui_${3000 + (seedN % 900)}`, latencyMs: 700 + Math.round(Math.random() * 1800), inputTokens: 0, outputTokens: 0, status: lowLight ? "warning" : "success", detail: lowLight ? "low_light_rejected" : `ok · ${detected} nguyên liệu` };
    }
  }
}

const logs: AiLog[] = Array.from({ length: 40 }, (_, i) => makeLog(new Date(Date.now() - (40 - i) * 7000))).filter(
  (l): l is AiLog => l !== null,
);
let lastGenerated = Date.now();

/** Each poll appends the calls that "happened" since the previous poll. */
function tick() {
  const now = Date.now();
  const elapsed = now - lastGenerated;
  const count = Math.min(6, Math.floor(elapsed / 1500));
  for (let i = count; i > 0; i--) {
    const log = makeLog(new Date(now - i * 400));
    if (log) logs.push(log);
  }
  if (count > 0) lastGenerated = now;
  if (logs.length > 500) {
    for (const pruned of logs.splice(0, logs.length - 500)) extras.delete(pruned.id);
  }
}

export async function listLogs(query: AiLogQuery): Promise<AiLog[]> {
  await sleep(200);
  tick();
  return logs
    .filter((l) => query.task === "all" || l.task === query.task)
    .slice(-query.limit)
    .reverse()
    .map((l) => ({ ...l }));
}

const formatBytes = (n: number) => `${Math.round(n / 1000)} KB`;

/** Deterministic input_text / output_text for a log (the mock does not store them). */
function describeLog(log: AiLog): { inputText: string; outputText: string } {
  const extra = extras.get(log.id) ?? { seed: 0 };
  switch (log.task) {
    case "moderation": {
      const target = MODERATION_REFS.find((r) => r.id === log.refId) ?? MODERATION_REFS[0];
      const score = Number((extra.score ?? 0).toFixed(2));
      return {
        inputText: target.text,
        outputText: JSON.stringify({ flagged: log.flagged ?? false, category: extra.category ?? target.category, score }, null, 2),
      };
    }
    case "chatbot": {
      const sample = CHAT_SAMPLES[extra.seed % CHAT_SAMPLES.length];
      return {
        inputText: sample.q,
        outputText:
          log.status === "error"
            ? "(Không có đầu ra — hết thời gian chờ 12 s, ứng dụng hiện câu trả lời dự phòng.)"
            : `${sample.a}\n\nNguồn: [1] WHO — Healthy diet fact sheet · [2] Tài liệu chuyên gia đã duyệt`,
      };
    }
    case "meal_plan": {
      const sample = MEAL_PLAN_SAMPLES[extra.seed % MEAL_PLAN_SAMPLES.length];
      return {
        inputText: sample.input,
        outputText: log.status === "error" ? '{"days":[{"day":"Thứ 2","meals":[{"slot":"breakfast","name":"Yến mạch sữa hạt' : sample.output,
      };
    }
    case "vision_scan": {
      const labels = extra.labels ?? [];
      const threshold = generator.vision_scan.threshold ?? 0.7;
      return {
        inputText: `fridge.jpg 1280×960 · ${formatBytes(180_000 + (extra.seed % 400) * 1000)}`,
        outputText:
          log.status === "warning"
            ? "Ảnh quá tối (độ sáng 0,18) — yêu cầu người dùng chụp lại dưới đèn."
            : labels
                .map((l) => `${l.confidence >= threshold ? "✓" : "·"} ${l.name} (${l.confidence.toFixed(2)})`)
                .join("\n"),
      };
    }
  }
}

function toDetail(log: AiLog): AiLogDetail {
  const label = logLabels.get(log.id);
  return {
    ...log,
    ...describeLog(log),
    label: label ? { verdict: label.verdict, note: label.note, by: label.by, at: label.at } : undefined,
  };
}

export async function getLogDetail(id: string): Promise<AiLogDetail> {
  await sleep(250);
  const log = logs.find((l) => l.id === id);
  if (!log) throw new ApiError("Bản ghi đã quá cũ, không còn lưu nội dung chi tiết.", 404, "not_found");
  return toDetail(log);
}

export async function labelLog(input: AiLogLabelInput, by: string): Promise<AiLogDetail> {
  await sleep(400);
  if (input.note?.includes("#fail")) {
    throw new ApiError("Máy chủ đang bận, chưa lưu được đánh giá. Thử lại sau.", 503, "unavailable");
  }
  const log = logs.find((l) => l.id === input.logId);
  if (!log) throw new ApiError("Bản ghi đã quá cũ, không còn lưu nội dung chi tiết.", 404, "not_found");
  logLabels.set(log.id, { verdict: input.verdict, note: input.note?.trim() || undefined, by, at: new Date().toISOString(), task: log.task });
  return toDetail(log);
}

/** Admin labels so far (ai_log_labels), for the accuracy table on /ai-models. */
export function getLogLabels(): { task: AiTaskType; correct: boolean }[] {
  return [...logLabels.values()].map((l) => ({ task: l.task, correct: l.verdict === "correct" }));
}

const RANGE_SCALE: Record<TelemetryRange, number> = { "1h": 1 / 24, "24h": 1, "7d": 7 };

export async function getTelemetrySummary(range: TelemetryRange): Promise<TelemetrySummary> {
  await sleep(350);
  const scale = RANGE_SCALE[range];
  const jitter = () => 1 + (Math.random() - 0.5) * 0.02;
  const byTask = [
    { task: "chatbot" as const, calls: Math.round(61204 * scale * jitter()), avgLatencyMs: 1650, p95LatencyMs: 3800, errorRate: 0.009 },
    { task: "moderation" as const, calls: Math.round(18930 * scale * jitter()), avgLatencyMs: 410, p95LatencyMs: 840, errorRate: 0.004 },
    { task: "meal_plan" as const, calls: Math.round(1466 * scale * jitter()), avgLatencyMs: 6900, p95LatencyMs: 9800, errorRate: 0.011 },
    { task: "vision_scan" as const, calls: Math.round(4812 * scale * jitter()), avgLatencyMs: 1250, p95LatencyMs: 2600, errorRate: 0.047 },
  ];
  const totalCalls = byTask.reduce((s, t) => s + t.calls, 0);
  const weighted = (key: "avgLatencyMs" | "errorRate") =>
    byTask.reduce((s, t) => s + t[key] * t.calls, 0) / Math.max(1, totalCalls);

  return {
    range,
    totalCalls,
    avgLatencyMs: Math.round(weighted("avgLatencyMs")),
    p95LatencyMs: 3600,
    flagRate: 0.118,
    errorRate: weighted("errorRate"),
    totalTokens: Math.round(50_600_000 * scale),
    delta: { totalCalls: 0.098, avgLatencyMs: 0.042, flagRate: -0.012, errorRate: 0.31 },
    byTask,
  };
}
