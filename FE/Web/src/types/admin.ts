// src/types/admin.ts
// Admin console types. User fields mirror the backend `UserResponse`
// (ApplicationLayer.DTOs.Users) and `GeneralEnum.UserStatusEnum` / `AuthTypeEnum`.
import type { ISODateString } from "./moderation";

/* ------------------------------------------------------------------- auth */

export interface AdminSession {
  userId: string;
  fullName: string;
  email: string;
  /** JWT from POST /auth/login (mock: a fake token). */
  accessToken: string;
}

/* ------------------------------------------------------------------ users */

export const USER_ROLES = ["Admin", "Member"] as const;
export type UserRole = (typeof USER_ROLES)[number];

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
  Member: "Thành viên",
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
  /** Extras the console needs (not in UserResponse yet). */
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

export type ContentKind = "recipe" | "video" | "discussion";
export type VideoAiStatus = "queued" | "transcribing" | "extracting" | "ready" | "failed";

export const CONTENT_KIND_LABEL: Record<ContentKind, string> = {
  recipe: "Công thức",
  video: "Video",
  discussion: "Thảo luận",
};

export const VIDEO_AI_STATUS_LABEL: Record<VideoAiStatus, string> = {
  queued: "Chờ xử lý",
  transcribing: "Nhận dạng giọng nói",
  extracting: "Đang trích xuất",
  ready: "Đã tóm tắt",
  failed: "AI lỗi",
};

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
  video?: { durationSeconds: number; aiStatus: VideoAiStatus; failureReason?: string };
}

export type ContentView = "all" | "reported" | "hidden" | "pinned";

export interface ContentQuery {
  view: ContentView;
  kind: ContentKind | "all";
  search: string;
}

export type ContentAction = "hide" | "unhide" | "pin" | "unpin" | "delete" | "retry_ai";

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
  };
  signupsDaily: { date: ISODateString; count: number }[];
  contentMix: { kind: ContentKind; count: number }[];
  recentActions: { id: string; at: ISODateString; actor: string; action: string; target: string }[];
}
