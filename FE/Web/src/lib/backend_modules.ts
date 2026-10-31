// src/lib/backend_modules.ts
// The one place that decides which admin modules talk to the real ASP.NET Core API.
//
//   NEXT_PUBLIC_USE_MOCK_DATA !== "false"   every module is mock (the default)
//   NEXT_PUBLIC_USE_MOCK_DATA=false         REAL_DEFAULT is real, the rest stay mock
//   NEXT_PUBLIC_REAL_MODULES=comments,ads   adds modules to the real set
//   NEXT_PUBLIC_MOCK_MODULES=content        removes modules (a module in both ends up mock)
//
// `auth` mock means everything is mock: real modules need a JWT and a mock session has none.
// NEXT_PUBLIC_* values are inlined at build time, so changing them needs a rebuild.

export const WEB_MODULES = [
  "auth",
  "users",
  "content",
  "comments",
  "chefs",
  "catalog",
  "overview",
  "moderation",
  "telemetry",
  "aiModels",
  "knowledge",
  "commerce",
  "bookings",
  "payouts",
  "restaurants",
  "ads",
] as const;

export type WebModule = (typeof WEB_MODULES)[number];

/** What the backend supports today (be_integration_plan §4). Flipping a module later is one line. */
const REAL_DEFAULT: readonly WebModule[] = ["auth", "users", "content"];

/** Comma-separated, case-insensitive module names. Unknown names are ignored. */
function parseModules(raw: string | undefined): WebModule[] {
  const names = (raw ?? "").split(",").map((part) => part.trim().toLowerCase());
  return WEB_MODULES.filter((name) => names.includes(name.toLowerCase()));
}

function resolveRealModules(): ReadonlySet<WebModule> {
  if (process.env.NEXT_PUBLIC_USE_MOCK_DATA !== "false") return new Set();
  const real = new Set<WebModule>([...REAL_DEFAULT, ...parseModules(process.env.NEXT_PUBLIC_REAL_MODULES)]);
  for (const name of parseModules(process.env.NEXT_PUBLIC_MOCK_MODULES)) real.delete(name);
  return real.has("auth") ? real : new Set();
}

const REAL_MODULES = resolveRealModules();

export function isMock(name: WebModule): boolean {
  return !REAL_MODULES.has(name);
}

export const ALL_MODULES_REAL = REAL_MODULES.size === WEB_MODULES.length;

/** Header badge text. */
export const DATA_MODE_LABEL = REAL_MODULES.size === 0 ? "Dữ liệu mô phỏng" : ALL_MODULES_REAL ? "Production" : "Kết hợp: máy chủ + mô phỏng";

/** Actions a real module has no backend route for: disabled in the UI, refused by the API layer. */
export const UNSUPPORTED_ACTION = "Máy chủ chưa hỗ trợ thao tác này.";
