// src/app/(admin)/content/page.tsx
"use client";

import * as React from "react";
import { useSearchParams } from "next/navigation";
import { FileText, RefreshCw, Search } from "lucide-react";

import { PageHeader } from "@/components/admin/page-header";
import { EmptyState, ErrorState } from "@/components/admin/states";
import { ContentDrawer } from "@/components/content/content-drawer";
import { ContentTable } from "@/components/content/content-table";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input, NativeSelect } from "@/components/ui/form-controls";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useContent } from "@/lib/hooks/use-admin";
import { CONTENT_KIND_LABEL, type ContentItem, type ContentKind, type ContentView } from "@/types/admin";

const VIEWS: { value: ContentView; label: string }[] = [
  { value: "all", label: "Tất cả" },
  { value: "reported", label: "Bị báo cáo" },
  { value: "hidden", label: "Đã ẩn" },
  { value: "pinned", label: "Đã ghim" },
];

const isView = (v: string | null): v is ContentView => VIEWS.some((x) => x.value === v);
const isKind = (v: string | null): v is ContentKind => v !== null && v in CONTENT_KIND_LABEL;

export default function ContentPage() {
  return (
    <React.Suspense fallback={null}>
      <ContentScreen />
    </React.Suspense>
  );
}

function ContentScreen() {
  const params = useSearchParams();
  const [view, setView] = React.useState<ContentView>(() => (isView(params.get("view")) ? (params.get("view") as ContentView) : "all"));
  const [kind, setKind] = React.useState<ContentKind | "all">(() => (isKind(params.get("kind")) ? (params.get("kind") as ContentKind) : "all"));
  const [searchInput, setSearchInput] = React.useState("");
  const search = React.useDeferredValue(searchInput);
  const [selected, setSelected] = React.useState<ContentItem | null>(null);

  const query = React.useMemo(() => ({ view, kind, search }), [view, kind, search]);
  const content = useContent(query);

  // Reflect hide / pin / retry results in the open drawer.
  const selectedId = selected?.id ?? null;
  React.useEffect(() => {
    if (!selectedId || !content.data) return;
    const fresh = content.data.find((c) => c.id === selectedId);
    if (fresh) setSelected((current) => (current && current !== fresh ? fresh : current));
  }, [content.data, selectedId]);

  return (
    <div className="flex flex-col gap-6">
      <PageHeader
        title="Quản lý nội dung"
        description="Bài viết, công thức và video người dùng đăng từ ứng dụng di động."
        actions={
          <Button variant="outline" onClick={() => content.refetch()} disabled={content.isFetching}>
            <RefreshCw className={content.isFetching ? "animate-spin" : undefined} aria-hidden />
            Làm mới
          </Button>
        }
      />

      <Card className="gap-0 py-0">
        <div className="flex flex-wrap items-center gap-3 border-b p-4">
          <Tabs value={view} onValueChange={(v) => setView(v as ContentView)} className="max-w-full">
            <TabsList className="max-w-full justify-start overflow-x-auto">
              {VIEWS.map((v) => (
                <TabsTrigger key={v.value} value={v.value}>
                  {v.label}
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
              placeholder="Tìm tiêu đề, tác giả…"
              aria-label="Tìm bài viết"
              className="pl-9"
            />
          </div>
          <NativeSelect
            aria-label="Lọc theo loại"
            value={kind}
            onChange={(e) => setKind(e.target.value as ContentKind | "all")}
            className="w-full sm:w-44"
          >
            <option value="all">Tất cả loại</option>
            {(Object.keys(CONTENT_KIND_LABEL) as ContentKind[]).map((k) => (
              <option key={k} value={k}>
                {CONTENT_KIND_LABEL[k]}
              </option>
            ))}
          </NativeSelect>
        </div>

        {content.isError && !content.data ? (
          <ErrorState error={content.error} onRetry={() => content.refetch()} />
        ) : content.data?.length === 0 ? (
          <EmptyState
            icon={FileText}
            title={view === "reported" ? "Không còn bài bị báo cáo" : "Không có bài viết khớp bộ lọc"}
            description={view === "reported" ? "Báo cáo mới từ ứng dụng sẽ xuất hiện ở đây." : "Thử đổi loại hoặc bỏ bớt từ khoá."}
          />
        ) : (
          <div className={content.isFetching && !content.isLoading ? "opacity-60 transition-opacity" : undefined}>
            <ContentTable items={content.data} isLoading={content.isLoading} selectedId={selectedId} onSelect={setSelected} />
          </div>
        )}
      </Card>

      <ContentDrawer item={selected} onOpenChange={(open) => !open && setSelected(null)} />
    </div>
  );
}
