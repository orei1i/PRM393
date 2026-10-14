// src/components/moderation/moderation-action-bar.tsx
"use client";

import * as React from "react";
import { Ban, CircleCheck, LoaderCircle, TriangleAlert } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Checkbox, Label, Textarea } from "@/components/ui/form-controls";
import { describeError } from "@/lib/api_error";
import { useModerationDecision } from "@/lib/hooks/use-moderation";
import { ACTION_LABEL, MIN_AUDIT_NOTE_LENGTH, type AiFlag, type ModerationAction } from "@/types/moderation";

/**
 * Approve / Warn / Reject with a mandatory internal audit note.
 * Buttons stay disabled until the note is long enough; ⌘/Ctrl + Enter submits the AI suggestion.
 */
export function ModerationActionBar({ flag, onDecided }: { flag: AiFlag; onDecided: () => void }) {
  const [note, setNote] = React.useState("");
  const [notifyAuthor, setNotifyAuthor] = React.useState(true);
  const [pendingAction, setPendingAction] = React.useState<ModerationAction | null>(null);
  const decision = useModerationDecision();
  const noteId = React.useId();
  const hintId = React.useId();

  const noteLength = note.trim().length;
  const noteOk = noteLength >= MIN_AUDIT_NOTE_LENGTH;
  const busy = decision.isPending;

  function submit(action: ModerationAction) {
    if (!noteOk || busy) return;
    setPendingAction(action);
    decision.mutate(
      { flagId: flag.id, action, note: note.trim(), notifyAuthor },
      {
        onSuccess: () => {
          toast.success(`${ACTION_LABEL[action]}: @${flag.post.author.handle}`, {
            description: "Đã lưu vào nhật ký kiểm duyệt.",
          });
          onDecided();
        },
        onError: (error) => toast.error("Chưa lưu được quyết định", { description: describeError(error) }),
        onSettled: () => setPendingAction(null),
      },
    );
  }

  function onKeyDown(e: React.KeyboardEvent<HTMLTextAreaElement>) {
    if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
      e.preventDefault();
      submit(flag.suggestedAction);
    }
  }

  const spinner = (action: ModerationAction) =>
    pendingAction === action ? <LoaderCircle className="animate-spin" aria-hidden /> : null;

  return (
    <div className="flex flex-col gap-3 border-t bg-card p-5">
      <div className="flex flex-col gap-1.5">
        <Label htmlFor={noteId}>
          Ghi chú kiểm duyệt nội bộ <span className="text-destructive">(bắt buộc)</span>
        </Label>
        <Textarea
          id={noteId}
          value={note}
          onChange={(e) => setNote(e.target.value)}
          onKeyDown={onKeyDown}
          rows={3}
          placeholder="Vì sao bạn quyết định như vậy? Chỉ quản trị viên xem được."
          aria-describedby={hintId}
          aria-invalid={note.length > 0 && !noteOk}
          disabled={busy}
        />
        <p id={hintId} className="flex justify-between text-xs text-muted-foreground">
          <span>Tối thiểu {MIN_AUDIT_NOTE_LENGTH} ký tự · ⌘/Ctrl + Enter = làm theo gợi ý AI</span>
          <span className="font-mono tabular">{noteLength}</span>
        </p>
      </div>

      <Label className="font-medium">
        <Checkbox checked={notifyAuthor} onChange={(e) => setNotifyAuthor(e.target.checked)} disabled={busy} />
        Gửi thông báo theo mẫu {flag.policyRef} cho tác giả
      </Label>

      <div className="flex flex-wrap gap-2">
        <Button variant="outline" className="flex-1" disabled={!noteOk || busy} onClick={() => submit("approve")}>
          {spinner("approve") ?? <CircleCheck aria-hidden />}
          {ACTION_LABEL.approve}
        </Button>
        <Button variant="warn" className="flex-1" disabled={!noteOk || busy} onClick={() => submit("warn")}>
          {spinner("warn") ?? <TriangleAlert aria-hidden />}
          {ACTION_LABEL.warn}
        </Button>
        <Button variant="destructive" className="flex-1" disabled={!noteOk || busy} onClick={() => submit("reject")}>
          {spinner("reject") ?? <Ban aria-hidden />}
          {ACTION_LABEL.reject}
        </Button>
      </div>
      {!noteOk && (
        <p className="text-xs text-muted-foreground" aria-live="polite">
          Nhập ghi chú để mở khoá các nút quyết định.
        </p>
      )}
    </div>
  );
}
