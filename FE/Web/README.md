# VeganLife Web — Admin console (Next.js 15)

**Chỉ dành cho ban quản trị.** Người dùng (khách, thành viên, chuyên gia) dùng ứng dụng di động trong `FE/Mobile`. Web không có trang nào cho thành viên: mọi route đều phải đăng nhập bằng tài khoản vai trò `Admin`. Tài khoản `User`/`Chef` (và giá trị cũ `Member`) bị từ chối và được hướng sang app.

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
| `/overview` | KPI, hàng đợi cần xử lý (cờ AI, bài chờ duyệt, hồ sơ chuyên gia, tài liệu chờ duyệt, yêu cầu rút tiền, bài bị báo cáo, video AI lỗi), đăng ký mới 14 ngày, nhật ký quản trị |
| **Người dùng** | |
| `/users` | Tìm/lọc theo vai trò Quản trị viên / Thành viên / Chuyên gia và trạng thái; đổi vai trò User ↔ Admin (vai trò Chef bị khoá, chỉ đổi qua duyệt chuyên gia); tạm khoá, cấm (bắt buộc lý do), mở khoá; xoá (gõ email). Drawer có liên kết "Bài viết & video" và "Bình luận" của người đó. Không thể tự khoá hay tự hạ quyền |
| `/chefs` | Duyệt hồ sơ "Trở thành chuyên gia" gửi từ app; duyệt xong vai trò thành `Chef`; từ chối phải có ghi chú |
| **Nội dung** | |
| `/content` | Bài viết, công thức, video. Tab **Chờ duyệt** (bài AI gắn cờ, kèm lý do và điểm AI → "Duyệt & đăng" / "Từ chối" có ghi chú ≥ 10 ký tự) và **Bị từ chối**; ẩn/hiện, ghim (tối đa 3), xoá, chạy lại AI cho video lỗi. `?open=<id>`, `?author=<userId>` |
| `/comments` | Bình luận: Tất cả / Bị báo cáo / Đã ẩn; ẩn/hiện, xoá (lý do tuỳ chọn), "Mở bài viết". Lọc `?author=`, `?post=` |
| `/moderation` | Hàng đợi cờ AI, xem chi tiết, quyết định kèm ghi chú kiểm toán |
| `/restaurants` | Quán chay (do admin thêm hoặc người dùng gợi ý từ app): bật/tắt "Chứng nhận thuần chay", xem/xoá đánh giá, xoá quán |
| `/catalog` | Danh mục món, thẻ chế độ ăn, chất gây dị ứng (kèm nhãn AI quét), chuyên môn chuyên gia — thêm, đổi tên, bật/tắt, xoá khi chưa dùng |
| **Kinh doanh** | |
| `/orders` | Đơn mua dịch vụ chuyên gia (Tư vấn / Khoá học / Thực đơn VIP) qua PaymentOS: KPI doanh thu, tab theo trạng thái, drawer tiến trình Tạo đơn → Thanh toán → Cấp quyền → Tư vấn; "Hoàn tiền" đơn đã thanh toán, "Huỷ đơn" đơn chờ thanh toán (ghi chú ≥ 10 ký tự). Tab "Dịch vụ theo chuyên gia" có doanh thu từng dịch vụ |
| `/payouts` | Ví & rút tiền chuyên gia: KPI (số dư có thể rút, đang giữ, đã chi trả tháng này, phí nền tảng 10%); yêu cầu rút ≤ 5.000.000đ tự chi trả, lớn hơn cần admin "Đánh dấu đã chuyển" (mã giao dịch) hoặc "Từ chối" (lý do); tab ví từng chuyên gia |
| `/ads` | Quảng cáo cửa hàng hiển thị thành thẻ "Được tài trợ" trên bảng tin app: tạo/sửa chiến dịch (xem trước thẻ), tạm dừng/chạy lại, lượt hiển thị, lượt bấm, CTR, chi tiêu |
| **AI & tri thức** | |
| `/knowledge` | Tài liệu cho chatbot RAG: duyệt/từ chối tài liệu chuyên gia gửi (chỉ tài liệu đã duyệt mới được AI dùng), xem trước các đoạn (chunk), tải tài liệu WHO, xoá |
| `/ai-models` | Độ chính xác kiểm duyệt (cờ AI so với quyết định admin), độ chính xác theo nhãn; bật/tắt mô hình, đổi phiên bản/ngưỡng (bắt buộc ghi chú kiểm toán) |
| `/telemetry` | Giám sát mô hình AI: độ trễ, lỗi, live `ai_logs`; bấm một dòng để xem input/output và gắn nhãn Đúng/Sai. `?task=` |

## Đăng nhập & phân quyền

- `src/middleware.ts` chuyển mọi route chưa đăng nhập về `/login?next=…`, và chỉ cho quay lại đường dẫn nội bộ.
- `POST /auth/login` trả `AuthResponse { accessToken, refreshToken, expiresAt, user }`. Console chỉ nhận khi `user.role === "Admin"`, rồi gửi `Authorization: Bearer <token>` cho mọi request. Gặp 401 thì xoá phiên và quay về trang đăng nhập.
- Phiên lưu trong cookie `vl_admin_session` (SameSite=Strict, 8 giờ). Khi lên production, nên chuyển sang cookie HttpOnly do BE hoặc một route handler của Next cấp.

## Khớp với backend

- Mọi response được bóc lớp `ApiResponse<T> { success, message, data, statusCode }` (xem `unwrapEnvelope` trong `src/lib/api_client.ts`).
- Enum C# (`UserStatusEnum`, `AuthTypeEnum`) được nhận cả dạng số lẫn dạng chuỗi (`normalizeUser` trong `src/lib/admin_api.ts`).
- Vai trò theo sơ đồ SQL: `Admin` / `User` / `Chef`; giá trị cũ `Member` và giá trị lạ được đọc thành `User`.
- ID: sơ đồ SQL dùng `INT`, FE luôn giữ id dạng chuỗi (`readId`) và gửi lại dạng số khi là số (`apiId` trong `src/lib/ids.ts`).
- Tên trường JSON = camelCase của tên cột SQL (`media_type` → `mediaType`, `transaction_ref` → `transactionRef`…).

BE hiện mới có `UsersController` (`GET/PUT/DELETE /api/v1/users`). **Chưa có `POST /auth/login`** nên khi tắt mock sẽ không đăng nhập được. Mọi endpoint còn lại BE cần thêm:

| Nhóm | Endpoint (dưới `/api/v1`) | File mô tả |
|---|---|---|
| Đăng nhập | POST `/auth/login` | `admin_api.ts` |
| Người dùng | GET `/users`, DELETE `/users/{id}` (**đã có**); PATCH `/users/{id}/role`, PATCH `/users/{id}/status` | `admin_api.ts` |
| Tổng quan, chuyên gia, danh mục | GET `/admin/overview`; `/admin/chef-applications…`; GET/POST/PATCH/DELETE `/admin/catalog` | `admin_api.ts` |
| Nội dung | GET `/admin/posts?view=&kind=&search=`, POST `/admin/posts/{id}/actions`, POST `/admin/posts/{id}/review`, DELETE `/admin/posts/{id}` | `admin_api.ts` |
| Bình luận | GET `/admin/comments?view=&search=&authorId=&postId=`, POST `/admin/comments/{id}/actions`, DELETE `/admin/comments/{id}` | `admin_api.ts` |
| Kiểm duyệt & AI | `/admin/moderation/flags…`, GET `/admin/ai/metrics?range=`, GET/PATCH `/admin/ai/models[/{id}]`, GET `/admin/ai/logs[/{id}]`, POST `/admin/ai/logs/{id}/label` | `api_client.ts` |
| Tri thức (RAG) | GET `/admin/knowledge-docs?source=&status=&search=`, `/counts`, `/{id}/chunks`; POST `/admin/knowledge-docs`, `/{id}/review`; DELETE `/{id}` | `knowledge_api.ts` |
| Đơn hàng | GET `/admin/commerce/summary`, GET `/admin/orders?status=&type=&search=`, GET `/admin/orders/{id}`, POST `/admin/orders/{id}/refund\|cancel`, GET `/admin/services?chefId=&search=` | `commerce_api.ts` |
| Rút tiền | GET `/admin/payouts/summary`, GET `/admin/withdrawals?status=&search=`, POST `/admin/withdrawals/{id}/complete\|reject`, GET `/admin/chef-wallets`, GET `/admin/chef-wallets/{chefId}/transactions` | `payouts_api.ts` |
| Quán chay | GET `/admin/restaurants?certified=&source=&search=`, PATCH/DELETE `/admin/restaurants/{id}`, GET `/admin/restaurants/{id}/reviews`, DELETE `/admin/reviews/{id}` | `restaurants_api.ts` |
| Quảng cáo | GET/POST `/admin/ads`, PATCH/DELETE `/admin/ads/{id}`, POST `/admin/ads/{id}/pause\|resume`; app gọi GET `/ads/feed?city=&lat=&lng=&limit=`, POST `/ads/{id}/impression\|click` | `ads_api.ts` |

Kiểu dữ liệu nằm trong `src/types/` (`admin`, `moderation`, `knowledge`, `ai_models`, `commerce`, `restaurants`, `payouts`, `ads`).

**Chênh lệch với sơ đồ SQL 26 bảng** (cần BE/ERD bổ sung):
- Chưa có bảng: bình luận, báo cáo, danh mục/thẻ, hồ sơ xin làm chuyên gia, nhật ký quản trị, ví/giao dịch ví/yêu cầu rút/tài khoản ngân hàng (`wallets`, `wallet_transactions`, `withdrawal_requests`, `bank_accounts`), chiến dịch quảng cáo (`ad_campaigns`).
- Thiếu cột: `ai_logs` (model, độ trễ, token, trạng thái, nhãn), `ai_flags` (điểm theo hạng mục, trạng thái), `posts` (`hidden`, `pinned`, `updated_at`), `restaurants` (`latitude`, `longitude`), `orders.refunded_at`.
- `moderation_decisions` chỉ có Approve/Reject; `/moderation` còn dùng "Cảnh cáo" và "Chuyển cấp trên".

## Cấu trúc

```
src/
├── middleware.ts                 # chặn route khi chưa đăng nhập admin
├── app/
│   ├── login/page.tsx
│   ├── (admin)/                  # sidebar + header (user menu, đăng xuất)
│   │   ├── overview/ users/ chefs/ content/ comments/ moderation/ restaurants/ catalog/
│   │   ├── orders/ payouts/ ads/ knowledge/ ai-models/ telemetry/
│   └── layout.tsx, globals.css   # font, QueryClient, Toaster, token màu
├── components/
│   ├── ui/                       # button, card, badge, table, sheet, dialog, switch, tabs, form-controls, sonner
│   ├── admin/                    # sidebar, user-menu, page-header, states, initials-avatar
│   ├── overview/ users/ chefs/ content/ comments/ moderation/ restaurants/ catalog/
│   ├── orders/ payouts/ ads/ knowledge/ ai-models/ telemetry/
├── lib/
│   ├── api_client.ts             # request(), envelope, Bearer, moderation/telemetry/AI models API
│   ├── admin_api.ts              # auth, users, chef applications, content, comments, catalog, overview
│   ├── knowledge_api.ts, commerce_api.ts, payouts_api.ts, restaurants_api.ts, ads_api.ts
│   ├── ids.ts                    # readId / apiId (INT ↔ chuỗi)
│   ├── auth.ts                   # cookie phiên admin
│   ├── mock_*.ts                 # backend mô phỏng theo từng nhóm
│   └── hooks/                    # TanStack Query (cập nhật lạc quan, polling)
└── types/
```

## Thử nhanh (mock)

- Dữ liệu mock nằm trong bộ nhớ trình duyệt, tải lại trang là về dữ liệu ban đầu.
- Thêm `#fail` vào ô ghi chú/lý do để xem đường lỗi 503 (toast + hoàn tác): lý do khoá tài khoản, ghi chú duyệt chuyên gia, ghi chú kiểm duyệt, ghi chú duyệt/từ chối bài, lý do xoá bình luận, ghi chú đổi mô hình AI, ghi chú gắn nhãn log, ghi chú duyệt tài liệu, tiêu đề tài liệu WHO, ghi chú hoàn tiền/huỷ đơn, mã chuyển khoản/lý do từ chối rút tiền, tiêu đề quảng cáo, và các ô tìm kiếm ở `/orders`, `/restaurants`, `/payouts`, `/ads`.
- Bản ghi dùng để thử hoàn tác khi không có ô chữ: quán **"Quán thử nghiệm QA #fail"** (bật/tắt chứng nhận, xoá) và chiến dịch `ad_qa_fail` (tạm dừng, chạy lại, sửa, xoá) luôn trả 503.
- Lỗi nghiệp vụ: ghi chú < 10 ký tự → 400; xử lý lại bài/tài liệu/yêu cầu đã quyết → 409; đổi vai trò của Chef → 409 `chef_role_locked`; ghim bài chưa đăng → 409; hoàn tiền đơn chưa thanh toán → 409 `not_paid`; huỷ đơn không ở trạng thái chờ → 409 `not_pending`; chạy lại chiến dịch đã kết thúc → 409 `ended`.
- Dữ liệu mẫu đáng chú ý: bài chờ duyệt `p_me_pending_celery`, `p_detox_tea`, `p_flan`; tài liệu chờ duyệt `kd_tam_2`, `kd_thu_ha_2`, `kd_chau_1`; yêu cầu rút `wd_tam_3` (5.100.000đ, cần duyệt) và `wd_ha_3` (tự chuyển sau ~3 phút); mô hình quét ảnh mới có 7 nhãn nên hiện "Chưa đủ nhãn".
- Mở tài khoản của chính bạn ở `/users` để thấy các thao tác nguy hiểm bị khoá.
- `/catalog`: thêm một mã đã có (ví dụ `main`) sẽ báo trùng; mục đang được dùng thì không xoá được, chỉ tắt.
