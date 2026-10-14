// src/app/(admin)/telemetry/page.tsx
"use client";

import * as React from "react";
import { Activity, Flag, Gauge, Pause, Play, TriangleAlert } from "lucide-react";

import { LiveLogTable } from "@/components/telemetry/live-log-table";
import { MetricCard } from "@/components/telemetry/metric-card";
import { TaskFilter } from "@/components/telemetry/task-filter";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { NativeSelect } from "@/components/ui/form-controls";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { describeError } from "@/lib/api_error";
import { useAiLogs, useTelemetrySummary } from "@/lib/hooks/use-telemetry";
import { cn, formatNumber, formatPercent } from "@/lib/utils";
import { TASK_LABEL, type AiTaskType, type TelemetryRange } from "@/types/moderation";

const RANGE_LABEL: Record<TelemetryRange, string> = { "1h": "1 giờ qua", "24h": "24 giờ qua", "7d": "7 ngày qua" };

/** Error-rate SLO per task; rows above it are highlighted. */
const ERROR_SLO = 0.02;

export default function TelemetryPage() {
  const [range, setRange] = React.useState<TelemetryRange>("24h");
  const [task, setTask] = React.useState<AiTaskType | "all">("all");
  const [live, setLive] = React.useState(true);

  const summary = useTelemetrySummary(range);
  const logQuery = React.useMemo(() => ({ task, limit: 50 }), [task]);
  const logs = useAiLogs(logQuery, live);
  const s = summary.data;

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-2xl font-extrabold tracking-tight">Giám sát mô hình AI</h1>
          <p className="text-sm text-muted-foreground">Độ trễ, token và tỉ lệ lỗi theo tác vụ, lấy từ bảng ai_logs.</p>
        </div>
        <NativeSelect
          aria-label="Khoảng thời gian"
          value={range}
          onChange={(e) => setRange(e.target.value as TelemetryRange)}
          className="w-40"
        >
          {(Object.keys(RANGE_LABEL) as TelemetryRange[]).map((r) => (
            <option key={r} value={r}>
              {RANGE_LABEL[r]}
            </option>
          ))}
        </NativeSelect>
      </div>

      {summary.isError && (
        <p role="alert" className="rounded-lg border border-ochre-border bg-ochre-soft px-4 py-3 text-sm text-ochre-text">
          Chưa tải được số liệu tổng hợp: {describeError(summary.error)}
        </p>
      )}

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard
          label="Tổng lượt gọi"
          icon={Activity}
          loading={summary.isLoading}
          value={s ? formatNumber(s.totalCalls) : "–"}
          delta={s?.delta.totalCalls}
          hint={s ? `${formatNumber(Math.round(s.totalTokens / 1e6))} triệu token` : undefined}
        />
        <MetricCard
          label="Độ trễ trung bình"
          icon={Gauge}
          loading={summary.isLoading}
          value={s ? formatNumber(s.avgLatencyMs) : "–"}
          unit="ms"
          delta={s?.delta.avgLatencyMs}
          goodWhen="down"
          hint={s ? `p95 ${formatNumber(s.p95LatencyMs)} ms` : undefined}
        />
        <MetricCard
          label="Tỉ lệ gắn cờ"
          icon={Flag}
          loading={summary.isLoading}
          value={s ? formatPercent(s.flagRate) : "–"}
          delta={s?.delta.flagRate}
          goodWhen="down"
          hint="trên lượt kiểm duyệt"
        />
        <MetricCard
          label="Tỉ lệ lỗi"
          icon={TriangleAlert}
          loading={summary.isLoading}
          value={s ? formatPercent(s.errorRate) : "–"}
          delta={s?.delta.errorRate}
          goodWhen="down"
          hint={`SLO ${formatPercent(ERROR_SLO)}`}
        />
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Theo tác vụ</CardTitle>
          <CardDescription>{RANGE_LABEL[range]} · dòng tô màu là tác vụ vượt SLO lỗi</CardDescription>
        </CardHeader>
        <CardContent className="px-0">
          <Table>
            <TableHeader>
              <TableRow className="hover:bg-transparent">
                <TableHead className="pl-5">Tác vụ</TableHead>
                <TableHead className="text-right">Lượt gọi</TableHead>
                <TableHead className="text-right">Trung bình</TableHead>
                <TableHead className="text-right">p95</TableHead>
                <TableHead className="pr-5 text-right">Tỉ lệ lỗi</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody className="font-mono text-xs">
              {s?.byTask.map((t) => {
                const breach = t.errorRate > ERROR_SLO;
                return (
                  <TableRow key={t.task} className={cn(breach && "bg-ochre-soft hover:bg-ochre-soft")}>
                    <TableCell className="pl-5 font-sans text-sm font-semibold">{TASK_LABEL[t.task]}</TableCell>
                    <TableCell className="text-right tabular">{formatNumber(t.calls)}</TableCell>
                    <TableCell className="text-right tabular">{formatNumber(t.avgLatencyMs)} ms</TableCell>
                    <TableCell className="text-right tabular">{formatNumber(t.p95LatencyMs)} ms</TableCell>
                    <TableCell className={cn("pr-5 text-right tabular", breach && "font-bold text-ochre-text")}>
                      {formatPercent(t.errorRate)}
                      {breach && <span className="ml-1 font-sans">· vượt SLO</span>}
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Card className="gap-0 py-0">
        <div className="flex flex-wrap items-center gap-3 border-b p-4">
          <h2 className="font-bold">Nhật ký AI trực tiếp</h2>
          <span
            className={cn(
              "inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-bold",
              live ? "bg-sprout-soft text-sprout-text" : "bg-muted text-muted-foreground",
            )}
            aria-live="polite"
          >
            <span className={cn("size-1.5 rounded-full", live ? "animate-pulse bg-sprout" : "bg-muted-foreground")} />
            {live ? "Đang cập nhật mỗi 3 giây" : "Đã tạm dừng"}
          </span>
          <div className="ml-auto flex flex-wrap items-center gap-2">
            <TaskFilter value={task} onChange={setTask} />
            <Button variant="outline" size="sm" onClick={() => setLive((v) => !v)} aria-pressed={!live}>
              {live ? <Pause aria-hidden /> : <Play aria-hidden />}
              {live ? "Tạm dừng" : "Tiếp tục"}
            </Button>
          </div>
        </div>
        {logs.isError ? (
          <p role="alert" className="p-6 text-sm text-ochre-text">
            Mất kết nối luồng nhật ký: {describeError(logs.error)}. Hệ thống sẽ thử lại tự động.
          </p>
        ) : (
          <LiveLogTable logs={logs.data} isLoading={logs.isLoading} />
        )}
      </Card>
    </div>
  );
}
