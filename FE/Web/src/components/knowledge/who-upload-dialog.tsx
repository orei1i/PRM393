// src/components/knowledge/who-upload-dialog.tsx
"use client";

import * as React from "react";
import { FileUp, Link2, Upload } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogTitle } from "@/components/ui/dialog";
import { Input, Label } from "@/components/ui/form-controls";
import { describeError } from "@/lib/api_error";
import { useCreateWhoDoc } from "@/lib/hooks/use-knowledge";
import { whoFileUrlFor } from "@/lib/knowledge_api";
import { cn, formatNumber } from "@/lib/utils";
import type { KnowledgeDoc } from "@/types/knowledge";

const MIN_TITLE = 10;

type Mode = "file" | "url";

/** WHO upload: title + a PDF (stub: file name → files.veganlife.vn URL) or a link. Starts Approved. */
export function WhoUploadDialog({
  open,
  onOpenChange,
  onCreated,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onCreated?: (doc: KnowledgeDoc) => void;
}) {
  const create = useCreateWhoDoc();
  const [title, setTitle] = React.useState("");
  const [mode, setMode] = React.useState<Mode>("file");
  const [fileName, setFileName] = React.useState<string | null>(null);
  const [url, setUrl] = React.useState("");
  const ids = React.useId();

  const titleOk = title.trim().length >= MIN_TITLE;
  const fileOk = fileName !== null && /\.pdf$/i.test(fileName);
  const urlOk = /^https:\/\/\S+$/i.test(url.trim());
  const sourceOk = mode === "file" ? fileOk : urlOk;
  const fileUrl = mode === "file" ? (fileOk && fileName ? whoFileUrlFor(fileName) : "") : url.trim();

  function reset() {
    setTitle("");
    setMode("file");
    setFileName(null);
    setUrl("");
  }

  function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!titleOk || !sourceOk || create.isPending) return;
    create.mutate(
      { title: title.trim(), fileUrl },
      {
        onSuccess: (doc) => {
          toast.success(`Đã thêm “${doc.title}”`, {
            description: `${formatNumber(doc.chunkCount)} đoạn đã sẵn sàng cho chatbot (mô phỏng).`,
          });
          reset();
          onOpenChange(false);
          onCreated?.(doc);
        },
        onError: (err) => toast.error("Chưa tải được tài liệu", { description: describeError(err) }),
      },
    );
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        if (create.isPending) return;
        onOpenChange(next);
      }}
    >
      <DialogContent className="max-w-lg">
        <DialogTitle>Tải tài liệu WHO</DialogTitle>
        <DialogDescription>Tài liệu WHO được duyệt ngay và đưa vào nguồn trích dẫn của chatbot.</DialogDescription>
        <form className="flex flex-col gap-4" onSubmit={submit}>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor={`${ids}-title`}>Tiêu đề</Label>
            <Input
              id={`${ids}-title`}
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="VD: Healthy diet — Fact sheet (2025)"
              aria-invalid={title.length > 0 && !titleOk ? true : undefined}
              aria-describedby={`${ids}-title-hint`}
              disabled={create.isPending}
            />
            <p id={`${ids}-title-hint`} className="text-xs text-muted-foreground">
              Tối thiểu {MIN_TITLE} ký tự · {title.trim().length}
            </p>
          </div>

          <div className="flex flex-col gap-2">
            <span className="text-sm font-semibold" id={`${ids}-mode`}>
              Tệp tài liệu
            </span>
            <div role="radiogroup" aria-labelledby={`${ids}-mode`} className="inline-flex w-fit gap-1 rounded-lg bg-muted p-1">
              {(
                [
                  ["file", "Tải tệp PDF", FileUp],
                  ["url", "Dán đường dẫn", Link2],
                ] as const
              ).map(([value, label, Icon]) => (
                <button
                  key={value}
                  type="button"
                  role="radio"
                  aria-checked={mode === value}
                  onClick={() => setMode(value)}
                  disabled={create.isPending}
                  className={cn(
                    "inline-flex h-8 items-center gap-1.5 rounded-md px-3 text-sm font-semibold text-muted-foreground transition-colors outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40",
                    mode === value ? "bg-card text-foreground shadow-sm" : "hover:text-foreground",
                  )}
                >
                  <Icon className="size-4" aria-hidden />
                  {label}
                </button>
              ))}
            </div>

            {mode === "file" ? (
              <div className="flex flex-col gap-1.5">
                <Label htmlFor={`${ids}-file`} className="sr-only">
                  Chọn tệp PDF
                </Label>
                <Input
                  id={`${ids}-file`}
                  type="file"
                  accept=".pdf,application/pdf"
                  onChange={(e) => setFileName(e.target.files?.[0]?.name ?? null)}
                  disabled={create.isPending}
                  className="py-2 file:mr-3 file:border-0 file:bg-transparent file:text-sm file:font-semibold file:text-foreground"
                  aria-describedby={`${ids}-file-hint`}
                />
                <p id={`${ids}-file-hint`} className={cn("break-all text-xs", fileName && !fileOk ? "text-destructive" : "text-muted-foreground")}>
                  {fileName && !fileOk
                    ? "Chỉ nhận tệp .pdf."
                    : fileOk
                      ? `Lưu tại: ${fileUrl} (mô phỏng, chưa tải tệp lên máy chủ)`
                      : "Chưa chọn tệp."}
                </p>
              </div>
            ) : (
              <div className="flex flex-col gap-1.5">
                <Label htmlFor={`${ids}-url`} className="sr-only">
                  Đường dẫn tệp
                </Label>
                <Input
                  id={`${ids}-url`}
                  type="url"
                  inputMode="url"
                  value={url}
                  onChange={(e) => setUrl(e.target.value)}
                  placeholder="https://www.who.int/…/tai-lieu.pdf"
                  aria-invalid={url.length > 0 && !urlOk ? true : undefined}
                  aria-describedby={`${ids}-url-hint`}
                  disabled={create.isPending}
                />
                <p id={`${ids}-url-hint`} className={cn("text-xs", url.length > 0 && !urlOk ? "text-destructive" : "text-muted-foreground")}>
                  Đường dẫn phải bắt đầu bằng https://
                </p>
              </div>
            )}
          </div>

          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="outline" disabled={create.isPending}>
                Huỷ
              </Button>
            </DialogClose>
            <Button type="submit" disabled={!titleOk || !sourceOk || create.isPending}>
              <Upload aria-hidden />
              {create.isPending ? "Đang tải lên…" : "Tải lên"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
