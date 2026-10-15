// src/app/(admin)/orders/page.tsx
"use client";

import * as React from "react";
import { useIsFetching, useQueryClient } from "@tanstack/react-query";
import { RefreshCw } from "lucide-react";

import { PageHeader } from "@/components/admin/page-header";
import { CommerceKpis } from "@/components/orders/commerce-kpis";
import { OrdersPanel } from "@/components/orders/orders-panel";
import { ServicesPanel } from "@/components/orders/services-panel";
import { Button } from "@/components/ui/button";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { commerceKeys, useCommerceSummary } from "@/lib/hooks/use-commerce";

type PageTab = "orders" | "services";

export default function OrdersPage() {
  const [tab, setTab] = React.useState<PageTab>("orders");
  const qc = useQueryClient();
  const fetching = useIsFetching({ queryKey: commerceKeys.all }) > 0;
  const summary = useCommerceSummary();

  return (
    <div className="flex flex-col gap-6">
      <PageHeader
        title="Đơn hàng & thanh toán"
        description="Đơn mua dịch vụ chuyên gia qua PaymentOS, quyền truy cập và doanh thu theo dịch vụ."
        actions={
          <Button variant="outline" onClick={() => qc.invalidateQueries({ queryKey: commerceKeys.all })} disabled={fetching}>
            <RefreshCw className={fetching ? "animate-spin" : undefined} aria-hidden />
            Làm mới
          </Button>
        }
      />

      <CommerceKpis summary={summary} />

      <Tabs value={tab} onValueChange={(v) => setTab(v as PageTab)} className="gap-4">
        <TabsList className="max-w-full justify-start overflow-x-auto">
          <TabsTrigger value="orders">Đơn hàng</TabsTrigger>
          <TabsTrigger value="services">Dịch vụ theo chuyên gia</TabsTrigger>
        </TabsList>
        <TabsContent value="orders" className="min-w-0">
          <OrdersPanel summary={summary.data} />
        </TabsContent>
        <TabsContent value="services" className="min-w-0">
          <ServicesPanel />
        </TabsContent>
      </Tabs>
    </div>
  );
}
