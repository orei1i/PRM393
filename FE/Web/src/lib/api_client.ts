// src/lib/api_client.ts
// Typed API layer shared by every admin page (moderation, telemetry here;
// users/chefs/content/catalog/overview in admin_api.ts).
// NEXT_PUBLIC_USE_MOCK_DATA=false switches every call to the ASP.NET Core API.
import type {
  AiFlag,
  AiLog,
  AiLogQuery,
  FlagQueueQuery,
  FlagStatus,
  ModerationDecision,
  ModerationDecisionInput,
  TelemetryRange,
  TelemetrySummary,
} from "@/types/moderation";

import { ApiError } from "./api_error";
import { clearSession, readSession } from "./auth";
import * as mock from "./mock_data";

export const USE_MOCK_DATA = process.env.NEXT_PUBLIC_USE_MOCK_DATA !== "false";
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

  if (!res.ok) {
    let body: { message?: string; title?: string; code?: string } = {};
    try {
      body = await res.json();
    } catch {
      // non-JSON error body
    }
    throw new ApiError(body.message ?? body.title ?? `Yêu cầu thất bại (${res.status}).`, res.status, body.code);
  }
  if (res.status === 204) return undefined as T;
  return unwrapEnvelope<T>(await res.json());
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
    if (USE_MOCK_DATA) return mock.listFlags(query);
    return request<AiFlag[]>(
      `/admin/moderation/flags?${qs({ status: query.status, category: query.category === "all" ? undefined : query.category, search: query.search })}`,
    );
  },

  getCounts(): Promise<Record<FlagStatus, number>> {
    if (USE_MOCK_DATA) return mock.getFlagCounts();
    return request<Record<FlagStatus, number>>("/admin/moderation/flags/counts");
  },

  /** POST /admin/moderation/flags/{id}/decision → persisted in moderation_decisions */
  decide(input: ModerationDecisionInput): Promise<ModerationDecision> {
    if (USE_MOCK_DATA) return mock.decide(input);
    return request<ModerationDecision>(`/admin/moderation/flags/${input.flagId}/decision`, {
      method: "POST",
      body: JSON.stringify(input),
    });
  },
};

export const telemetryApi = {
  getSummary(range: TelemetryRange): Promise<TelemetrySummary> {
    if (USE_MOCK_DATA) return mock.getTelemetrySummary(range);
    return request<TelemetrySummary>(`/admin/ai/telemetry/summary?${qs({ range })}`);
  },

  /** Latest ai_logs rows, newest first. */
  listLogs(query: AiLogQuery): Promise<AiLog[]> {
    if (USE_MOCK_DATA) return mock.listLogs(query);
    return request<AiLog[]>(`/admin/ai/logs?${qs({ task: query.task === "all" ? undefined : query.task, limit: query.limit })}`);
  },
};
