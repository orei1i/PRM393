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
  type AdminRestaurant,
  type RestaurantCertifiedFilter,
  type RestaurantSource,
} from "@/types/restaurants";

const TABS: { value: RestaurantCertifiedFilter; label: string }[] = [
  { value: "all", label: "Tất cả" },
  { value: "uncertified", label: "Chưa chứng nhận" },
  { value: "certified", label: "Đã chứng nhận" },
];

export default function RestaurantsPage() {
  const [certified, setCertified] = React.useState<RestaurantCertifiedFilter>("all");
  const [source, setSource] = React.useState<RestaurantSource>("all");
  const [searchInput, setSearchInput] = React.useState("");
  const search = React.useDeferredValue(searchInput);
  const [selected, setSelected] = React.useState<AdminRestaurant | null>(null);

  const query = React.useMemo(() => ({ certified, source, search }), [certified, source, search]);
  const restaurants = useRestaurants(query);
  // Tab counts: the same source/search without the certification filter (one shared request on "Tất cả").
  const unfiltered = useRestaurants(React.useMemo(() => ({ certified: "all" as const, source, search }), [source, search]));

  // Keep the drawer in sync with refetched / optimistically patched rows.
  const selectedId = selected?.id ?? null;
  React.useEffect(() => {
    if (!selectedId || !restaurants.data) return;
    const fresh = restaurants.data.find((r) => r.id === selectedId) ?? unfiltered.data?.find((r) => r.id === selectedId);
    if (fresh) setSelected((current) => (current && current !== fresh ? fresh : current));
  }, [restaurants.data, unfiltered.data, selectedId]);

  const countFor = (tab: RestaurantCertifiedFilter) => {
    const rows = unfiltered.data;
    if (!rows) return "–";
    if (tab === "all") return formatNumber(rows.length);
    return formatNumber(rows.filter((r) => r.isVeganCertified === (tab === "certified")).length);
  };

  const filtered = source !== "all" || search.trim().length > 0;
  const withoutCoords = restaurants.data?.filter((r) => r.latitude === null || r.longitude === null).length ?? 0;

  return (
    <div className="flex flex-col gap-6">
      <PageHeader
        title="Quán chay"
        description="Quán do người dùng gợi ý từ ứng dụng và do Ban quản trị thêm. Xác minh rồi bật chứng nhận thuần chay."
        actions={
          <Button
            variant="outline"
            onClick={() => {
              restaurants.refetch();
              if (certified !== "all") unfiltered.refetch();
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
            value={certified}
            onValueChange={(v) => setCertified(v as RestaurantCertifiedFilter)}
            className="w-full min-w-0 max-w-full lg:w-auto"
          >
            <TabsList className="max-w-full justify-start overflow-x-auto" aria-label="Lọc theo chứng nhận">
              {TABS.map((t) => (
                <TabsTrigger key={t.value} value={t.value}>
                  {t.label}
                  <span className="rounded-full bg-muted px-1.5 font-mono text-[11px] tabular">{countFor(t.value)}</span>
                </TabsTrigger>
              ))}
            </TabsList>
          </Tabs>
          <div className="relative w-full sm:w-64 lg:ml-auto">
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
            aria-label="Lọc theo nguồn"
            value={source}
            onChange={(e) => setSource(e.target.value as RestaurantSource)}
            className="w-full sm:w-48"
          >
            <option value="all">Tất cả nguồn</option>
            <option value="user">{RESTAURANT_SOURCE_LABEL.user}</option>
            <option value="admin">{RESTAURANT_SOURCE_LABEL.admin}</option>
          </NativeSelect>
          <p className="w-full text-sm text-muted-foreground" aria-live="polite">
            {restaurants.data
              ? `${formatNumber(restaurants.data.length)} quán${withoutCoords ? ` · ${formatNumber(withoutCoords)} chưa có toạ độ` : ""}`
              : "Đang tải…"}
          </p>
        </div>

        {restaurants.isError && !restaurants.data ? (
          <ErrorState error={restaurants.error} onRetry={() => restaurants.refetch()} title="Chưa tải được danh sách quán" />
        ) : restaurants.data?.length === 0 ? (
          <EmptyState
            icon={Store}
            title={
              certified === "uncertified" && !filtered ? "Không còn quán chờ chứng nhận" : "Không có quán khớp bộ lọc"
            }
            description={
              certified === "uncertified" && !filtered
                ? "Quán người dùng gợi ý từ ứng dụng sẽ xuất hiện ở đây."
                : "Thử đổi nguồn hoặc bỏ bớt từ khoá."
            }
            action={
              filtered ? (
                <Button
                  variant="outline"
                  onClick={() => {
                    setSearchInput("");
                    setSource("all");
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
