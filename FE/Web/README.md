# VeganLife Web — Admin console (Next.js 15)

**Chỉ dành cho ban quản trị.** Người dùng (khách, thành viên, chuyên gia) dùng ứng dụng di động trong `FE/Mobile`. Web không có trang nào cho thành viên: mọi route đều phải đăng nhập bằng tài khoản vai trò `Admin`. Tài khoản `User`/`Chef` (và giá trị cũ `Member`) bị từ chối và được hướng sang app.

Stack: App Router, TypeScript strict, Tailwind CSS v4, component kiểu shadcn/ui, TanStack Query v5, Lucide. UI tiếng Việt.

## Chạy

```bash
cd FE/Web
npm install
npm run dev        # http://localhost:3000 → /login → /overview
```

Khi dùng dữ liệu mô phỏng (mặc định), đăng nhập bằng `admin@veganlife.vn` / `admin123`. Thử `minhanh.nguyen@gmail.com` (mật khẩu bất kỳ, ≥ 6 ký tự) để xem màn hình chặn tài khoản thành viên.

`npm run build` chạy luôn type-check và lint. Font tự host (`@fontsource-variable/*`).

## Cấu hình (`.env.local`)

```bash
NEXT_PUBLIC_USE_MOCK_DATA=true                       # false → chế độ kết hợp, xem bên dưới
NEXT_PUBLIC_API_BASE_URL=http://localhost:5001/api/v1  # cổng trong BE launchSettings.json
NEXT_PUBLIC_REAL_MODULES=                            # thêm module thật, ví dụ comments,ads
NEXT_PUBLIC_MOCK_MODULES=                            # đưa module về mock, ví dụ content
```

Biến `NEXT_PUBLIC_*` được gắn vào bản build, nên đổi giá trị phải build lại (biến môi trường của shell thắng `.env.local`).

## Chế độ kết hợp (`NEXT_PUBLIC_USE_MOCK_DATA=false`)

Mọi công tắc nằm trong `src/lib/backend_modules.ts` (`isMock("users")`). Tên module: `auth, users, content, comments, chefs, catalog, overview, moderation, telemetry, aiModels, knowledge, commerce, bookings, payouts, restaurants, ads`. Module `auth` là mock thì mọi module đều mock. Nếu một module nằm ở cả hai danh sách thì nó là mock.

| Module | Khi tắt mock | Ghi chú |
|---|---|---|
| `auth` | Thật: POST `/auth/login` | **BE đang chặn Admin** (lỗi B2: trả 403 cho mọi tài khoản Admin). Form hiện "Máy chủ chưa cho phép tài khoản quản trị đăng nhập. Hãy báo nhóm BE." Tài khoản thành viên đăng nhập được ở BE nhưng bị console từ chối |
| `users` | Thật: GET `/users`, DELETE `/users/{id}` | Lọc và tìm ở phía client. Nút đổi vai trò và trạng thái bị khoá ("Máy chủ chưa hỗ trợ thao tác này."). BE không có số bài viết, số báo cáo, hoạt động gần nhất nên hiện "—" |
| `content` | Thật: GET `/posts?page&pageSize=50` (lặp đến hết `totalPages`), DELETE `/posts/{id}` | BE chỉ trả bài đã đăng, nên các tab Chờ duyệt, Bị báo cáo, Đã ẩn, Bị từ chối luôn trống. Ẩn, ghim, duyệt, chạy lại AI bị khoá. Drawer có liên kết "Xem tệp đính kèm" (URL tương đối được ghép origin của API) |
| Các module còn lại | Vẫn mock, hoạt động như cũ | BE chưa có route `/admin/*` tương ứng. Liên kết từ trang mock sang bài mock (`/content?open=p_…`) sẽ báo "Không tìm thấy bài viết" |

Nhãn ở header: "Dữ liệu mô phỏng" (toàn mock), "Kết hợp: máy chủ + mô phỏng" (một phần thật), "Production" (toàn bộ thật).

Lỗi từ BE luôn hiện tiếng Việt: dùng `message` của envelope, rồi `errors` của ProblemDetails, rồi thông báo theo mã HTTP. `title` của ProblemDetails là tiếng Anh nên không hiển thị.

**Chưa thử được với BE thật:** danh sách và xoá của `users`, `content` khi đăng nhập admin, vì B2 chặn admin. Sau khi BE thêm `POST /auth/admin/login`, đổi đường dẫn trong `authApi.login` (`src/lib/admin_api.ts`), đặt role Admin cho một tài khoản thử trên DB thử rồi kiểm tra lại hai module này.

## Màn hình

| Route | Việc admin làm |
|---|---|
| `/login` | Đăng nhập; chỉ vai trò Admin được vào |
| `/overview` | KPI, hàng đợi cần xử lý (cờ AI, bài chờ duyệt, hồ sơ chuyên gia, tài liệu chờ duyệt, **khiếu nại chờ xử lý**, yêu cầu rút tiền, bài bị báo cáo, video AI lỗi), đăng ký mới 14 ngày, nhật ký quản trị |
| **Người dùng** | |
| `/users` | Tìm/lọc theo vai trò Quản trị viên / Thành viên / Chuyên gia và trạng thái; đổi vai trò User ↔ Admin (vai trò Chef bị khoá, chỉ đổi qua duyệt chuyên gia); tạm khoá, cấm (bắt buộc lý do), mở khoá; xoá (gõ email). Drawer có liên kết "Bài viết & video" và "Bình luận" của người đó. Không thể tự khoá hay tự hạ quyền |
| `/chefs` | Duyệt hồ sơ "Trở thành chuyên gia" gửi từ app; duyệt xong vai trò thành `Chef`; từ chối phải có ghi chú |
| **Nội dung** | |
| `/content` | Bài **Công thức** và **Hỏi đáp** (ảnh hoặc video là tệp đính kèm; `type: "video"` cũ đọc thành Công thức có video). Lọc loại: Công thức / Hỏi đáp / **Có video**; drawer hiện "Gắn quán: …". Tab **Chờ duyệt** (bài AI gắn cờ, kèm lý do và điểm AI → "Duyệt & đăng" / "Từ chối" có ghi chú ≥ 10 ký tự) và **Bị từ chối**; ẩn/hiện, ghim (tối đa 3), xoá, chạy lại AI cho video lỗi. `?open=<id>`, `?author=<userId>`, `?kind=recipe\|discussion\|video` |
| `/comments` | Bình luận: Tất cả / Bị báo cáo / Đã ẩn; phản hồi hiện "↳ Trả lời {tên}" (một cấp, `parentId`); ẩn/hiện, xoá (lý do tuỳ chọn — xoá bình luận gốc xoá luôn các phản hồi), "Mở bài viết". Lọc `?author=`, `?post=` |
| `/moderation` | Hàng đợi cờ AI, xem chi tiết, quyết định kèm ghi chú kiểm toán |
| `/restaurants` | Quán chay (do admin thêm hoặc người dùng gợi ý từ app): bật/tắt "Chứng nhận thuần chay", ảnh & video của quán, toạ độ kèm "Xem trên OpenStreetMap", xem/xoá đánh giá, xoá quán |
| `/catalog` | Danh mục món, thẻ chế độ ăn, chất gây dị ứng (kèm nhãn AI quét), chuyên môn chuyên gia — thêm, đổi tên, bật/tắt, xoá khi chưa dùng |
| **Kinh doanh** | |
| `/orders` | Chỉ còn **thanh toán đặt chuyên gia** (thiết kế thực đơn N ngày) qua PaymentOS: KPI doanh thu / chờ thanh toán / đã hoàn / đang giữ, tab theo trạng thái (thêm "Hoàn một phần"), cột loại "Đặt chuyên gia" kèm mã đặt, drawer tiến trình Tạo hợp đồng → Thanh toán → Giữ tiền → Giao kế hoạch → Giải ngân / Hoàn tiền và liên kết sang `/disputes`. Chỉ "Huỷ đơn" đơn chờ thanh toán (ghi chú ≥ 10 ký tự); hoàn tiền làm ở `/disputes`. `?open=<orderId>` |
| `/disputes` | **Khiếu nại & giữ tiền**: KPI (tiền đang giữ, sẽ giải ngân trong 3 ngày, đang tạm giữ do khiếu nại, phí nền tảng tháng này); tab Chờ xử lý / Đã xử lý / Tiền đang giữ. Drawer: hồ sơ hợp đồng, dòng thời gian giữ tiền, các ngày kế hoạch đã giao + phản hồi, lịch sử trao đổi (chỉ xem), nội dung khiếu nại, bằng chứng (liên kết mở tab mới, ảnh thu nhỏ), phản hồi của chuyên gia. "Ra quyết định": Chuyển toàn bộ cho chuyên gia / Hoàn toàn bộ cho thành viên / Hoàn một phần (1.000đ ≤ X < giá) với xem trước "Thành viên nhận lại X · Chuyên gia nhận (giá − X) × 90 % = Y · Phí nền tảng Z", ghi chú ≥ 20 ký tự. `?open=<complaintId>`, `?booking=<bookingId>`, `?tab=open\|resolved\|holds` |
| `/payouts` | Ví & rút tiền chuyên gia: KPI (số dư có thể rút, đang giữ, đã chi trả tháng này, phí nền tảng 10%); tiền đặt chuyên gia **đang giữ đến 3 ngày sau khi kế hoạch kết thúc**, khoản bị khiếu nại hiện "Tạm giữ do khiếu nại" (liên kết `/disputes`); yêu cầu rút ≤ 5.000.000đ tự chi trả, lớn hơn cần admin "Đánh dấu đã chuyển" (mã giao dịch) hoặc "Từ chối" (lý do); tab ví từng chuyên gia |
| `/ads` | Quảng cáo cửa hàng: **một dòng "Được tài trợ" ở đầu danh sách Quán chay gần bạn** trong app (tối đa 1 quán mỗi lần, `placement: "nearby"`; không còn trên bảng tin). Tạo/sửa chiến dịch (xem trước dòng trong danh sách), tạm dừng/chạy lại, lượt hiển thị, lượt bấm, CTR, chi tiêu |
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

Danh sách dưới đây là hợp đồng đầy đủ mà console cần. BE hiện chỉ có phần nêu ở mục "Chế độ kết hợp"; mọi endpoint còn lại BE cần thêm:

| Nhóm | Endpoint (dưới `/api/v1`) | File mô tả |
|---|---|---|
| Đăng nhập | POST `/auth/login` (**đã có**, nhưng chặn Admin) | `admin_api.ts` |
| Người dùng | GET `/users`, DELETE `/users/{id}` (**đã có**); PATCH `/users/{id}/role`, PATCH `/users/{id}/status` | `admin_api.ts` |
| Tổng quan, chuyên gia, danh mục | GET `/admin/overview`; `/admin/chef-applications…`; GET/POST/PATCH/DELETE `/admin/catalog` | `admin_api.ts` |
| Nội dung | GET `/admin/posts?view=&kind=recipe\|discussion&hasVideo=true&search=` (bài có `restaurant` gắn kèm), POST `/admin/posts/{id}/actions`, POST `/admin/posts/{id}/review`, DELETE `/admin/posts/{id}` | `admin_api.ts` |
| Bình luận | GET `/admin/comments?view=&search=&authorId=&postId=` (mỗi dòng có `parentId`, `replyTo`, `replyCount`), POST `/admin/comments/{id}/actions`, DELETE `/admin/comments/{id}` | `admin_api.ts` |
| Kiểm duyệt & AI | `/admin/moderation/flags…`, GET `/admin/ai/metrics?range=`, GET/PATCH `/admin/ai/models[/{id}]`, GET `/admin/ai/logs[/{id}]`, POST `/admin/ai/logs/{id}/label` | `api_client.ts` |
| Tri thức (RAG) | GET `/admin/knowledge-docs?source=&status=&search=`, `/counts`, `/{id}/chunks`; POST `/admin/knowledge-docs`, `/{id}/review`; DELETE `/{id}` | `knowledge_api.ts` |
| Đơn hàng | GET `/admin/commerce/summary`, GET `/admin/orders?status=&search=`, GET `/admin/orders/{id}`, POST `/admin/orders/{id}/cancel` (đã bỏ `/refund` và `/admin/services`) | `commerce_api.ts` |
| Khiếu nại & giữ tiền | GET `/admin/complaints?status=Open\|Resolved&search=`, GET `/admin/complaints/{id}`, POST `/admin/complaints/{id}/decision { decision, refundAmount?, note }`, GET `/admin/escrow/summary`, GET `/admin/escrow/holds?status=&search=` | `bookings_api.ts` |
| Rút tiền | GET `/admin/payouts/summary`, GET `/admin/withdrawals?status=&search=`, POST `/admin/withdrawals/{id}/complete\|reject`, GET `/admin/chef-wallets`, GET `/admin/chef-wallets/{chefId}/transactions` | `payouts_api.ts` |
| Quán chay | GET `/admin/restaurants?certified=&source=&search=` (kèm `media`), PATCH/DELETE `/admin/restaurants/{id}`, GET `/admin/restaurants/{id}/reviews`, DELETE `/admin/reviews/{id}` | `restaurants_api.ts` |
| Quảng cáo | GET/POST `/admin/ads`, PATCH/DELETE `/admin/ads/{id}`, POST `/admin/ads/{id}/pause\|resume`; app gọi GET `/ads/feed?placement=nearby&city=&lat=&lng=&limit=1`, POST `/ads/{id}/impression\|click` | `ads_api.ts` |

Kiểu dữ liệu nằm trong `src/types/` (`admin`, `moderation`, `knowledge`, `ai_models`, `commerce`, `bookings`, `restaurants`, `payouts`, `ads`). `types/bookings.ts` có mẫu JSON đầy đủ (BookingDto, OfferDto, ContractDto, ComplaintDto, PlanDayDto, escrow) dùng chung với app di động.

**Chênh lệch với sơ đồ SQL 26 bảng** (cần BE/ERD bổ sung):
- Chưa có bảng: bình luận (`comments` + `parent_id`), báo cáo, danh mục/thẻ, hồ sơ xin làm chuyên gia, nhật ký quản trị, ví/giao dịch ví/yêu cầu rút/tài khoản ngân hàng (`wallets`, `wallet_transactions`, `withdrawal_requests`, `bank_accounts`), chiến dịch quảng cáo (`ad_campaigns` + `placement`), ảnh/video quán (`restaurant_media`), đặt chuyên gia (`chef_bookings`, `booking_offers`, `booking_messages`, `booking_contracts`, `booking_plan_days`, `booking_plan_meals`, `booking_day_feedback`), giữ tiền và khiếu nại (`escrow_holds`, `booking_complaints`, `complaint_evidence`).
- Thiếu cột: `ai_logs` (model, độ trễ, token, trạng thái, nhãn), `ai_flags` (điểm theo hạng mục, trạng thái), `posts` (`hidden`, `pinned`, `updated_at`, `restaurant_id`; `type` chỉ còn `recipe\|discussion`), `restaurants` (`latitude`, `longitude`), `orders` (`booking_id`, `refunded_at`; `service_id` cho phép NULL; trạng thái thêm `PartiallyRefunded`), `wallet_transactions` (`booking_id`; trạng thái `Held`, `Frozen` thay `Pending`).
- Không còn dùng: `services`, `consultations`, quyền truy cập (access grants), `chef_meal_suggestions`.
- `moderation_decisions` chỉ có Approve/Reject; `/moderation` còn dùng "Cảnh cáo" và "Chuyển cấp trên".

## Cấu trúc

```
src/
├── middleware.ts                 # chặn route khi chưa đăng nhập admin
├── app/
│   ├── login/page.tsx
│   ├── (admin)/                  # sidebar + header (user menu, đăng xuất)
│   │   ├── overview/ users/ chefs/ content/ comments/ moderation/ restaurants/ catalog/
│   │   ├── orders/ disputes/ payouts/ ads/ knowledge/ ai-models/ telemetry/
│   └── layout.tsx, globals.css   # font, QueryClient, Toaster, token màu
├── components/
│   ├── ui/                       # button, card, badge, table, sheet, dialog, switch, tabs, form-controls, sonner
│   ├── admin/                    # sidebar, user-menu, page-header, states, initials-avatar
│   ├── overview/ users/ chefs/ content/ comments/ moderation/ restaurants/ catalog/
│   ├── orders/ disputes/ payouts/ ads/ knowledge/ ai-models/ telemetry/
├── lib/
│   ├── backend_modules.ts        # công tắc mock/thật theo từng module
│   ├── api_client.ts             # request(), envelope, Bearer, lỗi tiếng Việt, moderation/telemetry/AI models API
│   ├── admin_api.ts              # auth, users, chef applications, content, comments, catalog, overview
│   ├── knowledge_api.ts, commerce_api.ts, bookings_api.ts, payouts_api.ts, restaurants_api.ts, ads_api.ts
│   ├── ids.ts                    # readId / apiId (INT ↔ chuỗi)
│   ├── auth.ts                   # cookie phiên admin
│   ├── mock_*.ts                 # backend mô phỏng theo từng nhóm (mock_bookings.ts là nguồn chung của /disputes, /orders, /payouts)
│   └── hooks/                    # TanStack Query (cập nhật lạc quan, polling)
└── types/
```

## Thử nhanh (mock)

- Dữ liệu mock nằm trong bộ nhớ trình duyệt, tải lại trang là về dữ liệu ban đầu.
- Thêm `#fail` vào ô ghi chú/lý do để xem đường lỗi 503 (toast + hoàn tác): lý do khoá tài khoản, ghi chú duyệt chuyên gia, ghi chú kiểm duyệt, ghi chú duyệt/từ chối bài, lý do xoá bình luận, ghi chú đổi mô hình AI, ghi chú gắn nhãn log, ghi chú duyệt tài liệu, tiêu đề tài liệu WHO, ghi chú huỷ đơn, **ghi chú quyết định khiếu nại**, mã chuyển khoản/lý do từ chối rút tiền, tiêu đề quảng cáo, và các ô tìm kiếm ở `/orders`, `/disputes`, `/restaurants`, `/payouts`, `/ads`.
- Bản ghi dùng để thử hoàn tác khi không có ô chữ: quán **"Quán thử nghiệm QA #fail"** (bật/tắt chứng nhận, xoá) và chiến dịch `ad_qa_fail` (tạm dừng, chạy lại, sửa, xoá) luôn trả 503.
- Lỗi nghiệp vụ: ghi chú < 10 ký tự → 400; xử lý lại bài/tài liệu/yêu cầu đã quyết → 409; đổi vai trò của Chef → 409 `chef_role_locked`; ghim bài chưa đăng → 409; huỷ đơn không ở trạng thái chờ → 409 `not_pending`; ghi chú quyết định khiếu nại < 20 ký tự → 400 `note_too_short`; hoàn một phần < 1.000đ hoặc ≥ giá → 400 `invalid_refund_amount`; quyết định khiếu nại `cp_qa_409` → 409 `already_decided` (mô phỏng quản trị viên khác đã xử lý trước, sau đó dòng chuyển sang "Đã xử lý"); chạy lại chiến dịch đã kết thúc → 409 `ended`.
- Đặt chuyên gia (id trùng với mock di động): Minh Anh `b_ma_tam_nego` (đang thoả thuận, chưa có đơn), `b_ma_thuha_active` (`ord_601`, đang giữ), `b_ma_tam_done` (`ord_602`, đã giải ngân 2 ngày trước); Lê Quang Tâm `b_nam_tam_req` (chờ báo giá), `b_vy_tam_active` (`ord_603`, ngày hôm nay còn nháp), `b_tram_tam` + khiếu nại **`cp_tram_tam`** (ảnh hưởng sức khoẻ, 1 liên kết + 1 ảnh, `ord_604` tạm giữ), `b_han_tam_done` (`ord_605`, đã giải ngân). Chỉ có trên web: khiếu nại chờ `cp_an_khoa` (hoàn toàn bộ, chưa có phản hồi chuyên gia), `cp_qa_409`; đã xử lý `cp_huy_ha` (hoàn một phần 400.000đ), `cp_bao_chau` (hoàn toàn bộ); `b_linh_lan` sẽ tự giải ngân trong 3 ngày; `ord_614` chờ thanh toán (thử "Huỷ đơn"), `ord_615` quá hạn. Ví Lê Quang Tâm: có thể rút 110.000đ (sau yêu cầu rút 5.100.000đ đang chờ), đang giữ 1.134.000đ, tạm giữ 945.000đ; quyết định `cp_tram_tam` cập nhật ví và đơn `ord_604` ngay.
- Mục tiêu của yêu cầu đặt chuyên gia (drawer `/disputes`) dùng mã mục tiêu trong hồ sơ sức khoẻ của app: `lose_weight` Giảm cân, `maintain` Giữ cân, `lean_muscle` Tăng cơ, `gain_weight` Tăng cân, cộng `eat_clean` Ăn lành mạnh (`gain_muscle` là mã cũ, đọc là Tăng cơ). Mã lạ hiện nguyên văn.
- Bài gắn quán trùng mock di động: `p_video_cha_lua` → Quán Chay An Lạc (`rs_an_lac`), `p_checkin_hanh_tam` → Bún Riêu Chay Hạnh Tâm (`rs_hanh_tam`). Phản hồi bình luận mẫu: `c_02`, `c_26` trả lời `c_01`; `c_07`, `c_27` trả lời `c_06`…
- Dữ liệu mẫu đáng chú ý: bài chờ duyệt `p_me_pending_celery`, `p_detox_tea`, `p_flan`; tài liệu chờ duyệt `kd_tam_2`, `kd_thu_ha_2`, `kd_chau_1`; yêu cầu rút `wd_tam_3` (5.100.000đ, cần duyệt) và `wd_ha_3` (tự chuyển sau ~3 phút); mô hình quét ảnh mới có 7 nhãn nên hiện "Chưa đủ nhãn".
- Mở tài khoản của chính bạn ở `/users` để thấy các thao tác nguy hiểm bị khoá.
- `/catalog`: thêm một mã đã có (ví dụ `main`) sẽ báo trùng; mục đang được dùng thì không xoá được, chỉ tắt (có hộp xác nhận); xoá mục chưa dùng cũng phải xác nhận.
