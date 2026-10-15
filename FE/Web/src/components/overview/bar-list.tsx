// src/components/overview/bar-list.tsx
import { formatNumber } from "@/lib/utils";

/**
 * Horizontal magnitude bars, one hue (identity comes from the text label,
 * not colour). Value sits at the bar tip; the track is a lighter step.
 */
export function BarList({ items }: { items: { label: string; value: number }[] }) {
  const max = Math.max(...items.map((i) => i.value), 1);
  const total = items.reduce((s, i) => s + i.value, 0);
  return (
    <ul className="flex flex-col gap-3">
      {items.map((item) => (
        <li key={item.label} className="flex flex-col gap-1.5">
          <div className="flex items-baseline justify-between gap-2 text-sm">
            <span className="font-semibold">{item.label}</span>
            <span className="font-mono text-xs text-muted-foreground tabular">
              {formatNumber(item.value)} · {Math.round((item.value / total) * 100)}%
            </span>
          </div>
          <div className="h-2.5 rounded-full bg-secondary" title={`${item.label}: ${formatNumber(item.value)}`}>
            <div className="h-full rounded-full bg-primary" style={{ width: `${(item.value / max) * 100}%` }} />
          </div>
        </li>
      ))}
    </ul>
  );
}
