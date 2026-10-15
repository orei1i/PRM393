// src/components/ai-models/model-card.tsx
"use client";

import * as React from "react";
import { Save, TriangleAlert } from "lucide-react";
import { toast } from "sonner";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogTitle } from "@/components/ui/dialog";
import { Input, Label, NativeSelect, Textarea } from "@/components/ui/form-controls";
import { Switch } from "@/components/ui/switch";
import { describeError } from "@/lib/api_error";
import { useUpdateAiModel } from "@/lib/hooks/use-ai-models";
import { AI_TASK_TITLE, THRESHOLD_MAX, THRESHOLD_MIN, type AiModel, type AiModelPatch } from "@/types/ai_models";
import { MIN_AUDIT_NOTE_LENGTH } from "@/types/moderation";

const dateTimeVi = new Intl.DateTimeFormat("vi-VN", { hour: "2-digit", minute: "2-digit", day: "2-digit", month: "2-digit", year: "numeric" });
const fmtThreshold = (n: number | null) => (n === null ? "" : n.toFixed(2));
const vi = (n: number) => n.toFixed(2).replace(".", ",");

const THRESHOLD_HINT: Partial<Record<AiModel["task"], string>> = {
  moderation: "Gắn cờ khi điểm vi phạm ≥ ngưỡng. Ngưỡng thấp bắt nhiều hơn nhưng dễ gắn nhầm.",
  vision_scan: "Chỉ nhận nguyên liệu có độ tin cậy ≥ ngưỡng.",
};

/** One model: version, on/off and threshold. Saving needs a confirm dialog with an audit note. */
export function ModelCard({ model }: { model: AiModel }) {
  const update = useUpdateAiModel();
  const [enabled, setEnabled] = React.useState(model.enabled);
  const [version, setVersion] = React.useState(model.activeVersion);
  const [threshold, setThreshold] = React.useState(fmtThreshold(model.threshold));
  /** Snapshot of what is being saved, so the dialog does not change while the optimistic update lands. */
  const [review, setReview] = React.useState<{ changes: string[]; moderationOff: boolean } | null>(null);
  const [note, setNote] = React.useState("");
  const ids = React.useId();

  // Follow the server copy (save, rollback after an error, refetch).
  React.useEffect(() => {
    setEnabled(model.enabled);
    setVersion(model.activeVersion);
    setThreshold(fmtThreshold(model.threshold));
  }, [model.enabled, model.activeVersion, model.threshold]);

  const thresholdValue = Number(threshold.replace(",", "."));
  const usesThreshold = model.threshold !== null;
  const thresholdOk =
    !usesThreshold || (threshold.trim() !== "" && Number.isFinite(thresholdValue) && thresholdValue >= THRESHOLD_MIN && thresholdValue <= THRESHOLD_MAX);
  const thresholdChanged = usesThreshold && thresholdOk && Math.abs(thresholdValue - (model.threshold ?? 0)) > 1e-9;
  const dirty = enabled !== model.enabled || version !== model.activeVersion || thresholdChanged;
  const noteOk = note.trim().length >= MIN_AUDIT_NOTE_LENGTH;
  const turningModerationOff = model.task === "moderation" && model.enabled && !enabled;

  const changes: string[] = [];
  if (enabled !== model.enabled) changes.push(enabled ? "Bật mô hình" : "Tắt mô hình");
  if (version !== model.activeVersion) changes.push(`Phiên bản: ${model.activeVersion} → ${version}`);
  if (thresholdChanged) changes.push(`Ngưỡng: ${vi(model.threshold ?? 0)} → ${vi(thresholdValue)}`);

  function save() {
    if (!dirty || !thresholdOk || !noteOk) return;
    const patch: AiModelPatch = { note: note.trim() };
    if (enabled !== model.enabled) patch.enabled = enabled;
    if (version !== model.activeVersion) patch.activeVersion = version;
    if (thresholdChanged) patch.threshold = Math.round(thresholdValue * 100) / 100;
    update.mutate(
      { id: model.id, patch },
      {
        onSuccess: (saved) => {
          toast.success(`Đã lưu ${saved.name}`, { description: "Thay đổi có hiệu lực với các lượt gọi mới." });
          setReview(null);
          setNote("");
        },
        onError: (e) => {
          toast.error("Chưa lưu được thay đổi", { description: describeError(e) });
          setReview(null);
        },
      },
    );
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="min-w-0">
            <CardTitle>{model.name}</CardTitle>
            <CardDescription>{AI_TASK_TITLE[model.task]}</CardDescription>
          </div>
          <div className="flex items-center gap-2">
            <Badge variant={model.enabled ? "sprout" : "secondary"}>{model.enabled ? "Đang chạy" : "Đang tắt"}</Badge>
            <span className="text-sm font-semibold" aria-hidden>
              Bật
            </span>
            <Switch checked={enabled} onCheckedChange={setEnabled} disabled={update.isPending} aria-label={`Bật ${model.name}`} />
          </div>
        </div>
      </CardHeader>

      <CardContent className="flex flex-col gap-4">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div className="flex flex-col gap-1.5">
            <Label htmlFor={`${ids}-version`}>Phiên bản đang chạy</Label>
            <NativeSelect id={`${ids}-version`} value={version} onChange={(e) => setVersion(e.target.value)} disabled={update.isPending}>
              {model.availableVersions.map((v) => (
                <option key={v} value={v}>
                  {v}
                  {v === model.activeVersion ? " (hiện tại)" : ""}
                </option>
              ))}
            </NativeSelect>
          </div>
          {usesThreshold && (
            <div className="flex flex-col gap-1.5">
              <Label htmlFor={`${ids}-threshold`}>
                Ngưỡng ({vi(THRESHOLD_MIN)}–{vi(THRESHOLD_MAX)})
              </Label>
              <Input
                id={`${ids}-threshold`}
                type="number"
                inputMode="decimal"
                step={0.01}
                min={THRESHOLD_MIN}
                max={THRESHOLD_MAX}
                value={threshold}
                onChange={(e) => setThreshold(e.target.value)}
                aria-invalid={!thresholdOk ? true : undefined}
                aria-describedby={`${ids}-threshold-hint`}
                disabled={update.isPending}
                className="font-mono"
              />
              <p id={`${ids}-threshold-hint`} className={thresholdOk ? "text-xs text-muted-foreground" : "text-xs text-destructive"}>
                {thresholdOk ? THRESHOLD_HINT[model.task] : `Nhập số từ ${vi(THRESHOLD_MIN)} đến ${vi(THRESHOLD_MAX)}.`}
              </p>
            </div>
          )}
        </div>

        <p
          className={
            enabled
              ? "rounded-lg bg-muted px-3 py-2 text-sm text-muted-foreground"
              : "rounded-lg border border-ochre-border bg-ochre-soft px-3 py-2 text-sm text-ochre-text"
          }
        >
          <b>Khi tắt:</b> {model.fallback}
        </p>

        <p className="text-xs text-muted-foreground">
          Cập nhật bởi {model.updatedBy ?? "hệ thống"} lúc {dateTimeVi.format(new Date(model.updatedAt))}
        </p>
      </CardContent>

      <CardFooter className="mt-auto justify-end gap-2">
        {dirty && (
          <Button
            variant="ghost"
            size="sm"
            disabled={update.isPending}
            onClick={() => {
              setEnabled(model.enabled);
              setVersion(model.activeVersion);
              setThreshold(fmtThreshold(model.threshold));
            }}
          >
            Huỷ thay đổi
          </Button>
        )}
        <Button size="sm" disabled={!dirty || !thresholdOk || update.isPending} onClick={() => setReview({ changes, moderationOff: turningModerationOff })}>
          <Save aria-hidden />
          {update.isPending ? "Đang lưu…" : "Lưu thay đổi"}
        </Button>
      </CardFooter>

      <Dialog
        open={review !== null}
        onOpenChange={(open) => {
          if (!open && !update.isPending) setReview(null);
        }}
      >
        <DialogContent>
          <DialogTitle>Lưu thay đổi cho {model.name}?</DialogTitle>
          <DialogDescription>Thay đổi áp dụng ngay cho các lượt gọi mới và được ghi vào nhật ký quản trị.</DialogDescription>
          <ul className="list-inside list-disc text-sm">
            {review?.changes.map((c) => (
              <li key={c}>{c}</li>
            ))}
          </ul>
          {review?.moderationOff && (
            <p role="alert" className="flex items-start gap-2 rounded-lg border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm text-destructive">
              <TriangleAlert className="mt-0.5 size-4 shrink-0" aria-hidden />
              Tắt kiểm duyệt AI: mọi bài mới sẽ vào hàng Chờ duyệt thủ công cho tới khi bật lại.
            </p>
          )}
          <div className="flex flex-col gap-1.5">
            <Label htmlFor={`${ids}-note`}>
              Ghi chú kiểm toán <span className="text-destructive">(bắt buộc)</span>
            </Label>
            <Textarea
              id={`${ids}-note`}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="VD: Hạ ngưỡng vì tuần qua bỏ sót nhiều bài quảng cáo."
              aria-describedby={`${ids}-note-hint`}
              aria-invalid={note.length > 0 && !noteOk ? true : undefined}
              disabled={update.isPending}
            />
            <p id={`${ids}-note-hint`} className="flex justify-between text-xs text-muted-foreground">
              <span>Tối thiểu {MIN_AUDIT_NOTE_LENGTH} ký tự</span>
              <span className="font-mono tabular">{note.trim().length}</span>
            </p>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" disabled={update.isPending}>
                Huỷ
              </Button>
            </DialogClose>
            <Button variant={review?.moderationOff ? "destructive" : "default"} disabled={!noteOk || update.isPending} onClick={save}>
              {update.isPending ? "Đang lưu…" : "Lưu thay đổi"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  );
}
