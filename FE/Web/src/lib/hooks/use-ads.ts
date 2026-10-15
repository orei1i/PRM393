// src/lib/hooks/use-ads.ts
"use client";

import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { deriveAdStatus, type AdCampaign, type AdInput, type AdQuery } from "@/types/ads";

import { adsApi } from "../ads_api";

export const adKeys = {
  all: ["ads"] as const,
  lists: ["ads", "list"] as const,
  list: (q: AdQuery) => ["ads", "list", q] as const,
};

export function useAds(query: AdQuery) {
  return useQuery({ queryKey: adKeys.list(query), queryFn: () => adsApi.list(query), placeholderData: keepPreviousData });
}

type Snapshots = [readonly unknown[], AdCampaign[] | undefined][];

function restore(qc: ReturnType<typeof useQueryClient>, snapshots: Snapshots | undefined) {
  snapshots?.forEach(([key, data]) => qc.setQueryData(key, data));
}

export function useCreateAd() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: AdInput) => adsApi.create(input),
    onSettled: () => {
      qc.invalidateQueries({ queryKey: adKeys.lists });
      qc.invalidateQueries({ queryKey: ["overview"] });
    },
  });
}

/** Edit: the row shows the new text / dates / derived status at once; rolls back on error. */
export function useUpdateAd() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, patch }: { id: string; patch: Partial<AdInput> }) => adsApi.update(id, patch),
    onMutate: async ({ id, patch }) => {
      await qc.cancelQueries({ queryKey: adKeys.lists });
      const snapshots: Snapshots = qc.getQueriesData<AdCampaign[]>({ queryKey: adKeys.lists });
      qc.setQueriesData<AdCampaign[]>({ queryKey: adKeys.lists }, (old) =>
        old?.map((a) => {
          if (a.id !== id) return a;
          const next = { ...a, ...patch };
          return { ...next, status: deriveAdStatus(next) };
        }),
      );
      return { snapshots };
    },
    onError: (_e, _v, context) => restore(qc, context?.snapshots),
    onSuccess: (ad) => qc.setQueriesData<AdCampaign[]>({ queryKey: adKeys.lists }, (old) => old?.map((a) => (a.id === ad.id ? ad : a))),
    onSettled: () => {
      qc.invalidateQueries({ queryKey: adKeys.lists });
      qc.invalidateQueries({ queryKey: ["overview"] });
    },
  });
}

/**
 * Pause / resume switch. The row flips at once and stays in its tab until the refetch
 * moves it; on error every cached list is restored.
 */
export function useSetAdPaused() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, paused }: { id: string; paused: boolean }) => adsApi.setPaused(id, paused),
    onMutate: async ({ id, paused }) => {
      await qc.cancelQueries({ queryKey: adKeys.lists });
      const snapshots: Snapshots = qc.getQueriesData<AdCampaign[]>({ queryKey: adKeys.lists });
      qc.setQueriesData<AdCampaign[]>({ queryKey: adKeys.lists }, (old) =>
        old?.map((a) => (a.id === id ? { ...a, isPaused: paused, status: deriveAdStatus({ ...a, isPaused: paused }) } : a)),
      );
      return { snapshots };
    },
    onError: (_e, _v, context) => restore(qc, context?.snapshots),
    onSuccess: (ad) => qc.setQueriesData<AdCampaign[]>({ queryKey: adKeys.lists }, (old) => old?.map((a) => (a.id === ad.id ? ad : a))),
    onSettled: () => {
      qc.invalidateQueries({ queryKey: adKeys.lists });
      qc.invalidateQueries({ queryKey: ["overview"] });
    },
  });
}

export function useDeleteAd() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => adsApi.remove(id),
    onMutate: async (id) => {
      await qc.cancelQueries({ queryKey: adKeys.lists });
      const snapshots: Snapshots = qc.getQueriesData<AdCampaign[]>({ queryKey: adKeys.lists });
      qc.setQueriesData<AdCampaign[]>({ queryKey: adKeys.lists }, (old) => old?.filter((a) => a.id !== id));
      return { snapshots };
    },
    onError: (_e, _v, context) => restore(qc, context?.snapshots),
    onSettled: () => {
      qc.invalidateQueries({ queryKey: adKeys.lists });
      qc.invalidateQueries({ queryKey: ["overview"] });
    },
  });
}
