// src/app/error.tsx
// Errors outside the admin pages' own boundary: /login, and the admin layout (sidebar, header).
"use client";

import * as React from "react";

import { ErrorScreen } from "@/components/admin/error-screen";

export default function RootError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  React.useEffect(() => console.error(error), [error]);
  return (
    <main className="flex min-h-dvh items-center justify-center">
      <ErrorScreen onRetry={reset} />
    </main>
  );
}
