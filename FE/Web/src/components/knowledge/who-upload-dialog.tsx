// src/components/knowledge/who-upload-dialog.tsx
"use client";

import * as React from "react";
import { FileUp, Link2, Upload } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogTitle } from "@/components/ui/dialog";
import { Input, Label, Textarea } from "@/components/ui/form-controls";
import { describeError } from "@/lib/api_error";
import { isMock } from "@/lib/backend_modules";
import { useCreateWhoDoc } from "@/lib/hooks/use-knowledge";
import { whoFileUrlFor } from "@/lib/knowledge_api";
import { cn, formatNumber } from "@/lib/utils";
import type { KnowledgeDoc } from "@/types/knowledge";

const MIN_TITLE = 10;
const MIN_CONTENT = 50;
const MAX_TEXT_FILE_BYTES = 5 * 1024 * 1024;
const MAX_PDF_BYTES = 30 * 1024 * 1024;

type Mode = "file" | "url";

/** Real mode sends the text itself: the server never fetches a URL a client gives it. */
function WhoUploadRealForm({ onDone, onCreated }: { onDone: () => void; onCreated?: (doc: KnowledgeDoc) => void }) {
  const create = useCreateWhoDoc();
  const [title, setTitle] = React.useState("");
  const [content, setContent] = React.useState("");
  const [link, setLink] = React.useState("");
  const [fileError, setFileError] = React.useState<string | null>(null);
  const [pdf, setPdf] = React.useState<File | null>(null);
  const ids = React.useId();

  const titleOk = title.trim().length >= MIN_TITLE;
  const contentOk = pdf !== null || content.trim().length >= MIN_CONTENT;
  const linkOk = link.trim() === "" || /^https?:\/\/\S+$/i.test(link.trim());

  async function readFile(file: File | undefined) {
    setFileError(null);
    setPdf(null);
    if (!file) return;
    if (/\.pdf$/i.test(file.name)) {
      if (file.size > MAX_PDF_BYTES) {
        setFileError("Tệp quá lớn: tối đa 30 MB.");
        return;
      }
      setPdf(file);
      setContent("");
      return;
    }
    if (!/\.(txt|md)$/i.test(file.name)) {
      setFileError("Máy chủ chưa đọc được tệp này. Chỉ nhận .pdf, .txt hoặc .md, hoặc dán nội dung vào ô bên dưới.");
      return;
    }
    if (file.size > MAX_TEXT_FILE_BYTES) {
      setFileError("Tệp quá lớn: tối đa 5 MB.");
      return;
    }
    try {
      setContent(await file.text());
    } catch {
      setFileError("Không đọc được tệp này. Thử lại hoặc dán nội dung vào ô bên dưới.");
    }
  }

  function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!titleOk || !contentOk || !linkOk || create.isPending) return;
    create.mutate(
      pdf ? { title: title.trim(), fileUrl: link.trim(), file: pdf } : { title: title.trim(), fileUrl: link.trim(), content: content.trim() },
      {
        onSuccess: (doc) => {
          if (doc.ingestStatus === "Failed") {
            toast.warning(`Đã lưu “${doc.title}”, chưa dùng được cho chatbot`, {
              description: doc.ingestError ?? "Chưa tạo được chỉ mục. Mở tài liệu và bấm Duyệt để thử lại.",
            });
          } else {
            toast.success(`Đã thêm “${doc.title}”`, { description: `${formatNumber(doc.chunkCount)} đoạn đã sẵn sàng cho chatbot.` });
          }
          onDone();
          onCreated?.(doc);
        },
        onError: (err) => toast.error("Chưa tải được tài liệu", { description: describeError(err) }),
      },
    );
  }

  return (
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

      <div className="flex flex-col gap-1.5">
        <Label htmlFor={`${ids}-file`}>Tệp tài liệu (.pdf, .txt, .md)</Label>
        <Input
          id={`${ids}-file`}
          type="file"
          accept=".pdf,.txt,.md,application/pdf,text/plain,text/markdown"
          onChange={(e) => void readFile(e.target.files?.[0])}
          disabled={create.isPending}
          className="py-2 file:mr-3 file:border-0 file:bg-transparent file:text-sm file:font-semibold file:text-foreground"
          aria-describedby={`${ids}-file-hint`}
        />
        <p id={`${ids}-file-hint`} className={cn("text-xs", fileError ? "text-destructive" : "text-muted-foreground")}>
          {fileError ?? (pdf ? `Đã chọn ${pdf.name}. Máy chủ sẽ đọc chữ trong tệp; PDF chỉ có ảnh quét sẽ bị từ chối.` : "Chọn tệp, hoặc dán nội dung vào ô dưới.")}
        </p>
      </div>

      <div className="flex flex-col gap-1.5">
        <Label htmlFor={`${ids}-content`}>Nội dung</Label>
        <Textarea
          id={`${ids}-content`}
          value={content}
          onChange={(e) => setContent(e.target.value)}
          rows={8}
          aria-invalid={content.length > 0 && !contentOk ? true : undefined}
          aria-describedby={`${ids}-content-hint`}
          disabled={create.isPending || pdf !== null}
        />
        <p id={`${ids}-content-hint`} className="text-xs text-muted-foreground">
          Tối thiểu {MIN_CONTENT} ký tự · {formatNumber(content.trim().length)}
        </p>
      </div>

      <div className="flex flex-col gap-1.5">
        <Label htmlFor={`${ids}-link`}>Liên kết nguồn (không bắt buộc)</Label>
        <Input
          id={`${ids}-link`}
          type="url"
          inputMode="url"
          value={link}
          onChange={(e) => setLink(e.target.value)}
          placeholder="https://www.who.int/…"
          aria-invalid={!linkOk ? true : undefined}
          aria-describedby={`${ids}-link-hint`}
          disabled={create.isPending}
        />
        <p id={`${ids}-link-hint`} className={cn("text-xs", !linkOk ? "text-destructive" : "text-muted-foreground")}>
          Hiện ở trích dẫn của chatbot. Đường dẫn phải bắt đầu bằng http:// hoặc https://
        </p>
      </div>

      <DialogFooter>
        <DialogClose asChild>
          <Button type="button" variant="outline" disabled={create.isPending}>
            Huỷ
          </Button>
        </DialogClose>
        <Button type="submit" disabled={!titleOk || !contentOk || !linkOk || create.isPending}>
          <Upload aria-hidden />
          {create.isPending ? "Đang tạo chỉ mục…" : "Tải lên"}
        </Button>
      </DialogFooter>
    </form>
  );
}

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
        {!isMock("knowledge") ? (
          <WhoUploadRealForm onDone={() => onOpenChange(false)} onCreated={onCreated} />
        ) : (
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
        )}
      </DialogContent>
    </Dialog>
  );
}
