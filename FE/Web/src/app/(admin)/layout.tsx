// src/app/(admin)/layout.tsx
import { AdminSidebar } from "@/components/admin/admin-sidebar";
import { DataModeBadge } from "@/components/admin/data-mode-badge";
import { UserMenu } from "@/components/admin/user-menu";

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-dvh flex-col md:flex-row">
      <AdminSidebar />
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex h-14 items-center justify-end gap-3 border-b bg-card px-4 md:px-8">
          <DataModeBadge />
          <UserMenu />
        </header>
        <main className="mx-auto w-full max-w-7xl flex-1 px-4 py-6 md:px-8">{children}</main>
      </div>
    </div>
  );
}
