// src/app/(admin)/ai-models/page.tsx
"use client";

import * as React from "react";

import { LabeledAccuracy, ModerationAccuracy } from "@/components/ai-models/accuracy-section";
import { ModelCard } from "@/components/ai-models/model-card";
import { PageHeader } from "@/components/admin/page-header";
import { ErrorState } from "@/components/admin/states";
import { Card } from "@/components/ui/card";
import { NativeSelect, Skeleton } from "@/components/ui/form-controls";
import { useAiMetrics, useAiModels } from "@/lib/hooks/use-ai-models";
import type { TelemetryRange } from "@/types/moderation";

const RANGE_LABEL: Record<TelemetryRange, string> = { "1h": "1 giờ", "24h": "24 giờ", "7d": "7 ngày" };

export default function AiModelsPage() {
  const [range, setRange] = React.useState<TelemetryRange>("24h");
  const metrics = useAiMetrics(range);
  const models = useAiModels();

  return (
    <div className="flex flex-col gap-8">
      <PageHeader
        title="Mô hình AI"
        description="Độ chính xác so với quyết định của admin, nhãn đánh giá đầu ra và công tắc điều khiển từng mô hình."
        actions={
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
        }
      />

      <ModerationAccuracy metrics={metrics} />

      <LabeledAccuracy metrics={metrics} />

      <section aria-labelledby="running-models" className="flex flex-col gap-4">
        <div>
          <h2 id="running-models" className="text-lg font-bold">
            Mô hình đang chạy
          </h2>
          <p className="text-sm text-muted-foreground">
            Mọi thay đổi cần ghi chú kiểm toán. Tắt một mô hình sẽ chuyển ứng dụng sang cách xử lý dự phòng ghi trên thẻ.
          </p>
        </div>
        {models.isError && !models.data ? (
          <Card>
            <ErrorState error={models.error} onRetry={() => models.refetch()} title="Chưa tải được danh sách mô hình" />
          </Card>
        ) : models.isLoading ? (
          <div className="grid gap-4 lg:grid-cols-2">
            {Array.from({ length: 4 }, (_, i) => (
              <Skeleton key={i} className="h-72 rounded-xl" />
            ))}
          </div>
        ) : models.data?.length === 0 ? (
          <Card className="px-5 text-sm text-muted-foreground">Chưa có mô hình nào được cấu hình.</Card>
        ) : (
          <div className="grid items-stretch gap-4 lg:grid-cols-2">
            {models.data?.map((m) => <ModelCard key={m.id} model={m} />)}
          </div>
        )}
      </section>
    </div>
  );
}
