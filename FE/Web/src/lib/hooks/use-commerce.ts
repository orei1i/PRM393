// src/lib/hooks/use-commerce.ts
"use client";

import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import type { AdminOrder, OrderActionInput, OrderQuery, ServiceQuery } from "@/types/commerce";

import { commerceApi } from "../commerce_api";

export const commerceKeys = {
  all: ["commerce"] as const,
  orders: (q: OrderQuery) => ["commerce", "orders", q] as const,
  services: (q: ServiceQuery) => ["commerce", "services", q] as const,
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

export function useAdminServices(query: ServiceQuery) {
  return useQuery({
    queryKey: commerceKeys.services(query),
    queryFn: () => commerceApi.listServices(query),
    placeholderData: keepPreviousData,
  });
}

/** What the server will do, applied locally so the row and drawer update at once. */
function project(order: AdminOrder, action: OrderActionInput["action"]): AdminOrder {
  if (action === "refund") {
    return {
      ...order,
      status: "Refunded",
      payments: order.payments.map((p) => (p.status === "Paid" ? { ...p, status: "Refunded" } : p)),
      accessGrant: order.accessGrant && { ...order.accessGrant, status: "Revoked" },
      consultation:
        order.consultation && order.consultation.status !== "Completed" ? { ...order.consultation, status: "Cancelled" } : order.consultation,
    };
  }
  return {
    ...order,
    status: "Cancelled",
    payments: order.payments.map((p) => (p.status === "Pending" ? { ...p, status: "Expired" } : p)),
    consultation: order.consultation && { ...order.consultation, status: "Cancelled" },
  };
}

/**
 * Refund (Paid) / cancel (Pending). Optimistically patches the order in every cached
 * list (it stays in place until the refetch moves it between status tabs); rolls back on error.
 */
export function useOrderAction() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: OrderActionInput) => commerceApi.act(input),
    onMutate: async (input) => {
      await qc.cancelQueries({ queryKey: ["commerce", "orders"] });
      const snapshots = qc.getQueriesData<AdminOrder[]>({ queryKey: ["commerce", "orders"] });
      qc.setQueriesData<AdminOrder[]>({ queryKey: ["commerce", "orders"] }, (old) =>
        old?.map((o) => (o.id === input.orderId ? project(o, input.action) : o)),
      );
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
      qc.invalidateQueries({ queryKey: ["overview"] });
    },
  });
}
