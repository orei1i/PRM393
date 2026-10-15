// src/app/(admin)/users/page.tsx
"use client";

import * as React from "react";
import { RefreshCw, Search, Users } from "lucide-react";

import { PageHeader } from "@/components/admin/page-header";
import { EmptyState, ErrorState } from "@/components/admin/states";
import { UserDrawer } from "@/components/users/user-drawer";
import { UserTable } from "@/components/users/user-table";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input, NativeSelect } from "@/components/ui/form-controls";
import { useUsers } from "@/lib/hooks/use-admin";
import { formatNumber } from "@/lib/utils";
import {
  USER_ROLE_LABEL,
  USER_ROLES,
  USER_STATUS_LABEL,
  USER_STATUSES,
  type AdminUser,
  type UserRole,
  type UserStatus,
} from "@/types/admin";

export default function UsersPage() {
  const [searchInput, setSearchInput] = React.useState("");
  const search = React.useDeferredValue(searchInput);
  const [role, setRole] = React.useState<UserRole | "all">("all");
  const [status, setStatus] = React.useState<UserStatus | "all">("all");
  const [selected, setSelected] = React.useState<AdminUser | null>(null);

  const query = React.useMemo(() => ({ search, role, status }), [search, role, status]);
  const users = useUsers(query);

  // Keep the drawer in sync after a role/status change refreshes the list.
  const selectedId = selected?.id ?? null;
  React.useEffect(() => {
    if (!selectedId || !users.data) return;
    const fresh = users.data.find((u) => u.id === selectedId);
    if (fresh) setSelected((current) => (current && current !== fresh ? fresh : current));
  }, [users.data, selectedId]);

  const filtered = role !== "all" || status !== "all" || search.trim().length > 0;

  return (
    <div className="flex flex-col gap-6">
      <PageHeader
        title="Người dùng"
        description="Tài khoản trên ứng dụng VeganLife. Chọn một dòng để xem chi tiết và xử lý."
        actions={
          <Button variant="outline" onClick={() => users.refetch()} disabled={users.isFetching}>
            <RefreshCw className={users.isFetching ? "animate-spin" : undefined} aria-hidden />
            Làm mới
          </Button>
        }
      />

      <Card className="gap-0 py-0">
        <div className="flex flex-wrap items-center gap-3 border-b p-4">
          <div className="relative w-full sm:w-72">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
            <Input
              type="search"
              value={searchInput}
              onChange={(e) => setSearchInput(e.target.value)}
              placeholder="Tìm tên, email, số điện thoại…"
              aria-label="Tìm người dùng"
              className="pl-9"
            />
          </div>
          <NativeSelect
            aria-label="Lọc theo vai trò"
            value={role}
            onChange={(e) => setRole(e.target.value as UserRole | "all")}
            className="w-full sm:w-44"
          >
            <option value="all">Tất cả vai trò</option>
            {USER_ROLES.map((r) => (
              <option key={r} value={r}>
                {USER_ROLE_LABEL[r]}
              </option>
            ))}
          </NativeSelect>
          <NativeSelect
            aria-label="Lọc theo trạng thái"
            value={status}
            onChange={(e) => setStatus(e.target.value as UserStatus | "all")}
            className="w-full sm:w-44"
          >
            <option value="all">Tất cả trạng thái</option>
            {USER_STATUSES.map((s) => (
              <option key={s} value={s}>
                {USER_STATUS_LABEL[s]}
              </option>
            ))}
          </NativeSelect>
          <p className="ml-auto text-sm text-muted-foreground" aria-live="polite">
            {users.data ? `${formatNumber(users.data.length)} người dùng` : "Đang tải…"}
          </p>
        </div>

        {users.isError && !users.data ? (
          <ErrorState error={users.error} onRetry={() => users.refetch()} title="Chưa tải được danh sách" />
        ) : users.data?.length === 0 ? (
          <EmptyState
            icon={Users}
            title="Không có người dùng khớp bộ lọc"
            description={filtered ? "Thử bỏ bớt từ khoá hoặc chọn lại vai trò / trạng thái." : undefined}
            action={
              filtered ? (
                <Button
                  variant="outline"
                  onClick={() => {
                    setSearchInput("");
                    setRole("all");
                    setStatus("all");
                  }}
                >
                  Xoá bộ lọc
                </Button>
              ) : undefined
            }
          />
        ) : (
          <div className={users.isFetching && !users.isLoading ? "opacity-60 transition-opacity" : undefined}>
            <UserTable users={users.data} isLoading={users.isLoading} selectedId={selectedId} onSelect={setSelected} />
          </div>
        )}
      </Card>

      <UserDrawer user={selected} onOpenChange={(open) => !open && setSelected(null)} />
    </div>
  );
}
