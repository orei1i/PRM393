// src/middleware.ts
// The web app is the admin console only: every page except /login needs an
// admin session. Members use the VeganLife mobile app.
import { NextResponse, type NextRequest } from "next/server";

import { decodeSession, SESSION_COOKIE } from "@/lib/auth";

export function middleware(request: NextRequest) {
  const { pathname, search } = request.nextUrl;
  const session = decodeSession(request.cookies.get(SESSION_COOKIE)?.value);

  if (pathname === "/login") {
    if (session) return NextResponse.redirect(new URL("/overview", request.url));
    return NextResponse.next();
  }

  if (!session) {
    const login = new URL("/login", request.url);
    if (pathname !== "/") login.searchParams.set("next", `${pathname}${search}`);
    return NextResponse.redirect(login);
  }
  return NextResponse.next();
}

export const config = {
  // Everything except Next internals and static files.
  matcher: ["/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|ico|webp)$).*)"],
};
