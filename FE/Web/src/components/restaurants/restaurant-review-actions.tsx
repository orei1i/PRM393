// src/components/restaurants/restaurant-review-actions.tsx
// Approve / reject a restaurant, in the /restaurants table and drawer. Both are optimistic and roll
// back on error (useReviewRestaurant). A decision can be changed later, so only the opposite one is
// offered once a place has been decided.
"use client";

import * as React from "react";
import { Ban, CircleCheck } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogTitle } from "@/components/ui/dialog";
import { Label, Textarea } from "@/components/ui/form-controls";
import { describeError } from "@/lib/api_error";
import { useReviewRestaurant } from "@/lib/hooks/use-restaurants";
import { cn } from "@/lib/utils";
import { MAX_RESTAURANT_REASON, type AdminRestaurant } from "@/types/restaurants";

export function RestaurantReviewActions({ restaurant, className }: { restaurant: AdminRestaurant; className?: string }) {
  const review = useReviewRestaurant();
  const [rejecting, setRejecting] = React.useState(false);
  const [reason, setReason] = React.useState("");
  const reasonId = React.useId();

  const trimmed = reason.trim();
  const reasonOk = trimmed.length > 0 && trimmed.length <= MAX_RESTAURANT_REASON;

  function approve() {
    review.mutate(
      { id: restaurant.id, decision: "Approve" },
      {
        onSuccess: () => toast.success("Đã duyệt quán", { description: `${restaurant.name} đã hiện công khai trong ứng dụng.` }),
        onError: (e) => toast.error("Chưa duyệt được quán", { description: describeError(e) }),
      },
    );
  }

  function reject(event: React.FormEvent) {
    event.preventDefault();
    if (!reasonOk || review.isPending) return;
    review.mutate(
      { id: restaurant.id, decision: "Reject", reason: trimmed },
      {
        onSuccess: () => {
          toast.success("Đã từ chối quán", { description: `${restaurant.name}: người gợi ý thấy lý do trong ứng dụng.` });
          setRejecting(false);
          setReason("");
        },
        onError: (e) => toast.error("Chưa từ chối được quán", { description: describeError(e) }),
      },
    );
  }

  return (
    <>
      <div className={cn("flex flex-wrap gap-1.5", className)}>
        {restaurant.status !== "Approved" && (
          <Button size="sm" variant="outline" disabled={review.isPending} onClick={approve} aria-label={`Duyệt quán ${restaurant.name}`}>
            <CircleCheck aria-hidden />
            {review.isPending ? "Đang lưu…" : "Duyệt"}
          </Button>
        )}
        {restaurant.status !== "Rejected" && (
          <Button
            size="sm"
            variant="ghost"
            className="text-destructive hover:text-destructive"
            disabled={review.isPending}
            onClick={() => setRejecting(true)}
            aria-label={`Từ chối quán ${restaurant.name}`}
          >
            <Ban aria-hidden />
            Từ chối
          </Button>
        )}
      </div>

      <Dialog open={rejecting} onOpenChange={(open) => !review.isPending && setRejecting(open)}>
        <DialogContent>
          <DialogTitle>Từ chối “{restaurant.name}”?</DialogTitle>
          <DialogDescription>
            Quán không hiện công khai. {restaurant.createdBy ? `${restaurant.createdBy.fullName} thấy lý do trong “Quán tôi đã gợi ý”.` : "Quán do Ban quản trị thêm."}
            {restaurant.isVeganCertified ? " Chứng nhận thuần chay của quán cũng bị bỏ." : ""}
          </DialogDescription>
          <form className="flex flex-col gap-4" onSubmit={reject}>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor={reasonId}>
                Lý do từ chối <span className="text-destructive">(bắt buộc)</span>
              </Label>
              <Textarea
                id={reasonId}
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                placeholder="VD: Không xác minh được địa chỉ: quán đã ngừng hoạt động."
                aria-invalid={trimmed.length > MAX_RESTAURANT_REASON ? true : undefined}
                aria-describedby={`${reasonId}-hint`}
                disabled={review.isPending}
              />
              <p id={`${reasonId}-hint`} className={cn("flex justify-between gap-3 text-xs", trimmed.length > MAX_RESTAURANT_REASON ? "text-destructive" : "text-muted-foreground")}>
                <span>Tối đa {MAX_RESTAURANT_REASON} ký tự</span>
                <span className="font-mono tabular">
                  {trimmed.length}/{MAX_RESTAURANT_REASON}
                </span>
              </p>
            </div>
            <DialogFooter>
              <DialogClose asChild>
                <Button type="button" variant="outline" disabled={review.isPending}>
                  Quay lại
                </Button>
              </DialogClose>
              <Button type="submit" variant="destructive" disabled={!reasonOk || review.isPending}>
                {review.isPending ? "Đang lưu…" : "Từ chối quán"}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </>
  );
}
