// src/app/(admin)/overview/page.tsx
"use client";

import * as React from "react";
import Link from "next/link";
import {
  Activity,
  ArrowRight,
  BadgeCheck,
  Bot,
  FileText,
  Flag,
  Hourglass,
  Library,
  ShieldAlert,
  UserPlus,
  Users,
  VideoOff,
  Wallet,
  type LucideIcon,
} from "lucide-react";

import { PageHeader } from "@/components/admin/page-header";
import { ErrorState } from "@/components/admin/states";
import { BarList } from "@/components/overview/bar-list";
import { SignupsChart } from "@/components/overview/signups-chart";
import { MetricCard } from "@/components/telemetry/metric-card";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/form-controls";
import { useOverview } from "@/lib/hooks/use-admin";
import { useKnowledgeCounts } from "@/lib/hooks/use-knowledge";
import { usePayoutSummary } from "@/lib/hooks/use-payouts";
import { formatAge, formatNumber } from "@/lib/utils";
import { CONTENT_KIND_LABEL } from "@/types/admin";

const timeAgo = (iso: string) => {
  const age = formatAge(iso);
  return age === "vừa xong" ? age : `${age} trước`;
};

const today = new Intl.DateTimeFormat("vi-VN", { weekday: "long", day: "2-digit", month: "2-digit", year: "numeric" });

export default function OverviewPage() {
  const overview = useOverview();
  const knowledgeCounts = useKnowledgeCounts();
  const payoutSummary = usePayoutSummary();
  const data = overview.data;
  // Format the date on the client only: the page is prerendered at build time.
  const [todayLabel, setTodayLabel] = React.useState<string | null>(null);
  React.useEffect(() => setTodayLabel(today.format(new Date())), []);

  if (overview.isError && !data) {
    return <ErrorState error={overview.error} onRetry={() => overview.refetch()} />;
  }

  const queue: { href: string; label: string; hint: string; count?: number; icon: LucideIcon }[] = [
    { href: "/moderation", label: "Cờ AI chờ duyệt", hint: "Bài AI nghi vi phạm, cần người quyết định", count: data?.pending.aiFlags, icon: ShieldAlert },
    { href: "/content?view=pending", label: "Bài chờ duyệt", hint: "Bài AI giữ lại khi đăng, chưa lên bảng tin", count: data?.pending.pendingPosts, icon: Hourglass },
    { href: "/chefs", label: "Hồ sơ chuyên gia", hint: "Thành viên xin xác minh đầu bếp / chuyên gia", count: data?.pending.chefApplications, icon: BadgeCheck },
    { href: "/content?view=reported", label: "Bài bị báo cáo", hint: "Người dùng báo cáo từ ứng dụng di động", count: data?.pending.reportedContent, icon: Flag },
    { href: "/content?kind=video", label: "Video AI lỗi", hint: "Không trích xuất được công thức từ video", count: data?.pending.failedVideos, icon: VideoOff },
    { href: "/knowledge", label: "Tài liệu chờ duyệt", hint: "Chuyên gia đóng góp cho chatbot", count: knowledgeCounts.data?.Pending, icon: Library },
    { href: "/payouts", label: "Yêu cầu rút tiền chờ duyệt", hint: "Trên 5.000.000đ, cần chuyển khoản và xác nhận", count: payoutSummary.data?.awaitingApproval, icon: Wallet },
  ];

  return (
    <div className="flex flex-col gap-6">
      <PageHeader title="Tổng quan" description={`Hoạt động trên ứng dụng di động VeganLife${todayLabel ? ` · ${todayLabel}` : ""}`} />

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard
          label="Người dùng"
          value={data ? formatNumber(data.totalUsers) : "–"}
          hint={data ? `+${formatNumber(data.newUsers7d)} trong 7 ngày` : undefined}
          delta={data?.newUsersDelta}
          icon={Users}
          loading={overview.isLoading}
        />
        <MetricCard
          label="Hoạt động 24 giờ"
          value={data ? formatNumber(data.activeUsers24h) : "–"}
          hint="so với hôm qua"
          delta={data?.activeDelta}
          icon={Activity}
          loading={overview.isLoading}
        />
        <MetricCard
          label="Bài mới 24 giờ"
          value={data ? formatNumber(data.posts24h) : "–"}
          hint="so với hôm qua"
          delta={data?.postsDelta}
          icon={FileText}
          loading={overview.isLoading}
        />
        <MetricCard
          label="Lượt hỏi AI 24 giờ"
          value={data ? formatNumber(data.aiQueries24h) : "–"}
          hint="chatbot + thực đơn + quét"
          delta={data?.aiQueriesDelta}
          icon={Bot}
          loading={overview.isLoading}
        />
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[minmax(0,1fr)_360px]">
        <Card>
          <CardHeader>
            <CardTitle>Việc cần xử lý</CardTitle>
            <CardDescription>Mục chờ lâu nhất nằm đầu mỗi hàng đợi.</CardDescription>
          </CardHeader>
          <CardContent className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            {queue.map((q) => (
              <Link
                key={q.href}
                href={q.href}
                className="group flex items-center gap-3 rounded-lg border p-3 transition-colors hover:bg-accent focus-visible:ring-[3px] focus-visible:ring-ring/40 focus-visible:outline-none"
              >
                <span className="flex size-10 shrink-0 items-center justify-center rounded-lg bg-secondary text-secondary-foreground">
                  <q.icon className="size-5" aria-hidden />
                </span>
                <span className="min-w-0 flex-1">
                  <span className="block text-sm font-bold">{q.label}</span>
                  <span className="block truncate text-xs text-muted-foreground">{q.hint}</span>
                </span>
                {overview.isLoading ? (
                  <Skeleton className="h-6 w-8" />
                ) : (
                  <span
                    className={
                      q.count
                        ? "rounded-full border border-ochre-border bg-ochre-soft px-2.5 py-0.5 font-mono text-sm font-bold text-ochre-text tabular"
                        : "rounded-full bg-sprout-soft px-2.5 py-0.5 font-mono text-sm font-bold text-sprout-text tabular"
                    }
                  >
                    {q.count ?? 0}
                  </span>
                )}
                <ArrowRight className="size-4 text-muted-foreground transition-transform group-hover:translate-x-0.5" aria-hidden />
              </Link>
            ))}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Nội dung theo loại</CardTitle>
            <CardDescription>Tổng bài đang hiển thị trên bảng tin.</CardDescription>
          </CardHeader>
          <CardContent>
            {data ? (
              <BarList items={data.contentMix.map((m) => ({ label: CONTENT_KIND_LABEL[m.kind], value: m.count }))} />
            ) : (
              <div className="flex flex-col gap-4">
                <Skeleton className="h-8" />
                <Skeleton className="h-8" />
                <Skeleton className="h-8" />
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[minmax(0,1fr)_360px]">
        <Card>
          <CardHeader>
            <div className="flex items-center gap-2">
              <UserPlus className="size-4 text-muted-foreground" aria-hidden />
              <CardTitle>Đăng ký mới mỗi ngày</CardTitle>
            </div>
            <CardDescription>14 ngày gần nhất, từ ứng dụng iOS và Android.</CardDescription>
          </CardHeader>
          <CardContent>
            {data ? <SignupsChart data={data.signupsDaily} dimmed={overview.isFetching && !overview.isLoading} /> : <Skeleton className="h-56" />}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Nhật ký quản trị</CardTitle>
            <CardDescription>Thao tác gần đây của ban quản trị.</CardDescription>
          </CardHeader>
          <CardContent>
            {data ? (
              <ol className="flex flex-col gap-3">
                {data.recentActions.map((a) => (
                  <li key={a.id} className="text-sm">
                    <p>
                      <b>{a.actor}</b> {a.action} <span className="text-muted-foreground">“{a.target}”</span>
                    </p>
                    <p className="text-xs text-muted-foreground">{timeAgo(a.at)}</p>
                  </li>
                ))}
              </ol>
            ) : (
              <div className="flex flex-col gap-3">
                <Skeleton className="h-10" />
                <Skeleton className="h-10" />
                <Skeleton className="h-10" />
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
