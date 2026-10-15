// src/components/content/filter-chip.tsx
import { X } from "lucide-react";

/** Removable filter chip, e.g. "Tác giả: Minh Anh ×" from a `?author=` link. */
export function FilterChip({ label, value, onRemove }: { label: string; value: string; onRemove: () => void }) {
  return (
    <span className="inline-flex h-8 max-w-full items-center gap-1 rounded-full border bg-secondary pl-3 pr-1 text-sm text-secondary-foreground">
      <span className="truncate">
        {label}: <b>{value}</b>
      </span>
      <button
        type="button"
        onClick={onRemove}
        aria-label={`Bỏ lọc ${label.toLowerCase()} ${value}`}
        className="flex size-6 shrink-0 items-center justify-center rounded-full outline-none hover:bg-accent focus-visible:ring-[3px] focus-visible:ring-ring/40"
      >
        <X className="size-3.5" aria-hidden />
      </button>
    </span>
  );
}
