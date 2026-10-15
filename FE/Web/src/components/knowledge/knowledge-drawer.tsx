// src/components/knowledge/knowledge-drawer.tsx
"use client";

import * as React from "react";
import { CircleCheck, CircleX, ExternalLink, Layers, Trash2 } from "lucide-react";
import { toast } from "sonner";

import { ErrorState } from "@/components/admin/states";
import { Button } from "@/components/ui/button";
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogTitle } from "@/components/ui/dialog";
import { Label, Skeleton, Textarea } from "@/components/ui/form-controls";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { describeError } from "@/lib/api_error";
import { useDeleteKnowledgeDoc, useKnowledgeChunks, useReviewKnowledgeDoc } from "@/lib/hooks/use-knowledge";
import { formatNumber } from "@/lib/utils";
import type { KnowledgeDoc } from "@/types/knowledge";
import { MIN_AUDIT_NOTE_LENGTH } from "@/types/moderation";

import { dateVi, KnowledgeSourceBadge, KnowledgeStatusBadge } from "./knowledge-table";

const dateTimeVi = new Intl.DateTimeFormat("vi-VN", { hour: "2-digit", minute: "2-digit", day: "2-digit", month: "2-digit", year: "numeric" });

export function KnowledgeDrawer({
  doc,
  onOpenChange,
  onDocChange,
}: {
  doc: KnowledgeDoc | null;
  onOpenChange: (open: boolean) => void;
  onDocChange: (doc: KnowledgeDoc) => void;
}) {
  return (
    <Sheet open={doc !== null} onOpenChange={onOpenChange}>
      <SheetContent className="gap-0 overflow-y-auto sm:max-w-lg">
        {doc && <Detail key={doc.id} doc={doc} onClose={() => onOpenChange(false)} onDocChange={onDocChange} />}
      </SheetContent>
    </Sheet>
  );
}

function Detail({ doc, onClose, onDocChange }: { doc: KnowledgeDoc; onClose: () => void; onDocChange: (doc: KnowledgeDoc) => void }) {
  const review = useReviewKnowledgeDoc();
  const remove = useDeleteKnowledgeDoc();
  const [showChunks, setShowChunks] = React.useState(false);
  const chunks = useKnowledgeChunks(doc.id, showChunks);
  const [rejectOpen, setRejectOpen] = React.useState(false);
  const [note, setNote] = React.useState("");
  const [confirmDelete, setConfirmDelete] = React.useState(false);
  const noteId = React.useId();

  const noteOk = note.trim().length >= MIN_AUDIT_NOTE_LENGTH;
  const busy = review.isPending || remove.isPending;
  const reviewable = doc.status === "Pending" && doc.source === "Chef";

  function decide(decision: "Approve" | "Reject") {
    if (decision === "Reject" && !noteOk) return;
    review.mutate(
      { docId: doc.id, decision, note: decision === "Reject" ? note.trim() : "" },
      {
        onSuccess: (updated) => {
          if (decision === "Approve") toast.success("Đã duyệt. Hệ thống đang tách đoạn & tạo embedding (mô phỏng).");
          else toast.success("Đã từ chối tài liệu", { description: "Chuyên gia sẽ thấy ghi chú trong ứng dụng." });
          setRejectOpen(false);
          setNote("");
          onDocChange(updated);
        },
        onError: (e) => toast.error("Chưa lưu được quyết định", { description: describeError(e) }),
      },
    );
  }

  function applyDelete() {
    remove.mutate(doc.id, {
      onSuccess: () => {
        toast.success("Đã xoá tài liệu");
        setConfirmDelete(false);
        onClose();
      },
      onError: (e) => toast.error("Chưa xoá được tài liệu", { description: describeError(e) }),
    });
  }

  return (
    <>
      <SheetHeader className="border-b">
        <div className="flex flex-wrap gap-1.5">
          <KnowledgeSourceBadge doc={doc} />
          <KnowledgeStatusBadge status={doc.status} />
        </div>
        <SheetTitle className="mt-2 leading-snug">{doc.title}</SheetTitle>
        <SheetDescription>Tạo ngày {dateVi.format(new Date(doc.createdAt))}</SheetDescription>
      </SheetHeader>

      <div className="flex flex-col gap-5 p-5">
        <dl className="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
          <Info label="Nguồn" value={doc.source === "WHO" ? "WHO" : "Chuyên gia"} />
          <Info label="Người đóng góp" value={doc.chefName ?? "Ban quản trị"} />
          <Info label="Số đoạn" value={doc.status === "Approved" ? formatNumber(doc.chunkCount) : "Chưa tách"} />
          <Info label="Lượt trích dẫn" value={formatNumber(doc.citationCount)} />
          {doc.reviewedBy && <Info label="Xử lý bởi" value={doc.reviewedBy} />}
          {doc.reviewedAt && <Info label="Lúc" value={dateTimeVi.format(new Date(doc.reviewedAt))} />}
        </dl>

        {doc.reviewNote && (
          <p className={doc.status === "Rejected" ? "rounded-lg border px-3 py-2 text-sm" : "rounded-lg bg-muted px-3 py-2 text-sm"}>
            <span className="text-muted-foreground">{doc.status === "Rejected" ? "Lý do từ chối: " : "Ghi chú: "}</span>
            {doc.reviewNote}
          </p>
        )}

        <div className="flex flex-wrap gap-2">
          <Button asChild size="sm" variant="outline">
            <a href={doc.fileUrl} target="_blank" rel="noopener noreferrer">
              <ExternalLink aria-hidden />
              Mở tệp
            </a>
          </Button>
          <Button size="sm" variant="outline" aria-expanded={showChunks} onClick={() => setShowChunks((v) => !v)}>
            <Layers aria-hidden />
            {showChunks ? "Ẩn các đoạn" : "Xem trước các đoạn"}
          </Button>
        </div>

        {showChunks && (
          <section aria-label="Các đoạn đầu tiên" className="flex flex-col gap-2">
            {chunks.isError ? (
              <div className="rounded-lg border">
                <ErrorState error={chunks.error} onRetry={() => chunks.refetch()} title="Chưa tải được các đoạn" />
              </div>
            ) : chunks.isLoading ? (
              <>
                <Skeleton className="h-14" />
                <Skeleton className="h-14" />
                <Skeleton className="h-14" />
              </>
            ) : chunks.data?.length === 0 ? (
              <p className="rounded-lg bg-muted px-3 py-2 text-sm text-muted-foreground">
                {doc.status === "Pending"
                  ? "Tài liệu chưa được tách đoạn. Duyệt để hệ thống tách đoạn & tạo embedding."
                  : "Tài liệu này không có đoạn nào trong chỉ mục của chatbot."}
              </p>
            ) : (
              <ol className="flex flex-col gap-2">
                {chunks.data?.map((c) => (
                  <li key={c.id} className="rounded-lg border p-3 text-sm leading-relaxed">
                    <span className="mb-1 block font-mono text-xs text-muted-foreground">Đoạn #{c.chunkIndex}</span>
                    {c.content}
                  </li>
                ))}
              </ol>
            )}
          </section>
        )}

        {reviewable && (
          <section className="flex flex-col gap-2 rounded-lg border p-3">
            <h3 className="text-sm font-bold">Duyệt tài liệu của chuyên gia</h3>
            <p className="text-xs text-muted-foreground">Chatbot chỉ trích dẫn tài liệu sau khi được duyệt.</p>
            <div className="flex flex-wrap gap-2">
              <Button size="sm" disabled={busy} onClick={() => decide("Approve")}>
                <CircleCheck aria-hidden />
                {review.isPending && !rejectOpen ? "Đang duyệt…" : "Duyệt — cho AI sử dụng"}
              </Button>
              <Button size="sm" variant="destructive" disabled={busy} onClick={() => setRejectOpen(true)}>
                <CircleX aria-hidden />
                Từ chối
              </Button>
            </div>
          </section>
        )}

        <section className="flex flex-col gap-2 rounded-lg border border-destructive/30 p-3">
          <h3 className="text-sm font-bold text-destructive">Xoá tài liệu</h3>
          <p className="text-xs text-muted-foreground">Gỡ khỏi nguồn của chatbot. Câu trả lời cũ vẫn giữ trích dẫn.</p>
          <Button size="sm" variant="destructive" className="w-fit" disabled={busy} onClick={() => setConfirmDelete(true)}>
            <Trash2 aria-hidden />
            Xoá tài liệu
          </Button>
        </section>
      </div>

      <Dialog
        open={rejectOpen}
        onOpenChange={(open) => {
          if (!review.isPending) setRejectOpen(open);
        }}
      >
        <DialogContent>
          <DialogTitle>Từ chối tài liệu?</DialogTitle>
          <DialogDescription>“{doc.title}” sẽ không được chatbot sử dụng. Chuyên gia có thể sửa và gửi lại.</DialogDescription>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor={noteId}>
              Ghi chú <span className="text-destructive">(bắt buộc)</span>
            </Label>
            <Textarea
              id={noteId}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="VD: Thiếu nguồn tham khảo cho phần liều bổ sung B12."
              aria-describedby={`${noteId}-hint`}
              aria-invalid={note.length > 0 && !noteOk ? true : undefined}
              disabled={review.isPending}
            />
            <p id={`${noteId}-hint`} className="flex justify-between gap-3 text-xs text-muted-foreground">
              <span>Gửi cho chuyên gia · tối thiểu {MIN_AUDIT_NOTE_LENGTH} ký tự</span>
              <span className="font-mono tabular">{note.trim().length}</span>
            </p>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" disabled={review.isPending}>
                Huỷ
              </Button>
            </DialogClose>
            <Button variant="destructive" disabled={!noteOk || review.isPending} onClick={() => decide("Reject")}>
              {review.isPending ? "Đang lưu…" : "Từ chối tài liệu"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={confirmDelete} onOpenChange={(open) => !remove.isPending && setConfirmDelete(open)}>
        <DialogContent>
          <DialogTitle>Xoá tài liệu?</DialogTitle>
          <DialogDescription>
            “{doc.title}” sẽ bị gỡ khỏi nguồn của chatbot. Câu trả lời cũ vẫn giữ trích dẫn.
          </DialogDescription>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" disabled={remove.isPending}>
                Huỷ
              </Button>
            </DialogClose>
            <Button variant="destructive" disabled={remove.isPending} onClick={applyDelete}>
              {remove.isPending ? "Đang xoá…" : "Xoá tài liệu"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

function Info({ label, value }: { label: string; value: string }) {
  return (
    <div className="min-w-0">
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className="break-words font-semibold">{value}</dd>
    </div>
  );
}
