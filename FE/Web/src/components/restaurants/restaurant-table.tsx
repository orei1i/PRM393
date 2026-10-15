// src/components/restaurants/restaurant-table.tsx
"use client";

import { Hourglass, MapPin, ShieldCheck, Star, UserRound } from "lucide-react";
import { toast } from "sonner";

import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/form-controls";
import { Switch } from "@/components/ui/switch";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { describeError } from "@/lib/api_error";
import { useSetRestaurantCertified } from "@/lib/hooks/use-restaurants";
import { cn } from "@/lib/utils";
import type { AdminRestaurant } from "@/types/restaurants";

const ratingVi = new Intl.NumberFormat("vi-VN", { minimumFractionDigits: 1, maximumFractionDigits: 1 });

/** 4.625 → "4,6" */
export const formatRating = (value: number) => ratingVi.format(value);

export const hasCoords = (r: Pick<AdminRestaurant, "latitude" | "longitude">) => r.latitude !== null && r.longitude !== null;

export function CertifiedBadge({ certified }: { certified: boolean }) {
  return certified ? (
    <Badge variant="sprout">
      <ShieldCheck aria-hidden />
      Chứng nhận thuần chay
    </Badge>
  ) : (
    <Badge variant="ochre">
      <Hourglass aria-hidden />
      Chưa chứng nhận
    </Badge>
  );
}

export function RatingSummary({ restaurant }: { restaurant: Pick<AdminRestaurant, "averageRating" | "reviewCount"> }) {
  if (restaurant.averageRating === null || restaurant.reviewCount === 0) {
    return <span className="text-muted-foreground">Chưa có</span>;
  }
  return (
    <span className="inline-flex items-center gap-1 whitespace-nowrap">
      <Star className="size-4 fill-current text-ochre" aria-hidden />
      <span className="font-mono font-semibold tabular">{formatRating(restaurant.averageRating)}</span>
      <span className="text-muted-foreground">({restaurant.reviewCount})</span>
      <span className="sr-only">
        điểm trung bình trên 5 từ {restaurant.reviewCount} đánh giá
      </span>
    </span>
  );
}

/** Optimistic certification toggle with toast; reverts (via the hook) on error. */
export function CertifiedSwitch({ restaurant, className }: { restaurant: AdminRestaurant; className?: string }) {
  const certify = useSetRestaurantCertified();
  return (
    <Switch
      checked={restaurant.isVeganCertified}
      disabled={certify.isPending}
      className={className}
      aria-label={
        restaurant.isVeganCertified ? `Bỏ chứng nhận thuần chay của ${restaurant.name}` : `Chứng nhận thuần chay cho ${restaurant.name}`
      }
      onCheckedChange={(isVeganCertified) =>
        certify.mutate(
          { id: restaurant.id, isVeganCertified },
          {
            onSuccess: () =>
              toast.success(isVeganCertified ? "Đã đánh dấu chứng nhận thuần chay" : "Đã bỏ chứng nhận", { description: restaurant.name }),
            onError: (e) => toast.error("Chưa lưu được chứng nhận", { description: describeError(e) }),
          },
        )
      }
    />
  );
}

export function RestaurantTable({
  restaurants,
  isLoading,
  selectedId,
  onSelect,
}: {
  restaurants: AdminRestaurant[] | undefined;
  isLoading: boolean;
  selectedId: string | null;
  onSelect: (restaurant: AdminRestaurant) => void;
}) {
  return (
    <Table className="min-w-[980px]">
      <TableHeader>
        <TableRow className="hover:bg-transparent">
          <TableHead className="w-[22%]">Tên quán</TableHead>
          <TableHead className="w-[30%]">Địa chỉ</TableHead>
          <TableHead>Chứng nhận</TableHead>
          <TableHead>Đánh giá</TableHead>
          <TableHead>Người gợi ý</TableHead>
          <TableHead>Toạ độ</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {isLoading
          ? Array.from({ length: 7 }, (_, i) => (
              <TableRow key={i}>
                <TableCell colSpan={6}>
                  <Skeleton className="h-9" />
                </TableCell>
              </TableRow>
            ))
          : restaurants?.map((r) => (
              <TableRow
                key={r.id}
                data-state={r.id === selectedId ? "selected" : undefined}
                tabIndex={0}
                onClick={() => onSelect(r)}
                onKeyDown={(e) => {
                  if (e.target === e.currentTarget && (e.key === "Enter" || e.key === " ")) {
                    e.preventDefault();
                    onSelect(r);
                  }
                }}
                className="cursor-pointer"
                aria-label={`Mở quán ${r.name}`}
              >
                <TableCell className="whitespace-normal">
                  <span className="line-clamp-2 font-semibold">{r.name}</span>
                </TableCell>
                <TableCell className="whitespace-normal text-muted-foreground">
                  <span className="line-clamp-2">{r.address}</span>
                </TableCell>
                {/* The switch acts on its own; clicks and keys must not open the drawer. */}
                <TableCell onClick={(e) => e.stopPropagation()} onKeyDown={(e) => e.stopPropagation()}>
                  <div className="flex items-center gap-2">
                    <CertifiedSwitch restaurant={r} />
                    <span className={cn("text-xs font-semibold", r.isVeganCertified ? "text-sprout-text" : "text-muted-foreground")}>
                      {r.isVeganCertified ? "Đã chứng nhận" : "Chưa"}
                    </span>
                  </div>
                </TableCell>
                <TableCell>
                  <RatingSummary restaurant={r} />
                </TableCell>
                <TableCell>
                  {r.createdBy ? (
                    <span className="inline-flex max-w-44 items-center gap-1.5">
                      <UserRound className="size-4 shrink-0 text-muted-foreground" aria-hidden />
                      <span className="truncate">{r.createdBy.fullName}</span>
                    </span>
                  ) : (
                    <span className="text-muted-foreground">Ban quản trị</span>
                  )}
                </TableCell>
                <TableCell>
                  {hasCoords(r) ? (
                    <span className="inline-flex items-center gap-1 text-sprout-text">
                      <MapPin className="size-4" aria-hidden />
                      Có
                    </span>
                  ) : (
                    <span className="text-muted-foreground">
                      <span aria-hidden>—</span>
                      <span className="sr-only">Chưa có toạ độ</span>
                    </span>
                  )}
                </TableCell>
              </TableRow>
            ))}
      </TableBody>
    </Table>
  );
}
