// src/app/(admin)/catalog/page.tsx
"use client";

import * as React from "react";
import { Tags } from "lucide-react";

import { AddCatalogForm } from "@/components/catalog/add-catalog-form";
import { CatalogTable } from "@/components/catalog/catalog-table";
import { PageHeader } from "@/components/admin/page-header";
import { EmptyState, ErrorState } from "@/components/admin/states";
import { Card } from "@/components/ui/card";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { isMock } from "@/lib/backend_modules";
import { useCatalog } from "@/lib/hooks/use-admin";
import { CATALOG_KIND_LABEL, type CatalogKind } from "@/types/admin";

const KINDS = Object.keys(CATALOG_KIND_LABEL) as CatalogKind[];

const HINT: Record<CatalogKind, string> = {
  category: "Nhóm món dùng cho bộ lọc công thức trên bảng tin.",
  diet_tag: "Thẻ người dùng gắn khi đăng bài; AI cũng dùng khi lên thực đơn.",
  allergen: "Dùng cho hồ sơ sức khoẻ, cảnh báo dị ứng trong thực đơn và màn quét tủ lạnh.",
  specialty: "Chuyên môn hiển thị trong tab Chuyên gia và form đăng ký chuyên gia.",
};

/** On the server only "category" reaches the app (the idle search page); the rest are its own lists. */
const REAL_DESCRIPTION = "Danh mục trên máy chủ. Số đang dùng đếm từ dữ liệu thật. Hiện chỉ Nhóm món ảnh hưởng tới app (trang tìm kiếm); dị ứng, thẻ và chuyên môn của app chưa đọc từ đây.";

export default function CatalogPage() {
  const [kind, setKind] = React.useState<CatalogKind>("category");
  const catalog = useCatalog(kind);

  return (
    <div className="flex flex-col gap-6">
      <PageHeader
        title="Danh mục"
        description={isMock("catalog") ? "Dữ liệu dùng chung cho ứng dụng di động. Tắt một mục để ẩn khỏi app mà không mất dữ liệu cũ." : REAL_DESCRIPTION}
      />

      <Tabs value={kind} onValueChange={(v) => setKind(v as CatalogKind)} className="max-w-full">
        <TabsList className="max-w-full justify-start overflow-x-auto">
          {KINDS.map((k) => (
            <TabsTrigger key={k} value={k}>
              {CATALOG_KIND_LABEL[k]}
            </TabsTrigger>
          ))}
        </TabsList>
      </Tabs>

      <Card className="gap-0 py-0">
        {isMock("catalog") && <p className="border-b px-4 py-3 text-sm text-muted-foreground">{HINT[kind]}</p>}
        <AddCatalogForm key={kind} kind={kind} />
        {catalog.isError && !catalog.data ? (
          <ErrorState error={catalog.error} onRetry={() => catalog.refetch()} />
        ) : catalog.data?.length === 0 ? (
          <EmptyState icon={Tags} title="Chưa có mục nào" description="Thêm mục đầu tiên bằng form phía trên." />
        ) : (
          <CatalogTable kind={kind} items={catalog.data} isLoading={catalog.isLoading} />
        )}
      </Card>
    </div>
  );
}
