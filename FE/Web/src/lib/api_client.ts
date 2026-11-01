// src/lib/api_client.ts
// Typed API layer shared by every admin page (moderation, telemetry, AI models
// here; users/chefs/content/comments/catalog/overview in admin_api.ts;
// knowledge docs in knowledge_api.ts).
// Which modules call the ASP.NET Core API is decided in backend_modules.ts.
//
// Every answer may be wrong: `request` turns transport failures and non-JSON bodies into a Vietnamese
// ApiError, `requestList` / `requestObject` do the same for a body of the wrong shape, and the
// normalisers (built on wire.ts) fill in whatever a row is missing. Pages can trust what they get.
import type { AiAccuracyMetrics, AiModel, AiModelPatch } from "@/types/ai_models";
import type {
  AiFlag,
  AiLog,
  AiLogDetail,
  AiLogLabelInput,
  AiLogQuery,
  AiLogStatus,
  AiTaskType,
  CategoryScore,
  ContentType,
  FlagCategory,
  FlagQueueQuery,
  FlagStatus,
  ModerationAction,
  ModerationDecision,
  ModerationDecisionInput,
  Post,
  PostVisibility,
  TaskTelemetry,
  TelemetryRange,
  TelemetrySummary,
} from "@/types/moderation";
import { CONTENT_TYPE_LABEL, FLAG_CATEGORY_LABEL } from "@/types/moderation";

import { ApiError, badResponse } from "./api_error";
import { clearSession, readSession, writeSession } from "./auth";
import { isMock } from "./backend_modules";
import { readId } from "./ids";
import * as mockModels from "./mock_ai_models";
import * as mock from "./mock_data";
import { bool, counts, hasId, isoOr, num, obj, objects, optNum, optText, pick, text, texts, type Raw } from "./wire";

const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:5001/api/v1";

/** A hung server must not leave a page on its skeleton forever. */
const REQUEST_TIMEOUT_MS = 20_000;

/**
 * The ASP.NET Core API wraps payloads in `ApiResponse<T> { success, message, data, statusCode }`.
 * Returns `data`; `success: false` becomes an ApiError with the server's message.
 */
export function unwrapEnvelope<T>(body: unknown): T {
  const envelope = obj(body);
  if (envelope?.success === false) {
    const status = typeof envelope.statusCode === "number" ? envelope.statusCode : undefined;
    throw new ApiError(optText(envelope.message) ?? "Yêu cầu thất bại.", status, optText(envelope.code) ?? undefined);
  }
  if (envelope && "success" in envelope && ("data" in envelope || "statusCode" in envelope)) return envelope.data as T;
  return body as T;
}

/**
 * The URL to display a media file from. Uploads come back host-relative
 * (`/uploads/images/x.png`); anything else is returned unchanged. Empty → null.
 */
export function absoluteMediaUrl(raw: unknown): string | null {
  if (typeof raw !== "string" || !raw) return null;
  if (!raw.startsWith("/") || raw.startsWith("//")) return raw;
  try {
    return `${new URL(API_BASE_URL).origin}${raw}`;
  } catch {
    return raw;
  }
}

const INVALID_INPUT = "Dữ liệu gửi lên chưa hợp lệ.";

/** `ProblemDetails.errors`: the first usable message per field. `$.x` keys and "The …" values are the framework's English parser errors. */
function validationMessage(errors: Record<string, unknown>): string | null {
  const messages: string[] = [];
  for (const [field, value] of Object.entries(errors)) {
    if (field.startsWith("$") || !Array.isArray(value)) continue;
    const text = value.map((item) => String(item ?? "").trim()).find((item) => item && !item.startsWith("The "));
    if (text) messages.push(text);
  }
  return messages.length ? messages.join(" ") : null;
}

function fallbackMessage(status: number): string {
  if (status === 400) return INVALID_INPUT;
  if (status === 401) return "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.";
  if (status === 403) return "Bạn không có quyền thực hiện thao tác này.";
  if (status === 404) return "Không tìm thấy dữ liệu.";
  if (status === 408) return "Máy chủ phản hồi quá lâu. Vui lòng thử lại.";
  if (status === 409) return "Dữ liệu vừa thay đổi. Tải lại rồi thử lại.";
  if (status === 429) return "Bạn thao tác quá nhanh. Thử lại sau ít phút.";
  if (status >= 500) return "Máy chủ đang gặp sự cố. Vui lòng thử lại sau.";
  return "Đã có lỗi xảy ra. Vui lòng thử lại.";
}

/**
 * A failed response as a Vietnamese ApiError. The `title` of ProblemDetails is English, so it is never
 * shown; neither is the `message` of a 5xx, which can be an exception's text.
 */
function errorFromResponse(status: number, body: unknown): ApiError {
  const data = obj(body) ?? {};
  const code = typeof data.code === "string" ? data.code : undefined;
  if (status < 500 && typeof data.message === "string" && data.message.trim()) return new ApiError(data.message, status, code);
  const errors = obj(data.errors);
  if (status < 500 && errors) return new ApiError(validationMessage(errors) ?? INVALID_INPUT, status, code);
  return new ApiError(fallbackMessage(status), status, code);
}

function connectionError(cause: unknown): ApiError {
  if (cause instanceof DOMException && cause.name === "TimeoutError") {
    return new ApiError("Máy chủ phản hồi quá lâu. Vui lòng thử lại.", undefined, "timeout");
  }
  return new ApiError("Không kết nối được máy chủ. Kiểm tra mạng hoặc VPN.", undefined, "network");
}

async function send(path: string, init: RequestInit | undefined, token: string | undefined): Promise<Response> {
  try {
    return await fetch(`${API_BASE_URL}${path}`, {
      ...init,
      signal: init?.signal ?? AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "Accept-Language": "vi-VN",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...init?.headers,
      },
    });
  } catch (e) {
    throw connectionError(e);
  }
}

/**
 * The JSON of an answer. Some have an empty body (403 from the auth middleware, 204) or an HTML one
 * (dev exception page, a proxy's error page): `junk` means it was not JSON. A connection dropped
 * halfway through a successful answer throws, so it is not mistaken for an empty one.
 */
async function readBody(res: Response): Promise<{ body: unknown; junk: boolean }> {
  let raw = "";
  try {
    raw = await res.text();
  } catch (e) {
    if (res.ok) throw connectionError(e);
  }
  if (!raw.trim()) return { body: null, junk: false };
  try {
    return { body: JSON.parse(raw), junk: false };
  } catch {
    return { body: null, junk: true };
  }
}

/** POST /auth/refresh. Null means the session is over; no network or a 5xx/429 throws and keeps it, since they say nothing about the token. */
async function rotateTokens(staleAccessToken: string | undefined): Promise<string | null> {
  const session = readSession();
  if (!session?.refreshToken) return null;
  // Another tab rotated while this one waited for the lock.
  if (session.accessToken !== staleAccessToken) return session.accessToken;

  const res = await send("/auth/refresh", { method: "POST", body: JSON.stringify({ refreshToken: session.refreshToken }) }, undefined);
  if (res.status >= 500 || res.status === 429) throw new ApiError(fallbackMessage(res.status), res.status);
  if (!res.ok) return null;
  const { body, junk } = await readBody(res);
  if (junk) throw badResponse(res.status);
  let data: Raw | null;
  try {
    data = obj(unwrapEnvelope<unknown>(body));
  } catch (e) {
    if (e instanceof ApiError && e.status === 401) return null;
    throw e;
  }
  const accessToken = optText(data?.accessToken);
  if (!data || !accessToken) throw badResponse(res.status);
  if (text(obj(data.user)?.role).toLowerCase() !== "admin") return null;
  // Signed out during the request: do not bring the session back.
  if (readSession()?.refreshToken !== session.refreshToken) return null;
  writeSession({ ...session, accessToken, refreshToken: optText(data.refreshToken) ?? session.refreshToken });
  return accessToken;
}

/** A refresh token works once, so a tab losing the race must not end the session. The Web Lock is absent on plain-http hosts. */
async function rotateAcrossTabs(staleAccessToken: string | undefined): Promise<string | null> {
  const rotate = () => rotateTokens(staleAccessToken);
  return navigator.locks ? navigator.locks.request("vl-admin-refresh", rotate) : rotate();
}

let refreshInFlight: Promise<string | null> | null = null;

/** The new access token, or null when the session is over. Single-flight within the tab. */
export function refreshAccessToken(staleAccessToken: string | undefined): Promise<string | null> {
  const flight = (refreshInFlight ??= rotateAcrossTabs(staleAccessToken).finally(() => {
    refreshInFlight = null;
  }));
  return flight;
}

let leaving = false;

/** Back to the login screen, keep the current page. Several calls can fail at once: the page leaves once. */
function endSession() {
  clearSession();
  if (leaving) return;
  leaving = true;
  window.location.assign(`/login?next=${encodeURIComponent(`${window.location.pathname}${window.location.search}`)}`);
}

export async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const token = readSession()?.accessToken;
  let res = await send(path, init, token);

  if (res.status === 401 && typeof window !== "undefined" && !path.startsWith("/auth/")) {
    // Access token expired or revoked: refresh once and retry; the rejected call did not run.
    const fresh = await refreshAccessToken(token);
    if (fresh) res = await send(path, init, fresh);
    if (!fresh || res.status === 401) endSession();
  }

  const { body, junk } = await readBody(res);
  if (!res.ok) throw errorFromResponse(res.status, body);
  if (junk) throw badResponse(res.status);
  if (body === null) return undefined as T;
  return unwrapEnvelope<T>(body);
}

/** An endpoint that answers with one object: anything else is a bad response. */
export async function requestObject(path: string, init?: RequestInit): Promise<Raw> {
  const body = obj(await request<unknown>(path, init));
  if (!body) throw badResponse();
  return body;
}

/** An endpoint that answers with a list: anything else is a bad response. Items that are not objects are dropped. */
export async function requestList(path: string, init?: RequestInit): Promise<Raw[]> {
  const body = await request<unknown>(path, init);
  if (!Array.isArray(body)) throw badResponse();
  return objects(body);
}

export function qs(params: Record<string, string | number | undefined>) {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== "") search.set(key, String(value));
  }
  return search.toString();
}

const FLAG_CATEGORIES = Object.keys(FLAG_CATEGORY_LABEL) as FlagCategory[];
const FLAG_STATUSES: readonly FlagStatus[] = ["pending", "escalated", "resolved"];
const MODERATION_ACTIONS: readonly ModerationAction[] = ["approve", "reject", "warn"];
const CONTENT_TYPES = Object.keys(CONTENT_TYPE_LABEL) as ContentType[];
const POST_VISIBILITIES: readonly PostVisibility[] = ["visible", "auto_hidden", "removed"];

const readScores = (raw: unknown): CategoryScore[] =>
  objects(raw).map((s) => ({ category: pick(FLAG_CATEGORIES, s.category, "toxicity"), score: num(s.score) }));

function normalizePost(raw: Raw): Post {
  const author = obj(raw.author) ?? {};
  const stats = obj(raw.stats) ?? {};
  return {
    id: readId(raw.id),
    type: pick(CONTENT_TYPES, raw.type, "post"),
    author: {
      id: readId(author.id),
      displayName: text(author.displayName ?? author.fullName ?? author.name, "Người dùng"),
      handle: text(author.handle),
      avatarUrl: optText(author.avatarUrl),
      priorWarnings: num(author.priorWarnings),
      joinedAt: isoOr(author.joinedAt),
    },
    text: text(raw.text ?? raw.content),
    media: objects(raw.media).map((m) => ({ url: text(m.url), alt: text(m.alt) })),
    ingredientTags: texts(raw.ingredientTags),
    createdAt: isoOr(raw.createdAt),
    stats: { likes: num(stats.likes), comments: num(stats.comments), reach: num(stats.reach) },
    reportCount: num(raw.reportCount),
    visibility: pick(POST_VISIBILITIES, raw.visibility, "visible"),
  };
}

export function normalizeFlag(raw: Raw): AiFlag {
  return {
    id: readId(raw.id),
    postId: readId(raw.postId ?? obj(raw.post)?.id),
    post: normalizePost(obj(raw.post) ?? {}),
    status: pick(FLAG_STATUSES, raw.status, "pending"),
    primaryCategory: pick(FLAG_CATEGORIES, raw.primaryCategory, "toxicity"),
    confidence: num(raw.confidence),
    toxicityScore: num(raw.toxicityScore),
    scores: readScores(raw.scores),
    reason: text(raw.reason),
    spans: objects(raw.spans).map((s) => ({ start: num(s.start), end: num(s.end), category: pick(FLAG_CATEGORIES, s.category, "toxicity") })),
    suggestedAction: pick(MODERATION_ACTIONS, raw.suggestedAction, "approve"),
    policyRef: text(raw.policyRef),
    modelVersion: text(raw.modelVersion),
    latencyMs: num(raw.latencyMs),
    traceId: text(raw.traceId),
    createdAt: isoOr(raw.createdAt),
  };
}

export const moderationApi = {
  async listFlags(query: FlagQueueQuery): Promise<AiFlag[]> {
    if (isMock("moderation")) return mock.listFlags(query);
    const raw = await requestList(
      `/admin/moderation/flags?${qs({ status: query.status, category: query.category === "all" ? undefined : query.category, search: query.search })}`,
    );
    return raw.map(normalizeFlag).filter(hasId);
  },

  async getCounts(): Promise<Record<FlagStatus, number>> {
    if (isMock("moderation")) return mock.getFlagCounts();
    return counts(FLAG_STATUSES, await requestObject("/admin/moderation/flags/counts"));
  },

  /** POST /admin/moderation/flags/{id}/decision → persisted in moderation_decisions. The queue refetches; nothing reads the answer's fields. */
  decide(input: ModerationDecisionInput): Promise<ModerationDecision> {
    if (isMock("moderation")) return mock.decide(input);
    return request<ModerationDecision>(`/admin/moderation/flags/${input.flagId}/decision`, {
      method: "POST",
      body: JSON.stringify(input),
    });
  },
};

/* ------------------------------------------------------------- ai_logs */

const AI_TASKS: readonly AiTaskType[] = ["moderation", "meal_plan", "chatbot", "vision_scan"];

const AI_LOG_STATUSES: readonly AiLogStatus[] = ["success", "warning", "error"];

/** Accepts the SQL-named aliases (`taskType`, `createdAt`) and INT ids. */
export function normalizeAiLog(raw: Raw): AiLogDetail {
  const label = obj(raw.label);
  return {
    id: readId(raw.id),
    timestamp: isoOr(raw.timestamp ?? raw.createdAt),
    task: pick(AI_TASKS, raw.task ?? raw.taskType, "chatbot"),
    model: text(raw.model, "—"),
    latencyMs: num(raw.latencyMs),
    inputTokens: num(raw.inputTokens),
    outputTokens: num(raw.outputTokens),
    status: pick(AI_LOG_STATUSES, raw.status, "success"),
    detail: text(raw.detail),
    traceId: text(raw.traceId),
    flagged: typeof raw.flagged === "boolean" ? raw.flagged : undefined,
    refType: optText(raw.refType),
    refId: raw.refId === null || raw.refId === undefined ? null : readId(raw.refId),
    inputText: text(raw.inputText),
    outputText: text(raw.outputText),
    label: label
      ? { verdict: pick(["correct", "incorrect"] as const, label.verdict, "correct"), note: optText(label.note) ?? undefined, by: text(label.by), at: isoOr(label.at) }
      : undefined,
  };
}

function normalizeTaskTelemetry(raw: Raw): TaskTelemetry {
  return {
    task: pick(AI_TASKS, raw.task, "chatbot"),
    calls: num(raw.calls),
    avgLatencyMs: num(raw.avgLatencyMs),
    p95LatencyMs: num(raw.p95LatencyMs),
    errorRate: num(raw.errorRate),
  };
}

function normalizeTelemetrySummary(raw: Raw, range: TelemetryRange): TelemetrySummary {
  const delta = obj(raw.delta) ?? {};
  return {
    range,
    totalCalls: num(raw.totalCalls),
    avgLatencyMs: num(raw.avgLatencyMs),
    p95LatencyMs: num(raw.p95LatencyMs),
    flagRate: num(raw.flagRate),
    errorRate: num(raw.errorRate),
    totalTokens: num(raw.totalTokens),
    delta: { totalCalls: num(delta.totalCalls), avgLatencyMs: num(delta.avgLatencyMs), flagRate: num(delta.flagRate), errorRate: num(delta.errorRate) },
    byTask: objects(raw.byTask).map(normalizeTaskTelemetry),
  };
}

const sessionName = () => readSession()?.fullName ?? "Quản trị viên";

export const telemetryApi = {
  async getSummary(range: TelemetryRange): Promise<TelemetrySummary> {
    if (isMock("telemetry")) return mock.getTelemetrySummary(range);
    return normalizeTelemetrySummary(await requestObject(`/admin/ai/telemetry/summary?${qs({ range })}`), range);
  },

  /** Latest ai_logs rows, newest first. */
  async listLogs(query: AiLogQuery): Promise<AiLog[]> {
    if (isMock("telemetry")) return mock.listLogs(query);
    const raw = await requestList(`/admin/ai/logs?${qs({ task: query.task === "all" ? undefined : query.task, limit: query.limit })}`);
    return raw.map(normalizeAiLog).filter(hasId);
  },

  /** GET /admin/ai/logs/{id} — input/output text and the admin label. 404 once the log is pruned. */
  async getLog(id: string): Promise<AiLogDetail> {
    if (isMock("telemetry")) return mock.getLogDetail(id);
    return normalizeAiLog(await requestObject(`/admin/ai/logs/${encodeURIComponent(id)}`));
  },

  /** POST /admin/ai/logs/{id}/label { verdict, note? } */
  async labelLog(input: AiLogLabelInput): Promise<AiLogDetail> {
    if (isMock("telemetry")) return mock.labelLog(input, sessionName());
    return normalizeAiLog(
      await requestObject(`/admin/ai/logs/${encodeURIComponent(input.logId)}/label`, {
        method: "POST",
        body: JSON.stringify({ verdict: input.verdict, note: input.note }),
      }),
    );
  },
};

/* ----------------------------------------------------------- ai models */

function normalizeAiModel(raw: Raw): AiModel {
  return {
    id: readId(raw.id),
    task: pick(AI_TASKS, raw.task, "chatbot"),
    name: text(raw.name),
    activeVersion: text(raw.activeVersion),
    availableVersions: texts(raw.availableVersions),
    enabled: bool(raw.enabled),
    threshold: optNum(raw.threshold),
    fallback: text(raw.fallback),
    updatedAt: isoOr(raw.updatedAt),
    updatedBy: optText(raw.updatedBy),
  };
}

function normalizeAiMetrics(raw: Raw, range: TelemetryRange): AiAccuracyMetrics {
  const moderation = obj(raw.moderation) ?? {};
  return {
    range,
    moderation: {
      decided: num(moderation.decided),
      confirmed: num(moderation.confirmed),
      overridden: num(moderation.overridden),
      precision: num(moderation.precision),
      overrideRate: num(moderation.overrideRate),
      pending: num(moderation.pending),
      medianDecisionMinutes: num(moderation.medianDecisionMinutes),
      byCategory: objects(moderation.byCategory).map((c) => ({
        category: pick(FLAG_CATEGORIES, c.category, "toxicity"),
        decided: num(c.decided),
        precision: num(c.precision),
      })),
    },
    labeled: objects(raw.labeled).map((l) => ({
      task: pick(AI_TASKS, l.task, "chatbot"),
      labeled: num(l.labeled),
      correct: num(l.correct),
      accuracy: optNum(l.accuracy),
    })),
  };
}

export const aiModelsApi = {
  /** GET /admin/ai/models */
  async list(): Promise<AiModel[]> {
    if (isMock("aiModels")) return mockModels.listModels();
    return (await requestList("/admin/ai/models")).map(normalizeAiModel).filter(hasId);
  },

  /** PATCH /admin/ai/models/{id} — audit note required. */
  async update(id: string, patch: AiModelPatch): Promise<AiModel> {
    if (isMock("aiModels")) return mockModels.updateModel(id, patch, readSession());
    return normalizeAiModel(await requestObject(`/admin/ai/models/${encodeURIComponent(id)}`, { method: "PATCH", body: JSON.stringify(patch) }));
  },

  /** GET /admin/ai/metrics?range= — precision from ai_flags × moderation_decisions + admin labels. */
  async metrics(range: TelemetryRange): Promise<AiAccuracyMetrics> {
    if (isMock("aiModels")) return mockModels.getMetrics(range);
    return normalizeAiMetrics(await requestObject(`/admin/ai/metrics?${qs({ range })}`), range);
  },
};
