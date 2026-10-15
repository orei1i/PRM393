// src/app/(admin)/content/page.tsx
"use client";

import * as React from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { FileText, RefreshCw, Search } from "lucide-react";
import { toast } from "sonner";

import { PageHeader } from "@/components/admin/page-header";
import { EmptyState, ErrorState } from "@/components/admin/states";
import { ContentDrawer } from "@/components/content/content-drawer";
import { ContentTable } from "@/components/content/content-table";
import { FilterChip } from "@/components/content/filter-chip";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input, NativeSelect } from "@/components/ui/form-controls";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useContent } from "@/lib/hooks/use-admin";
import { CONTENT_KIND_LABEL, type ContentItem, type ContentKind, type ContentView } from "@/types/admin";

const VIEWS: { value: ContentView; label: string }[] = [
  { value: "all", label: "Tất cả" },
  { value: "pending", label: "Chờ duyệt" },
  { value: "reported", label: "Bị báo cáo" },
  { value: "hidden", label: "Đã ẩn" },
  { value: "pinned", label: "Đã ghim" },
  { value: "rejected", label: "Bị từ chối" },
];

const EMPTY: Partial<Record<ContentView, { title: string; description: string }>> = {
  pending: { title: "Không còn bài chờ duyệt", description: "Bài bị AI giữ lại khi đăng sẽ xuất hiện ở đây." },
  reported: { title: "Không còn bài bị báo cáo", description: "Báo cáo mới từ ứng dụng sẽ xuất hiện ở đây." },
  rejected: { title: "Chưa có bài bị từ chối", description: "Bài bị từ chối kèm ghi chú gửi tác giả sẽ nằm ở đây." },
};

const isView = (v: string | null): v is ContentView => VIEWS.some((x) => x.value === v);
const isKind = (v: string | null): v is ContentKind => v !== null && v in CONTENT_KIND_LABEL;

const PENDING_QUERY = { view: "pending", kind: "all", search: "" } as const;

export default function ContentPage() {
  return (
    <React.Suspense fallback={null}>
      <ContentScreen />
    </React.Suspense>
  );
}

function ContentScreen() {
  const params = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();
  const viewParam = params.get("view");
  const kindParam = params.get("kind");
  const authorId = params.get("author") || undefined;
  const openId = params.get("open");

  const [view, setView] = React.useState<ContentView>(() => (isView(viewParam) ? viewParam : "all"));
  const [kind, setKind] = React.useState<ContentKind | "all">(() => (isKind(kindParam) ? kindParam : "all"));
  const [searchInput, setSearchInput] = React.useState("");
  const search = React.useDeferredValue(searchInput);
  const [selected, setSelected] = React.useState<ContentItem | null>(null);
  /** Post id from `?open=` waiting for the unfiltered list to load. */
  const [pendingOpen, setPendingOpen] = React.useState<string | null>(null);
  const [authorName, setAuthorName] = React.useState<string | null>(null);

  // Links into this page while it is already open (overview queue, sidebar) still apply.
  React.useEffect(() => {
    if (isView(viewParam)) setView(viewParam);
  }, [viewParam]);
  React.useEffect(() => {
    if (isKind(kindParam)) setKind(kindParam);
  }, [kindParam]);

  // `?open=<id>`: show everything, then open that post's drawer once it is in the list.
  React.useEffect(() => {
    if (!openId) return;
    setView("all");
    setKind("all");
    setSearchInput("");
    setPendingOpen(openId);
    router.replace(pathname, { scroll: false });
  }, [openId, pathname, router]);

  const query = React.useMemo(() => ({ view, kind, search, authorId }), [view, kind, search, authorId]);
  const content = useContent(query);
  const pending = useContent(PENDING_QUERY);

  React.useEffect(() => {
    if (!pendingOpen || view !== "all" || kind !== "all" || search !== "" || authorId) return;
    if (!content.data || content.isPlaceholderData) return;
    const found = content.data.find((c) => c.id === pendingOpen);
    if (found) setSelected(found);
    else toast.error("Không tìm thấy bài viết", { description: "Bài có thể đã bị xoá." });
    setPendingOpen(null);
  }, [pendingOpen, view, kind, search, authorId, content.data, content.isPlaceholderData]);

  // Remember the author's name for the chip, even when the current tab has none of their posts.
  React.useEffect(() => {
    if (!authorId) {
      setAuthorName(null);
      return;
    }
    const match = content.data?.find((c) => c.author.id === authorId) ?? pending.data?.find((c) => c.author.id === authorId);
    if (match) setAuthorName(match.author.fullName);
  }, [authorId, content.data, pending.data]);

  function clearAuthor() {
    const next = new URLSearchParams(params.toString());
    next.delete("author");
    const rest = next.toString();
    router.replace(rest ? `${pathname}?${rest}` : pathname, { scroll: false });
  }

  // Reflect hide / pin / retry results in the open drawer.
  const selectedId = selected?.id ?? null;
  React.useEffect(() => {
    if (!selectedId || !content.data) return;
    const fresh = content.data.find((c) => c.id === selectedId);
    if (fresh) setSelected((current) => (current && current !== fresh ? fresh : current));
  }, [content.data, selectedId]);

  const empty = EMPTY[view] ?? {
    title: authorId ? "Thành viên này chưa có bài khớp bộ lọc" : "Không có bài viết khớp bộ lọc",
    description: "Thử đổi loại hoặc bỏ bớt từ khoá.",
  };

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
          <Tabs value={view} onValueChange={(v) => setView(v as ContentView)} className="w-full min-w-0 max-w-full xl:w-auto">
            <TabsList className="max-w-full justify-start overflow-x-auto">
              {VIEWS.map((v) => (
                <TabsTrigger key={v.value} value={v.value}>
                  {v.label}
                  {v.value === "pending" && (
                    <span className="rounded-full bg-muted px-1.5 font-mono text-[11px] tabular">{pending.data?.length ?? "–"}</span>
                  )}
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
          {authorId && <FilterChip label="Tác giả" value={authorName ?? authorId} onRemove={clearAuthor} />}
        </div>

        {content.isError && !content.data ? (
          <ErrorState error={content.error} onRetry={() => content.refetch()} />
        ) : content.data?.length === 0 ? (
          <EmptyState icon={FileText} title={empty.title} description={empty.description} />
        ) : (
          <div className={content.isFetching && !content.isLoading ? "opacity-60 transition-opacity" : undefined}>
            <ContentTable items={content.data} isLoading={content.isLoading} selectedId={selectedId} onSelect={setSelected} />
          </div>
        )}
      </Card>

      <ContentDrawer item={selected} onOpenChange={(open) => !open && setSelected(null)} onItemChange={setSelected} />
    </div>
  );
}
