// src/components/admin/admin-sidebar.tsx
"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Activity, Leaf, ShieldAlert, type LucideIcon } from "lucide-react";

import { cn } from "@/lib/utils";
import { useFlagCounts } from "@/lib/hooks/use-moderation";

const NAV: { href: string; label: string; icon: LucideIcon; badge?: "pending" }[] = [
  { href: "/moderation", label: "Kiểm duyệt AI", icon: ShieldAlert, badge: "pending" },
  { href: "/telemetry", label: "Giám sát mô hình", icon: Activity },
];

export function AdminSidebar() {
  const pathname = usePathname();
  const { data: counts } = useFlagCounts();

  return (
    <aside className="flex shrink-0 flex-col gap-6 border-b bg-card px-3 py-4 md:sticky md:top-0 md:h-dvh md:w-60 md:border-b-0 md:border-r">
      <Link href="/moderation" className="flex items-center gap-2.5 px-2">
        <span className="flex size-8 items-center justify-center rounded-lg bg-primary text-primary-foreground">
          <Leaf className="size-4" aria-hidden />
        </span>
        <span className="flex flex-col leading-tight">
          <span className="text-[15px] font-extrabold">VeganLife</span>
          <span className="text-xs text-muted-foreground">Bảng quản trị</span>
        </span>
      </Link>

      <nav aria-label="Quản trị" className="flex gap-1 md:flex-col">
        {NAV.map((item) => {
          const active = pathname.startsWith(item.href);
          const count = item.badge ? counts?.[item.badge] : undefined;
          return (
            <Link
              key={item.href}
              href={item.href}
              aria-current={active ? "page" : undefined}
              className={cn(
                "flex h-9 items-center gap-2.5 rounded-lg px-2.5 text-sm font-semibold text-muted-foreground transition-colors hover:bg-accent hover:text-foreground",
                active && "bg-secondary text-secondary-foreground",
              )}
            >
              <item.icon className="size-4" aria-hidden />
              <span className="flex-1">{item.label}</span>
              {count ? (
                <span className="rounded-full bg-ochre-soft px-2 font-mono text-[11px] font-semibold text-ochre-text">
                  {count}
                </span>
              ) : null}
            </Link>
          );
        })}
      </nav>

      <p className="mt-auto hidden px-2 text-xs leading-relaxed text-muted-foreground md:block">
        Mọi quyết định được ghi vào nhật ký kiểm duyệt cùng phiên bản mô hình và điểm số.
      </p>
    </aside>
  );
}
