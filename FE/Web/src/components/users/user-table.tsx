// src/components/users/user-table.tsx
"use client";

import { Flag } from "lucide-react";

import { InitialsAvatar } from "@/components/admin/initials-avatar";
import { Skeleton } from "@/components/ui/form-controls";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { formatNumber } from "@/lib/utils";
import type { AdminUser } from "@/types/admin";

import { UserRoleBadges, UserStatusBadge } from "./status-badge";

const dateVi = new Intl.DateTimeFormat("vi-VN", { day: "2-digit", month: "2-digit", year: "numeric" });

export function UserTable({
  users,
  isLoading,
  selectedId,
  onSelect,
}: {
  users: AdminUser[] | undefined;
  isLoading: boolean;
  selectedId: string | null;
  onSelect: (user: AdminUser) => void;
}) {
  return (
    <Table className="min-w-[860px]">
      <TableHeader>
        <TableRow className="hover:bg-transparent">
          <TableHead>Người dùng</TableHead>
          <TableHead>Vai trò</TableHead>
          <TableHead>Trạng thái</TableHead>
          <TableHead>Đăng nhập</TableHead>
          <TableHead className="text-right">Bài viết</TableHead>
          <TableHead className="text-right">Bị báo cáo</TableHead>
          <TableHead>Tham gia</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {isLoading
          ? Array.from({ length: 8 }, (_, i) => (
              <TableRow key={i}>
                <TableCell colSpan={7}>
                  <Skeleton className="h-9" />
                </TableCell>
              </TableRow>
            ))
          : users?.map((u) => (
              <TableRow
                key={u.id}
                data-state={u.id === selectedId ? "selected" : undefined}
                tabIndex={0}
                onClick={() => onSelect(u)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault();
                    onSelect(u);
                  }
                }}
                className="cursor-pointer"
                aria-label={`Mở ${u.fullName}`}
              >
                <TableCell>
                  <div className="flex items-center gap-3">
                    <InitialsAvatar name={u.fullName} verified={u.isVerifiedChef} />
                    <div className="min-w-0">
                      <p className="truncate font-semibold">{u.fullName}</p>
                      <p className="truncate text-xs text-muted-foreground">{u.email}</p>
                    </div>
                  </div>
                </TableCell>
                <TableCell>
                  <div className="flex flex-wrap gap-1">
                    <UserRoleBadges user={u} />
                  </div>
                </TableCell>
                <TableCell>
                  <UserStatusBadge status={u.status} />
                </TableCell>
                <TableCell className="text-muted-foreground">{u.authType === "Google" ? "Google" : "Email"}</TableCell>
                <TableCell className="text-right font-mono tabular">{formatNumber(u.postCount)}</TableCell>
                <TableCell className="text-right">
                  {u.reportCount > 0 ? (
                    <span className="inline-flex items-center gap-1 font-mono font-semibold text-ochre-text tabular">
                      <Flag className="size-3.5" aria-hidden />
                      {u.reportCount}
                    </span>
                  ) : (
                    <span className="font-mono text-muted-foreground tabular">0</span>
                  )}
                </TableCell>
                <TableCell className="text-muted-foreground">{dateVi.format(new Date(u.createdAt))}</TableCell>
              </TableRow>
            ))}
      </TableBody>
    </Table>
  );
}
