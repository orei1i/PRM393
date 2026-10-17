// src/lib/hooks/use-commerce.ts
"use client";

import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import type { AdminOrder, OrderActionInput, OrderQuery } from "@/types/commerce";

import { commerceApi } from "../commerce_api";

export const commerceKeys = {
  all: ["commerce"] as const,
  orders: (q: OrderQuery) => ["commerce", "orders", q] as const,
  summary: ["commerce", "summary"] as const,
};

export function useOrders(query: OrderQuery) {
  return useQuery({
    queryKey: commerceKeys.orders(query),
    queryFn: () => commerceApi.listOrders(query),
    placeholderData: keepPreviousData,
  });
}

export function useCommerceSummary() {
  return useQuery({ queryKey: commerceKeys.summary, queryFn: () => commerceApi.summary(), refetchInterval: 60_000 });
}

/** What the server will do, applied locally so the row and drawer update at once. */
function project(order: AdminOrder): AdminOrder {
  return {
    ...order,
    status: "Cancelled",
    payments: order.payments.map((p) => (p.status === "Pending" ? { ...p, status: "Expired" } : p)),
    booking: { ...order.booking, status: "Cancelled" },
  };
}

/**
 * Cancel an unpaid order. Optimistically patches the order in every cached list (it stays in
 * place until the refetch moves it between status tabs); rolls back on error.
 */
export function useOrderAction() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: OrderActionInput) => commerceApi.act(input),
    onMutate: async (input) => {
      await qc.cancelQueries({ queryKey: ["commerce", "orders"] });
      const snapshots = qc.getQueriesData<AdminOrder[]>({ queryKey: ["commerce", "orders"] });
      qc.setQueriesData<AdminOrder[]>({ queryKey: ["commerce", "orders"] }, (old) => old?.map((o) => (o.id === input.orderId ? project(o) : o)));
      return { snapshots };
    },
    onError: (_e, _v, context) => {
      context?.snapshots.forEach(([key, data]) => qc.setQueryData(key, data));
    },
    onSuccess: (order) => {
      qc.setQueriesData<AdminOrder[]>({ queryKey: ["commerce", "orders"] }, (old) => old?.map((o) => (o.id === order.id ? order : o)));
    },
    onSettled: () => {
      qc.invalidateQueries({ queryKey: commerceKeys.all });
      qc.invalidateQueries({ queryKey: ["bookings"] });
      qc.invalidateQueries({ queryKey: ["overview"] });
    },
  });
}
