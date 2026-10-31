// src/components/content/content-table.tsx
"use client";

import { CircleCheck, CircleX, EyeOff, Flag, Hourglass, Image as ImageIcon, MapPin, Pin, Sparkles, TriangleAlert, Video } from "lucide-react";

import { InitialsAvatar } from "@/components/admin/initials-avatar";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/form-controls";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { isMock } from "@/lib/backend_modules";
import { formatAge, formatNumber } from "@/lib/utils";
import { CONTENT_KIND_LABEL, POST_STATUS_LABEL, VIDEO_AI_STATUS_LABEL, type ContentItem, type PostStatus } from "@/types/admin";

/** posts.status — icon + label, never colour alone. */
export function PostStatusBadge({ status }: { status: PostStatus }) {
  switch (status) {
    case "Published":
      return (
        <Badge variant="sprout">
          <CircleCheck aria-hidden />
          {POST_STATUS_LABEL[status]}
        </Badge>
      );
    case "Pending":
      return (
        <Badge variant="ochre">
          <Hourglass aria-hidden />
          {POST_STATUS_LABEL[status]}
        </Badge>
      );
    case "Rejected":
      return (
        <Badge variant="secondary">
          <CircleX aria-hidden />
          {POST_STATUS_LABEL[status]}
        </Badge>
      );
  }
}

/** The single attachment (posts.media_type): "Có video" / "Có ảnh". */
export function MediaBadge({ item }: { item: ContentItem }) {
  if (item.mediaType === "Text") return null;
  return item.mediaType === "Video" ? (
    <Badge variant="outline">
      <Video aria-hidden />
      Có video
    </Badge>
  ) : (
    <Badge variant="outline">
      <ImageIcon aria-hidden />
      Có ảnh
    </Badge>
  );
}

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

/** The backend's post list has no report count: "—", never a made-up 0. */
const REPORTS_KNOWN = isMock("content");

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
    <Table className="min-w-[980px]">
      <TableHeader>
        <TableRow className="hover:bg-transparent">
          <TableHead className="w-[38%]">Bài viết</TableHead>
          <TableHead>Loại</TableHead>
          <TableHead>Trạng thái</TableHead>
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
                <TableCell colSpan={7}>
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
                    {item.status === "Pending" && item.aiFlag ? (
                      <p className="line-clamp-1 text-xs text-ai-text">AI: {item.aiFlag.reason}</p>
                    ) : (
                      <p className="line-clamp-1 text-xs text-muted-foreground">{item.excerpt}</p>
                    )}
                    {item.restaurant && (
                      <p className="inline-flex items-center gap-1 text-xs text-muted-foreground">
                        <MapPin className="size-3" aria-hidden />
                        tại {item.restaurant.name}
                      </p>
                    )}
                  </div>
                </TableCell>
                <TableCell>
                  <div className="flex flex-col items-start gap-1">
                    <Badge variant="outline">{CONTENT_KIND_LABEL[item.kind]}</Badge>
                    <MediaBadge item={item} />
                    <VideoAiBadge item={item} />
                  </div>
                </TableCell>
                <TableCell>
                  <div className="flex flex-col items-start gap-1">
                    <PostStatusBadge status={item.status} />
                    {item.status === "Pending" && item.aiFlag && (
                      <span className="inline-flex items-center gap-1 font-mono text-xs text-ai-text tabular">
                        <Sparkles className="size-3" aria-hidden />
                        AI {item.aiFlag.score.toFixed(2)}
                      </span>
                    )}
                  </div>
                </TableCell>
                <TableCell>
                  <div className="flex items-center gap-2">
                    <InitialsAvatar name={item.author.fullName} verified={item.author.isVerifiedChef} className="size-7 text-[10px]" />
                    <span className="max-w-36 truncate">{item.author.fullName}</span>
                  </div>
                </TableCell>
                <TableCell className="text-right">
                  {!REPORTS_KNOWN ? (
                    <span className="font-mono text-muted-foreground tabular">—</span>
                  ) : item.reportCount > 0 ? (
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
