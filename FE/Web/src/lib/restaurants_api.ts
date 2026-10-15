// src/lib/restaurants_api.ts
// Vegan restaurants submitted from the app or added by admins, their certification
// flag and reviews. Remote rows are normalised: INT ids → strings, `createdBy` as an
// id (+ `createdByName`) or a nested user, nullable coordinates.
import type { AdminRestaurant, AdminReview, RestaurantPerson, RestaurantQuery } from "@/types/restaurants";

import { qs, request, USE_MOCK_DATA } from "./api_client";
import { readSession } from "./auth";
import { readId } from "./ids";
import * as mock from "./mock_restaurants";

type Raw = Record<string, unknown>;
const obj = (raw: unknown): Raw | null => (raw && typeof raw === "object" && !Array.isArray(raw) ? (raw as Raw) : null);

const optNumber = (raw: unknown) => {
  if (raw === null || raw === undefined || raw === "") return null;
  const n = typeof raw === "number" ? raw : Number(raw);
  return Number.isFinite(n) ? n : null;
};

function readPerson(raw: unknown, fallbackName?: unknown): RestaurantPerson | null {
  const nested = obj(raw);
  if (nested) return { id: readId(nested.id), fullName: String(nested.fullName ?? nested.name ?? "Người dùng") };
  if (raw === null || raw === undefined || raw === "") return null;
  return { id: readId(raw), fullName: typeof fallbackName === "string" && fallbackName ? fallbackName : `Người dùng #${readId(raw)}` };
}

export function normalizeRestaurant(raw: Raw): AdminRestaurant {
  const reviewCount = optNumber(raw.reviewCount) ?? 0;
  return {
    id: readId(raw.id),
    name: String(raw.name ?? ""),
    address: String(raw.address ?? ""),
    isVeganCertified: raw.isVeganCertified === true,
    createdBy: readPerson(raw.createdBy, raw.createdByName),
    latitude: optNumber(raw.latitude),
    longitude: optNumber(raw.longitude),
    averageRating: reviewCount > 0 ? optNumber(raw.averageRating) : null,
    reviewCount,
  };
}

export function normalizeReview(raw: Raw, restaurantId = ""): AdminReview {
  return {
    id: readId(raw.id),
    restaurantId: readId(raw.restaurantId ?? restaurantId),
    user: readPerson(raw.user ?? raw.userId, raw.userName) ?? { id: "", fullName: "Người dùng" },
    rating: Math.min(5, Math.max(1, Math.round(optNumber(raw.rating) ?? 0))),
    comment: String(raw.comment ?? raw.content ?? ""),
    createdAt: typeof raw.createdAt === "string" ? raw.createdAt : new Date(0).toISOString(),
  };
}

export const restaurantsApi = {
  /** GET /admin/restaurants?certified=&source=&search= */
  async list(query: RestaurantQuery): Promise<AdminRestaurant[]> {
    if (USE_MOCK_DATA) return mock.listRestaurants(query);
    const raw = await request<Raw[]>(
      `/admin/restaurants?${qs({
        certified: query.certified === "all" ? undefined : query.certified,
        source: query.source === "all" ? undefined : query.source,
        search: query.search,
      })}`,
    );
    return raw.map(normalizeRestaurant);
  },

  /** PATCH /admin/restaurants/{id} { isVeganCertified } */
  async setCertified(id: string, isVeganCertified: boolean): Promise<AdminRestaurant> {
    if (USE_MOCK_DATA) return mock.setCertified(id, isVeganCertified, readSession());
    return normalizeRestaurant(
      await request<Raw>(`/admin/restaurants/${encodeURIComponent(id)}`, {
        method: "PATCH",
        body: JSON.stringify({ isVeganCertified }),
      }),
    );
  },

  /** DELETE /admin/restaurants/{id} — removes its reviews too. */
  async remove(id: string): Promise<void> {
    if (USE_MOCK_DATA) return mock.deleteRestaurant(id, readSession());
    await request<unknown>(`/admin/restaurants/${encodeURIComponent(id)}`, { method: "DELETE" });
  },

  /** GET /admin/restaurants/{id}/reviews — newest first. */
  async reviews(restaurantId: string): Promise<AdminReview[]> {
    if (USE_MOCK_DATA) return mock.listReviews(restaurantId);
    const raw = await request<Raw[]>(`/admin/restaurants/${encodeURIComponent(restaurantId)}/reviews`);
    return raw.map((r) => normalizeReview(r, restaurantId)).sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  },

  /** DELETE /admin/reviews/{id} */
  async removeReview(id: string): Promise<void> {
    if (USE_MOCK_DATA) return mock.deleteReview(id, readSession());
    await request<unknown>(`/admin/reviews/${encodeURIComponent(id)}`, { method: "DELETE" });
  },
};
