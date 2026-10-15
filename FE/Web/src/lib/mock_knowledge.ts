// src/lib/mock_knowledge.ts
// In-memory knowledge_docs for the RAG chatbot. Chef docs mirror the mobile
// chef-studio seeds (Tâm: 1 approved, 1 pending, 1 rejected).
import type { AdminSession } from "@/types/admin";
import type {
  KnowledgeChunk,
  KnowledgeDoc,
  KnowledgeDocStatus,
  KnowledgeQuery,
  KnowledgeReviewInput,
  WhoDocInput,
} from "@/types/knowledge";
import { MIN_AUDIT_NOTE_LENGTH } from "@/types/moderation";

import { ApiError } from "./api_error";
import { logAction } from "./mock_admin";
import { sleep } from "./mock_data";

const minutesAgo = (m: number) => new Date(Date.now() - m * 60_000).toISOString();
const daysAgo = (d: number) => minutesAgo(d * 24 * 60);

const WHO_BASE = "https://files.veganlife.vn/who";
const CHEF_BASE = "https://files.veganlife.vn/mock";

function who(id: string, title: string, file: string, chunkCount: number, citationCount: number, age: number): KnowledgeDoc {
  return {
    id,
    chefId: null,
    chefName: null,
    title,
    source: "WHO",
    fileUrl: `${WHO_BASE}/${file}`,
    createdAt: daysAgo(age),
    status: "Approved",
    chunkCount,
    citationCount,
    reviewNote: null,
    reviewedBy: "Trần Thu Hằng",
    reviewedAt: daysAgo(age),
  };
}

function chef(
  id: string,
  chefId: string,
  chefName: string,
  title: string,
  file: string,
  createdAt: string,
  review: Partial<Pick<KnowledgeDoc, "status" | "chunkCount" | "citationCount" | "reviewNote" | "reviewedBy" | "reviewedAt">> = {},
): KnowledgeDoc {
  return {
    id,
    chefId,
    chefName,
    title,
    source: "Chef",
    fileUrl: `${CHEF_BASE}/${file}`,
    createdAt,
    status: "Pending",
    chunkCount: 0,
    citationCount: 0,
    reviewNote: null,
    reviewedBy: null,
    reviewedAt: null,
    ...review,
  };
}

const docs: KnowledgeDoc[] = [
  who("kd_who_1", "Healthy diet — Fact sheet (2025)", "healthy-diet-fact-sheet-2025.pdf", 42, 1840, 120),
  who("kd_who_2", "Guideline: Sodium intake for adults and children", "sodium-intake-guideline.pdf", 36, 612, 118),
  who("kd_who_3", "Guideline: Sugars intake for adults and children", "sugars-intake-guideline.pdf", 31, 540, 118),
  who("kd_who_4", "Vitamin and mineral requirements in human nutrition", "vitamin-mineral-requirements.pdf", 128, 1205, 110),
  who("kd_who_5", "Plant-based diets and their impact on health, sustainability and the environment", "plant-based-diets-review.pdf", 54, 980, 95),
  who("kd_who_6", "Total fat intake for the prevention of unhealthy weight gain", "total-fat-intake.pdf", 22, 230, 60),
  // Tâm's three docs mirror the mobile chef-studio seeds (FE/Mobile mock_commerce_db.dart).
  chef("kd_tam_1", "chef_tam", "Lê Quang Tâm", "Bữa sáng chay đủ đạm cho người tập", "bua-sang-chay-du-dam.pdf", daysAgo(21), {
    status: "Approved",
    chunkCount: 18,
    citationCount: 96,
    reviewedBy: "Lê Minh Quân",
    reviewedAt: daysAgo(19),
  }),
  chef("kd_tam_2", "chef_tam", "Lê Quang Tâm", "Bảo quản đồ ăn meal prep chay trong 5 ngày", "bao-quan-meal-prep.pdf", daysAgo(2)),
  chef("kd_tam_3", "chef_tam", "Lê Quang Tâm", "Nước ép rau củ thay bữa tối để thải độc", "nuoc-ep-thai-doc.pdf", daysAgo(9), {
    status: "Rejected",
    reviewNote: "Tài liệu khẳng định \"thải độc\" nhưng chưa có nguồn y khoa. Vui lòng bổ sung nguồn hoặc bỏ phần này.",
    reviewedBy: "Trần Thu Hằng",
    reviewedAt: daysAgo(8),
  }),
  chef("kd_thu_ha_1", "chef_thu_ha", "ThS. DD Phạm Thu Hà", "Bổ sung vitamin B12 cho người ăn thuần chay", "b12_thuan_chay.pdf", daysAgo(30), {
    status: "Approved",
    chunkCount: 24,
    citationCount: 410,
    reviewedBy: "Trần Thu Hằng",
    reviewedAt: daysAgo(28),
  }),
  chef("kd_thu_ha_2", "chef_thu_ha", "ThS. DD Phạm Thu Hà", "Ăn chay cho người tiền tiểu đường: chọn tinh bột và chia bữa", "tien_tieu_duong.pdf", minutesAgo(26 * 60)),
  chef("kd_chau_1", "chef_chau", "Tôn Nữ Minh Châu", "Món chay Huế giàu canxi từ mè đen và rau lá xanh", "chay_hue_canxi.pdf", minutesAgo(5 * 60)),
];

const fold = (s: string) => s.normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[Đđ]/g, "d").toLowerCase();

/** Mock chunking: a stable count per title. */
const chunkCountFor = (title: string) => 8 + ([...title].reduce((s, ch) => s + ch.charCodeAt(0), 0) % 23);

export async function listDocs(query: KnowledgeQuery): Promise<KnowledgeDoc[]> {
  await sleep(400);
  const q = fold(query.search.trim());
  return docs
    .filter((d) => query.status === "all" || d.status === query.status)
    .filter((d) => query.source === "all" || d.source === query.source)
    .filter((d) => !q || fold(`${d.title} ${d.chefName ?? ""}`).includes(q))
    .sort((x, y) => (query.status === "Pending" ? x.createdAt.localeCompare(y.createdAt) : y.createdAt.localeCompare(x.createdAt)))
    .map((d) => ({ ...d }));
}

export async function getCounts(): Promise<Record<KnowledgeDocStatus, number>> {
  await sleep(200);
  return {
    Pending: docs.filter((d) => d.status === "Pending").length,
    Approved: docs.filter((d) => d.status === "Approved").length,
    Rejected: docs.filter((d) => d.status === "Rejected").length,
  };
}

const slugify = (s: string) =>
  fold(s)
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 60) || "tai-lieu";

/** Stub storage: a picked file name becomes a stable files.veganlife.vn URL. */
export const whoFileUrl = (fileName: string) => `${WHO_BASE}/${slugify(fileName.replace(/\.pdf$/i, ""))}.pdf`;

let docSeq = 1;

export async function createWhoDoc(input: WhoDocInput, session: AdminSession | null): Promise<KnowledgeDoc> {
  await sleep(800);
  const title = input.title.trim();
  if (title.length < 10) throw new ApiError("Tiêu đề cần ít nhất 10 ký tự.", 400, "title_too_short");
  if (title.toLowerCase().includes("#fail")) {
    throw new ApiError("Máy chủ đang bận, chưa tải được tài liệu. Thử lại sau.", 503, "unavailable");
  }
  if (!/^https:\/\//i.test(input.fileUrl.trim())) throw new ApiError("Đường dẫn tệp phải bắt đầu bằng https://", 400, "bad_url");
  const actor = session?.fullName ?? "Quản trị viên";
  const now = new Date().toISOString();
  const doc: KnowledgeDoc = {
    id: `kd_new_${docSeq++}`,
    chefId: null,
    chefName: null,
    title,
    source: "WHO",
    fileUrl: input.fileUrl.trim(),
    createdAt: now,
    status: "Approved",
    chunkCount: chunkCountFor(title),
    citationCount: 0,
    reviewNote: null,
    reviewedBy: actor,
    reviewedAt: now,
  };
  docs.unshift(doc);
  logAction(actor, "tải tài liệu WHO", title);
  return { ...doc };
}

export async function reviewDoc(input: KnowledgeReviewInput, session: AdminSession | null): Promise<KnowledgeDoc> {
  await sleep(650);
  const note = input.note.trim();
  if (input.decision === "Reject" && note.length < MIN_AUDIT_NOTE_LENGTH) {
    throw new ApiError(`Ghi chú từ chối cần ít nhất ${MIN_AUDIT_NOTE_LENGTH} ký tự.`, 400, "note_too_short");
  }
  if (note.toLowerCase().includes("#fail")) {
    throw new ApiError("Máy chủ đang bận, chưa lưu được quyết định. Thử lại sau.", 503, "unavailable");
  }
  const doc = docs.find((d) => d.id === input.docId);
  if (!doc) throw new ApiError("Tài liệu không còn tồn tại.", 404);
  if (doc.status !== "Pending") throw new ApiError("Tài liệu đã được người khác xử lý.", 409, "already_reviewed");
  const actor = session?.fullName ?? "Quản trị viên";
  doc.status = input.decision === "Approve" ? "Approved" : "Rejected";
  doc.chunkCount = input.decision === "Approve" ? chunkCountFor(doc.title) : 0;
  doc.reviewNote = note || null;
  doc.reviewedBy = actor;
  doc.reviewedAt = new Date().toISOString();
  logAction(actor, input.decision === "Approve" ? "duyệt tài liệu kiến thức" : "từ chối tài liệu kiến thức", doc.title);
  return { ...doc };
}

export async function deleteDoc(id: string, session: AdminSession | null): Promise<void> {
  await sleep(500);
  const index = docs.findIndex((d) => d.id === id);
  if (index < 0) throw new ApiError("Tài liệu không còn tồn tại.", 404);
  const [removed] = docs.splice(index, 1);
  logAction(session?.fullName ?? "Quản trị viên", "xoá tài liệu kiến thức", removed.title);
}

const CHUNK_TEMPLATES: ((title: string) => string)[] = [
  (title: string) => `${title}. Phạm vi: áp dụng cho người trưởng thành khoẻ mạnh; không thay thế chỉ định của bác sĩ hoặc chuyên gia dinh dưỡng.`,
  () => "Khuyến nghị chính: ưu tiên ngũ cốc nguyên hạt, rau, trái cây, các loại đậu và hạt; hạn chế muối, đường tự do và chất béo bão hoà.",
  () => "Người ăn thuần chay cần chú ý vitamin B12, sắt, kẽm, canxi, iốt và omega-3. Bổ sung bằng thực phẩm tăng cường hoặc viên uống khi khẩu phần không đủ.",
  () => "Ví dụ một bữa cân đối: 1 bát cơm gạo lứt, 150 g đậu hũ hoặc tempeh, 1 đĩa rau xanh luộc, 1 phần trái cây giàu vitamin C để tăng hấp thu sắt.",
  () => "Lưu ý an toàn: người có bệnh mạn tính, phụ nữ mang thai, người cao tuổi và trẻ nhỏ nên được chuyên gia tư vấn riêng trước khi thay đổi chế độ ăn.",
  () => "Bảo quản: chia hộp ngay sau khi nấu, làm nguội dưới 2 giờ, giữ ngăn mát 0–4 °C tối đa 3–4 ngày và hâm nóng tới khi bốc hơi đều.",
  () => "Đạm thực vật: kết hợp đậu và ngũ cốc trong ngày để đủ axit amin thiết yếu; người tập luyện cần khoảng 1,2–1,6 g đạm/kg cân nặng mỗi ngày.",
];

export async function listChunks(docId: string, limit: number): Promise<KnowledgeChunk[]> {
  await sleep(350);
  const doc = docs.find((d) => d.id === docId);
  if (!doc) throw new ApiError("Tài liệu không còn tồn tại.", 404);
  if (doc.status !== "Approved") return [];
  const offset = [...doc.id].reduce((s, ch) => s + ch.charCodeAt(0), 0) % CHUNK_TEMPLATES.length;
  return Array.from({ length: Math.min(limit, doc.chunkCount) }, (_, i) => ({
    id: `${doc.id}_ck_${i}`,
    docId: doc.id,
    chunkIndex: i,
    content: i === 0 ? CHUNK_TEMPLATES[0](doc.title) : CHUNK_TEMPLATES[1 + ((offset + i) % (CHUNK_TEMPLATES.length - 1))](doc.title),
  }));
}
