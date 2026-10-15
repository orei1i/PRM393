// src/lib/hooks/use-restaurants.ts
"use client";

import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import type { AdminRestaurant, AdminReview, RestaurantQuery } from "@/types/restaurants";

import { restaurantsApi } from "../restaurants_api";

export const restaurantKeys = {
  all: ["restaurants"] as const,
  lists: ["restaurants", "list"] as const,
  list: (q: RestaurantQuery) => ["restaurants", "list", q] as const,
  reviews: (id: string) => ["restaurants", "reviews", id] as const,
};

export function useRestaurants(query: RestaurantQuery) {
  return useQuery({
    queryKey: restaurantKeys.list(query),
    queryFn: () => restaurantsApi.list(query),
    placeholderData: keepPreviousData,
  });
}

export function useRestaurantReviews(id: string) {
  return useQuery({ queryKey: restaurantKeys.reviews(id), queryFn: () => restaurantsApi.reviews(id) });
}

/**
 * Inline certification switch. The row flips at once and stays in its tab until the
 * refetch moves it; on error every cached list is restored.
 */
export function useSetRestaurantCertified() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, isVeganCertified }: { id: string; isVeganCertified: boolean }) => restaurantsApi.setCertified(id, isVeganCertified),
    onMutate: async ({ id, isVeganCertified }) => {
      await qc.cancelQueries({ queryKey: restaurantKeys.lists });
      const snapshots = qc.getQueriesData<AdminRestaurant[]>({ queryKey: restaurantKeys.lists });
      qc.setQueriesData<AdminRestaurant[]>({ queryKey: restaurantKeys.lists }, (old) =>
        old?.map((r) => (r.id === id ? { ...r, isVeganCertified } : r)),
      );
      return { snapshots };
    },
    onError: (_e, _v, context) => {
      context?.snapshots.forEach(([key, data]) => qc.setQueryData(key, data));
    },
    onSuccess: (restaurant) => {
      qc.setQueriesData<AdminRestaurant[]>({ queryKey: restaurantKeys.lists }, (old) =>
        old?.map((r) => (r.id === restaurant.id ? restaurant : r)),
      );
    },
    onSettled: () => qc.invalidateQueries({ queryKey: restaurantKeys.lists }),
  });
}

export function useDeleteRestaurant() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => restaurantsApi.remove(id),
    onMutate: async (id) => {
      await qc.cancelQueries({ queryKey: restaurantKeys.lists });
      const snapshots = qc.getQueriesData<AdminRestaurant[]>({ queryKey: restaurantKeys.lists });
      qc.setQueriesData<AdminRestaurant[]>({ queryKey: restaurantKeys.lists }, (old) => old?.filter((r) => r.id !== id));
      return { snapshots };
    },
    onError: (_e, _v, context) => {
      context?.snapshots.forEach(([key, data]) => qc.setQueryData(key, data));
    },
    onSuccess: (_void, id) => qc.removeQueries({ queryKey: restaurantKeys.reviews(id) }),
    onSettled: () => {
      qc.invalidateQueries({ queryKey: restaurantKeys.lists });
      qc.invalidateQueries({ queryKey: ["overview"] });
    },
  });
}

/** Drops the review and recomputes the restaurant's average and count in every cached list. */
export function useDeleteReview() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ reviewId }: { reviewId: string; restaurantId: string }) => restaurantsApi.removeReview(reviewId),
    onMutate: async ({ reviewId, restaurantId }) => {
      await qc.cancelQueries({ queryKey: restaurantKeys.all });
      const reviewsKey = restaurantKeys.reviews(restaurantId);
      const previousReviews = qc.getQueryData<AdminReview[]>(reviewsKey);
      const lists = qc.getQueriesData<AdminRestaurant[]>({ queryKey: restaurantKeys.lists });
      if (previousReviews) {
        const remaining = previousReviews.filter((r) => r.id !== reviewId);
        qc.setQueryData<AdminReview[]>(reviewsKey, remaining);
        const averageRating = remaining.length ? remaining.reduce((s, r) => s + r.rating, 0) / remaining.length : null;
        qc.setQueriesData<AdminRestaurant[]>({ queryKey: restaurantKeys.lists }, (old) =>
          old?.map((r) => (r.id === restaurantId ? { ...r, averageRating, reviewCount: remaining.length } : r)),
        );
      }
      return { previousReviews, lists };
    },
    onError: (_e, { restaurantId }, context) => {
      if (context?.previousReviews) qc.setQueryData(restaurantKeys.reviews(restaurantId), context.previousReviews);
      context?.lists.forEach(([key, data]) => qc.setQueryData(key, data));
    },
    onSettled: (_d, _e, { restaurantId }) => {
      qc.invalidateQueries({ queryKey: restaurantKeys.reviews(restaurantId) });
      qc.invalidateQueries({ queryKey: restaurantKeys.lists });
    },
  });
}
