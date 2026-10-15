// src/components/content/content-table.tsx
"use client";

import { EyeOff, Flag, Pin, Sparkles, TriangleAlert } from "lucide-react";

import { InitialsAvatar } from "@/components/admin/initials-avatar";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/form-controls";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { formatAge, formatNumber } from "@/lib/utils";
import { CONTENT_KIND_LABEL, VIDEO_AI_STATUS_LABEL, type ContentItem } from "@/types/admin";

export function VideoAiBadge({ item }: { item: ContentItem }) {
  if (!item.video) return null;
  const status = item.video.aiStatus;
  if (status === "failed") {
    return (
      <Badge variant="ochre">
        <TriangleAlert aria-hidden />
        {VIDEO_AI_STATUS_LABEL[status]}
      </Badge>
    );
  }
  return (
    <Badge variant="ai">
      <Sparkles aria-hidden />
      {VIDEO_AI_STATUS_LABEL[status]}
    </Badge>
  );
}

export function ContentTable({
  items,
  isLoading,
  selectedId,
  onSelect,
}: {
  items: ContentItem[] | undefined;
  isLoading: boolean;
  selectedId: string | null;
  onSelect: (item: ContentItem) => void;
}) {
  return (
    <Table className="min-w-[880px]">
      <TableHeader>
        <TableRow className="hover:bg-transparent">
          <TableHead className="w-[42%]">Bài viết</TableHead>
          <TableHead>Loại</TableHead>
          <TableHead>Tác giả</TableHead>
          <TableHead className="text-right">Báo cáo</TableHead>
          <TableHead className="text-right">Thích · Bình luận</TableHead>
          <TableHead>Đăng</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {isLoading
          ? Array.from({ length: 6 }, (_, i) => (
              <TableRow key={i}>
                <TableCell colSpan={6}>
                  <Skeleton className="h-10" />
                </TableCell>
              </TableRow>
            ))
          : items?.map((item) => (
              <TableRow
                key={item.id}
                data-state={item.id === selectedId ? "selected" : undefined}
                tabIndex={0}
                onClick={() => onSelect(item)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault();
                    onSelect(item);
                  }
                }}
                className="cursor-pointer"
                aria-label={`Mở bài: ${item.title}`}
              >
                <TableCell className="whitespace-normal">
                  <div className="flex flex-col gap-1">
                    <div className="flex flex-wrap items-center gap-1.5">
                      {item.pinned && (
                        <Badge variant="default">
                          <Pin aria-hidden />
                          Đã ghim
                        </Badge>
                      )}
                      {item.hidden && (
                        <Badge variant="secondary">
                          <EyeOff aria-hidden />
                          Đã ẩn
                        </Badge>
                      )}
                      <span className="font-semibold">{item.title}</span>
                    </div>
                    <p className="line-clamp-1 text-xs text-muted-foreground">{item.excerpt}</p>
                  </div>
                </TableCell>
                <TableCell>
                  <div className="flex flex-col items-start gap-1">
                    <Badge variant="outline">{CONTENT_KIND_LABEL[item.kind]}</Badge>
                    <VideoAiBadge item={item} />
                  </div>
                </TableCell>
                <TableCell>
                  <div className="flex items-center gap-2">
                    <InitialsAvatar name={item.author.fullName} verified={item.author.isVerifiedChef} className="size-7 text-[10px]" />
                    <span className="max-w-36 truncate">{item.author.fullName}</span>
                  </div>
                </TableCell>
                <TableCell className="text-right">
                  {item.reportCount > 0 ? (
                    <span className="inline-flex items-center gap-1 font-mono font-semibold text-ochre-text tabular">
                      <Flag className="size-3.5" aria-hidden />
                      {item.reportCount}
                    </span>
                  ) : (
                    <span className="font-mono text-muted-foreground tabular">0</span>
                  )}
                </TableCell>
                <TableCell className="text-right font-mono text-muted-foreground tabular">
                  {formatNumber(item.likeCount)} · {formatNumber(item.commentCount)}
                </TableCell>
                <TableCell className="text-muted-foreground">{formatAge(item.createdAt)} trước</TableCell>
              </TableRow>
            ))}
      </TableBody>
    </Table>
  );
}
