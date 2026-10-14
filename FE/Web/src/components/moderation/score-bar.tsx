// src/components/moderation/score-bar.tsx
import { cn } from "@/lib/utils";

const TONE = {
  ai: "bg-ai",
  aiLight: "bg-ai-light",
  ochre: "bg-ochre",
  sprout: "bg-sprout",
} as const;

/** 0…1 score as a bar + mono value. `role="meter"` so screen readers get the number. */
export function ScoreBar({
  value,
  label,
  tone = "ai",
  className,
  showValue = true,
}: {
  value: number;
  label: string;
  tone?: keyof typeof TONE;
  className?: string;
  showValue?: boolean;
}) {
  const pct = Math.round(Math.min(1, Math.max(0, value)) * 100);
  return (
    <div className={cn("flex items-center gap-2", className)}>
      <div
        role="meter"
        aria-label={label}
        aria-valuemin={0}
        aria-valuemax={1}
        aria-valuenow={Number(value.toFixed(2))}
        className="h-1.5 min-w-12 flex-1 overflow-hidden rounded-full bg-muted"
      >
        <div className={cn("h-full rounded-full transition-[width] duration-500", TONE[tone])} style={{ width: `${pct}%` }} />
      </div>
      {showValue && <span className="w-9 text-right font-mono text-xs font-semibold tabular">{value.toFixed(2)}</span>}
    </div>
  );
}
