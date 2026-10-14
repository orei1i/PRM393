// src/lib/hooks/use-moderation.ts
"use client";

import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import type { AiFlag, FlagQueueQuery, FlagStatus, ModerationDecisionInput } from "@/types/moderation";

import { moderationApi } from "../api_client";

export const moderationKeys = {
  all: ["moderation"] as const,
  flags: (query: FlagQueueQuery) => ["moderation", "flags", query] as const,
  counts: ["moderation", "counts"] as const,
};

export function useFlagQueue(query: FlagQueueQuery) {
  return useQuery({
    queryKey: moderationKeys.flags(query),
    queryFn: () => moderationApi.listFlags(query),
    placeholderData: keepPreviousData,
    refetchInterval: 30_000, // new AI flags arrive continuously
  });
}

export function useFlagCounts() {
  return useQuery({
    queryKey: moderationKeys.counts,
    queryFn: () => moderationApi.getCounts(),
    refetchInterval: 30_000,
  });
}

/** Optimistically removes the item from every queue list; rolls back on error. */
export function useModerationDecision() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (input: ModerationDecisionInput) => moderationApi.decide(input),
    onMutate: async (input) => {
      await queryClient.cancelQueries({ queryKey: ["moderation", "flags"] });
      const snapshots = queryClient.getQueriesData<AiFlag[]>({ queryKey: ["moderation", "flags"] });
      queryClient.setQueriesData<AiFlag[]>({ queryKey: ["moderation", "flags"] }, (old) =>
        old?.filter((f) => f.id !== input.flagId),
      );
      const counts = queryClient.getQueryData<Record<FlagStatus, number>>(moderationKeys.counts);
      return { snapshots, counts };
    },
    onError: (_error, _input, context) => {
      context?.snapshots.forEach(([key, data]) => queryClient.setQueryData(key, data));
      if (context?.counts) queryClient.setQueryData(moderationKeys.counts, context.counts);
    },
    onSettled: () => queryClient.invalidateQueries({ queryKey: moderationKeys.all }),
  });
}
