// src/components/users/user-drawer.tsx
"use client";

import * as React from "react";
import Link from "next/link";
import { Ban, FileText, Lock, LockOpen, MessageSquare, ShieldCheck, Trash2, UserRound } from "lucide-react";
import { toast } from "sonner";

import { InitialsAvatar } from "@/components/admin/initials-avatar";
import { Button } from "@/components/ui/button";
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogTitle } from "@/components/ui/dialog";
import { Input, Label, Textarea } from "@/components/ui/form-controls";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { describeError } from "@/lib/api_error";
import { readSession } from "@/lib/auth";
import { useDeleteUser, useSetUserRole, useSetUserStatus } from "@/lib/hooks/use-admin";
import { formatAge, formatNumber } from "@/lib/utils";
import { USER_ROLE_LABEL, USER_STATUS_LABEL, type AdminUser, type AssignableRole, type UserStatus } from "@/types/admin";

import { UserRoleBadges, UserStatusBadge } from "./status-badge";

const MIN_REASON = 10;
const dateVi = new Intl.DateTimeFormat("vi-VN", { day: "2-digit", month: "2-digit", year: "numeric" });

export function UserDrawer({ user, onOpenChange }: { user: AdminUser | null; onOpenChange: (open: boolean) => void }) {
  return (
    <Sheet open={user !== null} onOpenChange={onOpenChange}>
      <SheetContent className="gap-0 overflow-y-auto sm:max-w-lg">
        {user && <UserDetail key={user.id} user={user} onClose={() => onOpenChange(false)} />}
      </SheetContent>
    </Sheet>
  );
}

function UserDetail({ user, onClose }: { user: AdminUser; onClose: () => void }) {
  const [sessionUserId, setSessionUserId] = React.useState<string | null>(null);
  React.useEffect(() => setSessionUserId(readSession()?.userId ?? null), []);
  const isSelf = sessionUserId === user.id;

  const setRole = useSetUserRole();
  const setStatus = useSetUserStatus();
  const remove = useDeleteUser();

  const [pendingStatus, setPendingStatus] = React.useState<UserStatus | null>(null);
  const [reason, setReason] = React.useState("");
  const [confirmRole, setConfirmRole] = React.useState<AssignableRole | null>(null);
  const isChef = user.role === "Chef";
  const [confirmDelete, setConfirmDelete] = React.useState(false);
  const [deleteText, setDeleteText] = React.useState("");

  const needsReason = pendingStatus === "Locked" || pendingStatus === "Banned";
  const reasonOk = !needsReason || reason.trim().length >= MIN_REASON;

  function applyStatus() {
    if (!pendingStatus || !reasonOk) return;
    setStatus.mutate(
      { userId: user.id, status: pendingStatus, reason: reason.trim() || undefined },
      {
        onSuccess: (u) => {
          toast.success(`${u.fullName}: ${USER_STATUS_LABEL[u.status].toLowerCase()}`);
          setPendingStatus(null);
          setReason("");
        },
        onError: (e) => toast.error("Chưa cập nhật được trạng thái", { description: describeError(e) }),
      },
    );
  }

  function applyRole(role: AssignableRole) {
    setRole.mutate(
      { userId: user.id, role },
      {
        onSuccess: (u) => toast.success(`${u.fullName} giờ là ${USER_ROLE_LABEL[u.role].toLowerCase()}`),
        onError: (e) => toast.error("Chưa đổi được vai trò", { description: describeError(e) }),
        onSettled: () => setConfirmRole(null),
      },
    );
  }

  function applyDelete() {
    remove.mutate(user.id, {
      onSuccess: () => {
        toast.success(`Đã xoá tài khoản ${user.fullName}`);
        setConfirmDelete(false);
        onClose();
      },
      onError: (e) => toast.error("Chưa xoá được tài khoản", { description: describeError(e) }),
    });
  }

  const statusActions: { status: UserStatus; label: string; icon: typeof Lock; variant: "outline" | "warn" | "destructive" }[] =
    user.status === "Active"
      ? [
          { status: "Locked", label: "Tạm khoá", icon: Lock, variant: "warn" },
          { status: "Banned", label: "Cấm vĩnh viễn", icon: Ban, variant: "destructive" },
        ]
      : [{ status: "Active", label: user.status === "Inactive" ? "Kích hoạt" : "Mở khoá", icon: LockOpen, variant: "outline" }];

  return (
    <>
      <SheetHeader className="border-b">
        <div className="flex items-center gap-3">
          <InitialsAvatar name={user.fullName} verified={user.isVerifiedChef} className="size-12 text-sm" />
          <div className="min-w-0">
            <SheetTitle className="truncate">{user.fullName}</SheetTitle>
            <SheetDescription className="truncate">{user.email}</SheetDescription>
          </div>
        </div>
        <div className="mt-3 flex flex-wrap gap-1.5">
          <UserRoleBadges user={user} />
          <UserStatusBadge status={user.status} />
        </div>
      </SheetHeader>

      <div className="flex flex-col gap-6 p-5">
        <dl className="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
          <Info label="Số điện thoại" value={user.phone || "—"} />
          <Info label="Đăng nhập bằng" value={user.authType === "Google" ? "Google" : "Email & mật khẩu"} />
          <Info label="Tham gia" value={dateVi.format(new Date(user.createdAt))} />
          <Info label="Hoạt động gần nhất" value={user.lastActiveAt ? `${formatAge(user.lastActiveAt)} trước` : "Chưa đăng nhập"} />
          <Info label="Bài viết" value={formatNumber(user.postCount)} />
          <Info label="Bị báo cáo" value={formatNumber(user.reportCount)} highlight={user.reportCount > 0} />
        </dl>

        {isSelf && (
          <p className="rounded-lg bg-secondary px-3 py-2 text-sm text-secondary-foreground">
            Đây là tài khoản bạn đang đăng nhập — không thể tự đổi quyền, khoá hoặc xoá.
          </p>
        )}

        <section className="flex flex-col gap-2">
          <h3 className="text-sm font-bold">Nội dung</h3>
          <div className="flex flex-wrap gap-2">
            <Button asChild size="sm" variant="outline">
              <Link href={`/content?author=${encodeURIComponent(user.id)}`}>
                <FileText aria-hidden />
                Bài viết & video ({formatNumber(user.postCount)})
              </Link>
            </Button>
            <Button asChild size="sm" variant="outline">
              <Link href={`/comments?author=${encodeURIComponent(user.id)}`}>
                <MessageSquare aria-hidden />
                Bình luận
              </Link>
            </Button>
          </div>
        </section>

        <section className="flex flex-col gap-2">
          <h3 className="text-sm font-bold">Vai trò</h3>
          <div className="flex flex-wrap gap-2" role="radiogroup" aria-label="Vai trò" aria-describedby="role-hint">
            {(["User", "Admin"] as const).map((role) => (
              <Button
                key={role}
                role="radio"
                aria-checked={user.role === role}
                variant={user.role === role ? "secondary" : "outline"}
                size="sm"
                disabled={isSelf || isChef || setRole.isPending || user.role === role}
                onClick={() => setConfirmRole(role)}
              >
                {role === "Admin" ? <ShieldCheck aria-hidden /> : <UserRound aria-hidden />}
                {USER_ROLE_LABEL[role]}
              </Button>
            ))}
          </div>
          <p id="role-hint" className="text-xs text-muted-foreground">
            {isChef
              ? "Vai trò Chuyên gia được cấp khi duyệt hồ sơ chuyên gia."
              : "Quản trị viên đăng nhập được trang web này; thành viên chỉ dùng ứng dụng di động."}
          </p>
        </section>

        <section className="flex flex-col gap-2">
          <h3 className="text-sm font-bold">Trạng thái tài khoản</h3>
          <div className="flex flex-wrap gap-2">
            {statusActions.map((a) => (
              <Button
                key={a.status}
                size="sm"
                variant={pendingStatus === a.status ? "secondary" : a.variant}
                disabled={isSelf || setStatus.isPending}
                onClick={() => {
                  setPendingStatus(a.status);
                  if (a.status === "Active") setReason("");
                }}
              >
                <a.icon aria-hidden />
                {a.label}
              </Button>
            ))}
          </div>

          {pendingStatus && (
            <div className="flex flex-col gap-2 rounded-lg border p-3">
              <Label htmlFor="status-reason">
                Lý do {needsReason ? <span className="text-ochre-text">(bắt buộc, gửi tới người dùng)</span> : "(không bắt buộc)"}
              </Label>
              <Textarea
                id="status-reason"
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                placeholder={needsReason ? "VD: Đăng quảng cáo thuốc giảm cân nhiều lần dù đã nhắc nhở" : "Ghi chú nội bộ"}
                aria-invalid={!reasonOk && reason.length > 0 ? true : undefined}
              />
              {needsReason && (
                <p className="text-xs text-muted-foreground">
                  {reason.trim().length}/{MIN_REASON} ký tự tối thiểu
                </p>
              )}
              <div className="flex justify-end gap-2">
                <Button variant="ghost" size="sm" onClick={() => setPendingStatus(null)}>
                  Huỷ
                </Button>
                <Button
                  size="sm"
                  variant={pendingStatus === "Banned" ? "destructive" : pendingStatus === "Locked" ? "warn" : "default"}
                  disabled={!reasonOk || setStatus.isPending}
                  onClick={applyStatus}
                >
                  {setStatus.isPending ? "Đang lưu…" : `Xác nhận: ${USER_STATUS_LABEL[pendingStatus].toLowerCase()}`}
                </Button>
              </div>
            </div>
          )}
        </section>

        <section className="flex flex-col gap-2 rounded-lg border border-destructive/30 p-3">
          <h3 className="text-sm font-bold text-destructive">Vùng nguy hiểm</h3>
          <p className="text-xs text-muted-foreground">
            Xoá tài khoản sẽ gỡ hồ sơ khỏi ứng dụng. Bài viết vẫn được giữ ở dạng ẩn danh để không vỡ luồng bình luận.
          </p>
          <Button variant="destructive" size="sm" className="w-fit" disabled={isSelf} onClick={() => setConfirmDelete(true)}>
            <Trash2 aria-hidden />
            Xoá tài khoản
          </Button>
        </section>
      </div>

      <Dialog open={confirmRole !== null} onOpenChange={(open) => !open && setConfirmRole(null)}>
        <DialogContent>
          <DialogTitle>{confirmRole === "Admin" ? "Cấp quyền quản trị?" : "Gỡ quyền quản trị?"}</DialogTitle>
          <DialogDescription>
            {confirmRole === "Admin"
              ? `${user.fullName} sẽ đăng nhập được trang quản trị và xem toàn bộ dữ liệu người dùng.`
              : `${user.fullName} sẽ chỉ còn là thành viên trên ứng dụng di động.`}
          </DialogDescription>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Huỷ</Button>
            </DialogClose>
            <Button disabled={setRole.isPending} onClick={() => confirmRole && applyRole(confirmRole)}>
              {setRole.isPending ? "Đang lưu…" : "Xác nhận"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog
        open={confirmDelete}
        onOpenChange={(open) => {
          setConfirmDelete(open);
          if (!open) setDeleteText("");
        }}
      >
        <DialogContent>
          <DialogTitle>Xoá tài khoản {user.fullName}?</DialogTitle>
          <DialogDescription>Không hoàn tác được. Gõ email của tài khoản để xác nhận.</DialogDescription>
          <Input value={deleteText} onChange={(e) => setDeleteText(e.target.value)} placeholder={user.email} aria-label="Email xác nhận" />
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Huỷ</Button>
            </DialogClose>
            <Button
              variant="destructive"
              disabled={deleteText.trim().toLowerCase() !== user.email.toLowerCase() || remove.isPending}
              onClick={applyDelete}
            >
              {remove.isPending ? "Đang xoá…" : "Xoá vĩnh viễn"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

function Info({ label, value, highlight }: { label: string; value: string; highlight?: boolean }) {
  return (
    <div>
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className={highlight ? "font-semibold text-ochre-text" : "font-semibold"}>{value}</dd>
    </div>
  );
}
