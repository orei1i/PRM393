// src/components/catalog/add-catalog-form.tsx
"use client";

import * as React from "react";
import { Plus } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Input, Label } from "@/components/ui/form-controls";
import { describeError } from "@/lib/api_error";
import { useCatalogMutations } from "@/lib/hooks/use-admin";
import type { CatalogKind } from "@/types/admin";

/** "Không gluten" → "khong_gluten" (codes are what the mobile app stores). */
export function toCode(label: string) {
  return label
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[Đđ]/g, "d")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 40);
}

export function AddCatalogForm({ kind }: { kind: CatalogKind }) {
  const { create } = useCatalogMutations(kind);
  const [label, setLabel] = React.useState("");
  const [code, setCode] = React.useState("");
  const [codeTouched, setCodeTouched] = React.useState(false);
  const [cvLabel, setCvLabel] = React.useState("");

  const effectiveCode = codeTouched ? code : toCode(label);
  const valid = label.trim().length >= 2 && /^[a-z0-9_]{2,40}$/.test(effectiveCode);

  function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!valid) return;
    create.mutate(
      { kind, label: label.trim(), code: effectiveCode, cvLabel: kind === "allergen" ? cvLabel.trim() || undefined : undefined },
      {
        onSuccess: (item) => {
          toast.success(`Đã thêm “${item.label}”`);
          setLabel("");
          setCode("");
          setCodeTouched(false);
          setCvLabel("");
        },
        onError: (err) => toast.error("Chưa thêm được", { description: describeError(err) }),
      },
    );
  }

  return (
    <form onSubmit={submit} className="flex flex-wrap items-end gap-3 border-b p-4">
      <div className="flex w-full flex-col gap-1.5 sm:w-56">
        <Label htmlFor={`label-${kind}`}>Tên hiển thị</Label>
        <Input id={`label-${kind}`} value={label} onChange={(e) => setLabel(e.target.value)} placeholder="VD: Không gluten" />
      </div>
      <div className="flex w-full flex-col gap-1.5 sm:w-48">
        <Label htmlFor={`code-${kind}`}>Mã</Label>
        <Input
          id={`code-${kind}`}
          value={effectiveCode}
          onChange={(e) => {
            setCodeTouched(true);
            setCode(e.target.value);
          }}
          className="font-mono text-xs"
          aria-invalid={effectiveCode.length > 0 && !/^[a-z0-9_]{2,40}$/.test(effectiveCode) ? true : undefined}
        />
      </div>
      {kind === "allergen" && (
        <div className="flex w-full flex-col gap-1.5 sm:w-44">
          <Label htmlFor="cv-label">Nhãn AI quét</Label>
          <Input id="cv-label" value={cvLabel} onChange={(e) => setCvLabel(e.target.value)} placeholder="VD: peanut" className="font-mono text-xs" />
        </div>
      )}
      <Button type="submit" disabled={!valid || create.isPending}>
        <Plus aria-hidden />
        {create.isPending ? "Đang thêm…" : "Thêm"}
      </Button>
      <p className="w-full text-xs text-muted-foreground">
        Mã chỉ gồm chữ thường, số, dấu gạch dưới — ứng dụng di động lưu theo mã, nên đổi tên hiển thị không ảnh hưởng dữ liệu cũ.
      </p>
    </form>
  );
}
