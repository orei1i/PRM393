// src/types/moderation.ts
// Mirrors the ASP.NET Core DTOs (camelCase JSON via System.Text.Json defaults).
// Tables: posts, ai_flags, moderation_decisions, ai_logs.

/* ------------------------------------------------------------------ shared */

export type ISODateString = string;

export interface Paginated<T> {
  items: T[];
  total: number;
  page: number;
  pageSize: number;
}

/* ------------------------------------------------------------------- posts */

export type ContentType = "post" | "comment" | "video" | "recipe";

export type PostVisibility = "visible" | "auto_hidden" | "removed";

export interface Author {
  id: string;
  displayName: string;
  handle: string;
  avatarUrl?: string | null;
  priorWarnings: number;
  joinedAt: ISODateString;
}

export interface Post {
  id: string;
  type: ContentType;
  author: Author;
  text: string;
  media: { url: string; alt: string }[];
  ingredientTags: string[];
  createdAt: ISODateString;
  stats: { likes: number; comments: number; reach: number };
  reportCount: number;
  visibility: PostVisibility;
}

/* ---------------------------------------------------------------- ai_flags */

export type FlagCategory =
  | "health_misinformation"
  | "harassment"
  | "toxicity"
  | "spam_promo"
  | "not_vegan"
  | "copyright";

export type FlagStatus = "pending" | "escalated" | "resolved";

export type ModerationAction = "approve" | "reject" | "warn";

export interface CategoryScore {
  category: FlagCategory;
  /** 0…1, calibrated */
  score: number;
}

/** Character range in `post.text` the model relied on. `end` is exclusive. */
export interface FlagSpan {
  start: number;
  end: number;
  category: FlagCategory;
}

export interface AiFlag {
  id: string;
  postId: string;
  post: Post;
  status: FlagStatus;
  primaryCategory: FlagCategory;
  /** Confidence of the primary category, 0…1 */
  confidence: number;
  /** Generic toxicity score, 0…1 (shown as a column in the queue) */
  toxicityScore: number;
  scores: CategoryScore[];
  /** Model's short explanation (vi) */
  reason: string;
  spans: FlagSpan[];
  suggestedAction: ModerationAction;
  policyRef: string;
  modelVersion: string;
  latencyMs: number;
  traceId: string;
  createdAt: ISODateString;
}

export interface FlagQueueQuery {
  status: FlagStatus;
  category?: FlagCategory | "all";
  search?: string;
}

/* ---------------------------------------------------- moderation_decisions */

export interface ModerationDecisionInput {
  flagId: string;
  action: ModerationAction;
  /** Mandatory internal audit note (≥ 10 characters) */
  note: string;
  notifyAuthor: boolean;
}

export interface ModerationDecision extends ModerationDecisionInput {
  id: string;
  postId: string;
  adminId: string;
  adminName: string;
  modelVersion: string;
  scoresSnapshot: CategoryScore[];
  decidedAt: ISODateString;
}

/* ----------------------------------------------------------------- ai_logs */

export type AiTaskType = "moderation" | "meal_plan" | "chatbot" | "vision_scan";

export type AiLogStatus = "success" | "warning" | "error";

export interface AiLog {
  id: string;
  timestamp: ISODateString;
  task: AiTaskType;
  model: string;
  latencyMs: number;
  inputTokens: number;
  outputTokens: number;
  status: AiLogStatus;
  /** e.g. "flagged · 0.91", "low_light_rejected", "timeout → fallback" */
  detail: string;
  traceId: string;
  /** Moderation calls only: whether the item was flagged */
  flagged?: boolean;
}

export type TelemetryRange = "1h" | "24h" | "7d";

export interface TaskTelemetry {
  task: AiTaskType;
  calls: number;
  avgLatencyMs: number;
  p95LatencyMs: number;
  errorRate: number;
}

export interface TelemetrySummary {
  range: TelemetryRange;
  totalCalls: number;
  avgLatencyMs: number;
  p95LatencyMs: number;
  /** Share of moderation calls that produced a flag, 0…1 */
  flagRate: number;
  errorRate: number;
  totalTokens: number;
  /** Relative change vs the previous equal range, e.g. 0.098 = +9.8 % */
  delta: { totalCalls: number; avgLatencyMs: number; flagRate: number; errorRate: number };
  byTask: TaskTelemetry[];
}

export interface AiLogQuery {
  task: AiTaskType | "all";
  limit: number;
}

/* ------------------------------------------------------------- UI labels */

export const FLAG_CATEGORY_LABEL: Record<FlagCategory, string> = {
  health_misinformation: "Thông tin sức khoẻ sai lệch",
  harassment: "Quấy rối",
  toxicity: "Ngôn từ độc hại",
  spam_promo: "Spam / quảng cáo",
  not_vegan: "Không thuần chay",
  copyright: "Vi phạm bản quyền",
};

export const CONTENT_TYPE_LABEL: Record<ContentType, string> = {
  post: "Bài viết",
  comment: "Bình luận",
  video: "Video",
  recipe: "Công thức",
};

export const TASK_LABEL: Record<AiTaskType, string> = {
  moderation: "Kiểm duyệt",
  meal_plan: "Thực đơn",
  chatbot: "Chatbot",
  vision_scan: "Quét ảnh",
};

export const ACTION_LABEL: Record<ModerationAction, string> = {
  approve: "Duyệt",
  reject: "Gỡ bỏ",
  warn: "Cảnh cáo tác giả",
};

export const MIN_AUDIT_NOTE_LENGTH = 10;
