// src/lib/hooks/use-payouts.ts
"use client";

import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import type { WithdrawalActionInput, WithdrawalQuery, WithdrawalRequest } from "@/types/payouts";

import { payoutsApi } from "../payouts_api";

export const payoutKeys = {
  all: ["payouts"] as const,
  summary: ["payouts", "summary"] as const,
  withdrawalLists: ["payouts", "withdrawals"] as const,
  withdrawals: (q: WithdrawalQuery) => ["payouts", "withdrawals", q] as const,
  wallets: ["payouts", "wallets"] as const,
  ledger: (chefId: string) => ["payouts", "ledger", chefId] as const,
};

/** KPIs + tab counts + the sidebar / overview "chờ duyệt" badge. */
export function usePayoutSummary() {
  return useQuery({ queryKey: payoutKeys.summary, queryFn: () => payoutsApi.summary(), refetchInterval: 60_000 });
}

/** Polls so small requests visibly move to "Đã chuyển" when their automatic payout happens. */
export function useWithdrawals(query: WithdrawalQuery) {
  return useQuery({
    queryKey: payoutKeys.withdrawals(query),
    queryFn: () => payoutsApi.listWithdrawals(query),
    placeholderData: keepPreviousData,
    refetchInterval: 30_000,
  });
}

export function useChefWallets() {
  return useQuery({ queryKey: payoutKeys.wallets, queryFn: () => payoutsApi.wallets() });
}

export function useWalletLedger(chefId: string, limit = 8) {
  return useQuery({ queryKey: [...payoutKeys.ledger(chefId), limit] as const, queryFn: () => payoutsApi.transactions(chefId, limit) });
}

/** What the server will do, applied locally so the row and drawer update at once. */
function project(w: WithdrawalRequest, input: WithdrawalActionInput, now: string): WithdrawalRequest {
  return input.action === "complete"
    ? { ...w, status: "Completed", transactionRef: input.transactionRef.trim(), processedAt: now }
    : { ...w, status: "Rejected", reason: input.reason.trim(), processedAt: now };
}

/**
 * Mark as paid / reject. Optimistically patches the request in every cached list (it stays
 * in its tab until the refetch moves it); rolls back on error.
 */
export function useWithdrawalAction() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: WithdrawalActionInput) => payoutsApi.act(input),
    onMutate: async (input) => {
      await qc.cancelQueries({ queryKey: payoutKeys.withdrawalLists });
      const snapshots = qc.getQueriesData<WithdrawalRequest[]>({ queryKey: payoutKeys.withdrawalLists });
      const now = new Date().toISOString();
      qc.setQueriesData<WithdrawalRequest[]>({ queryKey: payoutKeys.withdrawalLists }, (old) =>
        old?.map((w) => (w.id === input.withdrawalId ? project(w, input, now) : w)),
      );
      return { snapshots };
    },
    onError: (_e, _v, context) => {
      context?.snapshots.forEach(([key, data]) => qc.setQueryData(key, data));
    },
    onSuccess: (updated) => {
      qc.setQueriesData<WithdrawalRequest[]>({ queryKey: payoutKeys.withdrawalLists }, (old) =>
        old?.map((w) => (w.id === updated.id ? updated : w)),
      );
    },
    onSettled: () => {
      qc.invalidateQueries({ queryKey: payoutKeys.all });
      qc.invalidateQueries({ queryKey: ["overview"] });
    },
  });
}
