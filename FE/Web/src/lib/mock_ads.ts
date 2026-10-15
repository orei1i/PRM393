// src/lib/mock_ads.ts
// In-memory store-ad campaigns for /ads, plus the public feed the mobile app reads.
// Restaurants come from mock_restaurants.ts (read-only): every campaign keeps a snapshot that is
// refreshed from the live list on each read, so a rename or a certification change on /restaurants
// shows up here; a deleted restaurant keeps its last snapshot.
// Spend is simulated at a 40.000đ CPM (40đ per impression), capped at the budget.
// QA: `#fail` in the headline on create / edit → 503. The seeded "Chiến dịch thử nghiệm QA #fail"
// fails pause / resume / delete with 503, so the optimistic rollback can be checked. `#fail` in search → 503.
import type { AdminSession } from "@/types/admin";
import type { AdCampaign, AdCtaType, AdFeedItem, AdInput, AdQuery, AdRestaurant, AdStatus } from "@/types/ads";
import { AD_CTA_LABEL, adInputErrors, deriveAdStatus } from "@/types/ads";
import type { AdminRestaurant } from "@/types/restaurants";

import { ApiError } from "./api_error";
import { logAction } from "./mock_admin";
import { sleep } from "./mock_data";
import { listRestaurants } from "./mock_restaurants";

const NOW = Date.now();
const iso = (ms: number) => new Date(ms).toISOString();

/** Local midnight `offset` days from today / the last millisecond of that day. */
function dayStart(offset: number) {
  const d = new Date(NOW);
  d.setDate(d.getDate() + offset);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}
const dayEnd = (offset: number) => dayStart(offset + 1) - 1;

/** Mock spend: 40đ per impression (40.000đ CPM). */
const COST_PER_IMPRESSION = 40;

const ALL_RESTAURANTS = { certified: "all", source: "all", search: "" } as const;

/* ----------------------------------------------------------------- seeds */

/** Snapshots for the seeds; refreshed from mock_restaurants on every read. */
const SEED_RESTAURANTS: Record<string, AdRestaurant> = {
  rs_hanh_tam: {
    id: "rs_hanh_tam",
    name: "Bún Riêu Chay Hạnh Tâm",
    address: "152 Đinh Tiên Hoàng, P.1, Q. Bình Thạnh, TP.HCM",
    isVeganCertified: true,
    latitude: 10.8003,
    longitude: 106.6977,
  },
  rs_moc_nhien: {
    id: "rs_moc_nhien",
    name: "Lẩu Nấm Chay Mộc Nhiên",
    address: "88 Nguyễn Trãi, P.3, Q.5, TP.HCM",
    isVeganCertified: true,
    latitude: 10.7578,
    longitude: 106.6815,
  },
  rs_lanh: {
    id: "rs_lanh",
    name: "Sữa Hạt & Chay Lành",
    address: "24 Nguyễn Gia Trí, P.25, Q. Bình Thạnh, TP.HCM",
    isVeganCertified: true,
    latitude: 10.8036,
    longitude: 106.7155,
  },
  rs_van_hoa: {
    id: "rs_van_hoa",
    name: "Nhà Hàng Chay Vạn Hoa",
    address: "61 Nguyễn Thị Thập, P. Tân Hưng, Q.7, TP.HCM",
    isVeganCertified: true,
    latitude: 10.738,
    longitude: 106.716,
  },
  rs_bo_de: {
    id: "rs_bo_de",
    name: "Phở Chay Bồ Đề Xanh",
    address: "17 Hải Thượng Lãn Ông, P.10, Q.5, TP.HCM",
    isVeganCertified: true,
    latitude: 10.7505,
    longitude: 106.66,
  },
  rs_tam_nhu: {
    id: "rs_tam_nhu",
    name: "Cơm Chay Tâm Như",
    address: "210 Lê Văn Sỹ, P.14, Q.3, TP.HCM",
    isVeganCertified: true,
    latitude: 10.7905,
    longitude: 106.6788,
  },
};

type Seed = [
  id: string,
  restaurantId: keyof typeof SEED_RESTAURANTS,
  headline: string,
  message: string,
  cta: AdCtaType,
  city: string | null,
  startDay: number,
  endDay: number,
  paused: boolean,
  budget: number,
  impressions: number,
  clicks: number,
];

const HCM = "TP. Hồ Chí Minh";

const SEEDS: Seed[] = [
  [
    "ad_hanh_tam",
    "rs_hanh_tam",
    "Bún riêu chay 35k — riêu đậu hũ mềm",
    "Tô đầy đặn, nước dùng ngọt từ rau củ, mắm tôm chay để riêng. Mở cửa 6:00–21:00.",
    "ViewStore",
    HCM,
    -10,
    20,
    false,
    3_000_000,
    48_210,
    1_327,
  ],
  [
    "ad_moc_nhien",
    "rs_moc_nhien",
    "Lẩu nấm 7 loại cho nhóm bạn",
    "Giảm 15% cho bàn từ 4 người tối thứ 2–5. Có phòng riêng cho gia đình.",
    "Book",
    HCM,
    -5,
    25,
    false,
    5_000_000,
    31_540,
    942,
  ],
  [
    "ad_lanh",
    "rs_lanh",
    "Sữa hạt óc chó ít ngọt, làm mỗi sáng",
    "Có chai 1 lít mang về và bánh mì chay pate nấm. Ghé quán gần cầu Thị Nghè.",
    "Directions",
    HCM,
    -12,
    18,
    true,
    2_000_000,
    12_880,
    301,
  ],
  [
    "ad_van_hoa",
    "rs_van_hoa",
    "Đặt tiệc chay giỗ chạp, 8–12 món",
    "Thực đơn tiệc chay đa dạng, có chỗ đậu ô tô. Đặt trước 3 ngày để chọn món.",
    "Book",
    HCM,
    3,
    33,
    false,
    4_000_000,
    0,
    0,
  ],
  [
    "ad_bo_de",
    "rs_bo_de",
    "Phở chay đúng vị Bắc từ 6 giờ sáng",
    "Nước dùng ninh từ củ cải, bắp và nấm hương. Có bánh cuốn chay nhân nấm mèo.",
    "ViewStore",
    HCM,
    -40,
    -10,
    false,
    2_500_000,
    61_200,
    1_598,
  ],
  [
    "ad_qa_fail",
    "rs_tam_nhu",
    "Chiến dịch thử nghiệm QA #fail",
    "Mọi thao tác trên chiến dịch này trả lỗi 503 để kiểm tra hoàn tác.",
    "ViewStore",
    null,
    -2,
    12,
    true,
    1_000_000,
    0,
    0,
  ],
];

type Row = Omit<AdCampaign, "status">;

let ads: Row[] = SEEDS.map(([id, restaurantId, headline, message, ctaType, targetCity, startDay, endDay, isPaused, budget, impressions, clicks]) => {
  const created = dayStart(Math.min(startDay, 0) - 2) + 10 * 60 * 60_000;
  return {
    id,
    restaurantId,
    restaurant: { ...SEED_RESTAURANTS[restaurantId] },
    headline,
    message,
    ctaType,
    targetCity,
    startAt: iso(dayStart(startDay)),
    endAt: iso(dayEnd(endDay)),
    isPaused,
    budget,
    spent: Math.min(budget, impressions * COST_PER_IMPRESSION),
    impressions,
    clicks,
    createdAt: iso(created),
    updatedAt: iso(created),
  };
});

let adSeq = 0;

/* ----------------------------------------------------------------- helpers */

const fold = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[Đđ]/g, "d").toLowerCase();
const hasFail = (text: string) => text.toLowerCase().includes("#fail");
const unavailable = (what: string) => new ApiError(`Máy chủ đang bận, chưa ${what}. Thử lại sau.`, 503, "unavailable");

const snapshot = (r: AdminRestaurant): AdRestaurant => ({
  id: r.id,
  name: r.name,
  address: r.address,
  isVeganCertified: r.isVeganCertified,
  latitude: r.latitude,
  longitude: r.longitude,
});

/** Live restaurants; also refreshes every campaign's snapshot. */
async function loadRestaurants(): Promise<Map<string, AdminRestaurant>> {
  const list = await listRestaurants(ALL_RESTAURANTS);
  const byId = new Map(list.map((r) => [r.id, r]));
  for (const ad of ads) {
    const live = byId.get(ad.restaurantId);
    if (live) ad.restaurant = snapshot(live);
  }
  return byId;
}

function view(row: Row, now = Date.now()): AdCampaign {
  return { ...row, restaurant: { ...row.restaurant }, status: deriveAdStatus(row, now) };
}

function find(id: string) {
  const row = ads.find((a) => a.id === id);
  if (!row) throw new ApiError("Chiến dịch quảng cáo không còn tồn tại.", 404, "not_found");
  return row;
}

function assertValid(input: AdInput, isNew: boolean, spent?: number) {
  const errors = adInputErrors(input, { isNew, spent });
  const first = Object.values(errors)[0];
  if (first) throw new ApiError(first, 400, "validation");
}

const STATUS_ORDER: Record<AdStatus, number> = { Running: 0, Scheduled: 1, Paused: 2, Ended: 3 };

/* ----------------------------------------------------------------- reads */

/** GET /admin/ads?status=&city=&search= */
export async function listAds(query: AdQuery): Promise<AdCampaign[]> {
  await Promise.all([loadRestaurants(), sleep(150)]);
  if (hasFail(query.search)) throw unavailable("tải được danh sách quảng cáo");
  const now = Date.now();
  const q = fold(query.search.trim());
  return ads
    .map((row) => view(row, now))
    .filter((a) => query.status === "all" || a.status === query.status)
    .filter((a) => query.city === "all" || (query.city === "national" ? a.targetCity === null : a.targetCity === query.city))
    .filter((a) => !q || fold(`${a.headline} ${a.message} ${a.restaurant.name}`).includes(q))
    .sort((x, y) => STATUS_ORDER[x.status] - STATUS_ORDER[y.status] || y.startAt.localeCompare(x.startAt));
}

const haversineKm = (lat1: number, lng1: number, lat2: number, lng2: number) => {
  const rad = (d: number) => (d * Math.PI) / 180;
  const a = Math.sin(rad(lat2 - lat1) / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(rad(lng2 - lng1) / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.sqrt(a));
};

/** GET /ads/feed?city=&lat=&lng=&limit= — what the mobile feed shows as "Được tài trợ" cards. */
export async function getFeed(city: string | null, coords: { lat: number; lng: number } | null, limit = 3): Promise<AdFeedItem[]> {
  const [restaurants] = await Promise.all([loadRestaurants(), sleep(150)]);
  const now = Date.now();
  const wanted = city ? fold(city.trim()) : null;
  return ads
    .filter((a) => deriveAdStatus(a, now) === "Running")
    .filter((a) => a.targetCity === null || wanted === null || fold(a.targetCity) === wanted)
    .map((a): AdFeedItem => {
      const r = a.restaurant;
      const live = restaurants.get(a.restaurantId);
      const distanceKm =
        coords && r.latitude !== null && r.longitude !== null
          ? Math.round(haversineKm(coords.lat, coords.lng, r.latitude, r.longitude) * 10) / 10
          : null;
      return {
        id: a.id,
        restaurantId: a.restaurantId,
        restaurant: { ...r, averageRating: live?.averageRating ?? null, reviewCount: live?.reviewCount ?? 0 },
        headline: a.headline,
        message: a.message,
        ctaType: a.ctaType,
        ctaLabel: AD_CTA_LABEL[a.ctaType],
        targetCity: a.targetCity,
        startAt: a.startAt,
        endAt: a.endAt,
        distanceKm,
      };
    })
    .sort((x, y) => (x.distanceKm ?? Infinity) - (y.distanceKm ?? Infinity) || y.startAt.localeCompare(x.startAt))
    .slice(0, Math.max(1, limit));
}

/* ---------------------------------------------------------------- writes */

/** POST /admin/ads */
export async function createAd(input: AdInput, session: AdminSession | null): Promise<AdCampaign> {
  const [restaurants] = await Promise.all([loadRestaurants(), sleep(450)]);
  assertValid(input, true);
  if (hasFail(input.headline)) throw unavailable("tạo được quảng cáo");
  const restaurant = restaurants.get(input.restaurantId);
  if (!restaurant) throw new ApiError("Quán không còn tồn tại.", 400, "restaurant_not_found");
  const now = new Date().toISOString();
  const row: Row = {
    id: `ad_new_${++adSeq}`,
    ...input,
    headline: input.headline.trim(),
    message: input.message.trim(),
    restaurant: snapshot(restaurant),
    isPaused: false,
    spent: 0,
    impressions: 0,
    clicks: 0,
    createdAt: now,
    updatedAt: now,
  };
  ads = [row, ...ads];
  logAction(session?.fullName ?? "Quản trị viên", "tạo quảng cáo cửa hàng", `${restaurant.name} · ${row.headline}`);
  return view(row);
}

/** PATCH /admin/ads/{id} — any subset of AdInput. */
export async function updateAd(id: string, patch: Partial<AdInput>, session: AdminSession | null): Promise<AdCampaign> {
  const [restaurants] = await Promise.all([loadRestaurants(), sleep(450)]);
  const row = find(id);
  const next: AdInput = {
    restaurantId: patch.restaurantId ?? row.restaurantId,
    headline: (patch.headline ?? row.headline).trim(),
    message: (patch.message ?? row.message).trim(),
    ctaType: patch.ctaType ?? row.ctaType,
    targetCity: patch.targetCity === undefined ? row.targetCity : patch.targetCity,
    startAt: patch.startAt ?? row.startAt,
    endAt: patch.endAt ?? row.endAt,
    budget: patch.budget ?? row.budget,
  };
  assertValid(next, false, row.spent);
  if (hasFail(next.headline)) throw unavailable("lưu được quảng cáo");
  const restaurant = restaurants.get(next.restaurantId);
  if (!restaurant && next.restaurantId !== row.restaurantId) throw new ApiError("Quán không còn tồn tại.", 400, "restaurant_not_found");
  Object.assign(row, next, { restaurant: restaurant ? snapshot(restaurant) : row.restaurant, updatedAt: new Date().toISOString() });
  logAction(session?.fullName ?? "Quản trị viên", "sửa quảng cáo cửa hàng", `${row.restaurant.name} · ${row.headline}`);
  return view(row);
}

/** POST /admin/ads/{id}/pause | /resume — 409 once the campaign has ended. */
export async function setAdPaused(id: string, paused: boolean, session: AdminSession | null): Promise<AdCampaign> {
  await sleep(450);
  const row = find(id);
  if (hasFail(row.headline)) throw unavailable(paused ? "tạm dừng được quảng cáo" : "chạy lại được quảng cáo");
  if (deriveAdStatus(row) === "Ended") {
    throw new ApiError("Chiến dịch đã kết thúc — sửa ngày kết thúc hoặc ngân sách để chạy lại.", 409, "ended");
  }
  row.isPaused = paused;
  row.updatedAt = new Date().toISOString();
  logAction(session?.fullName ?? "Quản trị viên", paused ? "tạm dừng quảng cáo" : "chạy lại quảng cáo", `${row.restaurant.name} · ${row.headline}`);
  return view(row);
}

/** DELETE /admin/ads/{id} */
export async function deleteAd(id: string, session: AdminSession | null): Promise<void> {
  await sleep(500);
  const row = find(id);
  if (hasFail(row.headline)) throw unavailable("xoá được quảng cáo");
  ads = ads.filter((a) => a.id !== id);
  logAction(session?.fullName ?? "Quản trị viên", "xoá quảng cáo cửa hàng", `${row.restaurant.name} · ${row.headline}`);
}
