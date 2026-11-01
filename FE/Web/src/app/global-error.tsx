// src/app/global-error.tsx
// The root layout itself failed, so it replaces <html> and has neither the Providers nor the design
// system's components to lean on. Retrying reloads the page rather than re-rendering the broken tree.
"use client";

import "./globals.css";

export default function GlobalError() {
  return (
    <html lang="vi">
      <body>
        <main role="alert" className="flex min-h-dvh flex-col items-center justify-center gap-3 px-6 text-center">
          <h1 className="text-lg font-extrabold">VeganLife Admin gặp sự cố</h1>
          <p className="max-w-sm text-sm text-muted-foreground">Dữ liệu của bạn không bị ảnh hưởng. Thử tải lại, nếu vẫn lỗi hãy quay lại sau ít phút.</p>
          <button type="button" onClick={() => window.location.reload()} className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground">
            Thử lại
          </button>
        </main>
      </body>
    </html>
  );
}
