// src/lib/hooks/use-telemetry.ts
"use client";

import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import type { AiLogLabelInput, AiLogQuery, TelemetryRange } from "@/types/moderation";

import { telemetryApi } from "../api_client";

export const telemetryKeys = {
  summary: (range: TelemetryRange) => ["telemetry", "summary", range] as const,
  logs: (query: AiLogQuery) => ["telemetry", "logs", query] as const,
  log: (id: string) => ["telemetry", "log", id] as const,
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

/** One log with input/output text. A pruned log answers 404, so no retry. */
export function useAiLogDetail(id: string | null) {
  return useQuery({
    queryKey: telemetryKeys.log(id ?? ""),
    queryFn: () => telemetryApi.getLog(id ?? ""),
    enabled: id !== null,
    retry: false,
  });
}

export function useLabelAiLog() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: AiLogLabelInput) => telemetryApi.labelLog(input),
    onSuccess: (detail) => qc.setQueryData(telemetryKeys.log(detail.id), detail),
    // Labelled accuracy on /ai-models changes with every label.
    onSettled: () => qc.invalidateQueries({ queryKey: ["ai-models", "metrics"] }),
  });
}
