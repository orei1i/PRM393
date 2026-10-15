// src/components/chefs/application-card.tsx
"use client";

import * as React from "react";
import { BadgeCheck, CalendarDays, FileCheck2, FileWarning, MapPin, ThumbsDown, ThumbsUp } from "lucide-react";
import { toast } from "sonner";

import { InitialsAvatar } from "@/components/admin/initials-avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Label, Textarea } from "@/components/ui/form-controls";
import { describeError } from "@/lib/api_error";
import { useReviewChefApplication } from "@/lib/hooks/use-admin";
import { formatAge } from "@/lib/utils";
import { CHEF_APPLICATION_STATUS_LABEL, type ChefApplication } from "@/types/admin";

const MIN_NOTE = 10;
const dateVi = new Intl.DateTimeFormat("vi-VN", { day: "2-digit", month: "2-digit", year: "numeric" });

export function ApplicationCard({ application }: { application: ChefApplication }) {
  const review = useReviewChefApplication();
  const [decision, setDecision] = React.useState<"approved" | "rejected" | null>(null);
  const [note, setNote] = React.useState("");

  const pending = application.status === "pending";
  const noteRequired = decision === "rejected";
  const noteOk = note.trim().length >= MIN_NOTE || (decision === "approved" && note.trim().length === 0);

  function submit() {
    if (!decision) return;
    review.mutate(
      { applicationId: application.id, decision, note: note.trim() },
      {
        onSuccess: (app) =>
          toast.success(
            decision === "approved" ? `Đã duyệt ${app.fullName} thành chuyên gia` : `Đã từ chối hồ sơ của ${app.fullName}`,
          ),
        onError: (e) => toast.error("Chưa lưu được quyết định", { description: describeError(e) }),
      },
    );
  }

  return (
    <Card className="gap-4">
      <div className="flex flex-wrap items-start gap-3 px-5">
        <InitialsAvatar name={application.fullName} verified={application.status === "approved"} className="size-11" />
        <div className="min-w-0 flex-1">
          <p className="truncate font-bold">{application.fullName}</p>
          <p className="truncate text-sm text-muted-foreground">{application.email}</p>
          <div className="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
            <span className="inline-flex items-center gap-1">
              <MapPin className="size-3.5" aria-hidden />
              {application.city}
            </span>
            <span className="inline-flex items-center gap-1">
              <CalendarDays className="size-3.5" aria-hidden />
              {application.yearsExperience} năm kinh nghiệm
            </span>
            <span>Thành viên từ {dateVi.format(new Date(application.memberSince))} · {application.postCount} bài</span>
          </div>
        </div>
        {pending ? (
          <Badge variant="ochre">Gửi {formatAge(application.submittedAt)} trước</Badge>
        ) : (
          <Badge variant={application.status === "approved" ? "sprout" : "secondary"}>
            {application.status === "approved" && <BadgeCheck aria-hidden />}
            {CHEF_APPLICATION_STATUS_LABEL[application.status]}
          </Badge>
        )}
      </div>

      <div className="flex flex-col gap-3 px-5">
        <div className="flex flex-wrap gap-1.5">
          {application.specialties.map((s) => (
            <Badge key={s} variant="secondary">
              {s}
            </Badge>
          ))}
        </div>
        <p className="text-sm leading-relaxed">{application.bio}</p>
        <ul className="flex flex-col gap-1.5">
          {application.certificates.map((cert) => (
            <li key={cert.name} className="flex items-start gap-2 text-sm">
              {cert.fileUrl ? (
                <FileCheck2 className="mt-0.5 size-4 shrink-0 text-sprout-text" aria-hidden />
              ) : (
                <FileWarning className="mt-0.5 size-4 shrink-0 text-ochre-text" aria-hidden />
              )}
              <span className="min-w-0">
                {cert.name}
                {cert.fileUrl ? (
                  <a href={cert.fileUrl} className="ml-2 text-xs font-semibold text-primary underline-offset-4 hover:underline">
                    Xem ảnh
                  </a>
                ) : (
                  <span className="ml-2 text-xs text-ochre-text">chưa có ảnh chứng chỉ</span>
                )}
              </span>
            </li>
          ))}
        </ul>
      </div>

      {pending ? (
        <div className="flex flex-col gap-3 border-t px-5 pt-4">
          <div className="flex flex-wrap gap-2">
            <Button
              size="sm"
              variant={decision === "approved" ? "default" : "outline"}
              aria-pressed={decision === "approved"}
              onClick={() => setDecision("approved")}
            >
              <ThumbsUp aria-hidden />
              Duyệt
            </Button>
            <Button
              size="sm"
              variant={decision === "rejected" ? "destructive" : "outline"}
              aria-pressed={decision === "rejected"}
              onClick={() => setDecision("rejected")}
            >
              <ThumbsDown aria-hidden />
              Từ chối
            </Button>
          </div>

          {decision && (
            <div className="flex flex-col gap-2">
              <Label htmlFor={`note-${application.id}`}>
                Ghi chú {noteRequired ? <span className="text-ochre-text">(bắt buộc, gửi cho người đăng ký)</span> : "(không bắt buộc)"}
              </Label>
              <Textarea
                id={`note-${application.id}`}
                value={note}
                onChange={(e) => setNote(e.target.value)}
                placeholder={
                  noteRequired
                    ? "VD: Chứng chỉ không tra cứu được, vui lòng gửi ảnh bản gốc và nơi cấp."
                    : "VD: Đã gọi xác minh nơi làm việc."
                }
                aria-invalid={noteRequired && note.length > 0 && !noteOk ? true : undefined}
              />
              <div className="flex items-center justify-between gap-3">
                <p className="text-xs text-muted-foreground">
                  {noteRequired ? `${note.trim().length}/${MIN_NOTE} ký tự tối thiểu` : "Mọi quyết định được ghi vào nhật ký."}
                </p>
                <Button
                  size="sm"
                  variant={decision === "rejected" ? "destructive" : "default"}
                  disabled={!noteOk || review.isPending}
                  onClick={submit}
                >
                  {review.isPending ? "Đang lưu…" : decision === "approved" ? "Xác nhận duyệt" : "Xác nhận từ chối"}
                </Button>
              </div>
            </div>
          )}
        </div>
      ) : (
        application.reviewNote && (
          <div className="border-t px-5 pt-4 text-sm">
            <p className="text-xs text-muted-foreground">
              {application.reviewedBy} · {application.reviewedAt ? `${formatAge(application.reviewedAt)} trước` : ""}
            </p>
            <p className="mt-0.5">{application.reviewNote}</p>
          </div>
        )
      )}
    </Card>
  );
}
