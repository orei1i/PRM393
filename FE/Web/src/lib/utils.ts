// src/lib/utils.ts
import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/** For search: lower case, no Vietnamese accents ("Đậu" → "dau"). */
export const foldText = (s: string) =>
  s
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[Đđ]/g, "d")
    .toLowerCase();

/**
 * A date formatter that cannot throw. `Intl.DateTimeFormat.format` raises a RangeError on an invalid
 * Date, which in render would take the whole page down. Bad dates and the epoch placeholder the
 * normalisers use for "no date" print as "—".
 */
export function dateFormat(options: Intl.DateTimeFormatOptions) {
  const inner = new Intl.DateTimeFormat("vi-VN", options);
  return { format: (date: Date) => (date.getTime() > 0 ? inner.format(date) : "—") };
}

const numberVi = new Intl.NumberFormat("vi-VN");
const percentVi = new Intl.NumberFormat("vi-VN", { style: "percent", maximumFractionDigits: 1 });

/** 86412 → "86.412" */
export const formatNumber = (n: number) => numberVi.format(n);

/** 0.018 → "1,8 %" */
export const formatPercent = (ratio: number) => percentVi.format(ratio);

/** "2 giờ 14 phút" / "3 ngày" since an ISO date */
export function formatAge(iso: string, now: Date = new Date()) {
  const then = new Date(iso).getTime();
  if (!(then > 0)) return "—";
  const minutes = Math.max(0, Math.round((now.getTime() - then) / 60000));
  if (minutes < 1) return "vừa xong";
  if (minutes < 60) return `${minutes} phút`;
  if (minutes >= 48 * 60) return `${Math.floor(minutes / (24 * 60))} ngày`;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return rest ? `${hours} giờ ${rest} phút` : `${hours} giờ`;
}

/** "11:02:41" */
export function formatTime(iso: string) {
  const date = new Date(iso);
  return date.getTime() > 0 ? date.toLocaleTimeString("vi-VN", { hour12: false }) : "—";
}
