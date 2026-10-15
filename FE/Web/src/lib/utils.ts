// src/lib/utils.ts
import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

const numberVi = new Intl.NumberFormat("vi-VN");
const percentVi = new Intl.NumberFormat("vi-VN", { style: "percent", maximumFractionDigits: 1 });

/** 86412 → "86.412" */
export const formatNumber = (n: number) => numberVi.format(n);

/** 0.018 → "1,8 %" */
export const formatPercent = (ratio: number) => percentVi.format(ratio);

/** "2 giờ 14 phút" / "3 ngày" since an ISO date */
export function formatAge(iso: string, now: Date = new Date()) {
  const minutes = Math.max(0, Math.round((now.getTime() - new Date(iso).getTime()) / 60000));
  if (minutes < 1) return "vừa xong";
  if (minutes < 60) return `${minutes} phút`;
  if (minutes >= 48 * 60) return `${Math.floor(minutes / (24 * 60))} ngày`;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return rest ? `${hours} giờ ${rest} phút` : `${hours} giờ`;
}

/** "11:02:41" */
export function formatTime(iso: string) {
  return new Date(iso).toLocaleTimeString("vi-VN", { hour12: false });
}
