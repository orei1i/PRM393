// src/lib/hooks/use-telemetry.ts
"use client";

import { keepPreviousData, useQuery } from "@tanstack/react-query";

import type { AiLogQuery, TelemetryRange } from "@/types/moderation";

import { telemetryApi } from "../api_client";

export const telemetryKeys = {
  summary: (range: TelemetryRange) => ["telemetry", "summary", range] as const,
  logs: (query: AiLogQuery) => ["telemetry", "logs", query] as const,
};

export function useTelemetrySummary(range: TelemetryRange) {
  return useQuery({
    queryKey: telemetryKeys.summary(range),
    queryFn: () => telemetryApi.getSummary(range),
    placeholderData: keepPreviousData,
    refetchInterval: 15_000,
  });
}

/** Polls ai_logs every 3 s while `live` is on (swap for SSE/SignalR when the backend exposes it). */
export function useAiLogs(query: AiLogQuery, live: boolean) {
  return useQuery({
    queryKey: telemetryKeys.logs(query),
    queryFn: () => telemetryApi.listLogs(query),
    placeholderData: keepPreviousData,
    refetchInterval: live ? 3_000 : false,
    refetchIntervalInBackground: false,
  });
}
