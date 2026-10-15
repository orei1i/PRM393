// src/types/ads.ts
// Store ads: sponsored restaurant cards shown in the mobile forum / feed ("Được tài trợ").
//
// ┌ For the BE team: NOT in the 26-table SQL design. Proposed table:
// │ ad_campaigns  id, restaurant_id (FK restaurants), headline NVARCHAR(60), message NVARCHAR(140),
// │               cta_type VARCHAR(16) (ViewStore | Directions | Book), target_city NVARCHAR(64) NULL
// │               (NULL = toàn quốc), start_at, end_at, is_paused BIT, budget INT (VND), spent INT,
// │               impressions INT, clicks INT, created_by (FK users), created_at, updated_at
// │ Optional raw events feeding the counters: ad_events (id, campaign_id, user_id NULL,
// │               type Impression | Click, created_at).
// └ `status` is not stored: BE computes it with `deriveAdStatus` below. Wire = camelCase (plan D2).
import type { ISODateString } from "./moderation";

/* ---------------------------------------------------------------- enums */

export const AD_STATUSES = ["Running", "Scheduled", "Paused", "Ended"] as const;
export type AdStatus = (typeof AD_STATUSES)[number];

export const AD_STATUS_LABEL: Record<AdStatus, string> = {
  Running: "Đang chạy",
  Scheduled: "Lên lịch",
  Paused: "Tạm dừng",
  Ended: "Đã kết thúc",
};

export const AD_CTA_TYPES = ["ViewStore", "Directions", "Book"] as const;
export type AdCtaType = (typeof AD_CTA_TYPES)[number];

/** Button label on the mobile card. ViewStore → restaurant detail, Directions → Google Maps, Book → booking / call. */
export const AD_CTA_LABEL: Record<AdCtaType, string> = {
  ViewStore: "Xem quán",
  Directions: "Chỉ đường",
  Book: "Đặt bàn",
};

/** Same spelling as the mobile `city` values. `targetCity: null` = toàn quốc. */
export const AD_CITIES = ["TP. Hồ Chí Minh", "Hà Nội", "Đà Nẵng", "Huế", "Đà Lạt", "Cần Thơ"] as const;

export const AD_HEADLINE_MIN = 5;
export const AD_HEADLINE_MAX = 60;
export const AD_MESSAGE_MIN = 10;
export const AD_MESSAGE_MAX = 140;
export const AD_MIN_BUDGET = 100_000;

/* ---------------------------------------------------------------- rows */

/** Joined restaurant (computed by BE). */
export interface AdRestaurant {
  id: string;
  name: string;
  address: string;
  isVeganCertified: boolean;
  latitude: number | null;
  longitude: number | null;
}

export interface AdCampaign {
  id: string;
  restaurantId: string;
  restaurant: AdRestaurant;
  headline: string;
  message: string;
  ctaType: AdCtaType;
  targetCity: string | null;
  startAt: ISODateString;
  endAt: ISODateString;
  isPaused: boolean;
  /** Computed by BE (see deriveAdStatus). */
  status: AdStatus;
  /** VND. */
  budget: number;
  spent: number;
  impressions: number;
  clicks: number;
  createdAt: ISODateString;
  updatedAt: ISODateString;
}

export interface AdQuery {
  status: AdStatus | "all";
  /** A value of AD_CITIES, "national" (targetCity null) or "all". */
  city: string;
  /** Headline, message or restaurant name. */
  search: string;
}

/** POST /admin/ads, and PATCH /admin/ads/{id} with any subset. */
export interface AdInput {
  restaurantId: string;
  headline: string;
  message: string;
  ctaType: AdCtaType;
  targetCity: string | null;
  startAt: ISODateString;
  endAt: ISODateString;
  budget: number;
}

/**
 * GET /ads/feed?city=&lat=&lng=&limit= (public, guests allowed) — what the mobile feed renders
 * as a "Được tài trợ" card. Only Running campaigns whose targetCity is null or equals `city`
 * (case / diacritic-insensitive). With lat/lng the server adds `distanceKm` and sorts nearest first.
 */
export interface AdFeedItem {
  id: string;
  restaurantId: string;
  restaurant: AdRestaurant & { averageRating: number | null; reviewCount: number };
  headline: string;
  message: string;
  ctaType: AdCtaType;
  ctaLabel: string;
  targetCity: string | null;
  startAt: ISODateString;
  endAt: ISODateString;
  /** null without lat/lng or when the restaurant has no coordinates. */
  distanceKm: number | null;
}

/**
 * Status rule (BE source of truth, mirrored by the mock and the optimistic updates):
 * Ended after end_at or once spent ≥ budget; otherwise Paused when is_paused; Scheduled before start_at; else Running.
 */
export function deriveAdStatus(c: Pick<AdCampaign, "startAt" | "endAt" | "isPaused" | "budget" | "spent">, now = Date.now()): AdStatus {
  if (Date.parse(c.endAt) < now || c.spent >= c.budget) return "Ended";
  if (c.isPaused) return "Paused";
  if (Date.parse(c.startAt) > now) return "Scheduled";
  return "Running";
}

/** Click-through rate, 0 when there is no impression yet. */
export const adCtr = (c: Pick<AdCampaign, "impressions" | "clicks">) => (c.impressions > 0 ? c.clicks / c.impressions : 0);

const vnd = new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND", maximumFractionDigits: 0 });

export type AdInputErrors = Partial<Record<keyof AdInput, string>>;

/**
 * Field errors for a create / edit (empty object = valid). Same rules as the server (400 `validation`).
 * `spent` is the campaign's spend so far when editing; `isNew` also rejects an end date in the past.
 */
export function adInputErrors(input: AdInput, opts: { isNew: boolean; spent?: number; now?: number }): AdInputErrors {
  const errors: AdInputErrors = {};
  const now = opts.now ?? Date.now();
  const headline = input.headline.trim();
  const message = input.message.trim();
  if (!input.restaurantId) errors.restaurantId = "Chọn quán được quảng cáo.";
  if (headline.length < AD_HEADLINE_MIN || headline.length > AD_HEADLINE_MAX) {
    errors.headline = `Tiêu đề ${AD_HEADLINE_MIN}–${AD_HEADLINE_MAX} ký tự.`;
  }
  if (message.length < AD_MESSAGE_MIN || message.length > AD_MESSAGE_MAX) {
    errors.message = `Nội dung ${AD_MESSAGE_MIN}–${AD_MESSAGE_MAX} ký tự.`;
  }
  if (!(AD_CTA_TYPES as readonly string[]).includes(input.ctaType)) errors.ctaType = "Chọn nút hành động.";
  if (input.targetCity !== null && !(AD_CITIES as readonly string[]).includes(input.targetCity)) errors.targetCity = "Thành phố không hợp lệ.";
  const start = Date.parse(input.startAt);
  const end = Date.parse(input.endAt);
  if (!Number.isFinite(start)) errors.startAt = "Chọn ngày bắt đầu.";
  if (!Number.isFinite(end)) errors.endAt = "Chọn ngày kết thúc.";
  else if (Number.isFinite(start) && end <= start) errors.endAt = "Ngày kết thúc phải sau ngày bắt đầu.";
  else if (opts.isNew && end < now) errors.endAt = "Ngày kết thúc đã qua.";
  if (!Number.isInteger(input.budget) || input.budget < AD_MIN_BUDGET) {
    errors.budget = `Ngân sách tối thiểu ${vnd.format(AD_MIN_BUDGET)}.`;
  } else if (opts.spent !== undefined && input.budget < opts.spent) {
    errors.budget = `Ngân sách không thấp hơn số đã chi (${vnd.format(opts.spent)}).`;
  }
  return errors;
}
