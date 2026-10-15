// src/components/ads/ad-badges.tsx
import { CalendarClock, CircleCheck, CirclePause, Flag, MousePointerClick } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { AD_CTA_LABEL, AD_STATUS_LABEL, type AdCtaType, type AdStatus } from "@/types/ads";

export function AdStatusBadge({ status }: { status: AdStatus }) {
  switch (status) {
    case "Running":
      return (
        <Badge variant="sprout">
          <CircleCheck aria-hidden />
          {AD_STATUS_LABEL[status]}
        </Badge>
      );
    case "Scheduled":
      return (
        <Badge variant="ai">
          <CalendarClock aria-hidden />
          {AD_STATUS_LABEL[status]}
        </Badge>
      );
    case "Paused":
      return (
        <Badge variant="ochre">
          <CirclePause aria-hidden />
          {AD_STATUS_LABEL[status]}
        </Badge>
      );
    case "Ended":
      return (
        <Badge variant="secondary">
          <Flag aria-hidden />
          {AD_STATUS_LABEL[status]}
        </Badge>
      );
  }
}

export function CtaBadge({ cta }: { cta: AdCtaType }) {
  return (
    <Badge variant="outline">
      <MousePointerClick aria-hidden />
      {AD_CTA_LABEL[cta]}
    </Badge>
  );
}

/** "05/10/2026" */
export const dateVi = new Intl.DateTimeFormat("vi-VN", { day: "2-digit", month: "2-digit", year: "numeric" });

export const formatDateRange = (startAt: string, endAt: string) => `${dateVi.format(new Date(startAt))} – ${dateVi.format(new Date(endAt))}`;

const kmVi = new Intl.NumberFormat("vi-VN", { maximumFractionDigits: 1 });
export const formatKm = (km: number) => `${kmVi.format(km)} km`;
