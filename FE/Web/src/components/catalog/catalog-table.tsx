// src/components/catalog/catalog-table.tsx
"use client";

import * as React from "react";
import { Check, Pencil, Trash2, X } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Input, Skeleton } from "@/components/ui/form-controls";
import { Switch } from "@/components/ui/switch";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { describeError } from "@/lib/api_error";
import { useCatalogMutations } from "@/lib/hooks/use-admin";
import { formatNumber } from "@/lib/utils";
import type { CatalogItem, CatalogKind } from "@/types/admin";

export function CatalogTable({ kind, items, isLoading }: { kind: CatalogKind; items: CatalogItem[] | undefined; isLoading: boolean }) {
  const { update, remove } = useCatalogMutations(kind);
  const [editing, setEditing] = React.useState<string | null>(null);
  const [draft, setDraft] = React.useState("");

  function save(item: CatalogItem) {
    const label = draft.trim();
    if (!label || label === item.label) {
      setEditing(null);
      return;
    }
    update.mutate(
      { id: item.id, patch: { label } },
      {
        onSuccess: () => toast.success("Đã đổi tên"),
        onError: (e) => toast.error("Chưa lưu được", { description: describeError(e) }),
        onSettled: () => setEditing(null),
      },
    );
  }

  return (
    <Table className="min-w-[640px]">
      <TableHeader>
        <TableRow className="hover:bg-transparent">
          <TableHead>Tên hiển thị</TableHead>
          <TableHead>Mã</TableHead>
          {kind === "allergen" && <TableHead>Nhãn AI quét</TableHead>}
          <TableHead className="text-right">Đang dùng</TableHead>
          <TableHead>Bật</TableHead>
          <TableHead className="w-24 text-right">
            <span className="sr-only">Thao tác</span>
          </TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {isLoading
          ? Array.from({ length: 5 }, (_, i) => (
              <TableRow key={i}>
                <TableCell colSpan={kind === "allergen" ? 6 : 5}>
                  <Skeleton className="h-8" />
                </TableCell>
              </TableRow>
            ))
          : items?.map((item) => (
              <TableRow key={item.id} className={item.active ? undefined : "text-muted-foreground"}>
                <TableCell>
                  {editing === item.id ? (
                    <form
                      className="flex items-center gap-1"
                      onSubmit={(e) => {
                        e.preventDefault();
                        save(item);
                      }}
                    >
                      <Input autoFocus value={draft} onChange={(e) => setDraft(e.target.value)} className="h-8" aria-label="Tên mới" />
                      <Button type="submit" size="icon" variant="ghost" aria-label="Lưu">
                        <Check aria-hidden />
                      </Button>
                      <Button type="button" size="icon" variant="ghost" aria-label="Huỷ" onClick={() => setEditing(null)}>
                        <X aria-hidden />
                      </Button>
                    </form>
                  ) : (
                    <span className="font-semibold">{item.label}</span>
                  )}
                </TableCell>
                <TableCell className="font-mono text-xs">{item.code}</TableCell>
                {kind === "allergen" && <TableCell className="font-mono text-xs text-ai-text">{item.cvLabel ?? "—"}</TableCell>}
                <TableCell className="text-right font-mono tabular">{formatNumber(item.usageCount)}</TableCell>
                <TableCell>
                  <Switch
                    checked={item.active}
                    aria-label={item.active ? `Tắt ${item.label}` : `Bật ${item.label}`}
                    onCheckedChange={(active) =>
                      update.mutate(
                        { id: item.id, patch: { active } },
                        { onError: (e) => toast.error("Chưa lưu được", { description: describeError(e) }) },
                      )
                    }
                  />
                </TableCell>
                <TableCell className="text-right">
                  <div className="flex justify-end gap-1">
                    <Button
                      size="icon"
                      variant="ghost"
                      aria-label={`Đổi tên ${item.label}`}
                      onClick={() => {
                        setEditing(item.id);
                        setDraft(item.label);
                      }}
                    >
                      <Pencil aria-hidden />
                    </Button>
                    <Button
                      size="icon"
                      variant="ghost"
                      disabled={item.usageCount > 0 || remove.isPending}
                      title={item.usageCount > 0 ? `Đang dùng ở ${formatNumber(item.usageCount)} mục — hãy tắt thay vì xoá` : undefined}
                      aria-label={`Xoá ${item.label}`}
                      onClick={() =>
                        remove.mutate(item.id, {
                          onSuccess: () => toast.success(`Đã xoá “${item.label}”`),
                          onError: (e) => toast.error("Chưa xoá được", { description: describeError(e) }),
                        })
                      }
                    >
                      <Trash2 aria-hidden />
                    </Button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
      </TableBody>
    </Table>
  );
}
