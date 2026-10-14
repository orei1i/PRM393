// src/components/telemetry/metric-card.tsx
import { ArrowDownRight, ArrowUpRight, type LucideIcon } from "lucide-react";

import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/form-controls";
import { cn, formatPercent } from "@/lib/utils";

/**
 * KPI tile. `delta` is relative change vs the previous range;
 * `goodWhen` decides whether up is good (calls) or bad (latency, errors).
 */
export function MetricCard({
  label,
  value,
  unit,
  hint,
  delta,
  goodWhen = "up",
  icon: Icon,
  loading,
}: {
  label: string;
  value: string;
  unit?: string;
  hint?: string;
  delta?: number;
  goodWhen?: "up" | "down";
  icon: LucideIcon;
  loading?: boolean;
}) {
  const up = (delta ?? 0) >= 0;
  const good = goodWhen === "up" ? up : !up;

  return (
    <Card className="gap-2 px-5 py-4">
      <div className="flex items-center justify-between text-sm font-semibold text-muted-foreground">
        {label}
        <Icon className="size-4" aria-hidden />
      </div>
      {loading ? (
        <Skeleton className="h-8 w-32" />
      ) : (
        <p className="font-mono text-[28px] font-semibold leading-8 tabular">
          {value}
          {unit && <span className="ml-1 text-base text-muted-foreground">{unit}</span>}
        </p>
      )}
      <div className="flex min-h-5 flex-wrap items-center gap-x-2 text-xs">
        {delta !== undefined && !loading && (
          <span className={cn("inline-flex items-center gap-0.5 font-bold", good ? "text-sprout-text" : "text-ochre-text")}>
            {up ? <ArrowUpRight className="size-3.5" aria-hidden /> : <ArrowDownRight className="size-3.5" aria-hidden />}
            {up ? "+" : ""}
            {formatPercent(delta)}
            <span className="sr-only">{good ? " (tốt)" : " (cần chú ý)"}</span>
          </span>
        )}
        {hint && <span className="text-muted-foreground">{hint}</span>}
      </div>
    </Card>
  );
}
