// src/types/admin.ts
// Admin console types. User fields mirror the backend `UserResponse`
// (ApplicationLayer.DTOs.Users) and `GeneralEnum.UserStatusEnum` / `AuthTypeEnum`.
import type { FlagCategory, ISODateString } from "./moderation";

/* ------------------------------------------------------------------- auth */

export interface AdminSession {
  userId: string;
  fullName: string;
  email: string;
  /** JWT from POST /auth/login (mock: a fake token). */
  accessToken: string;
}

/* ------------------------------------------------------------------ users */

/** `users.role`. Legacy "Member" (and unknown values) read as "User". */
export const USER_ROLES = ["Admin", "User", "Chef"] as const;
export type UserRole = (typeof USER_ROLES)[number];
/** Roles an admin can assign; "Chef" is granted only by approving a chef application. */
export type AssignableRole = Exclude<UserRole, "Chef">;

/** Same order as the C# enum, so numeric values map by index. */
export const USER_STATUSES = ["Active", "Inactive", "Locked", "Banned"] as const;
export type UserStatus = (typeof USER_STATUSES)[number];

export const AUTH_TYPES = ["System", "Google"] as const;
export type AuthType = (typeof AUTH_TYPES)[number];

export const USER_STATUS_LABEL: Record<UserStatus, string> = {
  Active: "Đang hoạt động",
  Inactive: "Chưa kích hoạt",
  Locked: "Tạm khoá",
  Banned: "Bị cấm",
};

export const USER_ROLE_LABEL: Record<UserRole, string> = {
  Admin: "Quản trị viên",
  User: "Thành viên",
  Chef: "Chuyên gia",
};

export interface AdminUser {
  id: string;
  email: string;
  fullName: string;
  phone: string;
  role: UserRole;
  status: UserStatus;
  authType: AuthType;
  createdAt: ISODateString;
  /** Extras the console needs (not in UserResponse yet). Defaults to `role === "Chef"`. */
  isVerifiedChef: boolean;
  postCount: number;
  reportCount: number;
  lastActiveAt: ISODateString | null;
}

export interface UserQuery {
  search: string;
  role: UserRole | "all";
  status: UserStatus | "all";
}

export interface UserStatusChange {
  userId: string;
  status: UserStatus;
  /** Required for Locked / Banned, shown to the user in the app. */
  reason?: string;
}

/* ------------------------------------------------------ chef applications */

export type ChefApplicationStatus = "pending" | "approved" | "rejected";

export const CHEF_APPLICATION_STATUS_LABEL: Record<ChefApplicationStatus, string> = {
  pending: "Chờ duyệt",
  approved: "Đã duyệt",
  rejected: "Từ chối",
};

export interface ChefApplication {
  id: string;
  userId: string;
  fullName: string;
  email: string;
  city: string;
  specialties: string[];
  yearsExperience: number;
  bio: string;
  certificates: { name: string; fileUrl: string | null }[];
  /** Member activity that helps the decision. */
  memberSince: ISODateString;
  postCount: number;
  submittedAt: ISODateString;
  status: ChefApplicationStatus;
  reviewNote?: string;
  reviewedBy?: string;
  reviewedAt?: ISODateString;
}

export interface ChefReviewInput {
  applicationId: string;
  decision: "approved" | "rejected";
  /** Required when rejecting; sent to the applicant. */
  note: string;
}

/* ----------------------------------------------------------------- content */

/**
 * `posts.type`: only "Công thức" and "Hỏi đáp". A video or photo is an attachment
 * (`mediaType` / `mediaUrl`); legacy `type: "video"` reads as a recipe with a video.
 */
export type ContentKind = "recipe" | "discussion";
export type VideoAiStatus = "queued" | "transcribing" | "extracting" | "ready" | "failed";

export const CONTENT_KIND_LABEL: Record<ContentKind, string> = {
  recipe: "Công thức",
  discussion: "Hỏi đáp",
};

/** The "Loại" filter on /content: a kind, or "video" = posts with a video attachment (any kind). */
export type ContentKindFilter = ContentKind | "video" | "all";

export const CONTENT_FILTER_LABEL: Record<Exclude<ContentKindFilter, "all">, string> = {
  recipe: "Công thức",
  discussion: "Hỏi đáp",
  video: "Có video",
};

/** `posts.restaurant_id` joined (computed by BE): the one restaurant a post may tag. */
export interface TaggedRestaurant {
  id: string;
  name: string;
  /** "Q.1", "Q. Bình Thạnh"… */
  district: string;
  isCertified: boolean;
}

export const VIDEO_AI_STATUS_LABEL: Record<VideoAiStatus, string> = {
  queued: "Chờ xử lý",
  transcribing: "Nhận dạng giọng nói",
  extracting: "Đang trích xuất",
  ready: "Đã tóm tắt",
  failed: "AI lỗi",
};

/** `posts.status`: published unless the AI pre-screen flags it (then Pending until an admin decides). */
export const POST_STATUSES = ["Published", "Pending", "Rejected"] as const;
export type PostStatus = (typeof POST_STATUSES)[number];

export const POST_STATUS_LABEL: Record<PostStatus, string> = {
  Published: "Đã đăng",
  Pending: "Chờ duyệt",
  Rejected: "Bị từ chối",
};

/** `posts.media_type` — one attachment per post (single `media_url` column). */
export const MEDIA_TYPES = ["Text", "Image", "Video"] as const;
export type MediaType = (typeof MEDIA_TYPES)[number];

export type PostDecision = "Approve" | "Reject";

export interface ContentItem {
  id: string;
  kind: ContentKind;
  title: string;
  excerpt: string;
  author: { id: string; fullName: string; isVerifiedChef: boolean };
  createdAt: ISODateString;
  likeCount: number;
  commentCount: number;
  reportCount: number;
  hidden: boolean;
  pinned: boolean;
  /** Video attachment + AI recipe extraction (recipes with a video only). */
  video?: { durationSeconds: number; aiStatus: VideoAiStatus; failureReason?: string };
  status: PostStatus;
  mediaType: MediaType;
  mediaUrl: string | null;
  /** "Gắn quán" — organic tag, not paid. */
  restaurant: TaggedRestaurant | null;
  /** The AI pre-screen flag (ai_flags) that held the post. */
  aiFlag?: { reason: string; score: number; category: FlagCategory; createdAt: ISODateString };
  /** moderation_decisions row (one per post). `note` goes back to the author as rejectionReason. */
  decision?: { decision: PostDecision; note: string | null; adminName: string; decidedAt: ISODateString };
}

export type ContentView = "all" | "pending" | "reported" | "hidden" | "pinned" | "rejected";

export interface ContentQuery {
  view: ContentView;
  kind: ContentKind | "all";
  /** "Có video": only posts whose attachment is a video. */
  hasVideo?: boolean;
  search: string;
  /** `?author=` from the user drawer. */
  authorId?: string;
}

export type ContentAction = "hide" | "unhide" | "pin" | "unpin" | "delete" | "retry_ai";

/** POST /admin/posts/{id}/review — `note` is required (≥ 10 chars) when rejecting. */
export interface PostReviewInput {
  postId: string;
  decision: PostDecision;
  note: string;
}

/* ---------------------------------------------------------------- comments */

/** Proposed `comments.status` column. */
export type CommentStatus = "Visible" | "Hidden";

export const COMMENT_STATUS_LABEL: Record<CommentStatus, string> = {
  Visible: "Hiển thị",
  Hidden: "Đã ẩn",
};

export interface AdminComment {
  id: string;
  postId: string;
  postTitle: string;
  /** Replies are one level deep: a reply to a reply points at the same top-level comment. */
  parentId: string | null;
  /** Computed by BE: the parent comment's author (reply rows show "↳ Trả lời {tên}"). */
  replyTo: { id: string; authorName: string } | null;
  /** Top-level comments: number of replies (deleting the comment deletes them too). */
  replyCount: number;
  author: { id: string; fullName: string };
  content: string;
  status: CommentStatus;
  reportCount: number;
  createdAt: ISODateString;
  updatedAt: ISODateString | null;
}

export type CommentView = "all" | "reported" | "hidden";

export interface CommentQuery {
  view: CommentView;
  search: string;
  authorId?: string;
  postId?: string;
}

export type CommentAction = "hide" | "unhide" | "delete";

/* ----------------------------------------------------------------- catalog */

export type CatalogKind = "category" | "diet_tag" | "allergen" | "specialty";

export const CATALOG_KIND_LABEL: Record<CatalogKind, string> = {
  category: "Danh mục món",
  diet_tag: "Thẻ chế độ ăn",
  allergen: "Chất gây dị ứng",
  specialty: "Chuyên môn chuyên gia",
};

export interface CatalogItem {
  id: string;
  kind: CatalogKind;
  /** Stable id used by the apps (e.g. `high_protein`, `peanut`). */
  code: string;
  label: string;
  active: boolean;
  /** Posts / recipes / chefs referencing it. */
  usageCount: number;
  /** Allergens only: label emitted by the fridge-scanner model. */
  cvLabel?: string;
}

export interface CatalogInput {
  kind: CatalogKind;
  code: string;
  label: string;
  cvLabel?: string;
}

/* ---------------------------------------------------------------- overview */

export interface OverviewStats {
  totalUsers: number;
  newUsers7d: number;
  newUsersDelta: number;
  activeUsers24h: number;
  activeDelta: number;
  posts24h: number;
  postsDelta: number;
  aiQueries24h: number;
  aiQueriesDelta: number;
  pending: {
    aiFlags: number;
    chefApplications: number;
    reportedContent: number;
    failedVideos: number;
    /** Posts held by the AI pre-screen (status Pending). */
    pendingPosts: number;
  };
  signupsDaily: { date: ISODateString; count: number }[];
  contentMix: { kind: ContentKind; count: number }[];
  recentActions: { id: string; at: ISODateString; actor: string; action: string; target: string }[];
}
