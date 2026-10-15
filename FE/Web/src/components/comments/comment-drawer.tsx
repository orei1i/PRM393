// src/components/comments/comment-drawer.tsx
"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { ExternalLink, Eye, EyeOff, Flag, Trash2 } from "lucide-react";
import { toast } from "sonner";

import { InitialsAvatar } from "@/components/admin/initials-avatar";
import { Button } from "@/components/ui/button";
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogTitle } from "@/components/ui/dialog";
import { Label, Textarea } from "@/components/ui/form-controls";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { describeError } from "@/lib/api_error";
import { useCommentAction } from "@/lib/hooks/use-admin";
import type { AdminComment } from "@/types/admin";

import { CommentStatusBadge, timeAgo } from "./comment-table";

export function CommentDrawer({
  comment,
  onOpenChange,
  onCommentChange,
}: {
  comment: AdminComment | null;
  onOpenChange: (open: boolean) => void;
  onCommentChange: (comment: AdminComment) => void;
}) {
  return (
    <Sheet open={comment !== null} onOpenChange={onOpenChange}>
      <SheetContent className="gap-0 overflow-y-auto sm:max-w-lg">
        {comment && <Detail key={comment.id} comment={comment} onClose={() => onOpenChange(false)} onCommentChange={onCommentChange} />}
      </SheetContent>
    </Sheet>
  );
}

function Detail({
  comment,
  onClose,
  onCommentChange,
}: {
  comment: AdminComment;
  onClose: () => void;
  onCommentChange: (comment: AdminComment) => void;
}) {
  const router = useRouter();
  const action = useCommentAction();
  const [confirmDelete, setConfirmDelete] = React.useState(false);
  const [reason, setReason] = React.useState("");
  const reasonId = React.useId();

  function toggleVisibility() {
    const next = comment.status === "Visible" ? "hide" : "unhide";
    action.mutate(
      { id: comment.id, action: next },
      {
        onSuccess: (updated) => {
          toast.success(next === "hide" ? "Đã ẩn bình luận" : "Đã hiện lại bình luận");
          if (updated) onCommentChange(updated);
        },
        onError: (e) => toast.error("Chưa thực hiện được", { description: describeError(e) }),
      },
    );
  }

  function remove() {
    action.mutate(
      { id: comment.id, action: "delete", reason: reason.trim() || undefined },
      {
        onSuccess: () => {
          toast.success("Đã xoá bình luận");
          setConfirmDelete(false);
          onClose();
        },
        onError: (e) => toast.error("Chưa xoá được bình luận", { description: describeError(e) }),
      },
    );
  }

  return (
    <>
      <SheetHeader className="border-b">
        <div className="flex flex-wrap gap-1.5">
          <CommentStatusBadge status={comment.status} />
        </div>
        <SheetTitle className="mt-2">Bình luận của {comment.author.fullName}</SheetTitle>
        <SheetDescription>
          {timeAgo(comment.createdAt)}
          {comment.updatedAt ? ` · đã sửa ${timeAgo(comment.updatedAt)}` : ""}
        </SheetDescription>
      </SheetHeader>

      <div className="flex flex-col gap-5 p-5">
        <div className="flex items-center gap-3">
          <InitialsAvatar name={comment.author.fullName} />
          <p className="font-semibold">{comment.author.fullName}</p>
        </div>

        <p className="whitespace-pre-wrap rounded-lg bg-muted px-4 py-3 text-sm leading-relaxed">{comment.content}</p>

        {comment.reportCount > 0 && (
          <p className="flex items-start gap-2 rounded-lg border border-ochre-border bg-ochre-soft px-3 py-2 text-sm text-ochre-text">
            <Flag className="mt-0.5 size-4 shrink-0" aria-hidden />
            {comment.reportCount} người dùng đã báo cáo bình luận này từ ứng dụng.
          </p>
        )}

        <section aria-label="Bài viết gốc" className="flex flex-col gap-2 rounded-lg border p-3">
          <p className="text-xs font-bold uppercase tracking-wide text-muted-foreground">Bài viết</p>
          <p className="font-semibold leading-snug">{comment.postTitle}</p>
          <Button size="sm" variant="outline" className="w-fit" onClick={() => router.push(`/content?open=${encodeURIComponent(comment.postId)}`)}>
            <ExternalLink aria-hidden />
            Mở bài viết
          </Button>
        </section>

        <div className="flex flex-col gap-2">
          <h3 className="text-sm font-bold">Xử lý</h3>
          <div className="flex flex-wrap gap-2">
            {comment.status === "Visible" ? (
              <Button size="sm" variant="warn" disabled={action.isPending} onClick={toggleVisibility}>
                <EyeOff aria-hidden />
                Ẩn
              </Button>
            ) : (
              <Button size="sm" variant="outline" disabled={action.isPending} onClick={toggleVisibility}>
                <Eye aria-hidden />
                Hiện lại
              </Button>
            )}
            <Button size="sm" variant="destructive" disabled={action.isPending} onClick={() => setConfirmDelete(true)}>
              <Trash2 aria-hidden />
              Xoá
            </Button>
          </div>
          <p className="text-xs text-muted-foreground">Bình luận bị ẩn chỉ tác giả còn thấy; có thể hiện lại bất cứ lúc nào.</p>
        </div>
      </div>

      <Dialog
        open={confirmDelete}
        onOpenChange={(open) => {
          if (action.isPending) return;
          setConfirmDelete(open);
          if (!open) setReason("");
        }}
      >
        <DialogContent>
          <DialogTitle>Xoá bình luận?</DialogTitle>
          <DialogDescription>Bình luận bị xoá vĩnh viễn khỏi bài viết. Nếu chỉ cần gỡ tạm, hãy dùng “Ẩn”.</DialogDescription>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor={reasonId}>Lý do (gửi cho tác giả)</Label>
            <Textarea
              id={reasonId}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="Không bắt buộc. VD: Bình luận quảng cáo bán hàng."
              disabled={action.isPending}
            />
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" disabled={action.isPending}>
                Huỷ
              </Button>
            </DialogClose>
            <Button variant="destructive" disabled={action.isPending} onClick={remove}>
              {action.isPending ? "Đang xoá…" : "Xoá bình luận"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
