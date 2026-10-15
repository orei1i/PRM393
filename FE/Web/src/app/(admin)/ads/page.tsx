// src/app/(admin)/ads/page.tsx
"use client";

import * as React from "react";
import { Eye, Megaphone, MousePointerClick, Plus, RefreshCw, Search, Wallet } from "lucide-react";
import { toast } from "sonner";

import { PageHeader } from "@/components/admin/page-header";
import { EmptyState, ErrorState } from "@/components/admin/states";
import { AdFormDialog } from "@/components/ads/ad-form-dialog";
import { AdTable } from "@/components/ads/ad-table";
import { formatVnd } from "@/components/orders/order-badges";
import { MetricCard } from "@/components/telemetry/metric-card";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogTitle } from "@/components/ui/dialog";
import { Input, NativeSelect } from "@/components/ui/form-controls";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { describeError } from "@/lib/api_error";
import { useAds, useDeleteAd } from "@/lib/hooks/use-ads";
import { formatNumber, formatPercent } from "@/lib/utils";
import { AD_CITIES, AD_STATUS_LABEL, AD_STATUSES, type AdCampaign, type AdStatus } from "@/types/ads";

type StatusTab = AdStatus | "all";

const TABS: { value: StatusTab; label: string }[] = [{ value: "all", label: "Tất cả" }, ...AD_STATUSES.map((s) => ({ value: s, label: AD_STATUS_LABEL[s] }))];

const EVERYTHING = { status: "all", city: "all", search: "" } as const;

export default function AdsPage() {
  const [status, setStatus] = React.useState<StatusTab>("all");
  const [city, setCity] = React.useState<string>("all");
  const [searchInput, setSearchInput] = React.useState("");
  const search = React.useDeferredValue(searchInput);

  const [formOpen, setFormOpen] = React.useState(false);
  const [editing, setEditing] = React.useState<AdCampaign | null>(null);
  const [deleting, setDeleting] = React.useState<AdCampaign | null>(null);
  const remove = useDeleteAd();

  const ads = useAds(React.useMemo(() => ({ status, city, search }), [status, city, search]));
  // Tab counts: same city / search without the status filter. KPIs: every campaign.
  const unfiltered = useAds(React.useMemo(() => ({ status: "all" as const, city, search }), [city, search]));
  const everything = useAds(EVERYTHING);

  const countFor = (tab: StatusTab) => {
    const rows = unfiltered.data;
    if (!rows) return "–";
    return formatNumber(tab === "all" ? rows.length : rows.filter((a) => a.status === tab).length);
  };

  const kpi = React.useMemo(() => {
    const rows = everything.data;
    if (!rows) return null;
    const by = (s: AdStatus) => rows.filter((a) => a.status === s).length;
    const impressions = rows.reduce((n, a) => n + a.impressions, 0);
    const clicks = rows.reduce((n, a) => n + a.clicks, 0);
    return {
      running: by("Running"),
      scheduled: by("Scheduled"),
      paused: by("Paused"),
      impressions,
      clicks,
      ctr: impressions ? clicks / impressions : 0,
      spent: rows.reduce((n, a) => n + a.spent, 0),
      budget: rows.reduce((n, a) => n + a.budget, 0),
    };
  }, [everything.data]);

  const filtered = city !== "all" || search.trim().length > 0;
  const fetching = ads.isFetching || unfiltered.isFetching || everything.isFetching;

  function openCreate() {
    setEditing(null);
    setFormOpen(true);
  }

  function openEdit(ad: AdCampaign) {
    setEditing(ad);
    setFormOpen(true);
  }

  function confirmDelete() {
    if (!deleting) return;
    const target = deleting;
    remove.mutate(target.id, {
      onSuccess: () => {
        toast.success("Đã xoá quảng cáo", { description: `${target.restaurant.name} · ${target.headline}` });
        setDeleting(null);
      },
      onError: (e) => toast.error("Chưa xoá được quảng cáo", { description: describeError(e) }),
    });
  }

  return (
    <div className="flex flex-col gap-6">
      <PageHeader
        title="Quảng cáo cửa hàng"
        description="Thẻ “Được tài trợ” giới thiệu quán chay trên bảng tin của ứng dụng di động, theo thành phố và thời gian chạy."
        actions={
          <>
            <Button
              variant="outline"
              onClick={() => {
                ads.refetch();
                unfiltered.refetch();
                everything.refetch();
              }}
              disabled={fetching}
            >
              <RefreshCw className={fetching ? "animate-spin" : undefined} aria-hidden />
              Làm mới
            </Button>
            <Button onClick={openCreate}>
              <Plus aria-hidden />
              Tạo quảng cáo
            </Button>
          </>
        }
      />

      <section aria-label="Chỉ số quảng cáo" className="flex flex-col gap-3">
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <MetricCard
            label="Đang chạy"
            value={kpi ? formatNumber(kpi.running) : "–"}
            hint={kpi ? `${formatNumber(kpi.scheduled)} lên lịch · ${formatNumber(kpi.paused)} tạm dừng` : undefined}
            icon={Megaphone}
            loading={everything.isLoading}
          />
          <MetricCard
            label="Lượt hiển thị"
            value={kpi ? formatNumber(kpi.impressions) : "–"}
            hint="Tổng mọi chiến dịch"
            icon={Eye}
            loading={everything.isLoading}
          />
          <MetricCard
            label="Lượt nhấp"
            value={kpi ? formatNumber(kpi.clicks) : "–"}
            hint={kpi ? `CTR trung bình ${formatPercent(kpi.ctr)}` : undefined}
            icon={MousePointerClick}
            loading={everything.isLoading}
          />
          <MetricCard
            label="Đã chi"
            value={kpi ? formatVnd(kpi.spent) : "–"}
            hint={kpi ? `trên tổng ngân sách ${formatVnd(kpi.budget)}` : undefined}
            icon={Wallet}
            loading={everything.isLoading}
          />
        </div>
        {everything.isError && !everything.data && (
          <div role="alert" className="flex flex-wrap items-center gap-3 rounded-lg border border-destructive/30 px-4 py-2 text-sm">
            <span className="font-semibold">Chưa tải được chỉ số.</span>
            <span className="text-muted-foreground">{describeError(everything.error)}</span>
            <Button size="sm" variant="outline" className="sm:ml-auto" onClick={() => everything.refetch()}>
              Thử lại
            </Button>
          </div>
        )}
      </section>

      <Card className="gap-0 py-0">
        <div className="flex flex-wrap items-center gap-3 border-b p-4">
          <Tabs value={status} onValueChange={(v) => setStatus(v as StatusTab)} className="w-full min-w-0 max-w-full xl:w-auto">
            <TabsList className="max-w-full justify-start overflow-x-auto" aria-label="Lọc theo trạng thái quảng cáo">
              {TABS.map((t) => (
                <TabsTrigger key={t.value} value={t.value}>
                  {t.label}
                  <span className="rounded-full bg-muted px-1.5 font-mono text-[11px] tabular">{countFor(t.value)}</span>
                </TabsTrigger>
              ))}
            </TabsList>
          </Tabs>
          <div className="relative w-full sm:w-64 xl:ml-auto">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
            <Input
              type="search"
              value={searchInput}
              onChange={(e) => setSearchInput(e.target.value)}
              placeholder="Tìm tiêu đề, quán…"
              aria-label="Tìm quảng cáo"
              className="pl-9"
            />
          </div>
          <NativeSelect aria-label="Lọc theo khu vực" value={city} onChange={(e) => setCity(e.target.value)} className="w-full sm:w-48">
            <option value="all">Mọi khu vực</option>
            {AD_CITIES.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
            <option value="national">Toàn quốc</option>
          </NativeSelect>
          <p className="w-full text-sm text-muted-foreground" aria-live="polite">
            {ads.data ? `${formatNumber(ads.data.length)} chiến dịch · bấm một dòng để sửa` : "Đang tải…"}
          </p>
        </div>

        {ads.isError && !ads.data ? (
          <ErrorState error={ads.error} onRetry={() => ads.refetch()} title="Chưa tải được quảng cáo" />
        ) : ads.data?.length === 0 ? (
          <EmptyState
            icon={Megaphone}
            title={filtered || status !== "all" ? "Không có quảng cáo khớp bộ lọc" : "Chưa có quảng cáo nào"}
            description={
              filtered
                ? "Thử đổi khu vực hoặc bỏ bớt từ khoá."
                : status !== "all"
                  ? "Chưa có chiến dịch nào ở trạng thái này."
                  : "Tạo chiến dịch đầu tiên để giới thiệu quán chay trên bảng tin ứng dụng."
            }
            action={
              filtered ? (
                <Button
                  variant="outline"
                  onClick={() => {
                    setSearchInput("");
                    setCity("all");
                  }}
                >
                  Xoá bộ lọc
                </Button>
              ) : status === "all" ? (
                <Button onClick={openCreate}>
                  <Plus aria-hidden />
                  Tạo quảng cáo
                </Button>
              ) : undefined
            }
          />
        ) : (
          <div className={ads.isPlaceholderData ? "opacity-60 transition-opacity" : undefined}>
            <AdTable ads={ads.data} isLoading={ads.isLoading} onEdit={openEdit} onDelete={setDeleting} />
          </div>
        )}
      </Card>

      <AdFormDialog open={formOpen} campaign={editing} onOpenChange={setFormOpen} />

      <Dialog open={deleting !== null} onOpenChange={(open) => !open && !remove.isPending && setDeleting(null)}>
        <DialogContent>
          <DialogTitle>Xoá quảng cáo?</DialogTitle>
          <DialogDescription>
            {deleting ? `“${deleting.headline}” của ${deleting.restaurant.name}` : ""} sẽ ngừng hiển thị trên bảng tin và bị xoá cùng số liệu hiển thị,
            lượt nhấp. Không thể hoàn tác — muốn dừng tạm thời thì dùng công tắc Tạm dừng.
          </DialogDescription>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" disabled={remove.isPending}>
                Huỷ
              </Button>
            </DialogClose>
            <Button variant="destructive" disabled={remove.isPending} onClick={confirmDelete}>
              {remove.isPending ? "Đang xoá…" : "Xoá quảng cáo"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
