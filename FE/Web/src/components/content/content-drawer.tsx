// src/components/content/content-drawer.tsx
"use client";

import * as React from "react";
import { CircleCheck, CircleX, Eye, EyeOff, Pin, PinOff, RotateCcw, Sparkles, Trash2 } from "lucide-react";
import { toast } from "sonner";

import { InitialsAvatar } from "@/components/admin/initials-avatar";
import { ScoreBar } from "@/components/moderation/score-bar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogTitle } from "@/components/ui/dialog";
import { Label, Textarea } from "@/components/ui/form-controls";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { describeError } from "@/lib/api_error";
import { useContentAction, useReviewPost } from "@/lib/hooks/use-admin";
import { formatAge, formatNumber } from "@/lib/utils";
import { CONTENT_KIND_LABEL, type ContentAction, type ContentItem, type PostDecision } from "@/types/admin";
import { FLAG_CATEGORY_LABEL, MIN_AUDIT_NOTE_LENGTH } from "@/types/moderation";

import { PostStatusBadge, VideoAiBadge } from "./content-table";

const ACTION_DONE: Record<ContentAction, string> = {
  hide: "Đã ẩn khỏi bảng tin",
  unhide: "Đã hiện lại trên bảng tin",
  pin: "Đã ghim lên đầu bảng tin",
  unpin: "Đã bỏ ghim",
  delete: "Đã xoá bài viết",
  retry_ai: "Đã gửi video vào hàng chờ AI",
};

const dateTimeVi = new Intl.DateTimeFormat("vi-VN", { hour: "2-digit", minute: "2-digit", day: "2-digit", month: "2-digit", year: "numeric" });

export function ContentDrawer({
  item,
  onOpenChange,
  onItemChange,
}: {
  item: ContentItem | null;
  onOpenChange: (open: boolean) => void;
  /** Called with the server copy after a review, so the drawer shows the decision even once the item leaves the list. */
  onItemChange?: (item: ContentItem) => void;
}) {
  return (
    <Sheet open={item !== null} onOpenChange={onOpenChange}>
      <SheetContent className="gap-0 overflow-y-auto sm:max-w-lg">
        {item && <Detail key={item.id} item={item} onClose={() => onOpenChange(false)} onItemChange={onItemChange} />}
      </SheetContent>
    </Sheet>
  );
}

function Detail({ item, onClose, onItemChange }: { item: ContentItem; onClose: () => void; onItemChange?: (item: ContentItem) => void }) {
  const action = useContentAction();
  const review = useReviewPost();
  const [confirmDelete, setConfirmDelete] = React.useState(false);
  const [approveNote, setApproveNote] = React.useState("");
  const [rejectOpen, setRejectOpen] = React.useState(false);
  const [rejectNote, setRejectNote] = React.useState("");
  const rejectId = React.useId();
  const approveId = React.useId();

  const busy = action.isPending || review.isPending;
  const rejectOk = rejectNote.trim().length >= MIN_AUDIT_NOTE_LENGTH;

  function run(a: ContentAction) {
    action.mutate(
      { id: item.id, action: a },
      {
        onSuccess: () => {
          toast.success(ACTION_DONE[a]);
          if (a === "delete") {
            setConfirmDelete(false);
            onClose();
          }
        },
        onError: (e) => toast.error("Chưa thực hiện được", { description: describeError(e) }),
      },
    );
  }

  function decide(decision: PostDecision) {
    const note = (decision === "Approve" ? approveNote : rejectNote).trim();
    if (decision === "Reject" && note.length < MIN_AUDIT_NOTE_LENGTH) return;
    review.mutate(
      { postId: item.id, decision, note },
      {
        onSuccess: (updated) => {
          toast.success(decision === "Approve" ? "Đã duyệt & đăng bài" : "Đã từ chối bài viết", {
            description: decision === "Approve" ? "Bài đã hiện trên bảng tin." : "Tác giả sẽ thấy ghi chú trong ứng dụng.",
          });
          setRejectOpen(false);
          onItemChange?.(updated);
        },
        onError: (e) => toast.error("Chưa lưu được quyết định", { description: describeError(e) }),
      },
    );
  }

  return (
    <>
      <SheetHeader className="border-b">
        <div className="flex flex-wrap gap-1.5">
          <Badge variant="outline">{CONTENT_KIND_LABEL[item.kind]}</Badge>
          <PostStatusBadge status={item.status} />
          <VideoAiBadge item={item} />
          {item.pinned && <Badge>Đã ghim</Badge>}
          {item.hidden && <Badge variant="secondary">Đã ẩn</Badge>}
        </div>
        <SheetTitle className="mt-2 leading-snug">{item.title}</SheetTitle>
        <SheetDescription>
          {formatAge(item.createdAt)} trước · {formatNumber(item.likeCount)} lượt thích · {formatNumber(item.commentCount)} bình luận
        </SheetDescription>
      </SheetHeader>

      <div className="flex flex-col gap-5 p-5">
        <div className="flex items-center gap-3">
          <InitialsAvatar name={item.author.fullName} verified={item.author.isVerifiedChef} />
          <div>
            <p className="font-semibold">{item.author.fullName}</p>
            <p className="text-xs text-muted-foreground">{item.author.isVerifiedChef ? "Chuyên gia đã xác minh" : "Thành viên"}</p>
          </div>
        </div>

        <p className="rounded-lg bg-muted px-4 py-3 text-sm leading-relaxed">{item.excerpt}</p>

        {item.aiFlag && (
          <section aria-label="AI gắn cờ" className="flex flex-col gap-2 rounded-lg border border-ai-border bg-ai-soft p-3 text-sm">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <p className="inline-flex items-center gap-1.5 text-xs font-bold uppercase tracking-wide text-ai-text">
                <Sparkles className="size-3.5" aria-hidden />
                AI gắn cờ · {FLAG_CATEGORY_LABEL[item.aiFlag.category]}
              </p>
              <span className="text-xs text-muted-foreground">{formatAge(item.aiFlag.createdAt)} trước</span>
            </div>
            <p>{item.aiFlag.reason}</p>
            <ScoreBar value={item.aiFlag.score} label="Điểm tin cậy của AI" />
            <p className="text-xs text-muted-foreground">AI chỉ giữ bài lại chờ người duyệt, không tự gỡ bài.</p>
          </section>
        )}

        {item.decision && (
          <section
            aria-label="Quyết định kiểm duyệt"
            className={
              item.decision.decision === "Approve"
                ? "flex flex-col gap-1 rounded-lg border border-sprout/40 bg-sprout-soft p-3 text-sm text-sprout-text"
                : "flex flex-col gap-1 rounded-lg border p-3 text-sm"
            }
          >
            <p className="inline-flex items-center gap-1.5 font-semibold">
              {item.decision.decision === "Approve" ? <CircleCheck className="size-4" aria-hidden /> : <CircleX className="size-4" aria-hidden />}
              {item.decision.decision === "Approve" ? "Đã duyệt" : "Bị từ chối"} bởi {item.decision.adminName} lúc{" "}
              {dateTimeVi.format(new Date(item.decision.decidedAt))}
            </p>
            {item.decision.note && (
              <p className={item.decision.decision === "Approve" ? undefined : "text-muted-foreground"}>
                {item.decision.decision === "Reject" ? "Ghi chú gửi tác giả: " : "Ghi chú: "}
                {item.decision.note}
              </p>
            )}
          </section>
        )}

        {item.status === "Pending" && (
          <section className="flex flex-col gap-3 rounded-lg border p-3">
            <h3 className="text-sm font-bold">Duyệt bài chờ</h3>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor={approveId}>Ghi chú khi duyệt (không bắt buộc)</Label>
              <Textarea
                id={approveId}
                value={approveNote}
                onChange={(e) => setApproveNote(e.target.value)}
                placeholder="VD: Đã kiểm tra nguồn, nội dung phù hợp."
                rows={2}
                disabled={busy}
              />
            </div>
            <div className="flex flex-wrap gap-2">
              <Button size="sm" disabled={busy} onClick={() => decide("Approve")}>
                <CircleCheck aria-hidden />
                {review.isPending && !rejectOpen ? "Đang lưu…" : "Duyệt & đăng"}
              </Button>
              <Button size="sm" variant="destructive" disabled={busy} onClick={() => setRejectOpen(true)}>
                <CircleX aria-hidden />
                Từ chối
              </Button>
            </div>
          </section>
        )}

        {item.reportCount > 0 && (
          <p className="rounded-lg border border-ochre-border bg-ochre-soft px-3 py-2 text-sm text-ochre-text">
            {item.reportCount} người dùng đã báo cáo bài này từ ứng dụng. Xem lý do chi tiết ở mục Kiểm duyệt AI nếu bài cũng bị AI gắn cờ.
          </p>
        )}

        {item.video?.aiStatus === "failed" && (
          <div className="flex flex-col gap-2 rounded-lg border p-3 text-sm">
            <p className="font-semibold">AI chưa trích xuất được công thức</p>
            <p className="text-muted-foreground">{item.video.failureReason ?? "Không rõ nguyên nhân."}</p>
            <Button size="sm" variant="ai" className="w-fit" disabled={busy} onClick={() => run("retry_ai")}>
              <RotateCcw aria-hidden />
              Chạy lại AI
            </Button>
          </div>
        )}

        {item.status === "Published" ? (
          <div className="flex flex-col gap-2">
            <h3 className="text-sm font-bold">Hiển thị trên bảng tin</h3>
            <div className="flex flex-wrap gap-2">
              {item.hidden ? (
                <Button size="sm" variant="outline" disabled={busy} onClick={() => run("unhide")}>
                  <Eye aria-hidden />
                  Hiện lại
                </Button>
              ) : (
                <Button size="sm" variant="warn" disabled={busy} onClick={() => run("hide")}>
                  <EyeOff aria-hidden />
                  Ẩn bài
                </Button>
              )}
              {!item.hidden &&
                (item.pinned ? (
                  <Button size="sm" variant="outline" disabled={busy} onClick={() => run("unpin")}>
                    <PinOff aria-hidden />
                    Bỏ ghim
                  </Button>
                ) : (
                  <Button size="sm" variant="outline" disabled={busy} onClick={() => run("pin")}>
                    <Pin aria-hidden />
                    Ghim lên đầu
                  </Button>
                ))}
              <Button size="sm" variant="destructive" disabled={busy} onClick={() => setConfirmDelete(true)}>
                <Trash2 aria-hidden />
                Xoá
              </Button>
            </div>
            <p className="text-xs text-muted-foreground">Ẩn bài có thể hoàn tác; tác giả nhận thông báo trong ứng dụng.</p>
          </div>
        ) : (
          <div className="flex flex-col gap-2">
            <p className="text-xs text-muted-foreground">
              {item.status === "Pending"
                ? "Bài chưa hiển thị trên bảng tin; chỉ tác giả thấy nhãn “Chờ duyệt”."
                : "Bài không hiển thị trên bảng tin. Tác giả có thể sửa và gửi lại từ ứng dụng."}
            </p>
            <Button size="sm" variant="outline" className="w-fit" disabled={busy} onClick={() => setConfirmDelete(true)}>
              <Trash2 aria-hidden />
              Xoá bài
            </Button>
          </div>
        )}
      </div>

      <Dialog
        open={rejectOpen}
        onOpenChange={(open) => {
          if (!review.isPending) setRejectOpen(open);
        }}
      >
        <DialogContent>
          <DialogTitle>Từ chối bài viết?</DialogTitle>
          <DialogDescription>“{item.title}” sẽ không lên bảng tin. Tác giả có thể sửa và gửi lại để duyệt.</DialogDescription>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor={rejectId}>
              Lý do từ chối <span className="text-destructive">(bắt buộc)</span>
            </Label>
            <Textarea
              id={rejectId}
              value={rejectNote}
              onChange={(e) => setRejectNote(e.target.value)}
              placeholder="VD: Bài khẳng định chữa khỏi bệnh nhưng chưa có nguồn. Vui lòng ghi nguồn rồi gửi lại."
              aria-describedby={`${rejectId}-hint`}
              aria-invalid={rejectNote.length > 0 && !rejectOk ? true : undefined}
              disabled={review.isPending}
            />
            <p id={`${rejectId}-hint`} className="flex justify-between gap-3 text-xs text-muted-foreground">
              <span>Ghi chú sẽ gửi cho tác giả · tối thiểu {MIN_AUDIT_NOTE_LENGTH} ký tự</span>
              <span className="font-mono tabular">{rejectNote.trim().length}</span>
            </p>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" disabled={review.isPending}>
                Huỷ
              </Button>
            </DialogClose>
            <Button variant="destructive" disabled={!rejectOk || review.isPending} onClick={() => decide("Reject")}>
              {review.isPending ? "Đang lưu…" : "Từ chối bài"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={confirmDelete} onOpenChange={setConfirmDelete}>
        <DialogContent>
          <DialogTitle>Xoá bài viết?</DialogTitle>
          <DialogDescription>
            “{item.title}” sẽ bị xoá khỏi ứng dụng cùng toàn bộ bình luận.
            {item.status === "Published" ? " Nếu chỉ cần gỡ tạm, hãy dùng “Ẩn bài”." : ""}
          </DialogDescription>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Huỷ</Button>
            </DialogClose>
            <Button variant="destructive" disabled={action.isPending} onClick={() => run("delete")}>
              {action.isPending ? "Đang xoá…" : "Xoá vĩnh viễn"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
