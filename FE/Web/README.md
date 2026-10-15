# VeganLife Web — Admin console (Next.js 15)

**Chỉ dành cho ban quản trị.** Người dùng (khách, thành viên, chuyên gia) dùng ứng dụng di động trong `FE/Mobile`. Web không có trang nào cho thành viên: mọi route đều phải đăng nhập bằng tài khoản vai trò `Admin`. Tài khoản `Member` bị từ chối và được hướng sang app.

Stack: App Router, TypeScript strict, Tailwind CSS v4, component kiểu shadcn/ui, TanStack Query v5, Lucide. UI tiếng Việt.

## Chạy

```bash
cd FE/Web
npm install
npm run dev        # http://localhost:3000 → /login → /overview
```

Khi dùng dữ liệu mô phỏng, đăng nhập bằng `admin@veganlife.vn` / `admin123`. Thử `minhanh.nguyen@gmail.com` (mật khẩu bất kỳ, ≥ 6 ký tự) để xem màn hình chặn tài khoản thành viên.

`npm run build` chạy luôn type-check và lint. Font tự host (`@fontsource-variable/*`).

## Cấu hình (`.env.local`)

```bash
NEXT_PUBLIC_USE_MOCK_DATA=true                       # false → gọi API ASP.NET Core
NEXT_PUBLIC_API_BASE_URL=http://localhost:5001/api/v1  # cổng trong BE launchSettings.json
```

## Màn hình

| Route | Việc admin làm |
|---|---|
| `/login` | Đăng nhập; chỉ vai trò Admin được vào |
| `/overview` | KPI, hàng đợi cần xử lý (cờ AI, hồ sơ chuyên gia, bài bị báo cáo, video AI lỗi), đăng ký mới 14 ngày, nhật ký quản trị |
| `/users` | Tìm/lọc người dùng; đổi vai trò Admin/Member; tạm khoá, cấm (bắt buộc ghi lý do), mở khoá; xoá (gõ email để xác nhận). Không thể tự khoá hay tự hạ quyền chính mình |
| `/chefs` | Duyệt hồ sơ "Trở thành chuyên gia" gửi từ app; từ chối phải có ghi chú gửi cho người đăng ký |
| `/content` | Bài viết, công thức, video: ẩn/hiện, ghim (tối đa 3), xoá, chạy lại AI cho video lỗi; tab "Bị báo cáo" nhận báo cáo từ app |
| `/moderation` | Hàng đợi cờ AI, xem chi tiết, quyết định kèm ghi chú kiểm toán |
| `/catalog` | Danh mục món, thẻ chế độ ăn, chất gây dị ứng (kèm nhãn AI quét), chuyên môn chuyên gia — thêm, đổi tên, bật/tắt, xoá khi chưa dùng |
| `/telemetry` | Giám sát mô hình AI: độ trễ, lỗi, live `ai_logs` |

## Đăng nhập & phân quyền

- `src/middleware.ts` chuyển mọi route chưa đăng nhập về `/login?next=…`, và chỉ cho quay lại đường dẫn nội bộ.
- `POST /auth/login` trả `AuthResponse { accessToken, refreshToken, expiresAt, user }`. Console chỉ nhận khi `user.role === "Admin"`, rồi gửi `Authorization: Bearer <token>` cho mọi request. Gặp 401 thì xoá phiên và quay về trang đăng nhập.
- Phiên lưu trong cookie `vl_admin_session` (SameSite=Strict, 8 giờ). Khi lên production, nên chuyển sang cookie HttpOnly do BE hoặc một route handler của Next cấp.

## Khớp với backend

- Mọi response được bóc lớp `ApiResponse<T> { success, message, data, statusCode }` (xem `unwrapEnvelope` trong `src/lib/api_client.ts`).
- Enum C# (`UserStatusEnum`, `AuthTypeEnum`) được nhận cả dạng số lẫn dạng chuỗi (`normalizeUser` trong `src/lib/admin_api.ts`).

| Method | Path | Ghi chú |
|---|---|---|
| POST | `/auth/login` | **Đã có ở BE** |
| GET | `/users` | **Đã có** (Admin). Lọc phía client cho tới khi BE hỗ trợ query |
| DELETE | `/users/{id}` | **Đã có** (Admin) |
| PATCH | `/users/{id}/role` | Cần thêm — `{ role: "Admin" \| "Member" }` |
| PATCH | `/users/{id}/status` | Cần thêm — `{ status: "Active" \| "Locked" \| "Banned", reason? }` |
| GET | `/admin/overview` | Cần thêm — `OverviewStats` |
| GET | `/admin/chef-applications?status=` · `/counts` | Cần thêm |
| POST | `/admin/chef-applications/{id}/review` | Cần thêm — `{ decision, note }` |
| GET | `/admin/posts?view=&kind=&search=` | Cần thêm — `ContentItem[]` |
| POST | `/admin/posts/{id}/actions` · DELETE `/admin/posts/{id}` | Cần thêm — `hide`, `unhide`, `pin`, `unpin`, `retry_ai` |
| GET/POST/PATCH/DELETE | `/admin/catalog` | Cần thêm — `CatalogItem` |
| GET/POST | `/admin/moderation/flags…` | Cần thêm — xem `src/types/moderation.ts` |
| GET | `/admin/ai/telemetry/summary`, `/admin/ai/logs` | Cần thêm |

Kiểu dữ liệu nằm ở `src/types/admin.ts` và `src/types/moderation.ts`.

## Cấu trúc

```
src/
├── middleware.ts                 # chặn route khi chưa đăng nhập admin
├── app/
│   ├── login/page.tsx
│   ├── (admin)/                  # sidebar + header (user menu, đăng xuất)
│   │   ├── overview/ users/ chefs/ content/ catalog/ moderation/ telemetry/
│   └── layout.tsx, globals.css   # font, QueryClient, Toaster, token màu
├── components/
│   ├── ui/                       # button, card, badge, table, sheet, dialog, switch, tabs, form-controls, sonner
│   ├── admin/                    # sidebar, user-menu, page-header, states, initials-avatar
│   ├── overview/ users/ chefs/ content/ catalog/ moderation/ telemetry/
├── lib/
│   ├── api_client.ts             # request(), envelope, Bearer, moderation/telemetry API
│   ├── admin_api.ts              # auth, users, chef applications, content, catalog, overview
│   ├── auth.ts                   # cookie phiên admin
│   ├── mock_data.ts, mock_admin.ts
│   └── hooks/                    # TanStack Query (cập nhật lạc quan, polling)
└── types/                        # admin.ts, moderation.ts
```

## Thử nhanh (mock)

- Thêm `#fail` vào lý do khoá tài khoản, ghi chú duyệt chuyên gia hoặc ghi chú kiểm duyệt để xem đường lỗi (toast + hoàn tác).
- Mở tài khoản của chính bạn ở `/users` để thấy các thao tác nguy hiểm bị khoá.
- `/catalog`: thêm một mã đã có (ví dụ `main`) sẽ báo trùng; mục đang được dùng thì không xoá được, chỉ tắt.
- Dữ liệu mock nằm trong bộ nhớ trình duyệt, tải lại trang là về dữ liệu ban đầu.
