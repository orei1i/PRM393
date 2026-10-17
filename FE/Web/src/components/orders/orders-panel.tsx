// src/components/orders/orders-panel.tsx
"use client";

import * as React from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Receipt, Search } from "lucide-react";
import { toast } from "sonner";

import { EmptyState, ErrorState } from "@/components/admin/states";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/form-controls";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useOrders } from "@/lib/hooks/use-commerce";
import { formatNumber } from "@/lib/utils";
import { ORDER_STATUS_LABEL, ORDER_STATUSES, type AdminOrder, type CommerceSummary, type OrderStatus } from "@/types/commerce";

import { OrderDrawer } from "./order-drawer";
import { OrderTable } from "./order-table";

type StatusTab = OrderStatus | "all";

const STATUS_TABS: { value: StatusTab; label: string }[] = [
  { value: "all", label: "Tất cả" },
  ...ORDER_STATUSES.map((s) => ({ value: s, label: ORDER_STATUS_LABEL[s] })),
];

export function OrdersPanel({ summary }: { summary: CommerceSummary | undefined }) {
  const params = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();
  const openParam = params.get("open");

  const [status, setStatus] = React.useState<StatusTab>("all");
  const [searchInput, setSearchInput] = React.useState("");
  const search = React.useDeferredValue(searchInput);
  const [selected, setSelected] = React.useState<AdminOrder | null>(null);
  /** Order id from `?open=` (links from /disputes) waiting for the unfiltered list. */
  const [pendingOpen, setPendingOpen] = React.useState<string | null>(null);

  React.useEffect(() => {
    if (!openParam) return;
    setStatus("all");
    setSearchInput("");
    setPendingOpen(openParam);
    router.replace(pathname, { scroll: false });
  }, [openParam, pathname, router]);

  const query = React.useMemo(() => ({ status, search }), [status, search]);
  const orders = useOrders(query);

  React.useEffect(() => {
    if (!pendingOpen || status !== "all" || search !== "" || !orders.data || orders.isPlaceholderData) return;
    const found = orders.data.find((o) => o.id === pendingOpen);
    if (found) setSelected(found);
    else toast.error("Không tìm thấy đơn hàng", { description: pendingOpen });
    setPendingOpen(null);
  }, [pendingOpen, status, search, orders.data, orders.isPlaceholderData]);

  // Keep the drawer in sync with refetched / optimistically patched rows.
  const selectedId = selected?.id ?? null;
  React.useEffect(() => {
    if (!selectedId || !orders.data) return;
    const fresh = orders.data.find((o) => o.id === selectedId);
    if (fresh) setSelected((current) => (current && current !== fresh ? fresh : current));
  }, [orders.data, selectedId]);

  const countFor = (tab: StatusTab) => {
    if (!summary) return "–";
    return formatNumber(tab === "all" ? summary.totalOrders : summary.byStatus[tab]);
  };

  const filtered = search.trim().length > 0;

  return (
    <Card className="gap-0 py-0">
      <div className="flex flex-wrap items-center gap-3 border-b p-4">
        <Tabs value={status} onValueChange={(v) => setStatus(v as StatusTab)} className="w-full min-w-0 max-w-full xl:w-auto">
          <TabsList className="max-w-full justify-start overflow-x-auto" aria-label="Lọc theo trạng thái đơn">
            {STATUS_TABS.map((t) => (
              <TabsTrigger key={t.value} value={t.value}>
                {t.label}
                <span className="rounded-full bg-muted px-1.5 font-mono text-[11px] tabular">{countFor(t.value)}</span>
              </TabsTrigger>
            ))}
          </TabsList>
        </Tabs>
        <div className="relative w-full sm:w-80 xl:ml-auto">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
          <Input
            type="search"
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            placeholder="Mã đơn, mã đặt, mã giao dịch, thành viên, chuyên gia…"
            aria-label="Tìm đơn hàng"
            className="pl-9"
          />
        </div>
        <p className="w-full text-sm text-muted-foreground" aria-live="polite">
          {orders.data ? `${formatNumber(orders.data.length)} đơn thanh toán đặt chuyên gia` : "Đang tải…"}
        </p>
      </div>

      {orders.isError && !orders.data ? (
        <ErrorState error={orders.error} onRetry={() => orders.refetch()} title="Chưa tải được đơn hàng" />
      ) : orders.data?.length === 0 ? (
        <EmptyState
          icon={Receipt}
          title={filtered || status !== "all" ? "Không có đơn hàng khớp bộ lọc" : "Chưa có đơn hàng"}
          description={filtered ? "Thử bỏ bớt từ khoá." : "Khi thành viên đồng ý giá với chuyên gia, đơn thanh toán sẽ xuất hiện ở đây."}
          action={
            filtered ? (
              <Button variant="outline" onClick={() => setSearchInput("")}>
                Xoá từ khoá
              </Button>
            ) : undefined
          }
        />
      ) : (
        <div className={orders.isFetching && !orders.isLoading ? "opacity-60 transition-opacity" : undefined}>
          <OrderTable orders={orders.data} isLoading={orders.isLoading} selectedId={selectedId} onSelect={setSelected} />
        </div>
      )}

      <OrderDrawer order={selected} onOpenChange={(open) => !open && setSelected(null)} onOrderChange={setSelected} />
    </Card>
  );
}
