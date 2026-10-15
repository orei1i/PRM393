// src/lib/hooks/use-ai-models.ts
"use client";

import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import type { AiModel, AiModelPatch } from "@/types/ai_models";
import type { TelemetryRange } from "@/types/moderation";

import { aiModelsApi } from "../api_client";

export const aiModelKeys = {
  all: ["ai-models"] as const,
  list: ["ai-models", "list"] as const,
  metrics: (range: TelemetryRange) => ["ai-models", "metrics", range] as const,
};

export function useAiModels() {
  return useQuery({ queryKey: aiModelKeys.list, queryFn: () => aiModelsApi.list() });
}

export function useAiMetrics(range: TelemetryRange) {
  return useQuery({
    queryKey: aiModelKeys.metrics(range),
    queryFn: () => aiModelsApi.metrics(range),
    placeholderData: keepPreviousData,
    refetchInterval: 60_000,
  });
}

/** Optimistic: the card shows the new settings at once and reverts if the save fails. */
export function useUpdateAiModel() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, patch }: { id: string; patch: AiModelPatch }) => aiModelsApi.update(id, patch),
    onMutate: async ({ id, patch }) => {
      await qc.cancelQueries({ queryKey: aiModelKeys.list });
      const previous = qc.getQueryData<AiModel[]>(aiModelKeys.list);
      qc.setQueryData<AiModel[]>(aiModelKeys.list, (old) =>
        old?.map((m) =>
          m.id === id
            ? {
                ...m,
                enabled: patch.enabled ?? m.enabled,
                activeVersion: patch.activeVersion ?? m.activeVersion,
                threshold: patch.threshold ?? m.threshold,
              }
            : m,
        ),
      );
      return { previous };
    },
    onError: (_e, _v, context) => {
      if (context?.previous) qc.setQueryData(aiModelKeys.list, context.previous);
    },
    onSuccess: (model) => {
      qc.setQueryData<AiModel[]>(aiModelKeys.list, (old) => old?.map((m) => (m.id === model.id ? model : m)));
    },
    onSettled: () => {
      qc.invalidateQueries({ queryKey: aiModelKeys.all });
      // New settings change what the live ai_logs stream produces.
      qc.invalidateQueries({ queryKey: ["telemetry"] });
      qc.invalidateQueries({ queryKey: ["overview"] });
    },
  });
}
