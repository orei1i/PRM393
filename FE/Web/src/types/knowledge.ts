// src/types/knowledge.ts
// RAG knowledge base: knowledge_docs (+ proposed status / review columns) and their chunks.
import type { ISODateString } from "./moderation";

export const KNOWLEDGE_SOURCES = ["WHO", "Chef"] as const;
export type KnowledgeSource = (typeof KNOWLEDGE_SOURCES)[number];

export const KNOWLEDGE_DOC_STATUSES = ["Pending", "Approved", "Rejected"] as const;
export type KnowledgeDocStatus = (typeof KNOWLEDGE_DOC_STATUSES)[number];

export const KNOWLEDGE_SOURCE_LABEL: Record<KnowledgeSource, string> = {
  WHO: "WHO",
  Chef: "Chuyên gia",
};

export const KNOWLEDGE_STATUS_LABEL: Record<KnowledgeDocStatus, string> = {
  Pending: "Chờ duyệt",
  Approved: "Đã duyệt",
  Rejected: "Bị từ chối",
};

export interface KnowledgeDoc {
  id: string;
  chefId: string | null;
  chefName: string | null;
  title: string;
  source: KnowledgeSource;
  fileUrl: string;
  createdAt: ISODateString;
  status: KnowledgeDocStatus;
  /** Computed by BE (count of knowledge_chunks). 0 until approved. */
  chunkCount: number;
  /** Computed by BE: chatbot answers citing this doc. */
  citationCount: number;
  reviewNote: string | null;
  reviewedBy: string | null;
  reviewedAt: ISODateString | null;
}

export interface KnowledgeQuery {
  status: KnowledgeDocStatus | "all";
  source: KnowledgeSource | "all";
  search: string;
}

/** POST /admin/knowledge-docs/{id}/review — `note` required (≥ 10 chars) when rejecting. */
export interface KnowledgeReviewInput {
  docId: string;
  decision: "Approve" | "Reject";
  note: string;
}

export interface KnowledgeChunk {
  id: string;
  docId: string;
  chunkIndex: number;
  content: string;
}

/** POST /admin/knowledge-docs — WHO uploads start Approved. */
export interface WhoDocInput {
  title: string;
  fileUrl: string;
}
