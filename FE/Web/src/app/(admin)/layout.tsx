// src/app/(admin)/layout.tsx
import { AdminSidebar } from "@/components/admin/admin-sidebar";
import { UserMenu } from "@/components/admin/user-menu";
import { ALL_MODULES_REAL, DATA_MODE_LABEL } from "@/lib/backend_modules";

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-dvh flex-col md:flex-row">
      <AdminSidebar />
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex h-14 items-center justify-end gap-3 border-b bg-card px-4 md:px-8">
          <span
            className={
              ALL_MODULES_REAL
                ? "rounded-full bg-foreground px-3 py-1 text-xs font-bold text-background"
                : "rounded-full border border-ochre-border bg-ochre-soft px-3 py-1 text-xs font-bold text-ochre-text"
            }
          >
            {DATA_MODE_LABEL}
          </span>
          <UserMenu />
        </header>
        <main className="mx-auto w-full max-w-7xl flex-1 px-4 py-6 md:px-8">{children}</main>
      </div>
    </div>
  );
}
