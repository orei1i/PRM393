// src/types/restaurants.ts
// Vegan restaurants (restaurants + proposed latitude/longitude) and their reviews.
import type { ISODateString } from "./moderation";

export interface RestaurantPerson {
  id: string;
  fullName: string;
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
