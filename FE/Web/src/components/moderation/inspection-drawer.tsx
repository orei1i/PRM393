// src/components/moderation/inspection-drawer.tsx
"use client";

import { Clock, Cpu, Flag, ImageIcon, Sparkles } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { cn, formatAge, formatNumber } from "@/lib/utils";
import {
  ACTION_LABEL,
  CONTENT_TYPE_LABEL,
  FLAG_CATEGORY_LABEL,
  type AiFlag,
  type PostVisibility,
} from "@/types/moderation";

import { HighlightedText } from "./highlighted-text";
import { ModerationActionBar } from "./moderation-action-bar";
import { ScoreBar } from "./score-bar";

const VISIBILITY_LABEL: Record<PostVisibility, string> = {
  visible: "Đang hiển thị",
  auto_hidden: "AI đã tạm ẩn",
  removed: "Đã gỡ",
};

/** Side-by-side inspection: the post as users saw it vs. what the model flagged. */
export function InspectionDrawer({ flag, onOpenChange }: { flag: AiFlag | null; onOpenChange: (open: boolean) => void }) {
  return (
    <Sheet open={flag !== null} onOpenChange={onOpenChange}>
      <SheetContent className="w-full gap-0 overflow-hidden p-0 sm:max-w-4xl">
        {flag && (
          <>
            <SheetHeader className="border-b">
              <div className="flex flex-wrap items-center gap-2">
                <SheetTitle>Xem xét {CONTENT_TYPE_LABEL[flag.post.type].toLowerCase()}</SheetTitle>
                <Badge variant="ai">
                  <Sparkles aria-hidden /> {FLAG_CATEGORY_LABEL[flag.primaryCategory]}
                </Badge>
              </div>
              <SheetDescription>
                Gắn cờ {formatAge(flag.createdAt)} trước · trace <span className="font-mono">{flag.traceId}</span>
              </SheetDescription>
            </SheetHeader>

            <div className="grid min-h-0 flex-1 overflow-y-auto md:grid-cols-[1.15fr_1fr]">
              {/* Left: post content */}
              <section aria-label="Nội dung người dùng" className="flex flex-col gap-4 border-b p-5 md:border-b-0 md:border-r">
                <div className="flex items-center gap-3">
                  <span className="flex size-10 items-center justify-center rounded-full bg-sprout-soft text-sm font-extrabold text-sprout-text">
                    {flag.post.author.displayName.slice(0, 2).toUpperCase()}
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-bold">@{flag.post.author.handle}</p>
                    <p className="text-xs text-muted-foreground">
                      {flag.post.reportCount} báo cáo từ người dùng · {flag.post.author.priorWarnings} lần cảnh cáo trước
                    </p>
                  </div>
                  <Badge variant={flag.post.visibility === "auto_hidden" ? "ochre" : "secondary"}>
                    {VISIBILITY_LABEL[flag.post.visibility]}
                  </Badge>
                </div>

                <HighlightedText text={flag.post.text} spans={flag.spans} />

                {flag.post.media.map((m, i) => (
                  <div
                    key={i}
                    className="flex h-40 flex-col items-center justify-center gap-2 rounded-xl border border-dashed bg-muted text-sm text-muted-foreground"
                  >
                    <ImageIcon className="size-6" aria-hidden />
                    {m.alt}
                  </div>
                ))}

                {flag.post.ingredientTags.length > 0 && (
                  <div className="flex flex-wrap items-center gap-1.5">
                    <span className="text-xs text-muted-foreground">Nguyên liệu gắn thẻ:</span>
                    {flag.post.ingredientTags.map((tag) => (
                      <Badge key={tag} variant="secondary">
                        {tag}
                      </Badge>
                    ))}
                  </div>
                )}

                <dl className="grid grid-cols-3 gap-2 text-center">
                  {[
                    ["Lượt thích", flag.post.stats.likes],
                    ["Bình luận", flag.post.stats.comments],
                    ["Tiếp cận", flag.post.stats.reach],
                  ].map(([label, value]) => (
                    <div key={label} className="rounded-lg bg-muted px-2 py-2">
                      <dt className="text-xs text-muted-foreground">{label}</dt>
                      <dd className="font-mono text-sm font-semibold tabular">{formatNumber(Number(value))}</dd>
                    </div>
                  ))}
                </dl>
              </section>

              {/* Right: AI flag */}
              <section aria-label="Phân tích của AI" className="flex flex-col gap-4 p-5">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="text-xs font-bold uppercase tracking-wide text-ai-text">Lý do AI gắn cờ</p>
                    <p className="mt-1 font-bold">{FLAG_CATEGORY_LABEL[flag.primaryCategory]}</p>
                    <p className="mt-1 text-sm text-muted-foreground">{flag.reason}</p>
                  </div>
                  <div className="text-right">
                    <p className="font-mono text-3xl font-semibold text-ai-text tabular">{flag.confidence.toFixed(2)}</p>
                    <p className="text-xs text-muted-foreground">độ tin cậy</p>
                  </div>
                </div>

                <div className="flex flex-col gap-2 rounded-xl border p-4">
                  <p className="text-xs font-bold text-muted-foreground">Điểm theo hạng mục</p>
                  <div className="grid grid-cols-[minmax(0,10rem)_1fr] items-center gap-x-3 gap-y-2 text-sm">
                    <span>Độc hại (tổng)</span>
                    <ScoreBar value={flag.toxicityScore} label="Điểm độc hại tổng" tone={flag.toxicityScore >= 0.7 ? "ochre" : "aiLight"} />
                    {flag.scores.slice(0, 4).map((s) => (
                      <div key={s.category} className="contents">
                        <span className={cn("truncate", s.category === flag.primaryCategory && "font-bold")}>
                          {FLAG_CATEGORY_LABEL[s.category]}
                        </span>
                        <ScoreBar
                          value={s.score}
                          label={FLAG_CATEGORY_LABEL[s.category]}
                          tone={s.category === flag.primaryCategory ? "ai" : "aiLight"}
                        />
                      </div>
                    ))}
                  </div>
                </div>

                <div className="flex flex-wrap gap-2 text-xs">
                  <Badge variant="outline">
                    <Flag aria-hidden /> Chính sách {flag.policyRef}
                  </Badge>
                  <Badge variant="outline">
                    <Cpu aria-hidden /> {flag.modelVersion}
                  </Badge>
                  <Badge variant="outline">
                    <Clock aria-hidden /> {flag.latencyMs} ms
                  </Badge>
                </div>

                <p className="rounded-lg bg-ai-soft px-3 py-2 text-sm text-ai-text">
                  <Sparkles className="mr-1 inline size-4 align-[-3px]" aria-hidden />
                  AI gợi ý: <b>{ACTION_LABEL[flag.suggestedAction]}</b>. Gợi ý không bao giờ tự động gỡ bài.
                </p>
              </section>
            </div>

            <ModerationActionBar key={flag.id} flag={flag} onDecided={() => onOpenChange(false)} />
          </>
        )}
      </SheetContent>
    </Sheet>
  );
}
