// src/lib/hooks/use-bookings.ts
"use client";

import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { decisionOutcome, type AdminComplaint, type ComplaintDecisionInput, type ComplaintQuery, type EscrowHoldQuery } from "@/types/bookings";

import { bookingsApi } from "../bookings_api";

export const bookingKeys = {
  all: ["bookings"] as const,
  complaintLists: ["bookings", "complaints"] as const,
  complaints: (q: ComplaintQuery) => ["bookings", "complaints", q] as const,
  complaint: (id: string) => ["bookings", "complaint", id] as const,
  summary: ["bookings", "escrow-summary"] as const,
  holds: (q: EscrowHoldQuery) => ["bookings", "holds", q] as const,
};

export function useComplaints(query: ComplaintQuery) {
  return useQuery({
    queryKey: bookingKeys.complaints(query),
    queryFn: () => bookingsApi.listComplaints(query),
    placeholderData: keepPreviousData,
  });
}

/** Detail with plan days and chat; `initial` (the list row) renders the header at once. */
export function useComplaint(id: string | null, initial?: AdminComplaint | null) {
  return useQuery({
    queryKey: bookingKeys.complaint(id ?? ""),
    queryFn: () => bookingsApi.getComplaint(id ?? ""),
    enabled: id !== null,
    placeholderData: initial && initial.id === id ? initial : undefined,
  });
}

/** KPIs, tab badge, sidebar badge and the overview queue. */
export function useEscrowSummary() {
  return useQuery({ queryKey: bookingKeys.summary, queryFn: () => bookingsApi.summary(), refetchInterval: 60_000 });
}

export function useEscrowHolds(query: EscrowHoldQuery, enabled = true) {
  return useQuery({
    queryKey: bookingKeys.holds(query),
    queryFn: () => bookingsApi.listHolds(query),
    placeholderData: keepPreviousData,
    enabled,
  });
}

/** What the server will do, applied locally so the row and drawer update at once. */
function project(c: AdminComplaint, input: ComplaintDecisionInput, now: string): AdminComplaint {
  const price = c.booking.contract?.price ?? c.booking.escrow?.amount ?? 0;
  const out = decisionOutcome(price, input.decision, input.refundAmount);
  const escrow = c.booking.escrow && {
    ...c.booking.escrow,
    status: input.decision === "ReleaseToChef" ? ("Released" as const) : input.decision === "RefundMember" ? ("Refunded" as const) : ("PartiallyRefunded" as const),
    releasedAt: out.chefGross > 0 ? now : null,
    releasedAmount: out.chefGross,
    feeAmount: out.fee,
    refundedAmount: out.refund,
    resolutionNote: input.note.trim(),
  };
  return {
    ...c,
    status: "Resolved",
    decision: input.decision,
    refundAmount: out.refund,
    adminNote: input.note.trim(),
    decidedAt: now,
    booking: { ...c.booking, status: "Resolved", escrow },
  };
}

/**
 * Decide a complaint. Optimistically patches the complaint in every cached list and its detail
 * (it stays in its tab until the refetch moves it); rolls back on error (400 / 409 / 503).
 */
export function useComplaintDecision() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: ComplaintDecisionInput) => bookingsApi.decide(input),
    onMutate: async (input) => {
      await qc.cancelQueries({ queryKey: bookingKeys.complaintLists });
      await qc.cancelQueries({ queryKey: bookingKeys.complaint(input.complaintId) });
      const lists = qc.getQueriesData<AdminComplaint[]>({ queryKey: bookingKeys.complaintLists });
      const detail = qc.getQueryData<AdminComplaint>(bookingKeys.complaint(input.complaintId));
      const now = new Date().toISOString();
      qc.setQueriesData<AdminComplaint[]>({ queryKey: bookingKeys.complaintLists }, (old) =>
        old?.map((c) => (c.id === input.complaintId ? project(c, input, now) : c)),
      );
      if (detail) qc.setQueryData(bookingKeys.complaint(input.complaintId), project(detail, input, now));
      return { lists, detail };
    },
    onError: (_e, input, context) => {
      context?.lists.forEach(([key, data]) => qc.setQueryData(key, data));
      if (context?.detail) qc.setQueryData(bookingKeys.complaint(input.complaintId), context.detail);
    },
    onSuccess: (updated) => {
      qc.setQueriesData<AdminComplaint[]>({ queryKey: bookingKeys.complaintLists }, (old) =>
        old?.map((c) => (c.id === updated.id ? { ...updated, planDays: c.planDays, messages: c.messages } : c)),
      );
      qc.setQueryData(bookingKeys.complaint(updated.id), updated);
    },
    onSettled: () => {
      qc.invalidateQueries({ queryKey: bookingKeys.all });
      qc.invalidateQueries({ queryKey: ["commerce"] });
      qc.invalidateQueries({ queryKey: ["payouts"] });
      qc.invalidateQueries({ queryKey: ["overview"] });
    },
  });
}
