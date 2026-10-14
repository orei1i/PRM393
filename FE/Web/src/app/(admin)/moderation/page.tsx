// src/app/(admin)/moderation/page.tsx
"use client";

import * as React from "react";
import { RefreshCw, Search } from "lucide-react";

import { InspectionDrawer } from "@/components/moderation/inspection-drawer";
import { FlagQueueTable } from "@/components/moderation/flag-queue-table";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input, NativeSelect } from "@/components/ui/form-controls";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { describeError } from "@/lib/api_error";
import { useFlagCounts, useFlagQueue } from "@/lib/hooks/use-moderation";
import { FLAG_CATEGORY_LABEL, type AiFlag, type FlagCategory, type FlagStatus } from "@/types/moderation";

const STATUS_TABS: { value: FlagStatus; label: string }[] = [
  { value: "pending", label: "Chờ duyệt" },
  { value: "escalated", label: "Đã chuyển cấp trên" },
  { value: "resolved", label: "Đã xử lý" },
];

export default function ModerationPage() {
  const [status, setStatus] = React.useState<FlagStatus>("pending");
  const [category, setCategory] = React.useState<FlagCategory | "all">("all");
  const [searchInput, setSearchInput] = React.useState("");
  const search = React.useDeferredValue(searchInput);
  const [selected, setSelected] = React.useState<AiFlag | null>(null);

  const query = React.useMemo(() => ({ status, category, search }), [status, category, search]);
  const flags = useFlagQueue(query);
  const counts = useFlagCounts();

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-2xl font-extrabold tracking-tight">Kiểm duyệt nội dung</h1>
          <p className="text-sm text-muted-foreground">
            AI gắn cờ, con người quyết định. Hàng đợi sắp xếp mục chờ lâu nhất lên đầu.
          </p>
        </div>
        <Button variant="outline" onClick={() => flags.refetch()} disabled={flags.isFetching}>
          <RefreshCw className={flags.isFetching ? "animate-spin" : undefined} aria-hidden />
          Làm mới
        </Button>
      </div>

      <Card className="gap-0 py-0">
        <div className="flex flex-wrap items-center gap-3 border-b p-4">
          <Tabs value={status} onValueChange={(v) => setStatus(v as FlagStatus)} className="max-w-full">
            <TabsList className="max-w-full justify-start overflow-x-auto">
              {STATUS_TABS.map((tab) => (
                <TabsTrigger key={tab.value} value={tab.value}>
                  {tab.label}
                  <span className="rounded-full bg-muted px-1.5 font-mono text-[11px] tabular">{counts.data?.[tab.value] ?? "–"}</span>
                </TabsTrigger>
              ))}
            </TabsList>
          </Tabs>

          <div className="relative ml-auto w-full sm:w-64">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
            <Input
              type="search"
              value={searchInput}
              onChange={(e) => setSearchInput(e.target.value)}
              placeholder="Tìm nội dung, @tác giả…"
              aria-label="Tìm trong hàng đợi"
              className="pl-9"
            />
          </div>
          <NativeSelect
            aria-label="Lọc theo lý do"
            value={category}
            onChange={(e) => setCategory(e.target.value as FlagCategory | "all")}
            className="w-full sm:w-56"
          >
            <option value="all">Tất cả lý do</option>
            {(Object.keys(FLAG_CATEGORY_LABEL) as FlagCategory[]).map((c) => (
              <option key={c} value={c}>
                {FLAG_CATEGORY_LABEL[c]}
              </option>
            ))}
          </NativeSelect>
        </div>

        {flags.isError ? (
          <div role="alert" className="flex flex-col items-center gap-3 px-6 py-14 text-center">
            <p className="font-bold">Chưa tải được hàng đợi</p>
            <p className="text-sm text-muted-foreground">{describeError(flags.error)}</p>
            <Button variant="outline" onClick={() => flags.refetch()}>
              Thử lại
            </Button>
          </div>
        ) : (
          <FlagQueueTable
            flags={flags.data}
            isLoading={flags.isLoading}
            selectedId={selected?.id ?? null}
            onSelect={setSelected}
          />
        )}
      </Card>

      <InspectionDrawer flag={selected} onOpenChange={(open) => !open && setSelected(null)} />
    </div>
  );
}
