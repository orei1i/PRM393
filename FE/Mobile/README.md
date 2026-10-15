# VeganLife Mobile (Flutter) — nền tảng chính

VeganLife là **mobile-first**: mọi hành trình của khách, thành viên và chuyên gia đều nằm trong app này. `FE/Web` chỉ là **admin console** để kiểm duyệt và quản lý.

Feature-first Flutter, **Riverpod** cho state, **Dio** cho API. Feature nào cũng có abstract API service + **Mock repository**, nên app chạy được trước khi backend ASP.NET Core sẵn sàng. UI tiếng Việt.

## Điều hướng

| Tab | Màn hình | Khách xem được? |
|---|---|---|
| Trang chủ | Bảng tin cộng đồng: công thức, video (AI tóm tắt), hỏi đáp; thích, lưu, bình luận, báo cáo, đăng bài | Xem: có · Tương tác: cần đăng nhập |
| Thực đơn | Thực đơn AI 7 ngày, BMI, macro, đổi món, cảnh báo dị ứng | Cần đăng nhập |
| Quét | Camera nhận diện nguyên liệu → gợi ý món (mở toàn màn hình) | Cần đăng nhập |
| Chuyên gia | Danh bạ đầu bếp / chuyên gia dinh dưỡng đã xác minh, hồ sơ, gói tư vấn, đặt lịch | Xem: có · Đặt lịch: cần đăng nhập |
| Tôi | Hồ sơ, sức khoẻ, bài của tôi / đã lưu, lịch tư vấn, đăng ký chuyên gia, giao diện, đăng xuất | Cần đăng nhập |
| Nút **Hỏi AI** | Chatbot RAG có trích dẫn, khách hỏi miễn phí 3 lần | Có |

## Chạy lần đầu

```bash
cd FE/Mobile
flutter create --org vn.veganlife --project-name veganlife_mobile --platforms android,ios .   # tạo android/ ios/ (không ghi đè lib/)
flutter pub get
flutter run                                                    # mặc định USE_MOCK_DATA=true
```

Cần Flutter ≥ 3.27 (Dart ≥ 3.6). Từ thư mục `FE`, `run_checks.bat` chạy `dart format`, `flutter analyze`, `flutter test` và kiểm tra web.

### Quyền

- iOS `Info.plist`: `NSCameraUsageDescription` (đã thêm).
- Android `AndroidManifest.xml`: `INTERNET`, `CAMERA`, và khối `queries` cho link https (đã thêm).

## Cấu hình (`--dart-define`)

| Key | Mặc định | Ý nghĩa |
|---|---|---|
| `USE_MOCK_DATA` | `true` | `false` → gọi API thật qua Dio |
| `API_BASE_URL` | `http://10.0.2.2:5001/api/v1` | Gốc API ASP.NET Core (`launchSettings.json` của BE: cổng 5001; 10.0.2.2 = máy host khi chạy Android emulator) |
| `GUEST_TRIAL_LIMIT` | `3` | Số câu hỏi AI miễn phí cho khách (server quyết định cuối cùng) |
| `MOCK_SCAN_SCENARIO` | `normal` | `empty` / `error` để thử trạng thái biên của màn quét |

## Khớp với backend (FE ↔ BE)

- **Envelope**: mọi response của BE có dạng `ApiResponse<T> { success, message, data, statusCode }`. `EnvelopeInterceptor` tự bóc `data`; `success: false` thành `ApiException` với `message` từ server.
- **JSON camelCase** (mặc định của ASP.NET). Enum C# như `UserStatusEnum`, `AuthTypeEnum` được nhận cả dạng số lẫn dạng chuỗi.
- **Người dùng**: `GET /users/me`, và `PUT /users/{id}` gửi đúng `UpdateUserRequest { fullName, phone }` của `UsersController`.
- **Endpoint BE cần bổ sung** (đã định nghĩa trong `core/network/api_endpoints.dart`, JSON mẫu ở đầu mỗi file `data/models/*.dart`):

| Nhóm | Endpoint |
|---|---|
| Cộng đồng | `GET/POST /posts`, `GET /posts/{id}`, `PUT/DELETE /posts/{id}/like`, `PUT/DELETE /posts/{id}/save`, `GET/POST /posts/{id}/comments`, `POST /posts/{id}/reports` |
| Video AI | `GET /videos/{id}` (aiStatus: queued → transcribing → extracting → ready/failed), `POST /videos/{id}/extraction` |
| Chuyên gia | `GET /chefs`, `GET /chefs/{id}`, `POST /consultations`, `GET /consultations/me`, `POST /consultations/{id}/cancel` |
| Tài khoản | `GET /users/me`, `GET /users/me/posts`, `GET /users/me/saved-posts`, `POST /chef-applications` |
| Đã có từ trước | health profile, meal plans, vision scan, chat (SSE) |

## Cấu trúc

```
lib/
├── main.dart, app.dart              # ProviderScope, theme mode, shell 5 tab + nút Hỏi AI
├── core/
│   ├── config/env.dart
│   ├── models/author_summary.dart   # tác giả dùng chung (bài viết, video, bình luận)
│   ├── network/                     # dio_client, api_endpoints, api_envelope, interceptors, api_exception
│   ├── session/                     # guest token, Google sign-in seam, auth headers
│   ├── settings/                    # theme mode (Sáng / Tối / Theo hệ thống)
│   ├── theme/                       # sage #1B4D3E, sprout #22C55E, ochre, AI lavender
│   ├── utils/                       # BMI, định dạng VN, tìm kiếm không dấu, nhãn
│   └── widgets/                     # Shimmer, empty/error, GuestGate, SignInSheet, FoodCover, UserAvatar, VLCard
└── features/
    ├── community/                   # Trang chủ: feed, chi tiết bài, bình luận, đăng bài, báo cáo
    ├── video/                       # Video + AI tóm tắt (nguyên liệu, các bước, lời thoại, tua theo mốc)
    ├── meal_planner/                # Thực đơn AI
    ├── scanner/                     # Quét tủ lạnh
    ├── chef/                        # Danh bạ chuyên gia, hồ sơ, đặt lịch, lịch của tôi
    ├── profile/                     # Tôi: hồ sơ, sức khoẻ, nội dung, đăng ký chuyên gia
    └── chatbot/                     # Hỏi AI (RAG)
        ├── data/                    # models (DTO + JSON), *_api_service.dart, mock_*_repository.dart
        ├── domain/                  # entities
        └── presentation/            # controllers (Riverpod), screens, widgets
```

## Thử nhanh các trạng thái (mock)

- **Khách → thành viên**: app mở ở chế độ khách. Thích / bình luận / đăng bài / đặt lịch đều mở sheet đăng nhập. "Tiếp tục với Google" là mock; sau khi đăng nhập, thao tác được thực hiện tiếp.
- **Video AI**: đăng bài loại *Video* kèm một link bất kỳ → video đi qua các bước *Nhận video → Nhận dạng giọng nói → Trích xuất* (~16 giây) rồi mới có tóm tắt. Trong *Tôi › Bài viết của tôi* có sẵn một video lỗi, thử nút *Thử trích xuất lại*.
- **Lỗi có chủ đích**: thêm `#fail` vào bình luận, ghi chú đặt lịch hoặc họ tên để giả lập lỗi máy chủ; `#offline` trong câu hỏi chat để giả lập mất mạng giữa chừng.
- **Dị ứng**: hồ sơ mock dị ứng đậu phộng; bữa sáng thứ Năm và bữa trưa thứ Bảy kích hoạt cảnh báo.
- **Quét**: "Rau chân vịt?" (58 %) phải được xác nhận mới tính vào nguyên liệu.
- **Tìm chuyên gia**: tìm không dấu, ví dụ `chay hue`, `dinh duong`.

Video mẫu dùng clip công khai của Flutter docs; thay bằng URL Cloudinary khi BE sẵn sàng.

## Nối API thật

1. Đặt `USE_MOCK_DATA=false` và `API_BASE_URL`.
2. Google sign-in: hoàn thiện `RemoteAuthApiService.signInWithGoogle` (lấy ID token bằng `google_sign_in` / Firebase / Supabase rồi gọi `exchangeGoogleIdToken`).
3. Chat dùng SSE (`text/event-stream`) với các sự kiện `token`, `citation`, `done`, `error`. Khách gửi kèm `X-Guest-Token`; server trả `402` / `trial_exhausted` khi hết lượt.

```bash
flutter analyze && flutter test
```
