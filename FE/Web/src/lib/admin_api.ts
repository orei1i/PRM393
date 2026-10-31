// src/lib/admin_api.ts
// Admin-only endpoints. Real today: login, GET/DELETE /users, and posts through the
// public GET /posts + DELETE /posts/{id}. The rest are agreed contracts the backend
// still has to implement (see README › API contract).
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

import { absoluteMediaUrl, qs, request } from "./api_client";
import { ApiError } from "./api_error";
import { readSession } from "./auth";
import { isMock, UNSUPPORTED_ACTION } from "./backend_modules";
import { readId } from "./ids";
import * as mock from "./mock_admin";
import { foldText } from "./utils";

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

type RawContent = Partial<Omit<ContentItem, "id" | "author" | "status" | "mediaType" | "kind" | "restaurant">> & {
  id?: unknown;
  /** FE category; legacy "video" → recipe. Mobile PostDto calls it `type`. */
  kind?: string;
  type?: string;
  restaurant?: { id?: unknown; name?: string; district?: string; isCertified?: boolean; isVeganCertified?: boolean } | null;
  author?: { id?: unknown; fullName?: string; name?: string; isVerifiedChef?: boolean };
  status?: unknown;
  mediaType?: unknown;
  imageUrl?: string | null;
  /** PostResponse name of pinned. */
  isPinned?: boolean;
  /** SQL aliases of excerpt. */
  body?: string;
  content?: string;
};

/** "recipe" | "discussion"; legacy "video" (and unknown recipe-like values) → recipe. */
function readKind(raw: unknown): { kind: ContentKind; legacyVideo: boolean } {
  const value = typeof raw === "string" ? raw.toLowerCase() : "";
  if (value === "video") return { kind: "recipe", legacyVideo: true };
  return { kind: value in CONTENT_KIND_LABEL ? (value as ContentKind) : "discussion", legacyVideo: false };
}

export function normalizeContent(raw: RawContent): ContentItem {
  const { kind, legacyVideo } = readKind(raw.kind ?? raw.type);
  const derived: MediaType = legacyVideo || raw.video ? "Video" : raw.imageUrl || raw.mediaUrl ? "Image" : "Text";
  const r = raw.restaurant;
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
    pinned: raw.pinned ?? raw.isPinned ?? false,
    video: raw.video,
    status: raw.status === undefined || raw.status === null ? "Published" : enumValue(POST_STATUS_WIRE, raw.status, "Pending"),
    mediaType: raw.mediaType === undefined || raw.mediaType === null ? derived : enumValue(MEDIA_TYPES, raw.mediaType, "Text"),
    mediaUrl: absoluteMediaUrl(raw.mediaUrl ?? raw.imageUrl),
    restaurant:
      r && r.id !== undefined && r.id !== null
        ? { id: readId(r.id), name: r.name ?? "", district: r.district ?? "", isCertified: r.isCertified ?? r.isVeganCertified ?? false }
        : null,
    aiFlag: raw.aiFlag,
    decision: raw.decision,
  };
}

type RawComment = Partial<Omit<AdminComment, "id" | "postId" | "author" | "status" | "parentId" | "replyTo">> & {
  id?: unknown;
  postId?: unknown;
  parentId?: unknown;
  replyTo?: { id?: unknown; authorName?: string; fullName?: string } | null;
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
    parentId: raw.parentId === null || raw.parentId === undefined || raw.parentId === "" ? null : readId(raw.parentId),
    replyTo:
      raw.replyTo && raw.replyTo.id !== undefined && raw.replyTo.id !== null
        ? { id: readId(raw.replyTo.id), authorName: raw.replyTo.authorName ?? raw.replyTo.fullName ?? "" }
        : null,
    replyCount: raw.replyCount ?? 0,
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

/** BE bug B2: the only login endpoint answers 403 for every Admin, with a message meant for the mobile app. */
const ADMIN_LOGIN_BLOCKED = "Máy chủ chưa cho phép tài khoản quản trị đăng nhập. Hãy báo nhóm BE.";

export const authApi = {
  /** POST /auth/login → AuthResponse { accessToken, refreshToken, expiresAt, user } */
  async login(email: string, password: string): Promise<AdminSession> {
    if (isMock("auth")) return mock.login(email, password);
    const res = await request<AuthResponse>("/auth/login", { method: "POST", body: JSON.stringify({ email, password }) }).catch((e: unknown) => {
      throw e instanceof ApiError && e.status === 403 ? new ApiError(ADMIN_LOGIN_BLOCKED, 403, "admin_login_blocked") : e;
    });
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

const unsupported = () => new ApiError(UNSUPPORTED_ACTION, undefined, "unsupported");

export const usersApi = {
  /** BE: GET /users (Admin) returns every user; filtering happens client-side until it supports query params. */
  async list(query: UserQuery): Promise<AdminUser[]> {
    if (isMock("users")) return mock.listUsers(query);
    const raw = await request<RawUser[]>(`/users?${qs({ search: query.search, role: query.role === "all" ? undefined : query.role })}`);
    const q = foldText(query.search.trim());
    return raw
      .map(normalizeUser)
      .filter((u) => query.role === "all" || u.role === query.role)
      .filter((u) => query.status === "all" || u.status === query.status)
      .filter((u) => !q || foldText(`${u.fullName} ${u.email} ${u.phone}`).includes(q));
  },

  /** Needs BE: PATCH /users/{id}/role { role: "Admin" | "User" } — Chef comes only from approving an application. */
  async setRole(userId: string, role: AssignableRole): Promise<AdminUser> {
    if (isMock("users")) return mock.updateUserRole(userId, role, readSession());
    throw unsupported();
  },

  /** Needs BE: PATCH /users/{id}/status { status, reason } — status sent as the C# enum name. */
  async setStatus(change: UserStatusChange): Promise<AdminUser> {
    if (isMock("users")) return mock.updateUserStatus(change, readSession());
    throw unsupported();
  },

  /** BE: DELETE /users/{id} (Admin) */
  async remove(userId: string): Promise<void> {
    if (isMock("users")) return mock.deleteUser(userId, readSession());
    await request<unknown>(`/users/${userId}`, { method: "DELETE" });
  },
};

/* ---------------------------------------------------- chef applications --- */

export const chefApplicationsApi = {
  list(status: ChefApplicationStatus): Promise<ChefApplication[]> {
    if (isMock("chefs")) return mock.listChefApplications(status);
    return request<ChefApplication[]>(`/admin/chef-applications?${qs({ status })}`);
  },

  counts(): Promise<Record<ChefApplicationStatus, number>> {
    if (isMock("chefs")) return mock.getChefApplicationCounts();
    return request<Record<ChefApplicationStatus, number>>("/admin/chef-applications/counts");
  },

  review(input: ChefReviewInput): Promise<ChefApplication> {
    if (isMock("chefs")) return mock.reviewChefApplication(input, readSession());
    return request<ChefApplication>(`/admin/chef-applications/${input.applicationId}/review`, {
      method: "POST",
      body: JSON.stringify({ decision: input.decision, note: input.note }),
    });
  },
};

/* ------------------------------------------------------------- content --- */

const FEED_PAGE_SIZE = 50; // the backend's maximum
const FEED_MAX_PAGES = 100;

interface FeedPage {
  items: RawContent[];
  totalPages?: number;
}

/** BE: GET /posts is public and lists Published posts only. `nextCursor` is ignored by the backend (B15), so this pages by number. */
async function fetchPublishedPosts(): Promise<ContentItem[]> {
  const byId = new Map<string, ContentItem>();
  for (let page = 1; page <= FEED_MAX_PAGES; page++) {
    const res = await request<FeedPage>(`/posts?${qs({ page, pageSize: FEED_PAGE_SIZE })}`);
    for (const raw of res.items) {
      const item = normalizeContent(raw);
      // B21: every video claims AI status "ready" with duration 0, though no AI pipeline exists yet.
      if (item.video?.aiStatus === "ready" && !item.video.durationSeconds) item.video = undefined;
      byId.set(item.id, item);
    }
    if (res.items.length === 0 || page >= (res.totalPages ?? 1)) break;
  }
  return [...byId.values()];
}

let postsInFlight: Promise<ContentItem[]> | null = null;

/** /content runs two queries at once (current tab + pending count); they share one pass over the pages. */
function listPublishedPosts(): Promise<ContentItem[]> {
  postsInFlight ??= fetchPublishedPosts().finally(() => {
    postsInFlight = null;
  });
  return postsInFlight;
}

function inContentView(c: ContentItem, view: ContentQuery["view"]): boolean {
  switch (view) {
    case "pending":
      return c.status === "Pending";
    case "rejected":
      return c.status === "Rejected";
    case "reported":
      return c.status === "Published" && c.reportCount > 0 && !c.hidden;
    case "hidden":
      return c.hidden;
    case "pinned":
      return c.pinned;
    default:
      return true;
  }
}

export const contentApi = {
  /** The backend has no admin list or filters yet, so every filter runs client-side. */
  async list(query: ContentQuery): Promise<ContentItem[]> {
    if (isMock("content")) return mock.listContent(query);
    const q = foldText(query.search.trim());
    return (await listPublishedPosts())
      .filter((c) => query.kind === "all" || c.kind === query.kind)
      .filter((c) => !query.hasVideo || c.mediaType === "Video")
      .filter((c) => !query.authorId || c.author.id === query.authorId)
      .filter((c) => inContentView(c, query.view))
      .filter((c) => !q || foldText(`${c.title} ${c.author.fullName} ${c.restaurant?.name ?? ""}`).includes(q));
  },

  /** Returns the updated item, or null when deleted. */
  async act(id: string, action: ContentAction): Promise<ContentItem | null> {
    if (isMock("content")) return mock.applyContentAction(id, action, readSession());
    // Needs BE: POST /admin/posts/{id}/actions for hide, unhide, pin, unpin and retry_ai.
    if (action !== "delete") throw unsupported();
    await request<unknown>(`/posts/${id}`, { method: "DELETE" });
    return null;
  },

  /** Needs BE: POST /admin/posts/{id}/review { decision, note } → moderation_decisions (admin_id from the JWT). */
  async review(input: PostReviewInput): Promise<ContentItem> {
    if (isMock("content")) return mock.reviewPost(input, readSession());
    throw unsupported();
  },
};

/* ------------------------------------------------------------ comments --- */

export const commentsApi = {
  async list(query: CommentQuery): Promise<AdminComment[]> {
    if (isMock("comments")) return mock.listComments(query);
    const raw = await request<RawComment[]>(
      `/admin/comments?${qs({ view: query.view, search: query.search, authorId: query.authorId, postId: query.postId })}`,
    );
    return raw.map(normalizeComment);
  },

  /** hide / unhide return the updated comment; delete returns null. `reason` is sent to the author on delete. */
  async act(id: string, action: CommentAction, reason?: string): Promise<AdminComment | null> {
    if (action === "delete") {
      if (isMock("comments")) {
        await mock.deleteComment(id, reason, readSession());
        return null;
      }
      await request<unknown>(`/admin/comments/${id}`, { method: "DELETE", body: JSON.stringify({ reason: reason || undefined }) });
      return null;
    }
    if (isMock("comments")) return mock.applyCommentAction(id, action, readSession());
    return normalizeComment(await request<RawComment>(`/admin/comments/${id}/actions`, { method: "POST", body: JSON.stringify({ action }) }));
  },
};

/* ------------------------------------------------------------- catalog --- */

export const catalogApi = {
  list(kind: CatalogKind): Promise<CatalogItem[]> {
    if (isMock("catalog")) return mock.listCatalog(kind);
    return request<CatalogItem[]>(`/admin/catalog?${qs({ kind })}`);
  },

  create(input: CatalogInput): Promise<CatalogItem> {
    if (isMock("catalog")) return mock.createCatalogItem(input);
    return request<CatalogItem>("/admin/catalog", { method: "POST", body: JSON.stringify(input) });
  },

  update(id: string, patch: Partial<Pick<CatalogItem, "label" | "active" | "cvLabel">>): Promise<CatalogItem> {
    if (isMock("catalog")) return mock.updateCatalogItem(id, patch);
    return request<CatalogItem>(`/admin/catalog/${id}`, { method: "PATCH", body: JSON.stringify(patch) });
  },

  async remove(id: string): Promise<void> {
    if (isMock("catalog")) return mock.deleteCatalogItem(id);
    await request<unknown>(`/admin/catalog/${id}`, { method: "DELETE" });
  },
};

/* ------------------------------------------------------------ overview --- */

export const overviewApi = {
  get(): Promise<OverviewStats> {
    if (isMock("overview")) return mock.getOverview();
    return request<OverviewStats>("/admin/overview");
  },
};
