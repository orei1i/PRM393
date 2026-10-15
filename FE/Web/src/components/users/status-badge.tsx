// src/components/users/status-badge.tsx
import { Ban, BadgeCheck, CircleCheck, CircleDashed, Lock } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { USER_ROLE_LABEL, USER_STATUS_LABEL, type AdminUser, type UserStatus } from "@/types/admin";

/** Role badge; a verified chef who is not "Chef" by role (e.g. an admin) gets an extra chip. */
export function UserRoleBadges({ user }: { user: Pick<AdminUser, "role" | "isVerifiedChef"> }) {
  return (
    <>
      {user.role === "Chef" ? (
        <Badge variant="sprout">
          <BadgeCheck aria-hidden />
          {USER_ROLE_LABEL.Chef}
        </Badge>
      ) : (
        <Badge variant={user.role === "Admin" ? "default" : "secondary"}>{USER_ROLE_LABEL[user.role]}</Badge>
      )}
      {user.isVerifiedChef && user.role !== "Chef" && (
        <Badge variant="sprout">
          <BadgeCheck aria-hidden />
          Chuyên gia đã xác minh
        </Badge>
      )}
    </>
  );
}

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
