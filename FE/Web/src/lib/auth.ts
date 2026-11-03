// src/lib/auth.ts
// Admin session kept in a cookie so `middleware.ts` can guard every route.
// The backend issues a JWT and a refresh token (AuthResponse) — only role "Admin" may sign in here.
import type { AdminSession } from "@/types/admin";

export const SESSION_COOKIE = "vl_admin_session";
const MAX_AGE_SECONDS = 8 * 60 * 60; // one working day

export function encodeSession(session: AdminSession): string {
  return encodeURIComponent(JSON.stringify(session));
}

export function decodeSession(raw: string | undefined | null): AdminSession | null {
  if (!raw) return null;
  try {
    const parsed = JSON.parse(decodeURIComponent(raw)) as Partial<AdminSession>;
    if (!parsed.accessToken || !parsed.userId || !parsed.email) return null;
    return {
      userId: parsed.userId,
      email: parsed.email,
      fullName: parsed.fullName ?? parsed.email,
      accessToken: parsed.accessToken,
      refreshToken: parsed.refreshToken,
    };
  } catch {
    return null;
  }
}

export function readSession(): AdminSession | null {
  if (typeof document === "undefined") return null;
  const match = document.cookie.split("; ").find((c) => c.startsWith(`${SESSION_COOKIE}=`));
  return decodeSession(match?.slice(SESSION_COOKIE.length + 1));
}

export function writeSession(session: AdminSession) {
  const secure = typeof location !== "undefined" && location.protocol === "https:" ? "; Secure" : "";
  document.cookie = `${SESSION_COOKIE}=${encodeSession(session)}; Path=/; Max-Age=${MAX_AGE_SECONDS}; SameSite=Strict${secure}`;
}

export function clearSession() {
  document.cookie = `${SESSION_COOKIE}=; Path=/; Max-Age=0; SameSite=Strict`;
}

const AFTER_LOGIN = "/overview";
/** Never contacted: only compared with the origin the URL parser resolves to. */
const PATH_ORIGIN = "https://path.invalid";
/** The URL parser drops tab and newline and reads "\" as "/", so `/\host` and `/\t/host` are other origins. */
const UNSAFE_PATH_CHARS = /[\u0000-\u001f\u007f-\u009f\\]/;
/** `%2F`, `%252F`, … */
const ENCODED_SLASH = /%(?:25)*2f/i;

/** The path with every layer of percent-encoding removed, or null when the encoding is broken. */
function decodedPath(pathname: string): string | null {
  let path = pathname;
  try {
    for (let i = 0; i < 5 && path.includes("%"); i++) path = decodeURIComponent(path);
  } catch {
    return null;
  }
  return path.includes("%") ? null : path;
}

/**
 * Where to go after login: an internal path, normalised, or /overview. `next` has already been
 * decoded once by searchParams. Encoded separators and /login itself are refused in any spelling,
 * because a router or proxy further on may decode the path again.
 */
export function safeNextPath(next: string | null | undefined): string {
  if (!next || !next.startsWith("/") || next.startsWith("//") || UNSAFE_PATH_CHARS.test(next)) return AFTER_LOGIN;
  let url: URL;
  try {
    url = new URL(next, PATH_ORIGIN);
  } catch {
    return AFTER_LOGIN;
  }
  if (url.origin !== PATH_ORIGIN) return AFTER_LOGIN;
  const path = decodedPath(url.pathname);
  // `/.//host` parses to the pathname `//host`, so this looks at the parsed path, not at `next`.
  if (!path || path.startsWith("//") || UNSAFE_PATH_CHARS.test(path) || ENCODED_SLASH.test(url.pathname)) return AFTER_LOGIN;
  if (/^\/login(\/|$)/i.test(path)) return AFTER_LOGIN;
  return `${url.pathname}${url.search}${url.hash}`;
}
