// src/app/(admin)/chefs/page.tsx
"use client";

import * as React from "react";
import { BadgeCheck, RefreshCw } from "lucide-react";

import { ApplicationCard } from "@/components/chefs/application-card";
import { PageHeader } from "@/components/admin/page-header";
import { EmptyState, ErrorState } from "@/components/admin/states";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/form-controls";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useChefApplicationCounts, useChefApplications } from "@/lib/hooks/use-admin";
import { CHEF_APPLICATION_STATUS_LABEL, type ChefApplicationStatus } from "@/types/admin";

const TABS: ChefApplicationStatus[] = ["pending", "approved", "rejected"];

export default function ChefApplicationsPage() {
  const [status, setStatus] = React.useState<ChefApplicationStatus>("pending");
  const apps = useChefApplications(status);
  const counts = useChefApplicationCounts();

  return (
    <div className="flex flex-col gap-6">
      <PageHeader
        title="Duyệt chuyên gia"
        description="Thành viên gửi hồ sơ từ ứng dụng (Tôi › Trở thành chuyên gia). Đã duyệt sẽ hiện trong tab Chuyên gia và nhận đặt lịch tư vấn."
        actions={
          <Button variant="outline" onClick={() => apps.refetch()} disabled={apps.isFetching}>
            <RefreshCw className={apps.isFetching ? "animate-spin" : undefined} aria-hidden />
            Làm mới
          </Button>
        }
      />

      <Tabs value={status} onValueChange={(v) => setStatus(v as ChefApplicationStatus)} className="max-w-full">
        <TabsList className="max-w-full justify-start overflow-x-auto">
          {TABS.map((t) => (
            <TabsTrigger key={t} value={t}>
              {CHEF_APPLICATION_STATUS_LABEL[t]}
              <span className="rounded-full bg-muted px-1.5 font-mono text-[11px] tabular">{counts.data?.[t] ?? "–"}</span>
            </TabsTrigger>
          ))}
        </TabsList>
      </Tabs>

      {apps.isError && !apps.data ? (
        <Card>
          <ErrorState error={apps.error} onRetry={() => apps.refetch()} />
        </Card>
      ) : apps.isLoading ? (
        <div className="grid gap-4 xl:grid-cols-2">
          <Skeleton className="h-72 rounded-xl" />
          <Skeleton className="h-72 rounded-xl" />
        </div>
      ) : apps.data?.length === 0 ? (
        <Card>
          <EmptyState
            icon={BadgeCheck}
            title={status === "pending" ? "Không còn hồ sơ chờ duyệt" : "Chưa có hồ sơ nào"}
            description={status === "pending" ? "Hồ sơ mới từ ứng dụng di động sẽ xuất hiện ở đây." : undefined}
          />
        </Card>
      ) : (
        <div className="grid items-start gap-4 xl:grid-cols-2">
          {apps.data?.map((app) => <ApplicationCard key={app.id} application={app} />)}
        </div>
      )}
    </div>
  );
}
