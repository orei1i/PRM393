// src/lib/api_client.ts
// Typed API layer shared by every admin page (moderation, telemetry, AI models
// here; users/chefs/content/comments/catalog/overview in admin_api.ts;
// knowledge docs in knowledge_api.ts).
// Which modules call the ASP.NET Core API is decided in backend_modules.ts.
import type { AiAccuracyMetrics, AiModel, AiModelPatch } from "@/types/ai_models";
import type {
  AiFlag,
  AiLog,
  AiLogDetail,
  AiLogLabelInput,
  AiLogQuery,
  AiTaskType,
  FlagQueueQuery,
  FlagStatus,
  ModerationDecision,
  ModerationDecisionInput,
  TelemetryRange,
  TelemetrySummary,
} from "@/types/moderation";

import { ApiError } from "./api_error";
import { clearSession, readSession } from "./auth";
import { isMock } from "./backend_modules";
import { readId } from "./ids";
import * as mockModels from "./mock_ai_models";
import * as mock from "./mock_data";

const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:5001/api/v1";

/**
 * The ASP.NET Core API wraps payloads in `ApiResponse<T> { success, message, data, statusCode }`.
 * Returns `data`; `success: false` becomes an ApiError with the server's message.
 */
export function unwrapEnvelope<T>(body: unknown): T {
  if (body && typeof body === "object" && !Array.isArray(body) && "success" in body && ("data" in body || "statusCode" in body)) {
    const envelope = body as { success: boolean; message?: string | null; data?: unknown; statusCode?: number };
    if (!envelope.success) {
      throw new ApiError(envelope.message ?? "Yêu cầu thất bại.", envelope.statusCode);
    }
    return envelope.data as T;
  }
  return body as T;
}

/**
 * The URL to display a media file from. Uploads come back host-relative
 * (`/uploads/images/x.png`); anything else is returned unchanged. Empty → null.
 */
export function absoluteMediaUrl(raw: string | null | undefined): string | null {
  if (!raw) return null;
  return raw.startsWith("/") && !raw.startsWith("//") ? `${new URL(API_BASE_URL).origin}${raw}` : raw;
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
  if (status === 429) return "Bạn thao tác quá nhanh. Thử lại sau ít phút.";
  if (status >= 500) return "Máy chủ đang gặp sự cố. Vui lòng thử lại sau.";
  return "Đã có lỗi xảy ra. Vui lòng thử lại.";
}

/** A failed response as a Vietnamese ApiError. The `title` of ProblemDetails is English, so it is never shown. */
function errorFromResponse(status: number, body: unknown): ApiError {
  const data = body && typeof body === "object" ? (body as { message?: unknown; code?: unknown; errors?: unknown }) : {};
  const code = typeof data.code === "string" ? data.code : undefined;
  if (typeof data.message === "string" && data.message.trim()) return new ApiError(data.message, status, code);
  if (data.errors && typeof data.errors === "object") {
    return new ApiError(validationMessage(data.errors as Record<string, unknown>) ?? INVALID_INPUT, status, code);
  }
  return new ApiError(fallbackMessage(status), status, code);
}

export async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const token = readSession()?.accessToken;
  let res: Response;
  try {
    res = await fetch(`${API_BASE_URL}${path}`, {
      ...init,
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "Accept-Language": "vi-VN",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...init?.headers,
      },
    });
  } catch {
    throw new ApiError("Không kết nối được máy chủ. Kiểm tra mạng hoặc VPN.", undefined, "network");
  }

  if (res.status === 401 && typeof window !== "undefined" && !path.startsWith("/auth/")) {
    // Token expired or revoked: back to the login screen, keep the current page.
    clearSession();
    window.location.assign(`/login?next=${encodeURIComponent(window.location.pathname)}`);
  }

  // Some answers have an empty body (403 from the auth middleware, 204) or an HTML one (dev exception page).
  const text = await res.text().catch(() => "");
  let body: unknown = null;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = null;
  }

  if (!res.ok) throw errorFromResponse(res.status, body);
  if (body === null) return undefined as T;
  return unwrapEnvelope<T>(body);
}

export function qs(params: Record<string, string | number | undefined>) {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== "") search.set(key, String(value));
  }
  return search.toString();
}

export const moderationApi = {
  listFlags(query: FlagQueueQuery): Promise<AiFlag[]> {
    if (isMock("moderation")) return mock.listFlags(query);
    return request<AiFlag[]>(
      `/admin/moderation/flags?${qs({ status: query.status, category: query.category === "all" ? undefined : query.category, search: query.search })}`,
    );
  },

  getCounts(): Promise<Record<FlagStatus, number>> {
    if (isMock("moderation")) return mock.getFlagCounts();
    return request<Record<FlagStatus, number>>("/admin/moderation/flags/counts");
  },

  /** POST /admin/moderation/flags/{id}/decision → persisted in moderation_decisions */
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

type RawAiLog = Omit<Partial<AiLogDetail>, "id" | "refId" | "task"> & {
  id?: unknown;
  refId?: unknown;
  task?: string;
  taskType?: string;
  createdAt?: string;
};

/** Accepts the SQL-named aliases (`taskType`, `createdAt`) and INT ids. */
export function normalizeAiLog(raw: RawAiLog): AiLogDetail {
  const task = (raw.task ?? raw.taskType ?? "").toLowerCase();
  return {
    id: readId(raw.id),
    timestamp: raw.timestamp ?? raw.createdAt ?? new Date(0).toISOString(),
    task: AI_TASKS.find((t) => t === task) ?? "chatbot",
    model: raw.model ?? "—",
    latencyMs: raw.latencyMs ?? 0,
    inputTokens: raw.inputTokens ?? 0,
    outputTokens: raw.outputTokens ?? 0,
    status: raw.status ?? "success",
    detail: raw.detail ?? "",
    traceId: raw.traceId ?? "",
    flagged: raw.flagged,
    refType: raw.refType ?? null,
    refId: raw.refId === null || raw.refId === undefined ? null : readId(raw.refId),
    inputText: raw.inputText ?? "",
    outputText: raw.outputText ?? "",
    label: raw.label,
  };
}

const sessionName = () => readSession()?.fullName ?? "Quản trị viên";

export const telemetryApi = {
  getSummary(range: TelemetryRange): Promise<TelemetrySummary> {
    if (isMock("telemetry")) return mock.getTelemetrySummary(range);
    return request<TelemetrySummary>(`/admin/ai/telemetry/summary?${qs({ range })}`);
  },

  /** Latest ai_logs rows, newest first. */
  async listLogs(query: AiLogQuery): Promise<AiLog[]> {
    if (isMock("telemetry")) return mock.listLogs(query);
    const raw = await request<RawAiLog[]>(`/admin/ai/logs?${qs({ task: query.task === "all" ? undefined : query.task, limit: query.limit })}`);
    return raw.map(normalizeAiLog);
  },

  /** GET /admin/ai/logs/{id} — input/output text and the admin label. 404 once the log is pruned. */
  async getLog(id: string): Promise<AiLogDetail> {
    if (isMock("telemetry")) return mock.getLogDetail(id);
    return normalizeAiLog(await request<RawAiLog>(`/admin/ai/logs/${encodeURIComponent(id)}`));
  },

  /** POST /admin/ai/logs/{id}/label { verdict, note? } */
  async labelLog(input: AiLogLabelInput): Promise<AiLogDetail> {
    if (isMock("telemetry")) return mock.labelLog(input, sessionName());
    return normalizeAiLog(
      await request<RawAiLog>(`/admin/ai/logs/${encodeURIComponent(input.logId)}/label`, {
        method: "POST",
        body: JSON.stringify({ verdict: input.verdict, note: input.note }),
      }),
    );
  },
};

/* ----------------------------------------------------------- ai models */

export const aiModelsApi = {
  /** GET /admin/ai/models */
  list(): Promise<AiModel[]> {
    if (isMock("aiModels")) return mockModels.listModels();
    return request<AiModel[]>("/admin/ai/models");
  },

  /** PATCH /admin/ai/models/{id} — audit note required. */
  update(id: string, patch: AiModelPatch): Promise<AiModel> {
    if (isMock("aiModels")) return mockModels.updateModel(id, patch, readSession());
    return request<AiModel>(`/admin/ai/models/${encodeURIComponent(id)}`, { method: "PATCH", body: JSON.stringify(patch) });
  },

  /** GET /admin/ai/metrics?range= — precision from ai_flags × moderation_decisions + admin labels. */
  metrics(range: TelemetryRange): Promise<AiAccuracyMetrics> {
    if (isMock("aiModels")) return mockModels.getMetrics(range);
    return request<AiAccuracyMetrics>(`/admin/ai/metrics?${qs({ range })}`);
  },
};
