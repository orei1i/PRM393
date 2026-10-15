// src/components/orders/services-panel.tsx
"use client";

import * as React from "react";
import { Search, Store } from "lucide-react";

import { EmptyState, ErrorState } from "@/components/admin/states";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input, NativeSelect } from "@/components/ui/form-controls";
import { useAdminServices } from "@/lib/hooks/use-commerce";
import { formatNumber } from "@/lib/utils";

import { ServiceTable } from "./service-table";

const ALL_SERVICES = { chefId: "all", search: "" } as const;

export function ServicesPanel() {
  const [chefId, setChefId] = React.useState<string>("all");
  const [searchInput, setSearchInput] = React.useState("");
  const search = React.useDeferredValue(searchInput);

  const query = React.useMemo(() => ({ chefId, search }), [chefId, search]);
  const services = useAdminServices(query);
  // Chef options come from the unfiltered list (same request when no filter is set).
  const all = useAdminServices(ALL_SERVICES);
  const chefs = React.useMemo(() => {
    const seen = new Map<string, string>();
    for (const s of all.data ?? []) if (!seen.has(s.chefId)) seen.set(s.chefId, s.chefName);
    return [...seen].map(([id, name]) => ({ id, name })).sort((a, b) => a.name.localeCompare(b.name, "vi"));
  }, [all.data]);

  const filtered = chefId !== "all" || search.trim().length > 0;

  return (
    <Card className="gap-0 py-0">
      <div className="flex flex-wrap items-center gap-3 border-b p-4">
        <NativeSelect aria-label="Lọc theo chuyên gia" value={chefId} onChange={(e) => setChefId(e.target.value)} className="w-full sm:w-64">
          <option value="all">Tất cả chuyên gia</option>
          {chefs.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </NativeSelect>
        <div className="relative w-full sm:ml-auto sm:w-72">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
          <Input
            type="search"
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            placeholder="Tìm dịch vụ, chuyên gia…"
            aria-label="Tìm dịch vụ"
            className="pl-9"
          />
        </div>
        <p className="w-full text-sm text-muted-foreground">
          Doanh thu = tổng số tiền các đơn đang “Đã thanh toán” (đơn hoàn tiền không tính).
        </p>
      </div>

      {services.isError && !services.data ? (
        <ErrorState error={services.error} onRetry={() => services.refetch()} title="Chưa tải được dịch vụ" />
      ) : services.data?.length === 0 ? (
        <EmptyState
          icon={Store}
          title={filtered ? "Không có dịch vụ khớp bộ lọc" : "Chưa có dịch vụ nào"}
          description={filtered ? "Thử chọn chuyên gia khác hoặc bỏ bớt từ khoá." : "Chuyên gia tạo dịch vụ trong ứng dụng di động."}
          action={
            filtered ? (
              <Button
                variant="outline"
                onClick={() => {
                  setChefId("all");
                  setSearchInput("");
                }}
              >
                Xoá bộ lọc
              </Button>
            ) : undefined
          }
        />
      ) : (
        <div className={services.isFetching && !services.isLoading ? "opacity-60 transition-opacity" : undefined}>
          <ServiceTable services={services.data} isLoading={services.isLoading} />
          {services.data && (
            <p className="sr-only" aria-live="polite">
              {formatNumber(services.data.length)} dịch vụ
            </p>
          )}
        </div>
      )}
    </Card>
  );
}
