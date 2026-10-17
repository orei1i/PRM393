// src/components/ads/ad-form-dialog.tsx
"use client";

import * as React from "react";
import { Megaphone, Save, TriangleAlert } from "lucide-react";
import { toast } from "sonner";

import { formatVnd } from "@/components/orders/order-badges";
import { Button } from "@/components/ui/button";
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogTitle } from "@/components/ui/dialog";
import { Checkbox, Input, Label, NativeSelect, Textarea } from "@/components/ui/form-controls";
import { describeError } from "@/lib/api_error";
import { useCreateAd, useUpdateAd } from "@/lib/hooks/use-ads";
import { useRestaurants } from "@/lib/hooks/use-restaurants";
import { cn } from "@/lib/utils";
import {
  AD_CITIES,
  AD_CTA_LABEL,
  AD_CTA_TYPES,
  AD_HEADLINE_MAX,
  AD_MESSAGE_MAX,
  AD_MIN_BUDGET,
  adInputErrors,
  type AdCampaign,
  type AdCtaType,
  type AdInput,
  type AdRestaurant,
} from "@/types/ads";

import { AdPreview } from "./ad-preview";

const ALL_RESTAURANTS = { certified: "all", source: "all", search: "" } as const;
const NATIONAL = "__national__";

const pad2 = (n: number) => String(n).padStart(2, "0");
/** ISO → "yyyy-mm-dd" in local time (value of <input type="date">). */
const toDateInput = (iso: string) => {
  const d = new Date(iso);
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
};
function fromDateInput(value: string, endOfDay: boolean) {
  const [y, m, d] = value.split("-").map(Number);
  if (!y || !m || !d) return "";
  return (endOfDay ? new Date(y, m - 1, d, 23, 59, 59, 999) : new Date(y, m - 1, d)).toISOString();
}

interface FormState {
  restaurantId: string;
  headline: string;
  message: string;
  ctaType: AdCtaType;
  city: string;
  start: string;
  end: string;
  budget: string;
}

function initialState(campaign: AdCampaign | null): FormState {
  if (campaign) {
    return {
      restaurantId: campaign.restaurantId,
      headline: campaign.headline,
      message: campaign.message,
      ctaType: campaign.ctaType,
      city: campaign.targetCity ?? NATIONAL,
      start: toDateInput(campaign.startAt),
      end: toDateInput(campaign.endAt),
      budget: String(campaign.budget),
    };
  }
  const today = new Date();
  const end = new Date(today);
  end.setDate(end.getDate() + 30);
  return {
    restaurantId: "",
    headline: "",
    message: "",
    ctaType: "ViewStore",
    city: AD_CITIES[0],
    start: toDateInput(today.toISOString()),
    end: toDateInput(end.toISOString()),
    budget: "2000000",
  };
}

/**
 * Create (campaign = null) or edit a campaign. Fields are validated with the same rules as the
 * server (adInputErrors); errors show once a field was left or after the first submit.
 */
export function AdFormDialog({
  open,
  campaign,
  onOpenChange,
}: {
  open: boolean;
  campaign: AdCampaign | null;
  onOpenChange: (open: boolean) => void;
}) {
  const create = useCreateAd();
  const update = useUpdateAd();
  const pending = create.isPending || update.isPending;

  return (
    <Dialog open={open} onOpenChange={(next) => !pending && onOpenChange(next)}>
      <DialogContent className="max-h-[calc(100dvh-2rem)] max-w-4xl overflow-y-auto">
        {open && (
          <Form
            key={campaign?.id ?? "new"}
            campaign={campaign}
            pending={pending}
            onSubmit={(input) => {
              const callbacks = {
                onSuccess: (ad: AdCampaign) => {
                  toast.success(campaign ? "Đã lưu quảng cáo" : "Đã tạo quảng cáo", { description: `${ad.restaurant.name} · ${ad.headline}` });
                  onOpenChange(false);
                },
                onError: (e: unknown) => toast.error(campaign ? "Chưa lưu được quảng cáo" : "Chưa tạo được quảng cáo", { description: describeError(e) }),
              };
              if (campaign) update.mutate({ id: campaign.id, patch: input }, callbacks);
              else create.mutate(input, callbacks);
            }}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}

function Form({ campaign, pending, onSubmit }: { campaign: AdCampaign | null; pending: boolean; onSubmit: (input: AdInput) => void }) {
  const [state, setState] = React.useState<FormState>(() => initialState(campaign));
  const [showUncertified, setShowUncertified] = React.useState(() => campaign !== null && !campaign.restaurant.isVeganCertified);
  const [touched, setTouched] = React.useState<ReadonlySet<keyof AdInput>>(new Set());
  const [attempted, setAttempted] = React.useState(false);
  const ids = React.useId();

  const restaurants = useRestaurants(ALL_RESTAURANTS);

  const options = React.useMemo(() => {
    const list: AdRestaurant[] = (restaurants.data ?? [])
      .filter((r) => showUncertified || r.isVeganCertified || r.id === state.restaurantId)
      .map((r) => ({ id: r.id, name: r.name, address: r.address, isVeganCertified: r.isVeganCertified, latitude: r.latitude, longitude: r.longitude }));
    // Keep the campaign's restaurant selectable even if it was deleted on /restaurants.
    if (campaign && !list.some((r) => r.id === campaign.restaurantId)) list.unshift(campaign.restaurant);
    return list;
  }, [restaurants.data, showUncertified, state.restaurantId, campaign]);

  const selected = options.find((r) => r.id === state.restaurantId) ?? null;

  // Unchanged dates keep the stored time; changed ones become local start / end of day.
  const input: AdInput = {
    restaurantId: state.restaurantId,
    placement: campaign?.placement ?? "nearby",
    headline: state.headline.trim(),
    message: state.message.trim(),
    ctaType: state.ctaType,
    targetCity: state.city === NATIONAL ? null : state.city,
    startAt: campaign && state.start === toDateInput(campaign.startAt) ? campaign.startAt : fromDateInput(state.start, false),
    endAt: campaign && state.end === toDateInput(campaign.endAt) ? campaign.endAt : fromDateInput(state.end, true),
    budget: state.budget.trim() === "" ? NaN : Number(state.budget),
  };
  const errors = adInputErrors(input, { isNew: campaign === null, spent: campaign?.spent });
  const valid = Object.keys(errors).length === 0;
  const errorFor = (field: keyof AdInput) => (attempted || touched.has(field) ? errors[field] : undefined);
  const touch = (field: keyof AdInput) => () => setTouched((prev) => (prev.has(field) ? prev : new Set(prev).add(field)));
  const set = <K extends keyof FormState>(key: K, value: FormState[K]) => setState((s) => ({ ...s, [key]: value }));

  function submit(e: React.FormEvent) {
    e.preventDefault();
    setAttempted(true);
    if (!valid || pending) return;
    onSubmit(input);
  }

  const fieldProps = (field: keyof AdInput) => {
    const error = errorFor(field);
    return {
      id: `${ids}-${field}`,
      "aria-invalid": error ? true : undefined,
      "aria-describedby": `${ids}-${field}-hint`,
      onBlur: touch(field),
      disabled: pending,
    };
  };

  /** Help text under a field, replaced by its error when one is visible. */
  const hint = (field: keyof AdInput, help: string) => {
    const error = errorFor(field);
    return (
      <p id={`${ids}-${field}-hint`} className={cn("text-xs", error ? "text-destructive" : "text-muted-foreground")}>
        {error ?? help}
      </p>
    );
  };

  return (
    <>
      <DialogTitle>{campaign ? "Sửa quảng cáo cửa hàng" : "Tạo quảng cáo cửa hàng"}</DialogTitle>
      <DialogDescription>
        Hiển thị ở đầu danh sách Quán chay gần bạn trong app (tối đa 1 quán mỗi lần), cho người dùng ở thành phố mục tiêu, trong thời gian chạy
        và khi còn ngân sách.
      </DialogDescription>

      <div className="grid grid-cols-1 gap-6 md:grid-cols-[minmax(0,1fr)_340px]">
        <form id={`${ids}-form`} className="flex min-w-0 flex-col gap-4" onSubmit={submit} noValidate>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor={`${ids}-restaurantId`}>Quán được quảng cáo</Label>
            <NativeSelect
              {...fieldProps("restaurantId")}
              value={state.restaurantId}
              onChange={(e) => set("restaurantId", e.target.value)}
              disabled={pending || restaurants.isLoading}
            >
              <option value="">{restaurants.isLoading ? "Đang tải danh sách quán…" : "Chọn quán…"}</option>
              {options.map((r) => (
                <option key={r.id} value={r.id}>
                  {`${r.name}${r.isVeganCertified ? "" : " (chưa chứng nhận)"}`}
                </option>
              ))}
            </NativeSelect>
            {hint(
              "restaurantId",
              restaurants.isError
                ? `Chưa tải được danh sách quán: ${describeError(restaurants.error)}`
                : "Mặc định chỉ hiện quán đã chứng nhận thuần chay.",
            )}
            <label className="flex w-fit items-center gap-2 text-sm">
              <Checkbox checked={showUncertified} onChange={(e) => setShowUncertified(e.target.checked)} disabled={pending} />
              Hiện cả quán chưa chứng nhận
            </label>
            {selected && !selected.isVeganCertified && (
              <p className="flex gap-2 rounded-lg border border-ochre-border bg-ochre-soft px-3 py-2 text-xs text-ochre-text">
                <TriangleAlert className="size-4 shrink-0" aria-hidden />
                Quán chưa được chứng nhận thuần chay. Hãy xác minh ở trang Quán chay trước khi quảng cáo.
              </p>
            )}
          </div>

          <div className="flex flex-col gap-1.5">
            <Label htmlFor={`${ids}-headline`}>Tiêu đề</Label>
            <Input
              {...fieldProps("headline")}
              value={state.headline}
              onChange={(e) => set("headline", e.target.value)}
              maxLength={AD_HEADLINE_MAX + 20}
              placeholder="VD: Bún riêu chay 35k — riêu đậu hũ mềm"
            />
            {hint("headline", `${state.headline.trim().length}/${AD_HEADLINE_MAX} ký tự`)}
          </div>

          <div className="flex flex-col gap-1.5">
            <Label htmlFor={`${ids}-message`}>Nội dung</Label>
            <Textarea
              {...fieldProps("message")}
              value={state.message}
              onChange={(e) => set("message", e.target.value)}
              maxLength={AD_MESSAGE_MAX + 40}
              placeholder="VD: Tô đầy đặn, nước dùng ngọt từ rau củ. Mở cửa 6:00–21:00."
            />
            {hint("message", `${state.message.trim().length}/${AD_MESSAGE_MAX} ký tự`)}
          </div>

          <div className="flex flex-col gap-2">
            <span className="text-sm font-semibold" id={`${ids}-cta-label`}>
              Nút hành động
            </span>
            <div role="radiogroup" aria-labelledby={`${ids}-cta-label`} className="inline-flex w-fit max-w-full flex-wrap gap-1 rounded-lg bg-muted p-1">
              {AD_CTA_TYPES.map((cta) => (
                <button
                  key={cta}
                  type="button"
                  role="radio"
                  aria-checked={state.ctaType === cta}
                  onClick={() => set("ctaType", cta)}
                  disabled={pending}
                  className={cn(
                    "inline-flex h-8 items-center rounded-md px-3 text-sm font-semibold text-muted-foreground transition-colors outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40",
                    state.ctaType === cta ? "bg-card text-foreground shadow-sm" : "hover:text-foreground",
                  )}
                >
                  {AD_CTA_LABEL[cta]}
                </button>
              ))}
            </div>
            <p className="text-xs text-muted-foreground">
              Xem quán mở trang quán, Chỉ đường mở bản đồ chỉ đường trong ứng dụng, Đặt bàn mở trang đặt chỗ / gọi quán.
            </p>
          </div>

          <div className="flex flex-col gap-1.5">
            <Label htmlFor={`${ids}-targetCity`}>Thành phố mục tiêu</Label>
            <NativeSelect {...fieldProps("targetCity")} value={state.city} onChange={(e) => set("city", e.target.value)}>
              {AD_CITIES.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
              <option value={NATIONAL}>Toàn quốc</option>
            </NativeSelect>
            {hint("targetCity", "Người dùng ở thành phố này (theo vị trí đã chọn) mới thấy dòng tài trợ.")}
          </div>

          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div className="flex min-w-0 flex-col gap-1.5">
              <Label htmlFor={`${ids}-startAt`}>Bắt đầu</Label>
              <Input {...fieldProps("startAt")} type="date" value={state.start} onChange={(e) => set("start", e.target.value)} />
              {hint("startAt", "Từ 00:00")}
            </div>
            <div className="flex min-w-0 flex-col gap-1.5">
              <Label htmlFor={`${ids}-endAt`}>Kết thúc</Label>
              <Input {...fieldProps("endAt")} type="date" value={state.end} min={state.start || undefined} onChange={(e) => set("end", e.target.value)} />
              {hint("endAt", "Đến 23:59")}
            </div>
          </div>

          <div className="flex flex-col gap-1.5">
            <Label htmlFor={`${ids}-budget`}>Ngân sách (VND)</Label>
            <Input
              {...fieldProps("budget")}
              type="number"
              inputMode="numeric"
              min={AD_MIN_BUDGET}
              step={100_000}
              value={state.budget}
              onChange={(e) => set("budget", e.target.value)}
              className="font-mono"
            />
            {hint(
              "budget",
              `${Number.isFinite(input.budget) ? formatVnd(input.budget) : "—"} · ${
                campaign ? `đã chi ${formatVnd(campaign.spent)}` : `tối thiểu ${formatVnd(AD_MIN_BUDGET)}`
              }`,
            )}
          </div>
        </form>

        <AdPreview
          restaurant={selected}
          headline={state.headline}
          message={state.message}
          ctaType={state.ctaType}
          className="md:sticky md:top-0 md:self-start"
        />
      </div>

      <DialogFooter>
        <DialogClose asChild>
          <Button type="button" variant="outline" disabled={pending}>
            Huỷ
          </Button>
        </DialogClose>
        <Button type="submit" form={`${ids}-form`} disabled={pending || (attempted && !valid)}>
          {campaign ? <Save aria-hidden /> : <Megaphone aria-hidden />}
          {pending ? "Đang lưu…" : campaign ? "Lưu thay đổi" : "Tạo quảng cáo"}
        </Button>
      </DialogFooter>
    </>
  );
}
