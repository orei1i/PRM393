// src/app/(admin)/comments/page.tsx
"use client";

import * as React from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { MessageSquare, RefreshCw, Search } from "lucide-react";

import { PageHeader } from "@/components/admin/page-header";
import { EmptyState, ErrorState } from "@/components/admin/states";
import { CommentDrawer } from "@/components/comments/comment-drawer";
import { CommentTable } from "@/components/comments/comment-table";
import { FilterChip } from "@/components/content/filter-chip";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/form-controls";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useComments } from "@/lib/hooks/use-admin";
import { formatNumber } from "@/lib/utils";
import type { AdminComment, CommentView } from "@/types/admin";

const VIEWS: { value: CommentView; label: string }[] = [
  { value: "all", label: "Tất cả" },
  { value: "reported", label: "Bị báo cáo" },
  { value: "hidden", label: "Đã ẩn" },
];

const isView = (v: string | null): v is CommentView => VIEWS.some((x) => x.value === v);

export default function CommentsPage() {
  return (
    <React.Suspense fallback={null}>
      <CommentsScreen />
    </React.Suspense>
  );
}

function CommentsScreen() {
  const params = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();
  const viewParam = params.get("view");
  const authorId = params.get("author") || undefined;
  const postId = params.get("post") || undefined;

  const [view, setView] = React.useState<CommentView>(() => (isView(viewParam) ? viewParam : "all"));
  const [searchInput, setSearchInput] = React.useState("");
  const search = React.useDeferredValue(searchInput);
  const [selected, setSelected] = React.useState<AdminComment | null>(null);
  const [authorName, setAuthorName] = React.useState<string | null>(null);
  const [postTitle, setPostTitle] = React.useState<string | null>(null);

  React.useEffect(() => {
    if (isView(viewParam)) setView(viewParam);
  }, [viewParam]);

  const query = React.useMemo(() => ({ view, search, authorId, postId }), [view, search, authorId, postId]);
  const comments = useComments(query);

  // Names for the filter chips, remembered once seen.
  React.useEffect(() => {
    if (!authorId) setAuthorName(null);
    else {
      const match = comments.data?.find((c) => c.author.id === authorId);
      if (match) setAuthorName(match.author.fullName);
    }
    if (!postId) setPostTitle(null);
    else {
      const match = comments.data?.find((c) => c.postId === postId);
      if (match) setPostTitle(match.postTitle);
    }
  }, [authorId, postId, comments.data]);

  // Keep the drawer in sync with refetched rows.
  const selectedId = selected?.id ?? null;
  React.useEffect(() => {
    if (!selectedId || !comments.data) return;
    const fresh = comments.data.find((c) => c.id === selectedId);
    if (fresh) setSelected((current) => (current && current !== fresh ? fresh : current));
  }, [comments.data, selectedId]);

  function clearParam(name: "author" | "post") {
    const next = new URLSearchParams(params.toString());
    next.delete(name);
    const rest = next.toString();
    router.replace(rest ? `${pathname}?${rest}` : pathname, { scroll: false });
  }

  const filtered = search.trim().length > 0 || Boolean(authorId) || Boolean(postId);

  return (
    <div className="flex flex-col gap-6">
      <PageHeader
        title="Quản lý bình luận"
        description="Bình luận từ ứng dụng di động. Ẩn bình luận vi phạm hoặc xoá vĩnh viễn."
        actions={
          <Button variant="outline" onClick={() => comments.refetch()} disabled={comments.isFetching}>
            <RefreshCw className={comments.isFetching ? "animate-spin" : undefined} aria-hidden />
            Làm mới
          </Button>
        }
      />

      <Card className="gap-0 py-0">
        <div className="flex flex-wrap items-center gap-3 border-b p-4">
          <Tabs value={view} onValueChange={(v) => setView(v as CommentView)} className="w-full min-w-0 max-w-full sm:w-auto">
            <TabsList className="max-w-full justify-start overflow-x-auto">
              {VIEWS.map((v) => (
                <TabsTrigger key={v.value} value={v.value}>
                  {v.label}
                </TabsTrigger>
              ))}
            </TabsList>
          </Tabs>
          <div className="relative w-full sm:ml-auto sm:w-72">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
            <Input
              type="search"
              value={searchInput}
              onChange={(e) => setSearchInput(e.target.value)}
              placeholder="Tìm nội dung, tác giả, bài viết…"
              aria-label="Tìm bình luận"
              className="pl-9"
            />
          </div>
          {(authorId || postId) && (
            <div className="flex w-full flex-wrap items-center gap-2">
              {authorId && <FilterChip label="Tác giả" value={authorName ?? authorId} onRemove={() => clearParam("author")} />}
              {postId && <FilterChip label="Bài viết" value={postTitle ?? postId} onRemove={() => clearParam("post")} />}
            </div>
          )}
          <p className="w-full text-sm text-muted-foreground sm:w-auto" aria-live="polite">
            {comments.data ? `${formatNumber(comments.data.length)} bình luận` : "Đang tải…"}
          </p>
        </div>

        {comments.isError && !comments.data ? (
          <ErrorState error={comments.error} onRetry={() => comments.refetch()} title="Chưa tải được bình luận" />
        ) : comments.data?.length === 0 ? (
          <EmptyState
            icon={MessageSquare}
            title="Không có bình luận khớp bộ lọc"
            description={
              view === "reported"
                ? "Bình luận bị người dùng báo cáo sẽ xuất hiện ở đây."
                : filtered
                  ? "Thử bỏ bớt từ khoá hoặc bộ lọc."
                  : undefined
            }
            action={
              filtered ? (
                <Button
                  variant="outline"
                  onClick={() => {
                    setSearchInput("");
                    router.replace(pathname, { scroll: false });
                  }}
                >
                  Xoá bộ lọc
                </Button>
              ) : undefined
            }
          />
        ) : (
          <div className={comments.isFetching && !comments.isLoading ? "opacity-60 transition-opacity" : undefined}>
            <CommentTable comments={comments.data} isLoading={comments.isLoading} selectedId={selectedId} onSelect={setSelected} />
          </div>
        )}
      </Card>

      <CommentDrawer comment={selected} onOpenChange={(open) => !open && setSelected(null)} onCommentChange={setSelected} />
    </div>
  );
}
