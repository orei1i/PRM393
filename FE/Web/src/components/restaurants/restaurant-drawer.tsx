// src/components/restaurants/restaurant-drawer.tsx
"use client";

import * as React from "react";
import { ExternalLink, MessageSquareText, Star, Trash2 } from "lucide-react";
import { toast } from "sonner";

import { ErrorState } from "@/components/admin/states";
import { InitialsAvatar } from "@/components/admin/initials-avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogTitle } from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/form-controls";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { describeError } from "@/lib/api_error";
import { useDeleteRestaurant, useDeleteReview, useRestaurantReviews } from "@/lib/hooks/use-restaurants";
import { cn } from "@/lib/utils";
import { RESTAURANT_SOURCE_LABEL, type AdminRestaurant, type AdminReview } from "@/types/restaurants";

import { CertifiedBadge, CertifiedSwitch, formatRating, hasCoords, RatingSummary } from "./restaurant-table";

const dateVi = new Intl.DateTimeFormat("vi-VN", { day: "2-digit", month: "2-digit", year: "numeric" });

/** Google Maps search link: coordinates when known, otherwise the address. */
export function mapsUrl(r: Pick<AdminRestaurant, "latitude" | "longitude" | "address" | "name">) {
  const query = hasCoords(r) ? `${r.latitude},${r.longitude}` : `${r.name}, ${r.address}`;
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(query)}`;
}

export function RestaurantDrawer({
  restaurant,
  onOpenChange,
}: {
  restaurant: AdminRestaurant | null;
  onOpenChange: (open: boolean) => void;
}) {
  return (
    <Sheet open={restaurant !== null} onOpenChange={onOpenChange}>
      <SheetContent className="gap-0 overflow-y-auto sm:max-w-lg">
        {restaurant && <Detail key={restaurant.id} restaurant={restaurant} onClose={() => onOpenChange(false)} />}
      </SheetContent>
    </Sheet>
  );
}

function Stars({ rating }: { rating: number }) {
  return (
    <span className="inline-flex items-center gap-0.5" role="img" aria-label={`${rating} trên 5 sao`}>
      {Array.from({ length: 5 }, (_, i) => (
        <Star key={i} className={cn("size-3.5", i < rating ? "fill-current text-ochre" : "text-muted-foreground/50")} aria-hidden />
      ))}
    </span>
  );
}

function Detail({ restaurant, onClose }: { restaurant: AdminRestaurant; onClose: () => void }) {
  const reviews = useRestaurantReviews(restaurant.id);
  const removeReview = useDeleteReview();
  const removeRestaurant = useDeleteRestaurant();
  const [reviewTarget, setReviewTarget] = React.useState<AdminReview | null>(null);
  const [reviewDialogOpen, setReviewDialogOpen] = React.useState(false);
  const [restaurantDialogOpen, setRestaurantDialogOpen] = React.useState(false);
  const headingId = React.useId();

  function confirmDeleteReview(review: AdminReview) {
    setReviewTarget(review);
    setReviewDialogOpen(true);
  }

  function applyDeleteReview() {
    if (!reviewTarget) return;
    removeReview.mutate(
      { reviewId: reviewTarget.id, restaurantId: restaurant.id },
      {
        onSuccess: () => {
          toast.success("Đã xoá đánh giá", { description: `${reviewTarget.user.fullName} · ${restaurant.name}` });
          setReviewDialogOpen(false);
        },
        onError: (e) => toast.error("Chưa xoá được đánh giá", { description: describeError(e) }),
      },
    );
  }

  function applyDeleteRestaurant() {
    removeRestaurant.mutate(restaurant.id, {
      onSuccess: () => {
        toast.success("Đã xoá quán", { description: restaurant.name });
        setRestaurantDialogOpen(false);
        onClose();
      },
      onError: (e) => toast.error("Chưa xoá được quán", { description: describeError(e) }),
    });
  }

  const reviewCount = reviews.data?.length ?? restaurant.reviewCount;

  return (
    <>
      <SheetHeader className="border-b">
        <div className="flex flex-wrap gap-1.5">
          <CertifiedBadge certified={restaurant.isVeganCertified} />
          <Badge variant="outline">{RESTAURANT_SOURCE_LABEL[restaurant.createdBy ? "user" : "admin"]}</Badge>
        </div>
        <SheetTitle className="mt-2 leading-snug">{restaurant.name}</SheetTitle>
        <SheetDescription>{restaurant.address}</SheetDescription>
      </SheetHeader>

      <div className="flex flex-col gap-6 p-5">
        <dl className="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
          <Info label="Người gợi ý" value={restaurant.createdBy?.fullName ?? "Ban quản trị"} />
          <div className="min-w-0">
            <dt className="text-xs text-muted-foreground">Đánh giá</dt>
            <dd className="font-semibold">
              <RatingSummary restaurant={restaurant} />
            </dd>
          </div>
          <Info
            label="Toạ độ"
            value={hasCoords(restaurant) ? `${restaurant.latitude?.toFixed(4)}, ${restaurant.longitude?.toFixed(4)}` : "Chưa có vị trí"}
            mono={hasCoords(restaurant)}
          />
          <Info label="Mã quán" value={restaurant.id} mono />
        </dl>

        <Button asChild size="sm" variant="outline" className="w-fit">
          <a href={mapsUrl(restaurant)} target="_blank" rel="noopener noreferrer">
            <ExternalLink aria-hidden />
            Mở Google Maps
          </a>
        </Button>

        <section className="flex items-start justify-between gap-4 rounded-lg border p-3">
          <div className="min-w-0">
            <h3 className="text-sm font-bold">Chứng nhận thuần chay</h3>
            <p className="text-xs text-muted-foreground">
              Bật sau khi đã xác minh quán không dùng nguyên liệu động vật. Ứng dụng hiển thị nhãn “Chứng nhận chay” ngay.
            </p>
          </div>
          <CertifiedSwitch restaurant={restaurant} className="mt-0.5" />
        </section>

        <section aria-labelledby={headingId} className="flex flex-col gap-3">
          <h3 id={headingId} className="flex items-center gap-2 text-sm font-bold">
            Đánh giá
            <span className="rounded-full bg-muted px-1.5 font-mono text-[11px] tabular">{reviewCount}</span>
            {restaurant.averageRating !== null && (
              <span className="font-normal text-muted-foreground">· trung bình {formatRating(restaurant.averageRating)}/5</span>
            )}
          </h3>
          {reviews.isError && !reviews.data ? (
            <div className="rounded-lg border">
              <ErrorState error={reviews.error} onRetry={() => reviews.refetch()} title="Chưa tải được đánh giá" />
            </div>
          ) : reviews.isLoading ? (
            <>
              <Skeleton className="h-20" />
              <Skeleton className="h-20" />
              <Skeleton className="h-20" />
            </>
          ) : reviews.data?.length === 0 ? (
            <p className="flex items-center gap-2 rounded-lg bg-muted px-3 py-3 text-sm text-muted-foreground">
              <MessageSquareText className="size-4 shrink-0" aria-hidden />
              Chưa có đánh giá nào cho quán này.
            </p>
          ) : (
            <ul className="flex flex-col gap-2">
              {reviews.data?.map((review) => (
                <li key={review.id} className="flex flex-col gap-2 rounded-lg border p-3 text-sm">
                  <div className="flex items-center gap-2">
                    <InitialsAvatar name={review.user.fullName} className="size-8" />
                    <div className="min-w-0 flex-1">
                      <p className="truncate font-semibold">{review.user.fullName}</p>
                      <p className="flex flex-wrap items-center gap-x-2 text-xs text-muted-foreground">
                        <Stars rating={review.rating} />
                        {dateVi.format(new Date(review.createdAt))}
                      </p>
                    </div>
                  </div>
                  <p className="whitespace-pre-wrap break-words leading-relaxed">{review.comment}</p>
                  <Button
                    size="sm"
                    variant="ghost"
                    className="w-fit text-destructive hover:text-destructive"
                    disabled={removeReview.isPending}
                    onClick={() => confirmDeleteReview(review)}
                  >
                    <Trash2 aria-hidden />
                    Xoá đánh giá
                  </Button>
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="flex flex-col gap-2 rounded-lg border border-destructive/30 p-3">
          <h3 className="text-sm font-bold text-destructive">Xoá quán</h3>
          <p className="text-xs text-muted-foreground">Gỡ quán khỏi ứng dụng cùng toàn bộ đánh giá. Không thể hoàn tác.</p>
          <Button
            size="sm"
            variant="destructive"
            className="w-fit"
            disabled={removeRestaurant.isPending}
            onClick={() => setRestaurantDialogOpen(true)}
          >
            <Trash2 aria-hidden />
            Xoá quán
          </Button>
        </section>
      </div>

      <Dialog open={reviewDialogOpen} onOpenChange={(open) => !removeReview.isPending && setReviewDialogOpen(open)}>
        <DialogContent>
          <DialogTitle>Xoá đánh giá?</DialogTitle>
          <DialogDescription>
            Đánh giá {reviewTarget ? `${reviewTarget.rating}★ của ${reviewTarget.user.fullName}` : ""} sẽ bị xoá; điểm trung bình của quán được tính lại.
          </DialogDescription>
          {reviewTarget && <p className="line-clamp-3 rounded-lg bg-muted px-3 py-2 text-sm">{reviewTarget.comment}</p>}
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" disabled={removeReview.isPending}>
                Huỷ
              </Button>
            </DialogClose>
            <Button variant="destructive" disabled={removeReview.isPending} onClick={applyDeleteReview}>
              {removeReview.isPending ? "Đang xoá…" : "Xoá đánh giá"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={restaurantDialogOpen} onOpenChange={(open) => !removeRestaurant.isPending && setRestaurantDialogOpen(open)}>
        <DialogContent>
          <DialogTitle>Xoá quán và toàn bộ {reviewCount} đánh giá?</DialogTitle>
          <DialogDescription>“{restaurant.name}” sẽ biến mất khỏi ứng dụng, kể cả trong kết quả tìm kiếm và gợi ý quán.</DialogDescription>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" disabled={removeRestaurant.isPending}>
                Huỷ
              </Button>
            </DialogClose>
            <Button variant="destructive" disabled={removeRestaurant.isPending} onClick={applyDeleteRestaurant}>
              {removeRestaurant.isPending ? "Đang xoá…" : "Xoá quán"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

function Info({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="min-w-0">
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className={cn("break-words font-semibold", mono && "font-mono")}>{value}</dd>
    </div>
  );
}
