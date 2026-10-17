// src/lib/mock_admin.ts
// In-memory mock backend for the admin console (users, chef applications,
// content, comments, catalog, overview). Mirrors the mobile app's mock data so
// the same people and posts appear on both sides.
import type {
  AdminComment,
  AdminSession,
  AdminUser,
  AssignableRole,
  CatalogInput,
  CatalogItem,
  CatalogKind,
  ChefApplication,
  ChefApplicationStatus,
  ChefReviewInput,
  CommentQuery,
  ContentAction,
  ContentItem,
  ContentQuery,
  MediaType,
  OverviewStats,
  PostReviewInput,
  UserQuery,
  UserRole,
  UserStatus,
  UserStatusChange,
} from "@/types/admin";
import { MIN_AUDIT_NOTE_LENGTH } from "@/types/moderation";

import { ApiError } from "./api_error";
import { getFlagCounts, recordDecisionSample, sleep } from "./mock_data";

const minutesAgo = (m: number) => new Date(Date.now() - m * 60_000).toISOString();
const daysAgo = (d: number) => minutesAgo(d * 24 * 60);

export const MOCK_ADMIN = { id: "u_admin", email: "admin@veganlife.vn", password: "admin123", fullName: "Trần Thu Hằng" };

/* ------------------------------------------------------------------- audit */

const audit: OverviewStats["recentActions"] = [
  { id: "a3", at: minutesAgo(35), actor: "Trần Thu Hằng", action: "ẩn bài viết", target: "Trà giảm cân thảo mộc — inbox Zalo" },
  { id: "a2", at: minutesAgo(190), actor: "Lê Minh Quân", action: "duyệt chuyên gia", target: "Võ Thị Ngọc Lan" },
  { id: "a1", at: daysAgo(1), actor: "Trần Thu Hằng", action: "cấm tài khoản", target: "thuocgiamcan.official" },
];

let auditSeq = 0;

/** Admin audit log shown on /overview. Other mock modules (knowledge, AI models) write here too. */
export function logAction(actor: string, action: string, target: string) {
  audit.unshift({ id: `a${Date.now()}_${auditSeq++}`, at: new Date().toISOString(), actor, action, target });
  audit.splice(12);
}

/* ------------------------------------------------------------------- users */

/** `chef` = verified chef; their role is "Chef". */
type Seed = [id: string, fullName: string, email: string, role: UserRole, status: UserStatus, chef: boolean, posts: number, reports: number, joinedDaysAgo: number];

const SEED_USERS: Seed[] = [
  ["u_admin", "Trần Thu Hằng", "admin@veganlife.vn", "Admin", "Active", false, 3, 0, 210],
  ["u_admin_2", "Lê Minh Quân", "quan.le@veganlife.vn", "Admin", "Active", false, 0, 0, 180],
  ["u_me", "Minh Anh", "minhanh.nguyen@gmail.com", "User", "Active", false, 3, 0, 104],
  ["u_chef_tam", "Lê Quang Tâm", "tam.chefchay@gmail.com", "Chef", "Active", true, 48, 0, 320],
  ["u_thu_ha", "ThS. DD Phạm Thu Hà", "thuha.dinhduong@gmail.com", "Chef", "Active", true, 31, 0, 290],
  ["u_chef_chau", "Tôn Nữ Minh Châu", "minhchau.hue@gmail.com", "Chef", "Active", true, 22, 0, 260],
  ["u_chef_khoa", "Nguyễn Đăng Khoa", "khoa.fitvegan@gmail.com", "Chef", "Active", true, 17, 0, 150],
  ["u_chef_lan", "Võ Thị Ngọc Lan", "ngoclan.anddam@gmail.com", "Chef", "Active", true, 12, 0, 140],
  ["u_chef_minh", "Trần Quốc Minh", "quocminh.thucduong@gmail.com", "Chef", "Active", true, 9, 0, 230],
  ["u_bep_may", "Bếp Chay Nhà Mây", "bepchaynhamay@gmail.com", "User", "Active", false, 64, 1, 300],
  ["u_thao_vy", "Thảo Vy", "thaovy.nguyen@gmail.com", "User", "Active", false, 27, 0, 200],
  ["u_hoang_nam", "Hoàng Nam", "hoangnam.dev@gmail.com", "User", "Active", false, 15, 0, 120],
  ["u_ngoc_tram", "Ngọc Trâm", "ngoctram.k17@gmail.com", "User", "Active", false, 4, 0, 21],
  ["u_duc_huy", "Đức Huy", "duchuy.q9@gmail.com", "User", "Active", false, 6, 0, 45],
  ["u_spam_1", "thuocgiamcan.official", "zalo.giamcan247@gmail.com", "User", "Banned", false, 11, 23, 9],
  ["u_detox", "Detox Xanh Mỗi Ngày", "detoxxanh.vn@gmail.com", "User", "Locked", false, 8, 9, 30],
  ["u_new_1", "Phan Gia Bảo", "giabao.chef@gmail.com", "User", "Active", false, 5, 0, 60],
  ["u_new_2", "Lý Thanh Trúc", "thanhtruc.dietitian@gmail.com", "User", "Active", false, 2, 0, 33],
  ["u_new_3", "Đỗ Hải Yến", "haiyen.mebe@gmail.com", "User", "Active", false, 1, 0, 12],
  ["u_pending", "Quách Bảo Ngân", "baongan.q@gmail.com", "User", "Inactive", false, 0, 0, 1],
];

const FAMILY = ["Nguyễn", "Trần", "Lê", "Phạm", "Hoàng", "Huỳnh", "Phan", "Vũ", "Võ", "Đặng", "Bùi", "Đỗ", "Hồ", "Ngô", "Dương"];
const MIDDLE = ["Thị", "Văn", "Minh", "Ngọc", "Thanh", "Gia", "Bảo", "Hữu", "Quốc", "Thu"];
const GIVEN = ["An", "Bình", "Chi", "Dũng", "Giang", "Hà", "Khánh", "Linh", "Mai", "Nhi", "Phúc", "Quyên", "Sơn", "Tú", "Uyên", "Vy", "Yến", "Long", "Hạnh", "Tùng"];
const ASCII: Record<string, string> = { Đ: "d", đ: "d" };
const slug = (s: string) =>
  s
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[Đđ]/g, (c) => ASCII[c])
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ".")
    .replace(/^\.|\.$/g, "");

function buildUsers(): AdminUser[] {
  const users: AdminUser[] = SEED_USERS.map(([id, fullName, email, role, status, chef, posts, reports, joined], i) => ({
    id,
    email,
    fullName,
    phone: `09${String(10000000 + i * 7919).slice(0, 8)}`,
    role,
    status,
    authType: email.endsWith("@veganlife.vn") ? "System" : "Google",
    createdAt: daysAgo(joined),
    isVerifiedChef: chef,
    postCount: posts,
    reportCount: reports,
    lastActiveAt: status === "Inactive" ? null : minutesAgo(15 + i * 47),
  }));
  for (let i = 0; i < 36; i++) {
    const fullName = `${FAMILY[(i * 7) % FAMILY.length]} ${MIDDLE[(i * 3) % MIDDLE.length]} ${GIVEN[(i * 11) % GIVEN.length]}`;
    users.push({
      id: `u_gen_${i}`,
      email: `${slug(fullName)}${i}@gmail.com`,
      fullName,
      phone: `03${String(20000000 + i * 104729).slice(0, 8)}`,
      role: "User",
      status: i % 17 === 5 ? "Locked" : "Active",
      authType: i % 4 === 0 ? "System" : "Google",
      createdAt: daysAgo(2 + ((i * 13) % 200)),
      isVerifiedChef: false,
      postCount: (i * 5) % 14,
      reportCount: i % 17 === 5 ? 4 : 0,
      lastActiveAt: minutesAgo(30 + i * 173),
    });
  }
  return users;
}

const users = buildUsers();

const SEARCH_FOLD = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[Đđ]/g, "d").toLowerCase();

export async function listUsers(query: UserQuery): Promise<AdminUser[]> {
  await sleep(450);
  const q = SEARCH_FOLD(query.search.trim());
  return users
    .filter((u) => query.role === "all" || u.role === query.role)
    .filter((u) => query.status === "all" || u.status === query.status)
    .filter((u) => !q || SEARCH_FOLD(`${u.fullName} ${u.email} ${u.phone}`).includes(q))
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}

function findUser(id: string) {
  const user = users.find((u) => u.id === id);
  if (!user) throw new ApiError("Không tìm thấy người dùng.", 404);
  return user;
}

function guardSelf(id: string, session: AdminSession | null) {
  if (session && id === session.userId) {
    throw new ApiError("Bạn không thể tự đổi quyền, khoá hoặc xoá tài khoản đang đăng nhập.", 409, "self_action");
  }
}

export async function updateUserRole(id: string, role: AssignableRole, session: AdminSession | null): Promise<AdminUser> {
  await sleep(500);
  guardSelf(id, session);
  const user = findUser(id);
  if (user.role === "Chef") {
    throw new ApiError("Vai trò Chuyên gia được cấp khi duyệt hồ sơ chuyên gia, không đổi ở đây.", 409, "chef_role_locked");
  }
  user.role = role;
  logAction(session?.fullName ?? "Quản trị viên", role === "Admin" ? "cấp quyền quản trị" : "gỡ quyền quản trị", user.fullName);
  return { ...user };
}

export async function updateUserStatus(change: UserStatusChange, session: AdminSession | null): Promise<AdminUser> {
  await sleep(550);
  guardSelf(change.userId, session);
  if (change.reason?.toLowerCase().includes("#fail")) {
    throw new ApiError("Máy chủ đang bận, chưa cập nhật được trạng thái. Thử lại sau.", 503);
  }
  const user = findUser(change.userId);
  user.status = change.status;
  const verb: Record<UserStatus, string> = { Active: "mở khoá", Inactive: "vô hiệu hoá", Locked: "tạm khoá", Banned: "cấm tài khoản" };
  logAction(session?.fullName ?? "Quản trị viên", verb[change.status], user.fullName);
  return { ...user };
}

export async function deleteUser(id: string, session: AdminSession | null): Promise<void> {
  await sleep(600);
  guardSelf(id, session);
  const index = users.findIndex((u) => u.id === id);
  if (index < 0) throw new ApiError("Không tìm thấy người dùng.", 404);
  const [removed] = users.splice(index, 1);
  logAction(session?.fullName ?? "Quản trị viên", "xoá tài khoản", removed.fullName);
}

/* ------------------------------------------------------ chef applications */

const chefApplications: ChefApplication[] = [
  {
    id: "ca_1",
    userId: "u_new_1",
    fullName: "Phan Gia Bảo",
    email: "giabao.chef@gmail.com",
    city: "TP. Hồ Chí Minh",
    specialties: ["Ẩm thực chay Việt", "Meal prep"],
    yearsExperience: 7,
    bio: "7 năm làm bếp nóng tại khách sạn 4 sao, 3 năm phụ trách thực đơn chay buffet sáng. Muốn hướng dẫn gia đình trẻ nấu chay nhanh trong tuần.",
    certificates: [
      { name: "Chứng chỉ Kỹ thuật chế biến món ăn — CĐ Kinh tế Kỹ thuật TP.HCM", fileUrl: "#" },
      { name: "Giấy xác nhận kiến thức an toàn thực phẩm (2026)", fileUrl: "#" },
    ],
    memberSince: daysAgo(60),
    postCount: 5,
    submittedAt: minutesAgo(5 * 60),
    status: "pending",
  },
  {
    id: "ca_2",
    userId: "u_new_2",
    fullName: "Lý Thanh Trúc",
    email: "thanhtruc.dietitian@gmail.com",
    city: "Cần Thơ",
    specialties: ["Dinh dưỡng lâm sàng", "Giảm cân lành mạnh"],
    yearsExperience: 4,
    bio: "Cử nhân dinh dưỡng, đang làm tại phòng khám dinh dưỡng tư nhân. Tư vấn ăn chay cho người tiền tiểu đường và mỡ máu cao.",
    certificates: [{ name: "Cử nhân Dinh dưỡng — ĐH Y Dược Cần Thơ", fileUrl: "#" }],
    memberSince: daysAgo(33),
    postCount: 2,
    submittedAt: minutesAgo(26 * 60),
    status: "pending",
  },
  {
    id: "ca_3",
    userId: "u_new_3",
    fullName: "Đỗ Hải Yến",
    email: "haiyen.mebe@gmail.com",
    city: "Hà Nội",
    specialties: ["Bếp chay cho bé"],
    yearsExperience: 3,
    bio: "Mẹ của hai bé ăn chay từ lúc ăn dặm, chia sẻ thực đơn trên nhóm Facebook 20.000 thành viên.",
    certificates: [{ name: "Khoá Dinh dưỡng nhi khoa cơ bản (online)", fileUrl: null }],
    memberSince: daysAgo(12),
    postCount: 1,
    submittedAt: minutesAgo(50 * 60),
    status: "pending",
  },
  {
    id: "ca_4",
    userId: "u_chef_lan",
    fullName: "Võ Thị Ngọc Lan",
    email: "ngoclan.anddam@gmail.com",
    city: "TP. Hồ Chí Minh",
    specialties: ["Bếp chay cho bé", "Dinh dưỡng lâm sàng"],
    yearsExperience: 8,
    bio: "Thực đơn ăn dặm thuần chay đủ sắt, kẽm, B12 cho bé từ 6 tháng.",
    certificates: [{ name: "Cử nhân Dinh dưỡng — ĐH Y Dược TP.HCM", fileUrl: "#" }],
    memberSince: daysAgo(140),
    postCount: 12,
    submittedAt: daysAgo(4),
    status: "approved",
    reviewedBy: "Lê Minh Quân",
    reviewedAt: minutesAgo(190),
    reviewNote: "Bằng cử nhân hợp lệ, đã gọi xác minh nơi làm việc.",
  },
  {
    id: "ca_5",
    userId: "u_chef_khoa",
    fullName: "Nguyễn Đăng Khoa",
    email: "khoa.fitvegan@gmail.com",
    city: "Đà Nẵng",
    specialties: ["Dinh dưỡng thể thao", "Meal prep"],
    yearsExperience: 6,
    bio: "HLV thể hình, chuyên thực đơn tăng cơ bằng đạm thực vật.",
    certificates: [
      { name: "Chứng chỉ Huấn luyện viên cá nhân (ISSA)", fileUrl: "#" },
      { name: "Sports Nutrition Specialist", fileUrl: "#" },
    ],
    memberSince: daysAgo(150),
    postCount: 17,
    submittedAt: daysAgo(24),
    status: "approved",
    reviewedBy: "Trần Thu Hằng",
    reviewedAt: daysAgo(22),
    reviewNote: "Chứng chỉ ISSA tra cứu được trên trang chính thức.",
  },
  {
    id: "ca_6",
    userId: "u_detox",
    fullName: "Detox Xanh Mỗi Ngày",
    email: "detoxxanh.vn@gmail.com",
    city: "Hà Nội",
    specialties: ["Thực dưỡng", "Giảm cân lành mạnh"],
    yearsExperience: 2,
    bio: "Chuyên các liệu trình detox nước ép giúp thải độc, giảm 5 kg trong 7 ngày.",
    certificates: [{ name: "Chứng nhận chuyên gia detox quốc tế", fileUrl: null }],
    memberSince: daysAgo(30),
    postCount: 8,
    submittedAt: daysAgo(9),
    status: "rejected",
    reviewedBy: "Trần Thu Hằng",
    reviewedAt: daysAgo(8),
    reviewNote: "Tài khoản bán sản phẩm, chứng chỉ không xác minh được và có bài sai lệch về sức khoẻ.",
  },
];

export async function listChefApplications(status: ChefApplicationStatus): Promise<ChefApplication[]> {
  await sleep(450);
  return chefApplications
    .filter((a) => a.status === status)
    .sort((a, b) => (status === "pending" ? a.submittedAt.localeCompare(b.submittedAt) : (b.reviewedAt ?? "").localeCompare(a.reviewedAt ?? "")));
}

export async function getChefApplicationCounts(): Promise<Record<ChefApplicationStatus, number>> {
  await sleep(200);
  return {
    pending: chefApplications.filter((a) => a.status === "pending").length,
    approved: chefApplications.filter((a) => a.status === "approved").length,
    rejected: chefApplications.filter((a) => a.status === "rejected").length,
  };
}

export async function reviewChefApplication(input: ChefReviewInput, session: AdminSession | null): Promise<ChefApplication> {
  await sleep(650);
  if (input.note.toLowerCase().includes("#fail")) {
    throw new ApiError("Máy chủ đang bận, chưa lưu được quyết định. Thử lại sau.", 503);
  }
  const app = chefApplications.find((a) => a.id === input.applicationId);
  if (!app) throw new ApiError("Hồ sơ không còn tồn tại.", 404);
  if (app.status !== "pending") throw new ApiError("Hồ sơ đã được người khác xử lý.", 409, "already_reviewed");
  app.status = input.decision;
  app.reviewNote = input.note;
  app.reviewedAt = new Date().toISOString();
  app.reviewedBy = session?.fullName ?? "Quản trị viên";
  const user = users.find((u) => u.id === app.userId);
  if (user && input.decision === "approved") {
    user.isVerifiedChef = true;
    // Approval grants the Chef role (admins keep theirs).
    if (user.role !== "Admin") user.role = "Chef";
  }
  logAction(app.reviewedBy, input.decision === "approved" ? "duyệt chuyên gia" : "từ chối hồ sơ chuyên gia", app.fullName);
  return { ...app };
}

/* ----------------------------------------------------------------- content */

const a = (id: string, fullName: string, isVerifiedChef = false) => ({ id, fullName, isVerifiedChef });

type ContentSeed = Omit<ContentItem, "status" | "mediaType" | "mediaUrl" | "restaurant"> &
  Partial<Pick<ContentItem, "status" | "mediaType" | "mediaUrl" | "restaurant">>;

const MEDIA_BASE = "https://res.cloudinary.com/veganlife";

/** Legacy rows have no status (→ Published); a `video` block means a video attachment, recipes otherwise get a photo. */
function withPostDefaults(seed: ContentSeed): ContentItem {
  const mediaType: MediaType = seed.mediaType ?? (seed.video ? "Video" : seed.kind === "recipe" ? "Image" : "Text");
  const derivedUrl =
    mediaType === "Video" ? `${MEDIA_BASE}/video/upload/v1/${seed.id}.mp4` : mediaType === "Image" ? `${MEDIA_BASE}/image/upload/v1/${seed.id}.jpg` : null;
  return {
    ...seed,
    status: seed.status ?? "Published",
    mediaType,
    mediaUrl: seed.mediaUrl !== undefined ? seed.mediaUrl : derivedUrl,
    restaurant: seed.restaurant ?? null,
  };
}

/** Restaurants tagged by posts ("Gắn quán"); same ids and names as mock_restaurants.ts, same posts as the mobile seeds (p_video_cha_lua, p_checkin_hanh_tam). */
const TAG_AN_LAC = { id: "rs_an_lac", name: "Quán Chay An Lạc", district: "Q.1", isCertified: true };
const TAG_HANH_TAM = { id: "rs_hanh_tam", name: "Bún Riêu Chay Hạnh Tâm", district: "Q. Bình Thạnh", isCertified: true };

const CONTENT_SEED: ContentSeed[] = [
  { id: "p_pin_rules", kind: "discussion", title: "Nội quy cộng đồng & cách báo cáo bài sai thông tin", excerpt: "Chia sẻ công thức, kinh nghiệm và câu hỏi về ăn chay — nhớ ghi nguồn khi nói về sức khoẻ…", author: a("u_admin", "Ban quản trị VeganLife"), createdAt: daysAgo(12), likeCount: 312, commentCount: 18, reportCount: 0, hidden: false, pinned: true },
  { id: "p_video_cha_lua", kind: "recipe", title: "Chả lụa chay từ đậu hũ ky — không cần máy xay", excerpt: "Công thức mình bán ở quán 6 năm nay, chia sẻ cả nhà…", author: a("u_chef_tam", "Lê Quang Tâm", true), createdAt: minutesAgo(120), likeCount: 842, commentCount: 63, reportCount: 0, hidden: false, pinned: false, video: { durationSeconds: 724, aiStatus: "ready" }, restaurant: TAG_AN_LAC },
  { id: "p_detox", kind: "discussion", title: "Uống nước ép cần tây 7 ngày, mình đã ngưng thuốc tiểu đường!", excerpt: "Bác sĩ bảo phải uống thuốc suốt đời nhưng nước ép cần tây đã chữa khỏi cho mình…", author: a("u_detox", "Detox Xanh Mỗi Ngày"), createdAt: minutesAgo(200), likeCount: 41, commentCount: 37, reportCount: 9, hidden: false, pinned: false },
  { id: "p_bun_rieu", kind: "recipe", title: "Bún riêu chay cà chua đậu hũ — nước dùng ngọt từ củ quả", excerpt: "Nguyên liệu (4 người): 6 quả cà chua, 2 bìa đậu hũ, 300 g nấm rơm…", author: a("u_hoang_nam", "Hoàng Nam"), createdAt: minutesAgo(300), likeCount: 214, commentCount: 27, reportCount: 0, hidden: false, pinned: false },
  { id: "p_checkin_hanh_tam", kind: "discussion", title: "Có ai ăn thử bún riêu chay ở Hạnh Tâm chưa?", excerpt: "Trưa nay mình ghé quán, tô 35k đầy đặn, nước dùng ngọt từ rau củ, mắm tôm chay để riêng…", author: a("u_ngoc_tram", "Ngọc Trâm"), createdAt: minutesAgo(38 * 60), likeCount: 41, commentCount: 9, reportCount: 0, hidden: false, pinned: false, restaurant: TAG_HANH_TAM },
  { id: "p_video_lau", kind: "recipe", title: "Lẩu nấm chay 15 phút cho ngày mưa", excerpt: "Nước lẩu từ nấm đông cô và củ cải…", author: a("u_thao_vy", "Thảo Vy"), createdAt: minutesAgo(25), likeCount: 3, commentCount: 0, reportCount: 0, hidden: false, pinned: false, video: { durationSeconds: 412, aiStatus: "extracting" } },
  { id: "p_b12", kind: "discussion", title: "Mới ăn chay 3 tuần, nên bổ sung B12 thế nào?", excerpt: "Mình ăn chay trường được 3 tuần, hay bị mệt buổi chiều…", author: a("u_ngoc_tram", "Ngọc Trâm"), createdAt: minutesAgo(480), likeCount: 46, commentCount: 31, reportCount: 0, hidden: false, pinned: false },
  { id: "p_spam", kind: "discussion", title: "Trà giảm cân thảo mộc — giảm 8 kg/tháng, inbox Zalo 09xx", excerpt: "Cam kết hoàn tiền, 100% thiên nhiên, liên hệ ngay…", author: a("u_spam_1", "thuocgiamcan.official"), createdAt: daysAgo(1), likeCount: 2, commentCount: 5, reportCount: 14, hidden: true, pinned: false },
  { id: "p_video_meal_prep", kind: "recipe", title: "Meal prep 5 hộp cơm chay cho cả tuần với 150.000đ", excerpt: "Đi chợ một lần, nấu 90 phút…", author: a("u_bep_may", "Bếp Chay Nhà Mây"), createdAt: daysAgo(1), likeCount: 1290, commentCount: 88, reportCount: 1, hidden: false, pinned: false, video: { durationSeconds: 572, aiStatus: "ready" } },
  { id: "p_flan", kind: "recipe", title: "Bánh flan chay mềm mịn (dùng trứng gà ta cho béo)", excerpt: "Mình thêm 2 lòng đỏ trứng gà ta để bánh mịn hơn…", author: a("u_gen_3", "Hồ Ngọc Linh"), createdAt: daysAgo(2), likeCount: 19, commentCount: 12, reportCount: 3, hidden: false, pinned: false, status: "Pending", aiFlag: { reason: "Công thức gắn nhãn chay nhưng dùng lòng đỏ trứng gà.", score: 0.88, category: "not_vegan", createdAt: daysAgo(2) } },
  { id: "p_iq", kind: "discussion", title: "Ăn chay lâu năm có làm giảm trí nhớ không?", excerpt: "Đọc trên mạng thấy bảo ăn chay thiếu B12 dễ giảm trí nhớ…", author: a("u_gen_8", "Vũ Hữu Phúc"), createdAt: daysAgo(2), likeCount: 33, commentCount: 40, reportCount: 4, hidden: false, pinned: false },
  { id: "p_video_sua_hat", kind: "recipe", title: "Sữa hạt điều yến mạch 5 phút, không cần máy làm sữa", excerpt: "Bữa sáng 5 phút cho ngày bận rộn.", author: a("u_thao_vy", "Thảo Vy"), createdAt: daysAgo(2), likeCount: 376, commentCount: 21, reportCount: 0, hidden: false, pinned: false, video: { durationSeconds: 251, aiStatus: "ready" } },
  { id: "p_dam_thuc_vat", kind: "discussion", title: "5 nguồn đạm thực vật rẻ mà chợ nào cũng có", excerpt: "Đậu hũ, đậu xanh nguyên vỏ, đậu phộng, mè đen và tàu hũ ky…", author: a("u_thu_ha", "ThS. DD Phạm Thu Hà", true), createdAt: daysAgo(3), likeCount: 521, commentCount: 44, reportCount: 0, hidden: false, pinned: false },
  { id: "p_me_banh_xeo", kind: "recipe", title: "Bánh xèo chay nhân nấm — video đầu tay của mình", excerpt: "Lần đầu quay video nấu ăn, mọi người góp ý giúp mình nha!", author: a("u_me", "Minh Anh"), createdAt: daysAgo(5), likeCount: 12, commentCount: 3, reportCount: 0, hidden: false, pinned: false, video: { durationSeconds: 486, aiStatus: "failed", failureReason: "Âm thanh quá nhỏ để nhận dạng giọng nói." } },
  { id: "p_dau_hu_sot_ca", kind: "recipe", title: "Đậu hũ sốt cà chua kiểu Bắc — 15 phút", excerpt: "Rán vàng 2 bìa đậu, xào 3 quả cà chua với hành lá…", author: a("u_bep_may", "Bếp Chay Nhà Mây"), createdAt: daysAgo(3), likeCount: 98, commentCount: 6, reportCount: 0, hidden: false, pinned: false },
  // Held by the AI pre-screen (ids and titles mirror the mobile seeds).
  { id: "p_me_pending_celery", kind: "discussion", title: "Nước ép cần tây có chữa khỏi tiểu đường không?", excerpt: "Mẹ mình đọc trên mạng thấy uống nước ép cần tây mỗi sáng chữa khỏi tiểu đường, có ai thử chưa ạ?", author: a("u_me", "Minh Anh"), createdAt: minutesAgo(95), likeCount: 0, commentCount: 0, reportCount: 0, hidden: false, pinned: false, status: "Pending", aiFlag: { reason: "Có cụm “chữa khỏi tiểu đường” — dễ lan truyền thông tin sức khoẻ sai lệch nếu không có nguồn.", score: 0.82, category: "health_misinformation", createdAt: minutesAgo(95) } },
  { id: "p_detox_tea", kind: "discussion", title: "Trà detox thảo mộc giảm mỡ bụng — inbox Zalo nhận ưu đãi", excerpt: "Cam kết hoàn tiền nếu không giảm 5 kg trong 2 tuần, ship toàn quốc…", author: a("u_detox", "Detox Xanh Mỗi Ngày"), createdAt: minutesAgo(40), likeCount: 0, commentCount: 0, reportCount: 0, hidden: false, pinned: false, status: "Pending", aiFlag: { reason: "Quảng cáo bán hàng kèm số Zalo và cam kết giảm cân.", score: 0.94, category: "spam_promo", createdAt: minutesAgo(40) } },
  { id: "p_me_rejected_detox", kind: "discussion", title: "Trà detox giảm cân thần tốc 7 ngày", excerpt: "Công thức trà detox mình uống 7 ngày giảm 3 kg, mọi người thử nha…", author: a("u_me", "Minh Anh"), createdAt: daysAgo(4), likeCount: 0, commentCount: 0, reportCount: 0, hidden: false, pinned: false, status: "Rejected", aiFlag: { reason: "Khẳng định hiệu quả giảm cân nhanh chưa được kiểm chứng.", score: 0.79, category: "health_misinformation", createdAt: daysAgo(4) }, decision: { decision: "Reject", note: "Bài khẳng định hiệu quả giảm cân chưa được kiểm chứng. Vui lòng bỏ cam kết và ghi nguồn rồi gửi lại.", adminName: "Lê Minh Quân", decidedAt: minutesAgo(4 * 24 * 60 - 90) } },
];

const content: ContentItem[] = CONTENT_SEED.map(withPostDefaults);

export async function listContent(query: ContentQuery): Promise<ContentItem[]> {
  await sleep(450);
  const q = SEARCH_FOLD(query.search.trim());
  return content
    .filter((c) => query.kind === "all" || c.kind === query.kind)
    .filter((c) => !query.hasVideo || c.mediaType === "Video")
    .filter((c) => !query.authorId || c.author.id === query.authorId)
    .filter((c) => {
      switch (query.view) {
        case "pending":
          return c.status === "Pending";
        case "rejected":
          return c.status === "Rejected";
        case "reported":
          return c.status === "Published" && c.reportCount > 0 && !c.hidden;
        case "hidden":
          return c.hidden;
        case "pinned":
          return c.pinned;
        default:
          return true;
      }
    })
    .filter((c) => !q || SEARCH_FOLD(`${c.title} ${c.author.fullName} ${c.restaurant?.name ?? ""}`).includes(q))
    .sort((x, y) => {
      if (query.view === "reported") return y.reportCount - x.reportCount;
      // Oldest flag first, like the moderation queue.
      if (query.view === "pending") return (x.aiFlag?.createdAt ?? x.createdAt).localeCompare(y.aiFlag?.createdAt ?? y.createdAt);
      return y.createdAt.localeCompare(x.createdAt);
    })
    .map((c) => ({ ...c, restaurant: c.restaurant && { ...c.restaurant } }));
}

export function countPendingPosts(): number {
  return content.filter((c) => c.status === "Pending").length;
}

/** POST /admin/posts/{id}/review → writes moderation_decisions (one row per post). */
export async function reviewPost(input: PostReviewInput, session: AdminSession | null): Promise<ContentItem> {
  await sleep(600);
  const note = input.note.trim();
  if (input.decision === "Reject" && note.length < MIN_AUDIT_NOTE_LENGTH) {
    throw new ApiError(`Ghi chú từ chối cần ít nhất ${MIN_AUDIT_NOTE_LENGTH} ký tự.`, 400, "note_too_short");
  }
  if (note.toLowerCase().includes("#fail")) {
    throw new ApiError("Máy chủ đang bận, chưa lưu được quyết định. Thử lại sau.", 503, "unavailable");
  }
  const item = content.find((c) => c.id === input.postId);
  if (!item) throw new ApiError("Bài viết không còn tồn tại.", 404);
  if (item.status !== "Pending") throw new ApiError("Bài này đã được người khác xử lý.", 409, "already_reviewed");

  const actor = session?.fullName ?? "Quản trị viên";
  const decidedAt = new Date().toISOString();
  item.status = input.decision === "Approve" ? "Published" : "Rejected";
  item.decision = { decision: input.decision, note: note || null, adminName: actor, decidedAt };
  if (item.aiFlag) {
    recordDecisionSample({
      category: item.aiFlag.category,
      upheld: input.decision === "Reject",
      minutesToDecide: Math.max(1, Math.round((Date.now() - new Date(item.aiFlag.createdAt).getTime()) / 60_000)),
      decidedAt,
    });
  }
  logAction(actor, input.decision === "Approve" ? "duyệt bài chờ" : "từ chối bài", item.title);
  return { ...item };
}

export async function applyContentAction(id: string, action: ContentAction, session: AdminSession | null): Promise<ContentItem | null> {
  await sleep(500);
  const index = content.findIndex((c) => c.id === id);
  if (index < 0) throw new ApiError("Bài viết không còn tồn tại.", 404);
  const item = content[index];
  const actor = session?.fullName ?? "Quản trị viên";
  switch (action) {
    case "hide":
      item.hidden = true;
      item.pinned = false;
      logAction(actor, "ẩn bài viết", item.title);
      break;
    case "unhide":
      item.hidden = false;
      logAction(actor, "hiện lại bài viết", item.title);
      break;
    case "pin":
      if (item.status !== "Published") {
        throw new ApiError("Chỉ ghim được bài đã đăng.", 409, "not_published");
      }
      if (content.filter((c) => c.pinned).length >= 3) {
        throw new ApiError("Chỉ ghim tối đa 3 bài. Bỏ ghim một bài trước.", 409, "pin_limit");
      }
      item.pinned = true;
      logAction(actor, "ghim bài viết", item.title);
      break;
    case "unpin":
      item.pinned = false;
      logAction(actor, "bỏ ghim bài viết", item.title);
      break;
    case "retry_ai":
      if (item.video) item.video = { ...item.video, aiStatus: "queued", failureReason: undefined };
      logAction(actor, "chạy lại AI cho video", item.title);
      break;
    case "delete":
      content.splice(index, 1);
      // The post's comments go with it.
      for (let i = comments.length - 1; i >= 0; i--) if (comments[i].postId === id) comments.splice(i, 1);
      logAction(actor, "xoá bài viết", item.title);
      return null;
  }
  return { ...item };
}

/* ---------------------------------------------------------------- comments */

type StoredComment = Omit<AdminComment, "postTitle" | "replyTo" | "replyCount">;

type CommentSeed = [id: string, postId: string, authorId: string, author: string, text: string, ageMin: number, reports?: number, hidden?: boolean, editedMinAgo?: number];

const H = 60;
const D = 24 * H;

const COMMENT_SEED: CommentSeed[] = [
  ["c_01", "p_video_cha_lua", "u_thao_vy", "Thảo Vy", "Chả lụa nhìn mịn quá anh ơi, đậu hũ ky mua loại khô hay loại tươi ạ?", 100],
  ["c_02", "p_video_cha_lua", "u_chef_tam", "Lê Quang Tâm", "Loại tươi nha em, loại khô thì ngâm nước ấm 15 phút rồi vắt thật ráo.", 88],
  ["c_03", "p_video_cha_lua", "u_me", "Minh Anh", "Mình làm theo video, cuộn chặt tay hơn là không bị bở. Cảm ơn anh Tâm!", 50, 0, false, 32],
  ["c_04", "p_bun_rieu", "u_ngoc_tram", "Ngọc Trâm", "Nước dùng ngọt thanh thật, mình thêm chút củ cải trắng cho ngọt hơn.", 3 * H + 20],
  ["c_05", "p_bun_rieu", "u_spam_1", "thuocgiamcan.official", "Ăn chay mà muốn giảm 8 kg/tháng thì inbox Zalo 09xx nhé, trà thảo mộc 100% thiên nhiên!", 3 * H + 10, 6],
  ["c_06", "p_b12", "u_thu_ha", "ThS. DD Phạm Thu Hà", "Em nên xét nghiệm B12 trước rồi bổ sung theo chỉ định. Mệt buổi chiều cũng có thể do thiếu sắt.", 7 * H],
  ["c_07", "p_b12", "u_me", "Minh Anh", "Mình dùng sữa hạt có bổ sung B12, uống mỗi sáng thấy đỡ mệt hơn hẳn.", 6 * H + 40],
  ["c_08", "p_b12", "u_detox", "Detox Xanh Mỗi Ngày", "Không cần B12 đâu, uống nước ép cần tây là đủ chất. Liên hệ zalo để được tư vấn liệu trình.", 6 * H + 15, 4, true],
  ["c_09", "p_detox", "u_thu_ha", "ThS. DD Phạm Thu Hà", "Tự ý ngưng thuốc tiểu đường rất nguy hiểm. Bạn hãy trao đổi với bác sĩ điều trị trước nhé.", 3 * H],
  ["c_10", "p_detox", "u_hoang_nam", "Hoàng Nam", "Bài này nên được gỡ, nhiều người lớn tuổi đọc sẽ làm theo mất.", 2 * H + 45],
  ["c_11", "p_iq", "u_thao_vy", "Thảo Vy", "Mình ăn chay 5 năm, bổ sung B12 đều thì trí nhớ vẫn bình thường nha.", 2 * D],
  ["c_12", "p_iq", "u_duc_huy", "Đức Huy", "Có nghiên cứu nào cụ thể không bạn? Mình cũng đang lo chuyện này.", 2 * D - 3 * H],
  ["c_13", "p_video_meal_prep", "u_me", "Minh Anh", "150k cho 5 hộp thì rẻ thật, chị cho mình xin danh sách đi chợ với.", D + 2 * H],
  ["c_14", "p_video_meal_prep", "u_bep_may", "Bếp Chay Nhà Mây", "Danh sách mình để ở phần mô tả video nha bạn!", D + H],
  ["c_15", "p_video_meal_prep", "u_spam_1", "thuocgiamcan.official", "Nhận làm meal prep giảm cân cấp tốc, cam kết hoàn tiền, inbox zalo 0909xxx.", D + 30, 9, true],
  ["c_16", "p_flan", "u_hoang_nam", "Hoàng Nam", "Có trứng thì không còn là món chay rồi bạn ơi.", 2 * D - H],
  ["c_17", "p_flan", "u_ngoc_tram", "Ngọc Trâm", "Thay trứng bằng bột bắp và sữa đậu nành vẫn mịn nha.", 2 * D - 2 * H],
  ["c_18", "p_video_sua_hat", "u_chef_khoa", "Nguyễn Đăng Khoa", "Thêm 1 muỗng hạt chia là đủ đạm cho bữa sáng trước giờ tập.", 2 * D - 5 * H],
  ["c_19", "p_video_sua_hat", "u_detox", "Detox Xanh Mỗi Ngày", "Mua máy làm sữa hạt giá sỉ, inbox Zalo shop Detox Xanh để nhận mã giảm 50%.", 2 * D - 6 * H, 3],
  ["c_20", "p_dam_thuc_vat", "u_me", "Minh Anh", "Tàu hũ ky chiên giòn chấm tương là chân ái!", 3 * D - 2 * H],
  ["c_21", "p_dam_thuc_vat", "u_chef_chau", "Tôn Nữ Minh Châu", "Mè đen rang xay rắc lên cơm cũng là cách bổ sung canxi rất Huế.", 3 * D - 4 * H],
  ["c_22", "p_me_banh_xeo", "u_chef_tam", "Lê Quang Tâm", "Bột pha thêm chút nước cốt dừa, đổ chảo thật nóng thì bánh giòn lâu hơn em nhé.", 4 * D],
  ["c_23", "p_me_banh_xeo", "u_thao_vy", "Thảo Vy", "Video đầu tay mà quay đẹp ghê!", 4 * D + 3 * H],
  ["c_24", "p_dau_hu_sot_ca", "u_duc_huy", "Đức Huy", "Món cứu đói cuối tháng của sinh viên đây rồi.", 3 * D - H],
  ["c_25", "p_pin_rules", "u_hoang_nam", "Hoàng Nam", "Đề nghị thêm mục báo cáo riêng cho bình luận spam bán hàng.", 10 * D],
  ["c_26", "p_video_cha_lua", "u_me", "Minh Anh", "@Lê Quang Tâm Dạ em cảm ơn anh, mai em thử loại tươi.", 80],
  ["c_27", "p_b12", "u_ngoc_tram", "Ngọc Trâm", "@ThS. DD Phạm Thu Hà Dạ em sẽ đi xét nghiệm tuần này, cảm ơn chị.", 6 * H + 50],
];

/** Replies (one level deep): reply id → top-level comment id. A reply to a reply keeps the same parent and an "@Tên " prefix. */
const PARENT: Record<string, string> = {
  c_02: "c_01",
  c_26: "c_01",
  c_07: "c_06",
  c_27: "c_06",
  c_12: "c_11",
  c_14: "c_13",
  c_17: "c_16",
  c_10: "c_09",
};

const comments: StoredComment[] = COMMENT_SEED.map(([id, postId, authorId, fullName, text, ageMin, reports = 0, hidden = false, editedMinAgo]) => ({
  id,
  postId,
  parentId: PARENT[id] ?? null,
  author: { id: authorId, fullName },
  content: text,
  status: hidden ? "Hidden" : "Visible",
  reportCount: reports,
  createdAt: minutesAgo(ageMin),
  updatedAt: editedMinAgo === undefined ? null : minutesAgo(editedMinAgo),
}));

function toAdminComment(c: StoredComment): AdminComment {
  const parent = c.parentId ? comments.find((x) => x.id === c.parentId) : undefined;
  return {
    ...c,
    author: { ...c.author },
    postTitle: content.find((p) => p.id === c.postId)?.title ?? "(Bài viết đã bị xoá)",
    replyTo: parent ? { id: parent.id, authorName: parent.author.fullName } : null,
    replyCount: c.parentId ? 0 : comments.filter((x) => x.parentId === c.id).length,
  };
}

const commentExcerpt = (c: StoredComment) => `${c.author.fullName}: “${c.content.length > 48 ? `${c.content.slice(0, 48)}…` : c.content}”`;

export async function listComments(query: CommentQuery): Promise<AdminComment[]> {
  await sleep(400);
  const q = SEARCH_FOLD(query.search.trim());
  return comments
    .filter((c) => !query.authorId || c.author.id === query.authorId)
    .filter((c) => !query.postId || c.postId === query.postId)
    .filter((c) => {
      switch (query.view) {
        case "reported":
          return c.reportCount > 0 && c.status === "Visible";
        case "hidden":
          return c.status === "Hidden";
        default:
          return true;
      }
    })
    .map(toAdminComment)
    .filter((c) => !q || SEARCH_FOLD(`${c.content} ${c.author.fullName} ${c.postTitle}`).includes(q))
    .sort((x, y) => (query.view === "reported" ? y.reportCount - x.reportCount : y.createdAt.localeCompare(x.createdAt)));
}

/** POST /admin/comments/{id}/actions { action: "hide" | "unhide" } */
export async function applyCommentAction(id: string, action: "hide" | "unhide", session: AdminSession | null): Promise<AdminComment> {
  await sleep(450);
  const comment = comments.find((c) => c.id === id);
  if (!comment) throw new ApiError("Bình luận không còn tồn tại.", 404);
  comment.status = action === "hide" ? "Hidden" : "Visible";
  logAction(session?.fullName ?? "Quản trị viên", action === "hide" ? "ẩn bình luận" : "hiện lại bình luận", commentExcerpt(comment));
  return toAdminComment(comment);
}

/** DELETE /admin/comments/{id} { reason? } — the reason is sent to the author; a top-level comment takes its replies with it. */
export async function deleteComment(id: string, reason: string | undefined, session: AdminSession | null): Promise<void> {
  await sleep(550);
  if (reason?.toLowerCase().includes("#fail")) {
    throw new ApiError("Máy chủ đang bận, chưa xoá được bình luận. Thử lại sau.", 503, "unavailable");
  }
  const removed = comments.find((c) => c.id === id);
  if (!removed) throw new ApiError("Bình luận không còn tồn tại.", 404);
  const gone = new Set([id, ...comments.filter((c) => c.parentId === id).map((c) => c.id)]);
  for (let i = comments.length - 1; i >= 0; i--) if (gone.has(comments[i].id)) comments.splice(i, 1);
  const post = content.find((p) => p.id === removed.postId);
  // commentCount includes replies.
  if (post) post.commentCount = Math.max(0, post.commentCount - gone.size);
  logAction(
    session?.fullName ?? "Quản trị viên",
    gone.size > 1 ? `xoá bình luận và ${gone.size - 1} phản hồi` : "xoá bình luận",
    commentExcerpt(removed),
  );
}

/* ----------------------------------------------------------------- catalog */

let catalogSeq = 100;
const c = (kind: CatalogKind, code: string, label: string, usageCount: number, extra: Partial<CatalogItem> = {}): CatalogItem => ({
  id: `cat_${catalogSeq++}`,
  kind,
  code,
  label,
  active: true,
  usageCount,
  ...extra,
});

const catalog: CatalogItem[] = [
  c("category", "main", "Món chính", 1240),
  c("category", "breakfast", "Ăn sáng", 610),
  c("category", "soup_hotpot", "Canh & lẩu", 388),
  c("category", "snack", "Ăn vặt", 205),
  c("category", "drink", "Đồ uống", 176),
  c("category", "dessert", "Tráng miệng", 142),
  c("category", "party", "Tiệc chay", 0, { active: false }),
  c("diet_tag", "quick", "Nhanh gọn", 820),
  c("diet_tag", "high_protein", "Giàu đạm", 760),
  c("diet_tag", "high_fiber", "Giàu chất xơ", 540),
  c("diet_tag", "low_sodium", "Ít muối", 233),
  c("diet_tag", "whole_food", "Thực phẩm nguyên chất", 410),
  c("diet_tag", "seasonal", "Đang mùa", 96),
  c("diet_tag", "gluten_free", "Không gluten", 188),
  c("allergen", "peanut", "Đậu phộng", 312, { cvLabel: "peanut" }),
  c("allergen", "tree_nut", "Hạt cây (điều, hạnh nhân…)", 268, { cvLabel: "cashew" }),
  c("allergen", "soy", "Đậu nành", 1105, { cvLabel: "tofu" }),
  c("allergen", "gluten", "Gluten", 640, { cvLabel: "wheat_flour" }),
  c("allergen", "sesame", "Mè", 290, { cvLabel: "sesame" }),
  c("allergen", "mustard", "Mù tạt", 22, { cvLabel: "mustard" }),
  c("allergen", "celery", "Cần tây", 61, { cvLabel: "celery" }),
  c("specialty", "am_thuc_chay_viet", "Ẩm thực chay Việt", 14),
  c("specialty", "dinh_duong_lam_sang", "Dinh dưỡng lâm sàng", 9),
  c("specialty", "giam_can", "Giảm cân lành mạnh", 7),
  c("specialty", "chay_hue", "Ẩm thực chay Huế", 3),
  c("specialty", "the_thao", "Dinh dưỡng thể thao", 5),
  c("specialty", "bep_cho_be", "Bếp chay cho bé", 4),
  c("specialty", "thuc_duong", "Thực dưỡng", 6),
  c("specialty", "meal_prep", "Meal prep", 8),
];

export async function listCatalog(kind: CatalogKind): Promise<CatalogItem[]> {
  await sleep(350);
  return catalog.filter((i) => i.kind === kind).map((i) => ({ ...i }));
}

export async function createCatalogItem(input: CatalogInput): Promise<CatalogItem> {
  await sleep(450);
  if (catalog.some((i) => i.kind === input.kind && i.code === input.code)) {
    throw new ApiError(`Mã "${input.code}" đã tồn tại trong nhóm này.`, 409, "duplicate_code");
  }
  const item = c(input.kind, input.code, input.label, 0, input.cvLabel ? { cvLabel: input.cvLabel } : {});
  catalog.push(item);
  return { ...item };
}

export async function updateCatalogItem(id: string, patch: Partial<Pick<CatalogItem, "label" | "active" | "cvLabel">>): Promise<CatalogItem> {
  await sleep(350);
  const item = catalog.find((i) => i.id === id);
  if (!item) throw new ApiError("Mục không còn tồn tại.", 404);
  Object.assign(item, patch);
  return { ...item };
}

export async function deleteCatalogItem(id: string): Promise<void> {
  await sleep(400);
  const index = catalog.findIndex((i) => i.id === id);
  if (index < 0) throw new ApiError("Mục không còn tồn tại.", 404);
  if (catalog[index].usageCount > 0) {
    throw new ApiError("Mục đang được sử dụng — hãy tắt thay vì xoá.", 409, "in_use");
  }
  catalog.splice(index, 1);
}

/* ---------------------------------------------------------------- overview */

const SIGNUPS = [38, 42, 35, 51, 47, 60, 72, 55, 49, 58, 63, 71, 88, 64];

export async function getOverview(): Promise<OverviewStats> {
  await sleep(500);
  const flags = await getFlagCounts();
  const published = content.filter((x) => x.status === "Published");
  return {
    totalUsers: 12486 + users.length,
    newUsers7d: SIGNUPS.slice(-7).reduce((s, n) => s + n, 0),
    newUsersDelta: 0.18,
    activeUsers24h: 3184,
    activeDelta: 0.06,
    posts24h: 214,
    postsDelta: -0.04,
    aiQueries24h: 8930,
    aiQueriesDelta: 0.12,
    pending: {
      aiFlags: flags.pending,
      chefApplications: chefApplications.filter((x) => x.status === "pending").length,
      reportedContent: content.filter((x) => x.status === "Published" && x.reportCount > 0 && !x.hidden).length,
      failedVideos: content.filter((x) => x.video?.aiStatus === "failed").length,
      pendingPosts: countPendingPosts(),
    },
    signupsDaily: SIGNUPS.map((count, i) => ({ date: daysAgo(SIGNUPS.length - 1 - i), count })),
    contentMix: [
      { kind: "recipe", count: published.filter((x) => x.kind === "recipe").length * 312 },
      { kind: "discussion", count: published.filter((x) => x.kind === "discussion").length * 241 },
    ],
    recentActions: audit.slice(0, 6),
  };
}

/* -------------------------------------------------------------------- auth */

export async function login(email: string, password: string): Promise<AdminSession> {
  await sleep(700);
  const normalized = email.trim().toLowerCase();
  const user = users.find((u) => u.email.toLowerCase() === normalized);
  if (normalized === MOCK_ADMIN.email && password === MOCK_ADMIN.password) {
    return { userId: MOCK_ADMIN.id, email: MOCK_ADMIN.email, fullName: MOCK_ADMIN.fullName, accessToken: `mock.jwt.${Date.now()}` };
  }
  if (user && user.role !== "Admin" && password.length >= 6) {
    throw new ApiError(
      "Tài khoản này không có quyền quản trị. Người dùng vui lòng dùng ứng dụng VeganLife trên điện thoại.",
      403,
      "not_admin",
    );
  }
  throw new ApiError("Email hoặc mật khẩu không đúng.", 401, "invalid_credentials");
}
