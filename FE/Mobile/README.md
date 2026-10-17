# VeganLife Mobile (Flutter) — nền tảng chính

VeganLife là **mobile-first**: mọi hành trình của khách, thành viên và chuyên gia đều nằm trong app này. `FE/Web` chỉ là **admin console** để kiểm duyệt, xử lý khiếu nại và quản lý.

Feature-first Flutter, **Riverpod** cho state, **Dio** cho API. Feature nào cũng có abstract API service + **Mock repository**, nên app chạy được trước khi backend ASP.NET Core sẵn sàng. UI tiếng Việt.

## Điều hướng

Thanh dưới: **Trang chủ · Thực đơn · [Quét] · Chuyên gia · Tôi**. Mọi vai trò (thành viên, chuyên gia) có **cùng 5 vị trí**; công cụ của chuyên gia nằm trong **Tôi › Chuyên gia**.

| Vị trí | Màn hình | Khách xem được? |
|---|---|---|
| Trang chủ | Bảng tin cộng đồng, dải **Bếp nhanh** (video ngắn dọc), ô "Hôm nay {tên} nấu món gì?"; app bar có **Tìm kiếm** và **Quán chay gần bạn** | Xem: có · Tương tác: cần đăng nhập |
| Thực đơn | Thực đơn tuần theo "Các bữa trong ngày", "Chỉnh thực đơn với AI", thẻ **Nguyên liệu trong tủ**, thẻ **"Cần thực đơn riêng? Nhờ chuyên gia thiết kế"** | Cần đăng nhập |
| **Quét** (nút tròn giữa) | Chạm: quét tủ lạnh bằng cách đã dùng lần trước. Giữ: chọn **Chụp hình / Chọn ảnh / Nhập tay** (lựa chọn được nhớ). Mở toàn màn hình | Cần đăng nhập |
| Chuyên gia | Danh bạ đầu bếp / chuyên gia dinh dưỡng đã xác minh, hồ sơ và bảng giá, **Đặt chuyên gia lên thực đơn** | Xem: có · Đặt: cần đăng nhập |
| Tôi | Hồ sơ, Hồ sơ sức khoẻ, Nội dung của tôi, **Lịch sử tư vấn**, khu **Chuyên gia** (chỉ vai trò Chef), Thông tin cá nhân, Giao diện, Đăng xuất | Cần đăng nhập |
| Bong bóng **Hỏi AI** | Chat-head kiểu Messenger. Khi đứng yên chỉ là một dải mảnh 12×56dp sát mép (mặc định mép trái, ~38% chiều cao), nằm trong lề 16dp của màn hình nên không che nút nào; chạm vào dải là mở chatbot RAG có trích dẫn. Kéo ra thành bong bóng 56dp, thả là bám mép trái/phải gần nhất (nhớ vị trí), 1,5 giây sau tự thu lại thành dải. Giữ để "Ẩn bong bóng" / "Đưa về vị trí mặc định". Ẩn khi cuộn danh sách, khi bàn phím mở, trên hộp thoại và trên màn quét, Bếp nhanh, thanh toán, chat (màn nào bọc `AskAiBubbleFree` cũng ẩn). Trên Android 10+ vùng dải/bong bóng được loại khỏi cử chỉ vuốt "quay lại" (`setSystemGestureExclusionRects` qua MethodChannel `vn.veganlife/gesture_exclusion` trong `MainActivity.kt`). Khách hỏi miễn phí 3 lần (`GUEST_TRIAL_LIMIT`) | Có |

**Thanh tab nổi**: khối bo tròn cách mép 12dp, nằm trên vùng cử chỉ hệ thống; tab đang chọn có nền tô nhạt trượt theo; nút **Quét** tròn nằm trong phần khoét giữa thanh và nhô lên. Nội dung các tab cuộn phía sau thanh; khoảng trống cuối danh sách lấy từ `floatingBarClearance(context)` (`lib/core/widgets/floating_bar_clearance.dart`).

## Đăng nhập & tài khoản

- **Chỉ email + mật khẩu** (không có đăng nhập Google). Màn hình: **Welcome** → **Đăng nhập** / **Tạo tài khoản** / **Quên mật khẩu**.
- **Welcome** chỉ hiện ở lần mở đầu tiên khi chưa đăng nhập (`vl.onboarded`): "Đăng nhập", "Tạo tài khoản", "Khám phá không cần đăng nhập". Đăng xuất quay về Trang chủ ở chế độ khách, không về Welcome.
- **Đăng nhập**: "Email", "Mật khẩu" (hiện/ẩn), "Quên mật khẩu?", "Chưa có tài khoản? Đăng ký". Bản mock có chip **"Điền tài khoản thử nghiệm: Thành viên · Chuyên gia"**.
- **Tạo tài khoản**: "Bạn là" **Thành viên / Chuyên gia**, họ tên, email, số điện thoại (không bắt buộc), mật khẩu ≥ 8 ký tự gồm chữ và số, nhập lại, đồng ý điều khoản. `POST /auth/register` **luôn tạo vai trò `User`**; chọn Chuyên gia thì sau khi đăng ký mở "Bước 2/2: Hồ sơ chuyên gia". Vai trò thành `Chef` chỉ khi admin duyệt ở web `/chefs`; trong lúc chờ, Tôi hiện "Hồ sơ chuyên gia đang chờ duyệt".
- **Quên mật khẩu** (3 bước một màn): email → "Gửi mã" → nhập mã 6 số ("Gửi lại mã (0:59)") → "Mật khẩu mới" → "Đổi mật khẩu" → quay về Đăng nhập, email điền sẵn.
- **Khách** xem được bảng tin, chi tiết bài, Bếp nhanh, tìm kiếm, quán chay (danh sách, bản đồ, chi tiết) và danh bạ chuyên gia. Mọi thao tác khác (thích, bình luận, lưu, báo cáo, đăng bài, đánh giá, gợi ý quán, đặt chuyên gia, Thực đơn, Quét, Tôi, câu hỏi AI thứ 4) mở sheet **"Tham gia cộng đồng VeganLife"** ("Đăng nhập" / "Tạo tài khoản" / "Để sau"); đăng nhập xong thao tác được làm tiếp.
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
- **Chi tiết bài**: video phát ngay trong bài, **"Xem công thức"** (khi AI đã trích công thức) mở sheet Tóm tắt AI / Nguyên liệu / Các bước / Lời thoại, "Sao chép danh sách đi chợ", chạm mốc thời gian để tua video phía sau; chip trạng thái AI và "Thử trích xuất lại" (tác giả). Link trong nội dung bấm được.
- **Bình luận** ngay trong chi tiết bài (không còn trang bình luận riêng): mỗi lần tải 10 bình luận, **mới nhất trước**, tải thêm khi cuộn; mỗi bình luận gốc xem trước 2 phản hồi rồi "Xem thêm N phản hồi". Ô **"Viết bình luận…"** ghim ở đáy. Phản hồi **một cấp**: trả lời một phản hồi thì gắn vào cùng bình luận gốc và thêm "@Tên ". "Đang trả lời {tên} · Huỷ", "Đang sửa bình luận · Huỷ"; xoá bình luận gốc hỏi "Xoá bình luận và N phản hồi?". Bài chưa hiển thị trên bảng tin không nhận bình luận.
- **Bếp nhanh** (màn xem video dọc): "Bình luận" mở sheet bình luận (cùng luồng và ô viết), "Xem công thức" mở sheet công thức; không có nút Chia sẻ. Video dừng khi sheet mở.
- **Tạo bài viết** kiểu Facebook: "✕ · Tạo bài viết · Đăng" (sửa: "Sửa bài viết · Lưu"), Công thức / Hỏi đáp, tiêu đề ≤ 120, nội dung ≤ 3000, thanh **"Thêm vào bài viết"**: **Ảnh/Video** (ảnh jpg/png/webp/heic ≤ 10 MB, video mp4/mov/webm ≤ 200 MB; tiến độ "Đang tải lên 42 %", "Huỷ tải lên", "Thử lại", "Đổi"), **Gắn quán** (tìm + quán gần bạn), **Gắn thẻ**. "Đăng" bị khoá khi đang tải lên. AI chỉ trích công thức cho **Công thức + video**.
- **Trạng thái bài**: đăng là lên bảng tin, trừ khi AI sàng lọc gắn cờ → **Chờ duyệt** (chỉ tác giả thấy). Admin duyệt → Đã đăng; từ chối → **Bị từ chối** kèm lý do và "Sửa & gửi lại".
- **Nội dung của tôi** (Tôi): Bài của tôi (Tất cả / Đã đăng / Chờ duyệt / Bị từ chối) · Đã lưu · Bình luận (mở bài và tô sáng đúng bình luận).

### Tìm kiếm

- **Chưa gõ**: Tìm gần đây ("Xoá lịch sử"), Xu hướng tìm kiếm (top 6), Danh mục (Món chính, Ăn sáng, Bún & phở, Đồ uống, Tráng miệng, Món nhanh < 20 phút), Món theo mùa, Công thức được yêu thích, Đã xem gần đây (`vl.recent_views`, tối đa 10, chỉ tính mục mở từ tìm kiếm), Quán chay gần bạn.
- **Đang gõ**: chỉ danh sách gợi ý (chờ 250 ms), dòng đầu "Tìm «…»"; chạm công thức / bài / quán là mở luôn.
- **Kết quả**: chỉ sau Enter hoặc "Tìm «…»": tab **Tất cả · Công thức · Video · Bài viết · Quán**. Sửa chữ → quay lại gợi ý; ✕ → về trạng thái chưa gõ. Tìm không dấu.

### Quán chay, bản đồ & chỉ đường

- **Quán chay gần bạn**: chip vị trí "📍 {nơi} ▾" → **"Chọn vị trí"** (tab Tìm địa chỉ / Chọn trên bản đồ, "Dùng vị trí hiện tại (mô phỏng)", vị trí gần đây); ô tìm; **Bộ lọc** (chỉ quán đã chứng nhận thuần chay, sắp xếp Gần nhất / Đánh giá cao, bán kính 1 / 3 / 5 / 10 km / Không giới hạn, "Đặt lại" / "Áp dụng"); chip bộ lọc đang bật. **"Xem bản đồ" / "Xem danh sách"**: bản đồ có điểm của bạn, quán đã chứng nhận (xanh), quán khác (xám), quán tài trợ (có viền); chạm điểm → thẻ "Xem quán" / "Chỉ đường"; kéo bản đồ → "Tìm trong khu vực này". Đổi vị trí thì khoảng cách và thứ tự đổi ở mọi nơi (danh sách quán, tab Quán của tìm kiếm, gợi ý).
- **Được tài trợ**: tối đa **một** dòng ở đầu danh sách (và điểm nổi bật trên bản đồ); app gửi `POST /ads/{id}/impression` lần hiển thị đầu và `/click` khi bấm. Chiến dịch do admin quản lý ở web `/ads`.
- **Chi tiết quán**: bản đồ nhỏ 180dp (chạm → bản đồ lớn), "Ảnh & video", phân bố sao, "Viết đánh giá" (mỗi người 1 đánh giá, gửi lại là sửa). **"Chỉ đường"** vẽ tuyến trong app (OSRM, "2,6 km · ≈ 9 phút đi xe", "Từ: {nơi} · Đổi"); lỗi hoặc quá 5 giây → đường thẳng + "Không tải được tuyến đường — hiển thị đường thẳng". "Mở bằng Google Maps" chỉ ở menu ⋮ (OSRM không có dẫn đường từng bước). Quán chưa có toạ độ: "Quán chưa có vị trí trên bản đồ".
- **Gợi ý quán mới**: thẻ "Vị trí quán" với bản đồ nhỏ và 3 nút (Chọn trên bản đồ, Tìm địa chỉ, Dùng vị trí hiện tại) điền địa chỉ (vẫn sửa được) và toạ độ; thiếu toạ độ thì cảnh báo; tối đa 5 ảnh và 1 video giới thiệu. Quán hiện ngay với "Chưa chứng nhận" và "Được gợi ý bởi …".
- **Chính sách bản đồ**: ô bản đồ OpenStreetMap gửi `User-Agent` `vn.veganlife.veganlife_mobile`, có ghi công "© OpenStreetMap contributors", không tải hàng loạt. Máy chủ ô OSM công cộng không cho lưu lượng production nặng → đổi `MAP_TILE_URL`. OSRM demo công cộng chỉ có profile ô tô, ~1 request/giây, không SLA → app chỉ hỏi một lần mỗi màn chỉ đường, có cache; production nên dùng OSRM tự host (hoặc VietMap) sau BE. **Geocoding** đi qua BE (`/geo/search`, `/geo/reverse`), app không gọi thẳng Nominatim. "Dùng vị trí hiện tại" vẫn là **mô phỏng** (Quận 1) vì chưa duyệt thư viện GPS (`geolocator`).

### Thực đơn, tủ lạnh & hồ sơ sức khoẻ

- **Hồ sơ sức khoẻ**: chiều cao, cân nặng, **Giới tính** (Nam / Nữ / Khác), **Năm sinh** (13–100 tuổi, hiện "29 tuổi"), **Mức vận động** (Ít / Nhẹ / Vừa / Nhiều), mục tiêu (Giảm cân / Giữ cân / Tăng cơ / Tăng cân), **Dị ứng** là chip nhập tự do ("Nhập thành phần bạn dị ứng…", gợi ý không dấu từ `/catalog/allergens`, cho phép tên lạ như "lá lốt"), **Các bữa trong ngày** ("2 bữa", "3 bữa", "3 bữa + 1 phụ", "5 bữa nhỏ" hoặc tự chọn trong 6 bữa: Bữa sáng, Phụ sáng, Bữa trưa, Phụ chiều, Bữa tối, Phụ tối; ít nhất 1). Thẻ đầu hiện BMI và "Nhu cầu ≈ 1.900 kcal/ngày" (BMR/TDEE Mifflin–St Jeor; "Khác" lấy trung bình hai hằng số; mục tiêu −15 % / 0 / +5 % / +10 %). Mọi con số năng lượng (nhu cầu, BMR, mục tiêu ngày, tóm tắt gửi chuyên gia) tính từ một công thức trong `core/utils/energy.dart` và làm tròn **một lần** tới 10 kcal; lưu hồ sơ làm đổi mục tiêu thì tuần thực đơn hiện tại nhắm theo mục tiêu mới. **Tài khoản mới chưa có hồ sơ sức khoẻ**, thực đơn hay tủ lạnh: Thực đơn và Tôi hiện thẻ "Thiết lập hồ sơ sức khoẻ", form mở trống.
- **Thực đơn tuần**: bữa theo "Các bữa trong ngày"; **"＋ Thêm bữa"** thêm một bữa cho riêng ngày đó. Tạo bằng AI (kcal chia theo trọng số bữa từ TDEE), "Tự lên thực đơn" hoặc "Tạo thực đơn từ tủ lạnh". Chọn món từ **4 nguồn**: AI gợi ý (±10 % kcal, an toàn dị ứng) · Công thức của tôi · **Từ chuyên gia** (món của kế hoạch chuyên gia đã giao) · Tự nhập món. Macro không bịa: món thiếu macro thì ẩn, thẻ tổng ngày ước tính phần thiếu và ghi "≈".
- **"✨ Chỉnh thực đơn với AI"**: chat, gợi ý ("Ít tinh bột hơn cho bữa tối", "Thêm một bữa phụ chiều", "Thay các món có nấm", "Giảm còn 1.600 kcal/ngày", "Bữa sáng nhanh dưới 15 phút"), phạm vi "Hôm nay / Cả tuần"; AI trả **đề xuất** (danh sách thay đổi có ô chọn) → "Áp dụng thay đổi" / "Bỏ qua". Mọi món đề xuất đều thuần chay và tránh dị ứng.
- Thẻ **Nguyên liệu trong tủ** (số lượng + tên, "Xem tủ lạnh ›", "Tạo thực đơn từ tủ lạnh") và thẻ **"Cần thực đơn riêng? Nhờ chuyên gia thiết kế"** → danh bạ chuyên gia ở chế độ "Chọn chuyên gia" → hồ sơ → đặt.
- **Nguyên liệu trong tủ** (màn riêng, danh sách dọc): "Thêm nguyên liệu…" (chỉ thực phẩm thuần chay; món không thuần chay bị từ chối kèm "Gợi ý thay thế"), lọc Tất cả · Rau lá · Rau củ quả · Nấm · Đạm thực vật · Ngũ cốc · Hạt · Trái cây · Gia vị; mỗi dòng có hình minh hoạ (emoji trên nền màu theo nhóm), "18 kcal / 100 g · 1 quả ≈ 22 kcal", nguồn (Quét / Tự thêm); vuốt để xoá + "Hoàn tác"; "Xoá hết" trong menu; "Quét tủ lạnh", "Tạo thực đơn từ tủ lạnh".
- **Chi tiết nguyên liệu** (~35 nguyên liệu chay phổ biến): macro, vitamin/khoáng chất (%DV), "Phù hợp với", "Cần lưu ý / Không phù hợp với" (kèm cảnh báo dị ứng cá nhân), "Không nên dùng chung" (tham khảo), "Món gợi ý", "Công thức có nguyên liệu này", "Thêm vào tủ" / "Đã có trong tủ". Nguồn "Tham khảo: Bảng thành phần thực phẩm Việt Nam / USDA FoodData Central"; "Thông tin chỉ mang tính tham khảo, không thay thế tư vấn y tế".
- **Chi tiết công thức**: đầu trang (kcal, macro, "Có chứa: …", "Tìm video & quán liên quan"), hai tab **Nguyên liệu / Cách làm**; nguyên liệu có trong CSDL dinh dưỡng mở chi tiết nguyên liệu.

### Quét tủ lạnh

- Camera có khung nhận diện; "Chọn ảnh" (máy ảo không có ảnh → "Dùng ảnh tủ lạnh mẫu"); "Nhập tay".
- Chỉ xác định **thực phẩm là gì và có thuần chay không**: nhãn "Thuần chay" / "Không thuần chay" (✓ / ✕ kèm chữ). Thực phẩm không thuần chay nằm riêng ở "Không thuần chay — không lưu" với lý do và "Gợi ý thay thế:". Chỉ **Xác nhận / Bỏ**, không có số lượng.
- "Lưu vào tủ lạnh (N)" chỉ lưu thực phẩm thuần chay đã xác nhận → "Tạo thực đơn từ tủ lạnh" hoặc **"Xem tủ lạnh"** (mở màn Nguyên liệu trong tủ). "Gợi ý món từ nguyên liệu này" → "Thêm vào thực đơn" / "Xem công thức".

### Chuyên gia: thiết kế thực đơn N ngày

Không còn tư vấn theo khung giờ, khoá học, thực đơn VIP hay dịch vụ riêng lẻ; chuyên gia nhận **thiết kế thực đơn 3–30 ngày** theo yêu cầu.

1. **Hồ sơ chuyên gia**: thẻ **"Thiết kế thực đơn theo yêu cầu"** (giá mỗi ngày, giá có phản hồi mỗi ngày, số ngày tối thiểu–tối đa, "Giá cuối do hai bên thoả thuận") và nút **"Đặt chuyên gia lên thực đơn"**. Hồ sơ của chính mình: "Đây là hồ sơ của bạn…"; chuyên gia tạm ngưng: "Chuyên gia đang tạm ngưng nhận yêu cầu".
2. **Đặt chuyên gia lên thực đơn**: số ngày (3/7/10/14/30 hoặc tự chỉnh, 3–30), "Bắt đầu từ" (từ ngày mai), hình thức **"Giao trọn kế hoạch một lần"** / **"Có phản hồi mỗi ngày"**, mục tiêu, dị ứng, các bữa trong ngày (lấy sẵn từ hồ sơ sức khoẻ), ngân sách đi chợ mỗi ngày (không bắt buộc), **"Nhu cầu & ghi chú"** (≥ 20 ký tự), "Chia sẻ hồ sơ sức khoẻ với chuyên gia", ước tính "≈ 10 ngày × 180.000đ = 1.800.000đ". **"Gửi yêu cầu"** → mở trang yêu cầu.
3. **Trang yêu cầu** (dùng chung cho hai bên), tiến trình "Gửi yêu cầu → Thoả thuận giá → Thanh toán → Nhận kế hoạch → Hoàn tất":
   - **Trao đổi**: chat (tự cập nhật mỗi 5 giây), thẻ **Đề xuất giá** (giá, số ngày, hình thức, ngày bắt đầu, lời nhắn); bên kia "Đồng ý" hoặc "Đề xuất giá khác". Nhắc tới zalo / sđt / "chuyển khoản riêng" / số điện thoại → banner "Giao dịch ngoài VeganLife không được bảo vệ bởi cơ chế giữ tiền".
   - **Kế hoạch**: các ngày đã giao ("Ngày 1 · Thứ Hai 20/10"), món theo bữa, ghi chú; kiểu có phản hồi: "Phản hồi ngày này" (1–5 ★, Đầy đủ / Một phần / Không, góp ý cho ngày mai); **"Áp dụng kế hoạch vào Thực đơn"** (mọi món đã giao vào đúng ngày và bữa của tuần hiện tại, **một request gộp** `POST /meal-plans/current/meals/batch`; ngày ngoài tuần được bỏ qua và báo lại).
   - **Hợp đồng**: phạm vi, số ngày, hình thức, ngày, giá, phí 10 %, "Tiền được VeganLife giữ đến {ngày} (3 ngày sau khi kết thúc kế hoạch)", dòng thời gian giữ tiền.
   - Nút theo trạng thái: chờ thanh toán → **"Thanh toán {giá}"** (PaymentOS QR); trước khi thanh toán → "Huỷ yêu cầu"; từ lúc thanh toán đến hết hạn giữ tiền và chưa khiếu nại → **"Khiếu nại"**.
4. **Khiếu nại kế hoạch**: lý do (Kế hoạch không đúng yêu cầu đã thoả thuận / Có nội dung ảnh hưởng sức khoẻ / Giao trễ hoặc thiếu ngày / Có món chứa chất tôi dị ứng / Khác), mô tả ≥ 30 ký tự, **bằng chứng bắt buộc** (ít nhất 1: "Thêm liên kết nguồn" http(s) hoặc "Thêm ảnh" ≤ 5); "Có nội dung ảnh hưởng sức khoẻ" cần ít nhất một liên kết nguồn; yêu cầu Hoàn toàn bộ / Hoàn một phần. Gửi xong: yêu cầu thành Đang khiếu nại, tiền **tạm giữ**, "Ban quản trị sẽ xem xét và phản hồi trong 3 ngày làm việc."
5. **Lịch sử tư vấn** (Tôi; cũng là nút trên app bar tab Chuyên gia): tab "Đang diễn ra" / "Đã kết thúc", thẻ có tiến độ "Đã nhận 3/10 ngày" và kết quả ("Đã chuyển cho chuyên gia" / "Đã hoàn … về tài khoản thanh toán" / "Hoàn một phần …").

**Quy tắc giữ tiền (escrow)** — `lib/features/booking/domain/booking_rules.dart`, web dùng cùng số:

- 3–30 ngày; tổng giá 100.000đ – 50.000.000đ; lời nhắn đề xuất ≤ 300 ký tự; tin nhắn ≤ 1000. Chỉ bên **không** đưa ra đề xuất mới đồng ý được, và chỉ đề xuất mới nhất. Không tự đặt chính mình (409).
- Đồng ý giá → tạo hợp đồng + đơn hàng, **hạn thanh toán 48 giờ** (quá hạn → Hết hạn); mỗi mã QR sống 15 phút ("Tạo mã mới").
- Giao kế hoạch: một lần → hạn = max(00:00 ngày bắt đầu, lúc thanh toán + 24 giờ); có phản hồi mỗi ngày → ngày N hạn **06:00** sáng ngày đó, thành viên góp ý trước **21:00**.
- `endDate = startDate + số ngày − 1`; **giữ tiền đến 23:59 (giờ Việt Nam) ngày kết thúc + 3 ngày**. Hết hạn mà không khiếu nại → chuyển cho chuyên gia, **trừ phí nền tảng 10 %** (90 % vào "Có thể rút").
- Khiếu nại → tiền **tạm giữ** đến khi admin quyết định ở web `/disputes`: chuyển toàn bộ cho chuyên gia, hoàn toàn bộ, hoặc **hoàn một phần X** (1.000đ ≤ X < giá): thành viên nhận X, chuyên gia nhận (giá − X) × 90 %, phí (giá − X) × 10 %. Hoàn tiền về **phương thức thanh toán ban đầu** qua PaymentOS (không có ví thành viên).

### Tôi › Chuyên gia (vai trò Chef)

KPI "Yêu cầu mới · Đang thực hiện · Đang giữ (đ)" và:

- **Yêu cầu tư vấn**: tab Mới · Đang thương lượng · Đang thực hiện · Đã kết thúc, có huy hiệu. Yêu cầu mới: **"Báo giá"** (điền sẵn bảng giá) hoặc **"Từ chối"** (lý do ≥ 10 ký tự); xem hồ sơ sức khoẻ thành viên chia sẻ; đang thực hiện: **"Soạn kế hoạch"**; bị khiếu nại: **"Phản hồi khiếu nại"**.
- **Soạn kế hoạch**: chip ngày ("Chưa soạn" / "Nháp" / "Đã gửi"), phản hồi của thành viên cho ngày trước ở trên cùng, món theo bữa ("Nhập món mới" hoặc "Chọn từ công thức của tôi"), "Sao chép từ ngày trước", ghi chú ngày, "Lưu nháp". Giao một lần: **"Gửi toàn bộ kế hoạch"** (chỉ bật khi đủ món mọi ngày); có phản hồi: **"Gửi ngày này"** ("Hạn gửi: 06:00 …"). Món đã gửi hiện trong "Từ chuyên gia" của thành viên.
- **Ví của tôi**: Đang giữ (đến hạn giữ tiền) / Tạm giữ do khiếu nại / Có thể rút (sau phí 10 %) / Đã hoàn; lịch sử theo tháng, **Tài khoản nhận tiền**, **Rút tiền** (tối thiểu 100.000đ; ≤ 5.000.000đ tự chuyển, lớn hơn chờ admin duyệt ở web `/payouts`).
- **Hồ sơ & bảng giá**: chuyên môn, giới thiệu, giá mỗi ngày, giá có phản hồi mỗi ngày, số ngày tối thiểu / tối đa, công tắc "Đang nhận yêu cầu".
- **Tài liệu kiến thức**: gửi tài liệu cho chatbot RAG → Chờ duyệt / Đã duyệt / Bị từ chối.

## Chạy lần đầu

```bash
cd FE/Mobile
flutter pub get
flutter run                                                    # mặc định USE_MOCK_DATA=true
```

Cần Flutter ≥ 3.27 (Dart ≥ 3.6). Kiểm tra: `dart format --output=none --set-exit-if-changed lib test tool`, `flutter analyze`, `flutter test`, `flutter build apk --debug`. Từ thư mục `FE`, `run_checks.bat` chạy kiểm tra cho cả mobile và web.

### Quyền

- iOS `Info.plist`: `NSCameraUsageDescription` (quét tủ lạnh) và `NSPhotoLibraryUsageDescription` (chọn ảnh tủ lạnh, ảnh/video để đăng).
- Android `AndroidManifest.xml`: `INTERNET` (API, ô bản đồ, OSRM), `CAMERA`, khối `queries` cho link https (`url_launcher`, "Mở bằng Google Maps"). Chọn ảnh/video dùng trình chọn ảnh hệ thống (`image_picker`), không cần quyền đọc bộ nhớ. Không xin quyền vị trí (vị trí đang mô phỏng).

## Cấu hình (`--dart-define`)

| Key | Mặc định | Ý nghĩa |
|---|---|---|
| `USE_MOCK_DATA` | `true` | `false` → gọi API thật qua Dio |
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

**BE hiện mới có `UsersController`**: `GET /users`, `GET /users/{id}`, `PUT /users/{id}`, `DELETE /users/{id}`. Khi tắt mock, chỉ "Thông tin cá nhân" (`PUT /users/{id}`) chạy được; mọi endpoint dưới đây BE cần thêm (dưới `/api/v1`):

| Nhóm | Endpoint | File (`lib/…`) |
|---|---|---|
| Đăng nhập | POST `/auth/login`, `/auth/register`, `/auth/forgot-password`, `/auth/verify-reset-code`, `/auth/reset-password` | `core/session/auth_api_service.dart` |
| Tài khoản | GET `/users/me`; PUT `/users/{id}` (**đã có**); POST `/chef-applications` | `features/profile/data/profile_api_service.dart` |
| Cộng đồng | GET `/posts?type=&cursor=&limit=`, POST `/posts`; GET/PUT/DELETE `/posts/{id}`; PUT/DELETE `/posts/{id}/like`, `/posts/{id}/save`; POST `/posts/{id}/reports`; GET/POST `/posts/{id}/comments?cursor=&limit=10` (`parentId` khi trả lời); GET `/posts/{postId}/comments/{commentId}/replies`; PUT/DELETE `/posts/{postId}/comments/{commentId}`; GET `/users/me/posts`, `/users/me/saved-posts`, `/users/me/comments` | `features/community/data/community_api_service.dart` |
| Tải tệp | POST `/media/images` (multipart, ≤ 10 MB), POST `/media/videos` (multipart, ≤ 200 MB) | `features/community/data/media_api_service.dart` |
| Bếp nhanh (video ngắn) & video AI | GET `/posts?mediaType=Video&limit=`; GET `/videos/{id}`, POST `/videos/{id}/extraction` | `features/reels/data/reels_api_service.dart`, `features/video/data/video_api_service.dart` |
| Tìm kiếm | GET `/search?q=&type=&lat=&lng=`, `/search/suggest?q=&limit=8`, `/search/discover?lat=&lng=` | `features/search/data/search_api_service.dart` |
| Quán chay | GET `/restaurants?lat=&lng=&q=&certifiedOnly=&sort=&radiusKm=`, POST `/restaurants` (kèm `latitude`, `longitude`, `media`); GET `/restaurants/{id}`, `/restaurants/{id}/media`; GET/POST `/restaurants/{id}/reviews`; GET `/restaurants/suggested` | `features/restaurant/data/restaurant_api_service.dart` |
| Vị trí | GET `/geo/search?q=`, `/geo/reverse?lat=&lng=` (BE làm proxy, tôn trọng chính sách Nominatim) | `features/restaurant/data/geocoding_service.dart` |
| Quảng cáo | GET `/ads/feed?placement=nearby&lat=&lng=&limit=1`; POST `/ads/{id}/impression`, `/ads/{id}/click` | `features/ads/data/ads_api_service.dart` |
| Sức khoẻ & thực đơn | GET/PUT `/health-profile/me` (GET trả **404** khi chưa có hồ sơ; PUT tạo hoặc sửa, và cập nhật `dailyTargets` của tuần hiện tại); GET `/catalog/allergens?q=`; GET `/meal-plans/current`; POST `/meal-plans` (tuần trống), `/meal-plans/generate` (`usePantry`); GET `/meal-plans/{id}/swap-suggestions`; PATCH/DELETE `/meal-plans/{id}/meals`; POST `/meal-plans/current/meals`, **`/meal-plans/current/meals/batch`** (`{ meals: [...] }` → `{ placed, skipped, days }`); POST `/meal-plans/current/adjust`, `/meal-plans/current/adjust/{proposalId}/apply`; GET `/meal-plans/chef-suggestions`; GET `/users/me/recipes`, POST `/recipes`, GET `/recipes/{id}` | `features/meal_planner/data/meal_planner_api_service.dart`, `allergen_api_service.dart`, `features/recipe/data/recipe_api_service.dart` |
| Tủ lạnh & nguyên liệu | GET/POST/DELETE `/users/me/ingredients`, DELETE `/users/me/ingredients/{id}`; GET `/ingredients?q=&veganOnly=true`, `/ingredients/{id}` | `features/meal_planner/data/pantry_api_service.dart`, `features/ingredient/data/ingredient_api_service.dart` |
| Quét | POST `/vision/scan`, `/meal-plans/from-ingredients` | `features/scanner/data/scanner_api_service.dart` |
| Chatbot | GET `/chat/guest-trial`, POST `/chat/sessions/{id}/messages` (SSE) | `features/chatbot/data/chat_api_service.dart` |
| Chuyên gia (danh bạ) | GET `/chefs`, `/chefs/{id}` (kèm bảng giá, `acceptingBookings`) | `features/chef/data/chef_api_service.dart` |
| Đặt chuyên gia (thành viên) | POST `/bookings`; GET `/bookings/me`, `/bookings/{id}` (kèm hợp đồng, giữ tiền, khiếu nại); GET/POST `/bookings/{id}/messages`; POST `/bookings/{id}/offers`, `/bookings/{id}/offers/{offerId}/accept\|reject`, `/bookings/{id}/cancel`, `/bookings/{id}/payments`, `/bookings/{id}/complaint`; GET `/bookings/{id}/plan`; PUT `/bookings/{id}/plan/days/{dayIndex}/feedback` | `features/booking/data/booking_api_service.dart` |
| Thanh toán | GET `/orders/{id}`; POST `/orders/{id}/payments` (QR mới); GET `/payments/{id}` (hỏi mỗi 3 giây; xác nhận thật là webhook PaymentOS gọi BE) | `features/commerce/data/commerce_api_service.dart` |
| Chuyên gia: yêu cầu | GET `/chefs/me/bookings`; POST `/chefs/me/bookings/{id}/decline`; PUT `/chefs/me/bookings/{id}/plan/days/{dayIndex}`; POST `…/plan/days/{dayIndex}/send`, `…/plan/send`, `…/complaint/response` | `features/booking/data/booking_api_service.dart` |
| Chuyên gia: hồ sơ, tài liệu, ví | GET/PUT `/chefs/me/profile`; GET/POST `/chefs/me/knowledge-docs`; GET `/chefs/me/wallet`, `/chefs/me/wallet/transactions?month=`; PUT `/chefs/me/bank-account`; GET/POST `/chefs/me/withdrawals` | `features/chef_studio/data/chef_studio_api_service.dart`, `chef_wallet_api_service.dart` |

Đã khai báo nhưng app chưa gọi: `POST /auth/google` (dự phòng, không có luồng nào dùng), `GET /recipes/{id}/related-posts` (tuỳ chọn), `GET /chef-applications/me` (trạng thái hồ sơ đọc từ `GET /users/me`).

## Chênh lệch với sơ đồ SQL 26 bảng

App coi các trường mới là tuỳ chọn (thiếu thì UI vẫn chạy), nhưng BE/ERD cần bổ sung để dùng thật:

- **Bảng mới — cộng đồng**: `comments` (id, post_id, user_id, **parent_id** → comments.id, chỉ một cấp, content, status Visible/Hidden, created_at, updated_at), `post_likes`, `saved_posts`, `post_reports`, `post_tags`; `search_logs` (tuỳ chọn, cho "Xu hướng tìm kiếm"). Mỗi bài chỉ một tệp đính kèm (`posts.media_url`); nhiều ảnh cần bảng `post_media` sau này (chưa làm).
- **Bảng mới — tài khoản**: `password_reset_codes` (code_hash, expires_at 10 phút, attempts tối đa 3, reset_token_hash, used_at), `chef_applications`.
- **Bảng mới — sức khoẻ & nguyên liệu**: `user_allergies` (allergen_id hoặc custom_name), `ingredient_nutrition` (khẩu phần, kcal, macro, vi chất JSON, good_for, caution_for, source), `ingredient_incompatibilities`, `meal_plan_adjustments` (message, reply, changes JSON, scope, status Proposed/Applied/Dismissed).
- **Bảng mới — quán & quảng cáo**: `restaurant_media` (Image/Video), `ad_campaigns` (kèm `placement` = `nearby`, lượt hiển thị/bấm).
- **Bảng mới — đặt chuyên gia**: `chef_bookings` (booking_type OneShot/DailyFeedback, plan_days, start_date, goal, allergies_snapshot, meal_pattern, budget_per_day, needs, share_health_profile, status, decline_reason, cancel_reason), `booking_offers`, `booking_messages` (Text/Offer/System/Attachment), `booking_contracts` (1:1, bất biến: giá, ngày, delivery_due_at, daily_send_cutoff 06:00, feedback_cutoff 21:00, fee_rate 0.10, hold_days 3, payment_due_at +48 giờ), `booking_plan_days`, `booking_plan_meals` (6 bữa), `booking_day_feedback`.
- **Bảng mới — giữ tiền & khiếu nại**: `escrow_holds` (Held/Frozen/Released/Refunded/PartiallyRefunded, release_at = end_date 23:59 giờ VN + 3 ngày, released/fee/refunded amount), `booking_complaints` (reason, description, requested_outcome, requested_amount, chef_response, decision ReleaseToChef/RefundMember/Split, refund_amount, admin_note), `complaint_evidence` (Link/Image, url, caption).
- **Bảng mới — ví chuyên gia**: `wallets`, `wallet_transactions` (kèm `booking_id`; trạng thái `Held` "Đang giữ" thay `Pending`, `Frozen` "Tạm giữ do khiếu nại"), `withdrawal_requests`, `bank_accounts`.
- **Cột mới / đổi**:
  - `posts.restaurant_id` (gắn một quán), `posts.updated_at`, `posts.duration_seconds`; `posts.type` chỉ còn `recipe|discussion`;
  - `health_profiles.gender` (Male/Female/Other), `birth_year`, `activity_level` (sedentary/light/moderate/active), `meal_pattern`;
  - `meal_plan_recipes.meal_type` thêm `snack_am`, `snack_pm`, `snack_late`; `meal_plan_recipes.source` (ai / manual / user_recipe / chef / fridge_scan), `meal_plan_recipes.portion`;
  - `recipes.created_by`; `user_ingredients.scanned_at` (null = "Tự thêm");
  - `ingredients.is_vegan`, `ingredients.category` (leafy/veg/mushroom/plant_protein/grain/nut_seed/fruit/spice/plant_milk) + `ingredient_nutrition`;
  - `restaurants.latitude`, `restaurants.longitude` (+ `restaurant_media`); `reviews`: `UNIQUE(user_id, restaurant_id)`, `updated_at`;
  - `chef_profiles.price_per_day`, `feedback_price_per_day`, `min_plan_days` (3), `max_plan_days` (30), `accepting_bookings`;
  - `orders.booking_id`, `orders.refunded_at`, `orders.service_id` cho phép NULL, trạng thái thêm `PartiallyRefunded`; `payments.expires_at`, `payments.created_at`;
  - `knowledge_docs.status`, `review_note`, `reviewed_by`, `reviewed_at`.
- **Video AI** chưa có chỗ lưu: trạng thái xử lý (queued / transcribing / extracting / ready / failed, lý do lỗi), tóm tắt, nguyên liệu, các bước theo mốc thời gian, lời thoại.
- **Không còn dùng**: `services`, `consultations`, quyền truy cập gói (access grants), `chef_meal_suggestions` ("Từ chuyên gia" giờ lấy từ `booking_plan_days` / `booking_plan_meals`).

## Cấu trúc

```
lib/
├── main.dart, app.dart              # ProviderScope, theme, AppEntry (Welcome / shell), thanh tab + nút Quét + bong bóng Hỏi AI
├── core/
│   ├── config/env.dart              # --dart-define
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
    ├── commerce/                    # đơn hàng + thanh toán PaymentOS (QR) cho yêu cầu đặt chuyên gia
    ├── chef_studio/                 # ví, hồ sơ & bảng giá, tài liệu kiến thức
    ├── profile/                     # Tôi, nội dung của tôi, đăng ký chuyên gia
    └── chatbot/                     # Hỏi AI (RAG)
        ├── data/                    # models (DTO + JSON), *_api_service.dart, mock_*_repository.dart
        ├── domain/                  # entities, quy tắc nghiệp vụ
        └── presentation/            # controllers (Riverpod), screens, widgets
tool/brand/                          # sinh icon + splash
```

## Thử nhanh (mock)

**Dữ liệu mẫu**

- **Minh Anh**: dị ứng đậu phộng, "3 bữa + 1 phụ" (sáng, trưa, phụ chiều, tối), Nữ, sinh 1997, vận động nhẹ, mục tiêu Tăng cơ; tủ lạnh có Đậu hũ, Cà chua, Nấm rơm (Quét) và Gạo lứt (Tự thêm); bài chờ duyệt `p_me_pending_celery`, bài bị từ chối `p_me_rejected_detox`, video `p_me_banh_xeo` bị AI xử lý lỗi ("Thử trích xuất lại").
- **Lê Quang Tâm**: hồ sơ sức khoẻ cũ chưa có giới tính / năm sinh (hiện lời nhắc bổ sung); bảng giá 150.000đ/ngày, có phản hồi 180.000đ/ngày. Danh bạ: Trần Quốc Minh đang tạm ngưng nhận yêu cầu.
- **Yêu cầu đặt chuyên gia** (ngày tính từ hôm nay; id trùng với web):
  - Minh Anh: `b_ma_tam_nego` (Tâm, 10 ngày có phản hồi, Tâm đề xuất 1.500.000đ → "Đồng ý" hoặc "Đề xuất giá khác"); `b_ma_thuha_active` (ThS. DD Phạm Thu Hà, 7 ngày giao một lần, đã thanh toán, đã giao đủ, hôm nay là ngày 3 → "Áp dụng kế hoạch vào Thực đơn", "Khiếu nại"); `b_ma_tam_done` (Tâm, 5 ngày, đã chuyển cho chuyên gia 2 ngày trước).
  - Tâm: `b_nam_tam_req` (Hoàng Nam, 14 ngày giao một lần, chờ báo giá); `b_vy_tam_active` (Thảo Vy, 7 ngày có phản hồi, đã có phản hồi ngày 2, ngày hôm nay còn nháp → "Soạn kế hoạch"); `b_tram_tam` (Ngọc Trâm, đang khiếu nại **`cp_tram_tam`**: ảnh hưởng sức khoẻ, 1 liên kết + 1 ảnh, tiền tạm giữ, chuyên gia đã phản hồi); `b_han_tam_done` (Gia Hân, 30 ngày, đã chuyển). Ví của Tâm tính lại từ các yêu cầu này; tài khoản nhận tiền và lịch sử rút tiền có sẵn.
- **Bài gắn quán**: `p_video_cha_lua` → Quán Chay An Lạc, `p_checkin_hanh_tam` → Bún Riêu Chay Hạnh Tâm. Bài `p_video_cha_lua` có bình luận kèm phản hồi của Tâm.
- **Luồng hai tài khoản**: Minh Anh gửi yêu cầu cho Tâm → Tâm "Báo giá" → Minh Anh "Đề xuất giá khác" → Tâm "Đồng ý" → Minh Anh "Thanh toán" → "Mô phỏng đã thanh toán" → Tâm "Gửi ngày này" (ngày 1) → Minh Anh "Phản hồi ngày này" → Tâm gửi ngày 2 → … → hết hạn giữ tiền thì ví Tâm có 90 % ở "Có thể rút".

**Kích hoạt có chủ đích**

- **`#fail`** → lỗi 503 khi có trong: bình luận (thêm, sửa), tiêu đề/nội dung bài, họ tên ở "Thông tin cá nhân", tên món tự nhập / "Công thức của tôi" / món áp dụng từ kế hoạch chuyên gia, yêu cầu "Chỉnh thực đơn với AI", tên nguyên liệu thêm vào tủ, ô tìm nguyên liệu và dị ứng, ô tìm kiếm (toàn app và quán chay), ô tìm địa chỉ ("Chọn vị trí"), nhận xét đánh giá quán, tên/địa chỉ quán gợi ý; đặt chuyên gia: nhu cầu, tin nhắn, lời nhắn đề xuất giá, lý do huỷ / từ chối, góp ý ngày, tên món / ghi chú ngày khi soạn kế hoạch, mô tả khiếu nại, phản hồi khiếu nại; phía chuyên gia: giới thiệu hồ sơ, tiêu đề tài liệu, tên chủ tài khoản ngân hàng. Quán **"Quán thử nghiệm QA #fail"** luôn lỗi khi gửi đánh giá.
- **`#flag`** hoặc các cụm `chữa khỏi`, `giảm cân thần tốc`, `inbox`, `zalo`, `cam kết hoàn tiền` (không dấu cũng tính) trong tiêu đề/nội dung bài → bài vào **Chờ duyệt**.
- **`#expire`** trong "Nhu cầu & ghi chú" khi đặt chuyên gia → hạn thanh toán và mã QR chỉ còn 30 giây ("Tạo mã mới" / yêu cầu hết hạn). Màn thanh toán mock có "Mô phỏng đã thanh toán" / "Mô phỏng thất bại".
- **`#offline`** trong câu hỏi chat → mất mạng giữa chừng.
- **Cân nặng `99.9`** khi lưu hồ sơ sức khoẻ → 503.
- **Tệp mẫu** (Tạo bài viết › Ảnh/Video, ảnh quán, ảnh bằng chứng): `dau_hu_sot_ca.jpg` (2,1 MB, tải được), `anh_qua_lon.png` (14 MB, bị chặn), `banh_xeo_chay.mp4` (48 MB), `mat_ket_noi.mp4` (mất kết nối ở 60 % → "Thử lại"), `video_4k_qua_lon.mov` (850 MB, bị chặn); "Chọn từ thư viện" dùng tệp thật trên máy.
- **Vị trí** (mock geocoder ~20 địa điểm): TP.HCM — Nhà hát Thành phố, Chợ Bến Thành, Nhà thờ Đức Bà, Phố đi bộ Nguyễn Huệ, Hồ Con Rùa, Chợ Bà Chiểu, Landmark 81, Phú Mỹ Hưng, Chợ Bình Tây, Đại học Bách khoa TP.HCM, Sân bay Tân Sơn Nhất, Khu Công nghệ cao; Hà Nội — Hồ Hoàn Kiếm, Văn Miếu – Quốc Tử Giám, Lăng Chủ tịch Hồ Chí Minh, Hồ Tây, Times City; Đà Nẵng — Cầu Rồng, Chợ Hàn, Bãi biển Mỹ Khê, Ngũ Hành Sơn. Chọn một địa điểm Hà Nội → khoảng cách và thứ tự quán đổi, không còn dòng tài trợ (chiến dịch mẫu chỉ chạy ở TP.HCM). "Dùng vị trí hiện tại (mô phỏng)" = "Quận 1, TP.HCM (vị trí mô phỏng)".
- **Chỉ đường dự phòng**: `--dart-define=OSRM_BASE_URL=http://127.0.0.1:9` hoặc tắt mạng → đường thẳng + ghi chú trong ≤ 6 giây.
- **Chỉnh với AI**: "Mình chưa hiểu yêu cầu…" khi câu không khớp gợi ý nào; đề xuất không bao giờ chứa đậu phộng (dị ứng của Minh Anh) hay món không thuần chay.
- **Quét** (ảnh tủ lạnh mẫu, cũng là kết quả camera / "Chọn ảnh" ở mock): 7 thực phẩm, "Rau chân vịt" (58 %) cần Xác nhận, "Trứng gà" và "Sữa bò" ở "Không thuần chay — không lưu". **Nhập tay**: `trứng vịt`, `mật ong`, `nước mắm`, `thit bo` → không thuần chay; `nấm mỡ`, `sữa đậu nành` → thuần chay. Trong "Nguyên liệu trong tủ", thêm `thịt bò` → bị từ chối kèm "Gợi ý thay thế".
- **Tìm kiếm**: gõ `bu` → chỉ có gợi ý; Enter → tab kết quả; `bun rieu` (không dấu) → "Bún riêu chay"; `xyzxyz` → "Không tìm thấy «xyzxyz»".
- **Lỗi nghiệp vụ đặt chuyên gia**: đặt chính mình (mở hồ sơ Tâm bằng tài khoản Tâm) → "Đây là hồ sơ của bạn…"; nhu cầu < 20 ký tự, lý do từ chối < 10 ký tự, mô tả khiếu nại < 30 ký tự, khiếu nại không có bằng chứng, "ảnh hưởng sức khoẻ" không có liên kết → bị chặn; đồng ý đề xuất của chính mình hoặc đề xuất cũ → 409; rút dưới 100.000đ hoặc vượt "Có thể rút" → báo lỗi; rút ≤ 5.000.000đ tự chuyển sau ~10 giây.
- **`MOCK_*_SCENARIO`**: `MOCK_SCAN_SCENARIO=empty|error`, `MOCK_COMMERCE_SCENARIO=empty|error`, `MOCK_ADS_SCENARIO=empty|error` (xem bảng cấu hình).

Video mẫu (bảng tin, Bếp nhanh) dùng clip công khai của Flutter docs (`bee.mp4`, `butterfly.mp4`) và MDN (`flower.mp4`, CC0). Thay bằng URL Cloudinary khi BE sẵn sàng.

## Nối API thật

1. Đặt `USE_MOCK_DATA=false` và `API_BASE_URL`.
2. Đăng nhập: `POST /auth/login` trả `{ accessToken, refreshToken, expiresAt, user: { id, fullName, email, role, status } }`; lỗi 401 `invalid_credentials`, 403 `admin_web_only`, 423 `account_locked`, 409 `email_taken`, 429 `too_many_attempts`. Chuyển token sang secure storage trước khi phát hành.
3. Chat dùng SSE (`text/event-stream`) với các sự kiện `token`, `citation`, `done`, `error`. Khách gửi kèm `X-Guest-Token`; server trả `402` / `trial_exhausted` khi hết lượt.
4. PaymentOS: BE tạo mã QR và nhận webhook; app chỉ hỏi `GET /payments/{id}` mỗi 3 giây. Nút mô phỏng thanh toán tự ẩn khi tắt mock. Giữ tiền cần PaymentOS hỗ trợ hoàn tiền và một job BE giải ngân khi đến `releaseAt`; cần điều khoản về việc giữ tiền (liên kết từ tab Hợp đồng).
5. Chưa có (cần thêm thư viện, chờ duyệt): GPS thật (`geolocator`), lưu token an toàn, tải tệp thật lên Cloudinary. Dữ liệu dinh dưỡng là số tham khảo; lời lẽ về sức khoẻ phải giữ thận trọng.
