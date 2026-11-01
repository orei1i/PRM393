// src/lib/admin_api.ts
// Admin-only endpoints. Real today: admin login, logout, /users and /admin/posts.
// The rest are agreed contracts the backend still has to implement (see README › API contract).
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
  PostDecision,
  PostReviewInput,
  PostStatus,
  UserQuery,
  UserRole,
  UserStatus,
  UserStatusChange,
  VideoAiStatus,
} from "@/types/admin";
import { AUTH_TYPES, CATALOG_KIND_LABEL, CONTENT_KIND_LABEL, MEDIA_TYPES, USER_STATUSES } from "@/types/admin";
import { FLAG_CATEGORY_LABEL, type FlagCategory } from "@/types/moderation";

import { absoluteMediaUrl, qs, refreshAccessToken, request, requestList, requestObject } from "./api_client";
import { ApiError, badResponse } from "./api_error";
import { readSession } from "./auth";
import { isMock, UNSUPPORTED_ACTION } from "./backend_modules";
import { readId } from "./ids";
import * as mock from "./mock_admin";
import { foldText } from "./utils";
import { bool, counts, dateOnly, hasId, isoOr, num, obj, objects, optIso, optText, pick, text, texts, type Raw } from "./wire";

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

/** `name` is the SQL alias of fullName. */
export function normalizeUser(raw: Raw): AdminUser {
  const role = normalizeRole(raw.role);
  return {
    id: readId(raw.id),
    email: text(raw.email),
    fullName: text(raw.fullName ?? raw.name),
    phone: text(raw.phone),
    role,
    status: enumValue<UserStatus>(USER_STATUSES, raw.status, "Active"),
    authType: enumValue<AuthType>(AUTH_TYPES, raw.authType, "System"),
    createdAt: isoOr(raw.createdAt),
    isVerifiedChef: bool(raw.isVerifiedChef, role === "Chef"),
    postCount: num(raw.postCount),
    reportCount: num(raw.reportCount),
    lastActiveAt: optIso(raw.lastActiveAt),
  };
}

/** Wire order of `posts.status`. A missing status is a legacy row → Published. */
const POST_STATUS_WIRE: readonly PostStatus[] = ["Pending", "Published", "Rejected"];

/** "recipe" | "discussion"; legacy "video" (and unknown recipe-like values) → recipe. */
function readKind(raw: unknown): { kind: ContentKind; legacyVideo: boolean } {
  const value = typeof raw === "string" ? raw.toLowerCase() : "";
  if (value === "video") return { kind: "recipe", legacyVideo: true };
  return { kind: Object.hasOwn(CONTENT_KIND_LABEL, value) ? (value as ContentKind) : "discussion", legacyVideo: false };
}

const FLAG_CATEGORIES = Object.keys(FLAG_CATEGORY_LABEL) as FlagCategory[];
const VIDEO_AI_STATUSES: readonly VideoAiStatus[] = ["queued", "transcribing", "extracting", "ready", "failed"];

function readVideo(raw: unknown): ContentItem["video"] {
  const video = obj(raw);
  if (!video) return undefined;
  return { durationSeconds: num(video.durationSeconds), aiStatus: pick(VIDEO_AI_STATUSES, video.aiStatus, "queued"), failureReason: optText(video.failureReason) ?? undefined };
}

function readAiFlag(raw: unknown): ContentItem["aiFlag"] {
  const flag = obj(raw);
  if (!flag) return undefined;
  return { reason: text(flag.reason), score: num(flag.score), category: pick(FLAG_CATEGORIES, flag.category, "toxicity"), createdAt: isoOr(flag.createdAt) };
}

function readDecision(raw: unknown): ContentItem["decision"] {
  const decision = obj(raw);
  if (!decision) return undefined;
  return {
    decision: pick<PostDecision>(["Approve", "Reject"], decision.decision, "Approve"),
    note: optText(decision.note),
    adminName: text(decision.adminName),
    decidedAt: isoOr(decision.decidedAt),
  };
}

/**
 * `kind` is the FE category (legacy "video" → recipe), `type` the mobile PostDto name for it.
 * `isPinned` is the PostResponse name of pinned; `body` and `content` are SQL aliases of excerpt.
 */
export function normalizeContent(raw: Raw): ContentItem {
  const { kind, legacyVideo } = readKind(raw.kind ?? raw.type);
  const video = readVideo(raw.video);
  const derived: MediaType = legacyVideo || video ? "Video" : raw.imageUrl || raw.mediaUrl ? "Image" : "Text";
  const author = obj(raw.author);
  const r = obj(raw.restaurant);
  return {
    id: readId(raw.id),
    kind,
    title: text(raw.title),
    excerpt: text(raw.excerpt ?? raw.body ?? raw.content),
    author: {
      id: readId(author?.id),
      fullName: text(author?.fullName ?? author?.name),
      isVerifiedChef: bool(author?.isVerifiedChef),
    },
    createdAt: isoOr(raw.createdAt),
    likeCount: num(raw.likeCount),
    commentCount: num(raw.commentCount),
    reportCount: num(raw.reportCount),
    hidden: bool(raw.hidden),
    pinned: bool(raw.pinned ?? raw.isPinned),
    video,
    status: raw.status === undefined || raw.status === null ? "Published" : enumValue(POST_STATUS_WIRE, raw.status, "Pending"),
    mediaType: raw.mediaType === undefined || raw.mediaType === null ? derived : enumValue(MEDIA_TYPES, raw.mediaType, "Text"),
    mediaUrl: absoluteMediaUrl(raw.mediaUrl ?? raw.imageUrl),
    restaurant:
      r && r.id !== undefined && r.id !== null
        ? { id: readId(r.id), name: text(r.name), district: text(r.district), isCertified: bool(r.isCertified ?? r.isVeganCertified) }
        : null,
    aiFlag: readAiFlag(raw.aiFlag),
    decision: readDecision(raw.decision),
  };
}

/** `text` is the mobile CommentDto name of content. */
export function normalizeComment(raw: Raw): AdminComment {
  const author = obj(raw.author);
  const replyTo = obj(raw.replyTo);
  return {
    id: readId(raw.id),
    postId: readId(raw.postId),
    postTitle: text(raw.postTitle),
    parentId: raw.parentId === null || raw.parentId === undefined || raw.parentId === "" ? null : readId(raw.parentId),
    replyTo: replyTo && replyTo.id !== undefined && replyTo.id !== null ? { id: readId(replyTo.id), authorName: text(replyTo.authorName ?? replyTo.fullName) } : null,
    replyCount: num(raw.replyCount),
    author: { id: readId(author?.id), fullName: text(author?.fullName ?? author?.name) },
    content: text(raw.content ?? raw.text),
    status: enumValue<CommentStatus>(["Visible", "Hidden"], raw.status, "Visible"),
    reportCount: num(raw.reportCount),
    createdAt: isoOr(raw.createdAt),
    updatedAt: optIso(raw.updatedAt),
  };
}

const CHEF_APPLICATION_STATUSES: readonly ChefApplicationStatus[] = ["pending", "approved", "rejected"];

function normalizeChefApplication(raw: Raw): ChefApplication {
  return {
    id: readId(raw.id),
    userId: readId(raw.userId),
    fullName: text(raw.fullName, "Người dùng"),
    email: text(raw.email),
    city: text(raw.city),
    specialties: texts(raw.specialties),
    yearsExperience: num(raw.yearsExperience),
    bio: text(raw.bio),
    certificates: objects(raw.certificates).map((c) => ({ name: text(c.name), fileUrl: optText(c.fileUrl) })),
    memberSince: isoOr(raw.memberSince),
    postCount: num(raw.postCount),
    submittedAt: isoOr(raw.submittedAt),
    status: pick(CHEF_APPLICATION_STATUSES, raw.status, "pending"),
    reviewNote: optText(raw.reviewNote) ?? undefined,
    reviewedBy: optText(raw.reviewedBy) ?? undefined,
    reviewedAt: optIso(raw.reviewedAt) ?? undefined,
  };
}

const CATALOG_KINDS = Object.keys(CATALOG_KIND_LABEL) as CatalogKind[];

function normalizeCatalogItem(raw: Raw, fallbackKind: CatalogKind): CatalogItem {
  return {
    id: readId(raw.id),
    kind: pick(CATALOG_KINDS, raw.kind, fallbackKind),
    code: text(raw.code),
    label: text(raw.label),
    active: bool(raw.active, true),
    usageCount: num(raw.usageCount),
    cvLabel: optText(raw.cvLabel) ?? undefined,
  };
}

const CONTENT_KINDS = Object.keys(CONTENT_KIND_LABEL) as ContentKind[];

function normalizeOverview(raw: Raw): OverviewStats {
  const pending = obj(raw.pending) ?? {};
  return {
    totalUsers: num(raw.totalUsers),
    newUsers7d: num(raw.newUsers7d),
    newUsersDelta: num(raw.newUsersDelta),
    activeUsers24h: num(raw.activeUsers24h),
    activeDelta: num(raw.activeDelta),
    posts24h: num(raw.posts24h),
    postsDelta: num(raw.postsDelta),
    aiQueries24h: num(raw.aiQueries24h),
    aiQueriesDelta: num(raw.aiQueriesDelta),
    pending: {
      aiFlags: num(pending.aiFlags),
      chefApplications: num(pending.chefApplications),
      reportedContent: num(pending.reportedContent),
      failedVideos: num(pending.failedVideos),
      pendingPosts: num(pending.pendingPosts),
    },
    signupsDaily: objects(raw.signupsDaily)
      .map((d) => ({ date: dateOnly(d.date), count: num(d.count) }))
      .filter((d) => d.date !== ""),
    contentMix: objects(raw.contentMix).map((m) => ({ kind: pick(CONTENT_KINDS, m.kind, "discussion"), count: num(m.count) })),
    recentActions: objects(raw.recentActions)
      .map((a) => ({ id: readId(a.id), at: isoOr(a.at), actor: text(a.actor), action: text(a.action), target: text(a.target) }))
      .filter(hasId),
  };
}

/* ---------------------------------------------------------------- auth --- */

const LOGOUT_TIMEOUT_MS = 3000;

/** Some BE messages are mojibake (auth, UsersController). App text by status; drop this once the BE is fixed. */
async function withStatusText<T>(call: Promise<T>, byStatus: Record<number, string>): Promise<T> {
  try {
    return await call;
  } catch (e) {
    const text = e instanceof ApiError && e.status ? byStatus[e.status] : undefined;
    throw text ? new ApiError(text, (e as ApiError).status, (e as ApiError).code) : e;
  }
}

const NOT_ADMIN = "Tài khoản này không có quyền quản trị. Người dùng vui lòng dùng ứng dụng VeganLife trên điện thoại.";
const BAD_LOGIN = "Máy chủ trả về dữ liệu đăng nhập không hợp lệ. Vui lòng thử lại sau.";

export const authApi = {
  /** POST /auth/admin/login → AuthResponse { accessToken, refreshToken, expiresAt, user }. Other roles get 403. */
  async login(email: string, password: string): Promise<AdminSession> {
    if (isMock("auth")) return mock.login(email, password);
    const res = await withStatusText(requestObject("/auth/admin/login", { method: "POST", body: JSON.stringify({ email, password }) }), {
      401: "Email hoặc mật khẩu không đúng.",
      403: NOT_ADMIN,
    });
    // Without these the session cookie would not decode, and the middleware would send the admin straight back here.
    const accessToken = optText(res.accessToken);
    const rawUser = obj(res.user);
    const user = rawUser ? normalizeUser(rawUser) : null;
    if (!accessToken || !user || !user.id || !user.email || rawUser?.role === undefined) throw new ApiError(BAD_LOGIN, undefined, "bad_response");
    if (user.role !== "Admin") throw new ApiError(NOT_ADMIN, 403, "not_admin");
    return { userId: user.id, email: user.email, fullName: user.fullName, accessToken, refreshToken: optText(res.refreshToken) ?? undefined };
  },

  /** POST /auth/logout revokes the refresh token. Best effort, never throws: signing out must work offline. */
  async logout(): Promise<void> {
    if (isMock("auth")) return;
    const revoke = () => request<void>("/auth/logout", { method: "POST", signal: AbortSignal.timeout(LOGOUT_TIMEOUT_MS) });
    try {
      await revoke();
    } catch (e) {
      // An idle admin's access token has expired; without a new one the refresh token would stay valid on the server.
      if (e instanceof ApiError && e.status === 401) {
        await refreshAccessToken(readSession()?.accessToken)
          .then((fresh) => (fresh ? revoke() : undefined))
          .catch(() => undefined);
      }
    }
  },
};

/* --------------------------------------------------------------- users --- */

const unsupported = () => new ApiError(UNSUPPORTED_ACTION, undefined, "unsupported");
const USER_GONE = "Tài khoản này không còn tồn tại.";

export const usersApi = {
  /** BE: GET /users (Admin) returns every user and takes no query params, so filtering happens client-side. */
  async list(query: UserQuery): Promise<AdminUser[]> {
    if (isMock("users")) return mock.listUsers(query);
    const raw = await requestList("/users");
    const q = foldText(query.search.trim());
    return raw
      .map(normalizeUser)
      .filter(hasId)
      .filter((u) => query.role === "all" || u.role === query.role)
      .filter((u) => query.status === "all" || u.status === query.status)
      .filter((u) => !q || foldText(`${u.fullName} ${u.email} ${u.phone}`).includes(q));
  },

  /** Real mode only (the drawer shows the form there). BE: PUT /users/{id} honours fullName and phone; role and status are ignored. A null phone keeps the old one. */
  async update(userId: string, input: { fullName: string; phone: string | null }): Promise<AdminUser> {
    const raw = await withStatusText(requestObject(`/users/${userId}`, { method: "PUT", body: JSON.stringify(input) }), { 404: USER_GONE });
    return normalizeUser(raw);
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
    await withStatusText(request<unknown>(`/users/${userId}`, { method: "DELETE" }), { 404: USER_GONE });
  },
};

/* ---------------------------------------------------- chef applications --- */

export const chefApplicationsApi = {
  async list(status: ChefApplicationStatus): Promise<ChefApplication[]> {
    if (isMock("chefs")) return mock.listChefApplications(status);
    return (await requestList(`/admin/chef-applications?${qs({ status })}`)).map(normalizeChefApplication).filter(hasId);
  },

  async counts(): Promise<Record<ChefApplicationStatus, number>> {
    if (isMock("chefs")) return mock.getChefApplicationCounts();
    return counts(CHEF_APPLICATION_STATUSES, await requestObject("/admin/chef-applications/counts"));
  },

  async review(input: ChefReviewInput): Promise<ChefApplication> {
    if (isMock("chefs")) return mock.reviewChefApplication(input, readSession());
    return normalizeChefApplication(
      await requestObject(`/admin/chef-applications/${input.applicationId}/review`, {
        method: "POST",
        body: JSON.stringify({ decision: input.decision, note: input.note }),
      }),
    );
  },
};

/* ------------------------------------------------------------- content --- */

const FEED_PAGE_SIZE = 50; // the backend's maximum
const FEED_MAX_PAGES = 100;

/** `status` is case-sensitive on the backend. Without it: every post that is not deleted. */
type AdminPostStatus = "Pending" | "Rejected";

/** BE: GET /admin/posts pages by number. The feed-page answer has no report count, reject reason or hidden flag. */
async function fetchAdminPosts(status: AdminPostStatus | undefined): Promise<ContentItem[]> {
  const byId = new Map<string, ContentItem>();
  for (let page = 1; page <= FEED_MAX_PAGES; page++) {
    const res = await requestObject(`/admin/posts?${qs({ status, page, pageSize: FEED_PAGE_SIZE })}`);
    if (!Array.isArray(res.items)) throw badResponse();
    const before = byId.size;
    for (const item of objects(res.items).map(normalizeContent).filter(hasId)) byId.set(item.id, item);
    // A page with nothing new ends the pass too: a wrong totalPages must not cost 100 requests.
    if (byId.size === before || page >= num(res.totalPages, 1)) break;
  }
  return [...byId.values()];
}

const postsInFlight = new Map<AdminPostStatus | undefined, Promise<ContentItem[]>>();

/** On the "Chờ duyệt" tab two queries want the same list (tab + count); they share one pass over the pages. */
function listAdminPosts(status: AdminPostStatus | undefined): Promise<ContentItem[]> {
  let pass = postsInFlight.get(status);
  if (!pass) {
    pass = fetchAdminPosts(status).finally(() => postsInFlight.delete(status));
    postsInFlight.set(status, pass);
  }
  return pass;
}

const ADMIN_POST_ACTIONS: readonly ContentAction[] = ["hide", "unhide", "restore", "delete"];

export const contentApi = {
  /** The backend filters by status only; the other filters run client-side. /content offers no other real view. */
  async list(query: ContentQuery): Promise<ContentItem[]> {
    if (isMock("content")) return mock.listContent(query);
    const q = foldText(query.search.trim());
    const status = query.view === "pending" ? "Pending" : query.view === "rejected" ? "Rejected" : undefined;
    return (await listAdminPosts(status))
      .filter((c) => query.kind === "all" || c.kind === query.kind)
      .filter((c) => !query.hasVideo || c.mediaType === "Video")
      .filter((c) => !query.authorId || c.author.id === query.authorId)
      .filter((c) => !q || foldText(`${c.title} ${c.author.fullName} ${c.restaurant?.name ?? ""}`).includes(q));
  },

  /** Returns the updated item, or null when deleted. BE: POST /admin/posts/{id}/actions; hide sets Pending (there is no Hidden state). Pin and retry_ai have no route. */
  async act(id: string, action: ContentAction): Promise<ContentItem | null> {
    if (isMock("content")) return mock.applyContentAction(id, action, readSession());
    if (!ADMIN_POST_ACTIONS.includes(action)) throw unsupported();
    const path = `/admin/posts/${id}/actions`;
    const init = { method: "POST", body: JSON.stringify({ action }) };
    if (action !== "delete") return normalizeContent(await requestObject(path, init));
    await request<unknown>(path, init);
    return null;
  },

  /** BE: POST /admin/posts/{id}/review { decision, reason? }. The reason is stored but no endpoint returns it. */
  async review(input: PostReviewInput): Promise<ContentItem> {
    if (isMock("content")) return mock.reviewPost(input, readSession());
    return normalizeContent(
      await requestObject(`/admin/posts/${input.postId}/review`, {
        method: "POST",
        body: JSON.stringify({ decision: input.decision, reason: input.note || undefined }),
      }),
    );
  },
};

/* ------------------------------------------------------------ comments --- */

export const commentsApi = {
  async list(query: CommentQuery): Promise<AdminComment[]> {
    if (isMock("comments")) return mock.listComments(query);
    const raw = await requestList(
      `/admin/comments?${qs({ view: query.view, search: query.search, authorId: query.authorId, postId: query.postId })}`,
    );
    return raw.map(normalizeComment).filter(hasId);
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
    return normalizeComment(await requestObject(`/admin/comments/${id}/actions`, { method: "POST", body: JSON.stringify({ action }) }));
  },
};

/* ------------------------------------------------------------- catalog --- */

export const catalogApi = {
  async list(kind: CatalogKind): Promise<CatalogItem[]> {
    if (isMock("catalog")) return mock.listCatalog(kind);
    return (await requestList(`/admin/catalog?${qs({ kind })}`)).map((item) => normalizeCatalogItem(item, kind)).filter(hasId);
  },

  async create(input: CatalogInput): Promise<CatalogItem> {
    if (isMock("catalog")) return mock.createCatalogItem(input);
    return normalizeCatalogItem(await requestObject("/admin/catalog", { method: "POST", body: JSON.stringify(input) }), input.kind);
  },

  async update(id: string, patch: Partial<Pick<CatalogItem, "label" | "active" | "cvLabel">>): Promise<CatalogItem> {
    if (isMock("catalog")) return mock.updateCatalogItem(id, patch);
    return normalizeCatalogItem(await requestObject(`/admin/catalog/${id}`, { method: "PATCH", body: JSON.stringify(patch) }), "category");
  },

  async remove(id: string): Promise<void> {
    if (isMock("catalog")) return mock.deleteCatalogItem(id);
    await request<unknown>(`/admin/catalog/${id}`, { method: "DELETE" });
  },
};

/* ------------------------------------------------------------ overview --- */

export const overviewApi = {
  async get(): Promise<OverviewStats> {
    if (isMock("overview")) return mock.getOverview();
    return normalizeOverview(await requestObject("/admin/overview"));
  },
};
