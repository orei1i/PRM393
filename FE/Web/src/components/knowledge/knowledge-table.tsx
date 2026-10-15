// src/components/knowledge/knowledge-table.tsx
"use client";

import { ChefHat, CircleCheck, CircleX, Globe, Hourglass } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/form-controls";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { formatNumber } from "@/lib/utils";
import { KNOWLEDGE_STATUS_LABEL, type KnowledgeDoc, type KnowledgeDocStatus } from "@/types/knowledge";

export const dateVi = new Intl.DateTimeFormat("vi-VN", { day: "2-digit", month: "2-digit", year: "numeric" });

export function KnowledgeStatusBadge({ status }: { status: KnowledgeDocStatus }) {
  switch (status) {
    case "Approved":
      return (
        <Badge variant="sprout">
          <CircleCheck aria-hidden />
          {KNOWLEDGE_STATUS_LABEL[status]}
        </Badge>
      );
    case "Pending":
      return (
        <Badge variant="ochre">
          <Hourglass aria-hidden />
          {KNOWLEDGE_STATUS_LABEL[status]}
        </Badge>
      );
    case "Rejected":
      return (
        <Badge variant="secondary">
          <CircleX aria-hidden />
          {KNOWLEDGE_STATUS_LABEL[status]}
        </Badge>
      );
  }
}

export function KnowledgeSourceBadge({ doc }: { doc: Pick<KnowledgeDoc, "source" | "chefName"> }) {
  return doc.source === "WHO" ? (
    <Badge variant="ai">
      <Globe aria-hidden />
      WHO
    </Badge>
  ) : (
    <Badge variant="outline" className="max-w-full">
      <ChefHat aria-hidden />
      <span className="truncate">Chef · {doc.chefName ?? "Chuyên gia"}</span>
    </Badge>
  );
}

export function KnowledgeTable({
  docs,
  isLoading,
  selectedId,
  onSelect,
}: {
  docs: KnowledgeDoc[] | undefined;
  isLoading: boolean;
  selectedId: string | null;
  onSelect: (doc: KnowledgeDoc) => void;
}) {
  return (
    <Table className="min-w-[860px]">
      <TableHeader>
        <TableRow className="hover:bg-transparent">
          <TableHead className="w-[40%]">Tiêu đề</TableHead>
          <TableHead>Nguồn</TableHead>
          <TableHead>Trạng thái</TableHead>
          <TableHead className="text-right">Số đoạn</TableHead>
          <TableHead className="text-right">Lượt trích dẫn</TableHead>
          <TableHead>Ngày tạo</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {isLoading
          ? Array.from({ length: 6 }, (_, i) => (
              <TableRow key={i}>
                <TableCell colSpan={6}>
                  <Skeleton className="h-9" />
                </TableCell>
              </TableRow>
            ))
          : docs?.map((doc) => (
              <TableRow
                key={doc.id}
                data-state={doc.id === selectedId ? "selected" : undefined}
                tabIndex={0}
                onClick={() => onSelect(doc)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault();
                    onSelect(doc);
                  }
                }}
                className="cursor-pointer"
                aria-label={`Mở tài liệu: ${doc.title}`}
              >
                <TableCell className="whitespace-normal">
                  <span className="line-clamp-2 font-semibold">{doc.title}</span>
                </TableCell>
                <TableCell>
                  <KnowledgeSourceBadge doc={doc} />
                </TableCell>
                <TableCell>
                  <KnowledgeStatusBadge status={doc.status} />
                </TableCell>
                <TableCell className="text-right font-mono tabular">{doc.status === "Approved" ? formatNumber(doc.chunkCount) : "–"}</TableCell>
                <TableCell className="text-right font-mono tabular">{formatNumber(doc.citationCount)}</TableCell>
                <TableCell className="text-muted-foreground">{dateVi.format(new Date(doc.createdAt))}</TableCell>
              </TableRow>
            ))}
      </TableBody>
    </Table>
  );
}
