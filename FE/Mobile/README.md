# VeganLife Mobile (Flutter)

Feature-first Flutter client: **Riverpod** state, **Dio** API layer, every feature ships an abstract API service + a **Mock repository**, so the UI runs before the ASP.NET Core backend is ready. UI copy is Vietnamese.

## Chạy lần đầu

```bash
cd FE/Mobile
flutter create --org vn.veganlife --project-name veganlife_mobile --platforms android,ios .   # tạo android/ ios/ (không ghi đè lib/)
flutter pub get
flutter run                                                    # mặc định USE_MOCK_DATA=true
```

Requires Flutter ≥ 3.27 (Dart ≥ 3.6).

### Quyền camera (bắt buộc cho màn Quét tủ lạnh)

`ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>VeganLife dùng camera để nhận diện nguyên liệu trong tủ lạnh.</string>
<key>NSMicrophoneUsageDescription</key>
<string>VeganLife không ghi âm; quyền này do thư viện camera yêu cầu.</string>
```

Android: the `camera` plugin adds the CAMERA permission; keep `minSdkVersion` ≥ 21. On an emulator without a camera the scanner falls back to a simulated fridge automatically.

## Cấu hình (`--dart-define`)

| Key | Default | Purpose |
|---|---|---|
| `USE_MOCK_DATA` | `true` | `false` → call the real API through Dio |
| `API_BASE_URL` | `http://10.0.2.2:5080/api/v1` | ASP.NET Core root (10.0.2.2 = host from Android emulator) |
| `GUEST_TRIAL_LIMIT` | `3` | Free AI questions for guests (server is the source of truth) |
| `MOCK_SCAN_SCENARIO` | `normal` | `empty` / `error` to test scanner edge states |

```bash
flutter run --dart-define=USE_MOCK_DATA=false --dart-define=API_BASE_URL=https://api.veganlife.vn/api/v1
```

## Cấu trúc

```
lib/
├── main.dart, app.dart              # ProviderScope, theme, bottom navigation
├── core/
│   ├── config/env.dart              # dart-define flags (useMockData…)
│   ├── network/                     # dio_client, api_endpoints, interceptors, api_exception
│   ├── session/                     # guest token, Google sign-in seam, auth headers
│   ├── theme/                       # sage #1B4D3E, sprout #22C55E, ochre, AI lavender, typography
│   ├── utils/                       # BMI, VN formatters, JSON readers, labels
│   └── widgets/                     # Shimmer skeleton, empty/error views, GuestGate, VLCard
└── features/
    ├── meal_planner/                # Module 1
    ├── scanner/                     # Module 2
    └── chatbot/                     # Module 3
        ├── data/                    # models (DTO + JSON), *_api_service.dart, mock_*_repository.dart
        ├── domain/entities/
        └── presentation/            # controllers (Riverpod), screens, widgets
```

## Thử nhanh các trạng thái

- **Khách → thành viên**: app starts as a guest. Plan and Scan show the sign-in gate; Chat allows 3 questions, then the sign-in sheet. "Tiếp tục với Google" is mocked in mock mode; the held question is sent after sign-in.
- **Mất mạng giữa chừng**: add `#offline` to a chat question; the partial answer stays and "Tiếp tục từ đây" resumes.
- **Dị ứng**: the mock profile is allergic to peanuts; Thursday breakfast and Saturday lunch trigger the allergy guard. Swap suggestions never include peanuts.
- **Quét**: low-confidence "Rau chân vịt?" (58 %) must be confirmed before it counts.

## Nối API thật

1. Set `USE_MOCK_DATA=false` and `API_BASE_URL`.
2. Endpoints and JSON shapes are documented at the top of each `data/models/*.dart` file and in `core/network/api_endpoints.dart`.
3. Google sign-in: implement `RemoteAuthApiService.signInWithGoogle` (get an ID token with `google_sign_in`, then call `exchangeGoogleIdToken`).
4. Chat uses SSE (`text/event-stream`) with `token`, `citation`, `done`, `error` events; guests send `X-Guest-Token`, and the server answers `402` / `trial_exhausted` when the quota is spent.

```bash
flutter analyze && flutter test
```
