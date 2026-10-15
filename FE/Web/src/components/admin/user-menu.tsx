// src/components/admin/user-menu.tsx
"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { useQueryClient } from "@tanstack/react-query";
import { ChevronDown, LogOut } from "lucide-react";

import { clearSession, readSession } from "@/lib/auth";
import type { AdminSession } from "@/types/admin";

import { InitialsAvatar } from "./initials-avatar";

export function UserMenu() {
  const router = useRouter();
  const queryClient = useQueryClient();
  const [session, setSession] = React.useState<AdminSession | null>(null);
  const [open, setOpen] = React.useState(false);
  const ref = React.useRef<HTMLDivElement>(null);

  // Read after mount: the cookie is not available during server rendering.
  React.useEffect(() => setSession(readSession()), []);

  React.useEffect(() => {
    if (!open) return;
    const onPointer = (e: PointerEvent) => {
      if (!ref.current?.contains(e.target as Node)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    document.addEventListener("pointerdown", onPointer);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("pointerdown", onPointer);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  function signOut() {
    clearSession();
    queryClient.clear();
    router.replace("/login");
    router.refresh();
  }

  const name = session?.fullName ?? "Quản trị viên";

  return (
    <div ref={ref} className="relative">
      <button
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((v) => !v)}
        className="flex items-center gap-2 rounded-lg px-1.5 py-1 text-sm font-semibold outline-none hover:bg-accent focus-visible:ring-[3px] focus-visible:ring-ring/40"
      >
        <InitialsAvatar name={name} className="size-8" />
        <span className="hidden max-w-40 truncate sm:inline">{name}</span>
        <ChevronDown className="size-4 text-muted-foreground" aria-hidden />
      </button>
      {open && (
        <div role="menu" className="absolute right-0 top-full z-40 mt-2 w-64 rounded-xl border bg-popover p-1.5 shadow-lg">
          <div className="px-2.5 py-2">
            <p className="truncate text-sm font-bold">{name}</p>
            <p className="truncate text-xs text-muted-foreground">{session?.email}</p>
            <p className="mt-1 text-xs font-semibold text-sprout-text">Vai trò: Admin</p>
          </div>
          <div className="my-1 h-px bg-border" />
          <button
            type="button"
            role="menuitem"
            onClick={signOut}
            className="flex w-full items-center gap-2 rounded-lg px-2.5 py-2 text-sm font-semibold text-destructive hover:bg-accent"
          >
            <LogOut className="size-4" aria-hidden />
            Đăng xuất
          </button>
        </div>
      )}
    </div>
  );
}
