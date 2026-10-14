// src/lib/api_client.ts
// Typed API layer. Pages only talk to `moderationApi` / `telemetryApi`;
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
import * as mock from "./mock_data";

export const USE_MOCK_DATA = process.env.NEXT_PUBLIC_USE_MOCK_DATA !== "false";
const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:5080/api/v1";

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  let res: Response;
  try {
    res = await fetch(`${API_BASE_URL}${path}`, {
      ...init,
      // Admin auth is an HttpOnly cookie issued by the backend (SSO + 2FA).
      credentials: "include",
      headers: { "Content-Type": "application/json", Accept: "application/json", "Accept-Language": "vi-VN", ...init?.headers },
    });
  } catch {
    throw new ApiError("Không kết nối được máy chủ. Kiểm tra mạng hoặc VPN.", undefined, "network");
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
  return (await res.json()) as T;
}

function qs(params: Record<string, string | number | undefined>) {
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
