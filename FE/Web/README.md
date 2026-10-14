# VeganLife Web Admin (Next.js 15)

Admin portal for AI content moderation and model telemetry. App Router, TypeScript strict mode, Tailwind CSS v4, shadcn/ui-style components, TanStack Query v5, Lucide icons. UI copy is Vietnamese.

## Chạy

```bash
cd FE/Web
npm install
npm run dev        # http://localhost:3000 → /moderation
```

`npm run build` passes type-check and lint. Fonts are self-hosted (`@fontsource-variable/*`), so the build doesn't need Google Fonts access.

## Cấu hình (`.env.local`)

```bash
NEXT_PUBLIC_USE_MOCK_DATA=true                       # false → call the ASP.NET Core API
NEXT_PUBLIC_API_BASE_URL=http://localhost:5080/api/v1
```

In mock mode the header shows "Dữ liệu mô phỏng". Admin auth is expected as an HttpOnly cookie from the backend (`credentials: "include"`).

## Cấu trúc

```
src/
├── app/
│   ├── (admin)/
│   │   ├── layout.tsx            # sidebar + header
│   │   ├── moderation/page.tsx   # Module 4: flag queue + inspection drawer + decisions
│   │   └── telemetry/page.tsx    # Module 4: metric cards + live ai_logs table
│   ├── layout.tsx                # fonts, QueryClient, Toaster
│   └── globals.css               # VeganLife tokens (sage, sprout, ochre, AI lavender) + dark
├── components/
│   ├── ui/                       # button, card, badge, table, sheet, tabs, form-controls, sonner
│   ├── admin/ moderation/ telemetry/
├── lib/
│   ├── api_client.ts             # moderationApi / telemetryApi (mock ↔ real switch)
│   ├── mock_data.ts              # in-memory backend with latency + live log generator
│   ├── api_error.ts
│   └── hooks/                    # TanStack Query hooks (optimistic decision, 3 s log polling)
└── types/moderation.ts           # AiLog, AiFlag, Post, ModerationDecision…
```

## Hợp đồng API (cho team backend)

| Method | Path | Body / Query | Returns |
|---|---|---|---|
| GET | `/admin/moderation/flags` | `status`, `category?`, `search?` | `AiFlag[]` (oldest first) |
| GET | `/admin/moderation/flags/counts` | | `{ pending, escalated, resolved }` |
| POST | `/admin/moderation/flags/{id}/decision` | `ModerationDecisionInput` | `ModerationDecision` (400 if note < 10 chars, 409 if already resolved) |
| GET | `/admin/ai/telemetry/summary` | `range=1h\|24h\|7d` | `TelemetrySummary` |
| GET | `/admin/ai/logs` | `task?`, `limit` | `AiLog[]` newest first |

Types are in `src/types/moderation.ts` (camelCase JSON, ASP.NET Core default).

## Thử nhanh

- Open an item → the decision buttons stay locked until the audit note has ≥ 10 characters. ⌘/Ctrl + Enter applies the AI suggestion.
- Put `#fail` in the note to see the error path (toast + rollback of the optimistic update).
- Telemetry: the log table polls every 3 s; new rows flash once. "Tạm dừng" stops polling, and the task filter narrows to Kiểm duyệt / Thực đơn / Chatbot / Quét ảnh.
