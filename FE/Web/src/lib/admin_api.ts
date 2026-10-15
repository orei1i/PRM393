// src/lib/admin_api.ts
// Admin-only endpoints. Users map to the backend UsersController
// (GET/PUT/DELETE /users, Admin role); the rest are agreed contracts the
// backend still has to implement (see README › API contract).
import type {
  AdminSession,
  AdminUser,
  AuthType,
  CatalogInput,
  CatalogItem,
  CatalogKind,
  ChefApplication,
  ChefApplicationStatus,
  ChefReviewInput,
  ContentAction,
  ContentItem,
  ContentQuery,
  OverviewStats,
  UserQuery,
  UserRole,
  UserStatus,
  UserStatusChange,
} from "@/types/admin";
import { AUTH_TYPES, USER_STATUSES } from "@/types/admin";

import { qs, request, USE_MOCK_DATA } from "./api_client";
import { ApiError } from "./api_error";
import { readSession } from "./auth";
import * as mock from "./mock_admin";

/* ------------------------------------------------------- normalisation --- */

/** ASP.NET serialises C# enums as numbers unless JsonStringEnumConverter is on. */
function enumValue<T extends string>(values: readonly T[], raw: unknown, fallback: T): T {
  if (typeof raw === "number") return values[raw] ?? fallback;
  if (typeof raw === "string") return values.find((v) => v.toLowerCase() === raw.toLowerCase()) ?? fallback;
  return fallback;
}

type RawUser = Partial<Omit<AdminUser, "status" | "authType">> & { status?: unknown; authType?: unknown };

export function normalizeUser(raw: RawUser): AdminUser {
  return {
    id: String(raw.id ?? ""),
    email: raw.email ?? "",
    fullName: raw.fullName ?? "",
    phone: raw.phone ?? "",
    role: raw.role === "Admin" ? "Admin" : "Member",
    status: enumValue<UserStatus>(USER_STATUSES, raw.status, "Active"),
    authType: enumValue<AuthType>(AUTH_TYPES, raw.authType, "System"),
    createdAt: raw.createdAt ?? new Date(0).toISOString(),
    isVerifiedChef: raw.isVerifiedChef ?? false,
    postCount: raw.postCount ?? 0,
    reportCount: raw.reportCount ?? 0,
    lastActiveAt: raw.lastActiveAt ?? null,
  };
}

/* ---------------------------------------------------------------- auth --- */

interface AuthResponse {
  accessToken: string;
  user: RawUser;
}

export const authApi = {
  /** POST /auth/login → AuthResponse { accessToken, refreshToken, expiresAt, user } */
  async login(email: string, password: string): Promise<AdminSession> {
    if (USE_MOCK_DATA) return mock.login(email, password);
    const res = await request<AuthResponse>("/auth/login", { method: "POST", body: JSON.stringify({ email, password }) });
    const user = normalizeUser(res.user);
    if (user.role !== "Admin") {
      throw new ApiError(
        "Tài khoản này không có quyền quản trị. Người dùng vui lòng dùng ứng dụng VeganLife trên điện thoại.",
        403,
        "not_admin",
      );
    }
    return { userId: user.id, email: user.email, fullName: user.fullName, accessToken: res.accessToken };
  },
};

/* --------------------------------------------------------------- users --- */

export const usersApi = {
  /** BE: GET /users (Admin) returns every user; filtering happens client-side until it supports query params. */
  async list(query: UserQuery): Promise<AdminUser[]> {
    if (USE_MOCK_DATA) return mock.listUsers(query);
    const raw = await request<RawUser[]>(`/users?${qs({ search: query.search, role: query.role === "all" ? undefined : query.role })}`);
    const q = query.search.trim().toLowerCase();
    return raw
      .map(normalizeUser)
      .filter((u) => query.role === "all" || u.role === query.role)
      .filter((u) => query.status === "all" || u.status === query.status)
      .filter((u) => !q || `${u.fullName} ${u.email} ${u.phone}`.toLowerCase().includes(q));
  },

  /** Needs BE: PATCH /users/{id}/role { role } */
  async setRole(userId: string, role: UserRole): Promise<AdminUser> {
    if (USE_MOCK_DATA) return mock.updateUserRole(userId, role, readSession());
    return normalizeUser(await request<RawUser>(`/users/${userId}/role`, { method: "PATCH", body: JSON.stringify({ role }) }));
  },

  /** Needs BE: PATCH /users/{id}/status { status, reason } — status sent as the C# enum name. */
  async setStatus(change: UserStatusChange): Promise<AdminUser> {
    if (USE_MOCK_DATA) return mock.updateUserStatus(change, readSession());
    return normalizeUser(
      await request<RawUser>(`/users/${change.userId}/status`, {
        method: "PATCH",
        body: JSON.stringify({ status: change.status, reason: change.reason }),
      }),
    );
  },

  /** BE: DELETE /users/{id} (Admin) */
  async remove(userId: string): Promise<void> {
    if (USE_MOCK_DATA) return mock.deleteUser(userId, readSession());
    await request<unknown>(`/users/${userId}`, { method: "DELETE" });
  },
};

/* ---------------------------------------------------- chef applications --- */

export const chefApplicationsApi = {
  list(status: ChefApplicationStatus): Promise<ChefApplication[]> {
    if (USE_MOCK_DATA) return mock.listChefApplications(status);
    return request<ChefApplication[]>(`/admin/chef-applications?${qs({ status })}`);
  },

  counts(): Promise<Record<ChefApplicationStatus, number>> {
    if (USE_MOCK_DATA) return mock.getChefApplicationCounts();
    return request<Record<ChefApplicationStatus, number>>("/admin/chef-applications/counts");
  },

  review(input: ChefReviewInput): Promise<ChefApplication> {
    if (USE_MOCK_DATA) return mock.reviewChefApplication(input, readSession());
    return request<ChefApplication>(`/admin/chef-applications/${input.applicationId}/review`, {
      method: "POST",
      body: JSON.stringify({ decision: input.decision, note: input.note }),
    });
  },
};

/* ------------------------------------------------------------- content --- */

export const contentApi = {
  list(query: ContentQuery): Promise<ContentItem[]> {
    if (USE_MOCK_DATA) return mock.listContent(query);
    return request<ContentItem[]>(
      `/admin/posts?${qs({ view: query.view, kind: query.kind === "all" ? undefined : query.kind, search: query.search })}`,
    );
  },

  /** Returns the updated item, or null when deleted. */
  async act(id: string, action: ContentAction): Promise<ContentItem | null> {
    if (USE_MOCK_DATA) return mock.applyContentAction(id, action, readSession());
    if (action === "delete") {
      await request<unknown>(`/admin/posts/${id}`, { method: "DELETE" });
      return null;
    }
    return request<ContentItem>(`/admin/posts/${id}/actions`, { method: "POST", body: JSON.stringify({ action }) });
  },
};

/* ------------------------------------------------------------- catalog --- */

export const catalogApi = {
  list(kind: CatalogKind): Promise<CatalogItem[]> {
    if (USE_MOCK_DATA) return mock.listCatalog(kind);
    return request<CatalogItem[]>(`/admin/catalog?${qs({ kind })}`);
  },

  create(input: CatalogInput): Promise<CatalogItem> {
    if (USE_MOCK_DATA) return mock.createCatalogItem(input);
    return request<CatalogItem>("/admin/catalog", { method: "POST", body: JSON.stringify(input) });
  },

  update(id: string, patch: Partial<Pick<CatalogItem, "label" | "active" | "cvLabel">>): Promise<CatalogItem> {
    if (USE_MOCK_DATA) return mock.updateCatalogItem(id, patch);
    return request<CatalogItem>(`/admin/catalog/${id}`, { method: "PATCH", body: JSON.stringify(patch) });
  },

  async remove(id: string): Promise<void> {
    if (USE_MOCK_DATA) return mock.deleteCatalogItem(id);
    await request<unknown>(`/admin/catalog/${id}`, { method: "DELETE" });
  },
};

/* ------------------------------------------------------------ overview --- */

export const overviewApi = {
  get(): Promise<OverviewStats> {
    if (USE_MOCK_DATA) return mock.getOverview();
    return request<OverviewStats>("/admin/overview");
  },
};
