// src/components/admin/error-screen.tsx
// What the error boundaries show instead of a white page. A boundary firing means a page threw while
// rendering (the API layer already turns bad answers into messages), so the text does not blame the user.
"use client";

import { RefreshCw, TriangleAlert } from "lucide-react";

import { Button } from "@/components/ui/button";

export function ErrorScreen({ onRetry, children }: { onRetry: () => void; children?: React.ReactNode }) {
  return (
    <div role="alert" className="flex flex-col items-center gap-3 px-6 py-20 text-center">
      <span className="flex size-11 items-center justify-center rounded-xl bg-ochre-soft text-ochre-text">
        <TriangleAlert className="size-5" aria-hidden />
      </span>
      <h1 className="text-lg font-extrabold">Trang này gặp sự cố</h1>
      <p className="max-w-sm text-sm text-muted-foreground">Dữ liệu của bạn không bị ảnh hưởng. Thử tải lại, nếu vẫn lỗi hãy quay lại sau ít phút.</p>
      <div className="flex flex-wrap justify-center gap-2">
        <Button onClick={onRetry}>
          <RefreshCw aria-hidden />
          Thử lại
        </Button>
        {children}
      </div>
    </div>
  );
}
