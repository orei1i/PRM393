// src/lib/wire.ts
// Readers for what the server sends. Nothing here trusts a field's presence or type, so a normaliser
// built on them always returns a complete row and no page has to guard against a missing list, a
// null name or a date it cannot format.
export type Raw = Record<string, unknown>;

export const obj = (raw: unknown): Raw | null => (raw && typeof raw === "object" && !Array.isArray(raw) ? (raw as Raw) : null);

/** The objects of a list; anything else in it, or anything that is not a list, is dropped. */
export const objects = (raw: unknown): Raw[] => (Array.isArray(raw) ? raw.map(obj).filter((x): x is Raw => x !== null) : []);

/** Case-insensitive, ignores spaces, `_` and `-`; unknown → fallback. */
export function pick<T extends string>(values: readonly T[], raw: unknown, fallback: T): T {
  if (typeof raw !== "string") return fallback;
  const key = (s: string) => s.replace(/[\s_-]/g, "").toLowerCase();
  return values.find((v) => key(v) === key(raw)) ?? fallback;
}

export const num = (raw: unknown, fallback = 0): number => {
  const n = typeof raw === "number" ? raw : typeof raw === "string" && raw.trim() !== "" ? Number(raw) : NaN;
  return Number.isFinite(n) ? n : fallback;
};

export const optNum = (raw: unknown): number | null => (raw === null || raw === undefined || raw === "" ? null : Number.isFinite(num(raw, NaN)) ? num(raw) : null);

/** Strings and numbers as text; objects, arrays and null → fallback, never "[object Object]". */
export const text = (raw: unknown, fallback = ""): string => (typeof raw === "string" ? raw : typeof raw === "number" ? String(raw) : fallback);

export const optText = (raw: unknown): string | null => (typeof raw === "string" && raw ? raw : null);

export const bool = (raw: unknown, fallback = false): boolean => (typeof raw === "boolean" ? raw : fallback);

/** Normalisers fill a missing required date with this; the date formatters print it as "—". */
export const NO_DATE = new Date(0).toISOString();

/** A date the formatters can use, or null. */
export const optIso = (raw: unknown): string | null => (typeof raw === "string" && !Number.isNaN(Date.parse(raw)) ? raw : null);

export const isoOr = (raw: unknown): string => optIso(raw) ?? NO_DATE;

/** "2026-10-20T00:00:00" → "2026-10-20"; anything that is not a date → "". */
export const dateOnly = (raw: unknown): string => {
  const day = typeof raw === "string" ? raw.slice(0, 10) : "";
  return /^\d{4}-\d{2}-\d{2}$/.test(day) && !Number.isNaN(Date.parse(day)) ? day : "";
};

export const texts = (raw: unknown): string[] => (Array.isArray(raw) ? raw.map((x) => text(x)).filter(Boolean) : []);

/** A count per key, 0 where the server sent none. */
export const counts = <K extends string>(keys: readonly K[], raw: unknown): Record<K, number> => {
  const source = obj(raw) ?? {};
  return Object.fromEntries(keys.map((key) => [key, num(source[key])])) as Record<K, number>;
};

/** A row the console cannot address is dropped from its list (actions and React keys need the id). */
export const hasId = (row: { id: string }) => row.id !== "";
