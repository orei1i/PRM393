// src/lib/admin_api.ts
// Admin-only endpoints. Users map to the backend UsersController
// (GET/PUT/DELETE /users, Admin role); the rest are agreed contracts the
// backend still has to implement (see README › API contract).
import type {
  AdminComment,
  AdminSession,
  AdminUser,
  AssignableRole,
  AuthType,
  CatalogInput,
  CatalogItem,
  CatalogKind,
  ChefApplication,
  ChefApplicationStatus,
  ChefReviewInput,
  CommentAction,
  CommentQuery,
  CommentStatus,
  ContentAction,
  ContentItem,
  ContentKind,
  ContentQuery,
  MediaType,
  OverviewStats,
  PostReviewInput,
  PostStatus,
  UserQuery,
  UserRole,
  UserStatus,
  UserStatusChange,
} from "@/types/admin";
import { AUTH_TYPES, CONTENT_KIND_LABEL, MEDIA_TYPES, USER_STATUSES } from "@/types/admin";

import { qs, request, USE_MOCK_DATA } from "./api_client";
import { ApiError } from "./api_error";
import { readSession } from "./auth";
import { readId } from "./ids";
import * as mock from "./mock_admin";

/* ------------------------------------------------------- normalisation --- */

/** ASP.NET serialises C# enums as numbers unless JsonStringEnumConverter is on. */
function enumValue<T extends string>(values: readonly T[], raw: unknown, fallback: T): T {
  if (typeof raw === "number") return values[raw] ?? fallback;
  if (typeof raw === "string") return values.find((v) => v.toLowerCase() === raw.toLowerCase()) ?? fallback;
  return fallback;
}

/** `users.role`: Admin / User / Chef. Legacy "Member", unknown or missing → "User". */
export function normalizeRole(raw: unknown): UserRole {
  const value = typeof raw === "string" ? raw.toLowerCase() : "";
  if (value === "admin") return "Admin";
  if (value === "chef") return "Chef";
  return "User";
}

type RawUser = Partial<Omit<AdminUser, "id" | "role" | "status" | "authType">> & {
  id?: unknown;
  role?: unknown;
  status?: unknown;
  authType?: unknown;
  /** SQL alias of fullName. */
  name?: string;
};

export function normalizeUser(raw: RawUser): AdminUser {
  const role = normalizeRole(raw.role);
  return {
    id: readId(raw.id),
    email: raw.email ?? "",
    fullName: raw.fullName ?? raw.name ?? "",
    phone: raw.phone ?? "",
    role,
    status: enumValue<UserStatus>(USER_STATUSES, raw.status, "Active"),
    authType: enumValue<AuthType>(AUTH_TYPES, raw.authType, "System"),
    createdAt: raw.createdAt ?? new Date(0).toISOString(),
    isVerifiedChef: raw.isVerifiedChef ?? role === "Chef",
    postCount: raw.postCount ?? 0,
    reportCount: raw.reportCount ?? 0,
    lastActiveAt: raw.lastActiveAt ?? null,
  };
}

/** Wire order of `posts.status`. A missing status is a legacy row → Published. */
const POST_STATUS_WIRE: readonly PostStatus[] = ["Pending", "Published", "Rejected"];

type RawContent = Partial<Omit<ContentItem, "id" | "author" | "status" | "mediaType">> & {
  id?: unknown;
  author?: { id?: unknown; fullName?: string; name?: string; isVerifiedChef?: boolean };
  status?: unknown;
  mediaType?: unknown;
  imageUrl?: string | null;
  /** SQL aliases of excerpt. */
  body?: string;
  content?: string;
};

export function normalizeContent(raw: RawContent): ContentItem {
  const kind: ContentKind = raw.kind && raw.kind in CONTENT_KIND_LABEL ? raw.kind : "discussion";
  const derived: MediaType = kind === "video" ? "Video" : raw.imageUrl || raw.mediaUrl ? "Image" : "Text";
  return {
    id: readId(raw.id),
    kind,
    title: raw.title ?? "",
    excerpt: raw.excerpt ?? raw.body ?? raw.content ?? "",
    author: {
      id: readId(raw.author?.id),
      fullName: raw.author?.fullName ?? raw.author?.name ?? "",
      isVerifiedChef: raw.author?.isVerifiedChef ?? false,
    },
    createdAt: raw.createdAt ?? new Date(0).toISOString(),
    likeCount: raw.likeCount ?? 0,
    commentCount: raw.commentCount ?? 0,
    reportCount: raw.reportCount ?? 0,
    hidden: raw.hidden ?? false,
    pinned: raw.pinned ?? false,
    video: raw.video,
    status: raw.status === undefined || raw.status === null ? "Published" : enumValue(POST_STATUS_WIRE, raw.status, "Pending"),
    mediaType: raw.mediaType === undefined || raw.mediaType === null ? derived : enumValue(MEDIA_TYPES, raw.mediaType, "Text"),
    mediaUrl: raw.mediaUrl ?? raw.imageUrl ?? null,
    aiFlag: raw.aiFlag,
    decision: raw.decision,
  };
}

type RawComment = Partial<Omit<AdminComment, "id" | "postId" | "author" | "status">> & {
  id?: unknown;
  postId?: unknown;
  author?: { id?: unknown; fullName?: string; name?: string };
  status?: unknown;
  /** Mobile CommentDto field name. */
  text?: string;
};

export function normalizeComment(raw: RawComment): AdminComment {
  return {
    id: readId(raw.id),
    postId: readId(raw.postId),
    postTitle: raw.postTitle ?? "",
    author: { id: readId(raw.author?.id), fullName: raw.author?.fullName ?? raw.author?.name ?? "" },
    content: raw.content ?? raw.text ?? "",
    status: enumValue<CommentStatus>(["Visible", "Hidden"], raw.status, "Visible"),
    reportCount: raw.reportCount ?? 0,
    createdAt: raw.createdAt ?? new Date(0).toISOString(),
    updatedAt: raw.updatedAt ?? null,
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

  /** Needs BE: PATCH /users/{id}/role { role: "Admin" | "User" } — Chef comes only from approving an application. */
  async setRole(userId: string, role: AssignableRole): Promise<AdminUser> {
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
  async list(query: ContentQuery): Promise<ContentItem[]> {
    if (USE_MOCK_DATA) return mock.listContent(query);
    const raw = await request<RawContent[]>(
      `/admin/posts?${qs({
        view: query.view,
        kind: query.kind === "all" ? undefined : query.kind,
        search: query.search,
        authorId: query.authorId,
      })}`,
    );
    return raw.map(normalizeContent);
  },

  /** Returns the updated item, or null when deleted. */
  async act(id: string, action: ContentAction): Promise<ContentItem | null> {
    if (USE_MOCK_DATA) return mock.applyContentAction(id, action, readSession());
    if (action === "delete") {
      await request<unknown>(`/admin/posts/${id}`, { method: "DELETE" });
      return null;
    }
    return normalizeContent(await request<RawContent>(`/admin/posts/${id}/actions`, { method: "POST", body: JSON.stringify({ action }) }));
  },

  /** POST /admin/posts/{id}/review { decision, note } → moderation_decisions (admin_id from the JWT). */
  async review(input: PostReviewInput): Promise<ContentItem> {
    if (USE_MOCK_DATA) return mock.reviewPost(input, readSession());
    return normalizeContent(
      await request<RawContent>(`/admin/posts/${input.postId}/review`, {
        method: "POST",
        body: JSON.stringify({ decision: input.decision, note: input.note }),
      }),
    );
  },
};

/* ------------------------------------------------------------ comments --- */

export const commentsApi = {
  async list(query: CommentQuery): Promise<AdminComment[]> {
    if (USE_MOCK_DATA) return mock.listComments(query);
    const raw = await request<RawComment[]>(
      `/admin/comments?${qs({ view: query.view, search: query.search, authorId: query.authorId, postId: query.postId })}`,
    );
    return raw.map(normalizeComment);
  },

  /** hide / unhide return the updated comment; delete returns null. `reason` is sent to the author on delete. */
  async act(id: string, action: CommentAction, reason?: string): Promise<AdminComment | null> {
    if (action === "delete") {
      if (USE_MOCK_DATA) {
        await mock.deleteComment(id, reason, readSession());
        return null;
      }
      await request<unknown>(`/admin/comments/${id}`, { method: "DELETE", body: JSON.stringify({ reason: reason || undefined }) });
      return null;
    }
    if (USE_MOCK_DATA) return mock.applyCommentAction(id, action, readSession());
    return normalizeComment(await request<RawComment>(`/admin/comments/${id}/actions`, { method: "POST", body: JSON.stringify({ action }) }));
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
