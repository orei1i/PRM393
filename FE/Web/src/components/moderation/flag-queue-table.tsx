// src/components/moderation/flag-queue-table.tsx
"use client";

import { FileText, Inbox, MessageSquare, UtensilsCrossed, Video, type LucideIcon } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/form-controls";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { cn, formatAge } from "@/lib/utils";
import { CONTENT_TYPE_LABEL, FLAG_CATEGORY_LABEL, type AiFlag, type ContentType } from "@/types/moderation";

import { ScoreBar } from "./score-bar";

const TYPE_ICON: Record<ContentType, LucideIcon> = {
  post: FileText,
  comment: MessageSquare,
  video: Video,
  recipe: UtensilsCrossed,
};

/** Items waiting longer than this get an ochre age (SLA warning). */
const SLA_WARNING_MINUTES = 120;

export function FlagQueueTable({
  flags,
  isLoading,
  selectedId,
  onSelect,
}: {
  flags: AiFlag[] | undefined;
  isLoading: boolean;
  selectedId: string | null;
  onSelect: (flag: AiFlag) => void;
}) {
  if (!isLoading && flags?.length === 0) {
    return (
      <div className="flex flex-col items-center gap-2 px-6 py-16 text-center">
        <span className="flex size-12 items-center justify-center rounded-xl bg-secondary text-primary">
          <Inbox className="size-6" aria-hidden />
        </span>
        <p className="font-bold">Hàng đợi trống</p>
        <p className="max-w-sm text-sm text-muted-foreground">
          Không còn mục nào khớp bộ lọc. AI quét nội dung mới mỗi vài phút, danh sách sẽ tự cập nhật.
        </p>
      </div>
    );
  }

  return (
    <Table className="min-w-[860px]">
      <TableHeader>
        <TableRow className="hover:bg-transparent">
          <TableHead className="w-[42%] pl-5">Nội dung</TableHead>
          <TableHead>Lý do AI gắn cờ</TableHead>
          <TableHead className="w-40">Điểm độc hại</TableHead>
          <TableHead className="w-40">Độ tin cậy</TableHead>
          <TableHead className="w-28">Chờ</TableHead>
          <TableHead className="w-20 pr-5">
            <span className="sr-only">Thao tác</span>
          </TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {isLoading && !flags
          ? Array.from({ length: 5 }, (_, i) => (
              <TableRow key={i}>
                <TableCell className="pl-5">
                  <Skeleton className="mb-2 h-3 w-32" />
                  <Skeleton className="h-4 w-full" />
                </TableCell>
                <TableCell>
                  <Skeleton className="h-5 w-36 rounded-full" />
                </TableCell>
                <TableCell>
                  <Skeleton className="h-2 w-full" />
                </TableCell>
                <TableCell>
                  <Skeleton className="h-2 w-full" />
                </TableCell>
                <TableCell>
                  <Skeleton className="h-4 w-16" />
                </TableCell>
                <TableCell />
              </TableRow>
            ))
          : flags?.map((flag) => {
              const Icon = TYPE_ICON[flag.post.type];
              const ageMinutes = (Date.now() - new Date(flag.createdAt).getTime()) / 60000;
              return (
                <TableRow
                  key={flag.id}
                  data-state={flag.id === selectedId ? "selected" : undefined}
                  className="cursor-pointer"
                  onClick={() => onSelect(flag)}
                >
                  <TableCell className="pl-5">
                    <div className="mb-1 flex items-center gap-1.5 text-xs text-muted-foreground">
                      <Icon className="size-3.5" aria-hidden />
                      <span className="font-semibold text-foreground">{CONTENT_TYPE_LABEL[flag.post.type]}</span>
                      <span>· @{flag.post.author.handle}</span>
                      {flag.post.reportCount > 0 && <span>· {flag.post.reportCount} báo cáo</span>}
                    </div>
                    <p className="line-clamp-2 max-w-xl text-sm leading-snug">{flag.post.text}</p>
                  </TableCell>
                  <TableCell>
                    <Badge variant="ai">{FLAG_CATEGORY_LABEL[flag.primaryCategory]}</Badge>
                  </TableCell>
                  <TableCell>
                    <ScoreBar value={flag.toxicityScore} label="Điểm độc hại" tone={flag.toxicityScore >= 0.7 ? "ochre" : "aiLight"} />
                  </TableCell>
                  <TableCell>
                    <ScoreBar value={flag.confidence} label="Độ tin cậy của AI" />
                  </TableCell>
                  <TableCell
                    className={cn(
                      "whitespace-nowrap font-mono text-xs tabular",
                      ageMinutes > SLA_WARNING_MINUTES && "font-semibold text-ochre-text",
                    )}
                  >
                    {formatAge(flag.createdAt)}
                  </TableCell>
                  <TableCell className="pr-5 text-right">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={(e) => {
                        e.stopPropagation();
                        onSelect(flag);
                      }}
                      aria-label={`Xem chi tiết mục của @${flag.post.author.handle}`}
                    >
                      Xem
                    </Button>
                  </TableCell>
                </TableRow>
              );
            })}
      </TableBody>
    </Table>
  );
}
