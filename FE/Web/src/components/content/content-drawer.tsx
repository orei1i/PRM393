// src/components/content/content-drawer.tsx
"use client";

import * as React from "react";
import { Eye, EyeOff, Pin, PinOff, RotateCcw, Trash2 } from "lucide-react";
import { toast } from "sonner";

import { InitialsAvatar } from "@/components/admin/initials-avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogTitle } from "@/components/ui/dialog";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { describeError } from "@/lib/api_error";
import { useContentAction } from "@/lib/hooks/use-admin";
import { formatAge, formatNumber } from "@/lib/utils";
import { CONTENT_KIND_LABEL, type ContentAction, type ContentItem } from "@/types/admin";

import { VideoAiBadge } from "./content-table";

const ACTION_DONE: Record<ContentAction, string> = {
  hide: "Đã ẩn khỏi bảng tin",
  unhide: "Đã hiện lại trên bảng tin",
  pin: "Đã ghim lên đầu bảng tin",
  unpin: "Đã bỏ ghim",
  delete: "Đã xoá bài viết",
  retry_ai: "Đã gửi video vào hàng chờ AI",
};

export function ContentDrawer({ item, onOpenChange }: { item: ContentItem | null; onOpenChange: (open: boolean) => void }) {
  return (
    <Sheet open={item !== null} onOpenChange={onOpenChange}>
      <SheetContent className="gap-0 overflow-y-auto sm:max-w-lg">
        {item && <Detail key={item.id} item={item} onClose={() => onOpenChange(false)} />}
      </SheetContent>
    </Sheet>
  );
}

function Detail({ item, onClose }: { item: ContentItem; onClose: () => void }) {
  const action = useContentAction();
  const [confirmDelete, setConfirmDelete] = React.useState(false);

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

  return (
    <>
      <SheetHeader className="border-b">
        <div className="flex flex-wrap gap-1.5">
          <Badge variant="outline">{CONTENT_KIND_LABEL[item.kind]}</Badge>
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

        {item.reportCount > 0 && (
          <p className="rounded-lg border border-ochre-border bg-ochre-soft px-3 py-2 text-sm text-ochre-text">
            {item.reportCount} người dùng đã báo cáo bài này từ ứng dụng. Xem lý do chi tiết ở mục Kiểm duyệt AI nếu bài cũng bị AI gắn cờ.
          </p>
        )}

        {item.video?.aiStatus === "failed" && (
          <div className="flex flex-col gap-2 rounded-lg border p-3 text-sm">
            <p className="font-semibold">AI chưa trích xuất được công thức</p>
            <p className="text-muted-foreground">{item.video.failureReason ?? "Không rõ nguyên nhân."}</p>
            <Button size="sm" variant="ai" className="w-fit" disabled={action.isPending} onClick={() => run("retry_ai")}>
              <RotateCcw aria-hidden />
              Chạy lại AI
            </Button>
          </div>
        )}

        <div className="flex flex-col gap-2">
          <h3 className="text-sm font-bold">Hiển thị trên bảng tin</h3>
          <div className="flex flex-wrap gap-2">
            {item.hidden ? (
              <Button size="sm" variant="outline" disabled={action.isPending} onClick={() => run("unhide")}>
                <Eye aria-hidden />
                Hiện lại
              </Button>
            ) : (
              <Button size="sm" variant="warn" disabled={action.isPending} onClick={() => run("hide")}>
                <EyeOff aria-hidden />
                Ẩn bài
              </Button>
            )}
            {!item.hidden &&
              (item.pinned ? (
                <Button size="sm" variant="outline" disabled={action.isPending} onClick={() => run("unpin")}>
                  <PinOff aria-hidden />
                  Bỏ ghim
                </Button>
              ) : (
                <Button size="sm" variant="outline" disabled={action.isPending} onClick={() => run("pin")}>
                  <Pin aria-hidden />
                  Ghim lên đầu
                </Button>
              ))}
            <Button size="sm" variant="destructive" disabled={action.isPending} onClick={() => setConfirmDelete(true)}>
              <Trash2 aria-hidden />
              Xoá
            </Button>
          </div>
          <p className="text-xs text-muted-foreground">Ẩn bài có thể hoàn tác; tác giả nhận thông báo trong ứng dụng.</p>
        </div>
      </div>

      <Dialog open={confirmDelete} onOpenChange={setConfirmDelete}>
        <DialogContent>
          <DialogTitle>Xoá bài viết?</DialogTitle>
          <DialogDescription>
            “{item.title}” sẽ bị xoá khỏi ứng dụng cùng toàn bộ bình luận. Nếu chỉ cần gỡ tạm, hãy dùng “Ẩn bài”.
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
