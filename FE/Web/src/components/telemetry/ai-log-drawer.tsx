// src/components/telemetry/ai-log-drawer.tsx
"use client";

import * as React from "react";
import Link from "next/link";
import { CircleCheck, CircleX, ExternalLink } from "lucide-react";
import { toast } from "sonner";

import { ErrorState } from "@/components/admin/states";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Label, Skeleton, Textarea } from "@/components/ui/form-controls";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { describeError } from "@/lib/api_error";
import { useAiLogDetail, useLabelAiLog } from "@/lib/hooks/use-telemetry";
import { formatNumber, formatTime } from "@/lib/utils";
import { TASK_LABEL, type AiLog, type AiLogVerdict } from "@/types/moderation";

import { LOG_STATUS } from "./live-log-table";

const REF_LABEL: Record<string, string> = {
  post: "Bài viết",
  chat_session: "Phiên chat",
  meal_plan: "Thực đơn",
  user_ingredients: "Nguyên liệu người dùng",
};

const dateTimeVi = new Intl.DateTimeFormat("vi-VN", {
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
  day: "2-digit",
  month: "2-digit",
  year: "numeric",
});

/** One ai_logs row: metadata, what it was about (ref), input/output text and the admin's verdict. */
export function AiLogDrawer({ log, onOpenChange }: { log: AiLog | null; onOpenChange: (open: boolean) => void }) {
  return (
    <Sheet open={log !== null} onOpenChange={onOpenChange}>
      <SheetContent className="gap-0 overflow-y-auto sm:max-w-xl">{log && <Detail key={log.id} log={log} />}</SheetContent>
    </Sheet>
  );
}

function Detail({ log }: { log: AiLog }) {
  const detail = useAiLogDetail(log.id);
  const label = useLabelAiLog();
  const [note, setNote] = React.useState("");
  const noteId = React.useId();
  const status = LOG_STATUS[log.status];
  const saved = detail.data?.label;

  function submit(verdict: AiLogVerdict) {
    label.mutate(
      { logId: log.id, verdict, note: note.trim() || undefined },
      {
        onSuccess: () => {
          toast.success(verdict === "correct" ? "Đã đánh giá: đầu ra đúng" : "Đã đánh giá: đầu ra sai", {
            description: "Độ chính xác theo nhãn trên trang Mô hình AI đã được cập nhật.",
          });
          setNote("");
        },
        onError: (e) => toast.error("Chưa lưu được đánh giá", { description: describeError(e) }),
      },
    );
  }

  return (
    <>
      <SheetHeader className="border-b">
        <div className="flex flex-wrap gap-1.5">
          <Badge variant="outline">{TASK_LABEL[log.task]}</Badge>
          <Badge variant={status.variant}>{status.label}</Badge>
        </div>
        <SheetTitle className="mt-2">Lượt gọi AI lúc {formatTime(log.timestamp)}</SheetTitle>
        <SheetDescription>
          {log.model} · trace <span className="font-mono">{log.traceId}</span>
        </SheetDescription>
      </SheetHeader>

      <div className="flex flex-col gap-5 p-5">
        <dl className="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
          <Info label="Tác vụ" value={TASK_LABEL[log.task]} />
          <Info label="Mô hình" value={log.model} mono />
          <Info label="Độ trễ" value={`${formatNumber(log.latencyMs)} ms`} mono />
          <Info
            label="Tokens vào / ra"
            value={log.inputTokens || log.outputTokens ? `${formatNumber(log.inputTokens)} / ${formatNumber(log.outputTokens)}` : "–"}
            mono
          />
          <Info label="Kết quả" value={log.detail || "–"} />
          <Info label="Thời gian" value={dateTimeVi.format(new Date(log.timestamp))} />
        </dl>

        {log.refType && (
          <section aria-label="Đối tượng liên quan" className="flex flex-wrap items-center justify-between gap-2 rounded-lg border p-3 text-sm">
            <p>
              <span className="text-muted-foreground">Liên quan: </span>
              <b>{REF_LABEL[log.refType] ?? log.refType}</b> <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">{log.refId}</code>
            </p>
            {log.refType === "post" && log.refId && (
              <Button asChild size="sm" variant="outline">
                <Link href={`/content?open=${encodeURIComponent(log.refId)}`}>
                  <ExternalLink aria-hidden />
                  Mở bài viết
                </Link>
              </Button>
            )}
          </section>
        )}

        {detail.isError ? (
          <div className="rounded-lg border">
            <ErrorState error={detail.error} onRetry={() => detail.refetch()} title="Chưa tải được nội dung lượt gọi" />
          </div>
        ) : (
          <>
            <TextBlock title="Đầu vào (input_text)" text={detail.data?.inputText} loading={detail.isLoading} />
            <TextBlock title="Đầu ra (output_text)" text={detail.data?.outputText} loading={detail.isLoading} />

            <section aria-label="Đánh giá đầu ra" className="flex flex-col gap-3 rounded-lg border p-3">
              <h3 className="text-sm font-bold">Đánh giá đầu ra</h3>
              {saved && (
                <p className="flex flex-wrap items-center gap-2 text-sm">
                  <Badge variant={saved.verdict === "correct" ? "sprout" : "destructive"}>
                    {saved.verdict === "correct" ? <CircleCheck aria-hidden /> : <CircleX aria-hidden />}
                    {saved.verdict === "correct" ? "Đúng" : "Sai"}
                  </Badge>
                  <span className="text-muted-foreground">
                    {saved.by} · {dateTimeVi.format(new Date(saved.at))}
                  </span>
                  {saved.note && <span className="w-full">“{saved.note}”</span>}
                </p>
              )}
              <div className="flex flex-col gap-1.5">
                <Label htmlFor={noteId}>Ghi chú (không bắt buộc)</Label>
                <Textarea
                  id={noteId}
                  rows={2}
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                  placeholder="VD: Trích dẫn đúng nguồn WHO nhưng thiếu cảnh báo cho người đang dùng thuốc."
                  disabled={label.isPending || detail.isLoading}
                />
              </div>
              <div className="flex flex-wrap gap-2">
                <Button size="sm" variant="outline" disabled={label.isPending || detail.isLoading} onClick={() => submit("correct")}>
                  <CircleCheck aria-hidden />
                  Đúng
                </Button>
                <Button size="sm" variant="outline" disabled={label.isPending || detail.isLoading} onClick={() => submit("incorrect")}>
                  <CircleX aria-hidden />
                  Sai
                </Button>
              </div>
              <p className="text-xs text-muted-foreground">
                {saved ? "Đánh giá lại sẽ thay nhãn cũ. " : ""}Nhãn dùng để tính độ chính xác theo tác vụ ở trang Mô hình AI.
              </p>
            </section>
          </>
        )}
      </div>
    </>
  );
}

function TextBlock({ title, text, loading }: { title: string; text: string | undefined; loading: boolean }) {
  return (
    <section className="flex flex-col gap-1.5">
      <h3 className="text-sm font-bold">{title}</h3>
      {loading ? (
        <Skeleton className="h-24" />
      ) : (
        <pre
          tabIndex={0}
          className="max-h-64 overflow-auto whitespace-pre-wrap break-words rounded-lg bg-muted p-3 font-mono text-xs leading-relaxed outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
        >
          {text || "(trống)"}
        </pre>
      )}
    </section>
  );
}

function Info({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="min-w-0">
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className={mono ? "break-words font-mono text-xs font-semibold" : "break-words font-semibold"}>{value}</dd>
    </div>
  );
}
