// src/types/ai_models.ts
// AI model controls and accuracy (proposed tables ai_models, ai_log_labels;
// precision comes from ai_flags × moderation_decisions).
import type { AiTaskType, FlagCategory, ISODateString, TelemetryRange } from "./moderation";

export interface AiModel {
  id: string;
  task: AiTaskType;
  name: string;
  activeVersion: string;
  availableVersions: string[];
  enabled: boolean;
  /** moderation: flag when score ≥ threshold; vision_scan: min label confidence. null for LLM tasks. */
  threshold: number | null;
  /** What the app does while the model is turned off. */
  fallback: string;
  updatedAt: ISODateString;
  updatedBy: string | null;
}

/** PATCH /admin/ai/models/{id} — `note` is the mandatory audit note (≥ 10 chars). */
export interface AiModelPatch {
  enabled?: boolean;
  threshold?: number;
  activeVersion?: string;
  note: string;
}

export interface AiAccuracyMetrics {
  range: TelemetryRange;
  moderation: {
    decided: number;
    /** Decisions that upheld the flag (reject / warn). */
    confirmed: number;
    /** Decisions that approved a flagged post. */
    overridden: number;
    precision: number;
    overrideRate: number;
    pending: number;
    medianDecisionMinutes: number;
    byCategory: { category: FlagCategory; decided: number; precision: number }[];
  };
  labeled: { task: AiTaskType; labeled: number; correct: number; accuracy: number | null }[];
}

export const THRESHOLD_MIN = 0.5;
export const THRESHOLD_MAX = 0.99;
/** Below this many labels the accuracy is not shown. */
export const MIN_LABELS_FOR_ACCURACY = 10;

/** Longer task names for the models page (TASK_LABEL stays short for tables). */
export const AI_TASK_TITLE: Record<AiTaskType, string> = {
  moderation: "Kiểm duyệt nội dung",
  chatbot: "Chatbot dinh dưỡng",
  meal_plan: "Gợi ý thực đơn",
  vision_scan: "Quét nguyên liệu",
};
