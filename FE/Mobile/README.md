# VeganLife Mobile (Flutter) — nền tảng chính

VeganLife là **mobile-first**: mọi hành trình của khách, thành viên và chuyên gia đều nằm trong app này. `FE/Web` chỉ là **admin console** để kiểm duyệt và quản lý.

Feature-first Flutter, **Riverpod** cho state, **Dio** cho API. Feature nào cũng có abstract API service + **Mock repository**, nên app chạy được trước khi backend ASP.NET Core sẵn sàng. UI tiếng Việt.

## Điều hướng

Thanh dưới có 4 tab, 2 tab mỗi bên một **nút Quét tròn lớn** ở giữa:

| Vị trí | Màn hình | Khách xem được? |
|---|---|---|
| Trang chủ | Bảng tin cộng đồng kiểu Facebook, dải **Reels**, thẻ "Được tài trợ"; trên app bar có **Tìm kiếm**, **Quán chay gần bạn**, **Tạo bài viết** | Xem: có · Tương tác: cần đăng nhập |
| Thực đơn | Thực đơn 7 ngày (AI hoặc tự lên), 4 nguồn món, BMI, macro, cảnh báo dị ứng, **Nguyên liệu trong tủ** | Cần đăng nhập |
| **Quét** (nút tròn giữa) | Chạm: quét tủ lạnh bằng cách đã dùng lần trước. Giữ: chọn **Chụp hình / Chọn ảnh / Nhập tay** (lựa chọn được nhớ, kể cả khi đổi cách quét ngay trong màn quét, ví dụ "Chụp bằng camera" / "Nhập tay" khi chưa chọn được ảnh). Mở toàn màn hình | Cần đăng nhập |
| Chuyên gia (thành viên, khách) | Danh bạ đầu bếp / chuyên gia dinh dưỡng đã xác minh, hồ sơ, dịch vụ, đặt lịch, mua gói | Xem: có · Đặt / mua: cần đăng nhập |
| **Khách hàng** (vai trò Chef) | Thay tab Chuyên gia khi đăng nhập bằng tài khoản chuyên gia: khách đang dùng gói của mình | Chỉ chuyên gia |
| Tôi | Hồ sơ, sức khoẻ, nội dung của tôi, đơn hàng, lịch tư vấn, khu **Chuyên gia** (Chef), giao diện, đăng xuất | Cần đăng nhập |
| Bong bóng **Hỏi AI** | Chat-head kiểu Messenger. Khi đứng yên chỉ là một dải mảnh 12×56dp sát mép (mặc định mép trái, ~38% chiều cao) nên không che nội dung; chạm vào dải là mở chatbot RAG có trích dẫn. Kéo ra thành bong bóng 56dp, thả là bám mép trái/phải gần nhất (nhớ vị trí), 1,5 giây sau tự thu lại thành dải. Giữ để "Ẩn bong bóng" / "Đưa về vị trí mặc định". Ẩn khi cuộn danh sách, khi bàn phím mở, trên hộp thoại và trên màn quét, Reels, thanh toán, chat (màn nào bọc `AskAiBubbleFree` cũng ẩn). Trên Android 10+ vùng dải/bong bóng được loại khỏi cử chỉ vuốt "quay lại" (`setSystemGestureExclusionRects` qua MethodChannel `vn.veganlife/gesture_exclusion` trong `MainActivity.kt`), nên kéo từ mép không thoát app. Khách hỏi miễn phí 3 lần | Có |

**Thanh tab nổi** (kiểu TPBank): khối bo tròn cách mép 12dp, nằm trên vùng cử chỉ hệ thống, nền mờ có bóng; tab đang chọn có nền tô nhạt trượt theo; nút **Quét** tròn nằm trong phần khoét giữa thanh và nhô lên, chữ "Quét" ở dưới. Nội dung các tab cuộn phía sau thanh; khoảng trống cuối danh sách lấy từ `floatingBarClearance(context)` (`lib/core/widgets/floating_bar_clearance.dart`).

Tab thứ 4 đổi ngay khi đăng nhập, đăng xuất hoặc đổi tài khoản.

## Tài khoản & vai trò

Ở chế độ mock, mọi nút **"Tiếp tục với Google"** mở sheet **"Chọn tài khoản Google (mô phỏng)"**:

| Tài khoản | `userId` | Email | Vai trò (`users.role`) |
|---|---|---|---|
| Minh Anh (Thành viên) | `u_me` | `minhanh.nguyen@gmail.com` | `User` |
| Lê Quang Tâm (Chuyên gia) | `u_chef_tam` | `tam.chefchay@gmail.com` | `Chef` |
| Khách | — | — | chưa đăng nhập: xem bảng tin, tìm kiếm, quán chay, danh bạ chuyên gia; hỏi AI 3 lần |

Đổi tài khoản = đăng xuất rồi đăng nhập lại. Phiên (`vl.user_id`, `vl.role`) được lưu và khôi phục khi mở lại app. Dữ liệu mock giữ trong bộ nhớ suốt phiên chạy app, nên thao tác của tài khoản này thấy được ở tài khoản kia (Minh Anh đặt lịch → Tâm thấy yêu cầu). Vai trò `Admin` chỉ dùng ở web. Màn hình chuyên gia kiểm tra `role == Chef`, nếu không thì hiện "Chỉ dành cho chuyên gia".

## Tính năng

### Trang chủ (cộng đồng)

- Bài đăng full-width kiểu Facebook, lọc **Tất cả / Công thức / Video / Thảo luận**, tải thêm khi cuộn, kéo để làm mới.
- **Reels**: dải video dọc 9:16 (tác giả, thời lượng) ngay dưới ô đăng bài. Chạm mở trình phát toàn màn hình, vuốt dọc qua clip kế tiếp; tự phát (tắt tiếng, có nút bật tiếng), chạm để dừng; cột Thích / Bình luận / Chia sẻ / Lưu; "Xem công thức" khi AI đã trích công thức từ video. Reels là các bài `mediaType = Video`.
- **"Được tài trợ"**: thẻ cửa hàng chay (tên, chứng nhận, sao, khoảng cách, tiêu đề chiến dịch, nút Xem quán / Chỉ đường / Đặt bàn) chèn sau mỗi 6 bài, gần bạn trước. Trong chi tiết bài **Công thức / Thảo luận có nhắc tới món ăn** có đúng 1 thẻ (sau thanh Thích–Bình luận–Lưu, trước phần bình luận): ưu tiên quán có tên hoặc tiêu đề quảng cáo khớp món trong bài, nếu không thì quán gần nhất. Chiến dịch do admin quản lý ở web `/ads`.
- Chi tiết bài, **trang bình luận toàn màn hình**, thích, lưu, báo cáo (4 lý do khớp hạng mục kiểm duyệt của web).
- **Nội dung của mình**: menu "⋯" trên bài của mình có **Sửa bài / Xoá bài** (bài người khác chỉ có "Báo cáo bài viết"); sửa/xoá bình luận của mình, hiện "(đã sửa)".
- **Trạng thái bài**: đăng là lên bảng tin, trừ khi AI sàng lọc gắn cờ → **Chờ duyệt** (chỉ tác giả thấy). Admin duyệt → Đã đăng, từ chối → **Bị từ chối** kèm lý do và nút "Sửa & gửi lại". Sửa bài bị từ chối luôn quay về Chờ duyệt.
- **Đăng bài**: Công thức / Video / Hỏi đáp, gắn thẻ chế độ ăn. Video: **"Tải video lên"** (thư viện máy qua `image_picker`, MP4/MOV/WEBM ≤ 200 MB, thanh tiến độ, "Huỷ tải lên", "Thử lại") hoặc **"Dán đường dẫn"**. Sau khi đăng, AI xử lý video qua các bước *Nhận video → Nhận dạng giọng nói → Trích xuất công thức*, rồi mới có tóm tắt, nguyên liệu, các bước và lời thoại tua theo mốc.

### Tìm kiếm & quán chay

- **Tìm kiếm** (khách dùng được): tìm không dấu, gợi ý `bún riêu`, `đậu hũ`, `sữa hạt`, `phở chay`, lịch sử "Tìm gần đây" (tối đa 8, "Xoá lịch sử"). Kết quả theo tab **Tất cả · Công thức · Video · Bài viết · Quán**; khi khớp một món có khối **"Gợi ý cho «tên món»"** gồm "Video & bài viết liên quan" và "Quán gợi ý".
- **Quán chay gần bạn**: vị trí mô phỏng "Quận 1, TP.HCM", lọc "Đã chứng nhận thuần chay", sắp xếp Gần nhất / Đánh giá cao, khoảng cách (quán chưa có toạ độ hiện "Chưa có vị trí" và xếp cuối).
- Chi tiết quán: "Mở bản đồ" / "Chỉ đường" (Google Maps qua `url_launcher`), phân bố sao, đánh giá mới nhất trước, **"Viết đánh giá"** (mỗi người 1 đánh giá, gửi lại là sửa). **"Gợi ý quán mới"**: quán hiện ngay với nhãn "Chưa chứng nhận" và "Được gợi ý bởi …".

### Thực đơn

- Thực đơn tuần: **Tạo thực đơn** bằng AI, **Tự lên thực đơn** (tuần trống) hoặc **Tạo thực đơn từ tủ lạnh** (chỉ dựa trên thực phẩm thuần chay trong tủ). Mỗi bữa có nhãn nguồn.
- Chọn món cho một bữa từ **4 nguồn**: **AI gợi ý** (±10 % kcal, an toàn dị ứng) · **Công thức của tôi** (tự viết công thức có nguyên liệu và các bước) · **Từ chuyên gia** (món chuyên gia đề xuất, kèm lời nhắn và "Cho bữa tối · Thứ Bảy, 17/10" khi chuyên gia chọn ngày) · **Tự nhập món** (tên, kcal và macro tuỳ chọn, vẫn kiểm tra dị ứng theo tên).
- **Macro không bịa**: món tự nhập, "Công thức của tôi" hay món chuyên gia đề xuất chỉ hiện macro đã nhập (thiếu thì ẩn, không bao giờ "Đạm 0 g"). Thẻ tổng ngày ước tính phần thiếu theo kcal (20 % đạm, 55 % tinh bột, 25 % béo) và ghi rõ "≈" kèm "Có phần ước tính theo kcal cho món chưa nhập đủ macro: …".
- **Hồ sơ sức khoẻ** (từ thẻ đầu Thực đơn hoặc từ Tôi): chiều cao, cân nặng, mục tiêu, dị ứng, BMI chuẩn châu Á cập nhật khi đang gõ; lưu xong có "Tạo lại thực đơn".
- **Nguyên liệu trong tủ** (`user_ingredients`): chỉ thực phẩm thuần chay, mỗi mục là tên + nguồn (biểu tượng "Quét" chỉ cho thực phẩm camera / ảnh nhận diện; tên gõ tay và món thay thế chọn trong khay quét là "Tự thêm"), không có số lượng hay độ tươi; thêm tay (thực phẩm không thuần chay bị từ chối, kèm lý do và "Gợi ý thay thế" chạm để thêm), bỏ, "Xoá hết", "Quét tủ lạnh".
- **Chi tiết công thức**: nguyên liệu, các bước, macro, cảnh báo dị ứng, "Tìm video & quán liên quan".

### Quét tủ lạnh

- Camera có khung nhận diện; "Chọn ảnh" từ thư viện (máy ảo không có ảnh → "Dùng ảnh tủ lạnh mẫu"); "Nhập tay".
- Màn quét chỉ xác định **thực phẩm là gì và có thuần chay không** (không đánh giá độ tươi). Mỗi thực phẩm có tên, độ tin cậy và nhãn **"Thuần chay" / "Không thuần chay"** (có biểu tượng ✓ / ✕ và chữ, không chỉ dựa vào màu): trên camera là khung xanh / đỏ, tên gắn ở cạnh trên khung và huy hiệu ở góc dưới (khung hẹp thì huy hiệu nằm giữa cạnh dưới); tên và huy hiệu tự né nhau, né khung bên cạnh và luôn nằm trong màn hình; trong khay là huy hiệu cạnh độ tin cậy. Chỉ có **Xác nhận / Bỏ**, không có số lượng hay đơn vị; nguyên liệu chưa xác nhận không được lưu.
- Tiêu đề khay tóm tắt, ví dụ "Tìm thấy 7 thực phẩm · 5 thuần chay · 2 không thuần chay · 1 cần xác nhận".
- Thực phẩm không thuần chay (trứng, sữa bò, mật ong, nước mắm, thịt, hải sản, gelatin, yến…) nằm riêng ở **"Không thuần chay — không lưu"**: lý do ("Có nguồn gốc động vật: trứng", "Chứa sữa bò"…), **"Gợi ý thay thế:"** (trứng → Đậu hũ non, sữa bò → Sữa hạt / Sữa đậu nành, mật ong → Siro phong, nước mắm → Nước tương / Nước mắm chay; chạm để thêm như món thuần chay tự nhập) và nút **"Bỏ"**.
- Tên tự gõ ("Nhập tay", "Loại khác…" trong sheet xác nhận, "Thêm vào tủ" ở Thực đơn) được kiểm tra thuần chay ngay trên máy bằng danh sách từ khoá (`scanner/domain/vegan_check.dart`, chạy cả khi offline); khi server trả `isVegan` thì server được ưu tiên.
- **"Lưu vào tủ lạnh (N)"** chỉ đếm và lưu thực phẩm **thuần chay đã xác nhận** → mời "Tạo thực đơn từ tủ lạnh" hoặc "Xem trong Thực đơn". Nếu mọi thực phẩm đều không thuần chay: "Chưa có thực phẩm thuần chay để lưu". "Gợi ý món từ nguyên liệu này" cũng chỉ dùng thực phẩm thuần chay, rồi "Thêm vào thực đơn" / "Xem công thức".

### Chuyên gia, mua dịch vụ & thanh toán

- Danh bạ (tìm theo tên, chuyên môn, thành phố) → hồ sơ chuyên gia với mục **Dịch vụ**: **Tư vấn 1–1** ("Đặt lịch tư vấn": dịch vụ → ngày → giờ → ghi chú; không đặt trùng giờ: giờ đã có người giữ hiện mờ "Đã kín", giờ trùng một lịch tư vấn khác của bạn với bất kỳ chuyên gia nào, kể cả đơn đang chờ thanh toán, hiện mờ "Bạn có lịch"; server vẫn chặn bằng 409 "Bạn đã có lịch lúc … — chọn giờ khác nhé."), **Khoá học** (truy cập 180 ngày), **Thực đơn VIP** (30 ngày) ("Mua gói").
- Tạo đơn → **Thanh toán PaymentOS**: mã QR (bản mock là QR vẽ tại chỗ, không quét được), số tiền, mã giao dịch `VL…` (chạm để sao chép), đếm ngược 15:00, tự kiểm tra trạng thái mỗi 3 giây, "Huỷ đơn". Hết hạn → "Tạo mã mới"; thất bại → "Thử lại". Lịch tư vấn được giữ chỗ ngay khi tạo đơn.
- Thanh toán xong → **cấp quyền truy cập** (tư vấn: đến 24 giờ sau giờ hẹn; khoá học 180 ngày; VIP 30 ngày) → "Xem lịch tư vấn" hoặc "Mở nội dung".
- **Đơn hàng của tôi** (Tôi › Nội dung & lịch hẹn): lọc Tất cả / Chờ thanh toán / Đã thanh toán / Đã huỷ / hoàn tiền; "Thanh toán tiếp" cho đơn đang chờ; chi tiết đơn có tiến trình Tạo đơn → Thanh toán → Cấp quyền → Tư vấn.
- **Lịch tư vấn của tôi**: huỷ được khi chuyên gia chưa xác nhận hoặc trước giờ hẹn 24 tiếng (hoàn tiền mô phỏng); xem "Ghi chú của chuyên gia" khi buổi đã xong; "Chuyên gia từ chối: <lý do>" kèm "Đã hoàn tiền".

### Chuyên gia (vai trò Chef)

Tôi › **Chuyên gia** › **Bảng điều khiển chuyên gia**: số yêu cầu chờ xác nhận, lịch hôm nay, doanh thu tháng này, tài liệu chờ duyệt, lịch sắp tới, và các mục:

- **Dịch vụ của tôi**: thêm / sửa / xoá dịch vụ (tên, loại, giá, thời lượng cho tư vấn, mô tả, đường dẫn nội dung cho khoá học và VIP). Dịch vụ đã có đơn không xoá được.
- **Lịch hẹn & đơn hàng**: tab Chờ xác nhận · Sắp tới · Gói đã bán · Đã xong; "Xác nhận" hoặc "Từ chối" (lý do ≥ 10 ký tự, khách được hoàn tiền mô phỏng).
- **Buổi tư vấn**: Đã thanh toán → Đã xác nhận → Đang tư vấn → Hoàn thành; "Bắt đầu buổi tư vấn" mở trước giờ hẹn 15 phút; "Ghi chú & khuyến nghị cho khách" (≥ 20 ký tự) gửi cho khách khi hoàn thành.
- **Tài liệu kiến thức**: gửi tài liệu cho chatbot RAG (chọn tệp PDF mẫu hoặc dán đường dẫn) → Chờ duyệt / Đã duyệt (AI đang dùng, số đoạn) / Bị từ chối (ghi chú của admin).
- **Ví**: Có thể rút / Đang chờ / Đã rút. Mỗi đơn trừ **phí nền tảng 10 %**; tiền tư vấn vào ví khi buổi hoàn thành, tiền khoá học / VIP giữ 7 ngày (thời hạn hoàn tiền); hoàn tiền thì trừ lại. Lịch sử giao dịch theo tháng, **Tài khoản nhận tiền**, **Rút tiền** (tối thiểu 100.000đ; ≤ 5.000.000đ tự chuyển, lớn hơn chờ admin duyệt ở web `/payouts`).
- **Khách hàng** (cũng là tab thứ 3 của chuyên gia): tab Đang dùng gói / Sắp hết hạn (≤ 7 ngày) / Đã kết thúc, tìm theo tên, lọc Tư vấn / Khoá học / Thực đơn VIP. Chi tiết khách: hồ sơ sức khoẻ khách chia sẻ qua gói (chỉ xem), đơn hàng & lịch tư vấn với mình, món đã đề xuất, "Đề xuất món", "Xem lịch hẹn", "Gọi video (sắp có)".
- **Đề xuất món cho khách**: tên món, kcal, nguyên liệu, lời nhắn, bữa và ngày → món hiện trong Thực đơn › **Từ chuyên gia** của khách.
- **Hồ sơ chuyên gia** (chuyên môn, giới thiệu) và "Xem trang công khai".

### Tôi

Hồ sơ (nhãn vai trò), thống kê Bài viết · Lượt thích · Đã lưu, thẻ **Hồ sơ sức khoẻ**, thẻ **Trở thành chuyên gia** (gửi hồ sơ cho admin duyệt; chuyên gia thấy "Mở bảng điều khiển"), **Nội dung của tôi** (tab Bài của tôi với bộ lọc Tất cả / Đã đăng / Chờ duyệt / Bị từ chối · Đã lưu · Bình luận), Đơn hàng của tôi, Lịch tư vấn, Thông tin cá nhân, Giao diện (Sáng / Tối / Theo hệ thống), Đăng xuất.

## Chạy lần đầu

```bash
cd FE/Mobile
flutter create --org vn.veganlife --project-name veganlife_mobile --platforms android,ios .   # chỉ khi chưa có android/ ios/ (không ghi đè lib/)
flutter pub get
flutter run                                                    # mặc định USE_MOCK_DATA=true
```

Cần Flutter ≥ 3.27 (Dart ≥ 3.6). Từ thư mục `FE`, `run_checks.bat` chạy `dart format`, `flutter analyze`, `flutter test` và kiểm tra web.

### Quyền

- iOS `Info.plist`: `NSCameraUsageDescription` (quét tủ lạnh) và `NSPhotoLibraryUsageDescription` (chọn ảnh tủ lạnh, chọn video để đăng).
- Android `AndroidManifest.xml`: `INTERNET`, `CAMERA`, và khối `queries` cho link https (`url_launcher`). Chọn ảnh/video dùng trình chọn ảnh của hệ thống qua `image_picker`, không cần quyền đọc bộ nhớ.

## Cấu hình (`--dart-define`)

| Key | Mặc định | Ý nghĩa |
|---|---|---|
| `USE_MOCK_DATA` | `true` | `false` → gọi API thật qua Dio |
| `API_BASE_URL` | `http://10.0.2.2:5001/api/v1` | Gốc API ASP.NET Core (`launchSettings.json` của BE: cổng 5001; 10.0.2.2 = máy host khi chạy Android emulator) |
| `GUEST_TRIAL_LIMIT` | `3` | Số câu hỏi AI miễn phí cho khách (server quyết định cuối cùng) |
| `MOCK_SCAN_SCENARIO` | `normal` | `empty` / `error` để thử trạng thái biên của màn quét |
| `MOCK_COMMERCE_SCENARIO` | `normal` | `empty` / `error` cho các danh sách đơn hàng, lịch và mọi màn chuyên gia (dịch vụ, lịch hẹn, tài liệu, ví, khách hàng) |
| `MOCK_ADS_SCENARIO` | `normal` | `empty` / `error`: không có thẻ "Được tài trợ" (bảng tin và chi tiết bài không bao giờ báo lỗi vì quảng cáo) |

Ví dụ: `flutter run --dart-define=MOCK_COMMERCE_SCENARIO=error`.

## Khớp với backend (FE ↔ BE)

- **Envelope**: mọi response của BE có dạng `ApiResponse<T> { success, message, data, statusCode }`. `EnvelopeInterceptor` tự bóc `data`; `success: false` thành `ApiException` với `message` từ server.
- **JSON camelCase** = camelCase của tên cột SQL (`media_type` → `mediaType`, `transaction_ref` → `transactionRef`…). Trường do BE tính có tên riêng: `chefName`, `buyer`, `distanceKm`, `averageRating`, `reviewCount`, `chunkCount`. Enum C# như `UserStatusEnum`, `AuthTypeEnum` được nhận cả dạng số lẫn dạng chuỗi.
- **ID**: sơ đồ SQL dùng `INT`; app luôn giữ id dạng chuỗi và gửi lại dạng số khi là số (`apiId` trong `core/utils/json_helpers.dart`).
- **Ngày giờ & tiền**: ISO-8601 UTC trên dây, hiển thị giờ máy; tiền là số nguyên VND.
- **Vai trò**: `Admin` / `User` / `Chef`; giá trị cũ `Member` và giá trị lạ đọc thành `User`.
- Mọi đường dẫn nằm trong `lib/core/network/api_endpoints.dart`; JSON mẫu ở đầu mỗi file `data/models/*.dart` (hoặc đầu API service).

**BE hiện mới có `UsersController`**: `GET /users`, `GET /users/{id}`, `PUT /users/{id}` (`UpdateUserRequest { fullName, phone }`, app dùng khi sửa thông tin cá nhân), `DELETE /users/{id}`. **Chưa có `POST /auth/google` và `GET /users/me`**, nên khi tắt mock sẽ chưa đăng nhập được. Mọi endpoint còn lại BE cần thêm (dưới `/api/v1`):

| Nhóm | Endpoint | File (`lib/features/…`) |
|---|---|---|
| Đăng nhập & tài khoản | POST `/auth/google`; GET `/users/me`, PUT `/users/{id}` (**đã có**); GET `/users/me/posts`, `/users/me/saved-posts`, `/users/me/comments`; POST `/chef-applications` | `core/session/auth_api_service.dart`, `profile/data/profile_api_service.dart`, `community/data/community_api_service.dart` |
| Cộng đồng | GET `/posts?type=&cursor=&limit=`, POST `/posts`; GET/PUT/DELETE `/posts/{id}`; PUT/DELETE `/posts/{id}/like`, `/posts/{id}/save`; GET/POST `/posts/{id}/comments`; PUT/DELETE `/posts/{postId}/comments/{commentId}`; POST `/posts/{id}/reports`; POST `/media/videos` (multipart) | `community/data/community_api_service.dart`, `community/data/media_api_service.dart` |
| Reels | GET `/posts?mediaType=Video&limit=` (kèm `mediaUrl`, `durationSeconds`) | `reels/data/reels_api_service.dart` |
| Video AI | GET `/videos/{id}` (aiStatus: queued → transcribing → extracting → ready/failed), POST `/videos/{id}/extraction` | `video/data/video_api_service.dart` |
| Quảng cáo | GET `/ads/feed?city=&lat=&lng=&limit=` (công khai; chưa gửi `POST /ads/{id}/impression\|click` mà web mô tả) | `ads/data/ads_api_service.dart` |
| Tìm kiếm | GET `/search?q=&type=&lat=&lng=&limit=` | `search/data/search_api_service.dart` |
| Quán chay | GET `/restaurants?lat=&lng=&q=&certifiedOnly=&sort=&limit=`, POST `/restaurants`; GET `/restaurants/{id}`; GET/POST `/restaurants/{id}/reviews`; GET `/restaurants/suggested?food=&lat=&lng=&limit=` | `restaurant/data/restaurant_api_service.dart` |
| Sức khoẻ & thực đơn | GET/PUT `/health-profile/me`; GET `/meal-plans/current`; POST `/meal-plans` (tuần trống), `/meal-plans/generate` (`usePantry`); GET `/meal-plans/{id}/swap-suggestions`; PATCH/DELETE `/meal-plans/{id}/meals`; POST `/meal-plans/current/meals`; GET `/meal-plans/chef-suggestions`; GET `/users/me/recipes`, POST `/recipes`, GET `/recipes/{id}` | `meal_planner/data/meal_planner_api_service.dart`, `recipe/data/recipe_api_service.dart` |
| Tủ lạnh | GET/POST/DELETE `/users/me/ingredients`, DELETE `/users/me/ingredients/{id}` | `meal_planner/data/pantry_api_service.dart` |
| Quét | POST `/vision/scan`, POST `/meal-plans/from-ingredients` | `scanner/data/scanner_api_service.dart` |
| Chatbot | GET `/chat/guest-trial`, POST `/chat/sessions/{id}/messages` (SSE) | `chatbot/data/chat_api_service.dart` |
| Chuyên gia & mua dịch vụ | GET `/chefs`, `/chefs/{id}` (kèm `availableSlots` và `bookedSlots` để làm mờ giờ đã kín); POST `/orders` (409 `slot_taken` khi giờ đã có người giữ, 409 `schedule_conflict` khi trùng lịch tư vấn khác của chính người mua); GET `/orders/me?status=`, `/orders/{id}`; POST `/orders/{id}/cancel`, `/orders/{id}/payments`; GET `/payments/{id}`; GET `/services/{id}/content`; GET `/consultations/me`; POST `/consultations/{id}/cancel` | `chef/data/chef_api_service.dart`, `commerce/data/commerce_api_service.dart` |
| Chuyên gia: studio | GET/PUT `/chefs/me/profile`; GET/POST `/chefs/me/services`, PUT/DELETE `/chefs/me/services/{id}`; GET `/chefs/me/orders?status=`, `/chefs/me/consultations?status=`; POST `/chefs/me/consultations/{id}/confirm\|decline\|start\|complete`; GET/POST `/chefs/me/knowledge-docs` | `chef_studio/data/chef_studio_api_service.dart` |
| Chuyên gia: khách & đề xuất | GET `/chefs/me/clients?status=`, `/chefs/me/clients/{userId}`; GET/POST `/chefs/me/clients/{userId}/suggestions` | `chef_studio/data/chef_clients_api_service.dart`, `meal_planner/data/chef_suggestion_api_service.dart` |
| Chuyên gia: ví | GET `/chefs/me/wallet`, `/chefs/me/wallet/transactions?month=`; PUT `/chefs/me/bank-account`; GET/POST `/chefs/me/withdrawals` | `chef_studio/data/chef_wallet_api_service.dart` |

Đã khai báo nhưng app chưa gọi: `POST /payments/{id}/mock-confirm` (chỉ dùng khi dev; thật là webhook PaymentOS gọi BE), `GET /recipes/{id}/related-posts` (tuỳ chọn; mock tự tính trong `/search`), `GET /chef-applications/me`.

## Chênh lệch với sơ đồ SQL 26 bảng

App coi các trường dưới đây là tuỳ chọn (thiếu thì UI vẫn chạy), nhưng BE/ERD cần bổ sung để dùng thật:

- **Chưa có bảng**:
  - bình luận (`comments`: id, post_id, user_id, content, status Visible/Hidden, created_at, `updated_at`), lượt thích (`post_likes`), bài đã lưu (`saved_posts`), báo cáo bài (`post_reports`), thẻ chế độ ăn của bài (`post_tags`);
  - hồ sơ xin làm chuyên gia (`chef_applications`);
  - ví chuyên gia: `wallets`, `wallet_transactions`, `withdrawal_requests`, `bank_accounts`;
  - chiến dịch quảng cáo (`ad_campaigns`, kèm lượt hiển thị/bấm);
  - món chuyên gia đề xuất (`chef_meal_suggestions`: id, chef_id, user_id, recipe_id, note, slot, target_date, created_at).
- **Thiếu cột**:
  - `meal_plan_recipes.source` (ai / manual / user_recipe / chef / fridge_scan);
  - `recipes.created_by` (Công thức của tôi, món chuyên gia tạo);
  - `user_ingredients.scanned_at` (null = tự thêm, hiện là "Tự thêm");
  - `ingredients.is_vegan BIT`: thực phẩm có thuần chay không, dùng cho màn quét (`POST /vision/scan` trả `isVegan`, kèm `nonVeganReason` và `veganAlternatives` khi không thuần chay) và để tủ lạnh chỉ nhận thực phẩm thuần chay;
  - `posts.updated_at`, `posts.duration_seconds` (Reels);
  - `restaurants.latitude`, `restaurants.longitude`;
  - `reviews`: `UNIQUE(user_id, restaurant_id)` (mỗi người 1 đánh giá, gửi lại là sửa) và `updated_at`;
  - `orders.refunded_at`; `payments.expires_at`, `payments.created_at`;
  - `services.description`, `services.duration_minutes`, `services.content_url`;
  - `consultations.buyer_note`, `chef_notes`, `decline_reason`, `started_at`, `completed_at`;
  - `knowledge_docs.status`, `review_note`, `reviewed_by`, `reviewed_at`.
- **Video AI** chưa có chỗ lưu: trạng thái xử lý (queued / transcribing / extracting / ready / failed, lý do lỗi), tóm tắt, nguyên liệu và các bước theo mốc thời gian, lời thoại.

## Cấu trúc

```
lib/
├── main.dart, app.dart              # ProviderScope, theme mode, shell 4 tab + nút Quét + bong bóng Hỏi AI
├── core/
│   ├── config/env.dart              # --dart-define
│   ├── models/author_summary.dart   # tác giả dùng chung (bài viết, video, bình luận)
│   ├── network/                     # dio_client, api_endpoints, api_envelope, interceptors, api_exception
│   ├── session/                     # phiên, vai trò, tài khoản mock, Google sign-in seam
│   ├── settings/                    # theme mode (Sáng / Tối / Theo hệ thống)
│   ├── theme/                       # sage #1B4D3E, sprout #22C55E, ochre, AI lavender
│   ├── utils/                       # BMI, định dạng VN, tìm kiếm không dấu, nhãn, json helpers
│   └── widgets/                     # Shimmer, empty/error, GuestGate, SignInSheet, mock account picker, FoodCover, UserAvatar, VLCard
└── features/
    ├── community/                   # Trang chủ: feed, chi tiết bài, trang bình luận, đăng/sửa bài, tải video, báo cáo
    ├── reels/                       # dải Reels + trình phát toàn màn hình
    ├── ads/                         # thẻ "Được tài trợ" (bảng tin + chi tiết bài)
    ├── video/                       # Video + AI tóm tắt (nguyên liệu, các bước, lời thoại, tua theo mốc)
    ├── search/                      # Tìm kiếm toàn app
    ├── restaurant/                  # Quán chay gần bạn, đánh giá, gợi ý quán, khớp món ↔ quán
    ├── meal_planner/                # Thực đơn, 4 nguồn món, hồ sơ sức khoẻ, tủ lạnh, đề xuất từ chuyên gia
    ├── recipe/                      # Chi tiết công thức
    ├── scanner/                     # Nút Quét, chọn cách quét, nhận diện + xác nhận nguyên liệu
    ├── chef/                        # Danh bạ chuyên gia, hồ sơ, dịch vụ, đặt lịch, mua gói, lịch của tôi
    ├── commerce/                    # Đơn hàng, thanh toán PaymentOS, quyền truy cập, nội dung đã mua
    ├── chef_studio/                 # Vai trò Chef: bảng điều khiển, dịch vụ, lịch hẹn, tài liệu, ví, khách hàng, đề xuất món
    ├── profile/                     # Tôi: hồ sơ, nội dung của tôi, đăng ký chuyên gia
    └── chatbot/                     # Hỏi AI (RAG)
        ├── data/                    # models (DTO + JSON), *_api_service.dart, mock_*_repository.dart
        ├── domain/                  # entities, quy tắc nghiệp vụ
        └── presentation/            # controllers (Riverpod), screens, widgets
```

## Thử nhanh (mock)

**Tài khoản & dữ liệu mẫu**

- App mở ở chế độ khách. Thích / bình luận / đăng bài / đặt lịch / đánh giá quán đều mở sheet đăng nhập; đăng nhập xong thao tác được làm tiếp.
- **Minh Anh**: lịch tư vấn với ThS. DD Phạm Thu Hà (đã xác nhận, 2 ngày nữa) và với Tâm (đã xong, có ghi chú); đã mua "Khoá meal prep chay 4 tuần" ("Mở nội dung"); đơn "Thực đơn VIP 30 ngày giảm cân lành mạnh" đang chờ thanh toán ("Thanh toán tiếp"); bài chờ duyệt `p_me_pending_celery`, bài bị từ chối `p_me_rejected_detox`; video `p_me_banh_xeo` bị AI xử lý lỗi (thử "Thử trích xuất lại"); tủ lạnh có Đậu hũ, Cà chua, Nấm rơm (Quét) và Gạo lứt (Tự thêm); 2 món Tâm đề xuất (một món ghi "Cho bữa tối · <ngày mai>"); dị ứng đậu phộng: bữa sáng thứ Năm và bữa trưa thứ Bảy hiện cảnh báo.
- **Lê Quang Tâm**: dịch vụ `svc_tam_consult` (350.000đ, 60 phút), `svc_tam_course` (990.000đ), `svc_tam_vip` (1.500.000đ). Lịch: Hoàng Nam **chờ xác nhận**, Thảo Vy **bắt đầu sau 10 phút** (bấm "Bắt đầu buổi tư vấn" được ngay), Ngọc Trâm đã xong. Khách: Lan Phương, Bảo Trâm, Gia Hân (VIP), Đức Huy, Quốc Việt (khoá học), Hoàng Nam, Thảo Vy, Ngọc Trâm (tư vấn) và Minh Anh. Tài liệu: 1 đã duyệt (18 đoạn), 1 chờ duyệt, 1 bị từ chối. Ví: tài khoản Vietcombank, 1 lần rút đã chuyển, 1 lần bị từ chối.
- Luồng hai tài khoản: Minh Anh đặt lịch với Tâm và thanh toán → đăng nhập Tâm thấy yêu cầu ở "Chờ xác nhận" → từ chối kèm lý do → quay lại Minh Anh thấy "Chuyên gia từ chối" và "Đã hoàn tiền".

**Kích hoạt có chủ đích**

- **`#fail`** → lỗi máy chủ 503 khi có trong: bình luận (thêm, sửa), tiêu đề/nội dung bài (đăng, sửa), ghi chú đặt lịch, họ tên ở "Thông tin cá nhân", tên món tự nhập và tên "Công thức của tôi", tên nguyên liệu thêm vào tủ, ô tìm kiếm (toàn app và quán chay), nhận xét đánh giá quán, tên/địa chỉ quán gợi ý; phía chuyên gia: tên dịch vụ, lý do từ chối, ghi chú hoàn thành buổi tư vấn, tiêu đề tài liệu, giới thiệu hồ sơ chuyên gia, tên chủ tài khoản ngân hàng, tên món/lời nhắn đề xuất. Quán **"Quán thử nghiệm QA #fail"** luôn lỗi khi gửi đánh giá.
- **`#flag`** hoặc các cụm `chữa khỏi`, `giảm cân thần tốc`, `inbox`, `zalo`, `cam kết hoàn tiền` (không dấu cũng tính) trong tiêu đề/nội dung bài → bài vào **Chờ duyệt**, không lên bảng tin và tìm kiếm.
- **`#expire`** trong ghi chú đặt lịch → mã QR hết hạn sau 30 giây ("Mã QR đã hết hạn" → "Tạo mã mới" hoặc "Huỷ đơn"). Màn thanh toán mock có "Mô phỏng đã thanh toán" / "Mô phỏng thất bại".
- **`#offline`** trong câu hỏi chat → mất mạng giữa chừng.
- **Cân nặng `99.9`** khi lưu hồ sơ sức khoẻ → 503.
- **Tải video** (Tạo bài viết › Video › Tải video lên › Chọn video › Tệp mẫu): `banh_xeo_chay.mp4` (48 MB, tải xong ~3 giây), `mat_ket_noi.mp4` (mất kết nối ở 60 %, "Thử lại"), `video_4k_qua_lon.mov` (850 MB, bị chặn trước khi tải). Video đăng mới (tải lên hoặc dán link) qua đủ 3 bước AI trong ~16 giây.
- **Quét** (ảnh tủ lạnh mẫu, cũng là kết quả của camera / "Chọn ảnh" ở chế độ mock): 7 thực phẩm, "Tìm thấy 7 thực phẩm · 5 thuần chay · 2 không thuần chay · 1 cần xác nhận". "Rau chân vịt" (58 %) hiện "Chưa chắc chắn", phải bấm Xác nhận mới được lưu vào tủ. "Trứng gà" (94 %) và "Sữa bò" (88 %) nằm ở "Không thuần chay — không lưu" nên nút là "Lưu vào tủ lạnh (4)"; chạm "Đậu hũ non" → "Lưu vào tủ lạnh (5)"; trong Thực đơn › "Nguyên liệu trong tủ", "Đậu hũ non" có biểu tượng "Tự thêm" (bút), các món camera nhận diện có biểu tượng "Quét".
- **Nhập tay**: `trứng vịt`, `mật ong`, `nước mắm`, `thit bo` (không dấu cũng nhận) → không thuần chay; chỉ nhập món không thuần chay → "Chưa có thực phẩm thuần chay để lưu". `nấm mỡ`, `rau chân vịt`, `sữa đậu nành`, `gà chay` → thuần chay. Ở Thực đơn › "Nguyên liệu trong tủ", thêm `thịt bò` → bị từ chối kèm "Gợi ý thay thế" (Đậu hũ, Nấm đùi gà, Mì căn).
- **Lỗi nghiệp vụ**: Minh Anh đặt Tâm lúc 19:30 ngày kia (trùng lịch với ThS. DD Phạm Thu Hà) → giờ đó mờ "Bạn có lịch", gọi thẳng API → 409 `schedule_conflict`; xoá `svc_tam_course` → "Dịch vụ đã có đơn hàng nên không xoá được."; bắt đầu buổi tư vấn sớm hơn 15 phút → 409; ghi chú hoàn thành < 20 ký tự hoặc lý do từ chối < 10 ký tự bị chặn; mở nội dung gói chưa mua → "Bạn chưa mua gói này"; rút dưới 100.000đ, vượt số dư "Có thể rút" hoặc chưa có tài khoản nhận tiền → báo lỗi; rút ≤ 5.000.000đ tự chuyển sau ~10 giây.
- **Tìm kiếm**: `bun rieu` (không dấu) → công thức "Bún riêu chay", khối "Gợi ý cho «Bún riêu chay»" và quán gợi ý; `xyzxyz` → trạng thái trống. Danh bạ chuyên gia: `chay hue`, `dinh duong`.
- **Thẻ tài trợ trong bài**: mở bài "Bún riêu chay cà chua đậu hũ…" → thẻ Bún Riêu Chay Hạnh Tâm; bài hỏi về B12 (không nói về món) không có thẻ.
- **`MOCK_*_SCENARIO`**: `MOCK_SCAN_SCENARIO=empty|error`, `MOCK_COMMERCE_SCENARIO=empty|error`, `MOCK_ADS_SCENARIO=empty|error` (xem bảng cấu hình).

Video mẫu (bảng tin, Reels) dùng clip công khai của Flutter docs (`bee.mp4`, `butterfly.mp4`) và MDN (`flower.mp4`, CC0); Reels có 7 clip khi xem ở chế độ khách. Thay bằng URL Cloudinary khi BE sẵn sàng.

## Nối API thật

1. Đặt `USE_MOCK_DATA=false` và `API_BASE_URL`.
2. Google sign-in: hoàn thiện `RemoteAuthApiService.signInWithGoogle` (lấy ID token bằng `google_sign_in` / Firebase / Supabase rồi gọi `exchangeGoogleIdToken`). Server trả `{ accessToken, user: { id, fullName, email, role } }`.
3. Chat dùng SSE (`text/event-stream`) với các sự kiện `token`, `citation`, `done`, `error`. Khách gửi kèm `X-Guest-Token`; server trả `402` / `trial_exhausted` khi hết lượt.
4. PaymentOS: BE tạo mã QR (`qrCodeUrl`) và nhận webhook; app chỉ hỏi `GET /payments/{id}` mỗi 3 giây. Nút mô phỏng thanh toán tự ẩn khi tắt mock.
5. Chưa có (cần thêm thư viện, chờ duyệt): GPS thật (vị trí đang cố định ở Quận 1), bản đồ trong app, tải video thật lên Cloudinary.

```bash
flutter analyze && flutter test
```
