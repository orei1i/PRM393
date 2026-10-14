// src/app/(admin)/layout.tsx
import { AdminSidebar } from "@/components/admin/admin-sidebar";
import { USE_MOCK_DATA } from "@/lib/api_client";

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-dvh flex-col md:flex-row">
      <AdminSidebar />
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex h-14 items-center justify-end gap-3 border-b bg-card px-4 md:px-8">
          <span
            className={
              USE_MOCK_DATA
                ? "rounded-full border border-ochre-border bg-ochre-soft px-3 py-1 text-xs font-bold text-ochre-text"
                : "rounded-full bg-foreground px-3 py-1 text-xs font-bold text-background"
            }
          >
            {USE_MOCK_DATA ? "Dữ liệu mô phỏng" : "Production"}
          </span>
          <span
            aria-label="Quản trị viên"
            className="flex size-8 items-center justify-center rounded-full bg-secondary text-xs font-extrabold text-secondary-foreground"
          >
            QT
          </span>
        </header>
        <main className="mx-auto w-full max-w-7xl flex-1 px-4 py-6 md:px-8">{children}</main>
      </div>
    </div>
  );
}
