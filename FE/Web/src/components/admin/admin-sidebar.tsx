// src/components/admin/admin-sidebar.tsx
"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  Activity,
  BadgeCheck,
  FileText,
  LayoutDashboard,
  Leaf,
  ShieldAlert,
  Smartphone,
  Tags,
  Users,
  type LucideIcon,
} from "lucide-react";

import { useChefApplicationCounts } from "@/lib/hooks/use-admin";
import { useFlagCounts } from "@/lib/hooks/use-moderation";
import { cn } from "@/lib/utils";

type NavItem = { href: string; label: string; icon: LucideIcon; badge?: "flags" | "chefs" };

const GROUPS: { label: string; items: NavItem[] }[] = [
  { label: "", items: [{ href: "/overview", label: "Tổng quan", icon: LayoutDashboard }] },
  {
    label: "Người dùng",
    items: [
      { href: "/users", label: "Người dùng", icon: Users },
      { href: "/chefs", label: "Duyệt chuyên gia", icon: BadgeCheck, badge: "chefs" },
    ],
  },
  {
    label: "Nội dung",
    items: [
      { href: "/content", label: "Quản lý nội dung", icon: FileText },
      { href: "/moderation", label: "Kiểm duyệt AI", icon: ShieldAlert, badge: "flags" },
      { href: "/catalog", label: "Danh mục", icon: Tags },
    ],
  },
  { label: "Hệ thống", items: [{ href: "/telemetry", label: "Giám sát AI", icon: Activity }] },
];

export function AdminSidebar() {
  const pathname = usePathname();
  const { data: flagCounts } = useFlagCounts();
  const { data: chefCounts } = useChefApplicationCounts();
  const badges = { flags: flagCounts?.pending, chefs: chefCounts?.pending };

  return (
    <aside className="flex shrink-0 flex-col gap-5 border-b bg-card px-3 py-4 md:sticky md:top-0 md:h-dvh md:w-64 md:border-b-0 md:border-r">
      <Link href="/overview" className="flex items-center gap-2.5 px-2">
        <span className="flex size-8 items-center justify-center rounded-lg bg-primary text-primary-foreground">
          <Leaf className="size-4" aria-hidden />
        </span>
        <span className="flex flex-col leading-tight">
          <span className="text-[15px] font-extrabold">VeganLife</span>
          <span className="text-xs text-muted-foreground">Bảng quản trị</span>
        </span>
      </Link>

      <nav aria-label="Quản trị" className="-mx-1 flex gap-1 overflow-x-auto px-1 pb-1 md:flex-col md:gap-4 md:overflow-visible md:pb-0">
        {GROUPS.map((group) => (
          <div key={group.label || "root"} className="flex gap-1 md:flex-col">
            {group.label && (
              <p className="hidden px-2.5 pb-1 text-[11px] font-bold uppercase tracking-wider text-muted-foreground md:block">
                {group.label}
              </p>
            )}
            {group.items.map((item) => {
              const active = pathname.startsWith(item.href);
              const count = item.badge ? badges[item.badge] : undefined;
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  aria-current={active ? "page" : undefined}
                  className={cn(
                    "flex h-9 shrink-0 items-center gap-2.5 rounded-lg px-2.5 text-sm font-semibold whitespace-nowrap text-muted-foreground transition-colors hover:bg-accent hover:text-foreground",
                    active && "bg-secondary text-secondary-foreground",
                  )}
                >
                  <item.icon className="size-4" aria-hidden />
                  <span className="flex-1">{item.label}</span>
                  {count ? (
                    <span className="rounded-full bg-ochre-soft px-2 font-mono text-[11px] font-semibold text-ochre-text">{count}</span>
                  ) : null}
                </Link>
              );
            })}
          </div>
        ))}
      </nav>

      <div className="mt-auto hidden gap-2.5 rounded-lg bg-secondary px-3 py-3 text-xs leading-relaxed text-secondary-foreground md:flex">
        <Smartphone className="mt-0.5 size-4 shrink-0" aria-hidden />
        <p>Người dùng dùng ứng dụng di động VeganLife. Web này chỉ để kiểm duyệt và quản lý.</p>
      </div>
    </aside>
  );
}
