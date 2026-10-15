// src/components/ads/ad-preview.tsx
// Preview of the "Được tài trợ" card the mobile feed renders from GET /ads/feed.
import { MapPin, Megaphone, MoreHorizontal, ShieldCheck, Store } from "lucide-react";

import { cn } from "@/lib/utils";
import { AD_CTA_LABEL, type AdCtaType, type AdRestaurant } from "@/types/ads";

import { formatKm } from "./ad-badges";

/** Mock user position (plan D8): Quận 1, TP.HCM. The app uses the device location. */
const MOCK_POSITION = { lat: 10.7769, lng: 106.7009 };

function distanceKm(r: Pick<AdRestaurant, "latitude" | "longitude">) {
  if (r.latitude === null || r.longitude === null) return null;
  const rad = (d: number) => (d * Math.PI) / 180;
  const a =
    Math.sin(rad(r.latitude - MOCK_POSITION.lat) / 2) ** 2 +
    Math.cos(rad(MOCK_POSITION.lat)) * Math.cos(rad(r.latitude)) * Math.sin(rad(r.longitude - MOCK_POSITION.lng) / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.sqrt(a));
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
      <figcaption className="text-xs font-semibold text-muted-foreground">Xem trước trên bảng tin ứng dụng</figcaption>
      <div className="w-full max-w-[340px] rounded-2xl border bg-background p-3">
        <div className="rounded-xl border bg-card p-4 shadow-xs">
          <div className="flex items-center justify-between gap-2">
            <span className="inline-flex items-center gap-1 rounded-full border border-ochre-border bg-ochre-soft px-2 py-0.5 text-[11px] font-bold text-ochre-text">
              <Megaphone className="size-3" aria-hidden />
              Được tài trợ
            </span>
            <MoreHorizontal className="size-4 text-muted-foreground" aria-hidden />
          </div>

          <div className="mt-3 flex gap-3">
            <span className="flex size-12 shrink-0 items-center justify-center rounded-xl bg-secondary text-secondary-foreground">
              <Store className="size-5" aria-hidden />
            </span>
            <div className="min-w-0">
              <p className="flex items-center gap-1 font-bold leading-tight">
                <span className="truncate">{restaurant?.name ?? "Tên quán"}</span>
                {restaurant?.isVeganCertified && <ShieldCheck className="size-4 shrink-0 text-sprout-text" aria-label="Chứng nhận thuần chay" />}
              </p>
              <p className="mt-0.5 line-clamp-2 text-xs text-muted-foreground">{restaurant?.address ?? "Địa chỉ quán"}</p>
              <p className="mt-1 inline-flex items-center gap-1 text-xs text-muted-foreground">
                <MapPin className="size-3.5" aria-hidden />
                {km === null ? "Khoảng cách theo vị trí người xem" : `${formatKm(km)} · từ vị trí mô phỏng Q.1`}
              </p>
            </div>
          </div>

          <p className={cn("mt-3 break-words font-bold leading-snug", !headline.trim() && "text-muted-foreground")}>
            {headline.trim() || "Tiêu đề quảng cáo"}
          </p>
          <p className={cn("mt-1 break-words text-sm leading-relaxed text-muted-foreground", !message.trim() && "italic")}>
            {message.trim() || "Nội dung ngắn giới thiệu món, ưu đãi hoặc giờ mở cửa."}
          </p>

          <span className="mt-3 flex h-10 w-full items-center justify-center rounded-lg bg-primary text-sm font-semibold text-primary-foreground">
            {AD_CTA_LABEL[ctaType]}
          </span>
        </div>
      </div>
    </figure>
  );
}
