// src/lib/knowledge_api.ts
// Knowledge docs for the RAG chatbot: WHO uploads (approved on upload) and
// chef contributions (used by the AI only after an admin approves them).
import type {
  KnowledgeChunk,
  KnowledgeDoc,
  KnowledgeDocStatus,
  KnowledgeQuery,
  KnowledgeReviewInput,
  KnowledgeSource,
  WhoDocInput,
} from "@/types/knowledge";
import { KNOWLEDGE_DOC_STATUSES, KNOWLEDGE_SOURCES } from "@/types/knowledge";

import { qs, request, USE_MOCK_DATA } from "./api_client";
import { readSession } from "./auth";
import { readId } from "./ids";
import * as mock from "./mock_knowledge";

function pick<T extends string>(values: readonly T[], raw: unknown, fallback: T): T {
  return typeof raw === "string" ? (values.find((v) => v.toLowerCase() === raw.toLowerCase()) ?? fallback) : fallback;
}

type RawDoc = Partial<Omit<KnowledgeDoc, "id" | "chefId" | "source" | "status">> & {
  id?: unknown;
  chefId?: unknown;
  source?: unknown;
  status?: unknown;
};

export function normalizeKnowledgeDoc(raw: RawDoc): KnowledgeDoc {
  return {
    id: readId(raw.id),
    chefId: raw.chefId === null || raw.chefId === undefined ? null : readId(raw.chefId),
    chefName: raw.chefName ?? null,
    title: raw.title ?? "",
    source: pick<KnowledgeSource>(KNOWLEDGE_SOURCES, raw.source, "WHO"),
    fileUrl: raw.fileUrl ?? "",
    createdAt: raw.createdAt ?? new Date(0).toISOString(),
    status: pick<KnowledgeDocStatus>(KNOWLEDGE_DOC_STATUSES, raw.status, "Pending"),
    chunkCount: raw.chunkCount ?? 0,
    citationCount: raw.citationCount ?? 0,
    reviewNote: raw.reviewNote ?? null,
    reviewedBy: raw.reviewedBy ?? null,
    reviewedAt: raw.reviewedAt ?? null,
  };
}

export const knowledgeApi = {
  /** GET /admin/knowledge-docs?source=&status=&search= */
  async list(query: KnowledgeQuery): Promise<KnowledgeDoc[]> {
    if (USE_MOCK_DATA) return mock.listDocs(query);
    const raw = await request<RawDoc[]>(
      `/admin/knowledge-docs?${qs({
        status: query.status === "all" ? undefined : query.status,
        source: query.source === "all" ? undefined : query.source,
        search: query.search,
      })}`,
    );
    return raw.map(normalizeKnowledgeDoc);
  },

  /** GET /admin/knowledge-docs/counts */
  counts(): Promise<Record<KnowledgeDocStatus, number>> {
    if (USE_MOCK_DATA) return mock.getCounts();
    return request<Record<KnowledgeDocStatus, number>>("/admin/knowledge-docs/counts");
  },

  /** POST /admin/knowledge-docs { title, fileUrl } → source WHO, status Approved. */
  async createWho(input: WhoDocInput): Promise<KnowledgeDoc> {
    if (USE_MOCK_DATA) return mock.createWhoDoc(input, readSession());
    return normalizeKnowledgeDoc(await request<RawDoc>("/admin/knowledge-docs", { method: "POST", body: JSON.stringify(input) }));
  },

  /** POST /admin/knowledge-docs/{id}/review { decision, note } */
  async review(input: KnowledgeReviewInput): Promise<KnowledgeDoc> {
    if (USE_MOCK_DATA) return mock.reviewDoc(input, readSession());
    return normalizeKnowledgeDoc(
      await request<RawDoc>(`/admin/knowledge-docs/${input.docId}/review`, {
        method: "POST",
        body: JSON.stringify({ decision: input.decision, note: input.note }),
      }),
    );
  },

  /** DELETE /admin/knowledge-docs/{id} — past answers keep their citations. */
  async remove(id: string): Promise<void> {
    if (USE_MOCK_DATA) return mock.deleteDoc(id, readSession());
    await request<unknown>(`/admin/knowledge-docs/${id}`, { method: "DELETE" });
  },

  /** GET /admin/knowledge-docs/{id}/chunks?limit= */
  async chunks(id: string, limit = 5): Promise<KnowledgeChunk[]> {
    if (USE_MOCK_DATA) return mock.listChunks(id, limit);
    const raw = await request<(Omit<KnowledgeChunk, "id" | "docId"> & { id?: unknown; docId?: unknown })[]>(
      `/admin/knowledge-docs/${id}/chunks?${qs({ limit })}`,
    );
    return raw.map((c) => ({ id: readId(c.id), docId: readId(c.docId ?? id), chunkIndex: c.chunkIndex ?? 0, content: c.content ?? "" }));
  },
};

/** Stub upload: a picked PDF's name becomes its files.veganlife.vn URL (no storage yet). */
export const whoFileUrlFor = (fileName: string) => mock.whoFileUrl(fileName);
