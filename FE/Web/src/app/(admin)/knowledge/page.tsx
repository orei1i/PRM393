// src/app/(admin)/knowledge/page.tsx
"use client";

import * as React from "react";
import { Library, RefreshCw, Search, Upload } from "lucide-react";

import { PageHeader } from "@/components/admin/page-header";
import { EmptyState, ErrorState } from "@/components/admin/states";
import { KnowledgeDrawer } from "@/components/knowledge/knowledge-drawer";
import { KnowledgeTable } from "@/components/knowledge/knowledge-table";
import { WhoUploadDialog } from "@/components/knowledge/who-upload-dialog";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input, NativeSelect } from "@/components/ui/form-controls";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useKnowledgeCounts, useKnowledgeDocs } from "@/lib/hooks/use-knowledge";
import { KNOWLEDGE_SOURCE_LABEL, KNOWLEDGE_SOURCES, type KnowledgeDoc, type KnowledgeDocStatus, type KnowledgeSource } from "@/types/knowledge";

type StatusTab = KnowledgeDocStatus | "all";

const TABS: { value: StatusTab; label: string }[] = [
  { value: "Pending", label: "Chờ duyệt" },
  { value: "Approved", label: "Đã duyệt" },
  { value: "Rejected", label: "Bị từ chối" },
  { value: "all", label: "Tất cả" },
];

export default function KnowledgePage() {
  const [status, setStatus] = React.useState<StatusTab>("Pending");
  const [source, setSource] = React.useState<KnowledgeSource | "all">("all");
  const [searchInput, setSearchInput] = React.useState("");
  const search = React.useDeferredValue(searchInput);
  const [selected, setSelected] = React.useState<KnowledgeDoc | null>(null);
  const [uploadOpen, setUploadOpen] = React.useState(false);

  const query = React.useMemo(() => ({ status, source, search }), [status, source, search]);
  const docs = useKnowledgeDocs(query);
  const counts = useKnowledgeCounts();

  const selectedId = selected?.id ?? null;
  React.useEffect(() => {
    if (!selectedId || !docs.data) return;
    const fresh = docs.data.find((d) => d.id === selectedId);
    if (fresh) setSelected((current) => (current && current !== fresh ? fresh : current));
  }, [docs.data, selectedId]);

  const countFor = (tab: StatusTab) => {
    if (!counts.data) return "–";
    return tab === "all" ? counts.data.Pending + counts.data.Approved + counts.data.Rejected : counts.data[tab];
  };

  const filtered = source !== "all" || search.trim().length > 0;

  return (
    <div className="flex flex-col gap-6">
      <PageHeader
        title="Tài liệu kiến thức"
        description="Nguồn cho chatbot RAG. Tài liệu của chuyên gia chỉ được dùng sau khi duyệt."
        actions={
          <>
            <Button variant="outline" onClick={() => docs.refetch()} disabled={docs.isFetching}>
              <RefreshCw className={docs.isFetching ? "animate-spin" : undefined} aria-hidden />
              Làm mới
            </Button>
            <Button onClick={() => setUploadOpen(true)}>
              <Upload aria-hidden />
              Tải tài liệu WHO
            </Button>
          </>
        }
      />

      <Card className="gap-0 py-0">
        <div className="flex flex-wrap items-center gap-3 border-b p-4">
          <Tabs value={status} onValueChange={(v) => setStatus(v as StatusTab)} className="w-full min-w-0 max-w-full lg:w-auto">
            <TabsList className="max-w-full justify-start overflow-x-auto">
              {TABS.map((t) => (
                <TabsTrigger key={t.value} value={t.value}>
                  {t.label}
                  <span className="rounded-full bg-muted px-1.5 font-mono text-[11px] tabular">{countFor(t.value)}</span>
                </TabsTrigger>
              ))}
            </TabsList>
          </Tabs>
          <div className="relative w-full sm:ml-auto sm:w-64">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
            <Input
              type="search"
              value={searchInput}
              onChange={(e) => setSearchInput(e.target.value)}
              placeholder="Tìm tiêu đề, chuyên gia…"
              aria-label="Tìm tài liệu"
              className="pl-9"
            />
          </div>
          <NativeSelect
            aria-label="Lọc theo nguồn"
            value={source}
            onChange={(e) => setSource(e.target.value as KnowledgeSource | "all")}
            className="w-full sm:w-44"
          >
            <option value="all">Tất cả nguồn</option>
            {KNOWLEDGE_SOURCES.map((s) => (
              <option key={s} value={s}>
                {KNOWLEDGE_SOURCE_LABEL[s]}
              </option>
            ))}
          </NativeSelect>
        </div>

        {docs.isError && !docs.data ? (
          <ErrorState error={docs.error} onRetry={() => docs.refetch()} title="Chưa tải được tài liệu" />
        ) : docs.data?.length === 0 ? (
          <EmptyState
            icon={Library}
            title={status === "Pending" && !filtered ? "Không còn tài liệu chờ duyệt" : "Không có tài liệu khớp bộ lọc"}
            description={
              status === "Pending" && !filtered ? "Tài liệu chuyên gia gửi từ ứng dụng sẽ xuất hiện ở đây." : "Thử đổi nguồn hoặc bỏ bớt từ khoá."
            }
          />
        ) : (
          <div className={docs.isFetching && !docs.isLoading ? "opacity-60 transition-opacity" : undefined}>
            <KnowledgeTable docs={docs.data} isLoading={docs.isLoading} selectedId={selectedId} onSelect={setSelected} />
          </div>
        )}
      </Card>

      <KnowledgeDrawer doc={selected} onOpenChange={(open) => !open && setSelected(null)} onDocChange={setSelected} />
      <WhoUploadDialog
        open={uploadOpen}
        onOpenChange={setUploadOpen}
        onCreated={() => {
          // The new WHO doc is already approved: show it where it landed.
          setStatus("Approved");
          setSource("all");
          setSearchInput("");
        }}
      />
    </div>
  );
}
