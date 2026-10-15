// src/lib/auth.ts
// Admin session kept in a cookie so `middleware.ts` can guard every route.
// The backend issues a JWT (AuthResponse.accessToken) — only role "Admin" may sign in here.
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

/** Only same-site relative paths are allowed after login (no open redirects). */
export function safeNextPath(next: string | null | undefined): string {
  if (!next || !next.startsWith("/") || next.startsWith("//") || next.startsWith("/login")) return "/overview";
  return next;
}
