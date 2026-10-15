// src/lib/mock_admin.ts
// In-memory mock backend for the admin console (users, chef applications,
// content, catalog, overview). Mirrors the mobile app's mock data so the
// same people and posts appear on both sides.
import type {
  AdminSession,
  AdminUser,
  CatalogInput,
  CatalogItem,
  CatalogKind,
  ChefApplication,
  ChefApplicationStatus,
  ChefReviewInput,
  ContentAction,
  ContentItem,
  ContentQuery,
  OverviewStats,
  UserQuery,
  UserRole,
  UserStatus,
  UserStatusChange,
} from "@/types/admin";

import { ApiError } from "./api_error";
import { getFlagCounts, sleep } from "./mock_data";

const minutesAgo = (m: number) => new Date(Date.now() - m * 60_000).toISOString();
const daysAgo = (d: number) => minutesAgo(d * 24 * 60);

export const MOCK_ADMIN = { id: "u_admin", email: "admin@veganlife.vn", password: "admin123", fullName: "Trần Thu Hằng" };

/* ------------------------------------------------------------------- audit */

const audit: OverviewStats["recentActions"] = [
  { id: "a3", at: minutesAgo(35), actor: "Trần Thu Hằng", action: "ẩn bài viết", target: "Trà giảm cân thảo mộc — inbox Zalo" },
  { id: "a2", at: minutesAgo(190), actor: "Lê Minh Quân", action: "duyệt chuyên gia", target: "Võ Thị Ngọc Lan" },
  { id: "a1", at: daysAgo(1), actor: "Trần Thu Hằng", action: "cấm tài khoản", target: "thuocgiamcan.official" },
];

function logAction(actor: string, action: string, target: string) {
  audit.unshift({ id: `a${Date.now()}`, at: new Date().toISOString(), actor, action, target });
  audit.splice(12);
}

/* ------------------------------------------------------------------- users */

type Seed = [id: string, fullName: string, email: string, role: UserRole, status: UserStatus, chef: boolean, posts: number, reports: number, joinedDaysAgo: number];

const SEED_USERS: Seed[] = [
  ["u_admin", "Trần Thu Hằng", "admin@veganlife.vn", "Admin", "Active", false, 3, 0, 210],
  ["u_admin_2", "Lê Minh Quân", "quan.le@veganlife.vn", "Admin", "Active", false, 0, 0, 180],
  ["u_me", "Minh Anh", "minhanh.nguyen@gmail.com", "Member", "Active", false, 2, 0, 104],
  ["u_chef_tam", "Lê Quang Tâm", "tam.chefchay@gmail.com", "Member", "Active", true, 48, 0, 320],
  ["u_thu_ha", "ThS. DD Phạm Thu Hà", "thuha.dinhduong@gmail.com", "Member", "Active", true, 31, 0, 290],
  ["u_chef_chau", "Tôn Nữ Minh Châu", "minhchau.hue@gmail.com", "Member", "Active", true, 22, 0, 260],
  ["u_chef_khoa", "Nguyễn Đăng Khoa", "khoa.fitvegan@gmail.com", "Member", "Active", true, 17, 0, 150],
  ["u_chef_lan", "Võ Thị Ngọc Lan", "ngoclan.anddam@gmail.com", "Member", "Active", true, 12, 0, 140],
  ["u_chef_minh", "Trần Quốc Minh", "quocminh.thucduong@gmail.com", "Member", "Active", true, 9, 0, 230],
  ["u_bep_may", "Bếp Chay Nhà Mây", "bepchaynhamay@gmail.com", "Member", "Active", false, 64, 1, 300],
  ["u_thao_vy", "Thảo Vy", "thaovy.nguyen@gmail.com", "Member", "Active", false, 27, 0, 200],
  ["u_hoang_nam", "Hoàng Nam", "hoangnam.dev@gmail.com", "Member", "Active", false, 15, 0, 120],
  ["u_ngoc_tram", "Ngọc Trâm", "ngoctram.k17@gmail.com", "Member", "Active", false, 4, 0, 21],
  ["u_duc_huy", "Đức Huy", "duchuy.q9@gmail.com", "Member", "Active", false, 6, 0, 45],
  ["u_spam_1", "thuocgiamcan.official", "zalo.giamcan247@gmail.com", "Member", "Banned", false, 11, 23, 9],
  ["u_detox", "Detox Xanh Mỗi Ngày", "detoxxanh.vn@gmail.com", "Member", "Locked", false, 8, 9, 30],
  ["u_new_1", "Phan Gia Bảo", "giabao.chef@gmail.com", "Member", "Active", false, 5, 0, 60],
  ["u_new_2", "Lý Thanh Trúc", "thanhtruc.dietitian@gmail.com", "Member", "Active", false, 2, 0, 33],
  ["u_new_3", "Đỗ Hải Yến", "haiyen.mebe@gmail.com", "Member", "Active", false, 1, 0, 12],
  ["u_pending", "Quách Bảo Ngân", "baongan.q@gmail.com", "Member", "Inactive", false, 0, 0, 1],
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
      role: "Member",
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

export async function updateUserRole(id: string, role: UserRole, session: AdminSession | null): Promise<AdminUser> {
  await sleep(500);
  guardSelf(id, session);
  const user = findUser(id);
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
  if (user && input.decision === "approved") user.isVerifiedChef = true;
  logAction(app.reviewedBy, input.decision === "approved" ? "duyệt chuyên gia" : "từ chối hồ sơ chuyên gia", app.fullName);
  return { ...app };
}

/* ----------------------------------------------------------------- content */

const a = (id: string, fullName: string, isVerifiedChef = false) => ({ id, fullName, isVerifiedChef });

const content: ContentItem[] = [
  { id: "p_pin_rules", kind: "discussion", title: "Nội quy cộng đồng & cách báo cáo bài sai thông tin", excerpt: "Chia sẻ công thức, kinh nghiệm và câu hỏi về ăn chay — nhớ ghi nguồn khi nói về sức khoẻ…", author: a("u_admin", "Ban quản trị VeganLife"), createdAt: daysAgo(12), likeCount: 312, commentCount: 18, reportCount: 0, hidden: false, pinned: true },
  { id: "p_video_cha_lua", kind: "video", title: "Chả lụa chay từ đậu hũ ky — không cần máy xay", excerpt: "Công thức mình bán ở quán 6 năm nay, chia sẻ cả nhà…", author: a("u_chef_tam", "Lê Quang Tâm", true), createdAt: minutesAgo(120), likeCount: 842, commentCount: 63, reportCount: 0, hidden: false, pinned: false, video: { durationSeconds: 724, aiStatus: "ready" } },
  { id: "p_detox", kind: "discussion", title: "Uống nước ép cần tây 7 ngày, mình đã ngưng thuốc tiểu đường!", excerpt: "Bác sĩ bảo phải uống thuốc suốt đời nhưng nước ép cần tây đã chữa khỏi cho mình…", author: a("u_detox", "Detox Xanh Mỗi Ngày"), createdAt: minutesAgo(200), likeCount: 41, commentCount: 37, reportCount: 9, hidden: false, pinned: false },
  { id: "p_bun_rieu", kind: "recipe", title: "Bún riêu chay cà chua đậu hũ — nước dùng ngọt từ củ quả", excerpt: "Nguyên liệu (4 người): 6 quả cà chua, 2 bìa đậu hũ, 300 g nấm rơm…", author: a("u_hoang_nam", "Hoàng Nam"), createdAt: minutesAgo(300), likeCount: 214, commentCount: 27, reportCount: 0, hidden: false, pinned: false },
  { id: "p_video_lau", kind: "video", title: "Lẩu nấm chay 15 phút cho ngày mưa", excerpt: "Nước lẩu từ nấm đông cô và củ cải…", author: a("u_thao_vy", "Thảo Vy"), createdAt: minutesAgo(25), likeCount: 3, commentCount: 0, reportCount: 0, hidden: false, pinned: false, video: { durationSeconds: 412, aiStatus: "extracting" } },
  { id: "p_b12", kind: "discussion", title: "Mới ăn chay 3 tuần, nên bổ sung B12 thế nào?", excerpt: "Mình ăn chay trường được 3 tuần, hay bị mệt buổi chiều…", author: a("u_ngoc_tram", "Ngọc Trâm"), createdAt: minutesAgo(480), likeCount: 46, commentCount: 31, reportCount: 0, hidden: false, pinned: false },
  { id: "p_spam", kind: "discussion", title: "Trà giảm cân thảo mộc — giảm 8 kg/tháng, inbox Zalo 09xx", excerpt: "Cam kết hoàn tiền, 100% thiên nhiên, liên hệ ngay…", author: a("u_spam_1", "thuocgiamcan.official"), createdAt: daysAgo(1), likeCount: 2, commentCount: 5, reportCount: 14, hidden: true, pinned: false },
  { id: "p_video_meal_prep", kind: "video", title: "Meal prep 5 hộp cơm chay cho cả tuần với 150.000đ", excerpt: "Đi chợ một lần, nấu 90 phút…", author: a("u_bep_may", "Bếp Chay Nhà Mây"), createdAt: daysAgo(1), likeCount: 1290, commentCount: 88, reportCount: 1, hidden: false, pinned: false, video: { durationSeconds: 572, aiStatus: "ready" } },
  { id: "p_flan", kind: "recipe", title: "Bánh flan chay mềm mịn (dùng trứng gà ta cho béo)", excerpt: "Mình thêm 2 lòng đỏ trứng gà ta để bánh mịn hơn…", author: a("u_gen_3", "Hồ Ngọc Linh"), createdAt: daysAgo(2), likeCount: 19, commentCount: 12, reportCount: 3, hidden: false, pinned: false },
  { id: "p_iq", kind: "discussion", title: "Ăn chay lâu năm có làm giảm trí nhớ không?", excerpt: "Đọc trên mạng thấy bảo ăn chay thiếu B12 dễ giảm trí nhớ…", author: a("u_gen_8", "Vũ Hữu Phúc"), createdAt: daysAgo(2), likeCount: 33, commentCount: 40, reportCount: 4, hidden: false, pinned: false },
  { id: "p_video_sua_hat", kind: "video", title: "Sữa hạt điều yến mạch 5 phút, không cần máy làm sữa", excerpt: "Bữa sáng 5 phút cho ngày bận rộn.", author: a("u_thao_vy", "Thảo Vy"), createdAt: daysAgo(2), likeCount: 376, commentCount: 21, reportCount: 0, hidden: false, pinned: false, video: { durationSeconds: 251, aiStatus: "ready" } },
  { id: "p_dam_thuc_vat", kind: "discussion", title: "5 nguồn đạm thực vật rẻ mà chợ nào cũng có", excerpt: "Đậu hũ, đậu xanh nguyên vỏ, đậu phộng, mè đen và tàu hũ ky…", author: a("u_thu_ha", "ThS. DD Phạm Thu Hà", true), createdAt: daysAgo(3), likeCount: 521, commentCount: 44, reportCount: 0, hidden: false, pinned: false },
  { id: "p_me_banh_xeo", kind: "video", title: "Bánh xèo chay nhân nấm — video đầu tay của mình", excerpt: "Lần đầu quay video nấu ăn, mọi người góp ý giúp mình nha!", author: a("u_me", "Minh Anh"), createdAt: daysAgo(5), likeCount: 12, commentCount: 3, reportCount: 0, hidden: false, pinned: false, video: { durationSeconds: 486, aiStatus: "failed", failureReason: "Âm thanh quá nhỏ để nhận dạng giọng nói." } },
  { id: "p_dau_hu_sot_ca", kind: "recipe", title: "Đậu hũ sốt cà chua kiểu Bắc — 15 phút", excerpt: "Rán vàng 2 bìa đậu, xào 3 quả cà chua với hành lá…", author: a("u_bep_may", "Bếp Chay Nhà Mây"), createdAt: daysAgo(3), likeCount: 98, commentCount: 6, reportCount: 0, hidden: false, pinned: false },
];

export async function listContent(query: ContentQuery): Promise<ContentItem[]> {
  await sleep(450);
  const q = SEARCH_FOLD(query.search.trim());
  return content
    .filter((c) => query.kind === "all" || c.kind === query.kind)
    .filter((c) => {
      switch (query.view) {
        case "reported":
          return c.reportCount > 0 && !c.hidden;
        case "hidden":
          return c.hidden;
        case "pinned":
          return c.pinned;
        default:
          return true;
      }
    })
    .filter((c) => !q || SEARCH_FOLD(`${c.title} ${c.author.fullName}`).includes(q))
    .sort((x, y) => (query.view === "reported" ? y.reportCount - x.reportCount : y.createdAt.localeCompare(x.createdAt)));
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
      logAction(actor, "xoá bài viết", item.title);
      return null;
  }
  return { ...item };
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
      reportedContent: content.filter((x) => x.reportCount > 0 && !x.hidden).length,
      failedVideos: content.filter((x) => x.video?.aiStatus === "failed").length,
    },
    signupsDaily: SIGNUPS.map((count, i) => ({ date: daysAgo(SIGNUPS.length - 1 - i), count })),
    contentMix: [
      { kind: "recipe", count: content.filter((x) => x.kind === "recipe").length * 312 },
      { kind: "video", count: content.filter((x) => x.kind === "video").length * 96 },
      { kind: "discussion", count: content.filter((x) => x.kind === "discussion").length * 241 },
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
