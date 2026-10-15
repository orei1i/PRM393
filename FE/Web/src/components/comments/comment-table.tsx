// src/components/comments/comment-table.tsx
"use client";

import { Eye, EyeOff, Flag } from "lucide-react";

import { InitialsAvatar } from "@/components/admin/initials-avatar";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/form-controls";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { formatAge } from "@/lib/utils";
import { COMMENT_STATUS_LABEL, type AdminComment, type CommentStatus } from "@/types/admin";

export const timeAgo = (iso: string) => {
  const age = formatAge(iso);
  return age === "vừa xong" ? age : `${age} trước`;
};

export function CommentStatusBadge({ status }: { status: CommentStatus }) {
  return status === "Visible" ? (
    <Badge variant="sprout">
      <Eye aria-hidden />
      {COMMENT_STATUS_LABEL[status]}
    </Badge>
  ) : (
    <Badge variant="secondary">
      <EyeOff aria-hidden />
      {COMMENT_STATUS_LABEL[status]}
    </Badge>
  );
}

export function CommentTable({
  comments,
  isLoading,
  selectedId,
  onSelect,
}: {
  comments: AdminComment[] | undefined;
  isLoading: boolean;
  selectedId: string | null;
  onSelect: (comment: AdminComment) => void;
}) {
  return (
    <Table className="min-w-[920px]">
      <TableHeader>
        <TableRow className="hover:bg-transparent">
          <TableHead className="w-[36%]">Bình luận</TableHead>
          <TableHead>Tác giả</TableHead>
          <TableHead>Bài viết</TableHead>
          <TableHead className="text-right">Báo cáo</TableHead>
          <TableHead>Trạng thái</TableHead>
          <TableHead>Thời gian</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {isLoading
          ? Array.from({ length: 7 }, (_, i) => (
              <TableRow key={i}>
                <TableCell colSpan={6}>
                  <Skeleton className="h-10" />
                </TableCell>
              </TableRow>
            ))
          : comments?.map((c) => (
              <TableRow
                key={c.id}
                data-state={c.id === selectedId ? "selected" : undefined}
                tabIndex={0}
                onClick={() => onSelect(c)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault();
                    onSelect(c);
                  }
                }}
                className="cursor-pointer"
                aria-label={`Mở bình luận của ${c.author.fullName}`}
              >
                <TableCell className="whitespace-normal">
                  <p className={c.status === "Hidden" ? "line-clamp-2 text-muted-foreground" : "line-clamp-2"}>{c.content}</p>
                  {c.updatedAt && <span className="text-xs text-muted-foreground">(đã sửa)</span>}
                </TableCell>
                <TableCell>
                  <div className="flex items-center gap-2">
                    <InitialsAvatar name={c.author.fullName} className="size-7 text-[10px]" />
                    <span className="max-w-36 truncate">{c.author.fullName}</span>
                  </div>
                </TableCell>
                <TableCell className="whitespace-normal">
                  <span className="line-clamp-2 max-w-56 text-muted-foreground">{c.postTitle}</span>
                </TableCell>
                <TableCell className="text-right">
                  {c.reportCount > 0 ? (
                    <span className="inline-flex items-center gap-1 font-mono font-semibold text-ochre-text tabular">
                      <Flag className="size-3.5" aria-hidden />
                      {c.reportCount}
                    </span>
                  ) : (
                    <span className="font-mono text-muted-foreground tabular">0</span>
                  )}
                </TableCell>
                <TableCell>
                  <CommentStatusBadge status={c.status} />
                </TableCell>
                <TableCell className="whitespace-nowrap text-muted-foreground">{timeAgo(c.createdAt)}</TableCell>
              </TableRow>
            ))}
      </TableBody>
    </Table>
  );
}
