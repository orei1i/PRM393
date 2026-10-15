// src/components/users/status-badge.tsx
import { Ban, CircleCheck, CircleDashed, Lock } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { USER_STATUS_LABEL, type UserStatus } from "@/types/admin";

/** Status always ships icon + label, never colour alone. */
export function UserStatusBadge({ status }: { status: UserStatus }) {
  switch (status) {
    case "Active":
      return (
        <Badge variant="sprout">
          <CircleCheck aria-hidden />
          {USER_STATUS_LABEL[status]}
        </Badge>
      );
    case "Inactive":
      return (
        <Badge variant="secondary">
          <CircleDashed aria-hidden />
          {USER_STATUS_LABEL[status]}
        </Badge>
      );
    case "Locked":
      return (
        <Badge variant="ochre">
          <Lock aria-hidden />
          {USER_STATUS_LABEL[status]}
        </Badge>
      );
    case "Banned":
      return (
        <Badge variant="destructive">
          <Ban aria-hidden />
          {USER_STATUS_LABEL[status]}
        </Badge>
      );
  }
}
