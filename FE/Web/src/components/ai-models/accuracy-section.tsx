// src/components/ai-models/accuracy-section.tsx
"use client";

import Link from "next/link";
import type { UseQueryResult } from "@tanstack/react-query";
import { Hourglass, Tags, Target, Timer, Undo2 } from "lucide-react";

import { ErrorState } from "@/components/admin/states";
import { ScoreBar } from "@/components/moderation/score-bar";
import { MetricCard } from "@/components/telemetry/metric-card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/form-controls";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { formatNumber, formatPercent } from "@/lib/utils";
import { AI_TASK_TITLE, MIN_LABELS_FOR_ACCURACY, type AiAccuracyMetrics } from "@/types/ai_models";
import { FLAG_CATEGORY_LABEL } from "@/types/moderation";

type MetricsQuery = UseQueryResult<AiAccuracyMetrics>;

/** 1 · Moderation precision: how often admins upheld the AI's flags. */
export function ModerationAccuracy({ metrics }: { metrics: MetricsQuery }) {
  const m = metrics.data?.moderation;

  if (metrics.isError && !m) {
    return (
      <Card>
        <ErrorState error={metrics.error} onRetry={() => metrics.refetch()} title="Chưa tải được độ chính xác kiểm duyệt" />
      </Card>
    );
  }

  return (
    <section aria-labelledby="moderation-accuracy" className="flex flex-col gap-4">
      <div>
        <h2 id="moderation-accuracy" className="text-lg font-bold">
          Độ chính xác kiểm duyệt
        </h2>
        <p className="text-sm text-muted-foreground">Tính từ ai_flags × moderation_decisions.</p>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard
          label="Độ chính xác cờ AI"
          icon={Target}
          loading={metrics.isLoading}
          value={m ? formatPercent(m.precision) : "–"}
          hint={m ? `${formatNumber(m.confirmed)}/${formatNumber(m.decided)} cờ được giữ nguyên` : undefined}
        />
        <MetricCard
          label="Tỉ lệ admin đảo quyết định"
          icon={Undo2}
          loading={metrics.isLoading}
          value={m ? formatPercent(m.overrideRate) : "–"}
          hint={m ? `${formatNumber(m.overridden)} cờ được duyệt lại cho đăng` : undefined}
        />
        <MetricCard
          label="Cờ đang chờ"
          icon={Hourglass}
          loading={metrics.isLoading}
          value={m ? formatNumber(m.pending) : "–"}
          hint="hàng Kiểm duyệt AI + bài chờ duyệt"
        />
        <MetricCard
          label="Thời gian xử lý trung vị"
          icon={Timer}
          loading={metrics.isLoading}
          value={m ? formatNumber(m.medianDecisionMinutes) : "–"}
          unit="phút"
          hint="từ lúc gắn cờ tới khi có quyết định"
        />
      </div>

      <Card className="gap-0 py-0">
        <div className="border-b px-5 py-4">
          <p className="font-bold">Theo hạng mục</p>
          <p className="text-sm text-muted-foreground">Độ chính xác = cờ bị admin giữ nguyên (gỡ / cảnh cáo) ÷ cờ đã có quyết định.</p>
        </div>
        <Table className="min-w-[520px]">
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              <TableHead className="pl-5">Hạng mục</TableHead>
              <TableHead className="text-right">Đã quyết định</TableHead>
              <TableHead className="w-[40%] pr-5">Độ chính xác</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {!m
              ? Array.from({ length: 4 }, (_, i) => (
                  <TableRow key={i}>
                    <TableCell colSpan={3} className="px-5">
                      <Skeleton className="h-6" />
                    </TableCell>
                  </TableRow>
                ))
              : m.byCategory.map((row) => (
                  <TableRow key={row.category}>
                    <TableCell className="pl-5 font-semibold">{FLAG_CATEGORY_LABEL[row.category]}</TableCell>
                    <TableCell className="text-right font-mono tabular">{formatNumber(row.decided)}</TableCell>
                    <TableCell className="pr-5">
                      {row.decided ? (
                        <div className="flex items-center gap-3">
                          <ScoreBar value={row.precision} label={`Độ chính xác ${FLAG_CATEGORY_LABEL[row.category]}`} showValue={false} />
                          <span className="w-14 text-right font-mono text-xs font-semibold tabular">{formatPercent(row.precision)}</span>
                        </div>
                      ) : (
                        <span className="text-muted-foreground">—</span>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
            {m && (
              <TableRow className="bg-muted/50 font-semibold hover:bg-muted/50">
                <TableCell className="pl-5">Tổng</TableCell>
                <TableCell className="text-right font-mono tabular">{formatNumber(m.decided)}</TableCell>
                <TableCell className="pr-5 text-right font-mono text-xs tabular">{formatPercent(m.precision)}</TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </Card>
    </section>
  );
}

/** 2 · Accuracy from admin labels on individual AI outputs (telemetry log drawer). */
export function LabeledAccuracy({ metrics }: { metrics: MetricsQuery }) {
  const rows = metrics.data?.labeled;

  return (
    <Card className="gap-0 py-0">
      <CardHeader className="border-b py-4">
        <CardTitle>Độ chính xác theo nhãn của admin</CardTitle>
        <CardDescription>
          Admin đánh giá Đúng / Sai từng đầu ra trong Giám sát AI. Cần ít nhất {MIN_LABELS_FOR_ACCURACY} nhãn để tính.
        </CardDescription>
      </CardHeader>
      <CardContent className="px-0">
        {metrics.isError && !rows ? (
          <ErrorState error={metrics.error} onRetry={() => metrics.refetch()} title="Chưa tải được số nhãn" />
        ) : (
          <Table className="min-w-[620px]">
            <TableHeader>
              <TableRow className="hover:bg-transparent">
                <TableHead className="pl-5">Tác vụ</TableHead>
                <TableHead className="text-right">Đã gắn nhãn</TableHead>
                <TableHead className="text-right">Đúng</TableHead>
                <TableHead>Độ chính xác</TableHead>
                <TableHead className="pr-5 text-right">
                  <span className="sr-only">Thao tác</span>
                </TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {!rows
                ? Array.from({ length: 3 }, (_, i) => (
                    <TableRow key={i}>
                      <TableCell colSpan={5} className="px-5">
                        <Skeleton className="h-6" />
                      </TableCell>
                    </TableRow>
                  ))
                : rows.map((row) => (
                    <TableRow key={row.task}>
                      <TableCell className="pl-5 font-semibold">{AI_TASK_TITLE[row.task]}</TableCell>
                      <TableCell className="text-right font-mono tabular">{formatNumber(row.labeled)}</TableCell>
                      <TableCell className="text-right font-mono tabular">{formatNumber(row.correct)}</TableCell>
                      <TableCell>
                        {row.accuracy === null ? (
                          <Badge variant="ochre">Chưa đủ nhãn</Badge>
                        ) : (
                          <span className="font-mono font-semibold tabular">{formatPercent(row.accuracy)}</span>
                        )}
                      </TableCell>
                      <TableCell className="pr-5 text-right">
                        <Button asChild size="sm" variant="ghost">
                          <Link href={`/telemetry?task=${row.task}`}>
                            <Tags aria-hidden />
                            Gắn nhãn thêm
                          </Link>
                        </Button>
                      </TableCell>
                    </TableRow>
                  ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}
