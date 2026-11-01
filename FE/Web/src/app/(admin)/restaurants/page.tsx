// src/app/(admin)/restaurants/page.tsx
"use client";

import * as React from "react";
import { RefreshCw, Search, Store } from "lucide-react";

import { PageHeader } from "@/components/admin/page-header";
import { EmptyState, ErrorState } from "@/components/admin/states";
import { RestaurantDrawer } from "@/components/restaurants/restaurant-drawer";
import { RestaurantTable } from "@/components/restaurants/restaurant-table";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input, NativeSelect } from "@/components/ui/form-controls";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useRestaurants } from "@/lib/hooks/use-restaurants";
import { formatNumber } from "@/lib/utils";
import {
  RESTAURANT_SOURCE_LABEL,
  RESTAURANT_STATUS_LABEL,
  RESTAURANT_STATUSES,
  type AdminRestaurant,
  type RestaurantCertifiedFilter,
  type RestaurantSource,
  type RestaurantStatus,
} from "@/types/restaurants";

type StatusTab = RestaurantStatus | "all";

const TABS: { value: StatusTab; label: string }[] = [
  ...RESTAURANT_STATUSES.map((s) => ({ value: s as StatusTab, label: RESTAURANT_STATUS_LABEL[s] })),
  { value: "all", label: "Tất cả" },
];

const EMPTY: Record<StatusTab, { title: string; description: string }> = {
  Pending: { title: "Không còn quán chờ duyệt", description: "Quán người dùng gợi ý từ ứng dụng sẽ xuất hiện ở đây; chưa duyệt thì chưa hiện công khai." },
  Approved: { title: "Chưa có quán đã duyệt", description: "Quán đã duyệt hiện công khai trong ứng dụng và mới được chứng nhận." },
  Rejected: { title: "Chưa có quán bị từ chối", description: "Quán bị từ chối kèm lý do gửi cho người gợi ý nằm ở đây." },
  all: { title: "Chưa có quán nào", description: "Quán do người dùng gợi ý hoặc Ban quản trị thêm sẽ xuất hiện ở đây." },
};

export default function RestaurantsPage() {
  const [status, setStatus] = React.useState<StatusTab>("Pending");
  const [certified, setCertified] = React.useState<RestaurantCertifiedFilter>("all");
  const [source, setSource] = React.useState<RestaurantSource>("all");
  const [searchInput, setSearchInput] = React.useState("");
  const search = React.useDeferredValue(searchInput);
  const [selected, setSelected] = React.useState<AdminRestaurant | null>(null);

  const query = React.useMemo(() => ({ status, certified, source, search }), [status, certified, source, search]);
  const restaurants = useRestaurants(query);
  // Tab counts: the same certification/source/search without the status filter (one shared request on "Tất cả").
  const unfiltered = useRestaurants(React.useMemo(() => ({ status: "all" as const, certified, source, search }), [certified, source, search]));

  // Keep the drawer in sync with refetched / optimistically patched rows.
  const selectedId = selected?.id ?? null;
  React.useEffect(() => {
    if (!selectedId || !restaurants.data) return;
    const fresh = restaurants.data.find((r) => r.id === selectedId) ?? unfiltered.data?.find((r) => r.id === selectedId);
    if (fresh) setSelected((current) => (current && current !== fresh ? fresh : current));
  }, [restaurants.data, unfiltered.data, selectedId]);

  const countFor = (tab: StatusTab) => {
    const rows = unfiltered.data;
    if (!rows) return "–";
    return formatNumber(tab === "all" ? rows.length : rows.filter((r) => r.status === tab).length);
  };

  const filtered = certified !== "all" || source !== "all" || search.trim().length > 0;
  const withoutCoords = restaurants.data?.filter((r) => r.latitude === null || r.longitude === null).length ?? 0;

  return (
    <div className="flex flex-col gap-6">
      <PageHeader
        title="Quán chay"
        description="Quán người dùng gợi ý chờ duyệt ở đây, duyệt xong mới hiện công khai. Chứng nhận thuần chay là bước riêng, chỉ cho quán đã duyệt."
        actions={
          <Button
            variant="outline"
            onClick={() => {
              restaurants.refetch();
              if (status !== "all") unfiltered.refetch();
            }}
            disabled={restaurants.isFetching}
          >
            <RefreshCw className={restaurants.isFetching ? "animate-spin" : undefined} aria-hidden />
            Làm mới
          </Button>
        }
      />

      <Card className="gap-0 py-0">
        <div className="flex flex-wrap items-center gap-3 border-b p-4">
          <Tabs
            value={status}
            onValueChange={(v) => setStatus(v as StatusTab)}
            className="w-full min-w-0 max-w-full lg:w-auto"
          >
            <TabsList className="max-w-full justify-start overflow-x-auto" aria-label="Lọc theo trạng thái duyệt">
              {TABS.map((t) => (
                <TabsTrigger key={t.value} value={t.value}>
                  {t.label}
                  <span className="rounded-full bg-muted px-1.5 font-mono text-[11px] tabular">{countFor(t.value)}</span>
                </TabsTrigger>
              ))}
            </TabsList>
          </Tabs>
          <div className="relative w-full sm:w-52 lg:ml-auto">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
            <Input
              type="search"
              value={searchInput}
              onChange={(e) => setSearchInput(e.target.value)}
              placeholder="Tìm tên quán, địa chỉ…"
              aria-label="Tìm quán"
              className="pl-9"
            />
          </div>
          <NativeSelect
            aria-label="Lọc theo chứng nhận"
            value={certified}
            onChange={(e) => setCertified(e.target.value as RestaurantCertifiedFilter)}
            className="w-full sm:w-44"
          >
            <option value="all">Mọi chứng nhận</option>
            <option value="uncertified">Chưa chứng nhận</option>
            <option value="certified">Đã chứng nhận</option>
          </NativeSelect>
          <NativeSelect
            aria-label="Lọc theo nguồn"
            value={source}
            onChange={(e) => setSource(e.target.value as RestaurantSource)}
            className="w-full sm:w-40"
          >
            <option value="all">Tất cả nguồn</option>
            <option value="user">{RESTAURANT_SOURCE_LABEL.user}</option>
            <option value="admin">{RESTAURANT_SOURCE_LABEL.admin}</option>
          </NativeSelect>
          <p className="w-full text-sm text-muted-foreground" aria-live="polite">
            {restaurants.data
              ? `${formatNumber(restaurants.data.length)} quán${withoutCoords ? ` · ${formatNumber(withoutCoords)} chưa có toạ độ` : ""}`
              : restaurants.isError ? "" : "Đang tải…"}
          </p>
        </div>

        {restaurants.isError && !restaurants.data ? (
          <ErrorState error={restaurants.error} onRetry={() => restaurants.refetch()} title="Chưa tải được danh sách quán" />
        ) : restaurants.data?.length === 0 ? (
          <EmptyState
            icon={Store}
            title={filtered ? "Không có quán khớp bộ lọc" : EMPTY[status].title}
            description={filtered ? "Thử đổi chứng nhận, nguồn hoặc bỏ bớt từ khoá." : EMPTY[status].description}
            action={
              filtered ? (
                <Button
                  variant="outline"
                  onClick={() => {
                    setSearchInput("");
                    setSource("all");
                    setCertified("all");
                  }}
                >
                  Xoá bộ lọc
                </Button>
              ) : undefined
            }
          />
        ) : (
          <div className={restaurants.isFetching && !restaurants.isLoading ? "opacity-60 transition-opacity" : undefined}>
            <RestaurantTable
              restaurants={restaurants.data}
              isLoading={restaurants.isLoading}
              selectedId={selectedId}
              onSelect={setSelected}
            />
          </div>
        )}
      </Card>

      <RestaurantDrawer restaurant={selected} onOpenChange={(open) => !open && setSelected(null)} />
    </div>
  );
}
