// src/app/(admin)/error.tsx
// A page in the admin group threw: the sidebar and header stay, only the page area is replaced.
"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { useQueryClient } from "@tanstack/react-query";

import { ErrorScreen } from "@/components/admin/error-screen";

export default function AdminError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  const router = useRouter();
  const queryClient = useQueryClient();

  React.useEffect(() => console.error(error), [error]);

  function retry() {
    // Whatever made the page throw may still be in the cache; retrying must fetch it again.
    queryClient.clear();
    React.startTransition(() => {
      router.refresh();
      reset();
    });
  }

  return <ErrorScreen onRetry={retry} />;
}
