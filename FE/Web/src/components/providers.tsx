// src/components/providers.tsx
"use client";

import * as React from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";

import { Toaster } from "@/components/ui/sonner";
import { ApiError } from "@/lib/api_error";

/** One more try for a dropped connection or a 5xx. A 4xx will not change, and a timeout has already waited long enough. */
const retryOnce = (failures: number, error: unknown) =>
  failures < 1 && error instanceof ApiError && (error.code === "network" || (error.status !== undefined && error.status >= 500));

export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = React.useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: { staleTime: 10_000, retry: retryOnce, refetchOnWindowFocus: false },
          mutations: { retry: 0 },
        },
      }),
  );

  return (
    <QueryClientProvider client={queryClient}>
      {children}
      <Toaster />
    </QueryClientProvider>
  );
}
