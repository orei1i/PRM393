// src/app/layout.tsx
import type { Metadata } from "next";
import "@fontsource-variable/plus-jakarta-sans";
import "@fontsource-variable/jetbrains-mono";
import "./globals.css";

import { Providers } from "@/components/providers";

export const metadata: Metadata = {
  title: { default: "VeganLife Admin", template: "%s · VeganLife Admin" },
  description: "Kiểm duyệt nội dung và giám sát AI của VeganLife.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="vi">
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
