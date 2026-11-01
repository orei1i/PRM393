// src/app/not-found.tsx
import type { Metadata } from "next";
import Link from "next/link";
import { Compass } from "lucide-react";

import { Button } from "@/components/ui/button";

export const metadata: Metadata = { title: "Không tìm thấy trang" };

export default function NotFound() {
  return (
    <main className="flex min-h-dvh flex-col items-center justify-center gap-3 px-6 text-center">
      <span className="flex size-11 items-center justify-center rounded-xl bg-secondary text-secondary-foreground">
        <Compass className="size-5" aria-hidden />
      </span>
      <h1 className="text-lg font-extrabold">Không tìm thấy trang</h1>
      <p className="max-w-sm text-sm text-muted-foreground">Đường dẫn này không tồn tại hoặc đã được chuyển đi.</p>
      <Button asChild>
        <Link href="/overview">Về trang Tổng quan</Link>
      </Button>
    </main>
  );
}
