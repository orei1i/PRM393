// src/components/ads/ad-preview.tsx
// Preview of the single "Được tài trợ" row at the top of the mobile "Quán chay gần bạn" list
// (GET /ads/feed?placement=nearby&limit=1). Organic rows below are placeholders.
import { ChevronDown, MapPin, Megaphone, ShieldCheck, Store } from "lucide-react";

import { cn } from "@/lib/utils";
import { AD_CTA_LABEL, type AdCtaType, type AdRestaurant } from "@/types/ads";

import { formatKm } from "./ad-badges";

/** Mock user position (plan D10: "Dùng vị trí hiện tại" is simulated at Quận 1, TP.HCM). */
const MOCK_POSITION = { lat: 10.7769, lng: 106.7009 };

function distanceKm(r: Pick<AdRestaurant, "latitude" | "longitude">) {
  if (r.latitude === null || r.longitude === null) return null;
  const rad = (d: number) => (d * Math.PI) / 180;
  const a =
    Math.sin(rad(r.latitude - MOCK_POSITION.lat) / 2) ** 2 +
    Math.cos(rad(MOCK_POSITION.lat)) * Math.cos(rad(r.latitude)) * Math.sin(rad(r.longitude - MOCK_POSITION.lng) / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.sqrt(a));
}

function OrganicRow() {
  return (
    <div className="flex items-center gap-3 border-t px-3 py-3 opacity-60" aria-hidden>
      <span className="size-10 shrink-0 rounded-lg bg-muted" />
      <span className="flex min-w-0 flex-1 flex-col gap-1.5">
        <span className="h-3 w-2/3 rounded bg-muted" />
        <span className="h-2.5 w-1/2 rounded bg-muted" />
      </span>
      <span className="h-2.5 w-10 rounded bg-muted" />
    </div>
  );
}

export function AdPreview({
  restaurant,
  headline,
  message,
  ctaType,
  className,
}: {
  restaurant: AdRestaurant | null;
  headline: string;
  message: string;
  ctaType: AdCtaType;
  className?: string;
}) {
  const km = restaurant ? distanceKm(restaurant) : null;
  return (
    <figure className={cn("flex flex-col gap-2", className)}>
      <figcaption className="text-xs font-semibold text-muted-foreground">Xem trước trong danh sách “Quán chay gần bạn”</figcaption>
      <div className="w-full max-w-[340px] overflow-hidden rounded-2xl border bg-background">
        <div className="flex items-center justify-between gap-2 border-b bg-card px-3 py-2.5">
          <span className="text-sm font-bold">Quán chay gần bạn</span>
          <span className="inline-flex items-center gap-0.5 rounded-full border px-2 py-0.5 text-[11px] text-muted-foreground">
            <MapPin className="size-3" aria-hidden />
            Quận 1
            <ChevronDown className="size-3" aria-hidden />
          </span>
        </div>

        {/* The sponsored row: always first, labelled, at most one. */}
        <div className="flex gap-3 bg-ochre-soft/50 px-3 py-3">
          <span className="flex size-10 shrink-0 items-center justify-center rounded-lg bg-secondary text-secondary-foreground">
            <Store className="size-5" aria-hidden />
          </span>
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-1.5">
              <span className="inline-flex shrink-0 items-center gap-1 rounded-full border border-ochre-border bg-ochre-soft px-1.5 py-px text-[10px] font-bold text-ochre-text">
                <Megaphone className="size-2.5" aria-hidden />
                Được tài trợ
              </span>
              {restaurant?.isVeganCertified && <ShieldCheck className="size-3.5 shrink-0 text-sprout-text" aria-label="Chứng nhận thuần chay" />}
            </div>
            <p className="mt-1 truncate text-sm font-bold leading-tight">{restaurant?.name ?? "Tên quán"}</p>
            <p className="truncate text-[11px] text-muted-foreground">
              {km === null ? "Khoảng cách theo vị trí người xem" : `${formatKm(km)} · từ vị trí mô phỏng Q.1`}
              {restaurant?.address ? ` · ${restaurant.address}` : ""}
            </p>
            <p className={cn("mt-1.5 break-words text-xs font-semibold leading-snug", !headline.trim() && "text-muted-foreground")}>
              {headline.trim() || "Tiêu đề quảng cáo"}
            </p>
            <p className={cn("line-clamp-2 break-words text-[11px] leading-relaxed text-muted-foreground", !message.trim() && "italic")}>
              {message.trim() || "Nội dung ngắn giới thiệu món, ưu đãi hoặc giờ mở cửa."}
            </p>
          </div>
          <span className="flex h-7 shrink-0 items-center self-center rounded-md bg-primary px-2.5 text-[11px] font-semibold text-primary-foreground">
            {AD_CTA_LABEL[ctaType]}
          </span>
        </div>

        <OrganicRow />
        <OrganicRow />
      </div>
      <p className="max-w-[340px] text-[11px] text-muted-foreground">
        Tối đa 1 quán được tài trợ mỗi lần, luôn nằm đầu danh sách; trên bản đồ quán có viền nổi bật.
      </p>
    </figure>
  );
}
