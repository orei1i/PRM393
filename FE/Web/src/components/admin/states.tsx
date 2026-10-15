// src/components/admin/states.tsx
import { Inbox, type LucideIcon } from "lucide-react";

import { Button } from "@/components/ui/button";
import { describeError } from "@/lib/api_error";

export function EmptyState({
  icon: Icon = Inbox,
  title,
  description,
  action,
}: {
  icon?: LucideIcon;
  title: string;
  description?: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="flex flex-col items-center gap-2 px-6 py-14 text-center">
      <span className="mb-1 flex size-11 items-center justify-center rounded-xl bg-secondary text-secondary-foreground">
        <Icon className="size-5" aria-hidden />
      </span>
      <p className="font-bold">{title}</p>
      {description && <p className="max-w-sm text-sm text-muted-foreground">{description}</p>}
      {action}
    </div>
  );
}

export function ErrorState({ error, onRetry, title = "Chưa tải được dữ liệu" }: { error: unknown; onRetry?: () => void; title?: string }) {
  return (
    <div role="alert" className="flex flex-col items-center gap-3 px-6 py-14 text-center">
      <p className="font-bold">{title}</p>
      <p className="text-sm text-muted-foreground">{describeError(error)}</p>
      {onRetry && (
        <Button variant="outline" onClick={onRetry}>
          Thử lại
        </Button>
      )}
    </div>
  );
}
