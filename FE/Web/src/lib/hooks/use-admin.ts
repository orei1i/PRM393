// src/lib/hooks/use-admin.ts
"use client";

import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import type {
  AdminUser,
  CatalogInput,
  CatalogItem,
  CatalogKind,
  ChefApplicationStatus,
  ChefReviewInput,
  ContentAction,
  ContentItem,
  ContentQuery,
  UserQuery,
  UserRole,
  UserStatusChange,
} from "@/types/admin";

import { catalogApi, chefApplicationsApi, contentApi, overviewApi, usersApi } from "../admin_api";

export const adminKeys = {
  overview: ["overview"] as const,
  users: (q?: UserQuery) => (q ? (["users", q] as const) : (["users"] as const)),
  chefApps: (status?: ChefApplicationStatus) => (status ? (["chef-apps", status] as const) : (["chef-apps"] as const)),
  chefCounts: ["chef-apps", "counts"] as const,
  content: (q?: ContentQuery) => (q ? (["content", q] as const) : (["content"] as const)),
  catalog: (kind?: CatalogKind) => (kind ? (["catalog", kind] as const) : (["catalog"] as const)),
};

/* -------------------------------------------------------------- overview */

export function useOverview() {
  return useQuery({ queryKey: adminKeys.overview, queryFn: () => overviewApi.get(), refetchInterval: 60_000 });
}

/* ----------------------------------------------------------------- users */

export function useUsers(query: UserQuery) {
  return useQuery({
    queryKey: adminKeys.users(query),
    queryFn: () => usersApi.list(query),
    placeholderData: keepPreviousData,
  });
}

/** Patches the user in every cached list so the table and drawer update together. */
function usePatchUser() {
  const qc = useQueryClient();
  return (updated: AdminUser) => {
    qc.setQueriesData<AdminUser[]>({ queryKey: ["users"] }, (old) => old?.map((u) => (u.id === updated.id ? updated : u)));
  };
}

export function useSetUserRole() {
  const qc = useQueryClient();
  const patch = usePatchUser();
  return useMutation({
    mutationFn: ({ userId, role }: { userId: string; role: UserRole }) => usersApi.setRole(userId, role),
    onSuccess: patch,
    onSettled: () => {
      qc.invalidateQueries({ queryKey: ["users"] });
      qc.invalidateQueries({ queryKey: adminKeys.overview });
    },
  });
}

export function useSetUserStatus() {
  const qc = useQueryClient();
  const patch = usePatchUser();
  return useMutation({
    mutationFn: (change: UserStatusChange) => usersApi.setStatus(change),
    onSuccess: patch,
    onSettled: () => {
      qc.invalidateQueries({ queryKey: ["users"] });
      qc.invalidateQueries({ queryKey: adminKeys.overview });
    },
  });
}

export function useDeleteUser() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (userId: string) => usersApi.remove(userId),
    onSuccess: (_void, userId) => {
      qc.setQueriesData<AdminUser[]>({ queryKey: ["users"] }, (old) => old?.filter((u) => u.id !== userId));
    },
    onSettled: () => qc.invalidateQueries({ queryKey: ["users"] }),
  });
}

/* ----------------------------------------------------- chef applications */

export function useChefApplications(status: ChefApplicationStatus) {
  return useQuery({
    queryKey: adminKeys.chefApps(status),
    queryFn: () => chefApplicationsApi.list(status),
    placeholderData: keepPreviousData,
  });
}

export function useChefApplicationCounts() {
  return useQuery({ queryKey: adminKeys.chefCounts, queryFn: () => chefApplicationsApi.counts(), refetchInterval: 60_000 });
}

export function useReviewChefApplication() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: ChefReviewInput) => chefApplicationsApi.review(input),
    onMutate: async (input) => {
      await qc.cancelQueries({ queryKey: adminKeys.chefApps("pending") });
      const previous = qc.getQueryData(adminKeys.chefApps("pending"));
      qc.setQueryData(adminKeys.chefApps("pending"), (old: { id: string }[] | undefined) =>
        old?.filter((a) => a.id !== input.applicationId),
      );
      return { previous };
    },
    onError: (_e, _input, context) => {
      if (context?.previous) qc.setQueryData(adminKeys.chefApps("pending"), context.previous);
    },
    onSettled: () => {
      qc.invalidateQueries({ queryKey: ["chef-apps"] });
      qc.invalidateQueries({ queryKey: ["users"] });
      qc.invalidateQueries({ queryKey: adminKeys.overview });
    },
  });
}

/* --------------------------------------------------------------- content */

export function useContent(query: ContentQuery) {
  return useQuery({
    queryKey: adminKeys.content(query),
    queryFn: () => contentApi.list(query),
    placeholderData: keepPreviousData,
  });
}

export function useContentAction() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, action }: { id: string; action: ContentAction }) => contentApi.act(id, action),
    onSuccess: (updated, { id }) => {
      qc.setQueriesData<ContentItem[]>({ queryKey: ["content"] }, (old) =>
        updated ? old?.map((c) => (c.id === id ? updated : c)) : old?.filter((c) => c.id !== id),
      );
    },
    onSettled: () => {
      qc.invalidateQueries({ queryKey: ["content"] });
      qc.invalidateQueries({ queryKey: adminKeys.overview });
    },
  });
}

/* --------------------------------------------------------------- catalog */

export function useCatalog(kind: CatalogKind) {
  return useQuery({ queryKey: adminKeys.catalog(kind), queryFn: () => catalogApi.list(kind) });
}

export function useCatalogMutations(kind: CatalogKind) {
  const qc = useQueryClient();
  const key = adminKeys.catalog(kind);
  const settle = () => qc.invalidateQueries({ queryKey: key });

  const create = useMutation({
    mutationFn: (input: CatalogInput) => catalogApi.create(input),
    onSuccess: (item) => qc.setQueryData<CatalogItem[]>(key, (old) => (old ? [...old, item] : [item])),
    onSettled: settle,
  });

  const update = useMutation({
    mutationFn: ({ id, patch }: { id: string; patch: Partial<Pick<CatalogItem, "label" | "active" | "cvLabel">> }) =>
      catalogApi.update(id, patch),
    onMutate: async ({ id, patch }) => {
      await qc.cancelQueries({ queryKey: key });
      const previous = qc.getQueryData<CatalogItem[]>(key);
      qc.setQueryData<CatalogItem[]>(key, (old) => old?.map((i) => (i.id === id ? { ...i, ...patch } : i)));
      return { previous };
    },
    onError: (_e, _v, context) => {
      if (context?.previous) qc.setQueryData(key, context.previous);
    },
    onSettled: settle,
  });

  const remove = useMutation({
    mutationFn: (id: string) => catalogApi.remove(id),
    onSuccess: (_void, id) => qc.setQueryData<CatalogItem[]>(key, (old) => old?.filter((i) => i.id !== id)),
    onSettled: settle,
  });

  return { create, update, remove };
}
