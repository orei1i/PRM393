// src/components/ui/switch.tsx
"use client";

import { cn } from "@/lib/utils";

/** Accessible on/off toggle (role="switch"), shadcn look without the Radix dependency. */
export function Switch({
  checked,
  onCheckedChange,
  disabled,
  className,
  ...aria
}: {
  checked: boolean;
  onCheckedChange: (next: boolean) => void;
  disabled?: boolean;
  className?: string;
  "aria-label"?: string;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      disabled={disabled}
      onClick={() => onCheckedChange(!checked)}
      className={cn(
        "relative inline-flex h-5 w-9 shrink-0 cursor-pointer items-center rounded-full border-2 border-transparent transition-colors outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 disabled:cursor-not-allowed disabled:opacity-50",
        checked ? "bg-primary" : "bg-input",
        className,
      )}
      {...aria}
    >
      <span
        aria-hidden
        className={cn(
          "pointer-events-none block size-4 rounded-full bg-card shadow-sm transition-transform",
          checked ? "translate-x-4" : "translate-x-0",
        )}
      />
    </button>
  );
}
