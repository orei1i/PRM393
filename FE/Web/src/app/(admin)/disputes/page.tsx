// src/app/(admin)/disputes/page.tsx
"use client";

import * as React from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useIsFetching, useQueryClient } from "@tanstack/react-query";
import { Info, Lock, RefreshCw, Scale, Search } from "lucide-react";

import { PageHeader } from "@/components/admin/page-header";
import { EmptyState, ErrorState } from "@/components/admin/states";
import { EscrowKpis } from "@/components/disputes/escrow-kpis";
import { ComplaintDrawer } from "@/components/disputes/complaint-drawer";
import { ComplaintTable } from "@/components/disputes/complaint-table";
import { EscrowHoldTable } from "@/components/disputes/escrow-hold-table";
import { ResolveHoldDialog } from "@/components/disputes/resolve-hold-dialog";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input, NativeSelect } from "@/components/ui/form-controls";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { bookingKeys, useComplaints, useEscrowHolds, useEscrowSummary } from "@/lib/hooks/use-bookings";
import { formatNumber, formatPercent } from "@/lib/utils";
import { AUTO_COMPLETE_DAYS, ESCROW_STATUS_LABEL, ESCROW_STATUSES, type AdminComplaint, type AdminEscrowHold, type EscrowHoldFilter } from "@/types/bookings";
import { ESCROW_HOLD_DAYS, PLATFORM_FEE_RATE } from "@/types/payouts";

type PageTab = "open" | "resolved" | "holds";
const isTab = (v: string | null): v is PageTab => v === "open" || v === "resolved" || v === "holds";

const HOLD_FILTERS: { value: EscrowHoldFilter; label: string }[] = [
  { value: "active", label: "Đang giữ & tạm giữ" },
  { value: "stuck", label: "Kẹt, cần Ban quản trị xử lý" },
  ...ESCROW_STATUSES.map((s) => ({ value: s, label: ESCROW_STATUS_LABEL[s] })),
  { value: "all", label: "Tất cả" },
];

export default function DisputesPage() {
  return (
    <React.Suspense fallback={null}>
      <DisputesScreen />
    </React.Suspense>
  );
}

function DisputesScreen() {
  const params = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();
  const qc = useQueryClient();
  const fetching = useIsFetching({ queryKey: bookingKeys.all }) > 0;

  const tabParam = params.get("tab");
  const bookingParam = params.get("booking");
  const openParam = params.get("open");

  const [tab, setTab] = React.useState<PageTab>(() => (isTab(tabParam) ? tabParam : bookingParam ? "holds" : "open"));
  const [searchInput, setSearchInput] = React.useState<Record<PageTab, string>>({ open: "", resolved: "", holds: bookingParam ?? "" });
  const search = React.useDeferredValue(searchInput);
  const [holdFilter, setHoldFilter] = React.useState<EscrowHoldFilter>(bookingParam ? "all" : "active");
  const [selected, setSelected] = React.useState<{ id: string; initial: AdminComplaint | null } | null>(null);
  const [resolving, setResolving] = React.useState<AdminEscrowHold | null>(null);
  /** Booking id from `?booking=` waiting for the holds list, to open its complaint. */
  const [pendingBooking, setPendingBooking] = React.useState<string | null>(bookingParam);

  // Deep links (/orders drawer, overview, sidebar) also apply while the page is open.
  React.useEffect(() => {
    if (!tabParam && !bookingParam && !openParam) return;
    if (isTab(tabParam)) setTab(tabParam);
    if (bookingParam) {
      setTab("holds");
      setHoldFilter("all");
      setSearchInput((s) => ({ ...s, holds: bookingParam }));
      setPendingBooking(bookingParam);
    }
    if (openParam) setSelected({ id: openParam, initial: null });
    router.replace(pathname, { scroll: false });
  }, [tabParam, bookingParam, openParam, pathname, router]);

  const summary = useEscrowSummary();
  const openQuery = React.useMemo(() => ({ status: "Open" as const, search: search.open }), [search.open]);
  const resolvedQuery = React.useMemo(() => ({ status: "Resolved" as const, search: search.resolved }), [search.resolved]);
  const holdQuery = React.useMemo(() => ({ status: holdFilter, search: search.holds }), [holdFilter, search.holds]);
  const open = useComplaints(openQuery);
  const resolved = useComplaints(resolvedQuery);
  const holds = useEscrowHolds(holdQuery, tab === "holds");

  React.useEffect(() => {
    if (!pendingBooking || !holds.data || holds.isPlaceholderData) return;
    const match = holds.data.find((h) => h.booking.id === pendingBooking);
    if (match?.booking.complaintId) setSelected({ id: match.booking.complaintId, initial: null });
    setPendingBooking(null);
  }, [pendingBooking, holds.data, holds.isPlaceholderData]);

  const setSearch = (value: string) => setSearchInput((s) => ({ ...s, [tab]: value }));
  const openCount = summary.data?.openComplaints;

  return (
    <div className="flex flex-col gap-6">
      <PageHeader
        title="Khiếu nại & giữ tiền"
        description={`Tiền đặt chuyên gia nằm ở VeganLife đến hết ${ESCROW_HOLD_DAYS} ngày giữ. Xem xét khiếu nại và quyết định chuyển vào ví chuyên gia hoặc ví thành viên.`}
        actions={
          <Button variant="outline" onClick={() => qc.invalidateQueries({ queryKey: bookingKeys.all })} disabled={fetching}>
            <RefreshCw className={fetching ? "animate-spin" : undefined} aria-hidden />
            Làm mới
          </Button>
        }
      />

      <EscrowKpis
        summary={summary}
        onShowStuck={() => {
          setTab("holds");
          setHoldFilter("stuck");
          setSearchInput((s) => ({ ...s, holds: "" }));
        }}
      />

      <p className="flex gap-2.5 rounded-lg border bg-card px-4 py-3 text-sm text-muted-foreground">
        <Info className="mt-0.5 size-4 shrink-0" aria-hidden />
        <span>
          Thành viên thanh toán qua PaymentOS hoặc bằng ví, tiền vào VeganLife. Chuyên gia chỉ xác nhận hoàn thành được khi đã giao đủ mọi ngày và đã tới ngày
          kết thúc kế hoạch; không xác nhận thì hệ thống tự hoàn tất {AUTO_COMPLETE_DAYS} ngày sau ngày kết thúc nếu đã giao đủ và không có khiếu nại. Từ lúc
          hoàn thành, tiền được giữ thêm <b className="text-foreground">{ESCROW_HOLD_DAYS} ngày</b>. Không có khiếu nại thì tiền tự vào ví chuyên gia (trừ phí{" "}
          {formatPercent(PLATFORM_FEE_RATE)}). Có khiếu nại (kèm bằng chứng) thì tiền bị tạm giữ đến khi Ban quản trị quyết định; tiền hoàn vào ví của thành viên.
          Quá hạn tự hoàn tất mà còn thiếu ngày hoặc giao đủ muộn thì khoản đó bị kẹt: Ban quản trị xử lý ở tab Tiền đang giữ.
        </span>
      </p>

      <Tabs value={tab} onValueChange={(v) => setTab(v as PageTab)} className="gap-4">
        <TabsList className="max-w-full justify-start overflow-x-auto" aria-label="Khiếu nại và tiền đang giữ">
          <TabsTrigger value="open">
            Chờ xử lý
            <span className="rounded-full bg-ochre-soft px-1.5 font-mono text-[11px] text-ochre-text tabular">
              {openCount === undefined ? "–" : formatNumber(openCount)}
              <span className="sr-only"> khiếu nại</span>
            </span>
          </TabsTrigger>
          <TabsTrigger value="resolved">Đã xử lý</TabsTrigger>
          <TabsTrigger value="holds">Tiền đang giữ</TabsTrigger>
        </TabsList>

        <TabsContent value="open" className="min-w-0">
          <ComplaintPanel
            query={open}
            mode="open"
            search={searchInput.open}
            onSearch={setSearch}
            selectedId={selected?.id ?? null}
            onSelect={(c) => setSelected({ id: c.id, initial: c })}
          />
        </TabsContent>
        <TabsContent value="resolved" className="min-w-0">
          <ComplaintPanel
            query={resolved}
            mode="resolved"
            search={searchInput.resolved}
            onSearch={setSearch}
            selectedId={selected?.id ?? null}
            onSelect={(c) => setSelected({ id: c.id, initial: c })}
          />
        </TabsContent>
        <TabsContent value="holds" className="min-w-0">
          <Card className="gap-0 py-0">
            <div className="flex flex-wrap items-center gap-3 border-b p-4">
              <SearchBox value={searchInput.holds} onChange={setSearch} placeholder="Mã đặt, mã đơn, thành viên, chuyên gia…" label="Tìm khoản tiền đang giữ" />
              <NativeSelect
                aria-label="Lọc theo trạng thái giữ tiền"
                value={holdFilter}
                onChange={(e) => setHoldFilter(e.target.value as EscrowHoldFilter)}
                className="w-full sm:w-56"
              >
                {HOLD_FILTERS.map((f) => (
                  <option key={f.value} value={f.value}>
                    {f.label}
                  </option>
                ))}
              </NativeSelect>
              <p className="w-full text-sm text-muted-foreground" aria-live="polite">
                {holds.data ? `${formatNumber(holds.data.length)} khoản` : holds.isError ? "" : "Đang tải…"}
              </p>
            </div>
            {holds.isError && !holds.data ? (
              <ErrorState error={holds.error} onRetry={() => holds.refetch()} title="Chưa tải được tiền đang giữ" />
            ) : holds.data?.length === 0 ? (
              <EmptyState
                icon={Lock}
                title={searchInput.holds.trim() ? "Không có khoản nào khớp từ khoá" : "Không có khoản tiền nào ở trạng thái này"}
                description="Mỗi lần thành viên thanh toán đặt chuyên gia, một khoản giữ tiền được tạo."
                action={
                  searchInput.holds.trim() || holdFilter !== "active" ? (
                    <Button
                      variant="outline"
                      onClick={() => {
                        setSearchInput((s) => ({ ...s, holds: "" }));
                        setHoldFilter("active");
                      }}
                    >
                      Xoá bộ lọc
                    </Button>
                  ) : undefined
                }
              />
            ) : (
              <div className={holds.isFetching && !holds.isLoading ? "opacity-60 transition-opacity" : undefined}>
                <EscrowHoldTable holds={holds.data} isLoading={holds.isLoading} onOpenComplaint={(id) => setSelected({ id, initial: null })} onResolve={setResolving} />
              </div>
            )}
          </Card>
        </TabsContent>
      </Tabs>

      <ComplaintDrawer complaintId={selected?.id ?? null} initial={selected?.initial ?? null} onOpenChange={(o) => !o && setSelected(null)} />
      <ResolveHoldDialog hold={resolving} onOpenChange={(o) => !o && setResolving(null)} />
    </div>
  );
}

function SearchBox({ value, onChange, placeholder, label }: { value: string; onChange: (v: string) => void; placeholder: string; label: string }) {
  return (
    <div className="relative w-full sm:w-80">
      <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
      <Input type="search" value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder} aria-label={label} className="pl-9" />
    </div>
  );
}

function ComplaintPanel({
  query,
  mode,
  search,
  onSearch,
  selectedId,
  onSelect,
}: {
  query: ReturnType<typeof useComplaints>;
  mode: "open" | "resolved";
  search: string;
  onSearch: (value: string) => void;
  selectedId: string | null;
  onSelect: (c: AdminComplaint) => void;
}) {
  const filtered = search.trim().length > 0;
  return (
    <Card className="gap-0 py-0">
      <div className="flex flex-wrap items-center gap-3 border-b p-4">
        <SearchBox value={search} onChange={onSearch} placeholder="Mã khiếu nại, mã đặt, thành viên, chuyên gia…" label="Tìm khiếu nại" />
        <p className="text-sm text-muted-foreground sm:ml-auto" aria-live="polite">
          {query.data ? `${formatNumber(query.data.length)} khiếu nại${mode === "open" ? " · cũ nhất trước" : " · mới quyết định trước"}` : query.isError ? "" : "Đang tải…"}
        </p>
      </div>
      {query.isError && !query.data ? (
        <ErrorState error={query.error} onRetry={() => query.refetch()} title="Chưa tải được khiếu nại" />
      ) : query.data?.length === 0 ? (
        <EmptyState
          icon={Scale}
          title={filtered ? "Không có khiếu nại khớp từ khoá" : mode === "open" ? "Không có khiếu nại chờ xử lý" : "Chưa có khiếu nại đã xử lý"}
          description={
            filtered
              ? "Thử tên thành viên, chuyên gia hoặc mã đặt khác."
              : mode === "open"
                ? "Khiếu nại thành viên gửi từ ứng dụng sẽ xuất hiện ở đây; tiền của đơn đó được tạm giữ đến khi bạn quyết định."
                : "Khiếu nại đã quyết định sẽ nằm ở đây cùng ghi chú và số tiền hoàn."
          }
          action={
            filtered ? (
              <Button variant="outline" onClick={() => onSearch("")}>
                Xoá từ khoá
              </Button>
            ) : undefined
          }
        />
      ) : (
        <div className={query.isFetching && !query.isLoading ? "opacity-60 transition-opacity" : undefined}>
          <ComplaintTable complaints={query.data} isLoading={query.isLoading} mode={mode} selectedId={selectedId} onSelect={onSelect} />
        </div>
      )}
    </Card>
  );
}
