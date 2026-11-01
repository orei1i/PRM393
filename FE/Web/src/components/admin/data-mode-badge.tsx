// src/components/admin/data-mode-badge.tsx
"use client";

import { usePathname } from "next/navigation";

import { ALL_MODULES_REAL, dataModeLabel } from "@/lib/backend_modules";

export function DataModeBadge() {
  const pathname = usePathname();
  return (
    <span
      className={
        ALL_MODULES_REAL
          ? "rounded-full bg-foreground px-3 py-1 text-xs font-bold text-background"
          : "rounded-full border border-ochre-border bg-ochre-soft px-3 py-1 text-xs font-bold text-ochre-text"
      }
    >
      {dataModeLabel(pathname)}
    </span>
  );
}
