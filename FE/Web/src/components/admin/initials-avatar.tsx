// src/components/admin/initials-avatar.tsx
import { BadgeCheck } from "lucide-react";

import { cn } from "@/lib/utils";

const TONES = [
  "bg-secondary text-secondary-foreground",
  "bg-ochre-soft text-ochre-text",
  "bg-ai-soft text-ai-text",
  "bg-sprout-soft text-sprout-text",
];

export function initials(name: string) {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return "?";
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[parts.length - 2][0] + parts[parts.length - 1][0]).toUpperCase();
}

export function InitialsAvatar({ name, verified, className }: { name: string; verified?: boolean; className?: string }) {
  const tone = TONES[[...name].reduce((s, ch) => s + ch.charCodeAt(0), 0) % TONES.length];
  return (
    <span className={cn("relative inline-flex size-9 shrink-0 items-center justify-center rounded-full text-xs font-extrabold", tone, className)}>
      {initials(name)}
      {verified && (
        <BadgeCheck
          aria-label="Chuyên gia đã xác minh"
          className="absolute -bottom-0.5 -right-0.5 size-4 rounded-full bg-card text-sprout-text"
        />
      )}
    </span>
  );
}
