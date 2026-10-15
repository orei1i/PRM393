// src/lib/hooks/use-knowledge.ts
"use client";

import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import type { KnowledgeDoc, KnowledgeQuery, KnowledgeReviewInput, WhoDocInput } from "@/types/knowledge";

import { knowledgeApi } from "../knowledge_api";

export const knowledgeKeys = {
  all: ["knowledge"] as const,
  list: (q: KnowledgeQuery) => ["knowledge", "list", q] as const,
  counts: ["knowledge", "counts"] as const,
  chunks: (id: string) => ["knowledge", "chunks", id] as const,
};

export function useKnowledgeDocs(query: KnowledgeQuery) {
  return useQuery({
    queryKey: knowledgeKeys.list(query),
    queryFn: () => knowledgeApi.list(query),
    placeholderData: keepPreviousData,
  });
}

export function useKnowledgeCounts() {
  return useQuery({ queryKey: knowledgeKeys.counts, queryFn: () => knowledgeApi.counts(), refetchInterval: 60_000 });
}

export function useKnowledgeChunks(id: string, enabled: boolean) {
  return useQuery({ queryKey: knowledgeKeys.chunks(id), queryFn: () => knowledgeApi.chunks(id, 5), enabled });
}

export function useCreateWhoDoc() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: WhoDocInput) => knowledgeApi.createWho(input),
    onSettled: () => qc.invalidateQueries({ queryKey: knowledgeKeys.all }),
  });
}

/** Optimistically drops the doc from "Chờ duyệt" lists; rolls back on error. */
export function useReviewKnowledgeDoc() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: KnowledgeReviewInput) => knowledgeApi.review(input),
    onMutate: async (input) => {
      await qc.cancelQueries({ queryKey: ["knowledge", "list"] });
      const snapshots = qc.getQueriesData<KnowledgeDoc[]>({ queryKey: ["knowledge", "list"] });
      for (const [key, data] of snapshots) {
        if (data && (key[2] as KnowledgeQuery | undefined)?.status === "Pending") {
          qc.setQueryData(key, data.filter((d) => d.id !== input.docId));
        }
      }
      return { snapshots };
    },
    onError: (_e, _v, context) => {
      context?.snapshots.forEach(([key, data]) => qc.setQueryData(key, data));
    },
    onSuccess: (doc) => {
      qc.setQueriesData<KnowledgeDoc[]>({ queryKey: ["knowledge", "list"] }, (old) => old?.map((d) => (d.id === doc.id ? doc : d)));
    },
    onSettled: () => qc.invalidateQueries({ queryKey: knowledgeKeys.all }),
  });
}

export function useDeleteKnowledgeDoc() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => knowledgeApi.remove(id),
    onMutate: async (id) => {
      await qc.cancelQueries({ queryKey: ["knowledge", "list"] });
      const snapshots = qc.getQueriesData<KnowledgeDoc[]>({ queryKey: ["knowledge", "list"] });
      qc.setQueriesData<KnowledgeDoc[]>({ queryKey: ["knowledge", "list"] }, (old) => old?.filter((d) => d.id !== id));
      return { snapshots };
    },
    onError: (_e, _v, context) => {
      context?.snapshots.forEach(([key, data]) => qc.setQueryData(key, data));
    },
    onSettled: () => qc.invalidateQueries({ queryKey: knowledgeKeys.all }),
  });
}
