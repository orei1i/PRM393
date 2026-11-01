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
NEXT_PUBLIC_USE_MOCK_DATA=true                       # false → chế độ kết hợp với BE thật, xem bên dưới
NEXT_PUBLIC_API_BASE_URL=http://localhost:5001/api/v1  # cổng trong BE launchSettings.json
NEXT_PUBLIC_REAL_MODULES=                            # thêm module thật, ví dụ comments,ads
NEXT_PUBLIC_MOCK_MODULES=                            # đưa module về mock, ví dụ content
```

Biến `NEXT_PUBLIC_*` được gắn vào bản build, nên đổi giá trị phải build lại (biến môi trường của shell thắng `.env.local`).

## Chế độ kết hợp (`NEXT_PUBLIC_USE_MOCK_DATA=false`)

Mọi công tắc nằm trong `src/lib/backend_modules.ts` (`isMock("users")`). Tên module: `auth, users, content, comments, chefs, catalog, overview, moderation, telemetry, aiModels, knowledge, commerce, bookings, payouts, restaurants, ads`. Module `auth` là mock thì mọi module đều mock. Nếu một module nằm ở cả hai danh sách thì nó là mock.

| Module | Khi tắt mock | Ghi chú |
|---|---|---|
| `auth` | Thật: POST `/auth/admin/login`, `/auth/refresh`, `/auth/logout` | Tài khoản khác Admin bị BE trả 403 và form báo "không có quyền quản trị". Xem mục Đăng nhập |
| `users` | Thật: GET `/users`, PUT `/users/{id}`, DELETE `/users/{id}` | Lọc và tìm ở phía client (BE không nhận tham số). Drawer có form sửa họ tên và số điện thoại. PUT bỏ qua `role`, `status` và BE không có route khoá, nên nút đổi vai trò và trạng thái bị khoá ("Máy chủ chưa hỗ trợ thao tác này."). BE không có số bài viết, số báo cáo, hoạt động gần nhất nên hiện "—". Ẩn liên kết "Bình luận" khi `comments` còn mock |
| `content` | Thật: GET `/admin/posts?status=&page&pageSize=50` (lặp đến hết `totalPages`), POST `/admin/posts/{id}/review`, POST `/admin/posts/{id}/actions` | Chỉ còn tab Tất cả, Chờ duyệt, Bị từ chối: BE không trả số báo cáo, không có trạng thái Đã ẩn và không ghim được. Chờ duyệt gồm bài đủ 3 báo cáo và bài quản trị viên ẩn (ẩn = về `Pending`). Duyệt, từ chối (lý do ≥ 10 ký tự), ẩn và hoàn tác ẩn, khôi phục bài bị từ chối, xoá. Lý do từ chối lưu ở BE nhưng chưa endpoint nào trả về. Drawer có liên kết "Xem tệp đính kèm" (URL tương đối được ghép origin của API) |
| Các module còn lại | Vẫn mock, hoạt động như cũ | BE chưa có route `/admin/*` tương ứng. Duyệt quán, luồng tiền và ví đều thuộc nhóm này: chỉ chạy trên dữ liệu mô phỏng, cả ở bản mặc định lẫn bản kết hợp. Liên kết từ trang mock sang bài mock (`/content?open=p_…`) sẽ báo "Không tìm thấy bài viết" |

Nhãn ở header theo từng trang: "Dữ liệu máy chủ" (module của trang là thật), "Dữ liệu mô phỏng" (trang dùng mock), "Production" (toàn bộ thật). Số đếm ở sidebar lấy từ các module còn mock.

Lỗi từ BE luôn hiện tiếng Việt: dùng `message` của envelope, rồi `errors` của ProblemDetails, rồi thông báo theo mã HTTP. `title` của ProblemDetails là tiếng Anh nên không hiển thị. Một số `message` của BE bị lỗi mã hoá (đăng nhập, `UsersController`), nên `withStatusText` trong `src/lib/admin_api.ts` thay bằng chữ của app theo mã HTTP (401, 403 khi đăng nhập; 404 khi sửa, xoá người dùng). Xoá hàm này khi BE sửa xong.

### Chạy với BE thật

BE chạy ở cổng 5001 (`BE/ControllerLayer`, xem `launchSettings.json`). Không cần sửa `.env.local`, biến môi trường của shell thắng:

```powershell
$env:NEXT_PUBLIC_USE_MOCK_DATA = "false"; npm run dev
```

```bash
NEXT_PUBLIC_USE_MOCK_DATA=false npm run dev
```

Đăng nhập bằng tài khoản admin dev trong `BE/TAI_LIEU_API_CHO_FRONTEND.md` mục 10.1 (tạo bởi `DatabaseSeeder`). Mỗi lần đăng nhập, kể cả từ máy khác, BE chỉ giữ một refresh token cho mỗi tài khoản, nên phiên trước sẽ hết khi access token của nó hết hạn.

## Màn hình

| Route | Việc admin làm |
|---|---|
| `/login` | Đăng nhập; chỉ vai trò Admin được vào |
| `/overview` | KPI, hàng đợi cần xử lý (cờ AI, bài chờ duyệt, hồ sơ chuyên gia, **quán chờ duyệt**, tài liệu chờ duyệt, **khiếu nại chờ xử lý**, yêu cầu rút tiền, bài bị báo cáo, video AI lỗi), đăng ký mới 14 ngày, nhật ký quản trị |
| **Người dùng** | |
| `/users` | Tìm/lọc theo vai trò Quản trị viên / Thành viên / Chuyên gia và trạng thái; đổi vai trò User ↔ Admin (vai trò Chef bị khoá, chỉ đổi qua duyệt chuyên gia); tạm khoá, cấm (bắt buộc lý do), mở khoá; xoá (gõ email). Drawer có liên kết "Bài viết & video" và "Bình luận" của người đó, và ở bản mock có mục **Ví** (nhãn "Dữ liệu mô phỏng", ẩn khi `users` là thật vì id không khớp). Không thể tự khoá hay tự hạ quyền |
| `/chefs` | Duyệt hồ sơ "Trở thành chuyên gia" gửi từ app; duyệt xong vai trò thành `Chef`; từ chối phải có ghi chú |
| **Nội dung** | |
| `/content` | Bài **Công thức** và **Hỏi đáp** (ảnh hoặc video là tệp đính kèm; `type: "video"` cũ đọc thành Công thức có video). Lọc loại: Công thức / Hỏi đáp / **Có video**; drawer hiện "Gắn quán: …". Tab **Chờ duyệt** (bài mới và bài đã sửa theo quy định mới, cùng bài AI gắn cờ kèm lý do và điểm AI → "Duyệt & đăng" / "Từ chối" có ghi chú ≥ 10 ký tự; BE thật hiện vẫn đăng bài mới ngay nên tab này chỉ có bài đủ 3 báo cáo hoặc bị ẩn) và **Bị từ chối**; ẩn/hiện, ghim (tối đa 3), xoá, chạy lại AI cho video lỗi. `?open=<id>`, `?author=<userId>`, `?kind=recipe\|discussion\|video` |
| `/comments` | Bình luận: Tất cả / Bị báo cáo / Đã ẩn; phản hồi hiện "↳ Trả lời {tên}" (một cấp, `parentId`); ẩn/hiện, xoá (lý do tuỳ chọn — xoá bình luận gốc xoá luôn các phản hồi), "Mở bài viết". Lọc `?author=`, `?post=` |
| `/moderation` | Hàng đợi cờ AI, xem chi tiết, quyết định kèm ghi chú kiểm toán |
| `/restaurants` | Quán chay (do admin thêm hoặc người dùng gợi ý từ app). Tab trạng thái **Chờ duyệt** (mặc định) / Đã duyệt / Bị từ chối / Tất cả, kèm người gợi ý, ngày, địa chỉ, toạ độ, ảnh & video. **Duyệt**, **Từ chối** (bắt buộc lý do ≤ 500 ký tự), đổi lại quyết định được. Chứng nhận thuần chay là bước riêng, chỉ quán đã duyệt mới bật được; từ chối quán sẽ bỏ chứng nhận. Toạ độ kèm "Xem trên OpenStreetMap", xem/xoá đánh giá, xoá quán. `/ads` chỉ chọn được quán đã duyệt |
| `/catalog` | Danh mục món, thẻ chế độ ăn, chất gây dị ứng (kèm nhãn AI quét), chuyên môn chuyên gia — thêm, đổi tên, bật/tắt, xoá khi chưa dùng |
| **Kinh doanh** | |
| `/orders` | Chỉ còn **thanh toán đặt chuyên gia** (thiết kế thực đơn N ngày) qua PaymentOS hoặc ví: KPI doanh thu / chờ thanh toán / đã hoàn / đang giữ, tab theo trạng thái (thêm "Hoàn một phần"), cột loại "Đặt chuyên gia" kèm mã đặt, drawer tiến trình Tạo hợp đồng → Thanh toán → Giữ tiền → Giao kế hoạch → Chuyên gia xác nhận hoàn thành (hoặc Hệ thống tự hoàn tất) → Vào ví chuyên gia / Hoàn vào ví thành viên, có "Đặt cho" (gia đình · N người · dị ứng) và dòng "Tiền đang ở" và liên kết sang `/disputes`. Chỉ "Huỷ đơn" đơn chờ thanh toán (ghi chú ≥ 10 ký tự); hoàn tiền làm ở `/disputes`. `?open=<orderId>` |
| `/disputes` | **Khiếu nại & giữ tiền**: KPI (tiền đang giữ, sẽ giải ngân trong 3 ngày, đang tạm giữ do khiếu nại, **kẹt cần Ban quản trị xử lý**, phí nền tảng tháng này); tab Chờ xử lý / Đã xử lý / Tiền đang giữ (cột xác nhận hoàn thành hoặc "Hệ thống tự hoàn tất", hạn giữ, tiền đang ở; bộ lọc "Kẹt, cần Ban quản trị xử lý"; dòng kẹt có nút **Xử lý**: xem đã giao bao nhiêu ngày, giá, hai bên và mỗi cách trả bao nhiêu cho mỗi bên rồi mới lưu). Drawer: hồ sơ hợp đồng, dòng thời gian giữ tiền, các ngày kế hoạch đã giao + phản hồi, lịch sử trao đổi (chỉ xem), nội dung khiếu nại, bằng chứng (liên kết mở tab mới, ảnh thu nhỏ), phản hồi của chuyên gia. "Ra quyết định": Chuyển toàn bộ cho chuyên gia / Hoàn toàn bộ cho thành viên / Hoàn một phần (1.000đ ≤ X < giá) với xem trước "Ví thành viên nhận X · Ví chuyên gia nhận (giá − X) × 90 % = Y · Phí nền tảng Z", ghi chú ≥ 20 ký tự. Tiền hoàn vào ví của thành viên. `?open=<complaintId>`, `?booking=<bookingId>`, `?tab=open\|resolved\|holds` |
| `/payouts` | Ví & rút tiền của **chuyên gia và thành viên**: KPI (số dư có thể rút theo vai trò, đang giữ, đã chi trả tháng này, phí nền tảng 10%); bộ lọc vai trò và nhãn vai trò trên mỗi dòng. **Mọi yêu cầu rút đều chờ admin**: "Duyệt & đánh dấu đã chuyển" (mã giao dịch) hoặc "Từ chối" (lý do ≥ 10 ký tự, tiền trở lại ví), cùng quy tắc cho cả hai vai trò; tab Ví. `?tab=wallets&q=<tên>` |
| `/ads` | Quảng cáo cửa hàng: **một dòng "Được tài trợ" ở đầu danh sách Quán chay gần bạn** trong app (tối đa 1 quán mỗi lần, `placement: "nearby"`; không còn trên bảng tin). Tạo/sửa chiến dịch (xem trước dòng trong danh sách), tạm dừng/chạy lại, lượt hiển thị, lượt bấm, CTR, chi tiêu |
| **AI & tri thức** | |
| `/knowledge` | Tài liệu cho chatbot RAG: duyệt/từ chối tài liệu chuyên gia gửi (chỉ tài liệu đã duyệt mới được AI dùng), xem trước các đoạn (chunk), tải tài liệu WHO, xoá |
| `/ai-models` | Độ chính xác kiểm duyệt (cờ AI so với quyết định admin), độ chính xác theo nhãn; bật/tắt mô hình, đổi phiên bản/ngưỡng (bắt buộc ghi chú kiểm toán) |
| `/telemetry` | Giám sát mô hình AI: độ trễ, lỗi, live `ai_logs`; bấm một dòng để xem input/output và gắn nhãn Đúng/Sai. `?task=` |

## Luồng tiền (mock)

Đây là quy tắc nghiệp vụ. Hiện chỉ có trên dữ liệu mô phỏng vì BE chưa có API.

1. Thành viên thanh toán qua PaymentOS hoặc **bằng ví** (`provider: "Wallet"`, trả đủ, sổ ví có dòng `Payment` số âm), **tiền vào VeganLife** (giữ tiền `Held`, chưa có ngày giải ngân).
2. Chuyên gia giao kế hoạch rồi **xác nhận hoàn thành** trong app, hợp đồng hoàn thành (`completedAt`, đặt chuyên gia `Ended`). Chỉ xác nhận được khi **đã giao đủ mọi ngày và hôm nay (giờ VN) từ ngày kết thúc trở đi**, sớm hơn thì 409 `plan_not_delivered`.
3. Tiền giữ **7 ngày kể từ lúc hoàn thành** (`releaseAt = completedAt + 7 ngày`, `ESCROW_HOLD_DAYS`).
4. Hết 7 ngày, không có khiếu nại: **tiền vào ví chuyên gia** sau phí 10% (`Released`, đặt chuyên gia `Completed`).
5. Khiếu nại lúc đang giữ (kể cả trước khi xác nhận): tiền bị **tạm giữ** (`Frozen`) đến khi admin quyết định ở `/disputes`. Quyết định cho thành viên thì **tiền hoàn vào ví thành viên** (không hoàn qua PaymentOS); chia một phần thì phần còn lại vào ví chuyên gia sau phí.
6. Chuyên gia hoặc thành viên yêu cầu rút, **admin duyệt** ở `/payouts` (không còn tự chi trả ≤ 5.000.000đ).

**Chuyên gia không xác nhận:** lúc 23:59 (giờ VN) của ngày kết thúc + 3 ngày, đặt chuyên gia đang `Held` đã giao đủ mọi ngày và không có khiếu nại mở sẽ **tự hoàn tất**: `completedAt` là đúng lúc đó, `autoCompleted: true`, đặt chuyên gia `Ended`, rồi giữ 7 ngày như thường và vào ví chuyên gia. Web ghi "Hệ thống tự hoàn tất" kèm ngày. Khiếu nại mở thì không tự hoàn tất. **Thiếu ngày lúc đó thì cũng không**, kể cả khi ngày đó được gửi sau: tiền vẫn `Held` (xem "Khoản kẹt").

**Khoản kẹt** (`isStuck`): `escrow.status == Held`, `completedAt == null`, `releaseAt == null`, không có khiếu nại `Open`, và đã qua lúc tự hoàn tất. Chuyên gia xác nhận hoặc thành viên khiếu nại thì hết kẹt như thường; hai đường đó còn mở đến khi admin quyết định. Bảng "Tiền đang giữ" ghi rõ lý do: "Thiếu N ngày nên không tự hoàn tất · cần Ban quản trị xem xét", hoặc "Giao đủ sau {lúc tự hoàn tất} nên không tự hoàn tất · cần Ban quản trị xem xét".

`POST /admin/escrow/holds/{id}/resolve { decision, refundAmount?, note }` trả về EscrowHoldDto. Tiền giống quyết định khiếu nại, ghi chú ≥ 20 ký tự, `resolvedBy` là tên admin, `resolutionNote` là ghi chú, có tin nhắn hệ thống cho hai bên, đơn có `resolution.action = "admin_resolve"`:

| Quyết định | Giữ tiền | Ví | Đặt chuyên gia | Đơn |
|---|---|---|---|---|
| `ReleaseToChef` | `Released`, `releasedAt`, `releasedAmount` = giá, `feeAmount` 10 % | Chuyên gia + 90 % | `Completed`, `completedAt` nếu chưa có | `Paid` |
| `RefundMember` | `Refunded`, `refundedAt` | Thành viên + toàn bộ giá | `Cancelled`, `cancelReason` = ghi chú | `Refunded` |
| `Split` (1.000đ ≤ X < giá) | `PartiallyRefunded`, `refundedAt`, `releasedAt` | Thành viên + X, chuyên gia + (giá − X) × 90 % | `Completed`, `completedAt` nếu chưa có | `PartiallyRefunded` |

Lỗi: 400 `note_too_short`, 400 `invalid_refund_amount`, 404, 409 `not_stuck` (cả khoản đã quyết định). Sau đó `/complete` trả 409 `not_active`, khiếu nại trả 409 `not_open`. `resolvedBy` khác null mà không có khiếu nại là admin xử lý; thành viên tự huỷ thì `resolvedBy` null. QA: `#fail` trong ghi chú → 503, `#409` → một admin khác xử lý trước.

**Huỷ sau khi thanh toán:** thành viên huỷ được khi chưa nhận ngày nào: đặt chuyên gia `Cancelled`, giữ tiền và đơn `Refunded`, toàn bộ giá vào ví thành viên. Đã nhận ngày nào thì chỉ còn khiếu nại (409 `plan_started`).

**Đặt cho gia đình:** `audience: "Family"`, `familySize` 2–20, `goal` null, không có hồ sơ sức khoẻ. `/disputes` và `/orders` hiện "Gia đình · N người" kèm dị ứng. Dòng cũ không có `audience` đọc là `Self`.

Xác nhận hoàn thành và huỷ diễn ra trong app, nên trên web chỉ có ở dữ liệu mẫu (`confirmedAt`, `cancelledAfterPay`). Khoản chưa hoàn thành hiện "Chưa có ngày". Quy tắc tự hoàn tất chạy trong `settle` của `mock_bookings.ts`, mỗi lần đọc, và chỉ tính ngày đã gửi trước lúc đó, nên đọc muộn hay đọc đúng giờ đều ra cùng kết quả.

Mẫu để xem: `b_giang_lan_auto` (tự hoàn tất, đang giữ), `b_khanh_minh_auto` (tự hoàn tất, đã vào ví), `b_an_chau_short` (kẹt: giao thiếu 3 ngày), `b_linh_khoa_late` (kẹt: giao đủ nhưng 2 ngày sau lúc tự hoàn tất), `b_chau_tam_ready` (gia đình 3 người, chờ tự hoàn tất), `b_yen_ha_cancel` (huỷ sau khi thanh toán), `b_yen_lan_wallet` + `wd_yen_1` (trả bằng ví, sổ ví ở drawer yêu cầu rút).

## Khi máy chủ trả lỗi

Trang không được trắng và không được kẹt. Có ba lớp, từ ngoài vào:

- **`request()` trong `api_client.ts`:** lỗi mạng, hết 20 giây không trả lời, ngắt giữa chừng, body không phải JSON, envelope `success: false` đều thành `ApiError` tiếng Việt. Không hiện `message` của 5xx (có thể là nội dung exception). `requestList` / `requestObject` báo "dữ liệu không hợp lệ" khi body sai dạng (`bad_response`).
- **Normaliser (`wire.ts`):** điền đủ mọi trường cho mỗi dòng, sai kiểu thì dùng giá trị mặc định. Dòng không có id bị bỏ (không thao tác được). Ngày hỏng hoặc thiếu hiện "—": mọi formatter ngày đều qua `dateFormat` trong `utils.ts`, không dùng `Intl.DateTimeFormat` trần vì nó ném `RangeError` khi render.
- **Error boundary (lưới cuối):** `(admin)/error.tsx` giữ sidebar và thay vùng trang, `error.tsx` cho `/login` và layout, `global-error.tsx` khi root layout hỏng, `not-found.tsx`. Đều có "Thử lại" và đúng giọng văn của app.

React Query chỉ thử lại một lần với lỗi mạng và 5xx. Lỗi 4xx hoặc hết giờ thì báo ngay. 401 thì refresh một lần; bị từ chối mới về `/login?next=…` và chỉ chuyển trang một lần dù nhiều request cùng lỗi. Refresh gặp 5xx, 429, mất mạng hoặc dữ liệu hỏng thì giữ phiên và báo lỗi.

## Đăng nhập & phân quyền

- `src/middleware.ts` chuyển mọi route chưa đăng nhập về `/login?next=…`, và chỉ cho quay lại đường dẫn nội bộ.
- `POST /auth/admin/login` trả `AuthResponse { accessToken, refreshToken, expiresAt, user }` và chỉ nhận vai trò `Admin` (khác → 403). Console gửi `Authorization: Bearer <token>` cho mọi request.
- Access token sống 60 phút. Gặp 401, `request()` gọi `POST /auth/refresh` một lần (dùng chung trong tab, Web Lock giữa các tab vì refresh token chỉ dùng được một lần) rồi gửi lại request. Phiên chỉ kết thúc khi BE từ chối refresh token; mất mạng, 5xx hoặc 429 khi refresh thì giữ phiên và báo lỗi. Hết phiên thì về `/login?next=…`.
- Đăng xuất gọi `POST /auth/logout` (tối đa 3 giây, lỗi vẫn đăng xuất). Access token đã hết hạn thì refresh trước để BE thu hồi được refresh token.
- Phiên lưu trong cookie `vl_admin_session` (SameSite=Strict, 8 giờ tính từ lần làm mới gần nhất), gồm cả refresh token, và JavaScript đọc được. Khi lên production, nên chuyển sang cookie HttpOnly do BE hoặc một route handler của Next cấp.

## Khớp với backend

- Mọi response được bóc lớp `ApiResponse<T> { success, message, data, statusCode }` (xem `unwrapEnvelope` trong `src/lib/api_client.ts`).
- Enum C# (`UserStatusEnum`, `AuthTypeEnum`) được nhận cả dạng số lẫn dạng chuỗi (`normalizeUser` trong `src/lib/admin_api.ts`).
- Vai trò theo sơ đồ SQL: `Admin` / `User` / `Chef`; giá trị cũ `Member` và giá trị lạ được đọc thành `User`.
- ID: sơ đồ SQL dùng `INT`, FE luôn giữ id dạng chuỗi (`readId`) và gửi lại dạng số khi là số (`apiId` trong `src/lib/ids.ts`).
- Tên trường JSON = camelCase của tên cột SQL (`media_type` → `mediaType`, `transaction_ref` → `transactionRef`…).

Danh sách dưới đây là hợp đồng đầy đủ mà console cần. BE hiện chỉ có phần nêu ở mục "Chế độ kết hợp" (ghi **đã có** dưới đây); mọi endpoint còn lại BE cần thêm:

| Nhóm | Endpoint (dưới `/api/v1`) | File mô tả |
|---|---|---|
| Đăng nhập | POST `/auth/admin/login`, `/auth/refresh`, `/auth/logout` (**đã có**) | `admin_api.ts`, `api_client.ts` |
| Người dùng | GET `/users`, PUT `/users/{id}` (họ tên, số điện thoại), DELETE `/users/{id}` (**đã có**); PATCH `/users/{id}/role`, PATCH `/users/{id}/status` | `admin_api.ts` |
| Tổng quan, chuyên gia, danh mục | GET `/admin/overview`; `/admin/chef-applications…`; GET/POST/PATCH/DELETE `/admin/catalog` | `admin_api.ts` |
| Nội dung | GET `/admin/posts?status=Pending\|Published\|Rejected&page&pageSize`, POST `/admin/posts/{id}/review { decision, reason? }`, POST `/admin/posts/{id}/actions { action: hide\|unhide\|restore\|delete, reason? }` (**đã có**); còn thiếu: số báo cáo, lý do từ chối, ghim, lọc `kind`/`search` ở BE | `admin_api.ts` |
| Bình luận | GET `/admin/comments?view=&search=&authorId=&postId=` (mỗi dòng có `parentId`, `replyTo`, `replyCount`), POST `/admin/comments/{id}/actions`, DELETE `/admin/comments/{id}` | `admin_api.ts` |
| Kiểm duyệt & AI | `/admin/moderation/flags…`, GET `/admin/ai/metrics?range=`, GET/PATCH `/admin/ai/models[/{id}]`, GET `/admin/ai/logs[/{id}]`, POST `/admin/ai/logs/{id}/label` | `api_client.ts` |
| Tri thức (RAG) | GET `/admin/knowledge-docs?source=&status=&search=`, `/counts`, `/{id}/chunks`; POST `/admin/knowledge-docs`, `/{id}/review`; DELETE `/{id}` | `knowledge_api.ts` |
| Đơn hàng | GET `/admin/commerce/summary`, GET `/admin/orders?status=&search=`, GET `/admin/orders/{id}`, POST `/admin/orders/{id}/cancel` (đã bỏ `/refund` và `/admin/services`) | `commerce_api.ts` |
| Khiếu nại & giữ tiền | GET `/admin/complaints?status=Open\|Resolved&search=`, GET `/admin/complaints/{id}`, POST `/admin/complaints/{id}/decision { decision, refundAmount?, note }`, GET `/admin/escrow/summary`, GET `/admin/escrow/holds?status=active\|stuck\|…&search=` (`completedAt`, `releaseAt` có thể null, `isStuck`), POST `/admin/escrow/holds/{id}/resolve { decision, refundAmount?, note }` (chưa có ở BE) | `bookings_api.ts` |
| Ví & rút tiền | GET `/admin/payouts/summary`, GET `/admin/withdrawals?status=&role=&search=`, POST `/admin/withdrawals/{id}/complete\|reject`, GET `/admin/wallets`, GET `/admin/wallets/{userId}/transactions` | `payouts_api.ts` |
| Quán chay | GET `/admin/restaurants?status=Pending\|Approved\|Rejected&certified=&source=&search=` (kèm `media`, `status`, `rejectionReason`, `createdAt`, `reviewedAt`), POST `/admin/restaurants/{id}/review { decision, reason? }`, PATCH (409 khi chưa duyệt)/DELETE `/admin/restaurants/{id}`, GET `/admin/restaurants/{id}/reviews`, DELETE `/admin/reviews/{id}` | `restaurants_api.ts` |
| Quảng cáo | GET/POST `/admin/ads`, PATCH/DELETE `/admin/ads/{id}`, POST `/admin/ads/{id}/pause\|resume`; app gọi GET `/ads/feed?placement=nearby&city=&lat=&lng=&limit=1`, POST `/ads/{id}/impression\|click` | `ads_api.ts` |

Kiểu dữ liệu nằm trong `src/types/` (`admin`, `moderation`, `knowledge`, `ai_models`, `commerce`, `bookings`, `restaurants`, `payouts`, `ads`). `types/bookings.ts` có mẫu JSON đầy đủ (BookingDto, OfferDto, ContractDto, ComplaintDto, PlanDayDto, escrow) dùng chung với app di động.

**Chênh lệch với sơ đồ SQL 26 bảng** (cần BE/ERD bổ sung):
- Chưa có bảng: bình luận (`comments` + `parent_id`), báo cáo, danh mục/thẻ, hồ sơ xin làm chuyên gia, nhật ký quản trị, ví của cả chuyên gia và thành viên/giao dịch ví/yêu cầu rút/tài khoản ngân hàng (`wallets`, `wallet_transactions`, `withdrawal_requests`, `bank_accounts`), chiến dịch quảng cáo (`ad_campaigns` + `placement`), ảnh/video quán (`restaurant_media`), đặt chuyên gia (`chef_bookings`, `booking_offers`, `booking_messages`, `booking_contracts`, `booking_plan_days`, `booking_plan_meals`, `booking_day_feedback`), giữ tiền và khiếu nại (`escrow_holds`, `booking_complaints`, `complaint_evidence`).
- Thiếu cột: `ai_logs` (model, độ trễ, token, trạng thái, nhãn), `ai_flags` (điểm theo hạng mục, trạng thái), `posts` (`hidden`, `pinned`, `updated_at`, `restaurant_id`; `type` chỉ còn `recipe\|discussion`), `restaurants` (`latitude`, `longitude`, `status`, `rejection_reason`, `reviewed_at`, `reviewed_by`, `created_at`), `orders` (`booking_id`, `refunded_at`; `service_id` cho phép NULL; trạng thái thêm `PartiallyRefunded`), `wallet_transactions` (`booking_id`; trạng thái `Held`, `Frozen` thay `Pending`).
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
│   ├── api_client.ts             # request(), envelope, Bearer, refresh token, lỗi tiếng Việt, moderation/telemetry/AI models API
│   ├── admin_api.ts              # auth, users, chef applications, content, comments, catalog, overview
│   ├── knowledge_api.ts, commerce_api.ts, bookings_api.ts, payouts_api.ts, restaurants_api.ts, ads_api.ts
│   ├── ids.ts                    # readId / apiId (INT ↔ chuỗi)
│   ├── auth.ts                   # cookie phiên admin (access + refresh token)
│   ├── mock_*.ts                 # backend mô phỏng theo từng nhóm (mock_bookings.ts là nguồn chung của /disputes, /orders, /payouts)
│   └── hooks/                    # TanStack Query (cập nhật lạc quan, polling)
└── types/
```

## Thử nhanh (mock)

- Dữ liệu mock nằm trong bộ nhớ trình duyệt, tải lại trang là về dữ liệu ban đầu.
- Thêm `#fail` vào ô ghi chú/lý do để xem đường lỗi 503 (toast + hoàn tác): lý do khoá tài khoản, ghi chú duyệt chuyên gia, ghi chú kiểm duyệt, ghi chú duyệt/từ chối bài, lý do xoá bình luận, ghi chú đổi mô hình AI, ghi chú gắn nhãn log, ghi chú duyệt tài liệu, tiêu đề tài liệu WHO, ghi chú huỷ đơn, **ghi chú quyết định khiếu nại**, mã chuyển khoản/lý do từ chối rút tiền, lý do từ chối quán, tiêu đề quảng cáo, và các ô tìm kiếm ở `/orders`, `/disputes`, `/restaurants`, `/payouts`, `/ads`.
- Bản ghi dùng để thử hoàn tác khi không có ô chữ: quán **"Quán thử nghiệm QA #fail"** (đã duyệt: bật/tắt chứng nhận, từ chối, xoá), **"Quán gợi ý QA #fail"** (chờ duyệt: duyệt, từ chối) và chiến dịch `ad_qa_fail` (tạm dừng, chạy lại, sửa, xoá) luôn trả 503.
- Lỗi nghiệp vụ: ghi chú < 10 ký tự → 400; xử lý lại bài/tài liệu/yêu cầu đã quyết → 409; đổi vai trò của Chef → 409 `chef_role_locked`; ghim bài chưa đăng → 409; huỷ đơn không ở trạng thái chờ → 409 `not_pending`; ghi chú quyết định khiếu nại < 20 ký tự → 400 `note_too_short`; hoàn một phần < 1.000đ hoặc ≥ giá → 400 `invalid_refund_amount`; quyết định khiếu nại `cp_qa_409` → 409 `already_decided` (mô phỏng quản trị viên khác đã xử lý trước, sau đó dòng chuyển sang "Đã xử lý"); chạy lại chiến dịch đã kết thúc → 409 `ended`; chứng nhận quán chưa duyệt → 409 `not_approved` (nút đã khoá sẵn); từ chối quán không có lý do → 400 `reason_required`, quá 500 ký tự → 400 `reason_too_long`.
- Quán gợi ý mẫu: chờ duyệt `rs_ut_muoi` (2 ảnh + 1 video, chưa có toạ độ), `rs_goc_xanh` (có toạ độ), `rs_nha_la`, `rs_qa_pending`; bị từ chối `rs_u_rejected_demo` (trùng mock di động).
- Đặt chuyên gia (id trùng với mock di động): Minh Anh `b_ma_tam_nego` (đang thoả thuận, chưa có đơn), `b_ma_thuha_active` (`ord_601`, đang giữ), `b_ma_tam_done` (`ord_602`, xác nhận 9 ngày trước nên đã vào ví 2 ngày trước); Lê Quang Tâm `b_nam_tam_req` (chờ báo giá), `b_vy_tam_active` (`ord_603`, ngày hôm nay còn nháp), `b_tram_tam` + khiếu nại **`cp_tram_tam`** (ảnh hưởng sức khoẻ, 1 liên kết + 1 ảnh, đã xác nhận rồi mới khiếu nại, `ord_604` tạm giữ), `b_han_tam_done` (`ord_605`, đã giải ngân). Chỉ có trên web: khiếu nại chờ `cp_an_khoa` (hoàn toàn bộ, chưa có phản hồi chuyên gia, gửi khi chuyên gia chưa xác nhận hoàn thành), `cp_qa_409`; đã xử lý `cp_huy_ha` (hoàn một phần 400.000đ), `cp_bao_chau` (hoàn toàn bộ); `b_linh_lan` sẽ tự vào ví trong 2 ngày; `b_chi_lan_soon` tự vào ví khoảng 90 giây sau khi tải trang (bấm "Làm mới" để thấy); `ord_614` chờ thanh toán (thử "Huỷ đơn"), `ord_615` quá hạn. Ví Lê Quang Tâm: có thể rút 110.000đ (sau yêu cầu rút 5.100.000đ đang chờ), đang giữ 1.134.000đ, tạm giữ 945.000đ; quyết định `cp_tram_tam` cập nhật ví cả hai bên và đơn `ord_604` ngay. Ví thành viên: Phan Gia Bảo được hoàn 1.330.000đ (đã rút 200.000đ, `wd_bao_2` 1.000.000đ chờ duyệt, còn 130.000đ), Đức Huy được hoàn 400.000đ (`wd_huy_1` bị từ chối). Thành viên chỉ có ví khi đã được hoàn tiền hoặc đã gửi yêu cầu rút.
- Mục tiêu của yêu cầu đặt chuyên gia (drawer `/disputes`) dùng mã mục tiêu trong hồ sơ sức khoẻ của app: `lose_weight` Giảm cân, `maintain` Giữ cân, `lean_muscle` Tăng cơ, `gain_weight` Tăng cân, cộng `eat_clean` Ăn lành mạnh (`gain_muscle` là mã cũ, đọc là Tăng cơ). Mã lạ hiện nguyên văn.
- Bài gắn quán trùng mock di động: `p_video_cha_lua` → Quán Chay An Lạc (`rs_an_lac`), `p_checkin_hanh_tam` → Bún Riêu Chay Hạnh Tâm (`rs_hanh_tam`). Phản hồi bình luận mẫu: `c_02`, `c_26` trả lời `c_01`; `c_07`, `c_27` trả lời `c_06`…
- Dữ liệu mẫu đáng chú ý: bài chờ duyệt `p_me_pending_celery`, `p_detox_tea`, `p_flan`; tài liệu chờ duyệt `kd_tam_2`, `kd_thu_ha_2`, `kd_chau_1`; yêu cầu rút chờ duyệt `wd_tam_3` (5.100.000đ), `wd_ha_3` (400.000đ), `wd_bao_2` (thành viên, 1.000.000đ); mô hình quét ảnh mới có 7 nhãn nên hiện "Chưa đủ nhãn".
- Mở tài khoản của chính bạn ở `/users` để thấy các thao tác nguy hiểm bị khoá.
- `/catalog`: thêm một mã đã có (ví dụ `main`) sẽ báo trùng; mục đang được dùng thì không xoá được, chỉ tắt (có hộp xác nhận); xoá mục chưa dùng cũng phải xác nhận.
