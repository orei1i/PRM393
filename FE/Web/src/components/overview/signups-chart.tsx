// src/components/overview/signups-chart.tsx
"use client";

import * as React from "react";

import { cn, formatNumber } from "@/lib/utils";

const fmtDay = new Intl.DateTimeFormat("vi-VN", { day: "2-digit", month: "2-digit" });
const fmtLong = new Intl.DateTimeFormat("vi-VN", { weekday: "long", day: "2-digit", month: "2-digit" });

/** Round the axis top up to a clean step (10, 20, 25, 50…). */
function niceMax(max: number) {
  const step = max <= 50 ? 10 : max <= 100 ? 25 : max <= 500 ? 100 : 250;
  return Math.max(step, Math.ceil(max / step) * step);
}

/**
 * Daily sign-ups, single series → no legend (the card title names it).
 * Columns ≤ 24px with a 4px rounded cap, hairline grid, per-column hover/focus
 * tooltip, peak value labelled, and a table view for keyboard / screen readers.
 */
export function SignupsChart({ data, dimmed }: { data: { date: string; count: number }[]; dimmed?: boolean }) {
  const [active, setActive] = React.useState<number | null>(null);
  const [showTable, setShowTable] = React.useState(false);
  const top = niceMax(Math.max(...data.map((d) => d.count), 1));
  const ticks = [top, top / 2, 0];
  const peak = data.reduce((best, d, i) => (d.count > data[best].count ? i : best), 0);

  return (
    <div className={cn("flex flex-col gap-3 transition-opacity", dimmed && "opacity-60")}>
      <div className="flex justify-end">
        <button
          type="button"
          onClick={() => setShowTable((v) => !v)}
          className="text-xs font-semibold text-muted-foreground underline-offset-4 hover:text-foreground hover:underline"
        >
          {showTable ? "Xem biểu đồ" : "Xem dạng bảng"}
        </button>
      </div>

      {showTable ? (
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b text-left text-xs text-muted-foreground">
              <th className="py-1.5 font-semibold">Ngày</th>
              <th className="py-1.5 text-right font-semibold">Đăng ký mới</th>
            </tr>
          </thead>
          <tbody>
            {data.map((d) => (
              <tr key={d.date} className="border-b last:border-0">
                <td className="py-1.5">{fmtLong.format(new Date(d.date))}</td>
                <td className="py-1.5 text-right font-mono tabular">{formatNumber(d.count)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : (
        <div className="flex gap-2">
          {/* y-axis */}
          <div className="relative h-48 w-8 shrink-0 text-right font-mono text-[11px] text-muted-foreground tabular">
            {ticks.map((t) => (
              <span key={t} className="absolute right-0 -translate-y-1/2" style={{ top: `${(1 - t / top) * 100}%` }}>
                {formatNumber(t)}
              </span>
            ))}
          </div>

          <div className="relative min-w-0 flex-1">
            {/* hairline grid */}
            <div className="pointer-events-none absolute inset-x-0 top-0 h-48" aria-hidden>
              {ticks.map((t) => (
                <div key={t} className="absolute inset-x-0 h-px bg-border" style={{ top: `${(1 - t / top) * 100}%` }} />
              ))}
            </div>

            <div className="relative flex h-48 items-end gap-0.5" role="list" aria-label="Đăng ký mới theo ngày">
              {data.map((d, i) => {
                const h = (d.count / top) * 100;
                const isActive = active === i;
                return (
                  <div
                    key={d.date}
                    role="listitem"
                    tabIndex={0}
                    aria-label={`${fmtLong.format(new Date(d.date))}: ${d.count} đăng ký`}
                    onPointerEnter={() => setActive(i)}
                    onPointerLeave={() => setActive((v) => (v === i ? null : v))}
                    onFocus={() => setActive(i)}
                    onBlur={() => setActive((v) => (v === i ? null : v))}
                    className="group relative flex h-full flex-1 cursor-default items-end justify-center outline-none"
                  >
                    <div
                      className={cn(
                        "w-full max-w-6 rounded-t-[4px] bg-primary transition-[filter]",
                        isActive && "brightness-125",
                        "group-focus-visible:ring-2 group-focus-visible:ring-ring/50",
                      )}
                      style={{ height: `${Math.max(h, 1)}%` }}
                    />
                    {i === peak && !isActive && (
                      <span className="absolute -translate-y-1 font-mono text-[11px] font-semibold text-foreground tabular" style={{ bottom: `${h}%` }}>
                        {d.count}
                      </span>
                    )}
                    {isActive && (
                      <div
                        role="tooltip"
                        className="pointer-events-none absolute z-10 mb-2 w-max -translate-y-1 rounded-lg border bg-popover px-2.5 py-1.5 text-xs shadow-md"
                        style={{ bottom: `${h}%` }}
                      >
                        <p className="font-mono text-sm font-bold tabular">{formatNumber(d.count)}</p>
                        <p className="text-muted-foreground">{fmtLong.format(new Date(d.date))}</p>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>

            {/* x-axis: first, middle, last */}
            <div className="mt-1.5 flex justify-between font-mono text-[11px] text-muted-foreground tabular">
              <span>{fmtDay.format(new Date(data[0]?.date ?? Date.now()))}</span>
              <span>{fmtDay.format(new Date(data[Math.floor(data.length / 2)]?.date ?? Date.now()))}</span>
              <span>{fmtDay.format(new Date(data[data.length - 1]?.date ?? Date.now()))}</span>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
