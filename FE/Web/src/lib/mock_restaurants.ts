// src/lib/mock_restaurants.ts
// In-memory restaurants + reviews for /restaurants. Fictional names only (we never imply
// a real place's certification), around Q.1/3/5/7 and Bình Thạnh, plus user submissions
// without coordinates. Review comments mention dishes, like the mobile mock.
// QA hook: the seeded submission "Quán thử nghiệm QA #fail" (and its review) fail every
// write with 503, so the optimistic toggle / delete rollback can be exercised.
import type { AdminSession } from "@/types/admin";
import type { AdminRestaurant, AdminReview, RestaurantMedia, RestaurantPerson, RestaurantQuery } from "@/types/restaurants";

import { ApiError } from "./api_error";
import { logAction } from "./mock_admin";
import { sleep } from "./mock_data";

const DAY = 24 * 60 * 60_000;
const NOW = Date.now();
const daysAgo = (d: number) => new Date(NOW - d * DAY).toISOString();

const PEOPLE = {
  u_me: "Minh Anh",
  u_thao_vy: "Thảo Vy",
  u_hoang_nam: "Hoàng Nam",
  u_ngoc_tram: "Ngọc Trâm",
  u_duc_huy: "Đức Huy",
  u_bep_may: "Bếp Chay Nhà Mây",
  u_new_1: "Phan Gia Bảo",
  u_new_2: "Lý Thanh Trúc",
  u_new_3: "Đỗ Hải Yến",
  u_chef_tam: "Lê Quang Tâm",
  u_gen_0: "Nguyễn Thị An",
  u_gen_1: "Vũ Ngọc Linh",
} as const;
type PersonId = keyof typeof PEOPLE;

const person = (id: PersonId): RestaurantPerson => ({ id, fullName: PEOPLE[id] });

interface RestaurantRow {
  id: string;
  name: string;
  address: string;
  isVeganCertified: boolean;
  createdBy: RestaurantPerson | null;
  latitude: number | null;
  longitude: number | null;
}

type Seed = [id: string, name: string, address: string, certified: boolean, createdBy: PersonId | null, coords: [number, number] | null];

const SEEDS: Seed[] = [
  ["rs_an_lac", "Quán Chay An Lạc", "12 Nguyễn Thị Minh Khai, P. Đa Kao, Q.1, TP.HCM", true, null, [10.7812, 106.699]],
  ["rs_thanh_tinh", "Chay Thanh Tịnh", "5 Tôn Thất Thiệp, P. Bến Nghé, Q.1, TP.HCM", false, null, [10.7745, 106.7032]],
  ["rs_sen_hong", "Bếp Chay Sen Hồng", "45 Trần Quốc Thảo, P. Võ Thị Sáu, Q.3, TP.HCM", true, null, [10.785, 106.6862]],
  ["rs_tam_nhu", "Cơm Chay Tâm Như", "210 Lê Văn Sỹ, P.14, Q.3, TP.HCM", true, null, [10.7905, 106.6788]],
  ["rs_nha_gao", "Cơm Chay Nhà Gạo", "73 Võ Văn Tần, P. Võ Thị Sáu, Q.3, TP.HCM", true, "u_hoang_nam", [10.7781, 106.6901]],
  ["rs_moc_nhien", "Lẩu Nấm Chay Mộc Nhiên", "88 Nguyễn Trãi, P.3, Q.5, TP.HCM", true, null, [10.7578, 106.6815]],
  ["rs_bo_de", "Phở Chay Bồ Đề Xanh", "17 Hải Thượng Lãn Ông, P.10, Q.5, TP.HCM", true, null, [10.7505, 106.66]],
  ["rs_co_ba", "Bánh Xèo Chay Cô Ba Hiền", "36 Đường số 7, P. Tân Phong, Q.7, TP.HCM", false, null, [10.7302, 106.7065]],
  ["rs_van_hoa", "Nhà Hàng Chay Vạn Hoa", "61 Nguyễn Thị Thập, P. Tân Hưng, Q.7, TP.HCM", true, null, [10.738, 106.716]],
  ["rs_hanh_tam", "Bún Riêu Chay Hạnh Tâm", "152 Đinh Tiên Hoàng, P.1, Q. Bình Thạnh, TP.HCM", true, null, [10.8003, 106.6977]],
  ["rs_lanh", "Sữa Hạt & Chay Lành", "24 Nguyễn Gia Trí, P.25, Q. Bình Thạnh, TP.HCM", true, null, [10.8036, 106.7155]],
  // User submissions from the app: uncertified, no coordinates.
  ["rs_ut_muoi", "Cơm Tấm Chay Út Mười", "Hẻm 120 Bùi Viện, P. Phạm Ngũ Lão, Q.1, TP.HCM", false, "u_me", null],
  ["rs_nha_la", "Quán Chay Nhà Lá", "Gian 12, chợ Bà Chiểu, Q. Bình Thạnh, TP.HCM", false, "u_thao_vy", null],
  ["rs_qa_fail", "Quán thử nghiệm QA #fail", "1 Đường thử nghiệm, Q.5, TP.HCM", false, "u_new_1", null],
];

const restaurants: RestaurantRow[] = SEEDS.map(([id, name, address, certified, createdBy, coords]) => ({
  id,
  name,
  address,
  isVeganCertified: certified,
  createdBy: createdBy ? person(createdBy) : null,
  latitude: coords?.[0] ?? null,
  longitude: coords?.[1] ?? null,
}));

type ReviewSeed = [user: PersonId, rating: number, comment: string, daysAgo: number];

const REVIEW_SEEDS: Record<string, ReviewSeed[]> = {
  rs_an_lac: [
    ["u_me", 5, "Bún riêu chay đậm vị, riêu đậu hũ mềm, nước dùng ngọt từ rau củ. Sẽ quay lại!", 3],
    ["u_hoang_nam", 4, "Phở chay nước trong, nhiều nấm. Trưa đông nên chờ hơi lâu.", 9],
    ["u_ngoc_tram", 5, "Quán sạch, nhân viên dễ thương, thực đơn ghi rõ món thuần chay không trứng sữa.", 16],
    ["u_duc_huy", 4, "Cơm tấm chay sườn non làm từ đậu khá giống thật, giá hợp lý.", 30],
  ],
  rs_thanh_tinh: [
    ["u_hoang_nam", 4, "Cơm chay văn phòng nhanh gọn, có giao hàng trong Q.1.", 4],
    ["u_thao_vy", 2, "Vỏ chả giò chay có vẻ dùng trứng, cần quán xác nhận lại nguyên liệu.", 12],
    ["u_gen_1", 4, "Mì xào chay giòn, rau cải ngọt.", 20],
  ],
  rs_sen_hong: [
    ["u_thao_vy", 5, "Lẩu nấm thập cẩm cho 2 người rất đầy đặn, nước lẩu thanh.", 2],
    ["u_new_2", 4, "Gỏi cuốn chay tươi, nước chấm tương đậu phộng ngon.", 11],
    ["u_bep_may", 5, "Không gian yên tĩnh, hợp đi cùng gia đình. Bánh xèo chay giòn rụm.", 20],
  ],
  rs_tam_nhu: [
    ["u_duc_huy", 4, "Cơm phần chay nhiều rau, 45k no bụng. Canh rong biển ngon.", 1],
    ["u_gen_0", 4, "Cơm tấm chay bì chả đầy đủ, chả làm từ đậu hũ non.", 7],
    ["u_gen_1", 3, "Đồ ăn ổn nhưng hơi mặn, giờ trưa khá đông.", 14],
    ["u_new_3", 5, "Có món riêng cho bé ăn dặm chay, chủ quán tư vấn nhiệt tình.", 25],
  ],
  rs_nha_gao: [
    ["u_me", 5, "Cơm gạo lứt muối mè và canh nấm, hợp người đang ăn kiêng.", 6],
    ["u_new_3", 4, "Quán nhỏ xinh, nêm vừa, có sữa hạt tự làm.", 17],
    ["u_duc_huy", 4, "Cơm tấm chay khá ổn, giá sinh viên.", 29],
  ],
  rs_moc_nhien: [
    ["u_me", 5, "Lẩu nấm 7 loại, nấm tươi, nước dùng ngọt thanh không bột ngọt.", 5],
    ["u_chef_tam", 5, "Nấm sơ chế kỹ, rau ăn kèm sạch. Hợp nhóm bạn đi đông.", 12],
    ["u_hoang_nam", 4, "Lẩu nấm ngon nhưng giá hơi cao so với khu vực.", 18],
    ["u_new_1", 4, "Đậu hũ phô mai chay thả lẩu rất béo, nên thử.", 40],
    ["u_thao_vy", 5, "Phục vụ nhanh, có phòng riêng cho gia đình.", 55],
  ],
  rs_bo_de: [
    ["u_ngoc_tram", 5, "Phở chay nước dùng ninh từ củ cải, bắp và nấm hương, đúng vị phở Bắc.", 4],
    ["u_gen_0", 4, "Bánh cuốn chay nhân nấm mèo mỏng, mềm.", 10],
    ["u_duc_huy", 4, "Sáng chủ nhật đông, nên đến trước 8 giờ.", 22],
  ],
  rs_co_ba: [
    ["u_new_2", 4, "Bánh xèo chay giòn, nhân củ sắn nấm mèo, rau rừng ăn kèm nhiều.", 6],
    ["u_thao_vy", 3, "Bánh xèo ngon nhưng chưa rõ nước chấm có dùng nước mắm thật không.", 13],
    ["u_bep_may", 4, "Bánh khọt chay cũng đáng thử.", 27],
  ],
  rs_van_hoa: [
    ["u_bep_may", 4, "Thực đơn tiệc chay đa dạng, hợp đặt bàn giỗ chạp.", 7],
    ["u_gen_0", 5, "Lẩu nấm và gỏi ngó sen chay rất ngon, phục vụ chuyên nghiệp.", 19],
    ["u_duc_huy", 3, "Món ngon nhưng cuối tuần phải chờ lâu.", 31],
    ["u_new_1", 4, "Có chỗ đậu ô tô, tiện đi cả gia đình.", 46],
  ],
  rs_hanh_tam: [
    ["u_me", 5, "Bún riêu chay ngon nhất mình từng ăn: riêu đậu hũ, cà chua chín, mắm tôm chay để riêng.", 2],
    ["u_new_3", 5, "Quán nhỏ nhưng sạch, có bún riêu chay ít cay cho trẻ em.", 8],
    ["u_hoang_nam", 4, "Bún mọc chay cũng ngon, chỗ để xe hơi chật.", 15],
    ["u_gen_1", 5, "Giá rẻ, 35k một tô đầy đặn.", 33],
  ],
  rs_lanh: [
    ["u_new_2", 5, "Sữa hạt óc chó ít ngọt, có bán theo chai mang về.", 3],
    ["u_ngoc_tram", 4, "Bánh mì chay pate nấm ngon, sữa hạt sen thơm.", 9],
    ["u_chef_tam", 4, "Nguyên liệu hạt rõ nguồn gốc. Nên thêm lựa chọn không đường.", 21],
  ],
  rs_ut_muoi: [["u_thao_vy", 4, "Cơm tấm chay sườn nướng sả thơm, quán vỉa hè nhưng sạch sẽ.", 1]],
  rs_qa_fail: [["u_new_1", 3, "Đánh giá thử nghiệm QA #fail — xoá sẽ báo lỗi để kiểm tra hoàn tác.", 0.5]],
};

const MEDIA_BASE = "https://res.cloudinary.com/veganlife";

/** restaurant_media: [restaurantId, type, file, uploader (null = admin team), days ago]. */
const MEDIA_SEEDS: [restaurantId: string, type: "Image" | "Video", file: string, by: PersonId | null, age: number][] = [
  ["rs_an_lac", "Image", "an_lac_mat_tien.jpg", null, 40],
  ["rs_an_lac", "Image", "an_lac_bun_rieu.jpg", "u_me", 3],
  ["rs_hanh_tam", "Image", "hanh_tam_to_bun.jpg", null, 30],
  ["rs_hanh_tam", "Video", "hanh_tam_gioi_thieu.mp4", null, 30],
  ["rs_moc_nhien", "Image", "moc_nhien_lau_nam.jpg", "u_chef_tam", 12],
  ["rs_nha_gao", "Image", "nha_gao_com_gao_lut.jpg", "u_hoang_nam", 17],
  ["rs_nha_gao", "Image", "nha_gao_quay.jpg", "u_hoang_nam", 17],
  ["rs_ut_muoi", "Image", "ut_muoi_com_tam.jpg", "u_me", 1],
  ["rs_ut_muoi", "Image", "ut_muoi_mat_tien.jpg", "u_me", 1],
  ["rs_ut_muoi", "Video", "ut_muoi_quay_quan.mp4", "u_me", 1],
  ["rs_nha_la", "Image", "nha_la_gian_hang.jpg", "u_thao_vy", 4],
];

const media: (RestaurantMedia & { restaurantId: string })[] = MEDIA_SEEDS.map(([restaurantId, type, file, by, age], i) => ({
  id: `rm_${i + 1}`,
  restaurantId,
  mediaType: type,
  mediaUrl: `${MEDIA_BASE}/${type === "Video" ? "video" : "image"}/upload/v1/restaurants/${file}`,
  uploadedBy: by ? person(by) : null,
  createdAt: daysAgo(age),
}));

let reviews: AdminReview[] = Object.entries(REVIEW_SEEDS).flatMap(([restaurantId, list]) =>
  list.map(([user, rating, comment, age], i) => ({
    id: `rv_${restaurantId.replace(/^rs_/, "")}_${i + 1}`,
    restaurantId,
    user: person(user),
    rating,
    comment,
    createdAt: daysAgo(age),
  })),
);

/* ----------------------------------------------------------------- reads */

const fold = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[Đđ]/g, "d").toLowerCase();

function view(r: RestaurantRow): AdminRestaurant {
  const mine = reviews.filter((v) => v.restaurantId === r.id);
  return {
    ...r,
    createdBy: r.createdBy && { ...r.createdBy },
    averageRating: mine.length ? mine.reduce((s, v) => s + v.rating, 0) / mine.length : null,
    reviewCount: mine.length,
    media: media
      .filter((m) => m.restaurantId === r.id)
      .map((m) => ({ id: m.id, mediaType: m.mediaType, mediaUrl: m.mediaUrl, uploadedBy: m.uploadedBy && { ...m.uploadedBy }, createdAt: m.createdAt })),
  };
}

const unavailable = (what: string) => new ApiError(`Máy chủ đang bận, chưa ${what}. Thử lại sau.`, 503, "unavailable");
const hasFail = (text: string) => text.toLowerCase().includes("#fail");

function find(id: string) {
  const r = restaurants.find((x) => x.id === id);
  if (!r) throw new ApiError("Quán không còn tồn tại.", 404, "not_found");
  return r;
}

export async function listRestaurants(query: RestaurantQuery): Promise<AdminRestaurant[]> {
  await sleep(400);
  if (hasFail(query.search)) throw unavailable("tải được danh sách quán");
  const q = fold(query.search.trim());
  return restaurants
    .filter((r) => query.certified === "all" || r.isVeganCertified === (query.certified === "certified"))
    .filter((r) => query.source === "all" || (query.source === "user") === (r.createdBy !== null))
    .filter((r) => !q || fold(`${r.name} ${r.address}`).includes(q))
    .sort((a, b) => a.name.localeCompare(b.name, "vi"))
    .map(view);
}

export async function listReviews(restaurantId: string): Promise<AdminReview[]> {
  await sleep(350);
  find(restaurantId);
  return reviews
    .filter((v) => v.restaurantId === restaurantId)
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
    .map((v) => ({ ...v, user: { ...v.user } }));
}

/* ---------------------------------------------------------------- writes */

export async function setCertified(id: string, isVeganCertified: boolean, session: AdminSession | null): Promise<AdminRestaurant> {
  await sleep(500);
  const r = find(id);
  if (hasFail(r.name)) throw unavailable("lưu được chứng nhận");
  r.isVeganCertified = isVeganCertified;
  logAction(session?.fullName ?? "Quản trị viên", isVeganCertified ? "chứng nhận quán thuần chay" : "bỏ chứng nhận quán chay", r.name);
  return view(r);
}

export async function deleteRestaurant(id: string, session: AdminSession | null): Promise<void> {
  await sleep(550);
  const r = find(id);
  if (hasFail(r.name)) throw unavailable("xoá được quán");
  restaurants.splice(restaurants.indexOf(r), 1);
  const removed = reviews.filter((v) => v.restaurantId === id).length;
  reviews = reviews.filter((v) => v.restaurantId !== id);
  logAction(session?.fullName ?? "Quản trị viên", "xoá quán chay", `${r.name} (${removed} đánh giá)`);
}

export async function deleteReview(id: string, session: AdminSession | null): Promise<void> {
  await sleep(450);
  const review = reviews.find((v) => v.id === id);
  if (!review) throw new ApiError("Đánh giá không còn tồn tại.", 404, "not_found");
  if (hasFail(review.comment)) throw unavailable("xoá được đánh giá");
  reviews = reviews.filter((v) => v.id !== id);
  const name = restaurants.find((r) => r.id === review.restaurantId)?.name ?? review.restaurantId;
  logAction(session?.fullName ?? "Quản trị viên", "xoá đánh giá quán", `${review.user.fullName} · ${name}`);
}
