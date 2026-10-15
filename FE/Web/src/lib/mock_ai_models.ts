// src/lib/mock_ai_models.ts
// Mock AI model controls + accuracy metrics. Saving a model reconfigures the
// ai_logs generator in mock_data.ts, so /telemetry reflects the change.
import type { AiAccuracyMetrics, AiModel, AiModelPatch } from "@/types/ai_models";
import { MIN_LABELS_FOR_ACCURACY, THRESHOLD_MAX, THRESHOLD_MIN } from "@/types/ai_models";
import type { AdminSession } from "@/types/admin";
import { MIN_AUDIT_NOTE_LENGTH, type AiTaskType, type FlagCategory, type TelemetryRange } from "@/types/moderation";

import { ApiError } from "./api_error";
import { countPendingPosts, logAction } from "./mock_admin";
import { configureGenerator, getDecisionSamples, getLogLabels, getOpenFlagCount, sleep } from "./mock_data";

const daysAgo = (d: number) => new Date(Date.now() - d * 24 * 60 * 60_000).toISOString();

const models: AiModel[] = [
  {
    id: "aim_moderation",
    task: "moderation",
    name: "Kiểm duyệt bài viết & bình luận",
    activeVersion: "moderation-v3",
    availableVersions: ["moderation-v3", "moderation-v2"],
    enabled: true,
    threshold: 0.6,
    fallback: "Bài mới vào hàng Chờ duyệt thủ công",
    updatedAt: daysAgo(6),
    updatedBy: "Lê Minh Quân",
  },
  {
    id: "aim_chatbot",
    task: "chatbot",
    name: "Trợ lý dinh dưỡng (RAG)",
    activeVersion: "llm-primary@v14",
    availableVersions: ["llm-primary@v14", "llm-primary@v13"],
    enabled: true,
    threshold: null,
    fallback: "Ứng dụng báo “Trợ lý đang tạm nghỉ” và gợi ý bài viết của chuyên gia",
    updatedAt: daysAgo(12),
    updatedBy: "Trần Thu Hằng",
  },
  {
    id: "aim_meal_plan",
    task: "meal_plan",
    name: "Gợi ý thực đơn",
    activeVersion: "llm-primary@v14",
    availableVersions: ["llm-primary@v14", "llm-primary@v13"],
    enabled: true,
    threshold: null,
    fallback: "Dùng thực đơn mẫu theo mục tiêu, không cá nhân hoá",
    updatedAt: daysAgo(12),
    updatedBy: "Trần Thu Hằng",
  },
  {
    id: "aim_vision",
    task: "vision_scan",
    name: "Nhận diện nguyên liệu",
    activeVersion: "vision-v2",
    availableVersions: ["vision-v2", "vision-v1"],
    enabled: true,
    threshold: 0.7,
    fallback: "Người dùng tự nhập nguyên liệu thay vì quét ảnh",
    updatedAt: daysAgo(20),
    updatedBy: null,
  },
];

export async function listModels(): Promise<AiModel[]> {
  await sleep(350);
  return models.map((m) => ({ ...m, availableVersions: [...m.availableVersions] }));
}

const thresholdVi = (n: number) => n.toFixed(2).replace(".", ",");

export async function updateModel(id: string, patch: AiModelPatch, session: AdminSession | null): Promise<AiModel> {
  await sleep(650);
  const note = patch.note.trim();
  if (note.length < MIN_AUDIT_NOTE_LENGTH) {
    throw new ApiError(`Ghi chú kiểm toán cần ít nhất ${MIN_AUDIT_NOTE_LENGTH} ký tự.`, 400, "note_too_short");
  }
  if (note.toLowerCase().includes("#fail")) {
    throw new ApiError("Máy chủ đang bận, chưa lưu được cấu hình mô hình. Thử lại sau.", 503, "unavailable");
  }
  const model = models.find((m) => m.id === id);
  if (!model) throw new ApiError("Không tìm thấy mô hình.", 404);
  if (patch.activeVersion !== undefined && !model.availableVersions.includes(patch.activeVersion)) {
    throw new ApiError(`Phiên bản ${patch.activeVersion} không có sẵn.`, 400, "unknown_version");
  }
  if (patch.threshold !== undefined) {
    if (model.threshold === null) throw new ApiError("Mô hình này không dùng ngưỡng.", 400, "no_threshold");
    if (!(patch.threshold >= THRESHOLD_MIN && patch.threshold <= THRESHOLD_MAX)) {
      throw new ApiError(`Ngưỡng phải từ ${thresholdVi(THRESHOLD_MIN)} đến ${thresholdVi(THRESHOLD_MAX)}.`, 400, "bad_threshold");
    }
  }

  const changes: string[] = [];
  if (patch.enabled !== undefined && patch.enabled !== model.enabled) changes.push(patch.enabled ? "bật" : "tắt");
  if (patch.activeVersion !== undefined && patch.activeVersion !== model.activeVersion) changes.push(`phiên bản ${patch.activeVersion}`);
  if (patch.threshold !== undefined && patch.threshold !== model.threshold) changes.push(`ngưỡng ${thresholdVi(patch.threshold)}`);

  const actor = session?.fullName ?? "Quản trị viên";
  Object.assign(model, {
    enabled: patch.enabled ?? model.enabled,
    activeVersion: patch.activeVersion ?? model.activeVersion,
    threshold: patch.threshold ?? model.threshold,
    updatedAt: new Date().toISOString(),
    updatedBy: actor,
  });
  configureGenerator(model.task, { enabled: model.enabled, version: model.activeVersion, threshold: model.threshold });
  logAction(actor, `cập nhật mô hình AI (${changes.join(", ") || "không đổi"})`, model.name);
  return { ...model, availableVersions: [...model.availableVersions] };
}

/* ----------------------------------------------------------------- metrics */

const RANGE_MS: Record<TelemetryRange, number> = { "1h": 60 * 60_000, "24h": 24 * 60 * 60_000, "7d": 7 * 24 * 60 * 60_000 };

/** Seeded decided flags per category: [decided, upheld]. */
const BASELINE: Record<TelemetryRange, Record<FlagCategory, [number, number]>> = {
  "1h": { health_misinformation: [3, 3], spam_promo: [2, 2], harassment: [1, 1], toxicity: [1, 0], not_vegan: [1, 1], copyright: [0, 0] },
  "24h": { health_misinformation: [38, 33], spam_promo: [29, 27], harassment: [14, 11], toxicity: [17, 12], not_vegan: [11, 8], copyright: [5, 2] },
  "7d": { health_misinformation: [242, 209], spam_promo: [198, 186], harassment: [96, 77], toxicity: [121, 88], not_vegan: [74, 55], copyright: [31, 14] },
};

/** Seeded minutes-to-decision samples per range (combined with live decisions for the median). */
const BASELINE_MINUTES: Record<TelemetryRange, number[]> = {
  "1h": [6, 9, 12, 14, 18, 21, 25],
  "24h": [12, 20, 28, 35, 42, 48, 55, 63, 90],
  "7d": [15, 30, 45, 58, 65, 72, 95, 130, 210],
};

/** Seeded admin labels per task: [labelled, correct]. vision_scan stays under the minimum on purpose. */
const BASELINE_LABELS: [AiTaskType, number, number][] = [
  ["chatbot", 46, 41],
  ["meal_plan", 23, 19],
  ["vision_scan", 7, 6],
];

function median(values: number[]) {
  const sorted = [...values].sort((x, y) => x - y);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : Math.round((sorted[mid - 1] + sorted[mid]) / 2);
}

export async function getMetrics(range: TelemetryRange): Promise<AiAccuracyMetrics> {
  await sleep(400);
  const since = Date.now() - RANGE_MS[range];
  const live = getDecisionSamples().filter((s) => new Date(s.decidedAt).getTime() >= since);

  const byCategory = (Object.keys(BASELINE[range]) as FlagCategory[])
    .map((category) => {
      const [baseDecided, baseUpheld] = BASELINE[range][category];
      const liveRows = live.filter((s) => s.category === category);
      const decided = baseDecided + liveRows.length;
      const upheld = baseUpheld + liveRows.filter((s) => s.upheld).length;
      return { category, decided, upheld, precision: decided ? upheld / decided : 0 };
    })
    .sort((x, y) => y.decided - x.decided);

  // Totals come from the rows so the category table always sums to `decided`.
  const decided = byCategory.reduce((s, c) => s + c.decided, 0);
  const confirmed = byCategory.reduce((s, c) => s + c.upheld, 0);
  const overridden = decided - confirmed;

  const labels = getLogLabels();
  const labeled = BASELINE_LABELS.map(([task, baseLabeled, baseCorrect]) => {
    const rows = labels.filter((l) => l.task === task);
    const total = baseLabeled + rows.length;
    const correct = baseCorrect + rows.filter((l) => l.correct).length;
    return { task, labeled: total, correct, accuracy: total >= MIN_LABELS_FOR_ACCURACY ? correct / total : null };
  });

  return {
    range,
    moderation: {
      decided,
      confirmed,
      overridden,
      precision: decided ? confirmed / decided : 0,
      overrideRate: decided ? overridden / decided : 0,
      pending: getOpenFlagCount() + countPendingPosts(),
      medianDecisionMinutes: median([...BASELINE_MINUTES[range], ...live.map((s) => s.minutesToDecide)]),
      byCategory: byCategory.map(({ category, decided: d, precision }) => ({ category, decided: d, precision })),
    },
    labeled,
  };
}
