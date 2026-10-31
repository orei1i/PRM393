// src/app/login/page.tsx
"use client";

import * as React from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { Leaf, LoaderCircle, ShieldCheck, Smartphone } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input, Label } from "@/components/ui/form-controls";
import { authApi } from "@/lib/admin_api";
import { describeError } from "@/lib/api_error";
import { safeNextPath, writeSession } from "@/lib/auth";
import { isMock } from "@/lib/backend_modules";

export default function LoginPage() {
  return (
    <React.Suspense fallback={null}>
      <LoginScreen />
    </React.Suspense>
  );
}

function LoginScreen() {
  const router = useRouter();
  const params = useSearchParams();
  const [email, setEmail] = React.useState("");
  const [password, setPassword] = React.useState("");
  const [error, setError] = React.useState<string | null>(null);
  const [pending, setPending] = React.useState(false);

  async function onSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!email.trim() || !password) {
      setError("Nhập email và mật khẩu.");
      return;
    }
    setPending(true);
    setError(null);
    try {
      const session = await authApi.login(email, password);
      writeSession(session);
      router.replace(safeNextPath(params.get("next")));
      router.refresh();
    } catch (e) {
      setError(describeError(e));
      setPending(false);
    }
  }

  return (
    <div className="grid min-h-dvh lg:grid-cols-[1fr_minmax(420px,520px)]">
      <section className="relative hidden flex-col justify-between overflow-hidden bg-primary p-10 text-primary-foreground lg:flex">
        <div className="flex items-center gap-2.5">
          <span className="flex size-9 items-center justify-center rounded-lg bg-primary-foreground/15">
            <Leaf className="size-5" aria-hidden />
          </span>
          <span className="text-lg font-extrabold">VeganLife Admin</span>
        </div>
        <div className="max-w-md">
          <h1 className="text-4xl font-extrabold leading-tight tracking-tight">Giữ cộng đồng ăn chay an toàn và đáng tin.</h1>
          <ul className="mt-6 flex flex-col gap-3 text-[15px] text-primary-foreground/85">
            <li className="flex gap-2.5">
              <ShieldCheck className="mt-0.5 size-5 shrink-0" aria-hidden />
              Kiểm duyệt nội dung AI gắn cờ, xử lý báo cáo từ người dùng
            </li>
            <li className="flex gap-2.5">
              <ShieldCheck className="mt-0.5 size-5 shrink-0" aria-hidden />
              Quản lý người dùng, duyệt hồ sơ chuyên gia và danh mục
            </li>
            <li className="flex gap-2.5">
              <ShieldCheck className="mt-0.5 size-5 shrink-0" aria-hidden />
              Theo dõi chất lượng mô hình AI theo thời gian thực
            </li>
          </ul>
        </div>
        <p className="text-sm text-primary-foreground/70">Mọi thao tác đều được ghi vào nhật ký quản trị.</p>
        <Leaf className="pointer-events-none absolute -bottom-16 -right-16 size-80 text-primary-foreground/[0.06]" aria-hidden />
      </section>

      <section className="flex items-center justify-center px-4 py-10">
        <div className="flex w-full max-w-sm flex-col gap-6">
          <div className="flex items-center gap-2.5 lg:hidden">
            <span className="flex size-9 items-center justify-center rounded-lg bg-primary text-primary-foreground">
              <Leaf className="size-5" aria-hidden />
            </span>
            <span className="text-lg font-extrabold">VeganLife Admin</span>
          </div>
          <div>
            <h2 className="text-2xl font-extrabold tracking-tight">Đăng nhập quản trị</h2>
            <p className="mt-1 text-sm text-muted-foreground">Chỉ tài khoản có vai trò Admin mới truy cập được.</p>
          </div>

          <Card className="gap-4 px-5 py-5">
            <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
              <div className="flex flex-col gap-2">
                <Label htmlFor="email">Email</Label>
                <Input
                  id="email"
                  type="email"
                  autoComplete="username"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  aria-invalid={error ? true : undefined}
                  placeholder="ban@veganlife.vn"
                />
              </div>
              <div className="flex flex-col gap-2">
                <Label htmlFor="password">Mật khẩu</Label>
                <Input
                  id="password"
                  type="password"
                  autoComplete="current-password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  aria-invalid={error ? true : undefined}
                />
              </div>
              {error && (
                <p role="alert" className="rounded-lg border border-ochre-border bg-ochre-soft px-3 py-2 text-sm text-ochre-text">
                  {error}
                </p>
              )}
              <Button type="submit" size="lg" disabled={pending}>
                {pending && <LoaderCircle className="animate-spin" aria-hidden />}
                {pending ? "Đang đăng nhập…" : "Đăng nhập"}
              </Button>
            </form>
          </Card>

          {isMock("auth") && (
            <p className="rounded-lg border border-dashed px-3 py-2 text-xs text-muted-foreground">
              Dữ liệu mô phỏng: <span className="font-mono">admin@veganlife.vn</span> /{" "}
              <span className="font-mono">admin123</span>. Thử <span className="font-mono">minhanh.nguyen@gmail.com</span> để xem
              thông báo khi tài khoản thành viên đăng nhập.
            </p>
          )}

          <div className="flex gap-3 rounded-lg bg-secondary px-4 py-3 text-sm text-secondary-foreground">
            <Smartphone className="mt-0.5 size-4 shrink-0" aria-hidden />
            <p>
              Bạn là người dùng? VeganLife dành cho thành viên chạy trên <b>ứng dụng di động</b> (iOS & Android) — trang web này
              chỉ dành cho ban quản trị.
            </p>
          </div>
        </div>
      </section>
    </div>
  );
}
