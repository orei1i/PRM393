// src/components/disputes/complaint-table.tsx
"use client";

import { InitialsAvatar } from "@/components/admin/initials-avatar";
import { formatVnd } from "@/components/orders/order-badges";
import { Skeleton } from "@/components/ui/form-controls";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { planSummary, type AdminComplaint } from "@/types/bookings";

import { ComplaintReasonBadge, DecisionBadge, EscrowStatusBadge, formatVnDate, formatVnDateTime, timeLeft } from "./booking-badges";

const priceOf = (c: AdminComplaint) => c.booking.contract?.price ?? c.booking.escrow?.amount ?? 0;

function Person({ name, verified }: { name: string; verified?: boolean }) {
  return (
    <div className="flex items-center gap-2">
      <InitialsAvatar name={name} verified={verified} className="size-7 text-[10px]" />
      <span className="max-w-36 truncate">{name}</span>
    </div>
  );
}

export function ComplaintTable({
  complaints,
  isLoading,
  mode,
  selectedId,
  onSelect,
}: {
  complaints: AdminComplaint[] | undefined;
  isLoading: boolean;
  mode: "open" | "resolved";
  selectedId: string | null;
  onSelect: (complaint: AdminComplaint) => void;
}) {
  return (
    <Table className="min-w-[1040px]">
      <TableHeader>
        <TableRow className="hover:bg-transparent">
          <TableHead>Đặt chuyên gia</TableHead>
          <TableHead>Thành viên</TableHead>
          <TableHead>Chuyên gia</TableHead>
          <TableHead className="text-right">Giá</TableHead>
          <TableHead>Lý do</TableHead>
          <TableHead>Ngày gửi</TableHead>
          <TableHead>{mode === "open" ? "Hạn giữ tiền" : "Quyết định"}</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {isLoading
          ? Array.from({ length: 4 }, (_, i) => (
              <TableRow key={i}>
                <TableCell colSpan={7}>
                  <Skeleton className="h-10" />
                </TableCell>
              </TableRow>
            ))
          : complaints?.map((c) => {
              const escrow = c.booking.escrow;
              return (
                <TableRow
                  key={c.id}
                  data-state={c.id === selectedId ? "selected" : undefined}
                  tabIndex={0}
                  onClick={() => onSelect(c)}
                  onKeyDown={(e) => {
                    if (e.target === e.currentTarget && (e.key === "Enter" || e.key === " ")) {
                      e.preventDefault();
                      onSelect(c);
                    }
                  }}
                  className="cursor-pointer"
                  aria-label={`Mở khiếu nại ${c.id} của ${c.booking.member.fullName} với ${c.booking.chef.fullName}`}
                >
                  <TableCell>
                    <span className="block font-mono text-xs font-semibold">{c.booking.id}</span>
                    <span className="block text-xs text-muted-foreground">{planSummary(c.booking)}</span>
                  </TableCell>
                  <TableCell>
                    <Person name={c.booking.member.fullName} />
                  </TableCell>
                  <TableCell>
                    <Person name={c.booking.chef.fullName} verified />
                  </TableCell>
                  <TableCell className="text-right font-mono font-semibold tabular">{formatVnd(priceOf(c))}</TableCell>
                  <TableCell>
                    <ComplaintReasonBadge reason={c.reason} />
                  </TableCell>
                  <TableCell className="whitespace-nowrap text-muted-foreground">{formatVnDateTime(c.createdAt)}</TableCell>
                  <TableCell>
                    {mode === "open" ? (
                      escrow ? (
                        <div className="flex flex-col items-start gap-1">
                          <EscrowStatusBadge status={escrow.status} />
                          <span className="whitespace-nowrap text-xs text-muted-foreground">
                            Hạn gốc {formatVnDate(escrow.releaseAt)} · {timeLeft(escrow.releaseAt)}
                          </span>
                        </div>
                      ) : (
                        <span className="text-muted-foreground">—</span>
                      )
                    ) : c.decision ? (
                      <div className="flex flex-col items-start gap-1">
                        <DecisionBadge decision={c.decision} />
                        <span className="whitespace-nowrap text-xs text-muted-foreground">
                          {c.refundAmount ? `Hoàn ${formatVnd(c.refundAmount)} · ` : ""}
                          {c.decidedBy ?? "Quản trị viên"}
                          {c.decidedAt ? ` · ${formatVnDate(c.decidedAt)}` : ""}
                        </span>
                      </div>
                    ) : (
                      <span className="text-muted-foreground">—</span>
                    )}
                  </TableCell>
                </TableRow>
              );
            })}
      </TableBody>
    </Table>
  );
}
