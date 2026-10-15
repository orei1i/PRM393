// src/components/ads/ad-table.tsx
"use client";

import { Pencil, ShieldCheck, Trash2 } from "lucide-react";
import { toast } from "sonner";

import { formatVnd } from "@/components/orders/order-badges";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/form-controls";
import { Switch } from "@/components/ui/switch";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { describeError } from "@/lib/api_error";
import { useSetAdPaused } from "@/lib/hooks/use-ads";
import { cn, formatNumber, formatPercent } from "@/lib/utils";
import { adCtr, type AdCampaign } from "@/types/ads";

import { AdStatusBadge, CtaBadge, formatDateRange } from "./ad-badges";

/** Optimistic pause / resume with toast; reverts (via the hook) on error. Disabled once ended. */
export function AdPauseSwitch({ ad, className }: { ad: AdCampaign; className?: string }) {
  const setPaused = useSetAdPaused();
  const ended = ad.status === "Ended";
  return (
    <Switch
      checked={!ad.isPaused && !ended}
      disabled={ended || setPaused.isPending}
      className={className}
      aria-label={ended ? `Quảng cáo “${ad.headline}” đã kết thúc` : ad.isPaused ? `Chạy lại quảng cáo “${ad.headline}”` : `Tạm dừng quảng cáo “${ad.headline}”`}
      onCheckedChange={(on) =>
        setPaused.mutate(
          { id: ad.id, paused: !on },
          {
            onSuccess: (updated) =>
              toast.success(on ? "Đã chạy lại quảng cáo" : "Đã tạm dừng quảng cáo", {
                description: `${updated.restaurant.name} · ${updated.status === "Scheduled" ? "sẽ chạy từ ngày bắt đầu" : updated.headline}`,
              }),
            onError: (e) => toast.error(on ? "Chưa chạy lại được quảng cáo" : "Chưa tạm dừng được quảng cáo", { description: describeError(e) }),
          },
        )
      }
    />
  );
}

function BudgetBar({ ad }: { ad: AdCampaign }) {
  const ratio = ad.budget > 0 ? Math.min(1, ad.spent / ad.budget) : 0;
  return (
    <div className="flex min-w-36 flex-col gap-1">
      <span className="font-mono text-xs tabular">
        <span className="font-semibold">{formatVnd(ad.spent)}</span>
        <span className="text-muted-foreground"> / {formatVnd(ad.budget)}</span>
      </span>
      <span
        className="h-1.5 w-full overflow-hidden rounded-full bg-muted"
        role="progressbar"
        aria-label="Ngân sách đã chi"
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={Math.round(ratio * 100)}
      >
        <span className={cn("block h-full rounded-full", ratio >= 0.9 ? "bg-ochre" : "bg-primary")} style={{ width: `${ratio * 100}%` }} />
      </span>
    </div>
  );
}

export function AdTable({
  ads,
  isLoading,
  onEdit,
  onDelete,
}: {
  ads: AdCampaign[] | undefined;
  isLoading: boolean;
  onEdit: (ad: AdCampaign) => void;
  onDelete: (ad: AdCampaign) => void;
}) {
  return (
    <Table className="min-w-[1180px]">
      <TableHeader>
        <TableRow className="hover:bg-transparent">
          <TableHead className="w-[18%]">Quán</TableHead>
          <TableHead className="w-[26%]">Nội dung</TableHead>
          <TableHead>Khu vực</TableHead>
          <TableHead>Thời gian</TableHead>
          <TableHead>Trạng thái</TableHead>
          <TableHead className="text-right">Hiển thị</TableHead>
          <TableHead className="text-right">Nhấp · CTR</TableHead>
          <TableHead>Ngân sách</TableHead>
          <TableHead>
            <span className="sr-only">Thao tác</span>
          </TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {isLoading
          ? Array.from({ length: 5 }, (_, i) => (
              <TableRow key={i}>
                <TableCell colSpan={9}>
                  <Skeleton className="h-12" />
                </TableCell>
              </TableRow>
            ))
          : ads?.map((ad) => (
              <TableRow
                key={ad.id}
                tabIndex={0}
                onClick={() => onEdit(ad)}
                onKeyDown={(e) => {
                  if (e.target === e.currentTarget && (e.key === "Enter" || e.key === " ")) {
                    e.preventDefault();
                    onEdit(ad);
                  }
                }}
                className="cursor-pointer"
                aria-label={`Sửa quảng cáo “${ad.headline}” của ${ad.restaurant.name}`}
              >
                <TableCell className="whitespace-normal">
                  <span className="flex items-center gap-1 font-semibold">
                    <span className="line-clamp-2">{ad.restaurant.name}</span>
                    {ad.restaurant.isVeganCertified && <ShieldCheck className="size-4 shrink-0 text-sprout-text" aria-label="Chứng nhận thuần chay" />}
                  </span>
                  <span className="line-clamp-1 text-xs text-muted-foreground">{ad.restaurant.address}</span>
                </TableCell>
                <TableCell className="whitespace-normal">
                  <span className="line-clamp-1 font-semibold">{ad.headline}</span>
                  <span className="line-clamp-2 text-xs text-muted-foreground">{ad.message}</span>
                  <span className="mt-1 block">
                    <CtaBadge cta={ad.ctaType} />
                  </span>
                </TableCell>
                <TableCell className={ad.targetCity ? undefined : "text-muted-foreground"}>{ad.targetCity ?? "Toàn quốc"}</TableCell>
                <TableCell className="text-muted-foreground">{formatDateRange(ad.startAt, ad.endAt)}</TableCell>
                {/* The switch acts on its own; clicks and keys must not open the editor. */}
                <TableCell onClick={(e) => e.stopPropagation()} onKeyDown={(e) => e.stopPropagation()}>
                  <div className="flex items-center gap-2">
                    <AdPauseSwitch ad={ad} />
                    <AdStatusBadge status={ad.status} />
                  </div>
                </TableCell>
                <TableCell className="text-right font-mono tabular">{formatNumber(ad.impressions)}</TableCell>
                <TableCell className="text-right font-mono tabular">
                  {formatNumber(ad.clicks)}
                  <span className="block text-xs text-muted-foreground">{ad.impressions ? formatPercent(adCtr(ad)) : "—"}</span>
                </TableCell>
                <TableCell>
                  <BudgetBar ad={ad} />
                </TableCell>
                <TableCell onClick={(e) => e.stopPropagation()} onKeyDown={(e) => e.stopPropagation()}>
                  <div className="flex items-center justify-end gap-1">
                    <Button size="icon" variant="ghost" aria-label={`Sửa quảng cáo “${ad.headline}”`} title="Sửa" onClick={() => onEdit(ad)}>
                      <Pencil aria-hidden />
                    </Button>
                    <Button
                      size="icon"
                      variant="ghost"
                      className="text-destructive hover:text-destructive"
                      aria-label={`Xoá quảng cáo “${ad.headline}”`}
                      title="Xoá"
                      onClick={() => onDelete(ad)}
                    >
                      <Trash2 aria-hidden />
                    </Button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
      </TableBody>
    </Table>
  );
}
