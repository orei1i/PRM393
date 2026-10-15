// src/lib/ids.ts
// The SQL ids are INT, but the console keeps every id as a string (mock ids
// stay readable, e.g. "p_bun_rieu"). Read with `readId`, send with `apiId`.

/** Request bodies: numeric ids go out as JSON numbers, anything else unchanged. */
export const apiId = (id: string) => (/^\d+$/.test(id) ? Number(id) : id);

/** Responses: 42 → "42", "p_x" → "p_x", null/undefined → "". */
export const readId = (raw: unknown): string => (raw === null || raw === undefined ? "" : String(raw));
