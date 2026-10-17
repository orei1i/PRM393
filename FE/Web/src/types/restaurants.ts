// src/types/restaurants.ts
// Vegan restaurants (restaurants + proposed latitude/longitude), their photos / videos
// (proposed table restaurant_media) and reviews.
//
// ┌ For the BE team: restaurant_media  id, restaurant_id (FK), media_type (Image | Video), media_url,
// │ uploaded_by (FK users), created_at. The app sends POST /restaurants { name, address, latitude,
// └ longitude, media: [{ mediaType, mediaUrl }] } (≤ 5 images + 1 video) and reads GET /restaurants/{id}/media.
import type { ISODateString } from "./moderation";

export interface RestaurantPerson {
  id: string;
  fullName: string;
}

export type RestaurantMediaType = "Image" | "Video";

export interface RestaurantMedia {
  id: string;
  mediaType: RestaurantMediaType;
  mediaUrl: string;
  /** Computed by BE (join users); null = admin team. */
  uploadedBy: RestaurantPerson | null;
  createdAt: ISODateString;
}

export interface AdminRestaurant {
  id: string;
  name: string;
  address: string;
  isVeganCertified: boolean;
  /** restaurants.created_by joined with users; null = added by the admin team. */
  createdBy: RestaurantPerson | null;
  /** Proposed columns (nullable): user submissions often have no coordinates. */
  latitude: number | null;
  longitude: number | null;
  /** Computed by BE from reviews; null when there is no review. */
  averageRating: number | null;
  reviewCount: number;
  /** restaurant_media, oldest first (photos and at most one video from the "Gợi ý quán mới" form). */
  media: RestaurantMedia[];
}

export type RestaurantCertifiedFilter = "all" | "certified" | "uncertified";
export type RestaurantSource = "all" | "user" | "admin";

export interface RestaurantQuery {
  certified: RestaurantCertifiedFilter;
  /** "user" = suggested from the app (created_by set), "admin" = added by the admin team. */
  source: RestaurantSource;
  /** Name or address. */
  search: string;
}

export const RESTAURANT_SOURCE_LABEL: Record<Exclude<RestaurantSource, "all">, string> = {
  user: "Người dùng gợi ý",
  admin: "Ban quản trị",
};

export interface AdminReview {
  id: string;
  restaurantId: string;
  user: RestaurantPerson;
  /** 1..5 */
  rating: number;
  comment: string;
  createdAt: ISODateString;
}
