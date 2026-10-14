// src/components/telemetry/live-log-table.tsx
"use client";

import * as React from "react";

import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/form-controls";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { cn, formatNumber, formatTime } from "@/lib/utils";
import { TASK_LABEL, type AiLog, type AiLogStatus } from "@/types/moderation";

const STATUS: Record<AiLogStatus, { label: string; variant: "sprout" | "ochre" | "destructive" }> = {
  success: { label: "OK", variant: "sprout" },
  warning: { label: "Cảnh báo", variant: "ochre" },
  error: { label: "Lỗi", variant: "destructive" },
};

/** ai_logs stream. Rows that arrived since the previous render flash once. */
export function LiveLogTable({ logs, isLoading }: { logs: AiLog[] | undefined; isLoading: boolean }) {
  const seen = React.useRef<Set<string> | null>(null);
  const [fresh, setFresh] = React.useState<Set<string>>(new Set());

  React.useEffect(() => {
    if (!logs) return;
    if (seen.current === null) {
      seen.current = new Set(logs.map((l) => l.id));
      return;
    }
    const next = new Set<string>();
    for (const l of logs) {
      if (!seen.current.has(l.id)) {
        next.add(l.id);
        seen.current.add(l.id);
      }
    }
    if (next.size) setFresh(next);
  }, [logs]);

  return (
    <Table className="min-w-[860px] font-mono text-xs">
      <TableHeader>
        <TableRow className="hover:bg-transparent">
          <TableHead className="pl-5 font-sans">Thời gian</TableHead>
          <TableHead className="font-sans">Tác vụ</TableHead>
          <TableHead className="font-sans">Mô hình</TableHead>
          <TableHead className="text-right font-sans">Độ trễ</TableHead>
          <TableHead className="text-right font-sans">Tokens vào / ra</TableHead>
          <TableHead className="font-sans">Kết quả</TableHead>
          <TableHead className="pr-5 font-sans">Trace</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {isLoading && !logs
          ? Array.from({ length: 8 }, (_, i) => (
              <TableRow key={i}>
                {Array.from({ length: 7 }, (__, j) => (
                  <TableCell key={j} className={j === 0 ? "pl-5" : undefined}>
                    <Skeleton className="h-4 w-full" />
                  </TableCell>
                ))}
              </TableRow>
            ))
          : logs?.map((log) => {
              const status = STATUS[log.status];
              return (
                <TableRow key={log.id} className={cn(fresh.has(log.id) && "vl-row-new")}>
                  <TableCell className="pl-5 tabular">{formatTime(log.timestamp)}</TableCell>
                  <TableCell className="font-sans font-semibold">{TASK_LABEL[log.task]}</TableCell>
                  <TableCell>{log.model}</TableCell>
                  <TableCell className={cn("text-right tabular", log.latencyMs > 8000 && "font-semibold text-ochre-text")}>
                    {formatNumber(log.latencyMs)} ms
                  </TableCell>
                  <TableCell className="text-right tabular">
                    {log.inputTokens || log.outputTokens ? `${formatNumber(log.inputTokens)} / ${formatNumber(log.outputTokens)}` : "–"}
                  </TableCell>
                  <TableCell>
                    <span className="flex items-center gap-2">
                      <Badge variant={status.variant} className="font-sans">
                        {status.label}
                      </Badge>
                      <span className="text-muted-foreground">{log.detail}</span>
                    </span>
                  </TableCell>
                  <TableCell className="pr-5">
                    <code className="rounded bg-muted px-1.5 py-0.5">{log.traceId}</code>
                  </TableCell>
                </TableRow>
              );
            })}
      </TableBody>
    </Table>
  );
}
