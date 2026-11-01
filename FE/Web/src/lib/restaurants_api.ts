// src/lib/restaurants_api.ts
// Vegan restaurants submitted from the app or added by admins, their approval status,
// certification flag and reviews. Remote rows are normalised: INT ids → strings, `createdBy` as an
// id (+ `createdByName`) or a nested user, nullable coordinates. A row with no status reads as
// Approved (existing rows do, per the contract with the mobile app).
//
// | Method | Path                            | Body / notes                                                  |
// |--------|---------------------------------|---------------------------------------------------------------|
// | GET    | /admin/restaurants              | ?status=Pending|Approved|Rejected&certified=&source=&search=  |
// | POST   | /admin/restaurants/{id}/review  | { decision: Approve|Reject, reason? } → row; reason required  |
// |        |                                 | for Reject, ≤ 500 chars (400). Re-deciding allowed. 404, 403. |
// | PATCH  | /admin/restaurants/{id}         | { isVeganCertified } → row; 409 not_approved unless Approved  |
// | DELETE | /admin/restaurants/{id}         | removes its reviews too                                       |
// | GET    | /admin/restaurants/{id}/reviews | newest first                                                  |
// | DELETE | /admin/reviews/{id}             |                                                               |
import type {
  AdminRestaurant,
  AdminReview,
  RestaurantMedia,
  RestaurantPerson,
  RestaurantQuery,
  RestaurantReviewInput,
  RestaurantStatus,
} from "@/types/restaurants";
import { RESTAURANT_STATUSES } from "@/types/restaurants";

import { qs, request, requestList, requestObject } from "./api_client";
import { isMock } from "./backend_modules";
import { readSession } from "./auth";
import { readId } from "./ids";
import * as mock from "./mock_restaurants";
import { hasId, isoOr, obj, objects, optIso, optNum as optNumber, optText, text, type Raw } from "./wire";

function readPerson(raw: unknown, fallbackName?: unknown): RestaurantPerson | null {
  const nested = obj(raw);
  if (nested) return { id: readId(nested.id), fullName: text(nested.fullName ?? nested.name, "Người dùng") };
  if (raw === null || raw === undefined || raw === "") return null;
  return { id: readId(raw), fullName: typeof fallbackName === "string" && fallbackName ? fallbackName : `Người dùng #${readId(raw)}` };
}

function normalizeMedia(raw: Raw): RestaurantMedia {
  return {
    id: readId(raw.id),
    mediaType: typeof raw.mediaType === "string" && raw.mediaType.toLowerCase() === "video" ? "Video" : "Image",
    mediaUrl: text(raw.mediaUrl ?? raw.url),
    uploadedBy: readPerson(raw.uploadedBy, raw.uploadedByName),
    createdAt: isoOr(raw.createdAt),
  };
}

const readStatus = (raw: unknown): RestaurantStatus =>
  typeof raw === "string" ? (RESTAURANT_STATUSES.find((s) => s.toLowerCase() === raw.toLowerCase()) ?? "Approved") : "Approved";

export function normalizeRestaurant(raw: Raw): AdminRestaurant {
  const reviewCount = optNumber(raw.reviewCount) ?? 0;
  return {
    id: readId(raw.id),
    name: text(raw.name),
    address: text(raw.address),
    status: readStatus(raw.status),
    rejectionReason: optText(raw.rejectionReason),
    createdAt: isoOr(raw.createdAt),
    reviewedAt: optIso(raw.reviewedAt),
    reviewedBy: optText(raw.reviewedBy) ?? optText(obj(raw.reviewedBy)?.fullName),
    isVeganCertified: raw.isVeganCertified === true,
    createdBy: readPerson(raw.createdBy, raw.createdByName),
    latitude: optNumber(raw.latitude),
    longitude: optNumber(raw.longitude),
    averageRating: reviewCount > 0 ? optNumber(raw.averageRating) : null,
    reviewCount,
    media: objects(raw.media)
      .map(normalizeMedia)
      .filter((m) => m.mediaUrl !== ""),
  };
}

export function normalizeReview(raw: Raw, restaurantId = ""): AdminReview {
  return {
    id: readId(raw.id),
    restaurantId: readId(raw.restaurantId ?? restaurantId),
    user: readPerson(raw.user ?? raw.userId, raw.userName) ?? { id: "", fullName: "Người dùng" },
    rating: Math.min(5, Math.max(1, Math.round(optNumber(raw.rating) ?? 0))),
    comment: text(raw.comment ?? raw.content),
    createdAt: isoOr(raw.createdAt),
  };
}

export const restaurantsApi = {
  /** GET /admin/restaurants?status=&certified=&source=&search= */
  async list(query: RestaurantQuery): Promise<AdminRestaurant[]> {
    if (isMock("restaurants")) return mock.listRestaurants(query);
    const raw = await requestList(
      `/admin/restaurants?${qs({
        status: query.status === "all" ? undefined : query.status,
        certified: query.certified === "all" ? undefined : query.certified,
        source: query.source === "all" ? undefined : query.source,
        search: query.search,
      })}`,
    );
    return raw.map(normalizeRestaurant).filter(hasId);
  },

  /** POST /admin/restaurants/{id}/review { decision, reason? } */
  async review(input: RestaurantReviewInput): Promise<AdminRestaurant> {
    if (isMock("restaurants")) return mock.reviewRestaurant(input, readSession());
    return normalizeRestaurant(
      await requestObject(`/admin/restaurants/${encodeURIComponent(input.id)}/review`, {
        method: "POST",
        body: JSON.stringify({ decision: input.decision, reason: input.decision === "Reject" ? input.reason : undefined }),
      }),
    );
  },

  /** PATCH /admin/restaurants/{id} { isVeganCertified } — 409 unless Approved. */
  async setCertified(id: string, isVeganCertified: boolean): Promise<AdminRestaurant> {
    if (isMock("restaurants")) return mock.setCertified(id, isVeganCertified, readSession());
    return normalizeRestaurant(
      await requestObject(`/admin/restaurants/${encodeURIComponent(id)}`, {
        method: "PATCH",
        body: JSON.stringify({ isVeganCertified }),
      }),
    );
  },

  /** DELETE /admin/restaurants/{id} — removes its reviews too. */
  async remove(id: string): Promise<void> {
    if (isMock("restaurants")) return mock.deleteRestaurant(id, readSession());
    await request<unknown>(`/admin/restaurants/${encodeURIComponent(id)}`, { method: "DELETE" });
  },

  /** GET /admin/restaurants/{id}/reviews — newest first. */
  async reviews(restaurantId: string): Promise<AdminReview[]> {
    if (isMock("restaurants")) return mock.listReviews(restaurantId);
    const raw = await requestList(`/admin/restaurants/${encodeURIComponent(restaurantId)}/reviews`);
    return raw.map((r) => normalizeReview(r, restaurantId)).filter(hasId).sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  },

  /** DELETE /admin/reviews/{id} */
  async removeReview(id: string): Promise<void> {
    if (isMock("restaurants")) return mock.deleteReview(id, readSession());
    await request<unknown>(`/admin/reviews/${encodeURIComponent(id)}`, { method: "DELETE" });
  },
};
