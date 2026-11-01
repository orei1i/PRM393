// src/lib/ids.ts
// The BE's ids are 24-hex strings, and the console keeps every id as a string
// (mock ids stay readable, e.g. "p_bun_rieu"). Read with `readId`, send with `apiId`.

/** Request bodies: short numeric ids go out as JSON numbers; a long all-digit id would lose digits as a number, so it stays a string. */
export const apiId = (id: string) => (/^\d{1,15}$/.test(id) ? Number(id) : id);

/** Responses: 42 → "42", "p_x" → "p_x", anything else → "". */
export const readId = (raw: unknown): string => (typeof raw === "string" || typeof raw === "number" ? String(raw) : "");
