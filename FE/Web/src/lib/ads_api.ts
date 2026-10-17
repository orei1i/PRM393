// src/lib/ads_api.ts
// Store ads for /ads: one "Được tài trợ" restaurant row at the top of the mobile
// "Quán chay gần bạn" list (placement "nearby"; no longer in the feed or post detail).
// Remote rows are normalised: INT ids → strings, enum values matched case-insensitively,
// restaurant nested or flat (restaurantName / restaurantAddress), nullable coordinates.
//
// | Method | Path                          | Body / notes                                              |
// |--------|-------------------------------|-----------------------------------------------------------|
// | GET    | /admin/ads?status=&city=&search= | AdCampaign[] (city: a city, "national" = toàn quốc)    |
// | POST   | /admin/ads                    | AdInput → AdCampaign (400 validation, see adInputErrors)  |
// | PATCH  | /admin/ads/{id}               | Partial<AdInput> → AdCampaign (budget ≥ spent)            |
// | POST   | /admin/ads/{id}/pause         | → AdCampaign                                              |
// | POST   | /admin/ads/{id}/resume        | → AdCampaign (409 `ended` once ended)                     |
// | DELETE | /admin/ads/{id}               | 204                                                       |
// | GET    | /ads/feed?placement=nearby&city=&lat=&lng=&limit=1 | Public (guests allowed), called by "Quán chay gần bạn" → AdFeedItem[] |
// | POST   | /ads/{id}/impression · /click | The app reports the first display / a tap (feeds impressions, clicks, spent) |
//
// GET /ads/feed returns only Running campaigns of `placement` (default nearby) whose targetCity is
// null or matches `city` (case / diacritic-insensitive), nearest first when lat/lng are sent,
// `limit` default 1:
// [{ "id": 12, "restaurantId": 7, "placement": "nearby",
//    "restaurant": { "id": 7, "name": "Bún Riêu Chay Hạnh Tâm", "address": "152 Đinh Tiên Hoàng, …",
//                    "isVeganCertified": true, "latitude": 10.8003, "longitude": 106.6977,
//                    "averageRating": 4.75, "reviewCount": 4 },
//    "headline": "Bún riêu chay 35k — riêu đậu hũ mềm", "message": "Tô đầy đặn, …",
//    "ctaType": "ViewStore", "ctaLabel": "Xem quán", "targetCity": "TP. Hồ Chí Minh",
//    "startAt": "2026-10-04T17:00:00Z", "endAt": "2026-11-04T16:59:59.999Z", "distanceKm": 2.6 }]
import type { AdCampaign, AdCtaType, AdFeedItem, AdInput, AdPlacement, AdQuery, AdRestaurant, AdStatus } from "@/types/ads";
import { AD_CTA_LABEL, AD_CTA_TYPES, AD_NEARBY_LIMIT, AD_PLACEMENTS, AD_STATUSES, deriveAdStatus } from "@/types/ads";

import { qs, request, USE_MOCK_DATA } from "./api_client";
import { readSession } from "./auth";
import { apiId, readId } from "./ids";
import * as mock from "./mock_ads";

type Raw = Record<string, unknown>;
const obj = (raw: unknown): Raw | null => (raw && typeof raw === "object" && !Array.isArray(raw) ? (raw as Raw) : null);

/** Case-insensitive, ignores spaces and underscores; unknown → fallback. */
function pick<T extends string>(values: readonly T[], raw: unknown, fallback: T): T {
  if (typeof raw !== "string") return fallback;
  const key = (s: string) => s.replace(/[\s_]/g, "").toLowerCase();
  return values.find((v) => key(v) === key(raw)) ?? fallback;
}

const num = (raw: unknown, fallback = 0) => {
  const n = typeof raw === "number" ? raw : typeof raw === "string" ? Number(raw) : NaN;
  return Number.isFinite(n) ? n : fallback;
};
const optNumber = (raw: unknown) => (raw === null || raw === undefined || raw === "" ? null : Number.isFinite(Number(raw)) ? Number(raw) : null);
const isoOr = (raw: unknown) => (typeof raw === "string" && raw ? raw : new Date(0).toISOString());

function readRestaurant(raw: Raw): AdRestaurant {
  const r = obj(raw.restaurant) ?? {};
  return {
    id: readId(r.id ?? raw.restaurantId),
    name: String(r.name ?? raw.restaurantName ?? ""),
    address: String(r.address ?? raw.restaurantAddress ?? ""),
    isVeganCertified: (r.isVeganCertified ?? raw.isVeganCertified) === true,
    latitude: optNumber(r.latitude),
    longitude: optNumber(r.longitude),
  };
}

export function normalizeAd(raw: Raw): AdCampaign {
  const base = {
    id: readId(raw.id),
    restaurantId: readId(raw.restaurantId ?? obj(raw.restaurant)?.id),
    restaurant: readRestaurant(raw),
    placement: pick<AdPlacement>(AD_PLACEMENTS, raw.placement, "nearby"),
    headline: String(raw.headline ?? ""),
    message: String(raw.message ?? ""),
    ctaType: pick<AdCtaType>(AD_CTA_TYPES, raw.ctaType, "ViewStore"),
    targetCity: typeof raw.targetCity === "string" && raw.targetCity ? raw.targetCity : null,
    startAt: isoOr(raw.startAt),
    endAt: isoOr(raw.endAt),
    isPaused: raw.isPaused === true,
    budget: num(raw.budget),
    spent: num(raw.spent),
    impressions: num(raw.impressions),
    clicks: num(raw.clicks),
    createdAt: isoOr(raw.createdAt),
    updatedAt: isoOr(raw.updatedAt ?? raw.createdAt),
  };
  // Trust the server's status when present; derive it otherwise.
  const status = typeof raw.status === "string" ? pick<AdStatus>(AD_STATUSES, raw.status, deriveAdStatus(base)) : deriveAdStatus(base);
  return { ...base, status };
}

export function normalizeAdFeedItem(raw: Raw): AdFeedItem {
  const r = obj(raw.restaurant) ?? {};
  const ctaType = pick<AdCtaType>(AD_CTA_TYPES, raw.ctaType, "ViewStore");
  return {
    id: readId(raw.id),
    restaurantId: readId(raw.restaurantId ?? r.id),
    placement: pick<AdPlacement>(AD_PLACEMENTS, raw.placement, "nearby"),
    restaurant: { ...readRestaurant(raw), averageRating: optNumber(r.averageRating), reviewCount: num(r.reviewCount) },
    headline: String(raw.headline ?? ""),
    message: String(raw.message ?? ""),
    ctaType,
    ctaLabel: typeof raw.ctaLabel === "string" && raw.ctaLabel ? raw.ctaLabel : AD_CTA_LABEL[ctaType],
    targetCity: typeof raw.targetCity === "string" && raw.targetCity ? raw.targetCity : null,
    startAt: isoOr(raw.startAt),
    endAt: isoOr(raw.endAt),
    distanceKm: optNumber(raw.distanceKm),
  };
}

/** Request body: numeric restaurant ids go out as JSON numbers (plan D3). */
function body(input: Partial<AdInput>) {
  return JSON.stringify(input.restaurantId === undefined ? input : { ...input, restaurantId: apiId(input.restaurantId) });
}

export const adsApi = {
  /** GET /admin/ads?status=&city=&search= */
  async list(query: AdQuery): Promise<AdCampaign[]> {
    if (USE_MOCK_DATA) return mock.listAds(query);
    const raw = await request<Raw[]>(
      `/admin/ads?${qs({
        status: query.status === "all" ? undefined : query.status,
        city: query.city === "all" ? undefined : query.city,
        search: query.search,
      })}`,
    );
    return raw.map(normalizeAd);
  },

  /** POST /admin/ads */
  async create(input: AdInput): Promise<AdCampaign> {
    if (USE_MOCK_DATA) return mock.createAd(input, readSession());
    return normalizeAd(await request<Raw>("/admin/ads", { method: "POST", body: body(input) }));
  },

  /** PATCH /admin/ads/{id} */
  async update(id: string, patch: Partial<AdInput>): Promise<AdCampaign> {
    if (USE_MOCK_DATA) return mock.updateAd(id, patch, readSession());
    return normalizeAd(await request<Raw>(`/admin/ads/${encodeURIComponent(id)}`, { method: "PATCH", body: body(patch) }));
  },

  /** POST /admin/ads/{id}/pause | /resume */
  async setPaused(id: string, paused: boolean): Promise<AdCampaign> {
    if (USE_MOCK_DATA) return mock.setAdPaused(id, paused, readSession());
    return normalizeAd(await request<Raw>(`/admin/ads/${encodeURIComponent(id)}/${paused ? "pause" : "resume"}`, { method: "POST" }));
  },

  /** DELETE /admin/ads/{id} */
  async remove(id: string): Promise<void> {
    if (USE_MOCK_DATA) return mock.deleteAd(id, readSession());
    await request<unknown>(`/admin/ads/${encodeURIComponent(id)}`, { method: "DELETE" });
  },

  /** GET /ads/feed?placement=nearby&city=&lat=&lng=&limit=1 — the public endpoint the app calls (documented here; the console does not use it). */
  async feed(
    city: string | null,
    coords: { lat: number; lng: number } | null = null,
    limit = AD_NEARBY_LIMIT,
    placement: AdPlacement = "nearby",
  ): Promise<AdFeedItem[]> {
    if (USE_MOCK_DATA) return mock.getFeed(city, coords, limit, placement);
    const raw = await request<Raw[]>(`/ads/feed?${qs({ placement, city: city ?? undefined, lat: coords?.lat, lng: coords?.lng, limit })}`);
    return raw.map(normalizeAdFeedItem);
  },
};
