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

import { qs, request, requestList, requestObject } from "./api_client";
import { isMock } from "./backend_modules";
import { readSession } from "./auth";
import { readId } from "./ids";
import * as mock from "./mock_knowledge";
import { counts, hasId, isoOr, num, optIso, optText, pick, text, type Raw } from "./wire";

export function normalizeKnowledgeDoc(raw: Raw): KnowledgeDoc {
  return {
    id: readId(raw.id),
    chefId: raw.chefId === null || raw.chefId === undefined ? null : readId(raw.chefId),
    chefName: optText(raw.chefName),
    title: text(raw.title),
    source: pick<KnowledgeSource>(KNOWLEDGE_SOURCES, raw.source, "WHO"),
    fileUrl: text(raw.fileUrl),
    createdAt: isoOr(raw.createdAt),
    status: pick<KnowledgeDocStatus>(KNOWLEDGE_DOC_STATUSES, raw.status, "Pending"),
    chunkCount: num(raw.chunkCount),
    citationCount: num(raw.citationCount),
    reviewNote: optText(raw.reviewNote),
    reviewedBy: optText(raw.reviewedBy),
    reviewedAt: optIso(raw.reviewedAt),
  };
}

export const knowledgeApi = {
  /** GET /admin/knowledge-docs?source=&status=&search= */
  async list(query: KnowledgeQuery): Promise<KnowledgeDoc[]> {
    if (isMock("knowledge")) return mock.listDocs(query);
    const raw = await requestList(
      `/admin/knowledge-docs?${qs({
        status: query.status === "all" ? undefined : query.status,
        source: query.source === "all" ? undefined : query.source,
        search: query.search,
      })}`,
    );
    return raw.map(normalizeKnowledgeDoc).filter(hasId);
  },

  /** GET /admin/knowledge-docs/counts */
  async counts(): Promise<Record<KnowledgeDocStatus, number>> {
    if (isMock("knowledge")) return mock.getCounts();
    return counts(KNOWLEDGE_DOC_STATUSES, await requestObject("/admin/knowledge-docs/counts"));
  },

  /** POST /admin/knowledge-docs { title, fileUrl } → source WHO, status Approved. */
  async createWho(input: WhoDocInput): Promise<KnowledgeDoc> {
    if (isMock("knowledge")) return mock.createWhoDoc(input, readSession());
    return normalizeKnowledgeDoc(await requestObject("/admin/knowledge-docs", { method: "POST", body: JSON.stringify(input) }));
  },

  /** POST /admin/knowledge-docs/{id}/review { decision, note } */
  async review(input: KnowledgeReviewInput): Promise<KnowledgeDoc> {
    if (isMock("knowledge")) return mock.reviewDoc(input, readSession());
    return normalizeKnowledgeDoc(
      await requestObject(`/admin/knowledge-docs/${input.docId}/review`, {
        method: "POST",
        body: JSON.stringify({ decision: input.decision, note: input.note }),
      }),
    );
  },

  /** DELETE /admin/knowledge-docs/{id} — past answers keep their citations. */
  async remove(id: string): Promise<void> {
    if (isMock("knowledge")) return mock.deleteDoc(id, readSession());
    await request<unknown>(`/admin/knowledge-docs/${id}`, { method: "DELETE" });
  },

  /** GET /admin/knowledge-docs/{id}/chunks?limit= */
  async chunks(id: string, limit = 5): Promise<KnowledgeChunk[]> {
    if (isMock("knowledge")) return mock.listChunks(id, limit);
    const raw = await requestList(`/admin/knowledge-docs/${id}/chunks?${qs({ limit })}`);
    return raw.map((c) => ({ id: readId(c.id), docId: readId(c.docId ?? id), chunkIndex: num(c.chunkIndex), content: text(c.content) })).filter(hasId);
  },
};

/** Stub upload: a picked PDF's name becomes its files.veganlife.vn URL (no storage yet). */
export const whoFileUrlFor = (fileName: string) => mock.whoFileUrl(fileName);
