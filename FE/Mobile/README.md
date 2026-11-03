# VeganLife Mobile (Flutter) — nền tảng chính

VeganLife là **mobile-first**: mọi hành trình của khách, thành viên và chuyên gia đều nằm trong app này. `FE/Web` chỉ là **admin console** để kiểm duyệt, xử lý khiếu nại và quản lý.

Feature-first Flutter, **Riverpod** cho state, **Dio** cho API. Feature nào cũng có abstract API service + **Mock repository**, nên app chạy được trước khi backend ASP.NET Core sẵn sàng. UI tiếng Việt.

## Điều hướng

Thanh dưới: **Trang chủ · Thực đơn · [Quét] · Chuyên gia · Tôi**. Mọi vai trò (thành viên, chuyên gia) có **cùng 5 vị trí**; công cụ của chuyên gia nằm trong **Tôi › Chuyên gia**.

| Vị trí | Màn hình | Khách xem được? |
|---|---|---|
| Trang chủ | Bảng tin cộng đồng, dải **Bếp nhanh** (video ngắn dọc), ô "Hôm nay {tên} nấu món gì?"; app bar có **Tìm kiếm** và **Quán chay gần bạn** | Xem: có · Tương tác: cần đăng nhập |
| Thực đơn | Thực đơn tuần theo "Các bữa trong ngày", "Chỉnh thực đơn với AI", **"Theo dõi cân nặng ›"** và thẻ **"Cập nhật cân nặng"** (khi đến hạn), thẻ **Nguyên liệu trong tủ**, thẻ **"Cần thực đơn riêng? Nhờ chuyên gia thiết kế"** | Cần đăng nhập |
| **Quét** (nút tròn giữa) | Chạm: quét tủ lạnh bằng cách đã dùng lần trước. Giữ: chọn **Chụp hình / Chọn ảnh / Nhập tay** (lựa chọn được nhớ). Mở toàn màn hình | Cần đăng nhập |
| Chuyên gia | Danh bạ đầu bếp / chuyên gia dinh dưỡng đã xác minh, hồ sơ và bảng giá, **Đặt chuyên gia lên thực đơn** | Xem: có · Đặt: cần đăng nhập |
| Tôi | Hồ sơ, Hồ sơ sức khoẻ (+ "Theo dõi cân nặng ›"), Nội dung của tôi, **Lịch sử tư vấn**, khu **Chuyên gia** (chỉ vai trò Chef), Thông tin cá nhân, Giao diện, Đăng xuất | Cần đăng nhập |
| Bong bóng **Hỏi AI** | Chat-head kiểu Messenger. Khi đứng yên chỉ là một dải mảnh 12×56dp sát mép (mặc định mép trái, ~38% chiều cao), nằm trong lề 16dp của màn hình nên không che nút nào; chạm vào dải là mở chatbot RAG có trích dẫn. Kéo ra thành bong bóng 56dp, thả là bám mép trái/phải gần nhất (nhớ vị trí), 1,5 giây sau tự thu lại thành dải. Giữ để "Ẩn bong bóng" / "Đưa về vị trí mặc định". Ẩn khi cuộn danh sách, khi bàn phím mở, trên hộp thoại và trên màn quét, Bếp nhanh, thanh toán, chat (màn nào bọc `AskAiBubbleFree` cũng ẩn). Trên Android 10+ vùng dải/bong bóng được loại khỏi cử chỉ vuốt "quay lại" (`setSystemGestureExclusionRects` qua MethodChannel `vn.veganlife/gesture_exclusion` trong `MainActivity.kt`). Khách hỏi miễn phí 3 lần (`GUEST_TRIAL_LIMIT`) | Có |

**Thanh tab nổi**: khối bo tròn cách mép 12dp, nằm trên vùng cử chỉ hệ thống; tab đang chọn có nền tô nhạt trượt theo; nút **Quét** tròn nằm trong phần khoét giữa thanh và nhô lên. Nội dung các tab cuộn phía sau thanh; khoảng trống cuối danh sách lấy từ `floatingBarClearance(context)` (`lib/core/widgets/floating_bar_clearance.dart`).

**Nút Back & quay về đúng chỗ** (`lib/core/navigation/`): Back của Android trên tab Thực đơn / Chuyên gia / Tôi → về **Trang chủ**; trên Trang chủ → thoát app. Mỗi tab giữ nguyên trạng thái khi quay lại.

- Không xếp chồng bản sao: mở lại một công thức, nguyên liệu, bài viết, quán hay yêu cầu đặt chuyên gia **đang mở bên dưới** thì quay về đúng trang đó (`AppNav.open`; tên trang trong `app_routes.dart`, ví dụ `/recipe/l5`, `/post/{id}`, `/restaurant/{id}`). Công thức ↔ nguyên liệu ("Công thức có nguyên liệu này") quay về trang đang mở; "Tìm video & quán liên quan" thay trang Tìm kiếm đang mở, không bao giờ có 2 trang Tìm kiếm.
- Luồng hoàn tất quay về đúng chỗ: "Gửi yêu cầu" đặt chuyên gia → trang yêu cầu ngay trên tab đã mở (Back một lần là về tab, kể cả khi đi từ thẻ "Nhờ chuyên gia" của Thực đơn); thanh toán xong "Lịch sử tư vấn" → một trang lịch sử duy nhất; "Khám phá chuyên gia" (lịch sử trống) → tab Chuyên gia; "Gửi toàn bộ kế hoạch" → về trang yêu cầu. "Áp dụng kế hoạch vào Thực đơn", "Thêm vào Thực đơn" ở trang công thức và "Thêm vào thực đơn" ở Quét đều có **"Xem Thực đơn"** mở tab Thực đơn (đúng ngày vừa thêm).

## Đăng nhập & tài khoản

- **Chỉ email + mật khẩu** (không có đăng nhập Google). Màn hình: **Welcome** → **Đăng nhập** / **Tạo tài khoản** / **Quên mật khẩu**.
- **Welcome** chỉ hiện ở lần mở đầu tiên khi chưa đăng nhập (`vl.onboarded`): "Đăng nhập", "Tạo tài khoản", "Khám phá không cần đăng nhập". Đăng xuất quay về Trang chủ ở chế độ khách, không về Welcome.
- **Đăng nhập**: "Email", "Mật khẩu" (hiện/ẩn), "Quên mật khẩu?", "Chưa có tài khoản? Đăng ký". Bản mock có chip **"Điền tài khoản thử nghiệm: Thành viên · Chuyên gia"**.
- **Tạo tài khoản**: "Bạn là" **Thành viên / Chuyên gia**, họ tên, email, số điện thoại (không bắt buộc), mật khẩu ≥ 8 ký tự gồm chữ và số, nhập lại, đồng ý điều khoản. `POST /auth/register` **luôn tạo vai trò `User`**; chọn Chuyên gia thì sau khi đăng ký mở "Bước 2/2: Hồ sơ chuyên gia". Vai trò thành `Chef` chỉ khi admin duyệt ở web `/chefs`; trong lúc chờ, Tôi hiện "Hồ sơ chuyên gia đang chờ duyệt".
- **Quên mật khẩu** (3 bước một màn): email → "Gửi mã" → nhập mã 6 số ("Gửi lại mã (0:59)") → "Mật khẩu mới" → "Đổi mật khẩu" → quay về Đăng nhập, email điền sẵn.
- **Khách** xem được bảng tin, chi tiết bài, Bếp nhanh, tìm kiếm, **chi tiết công thức** (chỉnh thử số người, đổi/bỏ nguyên liệu, xem năng lượng và đánh giá), quán chay (danh sách, bản đồ, chi tiết) và danh bạ chuyên gia. Mọi thao tác khác (thích, bình luận, lưu, báo cáo, đăng bài, đánh giá, gợi ý quán, lưu công thức đã chỉnh, thêm món vào Thực đơn, ghi chú công thức, đặt chuyên gia, Thực đơn, Quét, Tôi, câu hỏi AI thứ 4) mở sheet **"Tham gia cộng đồng VeganLife"** ("Đăng nhập" / "Tạo tài khoản" / "Để sau"); đăng nhập xong thao tác được làm tiếp.
- Phiên lưu trong `shared_preferences`: `vl.access_token`, `vl.refresh_token`, `vl.expires_at`, `vl.user_id`, `vl.role`, `vl.display_name`. **Production nên chuyển token sang secure storage** (`flutter_secure_storage` hoặc tương đương — thư viện mới, cần duyệt) và thêm luồng làm mới token.

### Tài khoản thử nghiệm (chỉ bản mock)

Nguồn duy nhất: `lib/core/session/mock_accounts.dart`.

| Tài khoản | Email | Mật khẩu | Kết quả |
|---|---|---|---|
| Minh Anh (Thành viên, `u_me`) | `minhanh.nguyen@gmail.com` | `minhanh2026` | Đăng nhập thành viên |
| Lê Quang Tâm (Chuyên gia, `u_chef_tam`) | `tam.chefchay@gmail.com` | `chefTam2026` | Đăng nhập chuyên gia đã xác minh |
| Trần Bảo Khoa (bị khoá) | `baokhoa.tran@gmail.com` | `baokhoa2026` | 423 "Tài khoản đang bị khoá. Liên hệ hỗ trợ." |
| Quản trị | `admin@veganlife.vn` | `admin2026` | 403 "Tài khoản quản trị chỉ dùng trên web quản trị." |
| Lỗi máy chủ | `loi.maychu@veganlife.vn` | bất kỳ | 503 |

- Sai mật khẩu → "Email hoặc mật khẩu không đúng."; **5 lần sai liên tiếp** cho một email → 429 "Bạn thử sai quá nhiều lần. Thử lại sau 5 phút." (khoá 5 phút).
- Mã đặt lại mật khẩu của mock: **`246810`** (màn hình cũng hiện "(Bản thử nghiệm) Mã xác minh: …"). Mã sống 10 phút, sai 3 lần → "Mã đã hết hiệu lực, hãy gửi lại mã". Đổi xong thì mật khẩu mới đăng nhập được, mật khẩu cũ không.
- Đăng ký bằng email đã có → 409 "Email này đã có tài khoản. Đăng nhập hoặc dùng email khác.". Tài khoản đăng ký mới chỉ sống trong bộ nhớ (mất khi khởi động lại app), dùng được cả 5 tab ngay.
- Dữ liệu mock giữ trong bộ nhớ suốt phiên chạy app, nên thao tác của tài khoản này thấy được ở tài khoản kia (Minh Anh gửi yêu cầu → đăng nhập Tâm thấy trong "Yêu cầu tư vấn").

## Splash & biểu tượng

Logo lá VeganLife (`VeganLifeMark` / `VeganLifeLogo` trong `lib/core/widgets/app_logo.dart`, vẽ bằng `CustomPainter`). Toàn bộ PNG (Android `mipmap-*`, adaptive icon, `splash_logo`, Android 12+ `android12splash`, iOS `AppIcon.appiconset`, `LaunchImage`) được sinh lại bằng:

```bash
flutter test tool/brand/render_brand_assets_test.dart
```

Nằm ngoài `test/` nên `flutter test` thường không chạy nó. iOS không kiểm tra được trên Windows.

## Tính năng

### Trang chủ (cộng đồng)

- Lọc **Tất cả · Công thức · Hỏi đáp · Có video**; dải Bếp nhanh chỉ hiện ở "Tất cả" và "Có video" (không có "Xem tất cả"). Không có thẻ "Được tài trợ" trên bảng tin hay trong chi tiết bài.
- Chỉ 2 loại bài: **Công thức** và **Hỏi đáp**. Ảnh hoặc video là **một tệp đính kèm** (`mediaType` Text/Image/Video + `mediaUrl`); bài cũ `type: "video"` đọc thành Công thức có video.
- **Thẻ bài**: dòng tác giả "· Công thức/Hỏi đáp" và "— tại {quán}" khi bài gắn quán, chip quán (tên · quận · ✓ chứng nhận) mở chi tiết quán. Chạm thân bài → chi tiết từ đầu; **"Bình luận"** → chi tiết, cuộn tới bình luận **và mở bàn phím**; **"N bình luận"** → cuộn tới bình luận, không mở bàn phím.
- **Chi tiết bài**: video phát ngay trong bài, **"Xem công thức"** (khi AI đã trích công thức) mở sheet Tóm tắt AI / Nguyên liệu / Các bước / Lời thoại, "Sao chép danh sách đi chợ", chạm mốc thời gian để tua video phía sau; chip trạng thái AI và "Thử trích xuất lại" (tác giả). Link trong nội dung bấm được. Video có nút phát/tạm dừng, thanh tua, thời gian, tắt tiếng, toàn màn hình; điều khiển tự ẩn sau 3 giây và hiện lại khi chạm.
- **Bình luận** ngay trong chi tiết bài (không còn trang bình luận riêng): mỗi lần tải 10 bình luận, **mới nhất trước**, tải thêm khi cuộn; mỗi bình luận gốc xem trước 2 phản hồi rồi "Xem thêm N phản hồi". Ô **"Viết bình luận…"** ghim ở đáy. Phản hồi **một cấp**: trả lời một phản hồi thì gắn vào cùng bình luận gốc và thêm "@Tên ". "Đang trả lời {tên} · Huỷ", "Đang sửa bình luận · Huỷ"; xoá bình luận gốc hỏi "Xoá bình luận và N phản hồi?". Bài chưa hiển thị trên bảng tin không nhận bình luận.
- **Bếp nhanh** (màn xem video dọc): "Bình luận" mở sheet bình luận (cùng luồng và ô viết), "Xem công thức" mở sheet công thức; không có nút Chia sẻ. Video dừng khi sheet mở.
- **Tạo bài viết** kiểu Facebook: "✕ · Tạo bài viết · Đăng" (sửa: "Sửa bài viết · Lưu"), Công thức / Hỏi đáp, tiêu đề ≤ 120, nội dung ≤ 3000, thanh **"Thêm vào bài viết"**: **Ảnh/Video** (ảnh jpg/png/webp/heic ≤ 10 MB, video mp4/mov/webm ≤ 200 MB; tiến độ "Đang tải lên 42 %", "Huỷ tải lên", "Thử lại", "Đổi"), **Gắn quán** (tìm + quán gần bạn), **Gắn thẻ**. "Đăng" bị khoá khi đang tải lên. AI chỉ trích công thức cho **Công thức + video**.
- **Trạng thái bài**: bài mới và bài sửa đều **Chờ duyệt** (chỉ tác giả thấy, kèm "bài sẽ hiển thị trên bảng tin sau khi Ban quản trị duyệt"); bản mock có "Duyệt thử" / "Từ chối thử" ngay trên banner để thử luồng. Admin duyệt → Đã đăng; từ chối → **Bị từ chối** kèm lý do và "Sửa & gửi lại". Với BE thật, app làm theo `status` máy chủ trả về (hôm nay BE trả `Published`). Admin ẩn bài → **Đã ẩn**: chỉ tác giả thấy, không thích, bình luận hay sửa được, vẫn xoá được, và chỉ admin mới bỏ ẩn. Trạng thái app chưa biết (hoặc thiếu) → **Chưa rõ trạng thái**: xử lý như bài chưa lên bảng tin, không bao giờ đọc thành "Đã đăng".
- **Nội dung của tôi** (Tôi): Bài của tôi (Tất cả / Đã đăng / Chờ duyệt / Bị từ chối / Đã ẩn, thêm "Chưa rõ trạng thái" khi có bài như vậy) · Đã lưu · Bình luận (mở bài và tô sáng đúng bình luận).

### Tìm kiếm

- **Chưa gõ**: Tìm gần đây ("Xoá lịch sử"), Xu hướng tìm kiếm (top 6), Danh mục (Món chính, Ăn sáng, Bún & phở, Đồ uống, Tráng miệng, Món nhanh < 20 phút), Món theo mùa, Công thức được yêu thích, Đã xem gần đây (`vl.recent_views`, tối đa 10, chỉ tính mục mở từ tìm kiếm), Quán chay gần bạn.
- **Đang gõ**: chỉ danh sách gợi ý (chờ 250 ms), dòng đầu "Tìm «…»"; chạm công thức / bài / quán là mở luôn.
- **Kết quả**: chỉ sau Enter hoặc "Tìm «…»": tab **Tất cả · Công thức · Video · Bài viết · Nguyên liệu · Quán**. Sửa chữ → quay lại gợi ý; ✕ → về trạng thái chưa gõ. Tìm không dấu.
- **BE thật**: tìm bằng `GET /search`, `/search/suggest`, `/search/discover`. Khách cũng tìm được công thức dùng chung; công thức riêng của người khác không hiện. BE chưa có lịch sử tìm kiếm và dữ liệu theo mùa nên Xu hướng và Món theo mùa không hiện; Công thức được yêu thích tính từ các thực đơn gần đây, chưa có thực đơn thì không hiện; Danh mục là các mục "Nhóm món" đang bật ở web `/catalog`. Với `BACKEND_MOCK_MODULES=search`, app tự tìm trên 250 bài mới nhất, công thức và nguyên liệu (`ClientSearchService`).

### Quán chay, bản đồ & chỉ đường

- **Quán chay gần bạn**: chip vị trí "📍 {nơi} ▾" → **"Chọn vị trí"**: một màn hình với ô tìm địa chỉ, "Dùng vị trí hiện tại (mô phỏng)", vị trí gần đây; nút nổi **"Tìm trên bản đồ"** góc dưới trái chuyển ngay màn đó sang bản đồ (kéo hoặc chạm để đặt ghim, "Dùng vị trí này"), quay lại bằng mũi tên, nút Back hoặc ô tìm trên bản đồ. Bản đồ nền lỗi vẫn chọn được điểm theo toạ độ. Ô tìm; **Bộ lọc** (chỉ quán đã chứng nhận thuần chay, sắp xếp Gần nhất / Đánh giá cao, bán kính 1 / 3 / 5 / 10 km / Không giới hạn, "Đặt lại" / "Áp dụng"); chip bộ lọc đang bật. **"Xem bản đồ" / "Xem danh sách"**: bản đồ có điểm của bạn, quán đã chứng nhận (xanh), quán khác (xám), quán tài trợ (có viền); chạm điểm → thẻ "Xem quán" / "Chỉ đường"; kéo bản đồ → "Tìm trong khu vực này". Đổi vị trí thì khoảng cách và thứ tự đổi ở mọi nơi (danh sách quán, tab Quán của tìm kiếm, gợi ý).
- **Được tài trợ**: tối đa **một** dòng ở đầu danh sách (và điểm nổi bật trên bản đồ); app gửi `POST /ads/{id}/impression` lần hiển thị đầu và `/click` khi bấm. Chiến dịch do admin quản lý ở web `/ads`.
- **Chi tiết quán**: bản đồ nhỏ 180dp (chạm → bản đồ lớn), "Ảnh & video", phân bố sao, "Viết đánh giá" (mỗi người 1 đánh giá, gửi lại là sửa). **"Chỉ đường"** vẽ tuyến trong app (OSRM, "2,6 km · ≈ 9 phút đi xe", "Từ: {nơi} · Đổi"); lỗi hoặc quá 5 giây → đường thẳng + "Không tải được tuyến đường — hiển thị đường thẳng". "Mở bằng Google Maps" chỉ ở menu ⋮ (OSRM không có dẫn đường từng bước). Quán chưa có toạ độ: "Quán chưa có vị trí trên bản đồ".
- **Gợi ý quán mới**: một nút "Chọn vị trí quán" mở màn Chọn vị trí, sau đó có "Đổi" / "Bỏ vị trí"; thiếu toạ độ thì cảnh báo; tối đa 5 ảnh và 1 video. Gợi ý **chờ Ban quản trị duyệt**, chưa hiện công khai. **"Quán tôi đã gợi ý"** (biểu tượng trên màn Quán chay gần bạn) cho xem Chờ duyệt / Đã duyệt / Bị từ chối kèm lý do; bản mock có "Duyệt thử" / "Từ chối thử".
- **Chính sách bản đồ**: ô bản đồ OpenStreetMap gửi `User-Agent` `vn.veganlife.veganlife_mobile`, có ghi công "© OpenStreetMap contributors", không tải hàng loạt. Máy chủ ô OSM công cộng không cho lưu lượng production nặng → đổi `MAP_TILE_URL`. OSRM demo công cộng chỉ có profile ô tô, ~1 request/giây, không SLA → app chỉ hỏi một lần mỗi màn chỉ đường, có cache; production nên dùng OSRM tự host (hoặc VietMap) sau BE. **Geocoding** đi qua BE (`/geo/search`, `/geo/reverse`), app không gọi thẳng Nominatim. "Dùng vị trí hiện tại" vẫn là **mô phỏng** (Quận 1) vì chưa duyệt thư viện GPS (`geolocator`).

### Thực đơn, tủ lạnh & hồ sơ sức khoẻ

- **Hồ sơ sức khoẻ**: chiều cao, cân nặng, **Giới tính** (Nam / Nữ; hồ sơ cũ ghi "Khác" thì không chọn sẵn, "Lưu" yêu cầu chọn), **Năm sinh** (13–100 tuổi, hiện "29 tuổi"), **Mức vận động** (Ít / Nhẹ / Vừa / Nhiều), mục tiêu (Giảm cân / Giữ cân / Tăng cơ / Tăng cân), **Dị ứng** là chip nhập tự do ("Nhập thành phần bạn dị ứng…", gợi ý không dấu từ `/catalog/allergens`, cho phép tên lạ như "lá lốt"), **Các bữa trong ngày** ("2 bữa", "3 bữa", "3 bữa + 1 phụ", "5 bữa nhỏ" hoặc tự chọn trong 6 bữa: Bữa sáng, Phụ sáng, Bữa trưa, Phụ chiều, Bữa tối, Phụ tối; ít nhất 1). Thẻ đầu hiện BMI và "Nhu cầu ≈ 1.900 kcal/ngày" (BMR/TDEE Mifflin–St Jeor; "Khác" lấy trung bình hai hằng số; mục tiêu −15 % / 0 / +5 % / +10 %). Mọi con số năng lượng (nhu cầu, BMR, mục tiêu ngày, tóm tắt gửi chuyên gia) tính từ một công thức trong `core/utils/energy.dart` và làm tròn **một lần** tới 10 kcal; lưu hồ sơ làm đổi mục tiêu thì tuần thực đơn hiện tại nhắm theo mục tiêu mới. **Tài khoản mới chưa có hồ sơ sức khoẻ**, thực đơn hay tủ lạnh: Thực đơn và Tôi hiện thẻ "Thiết lập hồ sơ sức khoẻ", form mở trống.
- **Thực đơn tuần**: bữa theo "Các bữa trong ngày"; **"＋ Thêm bữa"** thêm một bữa cho riêng ngày đó. Tạo bằng AI (kcal chia theo trọng số bữa từ TDEE), "Tự lên thực đơn" hoặc "Tạo thực đơn từ tủ lạnh". Chọn món từ **4 nguồn**: AI gợi ý (±10 % kcal, an toàn dị ứng) · Công thức của tôi · **Từ chuyên gia** (món của kế hoạch chuyên gia đã giao) · Tự nhập món; món thêm từ trang công thức mang nhãn **"Từ công thức"** (biến thể đã lưu: "Công thức của tôi"). Chạm thẻ món (hoặc "Xem công thức" trong sheet Đổi/Thêm bữa) mở công thức **so với mục tiêu của đúng bữa và ngày đó**, "Thêm vào Thực đơn" mặc định cũng là bữa đó. Macro không bịa: món thiếu macro thì ẩn, thẻ tổng ngày ước tính phần thiếu và ghi "≈".
- **Theo dõi cân nặng** (Thực đơn: "Theo dõi cân nặng ›" dưới thẻ sức khoẻ; Tôi › Hồ sơ sức khoẻ): thẻ **"Cập nhật cân nặng"** hiện trên Thực đơn khi đến hạn cân lại ("Mỗi tuần" = 7 ngày / "Mỗi tháng" = 30 ngày từ lần cân trước, chỉ khi đã có hồ sơ và thực đơn tuần này; "Để sau" ẩn tới hôm sau). Sheet check-in: cân nặng (30–250 kg, 1 chữ số thập phân), xem trước "BMI mới ≈ …", biểu đồ BMI có vùng xanh và số đang nhập. Lưu xong mở **"Tiến độ của bạn"**: cân nặng, BMI, mục tiêu năng lượng trước → sau, nhận xét theo mục tiêu ("Đúng hướng mục tiêu Giảm cân"…), cảnh báo khi giảm hơn 1 kg/tuần. Màn **Theo dõi cân nặng**: hiện tại + "30 ngày qua", khoảng cân nặng có BMI bình thường (chuẩn châu Á), biểu đồ **Cân nặng / BMI** theo **Tuần / Tháng / Tất cả** có dải BMI 18,5–22,9 (vẽ bằng `CustomPainter`), "Nhắc cập nhật cân nặng" (Mỗi tuần / Mỗi tháng), Lịch sử (sửa cân nặng trong Hồ sơ sức khoẻ cũng thêm một dòng "Từ Hồ sơ sức khoẻ"). Mỗi lần lưu cập nhật cân nặng, BMI, nhu cầu năng lượng của hồ sơ và mục tiêu của tuần thực đơn hiện tại.
- **"✨ Chỉnh thực đơn với AI"**: chat, gợi ý ("Ít tinh bột hơn cho bữa tối", "Thêm một bữa phụ chiều", "Thay các món có nấm", "Giảm còn 1.600 kcal/ngày", "Bữa sáng nhanh dưới 15 phút"), phạm vi "Hôm nay / Cả tuần"; AI trả **đề xuất** (danh sách thay đổi có ô chọn) → "Áp dụng thay đổi" / "Bỏ qua". Mọi món đề xuất đều thuần chay và tránh dị ứng.
- Thẻ **Nguyên liệu trong tủ** (số lượng + tên, "Xem tủ lạnh ›", "Tạo thực đơn từ tủ lạnh") và thẻ **"Cần thực đơn riêng? Nhờ chuyên gia thiết kế"** → danh bạ chuyên gia ở chế độ "Chọn chuyên gia" → hồ sơ → đặt.
- **Nguyên liệu trong tủ** (màn riêng, danh sách dọc): "Thêm nguyên liệu…" (chỉ thực phẩm thuần chay; món không thuần chay bị từ chối kèm "Gợi ý thay thế"), lọc Tất cả · Rau lá · Rau củ quả · Nấm · Đạm thực vật · Ngũ cốc · Hạt · Trái cây · Gia vị; mỗi dòng có hình minh hoạ (emoji trên nền màu theo nhóm), "18 kcal / 100 g · 1 quả ≈ 22 kcal", nguồn (Quét / Tự thêm); vuốt để xoá + "Hoàn tác"; "Xoá hết" trong menu; "Quét tủ lạnh", "Tạo thực đơn từ tủ lạnh".
- **Chi tiết nguyên liệu** (~35 nguyên liệu chay phổ biến): macro, vitamin/khoáng chất (%DV), "Phù hợp với", "Cần lưu ý / Không phù hợp với" (kèm cảnh báo dị ứng cá nhân), "Không nên dùng chung" (tham khảo), "Món gợi ý", "Công thức có nguyên liệu này", "Thêm vào tủ" / "Đã có trong tủ". Nguồn "Tham khảo: Bảng thành phần thực phẩm Việt Nam / USDA FoodData Central"; "Thông tin chỉ mang tính tham khảo, không thay thế tư vấn y tế".
- **Chi tiết công thức**: đầu trang (kcal "580 kcal / phần", đã chỉnh thì "≈ 514 kcal / phần"; macro; "Có chứa: …"; "★ 4,6 · 5 đánh giá"; "Tìm video & quán liên quan"), các tab **Nguyên liệu / Cách làm / Đánh giá** (Đánh giá chỉ có ở công thức công khai); nguyên liệu có trong CSDL dinh dưỡng mở chi tiết nguyên liệu.
  - **Nấu cho N người** (1–20, "Về {gốc} người"): chỉ đổi định lượng, làm tròn theo đơn vị (g ↔ kg, ml ↔ lít, quả/củ theo 0,5, tép/lá nguyên; "vừa ăn" giữ nguyên). Năng lượng mỗi phần không đổi; Thực đơn luôn tính 1 phần cho bạn.
  - **Đổi / bỏ nguyên liệu**: "Đổi" sang lựa chọn thay thế (gắn "Tránh được dị ứng …" / "Chứa …" theo dị ứng của bạn), ✕ bỏ nguyên liệu "Không bắt buộc"; "Hoàn tác", "Thêm lại", "Đặt lại". **Thành phần chính** (biểu tượng khoá, ví dụ phần riêu của Bún riêu chay) không bỏ được, chỉ đổi sang loại cùng vai trò.
  - **Năng lượng / Đảm bảo calo**: tính lại từ số liệu dinh dưỡng có sẵn của từng nguyên liệu, ghi **"≈"** khi đã chỉnh ("Mỗi phần: ≈ 514 kcal (gốc 580 kcal, −66)", "Tổng 3 phần: ≈ 1.542 kcal"); thiếu số liệu thì ghi "Chưa có số liệu dinh dưỡng của «…» — năng lượng là ước tính", không tự bịa; thay đổi ≥ 15 % thì cảnh báo. **"So với mục tiêu: [Bữa …]"** so một phần với mục tiêu bữa (mặc định bữa có mục tiêu gần nhất, hoặc đúng bữa khi mở từ Thực đơn). Khách: "Đăng nhập để so với mục tiêu bữa ăn của bạn".
  - **"Sao chép danh sách đi chợ"** (theo số người và nguyên liệu đã đổi), **"Lưu thành công thức của tôi"** (biến thể riêng tư trong "Công thức của tôi": "Biến thể của «…»" + các thay đổi, năng lượng do server tính lại), **"Thêm vào Thực đơn"** (chọn ngày + bữa; món đã chỉnh được lưu thành biến thể trước; "Xem Thực đơn" mở tab đúng ngày).
  - **Cách làm**: thẻ **"Ghi chú của tôi"** trên các bước (chỉ mình bạn thấy, ≤ 2000 ký tự, lưu trống = xoá).
  - **Đánh giá**: điểm trung bình, phân bố sao, mỗi thành viên một đánh giá (1–5 ★, nhận xét không bắt buộc 10–500 ký tự), "Sửa" / "Xoá"; không tự đánh giá công thức của mình; biến thể và công thức riêng không có tab này.
  - **Khách xem trước**: chỉnh thử thoải mái; "Lưu thành công thức của tôi", "Thêm vào Thực đơn", "Thêm ghi chú", "Viết đánh giá" mở sheet đăng nhập rồi làm tiếp, các thay đổi giữ nguyên.

### Quét tủ lạnh

- Camera có khung nhận diện; "Chọn ảnh" (máy ảo không có ảnh → "Dùng ảnh tủ lạnh mẫu"); "Nhập tay".
- Chỉ xác định **thực phẩm là gì và có thuần chay không**: nhãn "Thuần chay" / "Không thuần chay" (✓ / ✕ kèm chữ). Thực phẩm không thuần chay nằm riêng ở "Không thuần chay — không lưu" với lý do và "Gợi ý thay thế:". Chỉ **Xác nhận / Bỏ**, không có số lượng.
- "Lưu vào tủ lạnh (N)" chỉ lưu thực phẩm thuần chay đã xác nhận → "Tạo thực đơn từ tủ lạnh" hoặc **"Xem tủ lạnh"** (mở màn Nguyên liệu trong tủ). "Gợi ý món từ nguyên liệu này" → "Thêm vào thực đơn" / "Xem công thức".

### Chuyên gia: thiết kế thực đơn N ngày

Không còn tư vấn theo khung giờ, khoá học, thực đơn VIP hay dịch vụ riêng lẻ; chuyên gia nhận **thiết kế thực đơn 3–30 ngày** theo yêu cầu.

1. **Hồ sơ chuyên gia**: thẻ **"Thiết kế thực đơn theo yêu cầu"** (giá mỗi ngày, giá có phản hồi mỗi ngày, số ngày tối thiểu–tối đa, "Giá cuối do hai bên thoả thuận") và nút **"Đặt chuyên gia lên thực đơn"**. Hồ sơ của chính mình: "Đây là hồ sơ của bạn…"; chuyên gia tạm ngưng: "Chuyên gia đang tạm ngưng nhận yêu cầu".
2. **Đặt chuyên gia lên thực đơn**: số ngày (nút − / + hoặc nhập số, 3–30, trong giới hạn của chuyên gia), "Bắt đầu từ" (từ ngày mai), hình thức, **"Đặt cho": "Cho tôi" / "Cho gia đình"**. Cho tôi: mục tiêu, dị ứng, các bữa trong ngày, ngân sách, "Nhu cầu & ghi chú" (≥ 20 ký tự). Cho gia đình: số người (2–20), dị ứng, các bữa, ngân sách, ghi chú không bắt buộc; không gửi mục tiêu, BMI, nhu cầu. Thẻ **"Chuyên gia sẽ thấy"** liệt kê đúng những gì được gửi, công tắc "Chia sẻ hồ sơ sức khoẻ" chỉ có ở "Cho tôi". Thanh cố định ở đáy: **giá ước tính** (cập nhật ngay, chạm để xem chi tiết) cạnh **"Gửi yêu cầu"**.
3. **Trang yêu cầu** (dùng chung cho hai bên), tiến trình "Gửi yêu cầu → Thoả thuận giá → Thanh toán → Nhận kế hoạch → Hoàn tất":
   - **Trao đổi**: chat (tự cập nhật mỗi 5 giây), thẻ **Đề xuất giá**; bên kia trả lời ngay trên thẻ: "Đồng ý" hoặc "Đề xuất giá khác" (cuộn khỏi thẻ thì một thanh trên ô chat vẫn có hai nút này). Chuyên gia "Báo giá" ngay trong chat. Thành viên đồng ý thì mở luôn trang thanh toán. Nhắc tới zalo / sđt / "chuyển khoản riêng" / số điện thoại → banner "Giao dịch ngoài VeganLife không được bảo vệ bởi cơ chế giữ tiền".
   - **Kế hoạch**: các ngày đã giao ("Ngày 1 · Thứ Hai 20/10"), món theo bữa, ghi chú; kiểu có phản hồi: "Phản hồi ngày này" (1–5 ★, Đầy đủ / Một phần / Không, góp ý cho ngày mai); **"Áp dụng kế hoạch vào Thực đơn"** (mọi món đã giao vào đúng ngày và bữa của tuần hiện tại, **một request gộp** `POST /meal-plans/current/meals/batch`; ngày ngoài tuần được bỏ qua và báo lại).
   - **Hợp đồng**: phạm vi, số ngày, hình thức, ngày, giá, phí 10 %, đặt cho ai, **"Tiền của hợp đồng"**: số tiền, tiền đang ở đâu, ngày chuyển vào ví chuyên gia ("Chưa có ngày" khi hợp đồng chưa hoàn thành) và các bước. Hệ thống tự hoàn tất thì bước đó ghi "Hệ thống tự hoàn tất vì chuyên gia chưa xác nhận sau 3 ngày", cho cả hai bên. Ban quản trị xử lý khoản kẹt thì có mục **"Ban quản trị xử lý"**: mỗi bên nhận gì và ghi chú, đầu màn hình cũng ghi vậy, không còn nút hay lời nhắc nào.
   - Nút theo trạng thái. Thành viên: chờ thanh toán → **"Thanh toán {giá}"**; trước khi thanh toán, hoặc đã thanh toán mà chưa nhận ngày nào → "Huỷ yêu cầu"; đang giữ tiền và chưa khiếu nại → **"Khiếu nại"**. Chuyên gia: trước khi thanh toán → **"Không đồng ý"**; còn ngày chưa gửi → "Soạn kế hoạch"; đã gửi đủ và tới ngày kết thúc → **"Xác nhận hoàn thành"**.
4. **Khiếu nại kế hoạch**: lý do (Kế hoạch không đúng yêu cầu đã thoả thuận / Có nội dung ảnh hưởng sức khoẻ / Giao trễ hoặc thiếu ngày / Có món chứa chất tôi dị ứng / Khác), mô tả ≥ 30 ký tự, **bằng chứng bắt buộc** (ít nhất 1: "Thêm liên kết nguồn" http(s) hoặc "Thêm ảnh" ≤ 5); "Có nội dung ảnh hưởng sức khoẻ" cần ít nhất một liên kết nguồn; yêu cầu Hoàn toàn bộ / Hoàn một phần. Gửi xong: yêu cầu thành Đang khiếu nại, tiền **tạm giữ**, "Ban quản trị sẽ xem xét và phản hồi trong 3 ngày làm việc."
5. **Lịch sử tư vấn** (Tôi; cũng là nút trên app bar tab Chuyên gia): tab "Đang diễn ra" / "Đã kết thúc", thẻ có tiến độ "Đã nhận 3/10 ngày" và kết quả ("Đã chuyển cho chuyên gia" / "Đã hoàn … vào Ví của tôi" / "Hoàn một phần …").
6. **Ví của thành viên** (Tôi › Ví của tôi): số dư, lịch sử, tài khoản nhận tiền, rút tiền như ví chuyên gia. Tiền hoàn vào đây; màn thanh toán có **"Thanh toán bằng ví"** khi số dư đủ (không trả một phần). Mỗi người chỉ có một ví.

**Quy tắc giữ tiền (escrow)** — `lib/features/booking/domain/booking_rules.dart`, web dùng cùng số:

- 3–30 ngày; tổng giá 100.000đ – 50.000.000đ; lời nhắn đề xuất ≤ 300 ký tự; tin nhắn ≤ 1000. Chỉ bên **không** đưa ra đề xuất mới đồng ý được, và chỉ đề xuất mới nhất. Không tự đặt chính mình (409).
- Đồng ý giá → tạo hợp đồng + đơn hàng, **hạn thanh toán 48 giờ, không quá 00:00 ngày bắt đầu** (quá hạn → Hết hạn); mỗi mã QR sống 15 phút ("Tạo mã mới").
- Giao kế hoạch: một lần → hạn = max(00:00 ngày bắt đầu, lúc thanh toán + 24 giờ); có phản hồi mỗi ngày → ngày N hạn **06:00** sáng ngày đó, thành viên góp ý trước **21:00**.
- `endDate = startDate + số ngày − 1`. Thanh toán → VeganLife giữ tiền, chưa có ngày chuyển. Chuyên gia **xác nhận hoàn thành** (đã gửi đủ các ngày và hôm nay, giờ Việt Nam, từ ngày kết thúc trở đi) → hợp đồng hoàn thành, **giữ đúng 7 ngày từ lúc xác nhận**. Hết hạn mà không khiếu nại → vào ví chuyên gia, **trừ phí 10 %**.
- **Chuyên gia không xác nhận**: lúc 23:59 (giờ Việt Nam) của ngày kết thúc + 3 ngày, nếu đã gửi đủ các ngày trước lúc đó và không có khiếu nại đang mở, hệ thống tự hoàn tất: `completedAt` là đúng lúc đó, `autoCompleted: true`, giữ 7 ngày từ `completedAt` rồi vào ví chuyên gia như thường. Khiếu nại đang mở thì không tự hoàn tất. Còn thiếu ngày thì cũng không: tiền vẫn được giữ, thành viên được nhắc gửi khiếu nại, chuyên gia thấy "Cần bạn xử lý". Ngày gửi sau lúc đó không làm hợp đồng tự hoàn tất; chuyên gia vẫn xác nhận được, thành viên vẫn khiếu nại được.
- **Khoản kẹt**: tiền `Held`, chưa hoàn thành, chưa có `releaseAt`, không có khiếu nại đang mở, đã qua lúc tự hoàn tất. Chuyên gia xác nhận hoặc thành viên khiếu nại thì hết kẹt. Nếu không, admin quyết định ở web `/disputes` (`POST /admin/escrow/holds/{id}/resolve`, app không có màn hình admin): chuyển cho chuyên gia → đặt chuyên gia `Completed`; hoàn toàn bộ → `Cancelled`, `cancelReason` là ghi chú; hoàn một phần X → `Completed`. Tiền như quyết định khiếu nại. App nhận biết bằng `escrow.resolvedBy` khác null mà không có khiếu nại (`BookingDto.isAdminResolved`); thành viên tự huỷ thì `resolvedBy` null, nên không đọc nhầm thành "thành viên huỷ". Sau đó `/complete` trả 409 `not_active`, khiếu nại trả 409 `not_open`. Trong mock: `MockBookingDb.resolveHold` (chỉ cho test) và `isStuck`. App không đọc `resolution.action` của đơn. Dữ liệu mẫu không có booking đã xử lý: `b_ma_tam_short` là khoản kẹt, chưa ai quyết định.
- Khiếu nại lúc đang giữ tiền, trước hay sau khi hoàn thành → **tạm giữ** đến khi admin quyết định ở web `/disputes`: chuyển toàn bộ cho chuyên gia, hoàn toàn bộ, hoặc **hoàn một phần X** (1.000đ ≤ X < giá): thành viên nhận X, chuyên gia nhận (giá − X) × 90 %, phí (giá − X) × 10 %. Tiền hoàn luôn vào **ví của thành viên**.

### Tôi › Chuyên gia (vai trò Chef)

KPI "Yêu cầu mới · Đang thực hiện · Đang giữ (đ)" và:

- **Yêu cầu tư vấn**: tab Mới · Đang thương lượng · Đang thực hiện · Đã kết thúc, có huy hiệu. Yêu cầu mới: **"Báo giá"** (điền sẵn bảng giá) hoặc **"Từ chối"** (lý do ≥ 10 ký tự); xem hồ sơ sức khoẻ thành viên chia sẻ; đang thực hiện: **"Soạn kế hoạch"**; bị khiếu nại: **"Phản hồi khiếu nại"**.
- **Soạn kế hoạch**: chip ngày ("Chưa soạn" / "Nháp" / "Đã gửi"), phản hồi của thành viên cho ngày trước ở trên cùng, món theo bữa ("Nhập món mới" hoặc "Chọn từ công thức của tôi"), "Sao chép từ ngày trước", ghi chú ngày, "Lưu nháp". Giao một lần: **"Gửi toàn bộ kế hoạch"** (chỉ bật khi đủ món mọi ngày); có phản hồi: **"Gửi ngày này"** ("Hạn gửi: 06:00 …"). Món đã gửi hiện trong "Từ chuyên gia" của thành viên.
- **Ví của tôi**: Có thể rút / Đang giữ / Tạm giữ do khiếu nại / Đã rút; lịch sử theo tháng, **Tài khoản nhận tiền**, **Rút tiền** (tối thiểu 100.000đ, mọi yêu cầu chờ admin duyệt ở web `/payouts`; bản mock có "Mô phỏng duyệt" / "Mô phỏng từ chối").
- **Hồ sơ & bảng giá**: chuyên môn, giới thiệu, giá mỗi ngày, giá có phản hồi mỗi ngày, số ngày tối thiểu / tối đa, công tắc "Đang nhận yêu cầu".
- **Tài liệu kiến thức**: gửi tài liệu cho chatbot RAG → Chờ duyệt / Đã duyệt / Bị từ chối.

## Chạy lần đầu

```bash
cd FE/Mobile
flutter pub get
flutter run                                                    # mặc định USE_MOCK_DATA=true
```

Cần Flutter ≥ 3.27 (Dart ≥ 3.6). Kiểm tra: `dart format --output=none --set-exit-if-changed lib test tool integration_test_be`, `flutter analyze`, `flutter test`, `flutter build apk --debug`. Từ thư mục `FE`, `run_checks.bat` chạy kiểm tra cho cả mobile và web.

### Quyền

- iOS `Info.plist`: `NSCameraUsageDescription` (quét tủ lạnh) và `NSPhotoLibraryUsageDescription` (chọn ảnh tủ lạnh, ảnh/video để đăng).
- Android `AndroidManifest.xml`: `INTERNET` (API, ô bản đồ, OSRM), `CAMERA`, khối `queries` cho link https (`url_launcher`, "Mở bằng Google Maps"). Chọn ảnh/video dùng trình chọn ảnh hệ thống (`image_picker`), không cần quyền đọc bộ nhớ. Không xin quyền vị trí (vị trí đang mô phỏng).

## Cấu hình (`--dart-define`)

| Key | Mặc định | Ý nghĩa |
|---|---|---|
| `USE_MOCK_DATA` | `true` | `false` → chế độ lai: module BE đã hỗ trợ gọi API thật qua Dio, còn lại mock (xem "Chạy với BE thật") |
| `BACKEND_MOCK_MODULES` | (trống) | Khi `USE_MOCK_DATA=false`: các module ép dùng mock, cách nhau bằng dấu phẩy (`community,scanner`) |
| `BACKEND_REAL_MODULES` | (trống) | Khi `USE_MOCK_DATA=false`: các module ép gọi BE thật (`video`) |
| `API_BASE_URL` | `http://10.0.2.2:5001/api/v1` | Gốc API ASP.NET Core (10.0.2.2 = máy host khi chạy Android emulator) |
| `GUEST_TRIAL_LIMIT` | `3` | Số câu hỏi AI miễn phí cho khách; `0` = bắt đăng nhập ngay (server quyết định cuối cùng) |
| `MAP_TILES` | `on` | `off` → bản đồ là nền phẳng có điểm và tuyến, không tải ô bản đồ (test luôn tắt) |
| `MAP_TILE_URL` | `https://tile.openstreetmap.org/{z}/{x}/{y}.png` | Nguồn ô bản đồ (đổi sang nhà cung cấp trả phí / tự host khi lên production) |
| `OSRM_BASE_URL` | `https://router.project-osrm.org` | Máy chủ chỉ đường (profile `driving`, timeout 5 giây); để trống = chỉ vẽ đường thẳng |
| `MOCK_SCAN_SCENARIO` | `normal` | `empty` / `error` cho màn quét |
| `MOCK_COMMERCE_SCENARIO` | `normal` | `empty` / `error` cho danh sách đặt chuyên gia, ví và công cụ chuyên gia |
| `MOCK_ADS_SCENARIO` | `normal` | `empty` / `error`: không có dòng "Được tài trợ" (danh sách quán không bao giờ báo lỗi vì quảng cáo) |

Ví dụ: `flutter run --dart-define=MAP_TILES=off`, `flutter run --dart-define=OSRM_BASE_URL=http://127.0.0.1:9` (thử đường thẳng dự phòng).

## Khớp với backend (FE ↔ BE)

- **Envelope**: mọi response của BE có dạng `ApiResponse<T> { success, message, data, statusCode }`. `EnvelopeInterceptor` tự bóc `data`; `success: false` thành `ApiException` với `message` từ server.
- **JSON camelCase** = camelCase của tên cột SQL. Enum C# (`UserStatusEnum`, `AuthTypeEnum`) nhận cả số lẫn chuỗi. **ID**: SQL dùng `INT`; app giữ id dạng chuỗi và gửi lại dạng số khi là số (`apiId`). **Ngày giờ** ISO-8601 UTC; **tiền** là số nguyên VND. **Vai trò** `Admin` / `User` / `Chef`.
- Mọi đường dẫn nằm trong `lib/core/network/api_endpoints.dart`; JSON mẫu ở đầu mỗi file `data/models/*.dart` (hoặc đầu API service).

**BE hiện có** (ASP.NET Core + MongoDB) đủ các nhóm trong bảng dưới. Bảng là hợp đồng đầy đủ app mong đợi (dưới `/api/v1`), mock chạy đúng theo bảng; nhóm nào còn chênh lệch thì do các service `Remote*` tự xử lý (xem "Chênh lệch với BE hiện tại"); module nào đang thật hay mock xem "Chạy với BE thật":

| Nhóm | Endpoint | File (`lib/…`) |
|---|---|---|
| Đăng nhập | POST `/auth/login`, `/auth/register`, `/auth/refresh`, `/auth/logout`, `/auth/forgot-password`, `/auth/verify-reset-code`, `/auth/reset-password` | `core/session/auth_api_service.dart` |
| Tài khoản | GET `/users/me`; PUT `/users/{id}`; POST `/chef-applications` | `features/profile/data/profile_api_service.dart` |
| Cộng đồng | GET `/posts?type=&cursor=&limit=`, POST `/posts`; GET/PUT/DELETE `/posts/{id}`; PUT/DELETE `/posts/{id}/like`, `/posts/{id}/save`; POST `/posts/{id}/reports`; GET/POST `/posts/{id}/comments?cursor=&limit=10` (`parentId` khi trả lời); GET `/posts/{postId}/comments/{commentId}/replies`; PUT/DELETE `/posts/{postId}/comments/{commentId}`; GET `/users/me/posts`, `/users/me/saved-posts`, `/users/me/comments` | `features/community/data/community_api_service.dart` |
| Tải tệp | POST `/media/images` (multipart, ≤ 10 MB), POST `/media/videos` (multipart, ≤ 200 MB) | `features/community/data/media_api_service.dart` |
| Bếp nhanh (video ngắn) & video AI | GET `/posts?mediaType=Video&limit=`; GET `/videos/{id}`, POST `/videos/{id}/extraction` | `features/reels/data/reels_api_service.dart`, `features/video/data/video_api_service.dart` |
| Tìm kiếm | GET `/search?q=&type=&lat=&lng=`, `/search/suggest?q=&limit=8`, `/search/discover?lat=&lng=` | `features/search/data/search_api_service.dart` |
| Quán chay | GET `/restaurants?lat=&lng=&q=&certifiedOnly=&sort=&radiusKm=`, POST `/restaurants` (kèm `latitude`, `longitude`, `media`); GET `/restaurants/{id}`, `/restaurants/{id}/media`; GET/POST `/restaurants/{id}/reviews`; GET `/restaurants/suggested` | `features/restaurant/data/restaurant_api_service.dart` |
| Vị trí | GET `/geo/search?q=`, `/geo/reverse?lat=&lng=` (BE làm proxy, tôn trọng chính sách Nominatim) | `features/restaurant/data/geocoding_service.dart` |
| Quảng cáo | GET `/ads/feed?placement=nearby&lat=&lng=&limit=1`; POST `/ads/{id}/impression`, `/ads/{id}/click` | `features/ads/data/ads_api_service.dart` |
| Sức khoẻ & thực đơn | GET/PUT `/health-profile/me` (GET trả **404** khi chưa có hồ sơ; PUT tạo hoặc sửa, và cập nhật `dailyTargets` của tuần hiện tại); **GET `/health-profile/me/metrics?limit=100`** (mới nhất trước, thêm `waistCm`, `bodyFatPct`, `source` `profile`/`check_in`), **POST `/health-profile/me/metrics`** (check-in `{ weightKg, waistCm?, bodyFatPct? }`; trên BE thật trả về dòng vừa ghi, tự tính lại hồ sơ và tuần, trả **404** khi chưa có hồ sơ, **400** khi ngoài khoảng 20–300 kg); GET `/catalog/allergens?q=`; GET `/meal-plans/current`; POST `/meal-plans` (tuần trống, hoặc làm trống tuần đang có), `/meal-plans/generate` (`usePantry`), `/meal-plans/from-ingredients` (tối đa 10 món hợp với tủ lạnh, không đổi thực đơn); GET `/meal-plans/{id}/swap-suggestions`; PATCH/DELETE `/meal-plans/{id}/meals` (PATCH `{ date, slot, recipeId, source, portion }`, `source` có thêm `recipe`); POST `/meal-plans/current/meals`, **`/meal-plans/current/meals/batch`** (`{ meals: [...] }` → `{ placed, skipped, days }`); POST `/meal-plans/current/adjust`, `/meal-plans/current/adjust/{proposalId}/apply`; GET `/meal-plans/chef-suggestions`; GET `/users/me/recipes`, POST `/recipes` | `features/meal_planner/data/meal_planner_api_service.dart`, `allergen_api_service.dart` |
| Công thức | **GET `/recipes/{id}`** (hợp đồng đầy đủ: khách xem được; BE thật hiện cần đăng nhập và chưa có các trường dưới đây; nguyên liệu có `key`, `quantity`, `unit`, `role`, `isSignature`, `isOptional`, `allergens`, `nutrition`, `substitutes`; `servings`, `averageRating`, `ratingCount`, `basedOnRecipeId`, `customizations`); **POST `/recipes/{id}/variants`** (`{ name, swaps: [{ ingredientKey, substituteKey }], removed: [...] }` → 201 công thức riêng tư đã tính lại calo; 400 `signature_required` / `invalid_substitute`); **GET `/recipes/{id}/reviews?cursor=&limit=10`** (kèm `myReview` khi có token), **PUT/DELETE `/recipes/{id}/reviews/me`** (403 `own_recipe`); **GET/PUT/DELETE `/recipes/{id}/notes/me`** (GET 404 = chưa có ghi chú) | `features/recipe/data/recipe_api_service.dart`, `recipe_community_api_service.dart` |
| Tủ lạnh & nguyên liệu | GET/POST/DELETE `/users/me/ingredients`, DELETE `/users/me/ingredients/{id}`; GET `/ingredients?q=&veganOnly=true`, `/ingredients/{id}` | `features/meal_planner/data/pantry_api_service.dart`, `features/ingredient/data/ingredient_api_service.dart` |
| Quét | POST `/vision/scan`. "Gợi ý món" chọn trên máy từ danh mục công thức | `features/scanner/data/scanner_api_service.dart` |
| Chatbot | GET `/chat/guest-trial`, POST `/chat/sessions/{id}/messages` (SSE) | `features/chatbot/data/chat_api_service.dart` |
| Chuyên gia (danh bạ) | GET `/chefs`, `/chefs/{id}` (kèm bảng giá, `acceptingBookings`) | `features/chef/data/chef_api_service.dart` |
| Đặt chuyên gia (thành viên) | POST `/bookings`; GET `/bookings/me`, `/bookings/{id}` (kèm hợp đồng, giữ tiền, khiếu nại); GET/POST `/bookings/{id}/messages`; POST `/bookings/{id}/offers`, `/bookings/{id}/offers/{offerId}/accept\|reject`, `/bookings/{id}/cancel`, `/bookings/{id}/payments`, `/bookings/{id}/complaint`, `/orders/{id}/wallet-payment`; GET `/users/me/wallet`, `/users/me/wallet/transactions`; PUT `/users/me/bank-account`; GET/POST `/users/me/withdrawals`; GET `/bookings/{id}/plan`; PUT `/bookings/{id}/plan/days/{dayIndex}/feedback` | `features/booking/data/booking_api_service.dart` |
| Thanh toán | GET `/orders/{id}`; POST `/orders/{id}/payments` (QR mới); GET `/payments/{id}` (hỏi mỗi 3 giây; xác nhận thật là của cổng thanh toán, BE chưa có cổng thật) | `features/commerce/data/commerce_api_service.dart` |
| Chuyên gia: yêu cầu | GET `/chefs/me/bookings`; POST `/chefs/me/bookings/{id}/decline`; PUT `/chefs/me/bookings/{id}/plan/days/{dayIndex}`; POST `…/plan/days/{dayIndex}/send`, `…/plan/send`, `…/complaint/response` | `features/booking/data/booking_api_service.dart` |
| Chuyên gia: hồ sơ, tài liệu, ví | GET/PUT `/chefs/me/profile`; GET/POST `/chefs/me/knowledge-docs`; GET `/chefs/me/wallet`, `/chefs/me/wallet/transactions?month=`; PUT `/chefs/me/bank-account`; GET/POST `/chefs/me/withdrawals`; POST `/chefs/me/bookings/{id}/complete` | `features/chef_studio/data/chef_studio_api_service.dart`, `chef_wallet_api_service.dart` |

Đã khai báo nhưng app chưa gọi: `POST /auth/google` (dự phòng, không có luồng nào dùng), `GET /recipes/{id}/related-posts` (tuỳ chọn), `GET /chef-applications/me` (trạng thái hồ sơ đọc từ `GET /users/me`).

## Chênh lệch với sơ đồ SQL 26 bảng

App coi các trường mới là tuỳ chọn (thiếu thì UI vẫn chạy), nhưng BE/ERD cần bổ sung để dùng thật:

- **Bảng mới — cộng đồng**: `comments` (id, post_id, user_id, **parent_id** → comments.id, chỉ một cấp, content, status Visible/Hidden, created_at, updated_at), `post_likes`, `saved_posts`, `post_reports`, `post_tags`; `search_logs` (tuỳ chọn, cho "Xu hướng tìm kiếm"). Mỗi bài chỉ một tệp đính kèm (`posts.media_url`); nhiều ảnh cần bảng `post_media` sau này (chưa làm).
- **Bảng mới — tài khoản**: `password_reset_codes` (code_hash, expires_at 10 phút, attempts tối đa 3, reset_token_hash, used_at), `chef_applications`.
- **Bảng mới — sức khoẻ & nguyên liệu**: `user_allergies` (allergen_id hoặc custom_name), `ingredient_nutrition` (khẩu phần, kcal, macro, vi chất JSON, good_for, caution_for, source), `ingredient_incompatibilities`, `meal_plan_adjustments` (message, reply, changes JSON, scope, status Proposed/Applied/Dismissed).
- **Bảng mới — quán & quảng cáo**: `restaurant_media` (Image/Video), `ad_campaigns` (kèm `placement` = `nearby`, lượt hiển thị/bấm).
- **Bảng mới — đặt chuyên gia**: `chef_bookings` (booking_type OneShot/DailyFeedback, plan_days, start_date, audience, family_size, completed_at, auto_completed, goal, allergies_snapshot, meal_pattern, budget_per_day, needs, share_health_profile, status, decline_reason, cancel_reason), `booking_offers`, `booking_messages` (Text/Offer/System/Attachment), `booking_contracts` (1:1, bất biến: giá, ngày, delivery_due_at, daily_send_cutoff 06:00, feedback_cutoff 21:00, fee_rate 0.10, hold_days 7, payment_due_at = min(+48 giờ, 00:00 ngày bắt đầu)), `booking_plan_days`, `booking_plan_meals` (6 bữa), `booking_day_feedback`.
- **Bảng mới — giữ tiền & khiếu nại**: `escrow_holds` (Held/Frozen/Released/Refunded/PartiallyRefunded, completed_at, release_at NULL đến khi hợp đồng hoàn thành rồi = completed_at + 7 ngày, released/fee/refunded amount), `booking_complaints` (reason, description, requested_outcome, requested_amount, chef_response, decision ReleaseToChef/RefundMember/Split, refund_amount, admin_note), `complaint_evidence` (Link/Image, url, caption).
- **Bảng mới — ví**: `wallets`, `bank_accounts`, `wallet_transactions`, `withdrawal_requests` theo `user_id`, bảng cuối có `role` (`wallet_transactions` kèm `booking_id`; trạng thái `Held` "Đang giữ" thay `Pending`, `Frozen` "Tạm giữ do khiếu nại").
- **Bảng mới — công thức & cân nặng**: `recipe_ingredient_substitutes` (recipe_ingredient_id, substitute_key, ingredient_id NULL, name, quantity, unit, note, allergens, kcal/protein_g/carbs_g/fat_g/fiber_g NULL; `UNIQUE(recipe_ingredient_id, substitute_key)`), `recipe_reviews` (recipe_id, user_id, rating 1–5, content ≤ 500 NULL, status Visible/Hidden, created_at, updated_at; `UNIQUE(recipe_id, user_id)`), `recipe_notes` (recipe_id, user_id, content ≤ 2000, updated_at; `UNIQUE(recipe_id, user_id)`), `body_measurements` (user_id, logged_at, weight_kg, height_cm, bmi, waist_cm NULL, body_fat_pct NULL, source `profile`/`check_in`; index `(user_id, logged_at DESC)`).
- **Cột mới / đổi**:
  - `posts.restaurant_id` (gắn một quán), `posts.updated_at`, `posts.duration_seconds`; `posts.type` chỉ còn `recipe|discussion`;
  - `health_profiles.gender` (Male/Female/Other), `birth_year`, `activity_level` (sedentary/light/moderate/active), `meal_pattern`;
  - `meal_plan_recipes.meal_type` thêm `snack_am`, `snack_pm`, `snack_late`; `meal_plan_recipes.source` (ai / manual / user_recipe / chef / fridge_scan / recipe = "Từ công thức"), `meal_plan_recipes.portion`;
  - `recipes.created_by`, `servings` (mặc định 1), `based_on_recipe_id` → recipes.id (biến thể), `nutrition_estimated`, `rating_avg`, `rating_count`, `customizations` (JSON); `recipe_ingredients.ingredient_key` (`UNIQUE(recipe_id, ingredient_key)`), `role`, `is_signature`, `is_optional`, `sort_order`, `allergens`, kcal/protein_g/carbs_g/fat_g/fiber_g (đóng góp cho cả công thức ở định lượng gốc);
  - `user_ingredients.scanned_at` (null = "Tự thêm");
  - `ingredients.is_vegan`, `ingredients.category` (leafy/veg/mushroom/plant_protein/grain/nut_seed/fruit/spice/plant_milk) + `ingredient_nutrition`;
  - `restaurants.latitude`, `restaurants.longitude` (+ `restaurant_media`); `reviews`: `UNIQUE(user_id, restaurant_id)`, `updated_at`;
  - `chef_profiles.price_per_day`, `feedback_price_per_day`, `min_plan_days` (3), `max_plan_days` (30), `accepting_bookings`;
  - `orders.booking_id`, `orders.refunded_at`, `orders.service_id` cho phép NULL, trạng thái thêm `PartiallyRefunded`; `payments.expires_at`, `payments.created_at`;
  - `knowledge_docs.status`, `review_note`, `reviewed_by`, `reviewed_at`.
- **Video AI** chưa có chỗ lưu: trạng thái xử lý (queued / transcribing / extracting / ready / failed, lý do lỗi), tóm tắt, nguyên liệu, các bước theo mốc thời gian, lời thoại.
- **Không còn dùng**: `services`, `consultations`, quyền truy cập gói (access grants), `chef_meal_suggestions` ("Từ chuyên gia" giờ lấy từ `booking_plan_days` / `booking_plan_meals`).

### Chênh lệch với BE hiện tại (MongoDB)

Kiểm tra trên BE chạy thật ngày 2026-11-02 (BE ở `origin/main`, commit `2927565`). Lỗi còn mở có một test mang đúng số hiệu trong `integration_test_be/be_bug_pins_test.dart`: test đó khẳng định **hành vi sai của hôm nay**, nên khi BE sửa thì test đỏ và báo phần nào của app cần gỡ. Lỗi đã sửa thành hành vi bình thường, được kiểm tra trong các file còn lại của bộ test.

**BE chưa có (app có tính năng, BE thiếu):**

- Danh sách công thức theo dị ứng của thành viên. `GET /recipes` đã có nhưng không lọc dị ứng, nên app vẫn đọc danh mục qua `swap-suggestions` với id thực đơn của thành viên; ai chưa có thực đơn tuần này chỉ có tối đa 10 món từ `/from-ingredients`.
- Nguyên liệu có cấu trúc: công thức seed chưa có `ingredientItems` nên `/recipes/{id}/variants` chưa dùng được; app lưu biến thể bằng `POST /recipes`.
- AI cho "Chỉnh thực đơn": `POST /meal-plans/current/adjust` đọc theo quy tắc, không gọi AI, nên bản thật ghi "Chỉnh thực đơn".
- `/posts/{id}/save` đã có nhưng app giữ "Đã lưu" trên máy để không mất danh sách cũ.
- Cổng thanh toán thật: chỉ có cổng thử nghiệm `Payment:Provider=Sandbox`. App chưa nối `/videos`, `/geo/*` (có route nhưng cố ý còn mock, xem bảng module).

**Lỗi BE còn mở:**

Không còn lỗi đã biết nào trong danh sách này: B13, B37, B41, B43, B69, B70, B71 đã được BE sửa, xem "Đã sửa đúng". Lỗi đi từ tiền và đặt chuyên gia nằm trong `.qa-local/fe_real_report.md`.

Ghi nhận thêm: mỗi thiết bị một refresh token, tối đa 10 (B55); đăng xuất chỉ thu hồi thiết bị đó. Đặt lại mật khẩu, khoá, đổi vai trò, xoá tài khoản thì thu hồi hết. `POST /auth/logout` không thu hồi JWT đang dùng: nó còn hiệu lực tới khi hết hạn.

**Đã sửa đúng** (kiểm tra trong bộ test; app đã gỡ phần chữa tạm, và `guardFixed` trong `be_bug_pins_test.dart` báo nếu lỗi quay lại; B43, B71 chỉ có test ở BE): B13, B37, B41, B43, B55, B69, B70, B71, B1, B2, B3, B4, B5, B6, B7, B8, B9, B10 (trừ B43), B11, B12, B14, B15, B16, B17, B18, B19, B20, B21, B22, B23 (riêng việc gửi email: mã vẫn chỉ nằm trong log), B24, B25, B26, B27, B28, B29, B30, B31, B32 (thời lượng là `null`), B33, B34, B35, B36, B38, B39, B40, B68. B42 thử bằng tay ngày 2026-11-02: sau khi đặt lại mật khẩu, refresh token cũ trả 401. Bản dev vẫn trả URL tương đối cho tệp tải lên, nên app vẫn có `absoluteMediaUrl`; `wwwroot` nay được tạo sẵn.

**Sai trong `TAI_LIEU_API_CHO_FRONTEND.md`**: dị ứng ghi là chuỗi. Tài liệu kế hoạch BE ghi ngưỡng BMI của WHO, còn code BE (và app) dùng chuẩn châu Á – Thái Bình Dương.

Lưu trữ đề xuất cho BE (MongoDB; bản SQL ở mục trên):

- `recipes`: `+servings` (mặc định 1), `+ingredientItems: [{ key, ingredientId?, name, quantity?, unit, role?, isSignature, isOptional, allergens[], nutrition?{ calories, proteinG, carbsG, fatG, fiberG }, substitutes: [{ key, ingredientId?, name, quantity?, unit, note?, allergens[], nutrition? }] }]` (giữ `ingredients: string[]` = tên, cho `AllergyMatcher`), `+basedOnRecipeId?`, `+customizations[]`, `+nutritionEstimated`, `+ratingAvg?`, `+ratingCount`; index `basedOnRecipeId`.
- `recipe_reviews` (mới): `{ recipeId, userId, rating 1–5, content?, status Visible/Hidden, createdAt, updatedAt }`; unique `(recipeId, userId)`, index `(recipeId, createdAt desc)`.
- `recipe_notes` (mới): `{ recipeId, userId, content, updatedAt }`; unique `(recipeId, userId)`.
- `health_metric_logs`: `+source: "profile" | "check_in"` (thiếu = `profile`).
- `meal_plans.days[].meals.*.source`: thêm giá trị `recipe`.

## Cấu trúc

```
lib/
├── main.dart, app.dart              # ProviderScope, theme, AppEntry (Welcome / shell), thanh tab + nút Quét + bong bóng Hỏi AI
├── core/
│   ├── config/                      # env.dart (--dart-define), backend_modules.dart (module thật hay mock)
│   ├── network/                     # dio_client, api_endpoints, envelope, interceptors, api_exception
│   ├── session/                     # phiên, vai trò, auth API, tài khoản & máy chủ auth mock
│   ├── settings/ theme/ utils/      # giao diện, màu, BMI/năng lượng, định dạng VN, tìm không dấu
│   └── widgets/                     # app_logo, GuestGate, SignInSheet, AccountButton, VLCard, trạng thái trống/lỗi
└── features/
    ├── auth/                        # Welcome, Đăng nhập, Tạo tài khoản, Quên mật khẩu
    ├── community/                   # bảng tin, chi tiết bài + bình luận, đăng/sửa bài, tải ảnh/video, gắn quán
    ├── reels/  video/               # Bếp nhanh (video ngắn dọc); video + AI tóm tắt (sheet "Xem công thức")
    ├── search/                      # tìm kiếm 3 trạng thái
    ├── restaurant/  ads/            # quán chay, bản đồ, chỉ đường, vị trí, gợi ý quán; dòng "Được tài trợ"
    ├── meal_planner/  recipe/       # thực đơn, hồ sơ sức khoẻ, chỉnh với AI; chi tiết công thức
    ├── ingredient/                  # tủ lạnh, CSDL dinh dưỡng, chi tiết nguyên liệu
    ├── scanner/                     # nút Quét, nhận diện + xác nhận thực phẩm
    ├── chef/                        # danh bạ, hồ sơ chuyên gia, bảng giá
    ├── booking/                     # đặt chuyên gia, chat, đề xuất giá, hợp đồng, kế hoạch, khiếu nại, lịch sử, hộp yêu cầu
    ├── commerce/                    # đơn hàng + thanh toán (QR của cổng, hoặc ví) cho yêu cầu đặt chuyên gia
    ├── chef_studio/                 # ví, hồ sơ & bảng giá, tài liệu kiến thức
    ├── profile/                     # Tôi, nội dung của tôi, đăng ký chuyên gia
    └── chatbot/                     # Hỏi AI (RAG)
        ├── data/                    # models (DTO + JSON), *_api_service.dart, mock_*_repository.dart
        ├── domain/                  # entities, quy tắc nghiệp vụ
        └── presentation/            # controllers (Riverpod), screens, widgets
tool/brand/                          # sinh icon + splash
integration_test_be/                 # test với BE thật (xem "Chạy với BE thật")
```

## Thử nhanh (mock)

**Dữ liệu mẫu**

- **Minh Anh**: dị ứng đậu phộng, "3 bữa + 1 phụ" (sáng, trưa, phụ chiều, tối), Nữ, sinh 1997, vận động nhẹ, mục tiêu Tăng cơ; tủ lạnh có Đậu hũ, Cà chua, Nấm rơm (Quét) và Gạo lứt (Tự thêm); bài chờ duyệt `p_me_pending_celery`, bài bị từ chối `p_me_rejected_detox`, video `p_me_banh_xeo` bị AI xử lý lỗi ("Thử trích xuất lại"). Lịch sử cân (cao 172 cm): 6 lần trong 8 tuần, 65,0 → 66,0 kg, lần gần nhất 8 ngày trước → thẻ "Cập nhật cân nặng" hiện ngay trên Thực đơn.
- **Công thức** (tìm `bun rieu`): **Bún riêu chay** (`l5`, 2 phần, 580 kcal, ★ 4,6 · 5 đánh giá) có đủ số liệu dinh dưỡng: riêu Đậu hũ là thành phần chính (đổi sang Nấm rơm băm nhuyễn → ≈ 514 kcal hoặc Đậu nành ngâm xay), Bún tươi đổi được (Bánh phở tươi chưa có số liệu → "≈"), Rau muống và Mắm ruốc không bắt buộc. `menu_1`–`menu_3` (gợi ý của Quét) cũng chỉnh được; mỗi món của Thực đơn có một thành phần chính, một số nguyên liệu có lựa chọn thay thế (ví dụ Nước tương → Hạt nêm nấm cho người dị ứng đậu nành).
- **Lê Quang Tâm**: hồ sơ sức khoẻ cũ chưa có giới tính / năm sinh (hiện lời nhắc bổ sung); bảng giá 150.000đ/ngày, có phản hồi 180.000đ/ngày. Danh bạ: Trần Quốc Minh đang tạm ngưng nhận yêu cầu.
- **Yêu cầu đặt chuyên gia** (ngày tính từ hôm nay; id trùng với web):
  - Minh Anh: `b_ma_tam_nego` (Tâm, 10 ngày có phản hồi, Tâm đề xuất 1.500.000đ → "Đồng ý" hoặc "Đề xuất giá khác"); `b_ma_thuha_active` (ThS. DD Phạm Thu Hà, 7 ngày giao một lần, đã thanh toán, đã giao đủ, hôm nay là ngày 3 → "Áp dụng kế hoạch vào Thực đơn", "Khiếu nại"); `b_ma_tam_done` (Tâm, 5 ngày, đã chuyển cho chuyên gia); `b_ma_tam_hold` (đang giữ 7 ngày, có ngày chuyển); `b_ma_thuha_refund` (đã hoàn vào ví); `b_ma_tam_auto` (đã giao đủ, chuyên gia không xác nhận nên hệ thống tự hoàn tất, đang giữ); `b_ma_tam_short` (mới giao 3/5 ngày, đã quá 3 ngày sau ngày kết thúc: nhắc khiếu nại, tiền vẫn giữ). Ví của tôi 1.600.000đ.
  - Tâm: `b_nam_tam_req` (Hoàng Nam, 14 ngày giao một lần, chờ báo giá); `b_vy_tam_active` (Thảo Vy, 7 ngày có phản hồi, đã có phản hồi ngày 2, ngày hôm nay còn nháp → "Soạn kế hoạch"); `b_tram_tam` (Ngọc Trâm, đang khiếu nại **`cp_tram_tam`**: ảnh hưởng sức khoẻ, 1 liên kết + 1 ảnh, tiền tạm giữ, chuyên gia đã phản hồi); `b_chau_tam_ready` (gia đình 3 người, đã gửi đủ → "Xác nhận hoàn thành"); `b_han_tam_done` (gia đình 4 người, 30 ngày, đã chuyển). Ví của Tâm tính lại từ các yêu cầu này (đang giữ 2.934.000đ); tài khoản nhận tiền và lịch sử rút tiền có sẵn.
- **Bài gắn quán**: `p_video_cha_lua` → Quán Chay An Lạc, `p_checkin_hanh_tam` → Bún Riêu Chay Hạnh Tâm. Bài `p_video_cha_lua` có bình luận kèm phản hồi của Tâm.
- **Luồng hai tài khoản**: Minh Anh gửi yêu cầu cho Tâm → Tâm "Báo giá" → Minh Anh "Đề xuất giá khác" → Tâm "Đồng ý" → Minh Anh "Thanh toán" → "Mô phỏng đã thanh toán" → Tâm "Gửi ngày này" (ngày 1) → Minh Anh "Phản hồi ngày này" → Tâm gửi ngày 2 → … → hết hạn giữ tiền thì ví Tâm có 90 % ở "Có thể rút".

**Kích hoạt có chủ đích**

- **`#fail`** → lỗi 503 khi có trong: bình luận (thêm, sửa), tiêu đề/nội dung bài, họ tên ở "Thông tin cá nhân", tên món tự nhập / "Công thức của tôi" / món áp dụng từ kế hoạch chuyên gia, yêu cầu "Chỉnh thực đơn với AI", tên nguyên liệu thêm vào tủ, ô tìm nguyên liệu và dị ứng, ô tìm kiếm (toàn app và quán chay), ô tìm địa chỉ ("Chọn vị trí"), nhận xét đánh giá quán, tên/địa chỉ quán gợi ý; đặt chuyên gia: nhu cầu, tin nhắn, lời nhắn đề xuất giá, lý do huỷ / từ chối, góp ý ngày, tên món / ghi chú ngày khi soạn kế hoạch, mô tả khiếu nại, phản hồi khiếu nại; phía chuyên gia: giới thiệu hồ sơ, tiêu đề tài liệu, tên chủ tài khoản ngân hàng; trang công thức: tên công thức khi "Lưu công thức đã chỉnh", nhận xét đánh giá công thức, nội dung "Ghi chú của tôi" (lỗi hiện ngay trong hộp thoại/sheet, chữ đã nhập giữ nguyên). Quán **"Quán thử nghiệm QA #fail"** luôn lỗi khi gửi đánh giá.
- **Duyệt bài / duyệt quán (mock)**: mọi bài mới, bài sửa và quán gợi ý đều chờ duyệt; bấm "Duyệt thử" / "Từ chối thử" trên banner bài hoặc ở "Quán tôi đã gợi ý". `#fail` vẫn trả 503.
- **`#expire`** trong "Nhu cầu & ghi chú" khi đặt chuyên gia → hạn thanh toán và mã QR chỉ còn 30 giây ("Tạo mã mới" / yêu cầu hết hạn). Màn thanh toán mock có "Mô phỏng đã thanh toán" / "Mô phỏng thất bại".
- **`#offline`** trong câu hỏi chat → mất mạng giữa chừng.
- **Cân nặng `99.9`** khi lưu hồ sơ sức khoẻ hoặc check-in "Cập nhật cân nặng" → 503 (số đã nhập giữ nguyên).
- **Tệp mẫu** (Tạo bài viết › Ảnh/Video, ảnh quán, ảnh bằng chứng): `dau_hu_sot_ca.jpg` (2,1 MB, tải được), `anh_qua_lon.png` (14 MB, bị chặn), `banh_xeo_chay.mp4` (48 MB), `mat_ket_noi.mp4` (mất kết nối ở 60 % → "Thử lại"), `video_4k_qua_lon.mov` (850 MB, bị chặn); "Chọn từ thư viện" dùng tệp thật trên máy.
- **Vị trí** (mock geocoder ~20 địa điểm): TP.HCM — Nhà hát Thành phố, Chợ Bến Thành, Nhà thờ Đức Bà, Phố đi bộ Nguyễn Huệ, Hồ Con Rùa, Chợ Bà Chiểu, Landmark 81, Phú Mỹ Hưng, Chợ Bình Tây, Đại học Bách khoa TP.HCM, Sân bay Tân Sơn Nhất, Khu Công nghệ cao; Hà Nội — Hồ Hoàn Kiếm, Văn Miếu – Quốc Tử Giám, Lăng Chủ tịch Hồ Chí Minh, Hồ Tây, Times City; Đà Nẵng — Cầu Rồng, Chợ Hàn, Bãi biển Mỹ Khê, Ngũ Hành Sơn. Chọn một địa điểm Hà Nội → khoảng cách và thứ tự quán đổi, không còn dòng tài trợ (chiến dịch mẫu chỉ chạy ở TP.HCM). "Dùng vị trí hiện tại (mô phỏng)" = "Quận 1, TP.HCM (vị trí mô phỏng)".
- **Chỉ đường dự phòng**: `--dart-define=OSRM_BASE_URL=http://127.0.0.1:9` hoặc tắt mạng → đường thẳng + ghi chú trong ≤ 6 giây.
- **Chỉnh với AI**: "Mình chưa hiểu yêu cầu…" khi câu không khớp gợi ý nào; đề xuất không bao giờ chứa đậu phộng (dị ứng của Minh Anh) hay món không thuần chay.
- **Quét** (ảnh tủ lạnh mẫu, cũng là kết quả camera / "Chọn ảnh" ở mock): 7 thực phẩm, "Rau chân vịt" (58 %) cần Xác nhận, "Trứng gà" và "Sữa bò" ở "Không thuần chay — không lưu". **Nhập tay**: `trứng vịt`, `mật ong`, `nước mắm`, `thit bo` → không thuần chay; `nấm mỡ`, `sữa đậu nành` → thuần chay. Trong "Nguyên liệu trong tủ", thêm `thịt bò` → bị từ chối kèm "Gợi ý thay thế".
- **Tìm kiếm**: gõ `bu` → chỉ có gợi ý; Enter → tab kết quả; `bun rieu` (không dấu) → "Bún riêu chay"; `xyzxyz` → "Không tìm thấy «xyzxyz»".
- **Lỗi nghiệp vụ đặt chuyên gia**: đặt chính mình (mở hồ sơ Tâm bằng tài khoản Tâm) → "Đây là hồ sơ của bạn…"; nhu cầu < 20 ký tự, lý do từ chối < 10 ký tự, mô tả khiếu nại < 30 ký tự, khiếu nại không có bằng chứng, "ảnh hưởng sức khoẻ" không có liên kết → bị chặn; đồng ý đề xuất của chính mình hoặc đề xuất cũ → 409; rút dưới 100.000đ hoặc vượt "Có thể rút" → báo lỗi; rút ≤ 5.000.000đ tự chuyển sau ~10 giây.
- **`MOCK_*_SCENARIO`**: `MOCK_SCAN_SCENARIO=empty|error`, `MOCK_COMMERCE_SCENARIO=empty|error`, `MOCK_ADS_SCENARIO=empty|error` (xem bảng cấu hình).

Video mẫu (bảng tin, Bếp nhanh) dùng clip công khai của Flutter docs (`bee.mp4`, `butterfly.mp4`) và MDN (`flower.mp4`, CC0). Thay bằng URL Cloudinary khi BE sẵn sàng.

## Chạy với BE thật

### Khởi động BE

BE là ASP.NET Core + MongoDB, **target .NET 9** (`net9.0`).

```powershell
cd BE/ControllerLayer
# Máy chỉ có runtime .NET 10 (không có .NET 9) thì cho chạy lên bản major kế tiếp:
$env:DOTNET_ROLL_FORWARD = "Major"
dotnet run --no-launch-profile --urls http://localhost:5001
```

- Chuỗi kết nối và JWT cấu hình như `BE/README.md`. Nên dùng một database thử riêng: chạy `integration_test_be` để lại tài khoản, công thức, booking và tiền thử.
- Không có khoá Gemini thì `/vision/scan` trả kết quả mẫu; chatbot trả 503 `ai_unavailable` và app nói rõ, không có câu trả lời giả; tài liệu kiến thức ở `Pending` với `ingestStatus: Failed`. Admin tắt chatbot ở web `/ai-models` thì trả 503 `ai_disabled`. Không có khoá Cloudinary thì tệp nằm trong `wwwroot/uploads`.
- Chưa có email thật. Khi phát triển: chạy `Development` với `Auth__DevResetCodes=true`, rồi `GET /api/v1/dev/auth/reset-code?email=` (B23). Môi trường khác luôn 404.
- `appsettings.Development.json` bật cổng thử nghiệm `Payment:Provider=Sandbox` (không có tiền thật, bị bỏ qua ở Production) và `Payment:SandboxSelfConfirm`: người mua tự xác nhận giao dịch của mình bằng nút trên màn thanh toán (`POST /payments/{id}/sandbox-confirm`), admin xác nhận được mọi giao dịch. Bỏ cổng (`Payment__Provider=` để trống) thì route tạo QR trả 503 `payment_unavailable`, app nói rõ ở màn thanh toán và vẫn trả được bằng ví.
- Môi trường Development seed sẵn ba tài khoản (mật khẩu ở `BE/InfrastructureLayer/Seed/DatabaseSeeder.cs` và `TAI_LIEU_API_CHO_FRONTEND.md`): quản trị `admin@veganlife.vn` (chỉ đăng nhập được ở web), chuyên gia `chef.hoang@veganlife.vn`, thành viên `minhanh.nguyen@gmail.com`.

### Chạy app

```bash
cd FE/Mobile
flutter run --dart-define=USE_MOCK_DATA=false                  # Android emulator: http://10.0.2.2:5001/api/v1
```

- `10.0.2.2` là máy host khi nhìn từ emulator, và là `API_BASE_URL` mặc định. Máy thật: `adb reverse tcp:5001 tcp:5001` rồi thêm `--dart-define=API_BASE_URL=http://localhost:5001/api/v1`.
- HTTP thường chỉ được phép ở bản debug (`android/app/src/debug/AndroidManifest.xml`); profile và release không đổi. iOS chưa kiểm tra được trên máy này.
- Tài khoản: tự đăng ký trong app, hoặc dùng tài khoản seed ở trên (các chip thử nghiệm ở màn Đăng nhập tự ẩn). Muốn thử vai trò `Chef`, dùng `chef.hoang@veganlife.vn`.

Bật/tắt từng module, không cần sửa code (mọi quyết định nằm trong `lib/core/config/backend_modules.dart`):

```bash
flutter run --dart-define=USE_MOCK_DATA=false \
  --dart-define=BACKEND_MOCK_MODULES=community,scanner \
  --dart-define=BACKEND_REAL_MODULES=video
```

Tên module không phân biệt hoa thường, tên lạ bị bỏ qua. Có trong cả hai danh sách thì là mock. `auth` mock thì **mọi** module đều mock (module thật cần JWT).

### Module: thật hay mock

Với `USE_MOCK_DATA=false`, hôm nay:

| Module | Mặc định | Ghi chú |
|---|---|---|
| `auth`, `profile` | Thật | JWT hết hạn thì tự làm mới; đơn đăng ký chuyên gia gửi lên `POST /chef-applications`, Web duyệt ở `/chefs` |
| `community`, `reels`, `media` | Thật | Bảng tin phân trang bằng `cursor`/`limit`; bài đã lưu lưu trên máy |
| `planner`, `pantry`, `ingredients`, `allergens` | Thật | Check-in cân nặng: POST metrics rồi đọc lại hồ sơ |
| `recipes` | Thật | Trang công thức đọc `GET /recipes/{id}`; danh mục đọc qua swap-suggestions với thực đơn của thành viên, chưa có thực đơn thì `/from-ingredients`; id mock (`l5`, `menu_1`, `cs_…`) vẫn mở bằng mock |
| `scanner` | Thật | "Gợi ý món" chọn ngay trên máy từ danh mục, **không đụng tới thực đơn** |
| `video` | Mock, **cố ý** | Quyết định của người dùng: BE trích xuất công thức từ video chưa chạy với mô hình thật. Bài công thức có video mở công thức mẫu có nhãn (`test/hybrid/video_sample_recipe_test.dart`) |
| `recipeSocial` | Thật | Đánh giá và ghi chú của công thức thật qua `GET`, `PUT`, `DELETE /recipes/{id}/reviews…`, `/notes/me`. Công thức của thành viên không có đánh giá. Món chỉ biết qua thực đơn thì không có cả hai. Công thức mẫu còn sót (id mock, ví dụ từ "Đã xem gần đây" của bản cũ) đi vào mock và có banner. "Lưu thành công thức của tôi" vẫn dùng `POST /recipes`: `/recipes/{id}/variants` cần `ingredientItems` mà công thức seed chưa có |
| `chatbot` | Thật | SSE `POST /chat/sessions/{id}/messages`. BE không có AI hoặc admin tắt chatbot: 503 `ai_unavailable`, `ai_disabled`, câu hỏi ở lại, bong bóng ghi lý do và "Thử lại", không có câu trả lời giả, khách không mất lượt |
| `restaurants`, `ads` | Thật | Quán chỉ công khai sau khi admin duyệt ở web `/restaurants`; "Quán tôi đã gợi ý" đọc trạng thái và lý do từ chối. Ảnh gợi ý gửi đúng đường dẫn upload (BE khớp với tệp của chính người gợi ý). Chiến dịch ở web `/ads`; `impression`, `click` đếm thật |
| `geocoding` | Mock, **cố ý** | BE trả 503 `geo_unavailable` khi không có `Geo:BaseUrl`, và bản demo không cấu hình bộ định vị (Nominatim công khai có chính sách dùng riêng). Bản thật sẽ làm ô tìm địa chỉ báo lỗi mỗi lần gõ, nên app giữ danh sách địa điểm mẫu, có banner ở màn Chọn vị trí. Toạ độ chọn trên bản đồ vẫn là thật. Có bộ định vị thì bật bằng `BACKEND_REAL_MODULES=geocoding` |
| `search` | Thật | `GET /search`, `/search/suggest`, `/search/discover`. Không có xu hướng, món theo mùa: mục đó không hiện. `BACKEND_MOCK_MODULES=search` thì tìm trên client |
| `chefs`, `bookings`, `commerce`, `chefStudio`, `chefWallet` | Thật | Đã qua `integration_test_be/money_be_test.dart`. **Bật hoặc tắt cùng nhau** (`BACKEND_MOCK_MODULES=chefs,bookings,commerce,chefStudio,chefWallet`): booking đặt với chuyên gia trong danh bạ, đơn và tiền phải cùng một bên. Tắt thì tài khoản thật đóng vai dữ liệu mẫu: thành viên là Minh Anh (`u_me`), vai trò Chef là Tâm (`u_chef_tam`). Danh bạ rỗng cho tới khi có chuyên gia được duyệt đơn hoặc lưu hồ sơ (seed "Chef Hoàng" chưa có hồ sơ) |

**Banner "Dữ liệu mẫu · Máy chủ chưa hỗ trợ tính năng này"**: màn hình này đang hiện dữ liệu mẫu trong app, không phải dữ liệu của bạn trên máy chủ, vì module đó còn mock. Trên bản mặc định `USE_MOCK_DATA=false` chỉ còn: màn Chọn vị trí (`geocoding`), công thức mẫu của video (`video`) và trang một công thức mẫu còn sót. Bản hoàn toàn mock không có banner.

### Hành vi bị giới hạn khi chạy BE thật

| Ở đâu | Khi nào | App làm gì |
|---|---|---|
| Tạo bài viết | Video trên 100 MB | "Video MP4, MOV, WEBM tối đa 100 MB" |
| Nội dung của tôi › Đã lưu | Luôn luôn | "Bài đã lưu chỉ nằm trên máy này." |
| Nội dung của tôi › Bài của tôi | Hơn 250 bài | Đọc `GET /users/me/posts`, mọi trạng thái, từ mọi thiết bị, dừng ở 250 bài mới nhất: "Đang hiện 250 bài mới nhất của bạn." |
| Bài bị từ chối | BE trả `rejectionReason` | "Bị từ chối: {lý do}" |
| Bài bị ẩn | Admin ẩn bài, BE không lưu lý do | Tác giả thấy "Đã ẩn: Ban quản trị đã ẩn bài này nên bài không hiển thị trên bảng tin."; người khác: "Bài viết này không còn hiển thị." khi mở hoặc khi đang xem |
| Chi tiết bài, Bếp nhanh | Module `video` còn mock | "Xem công thức" mở công thức mẫu có nhãn; không có chip AI thật |
| Tôi | Số bài, lượt thích | Số thật từ `/users/me`; "Đã lưu" đếm trên máy này |
| Thực đơn | BE đọc theo quy tắc, không gọi AI | Ghi "Chỉnh thực đơn" thay vì "… với AI" |
| Thực đơn | Tạo thực đơn | Món có "2,35 phần", kcal và macro đã nhân phần ăn (`calories` của BE là cho một phần) |
| Thực đơn | Chưa có thực đơn tuần này | "Tạo thực đơn" / "Tự lên thực đơn"; "Áp dụng kế hoạch" báo cần tạo thực đơn trước |
| Danh mục công thức | Chưa có thực đơn tuần này | Tối đa 10 món hợp với tủ lạnh, cộng công thức của mình: nguyên liệu chỉ hiện món trong số đó, "Gợi ý món" chỉ tìm trong số đó (không ra món nào thì nêu lý do, kèm "Mở Thực đơn"). Trang công thức vẫn mở được bằng id. Không tự tạo thực đơn |
| Check-in cân nặng | Ngoài khoảng của form | Không gửi: "Cân nặng từ 30 đến 250 kg" (BE nhận 20–300) |
| Check-in cân nặng | Chưa có hồ sơ (404) | Thẻ và nút chỉ hiện khi có hồ sơ; nếu vẫn gặp, sheet giữ số đã nhập và hiện lời của BE |
| Check-in cân nặng | Đã lưu mà không đọc lại được hồ sơ | Vẫn tính là đã lưu; phần đánh giá dùng hồ sơ đang có trên màn hình |
| Trang công thức thật | 29 công thức seed | Chỉnh được số người, đổi nguyên liệu (thành phần chính chỉ đổi trong cùng vai trò), danh sách đi chợ, lưu, thêm vào Thực đơn. Định lượng là số tham khảo trong `lib/features/recipe/data/backend_recipe_items.dart`. Mỗi phần vẫn hiện kcal của BE; đổi nguyên liệu thì tính lại và ghi "≈". Không có đánh giá, ghi chú |
| Trang công thức thật | Công thức thành viên tự viết, tên lạ | Chỉ đọc: "Công thức này do thành viên tự viết nên chưa có vai trò và lựa chọn thay thế cho từng nguyên liệu: chưa chỉnh được số người hay đổi nguyên liệu ở đây." |
| Lưu công thức đã chỉnh | App chưa nối `/variants` | POST `/recipes`, định lượng theo số phần gốc; bước đầu của `instructions` ghi "Biến thể của «…» · Định lượng cho N phần · Năng lượng là ước tính." để app đọc lại; sửa tại chỗ (PUT) giữ dòng này |
| Hồ sơ sức khoẻ | Hồ sơ cũ ghi "Khác" | Không chọn sẵn gì; "Lưu" yêu cầu chọn Nam hoặc Nữ |
| Trang món tự nhập | Không có công thức | "Món này chưa có chi tiết công thức." |
| Hồ sơ chuyên gia | Chưa có email thật | Form không hứa gửi email; đơn chờ duyệt: "Ban quản trị sẽ phản hồi trong 1–3 ngày làm việc." |
| Thanh toán | Không có cổng (503) | Ở lại màn thanh toán: "Chưa thanh toán qua cổng được" · "Cổng thanh toán đang chưa sẵn sàng nên chưa tạo được mã QR. Bạn chưa bị trừ tiền.", có "Thử lại" và nút ví. Không bao giờ hiện đã trả nếu máy chủ chưa nói vậy |
| Thanh toán | Cổng `Sandbox` | "Cổng thử nghiệm, không có tiền thật: mã này không quét được, quản trị viên xác nhận giao dịch." App không có nút xác nhận |
| Thanh toán | Cổng thật không gửi ảnh QR | "Máy chủ chưa gửi mã QR.", không tự vẽ mã giả |
| Quét | Không có ảnh | "Chưa có ảnh để quét. Hãy chụp hoặc chọn ảnh khác."; không chọn ảnh nào: "Bạn có thể chụp bằng camera hoặc nhập tay." |
| Tủ lạnh | App thấy không thuần chay | Không gửi, vì BE chỉ gắn cờ chứ vẫn lưu: "{tên} không thuần chay nên không thêm vào tủ." kèm "Gợi ý thay thế" |
| Tủ lạnh | Chỉ BE thấy không thuần chay (VD "Tiết canh") | Xoá dòng vừa thêm: "Máy chủ xếp {tên} vào nhóm không thuần chay nên chưa thêm vào tủ." Dòng như vậy có sẵn trong tủ: nhãn "Máy chủ ghi: không thuần chay" |
| Tủ lạnh | Thêm trùng tên (B34) | Vẫn một dòng, BE giữ số lượng; không cảnh báo gì |
| Tủ lạnh | Dị ứng (B14) | "Bạn đã khai báo dị ứng với đậu phộng" |
| Quên mật khẩu | Bản debug (B23) | "(Bản thử nghiệm) Máy chủ chưa gửi email: xem mã trong nhật ký máy chủ." |
| Mọi request | 401 khi đang đăng nhập | Làm mới token (một lần cho mọi request đang chờ), lưu token mới, gửi lại request một lần. Mất mạng hoặc 5xx lúc làm mới: giữ phiên. BE từ chối refresh token: đóng mọi trang, về chế độ khách, snackbar "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại." |
| Đăng xuất | Luôn luôn | Xoá trên máy trước, báo BE sau (không chờ, được phép lỗi), nên vẫn đăng xuất được khi mất mạng; khi đó refresh token còn sống ở BE |
| Mọi request | Lỗi có `errors` | Hiện thông báo của từng trường; lời tiếng Anh của framework bị bỏ |
| Quên mật khẩu | Sai mã 5 lần, hoặc mã đã hết hạn | Hiện lời của BE; "Gửi lại mã" dùng được ngay |
| Mọi request | Thông báo sai bảng mã (BE đã hết sau B35, giữ để phòng) | Hiện câu theo mã trạng thái |

### Bộ test với BE thật (`integration_test_be`)

Gọi các service `Remote*` thật qua Dio thật, tới BE đang chạy. `content_be_test.dart`: quán, quảng cáo, `/search`, đánh giá và ghi chú công thức, `/geo` 503. `search_be_test.dart`: tìm trên client khi `search` bị ép mock. `chat_be_test.dart` và `chat_no_ai_be_test.dart` chỉ chạy khi được bật, xem dưới. Nằm ngoài `test/` nên `flutter test` thường không chạy nó. Tài khoản do bộ test tự đăng ký (email và mật khẩu ngẫu nhiên lúc chạy, không in ra); không lưu bí mật nào trong repo.

```bash
cd FE/Mobile/integration_test_be
flutter test . --concurrency=1 --dart-define=USE_MOCK_DATA=false --dart-define=API_BASE_URL=http://localhost:5002/api/v1
flutter test . --tags be-bug-pin --dart-define=USE_MOCK_DATA=false --dart-define=API_BASE_URL=http://localhost:5002/api/v1   # chỉ các lỗi BE
```

- **Phải chạy từ trong thư mục này.** `flutter test integration_test_be` từ gốc dự án dừng với lỗi `cannot run without a dependency on "package:integration_test"`: flutter_tools coi mọi đường dẫn bắt đầu bằng `<gốc>/integration_test` là test chạy trên thiết bị. Không cần thêm thư viện.
- **Chatbot**: `chat_be_test.dart` cần BE có Gemini (giả cũng được: `Gemini__BaseUrl`, `Gemini__ApiKey`, `Rag__MinScore=0.15`) và `--dart-define=RAG_QA=true`. `chat_no_ai_be_test.dart` cần BE không có Gemini và `--dart-define=NO_AI_QA=true`. Bộ đầy đủ chạy trên BE không có Gemini, vì `vision_be_test.dart` dựa vào kết quả mẫu của BE khi thiếu khoá.
- `--concurrency=1` vì các file dùng chung một bảng tin; bài mới của file khác làm lệch trang khi đang thử phân trang.
- BE tắt, hoặc thiếu `USE_MOCK_DATA=false`: mọi test **skip** kèm lý do ("BE down at …") và thoát 0. Không chạy được khi thiếu `API_BASE_URL`, vì mặc định `10.0.2.2` chỉ dùng được từ emulator.
- Test `guardFixed` trong `be_bug_pins_test.dart` đỏ nghĩa là **lỗi đã sửa quay lại**: app không còn phần chữa tạm, thông báo nêu chỗ bị ảnh hưởng. Một lỗi mới thì thêm lại `pinBug`: ghim hành vi sai, đỏ khi BE đã sửa.
- **Chạy BE cho bộ này**: `DatabaseName=VeganLifeDB_FEIT3`, `ASPNETCORE_ENVIRONMENT=Development`, `Auth__DevResetCodes=true`, `Payment__Provider=Sandbox`. Thiếu Sandbox thì các test tiền skip kèm lý do, và nhóm "without a gateway" chạy.
- **`money_be_test.dart` tua thời gian** bằng `mongosh`: dời ngày của đúng booking do test tạo trong `VeganLifeDB_FEIT3`, không có id đó thì báo đỏ và không ghi gì. Cần `mongosh` trong PATH.
- Vài test đăng nhập tài khoản seed (mật khẩu lấy từ `DatabaseSeeder.cs`). Test tiền đặt lịch với seed "Chef Hoàng", nên ví của tài khoản đó tăng dần: test so trước và sau, không so tổng.
- Tuần của BE tính theo UTC+7 cố định: máy chạy test ở múi giờ khác có thể đỏ quanh nửa đêm thứ Hai.

### Kiểm tra trên thiết bị (emulator, BE thật)

1. Đăng ký → vào app; màn Đăng nhập không có chip thử nghiệm. Tắt và mở lại → vẫn đăng nhập, Tôi hiện đúng tên.
2. Sai mật khẩu, trùng email, sai định dạng → tiếng Việt đúng dấu, không bao giờ tiếng Anh hay chữ lỗi bảng mã. Quên mật khẩu với mã trong log BE; mật khẩu mới dùng được.
3. Hồ sơ sức khoẻ: chọn "Đậu phộng" và một dị ứng tự nhập, mục tiêu Giảm cân → mục tiêu ≈ −15 %.
4. Tạo thực đơn: không có món đậu phộng, kcal trong ngày gần mục tiêu, món có "1,5 phần". Đổi món mở đúng công thức, "Hoàn tác" được, tự nhập món có macro, "Bỏ món" được, "Tự lên thực đơn" làm trống tuần.
5. Tủ lạnh: thêm, món không thuần chay bị từ chối ("Rau chan vit": máy chủ từ chối), đậu phộng báo dị ứng bằng tên tiếng Việt, thêm trùng tên giữ số lượng, vuốt xoá + "Hoàn tác", "Xoá hết", sửa số lượng và hạn dùng.
6. Quét: khung nhận diện, phần không thuần chay, lưu vào tủ, "Gợi ý món" ra công thức thật, thêm vào thực đơn; **các ngày khác không đổi**.
7. Bảng tin: đăng bài có ảnh và video thật, cả hai hiện và phát được. Cuộn quá 10 bài không quay vòng. 11 bình luận trở lên tải được trang 2; "Xem thêm N phản hồi" đọc hết; xoá bình luận gốc xoá luôn phản hồi và giảm đúng số; không có "(đã sửa)".
8. Thích, bỏ thích, thích lại đều đúng sau khi tải lại. Báo cáo hai lần → thông báo 409. Xoá bài của mình. Lưu bài → "Đã lưu" có ghi chú, còn sau khi mở lại app.
9. Theo dõi cân nặng: check-in chỉ hỏi cân nặng, biểu đồ BMI trong sheet hiện vùng xanh và số đang nhập, cân nặng 5 kg bị từ chối, mục tiêu năng lượng đổi theo, lịch sử không còn vòng eo và tỉ lệ mỡ.
10. Chuyên gia: banner, yêu cầu mẫu của Minh Anh, thanh toán bằng nút mô phỏng, "Áp dụng kế hoạch" vào thực đơn thật. Tìm `bun rieu` → công thức mẫu → thêm vào thực đơn thật.
11. Đăng xuất → bảng tin vẫn thật, thao tác cần đăng nhập mở sheet; tắt mạng vẫn đăng xuất được. `vl.access_token` sai hoặc `vl.expires_at` đã qua → tự làm mới, vẫn đăng nhập. Thêm `vl.refresh_token` sai → snackbar và về chế độ khách.
12. Chưa có thực đơn tuần này: nguyên liệu vẫn có công thức, mở được trang công thức, "Thêm vào Thực đơn" dẫn tới tab Thực đơn; "Gợi ý món" chỉ ra món trong số hợp với tủ lạnh.

### Lỗi từ máy chủ không làm app chết

`test/resilience/` chạy module thật qua Dio thật với máy chủ giả trả dữ liệu hỏng (thiếu trường, toàn null, sai kiểu, `data: null`, thân rỗng, HTML, JSON đứt, `success: false`, 400/401/403/404/409/429/500/502, hết giờ, mất kết nối giữa chừng), và từng trường một của thân đúng. Tiêu chí: không có exception, không có khung lỗi, không kẹt vòng xoay, không lộ chữ kỹ thuật. Thân sai dạng trong service thành `ApiException` (`code: bad_data`) tại `guardApi`. Lỗi lúc vẽ widget hiện `buildErrorFallback` thay cho màn đỏ hoặc xám. Kiểm thử không chứng minh được là hết crash; phần chưa chạy ghi trong báo cáo QA.

### Khi nối các module còn mock

1. Đổi một dòng trong `BackendModules.supportedByBackend` hoặc getter năng lực tương ứng, rồi gỡ phần chạy vòng mà test ghim lỗi chỉ ra.
2. Lỗi đăng nhập theo hợp đồng: 401 `invalid_credentials`, 403 `admin_web_only`, 423 `account_locked`, 409 `email_taken`, 429 `too_many_attempts` (BE thật chưa gửi `code`, app dựa vào mã trạng thái). Chuyển token sang secure storage trước khi phát hành.
3. Chat dùng SSE (`text/event-stream`) với các sự kiện `token`, `citation`, `done`, `error`. Khách gửi kèm `X-Guest-Token`; server trả `402` / `trial_exhausted` khi hết lượt.
4. Cổng thanh toán thật: BE tạo mã QR và nhận webhook có chữ ký; app chỉ hỏi `GET /payments/{id}` mỗi 3 giây và vẽ `qrCodeUrl`. Nút mô phỏng thanh toán chỉ có khi `commerce` là mock.
5. Chưa có (cần thêm thư viện, chờ duyệt): GPS thật (`geolocator`), lưu token an toàn. Dữ liệu dinh dưỡng là số tham khảo; lời lẽ về sức khoẻ phải giữ thận trọng.
6. Công thức: seed cần `ingredientItems` trong `RecipeResponse` (rồi xoá `backend_recipe_items.dart`). Một dòng có dạng:
   `{ "key": "dau_hu", "name": "Đậu hũ", "quantity": 200, "unit": "g", "role": "Riêu", "isSignature": true, "isOptional": false, "allergens": ["soy"], "nutrition": { "calories": 152, "proteinG": 16.2, "carbsG": 3.8, "fatG": 9.6, "fiberG": 0.6 }, "substitutes": [ { "key": "…", "name": "Đậu hũ non", "quantity": 280, "unit": "g", "role": "Riêu", "note": "…", "allergens": ["soy"], "nutrition": { } } ] }`
   `nutrition` là phần của cả công thức ở `quantity`, cho `servings` phần.
