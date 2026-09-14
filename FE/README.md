# VeganLife

Flutter frontend cho cộng đồng ăn chay, trợ lý dinh dưỡng mô phỏng và lập kế hoạch bữa ăn. Ứng dụng chạy được với dữ liệu seed, không cần tài khoản, API key hay backend.

**Phạm vi:** frontend tương tác dùng mock repositories trong bộ nhớ. Đây không phải hệ thống production đã có xác thực, lưu trữ, AI hoặc dịch vụ bản đồ thật. Restart/hot restart sẽ khôi phục dữ liệu seed.

## Chạy ứng dụng

Toolchain đã dùng: **Flutter 3.38.7 stable / Dart 3.10.7**. SDK constraints và dependencies ở `pubspec.yaml`; phiên bản đã resolve ở `pubspec.lock`.

Chạy tại thư mục chứa `pubspec.yaml`:

```sh
flutter pub get
flutter run -d chrome
# Hoặc chọn Android emulator / thiết bị đã kết nối:
flutter devices
flutter run -d emulator-5554
```

Trong chế độ debug, nút nổi **DEMO · GUEST** ở góc phải phía trên nội dung cho phép đổi **Guest / Member / Admin**. Nút được bố trí ngoài vùng chat để không che ô nhập. Đổi vai trò chuyển về trang chủ tương ứng và hủy công việc/chat thuộc vai trò cũ.

Nút đổi vai trò bị ẩn mặc định ở release. Để kiểm thử bản release bằng cả ba vai trò:

```sh
flutter build web --dart-define=DEMO_ROLES=true
flutter build apk --debug
# Chỉ dùng cho demo nội bộ, không phải cơ chế cấp quyền production:
flutter build apk --dart-define=DEMO_ROLES=true
```

Không dùng lệnh release demo cho sản phẩm có dữ liệu thật. Ẩn nút role switcher **không biến demo auth thành xác thực an toàn**. Android release signing hiện vẫn là cấu hình scaffold dành cho phát triển, chưa cấu hình khóa phát hành. iOS cần macOS/Xcode để build và ký.

## Luồng dùng thử

| Vai trò | Chức năng và thao tác có hiệu lực |
| --- | --- |
| Guest | Explore: tìm tên/nguyên liệu, lọc danh mục/video, phân trang; xem bài/video; thao tác lưu/vote/comment yêu cầu đăng nhập |
| Guest trial | Ba câu hỏi hợp lệ, phản hồi mock streaming, bộ đếm lượt và sheet mời đăng nhập khi hết lượt |
| Member | Feed, bookmark, up/downvote, comment/reply, tạo/sửa/xóa bài hoặc video mock của mình |
| Member AI | Prompt gợi ý, chat streaming, stop, reset, error state; nhập `/demo-error` để thử lỗi có chủ đích |
| Member meal plan | BMI metric/imperial có kiểm tra đầu vào; lịch 7 ngày, 3 bữa/ngày; tạo lịch theo pantry; chọn ngày; checklist mua sắm |
| Member discovery | Tìm shop mẫu, lọc loại, khoảng cách tăng dần, danh sách/sơ đồ, chọn marker để xem shop |
| Member profile | My Posts/My Videos/My Comments, sửa/xóa có kiểm tra chủ sở hữu; light/dark/system theme |
| Admin | Metrics cập nhật từ dữ liệu chung; biểu đồ tuần mẫu kèm tooltip và bảng dữ liệu; cảnh báo và nhật ký |
| Admin moderation | Approve/Delete/Warn có xác nhận; resolve báo cáo; lịch sử hành động; delete cập nhật feed/profile/dashboard |
| Admin catalog | CRUD category/tag; chặn tên trùng và xóa category đang dùng; rename cập nhật bài, bộ lọc và form đang mở |
| Admin AI operations | Lọc log, review signal, manual override có lý do; cập nhật log và dashboard, không thay đổi mô hình thực |

**Seed:** 8 bài (gồm 2 video), comment phân luồng, tài khoản Member `Alex Green`, 4 cửa hàng hư cấu tại TP.HCM, 3 báo cáo moderation và 3 AI logs mẫu.

### Quy tắc đáng chú ý

- Trial tính **ba prompt hợp lệ được chấp nhận**, không phải ba chunk phản hồi. Prompt trống/quá dài và gửi trùng khi đang stream không tốn lượt. Prompt đã được nhận nhưng bị dừng hoặc lỗi vẫn tính lượt.
- Xóa chat, rời trang hoặc đổi vai trò không reset trial quota. Restart ứng dụng reset quota vì không có lưu trữ bền vững. Sheet tự động chỉ mở sau phản hồi hoàn tất; dừng lượt cuối vẫn tốn lượt nhưng không mở sheet muộn.
- Dialog sửa comment, category/tag và AI override giữ nguyên draft khi validation thất bại; chỉ đóng sau khi lưu thành công hoặc người dùng chọn Cancel.
- Lỗi BMI độc lập với lỗi/loading của planner. Quay lại planner trong cùng tuần giữ lịch, ngày chọn và checklist; mở lại/resume sang tuần mới cập nhật tuần hiện tại. Generate cũng kiểm tra lại tuần lúc hoàn tất.
- Vote là một trạng thái trên mỗi người/bài: bấm lại bỏ vote; chuyển up → down thay đổi đúng 2 điểm.
- Xóa comment xóa cả nhánh reply để tránh dữ liệu mồ côi. UI xác nhận điều này trước khi xóa.
- Warn chỉ ghi nhận cảnh báo local và giữ bài; không gửi thông báo thật. Approve giữ nội dung và giải quyết báo cáo. Nếu chủ bài xóa nội dung, report được resolve và gắn `CONTENT REMOVED`, giảm pending count; không tạo hành động admin giả và không còn nút review/approve bài đã mất.
- AI log cần review khi confidence < 0.8 và chưa override. Entity `AiModelLog.needsReview` dùng chung cho filter, badge và dashboard.
- Không được xóa category đang được bài sử dụng hoặc category cuối cùng. Đổi tên category cascade sang bài liên quan. Tên filter hệ thống được dành riêng. Tag là catalog biên tập độc lập, chưa gắn vào từng RecipePost.
- Các route admin có guard; lệnh mutation có guard tại ViewModel. Các guard phía client chỉ minh họa hành vi UI, **backend vẫn phải xác thực token, role, quyền sở hữu và quota**.

## Kiến trúc

**Feature-first MVVM + ChangeNotifier nhất quán.** `provider` làm DI/listening; `go_router` xử lý navigation và role redirects. Không sử dụng Bloc, Riverpod hoặc một state-management thứ hai.

```text
View/widget → ViewModel command → Domain repository interface
                                  ↓
                            Mock implementation
                                  ↓ changes stream
Other subscribed ViewModels → notifyListeners → rebuilt views
```

- `domain/`: entities và repository interfaces pure Dart, không import Flutter/provider.
- `data/`: mock implementation, seed và DTO khi có dữ liệu map cần chuyển đổi. Không nhân đôi mỗi entity chỉ để lấp đầy thư mục.
- `presentation/view_models/`: validation, tính toán, lọc/phân trang, mutation, quyền hạn, lifecycle và state.
- `presentation/views/`, `widgets/`: render/bind state, điều khiển focus/text/scroll, dialog và navigation. Không truy cập trực tiếp mock repository.
- `core/`: theme, layout dùng chung, router/shell, async state, cấu hình backend tương lai.
- `bootstrap.dart`: composition root duy nhất; tạo repositories trước ViewModels và dispose theo thứ tự phụ thuộc ngược.
- `role_switcher` là widget kiểm thử dùng `AuthViewModel` của feature `auth`; không tạo một bản sao session/repository để đổi vai trò.

### Dữ liệu chung, không phải những màn hình tách rời

`MockCommunityRepository` là nguồn chung của community, explore, profile, categories, moderation và dashboard. Các repository phát broadcast stream đồng bộ sau mutation. Các ViewModel nhận sự kiện, tính getter mới và gọi `emit()` → `notifyListeners()`.

`MockCategoryRepository` được inject qua interface vào feed và composer. Composer giữ ID của category, nên category đổi tên trong khi form đang mở vẫn được giữ lựa chọn đúng. Nếu category bị xóa, form trở về category hiện có đầu tiên.

Quota nằm trong `MockTrialQuotaRepository` ở scope ứng dụng, tách khỏi chat history. Chat sử dụng generation token, `StreamSubscription` và `Completer` để ngăn callback cũ cập nhật dữ liệu sau cancel/đổi vai trò/dispose. Planner cũng có request token cho thao tác generate bất đồng bộ.

Transcript chat là snapshot immutable, chỉ đổi identity khi tin nhắn thay đổi. `Selector` tách transcript/composer/quota để nhập draft không rebuild danh sách; `ListView.builder` dựng các bubble trong viewport/cache thay vì cả lịch sử. Auto-scroll chỉ theo phản hồi khi người dùng đang gần cuối, không kéo khỏi tin nhắn cũ đang đọc. Bố cục thiếu chiều cao chuyển sang khung cuộn, giữ header, disclaimer và ô nhập có thể truy cập.

Navigation dùng `navigationRoot` để gắn BMI vào Meal plan, nội dung cá nhân/edit vào You, bài/video vào section theo vai trò. Đây là section ownership, không phải lịch sử tab đã mở bài. Nút Back dùng `pop` khi có history, nếu không thì về `AuthViewModel.homeRoute`.

`VeganLifeApp` sở hữu dependency graph mặc định. Khi inject `AppDependencies` vào tests, bên gọi chịu trách nhiệm dispose nó sau khi unmount app. Post detail, composer và video player có ViewModel do route provider sở hữu.

### Model cụ thể

`lib/src/features/community/domain/entities/community_entities.dart` định nghĩa `RecipePost`, `CookingVideo`, `Comment`, `VoteState`. Ví dụ khởi tạo entity thật:

```dart
const post = RecipePost(
  id: 'example',
  authorId: 'member-demo',
  author: 'Alex Green',
  title: 'Sesame tofu bowl',
  description: 'A quick plant-based lunch.',
  category: 'Quick & easy',
  ingredients: ['Tofu', 'Rice', 'Sesame'],
  steps: ['Cook rice.', 'Pan-fry tofu.', 'Combine and serve.'],
);
final edited = post.copyWith(title: 'My sesame tofu bowl');
```

`data/models/recipe_post_model.dart` chuyển seed map thành domain entity. Collections được đưa ra ngoài repositories/ViewModels dưới dạng unmodifiable; entity lists được seed bằng const hoặc copied unmodifiable trong create/edit.

### ViewModel cụ thể và điểm notify

`CommunityFeedViewModel` được tạo bằng ba dependency interfaces/state đã có:

```dart
final vm = CommunityFeedViewModel(communityRepository, authViewModel, categoryRepository);
vm.addListener(renderUpdatedState);
vm.setQuery('tofu'); // trim query, reset page, emit()
vm.setFilter('Quick recipes'); // derived filter, reset page, emit()
vm.loadMore(); // tăng page limit, emit()
// vm.posts, vm.hasMore, vm.filter là state cho View bind.
vm.dispose(); // hủy cả community/catalog subscriptions và auth listener.
```

Các API chính khác:

| ViewModel | State/getters | Commands / notification |
| --- | --- | --- |
| Auth | role, session, homeRoute, isGuest, isAdmin | switchRole / signOut cập nhật session và emit |
| PostDetail | post, votes, vote, comments, replies, canSubmit | toggleVote, toggleSaved, submitComment; repo event rebuild các màn hình liên quan |
| CreatePost | title, description, category, categories, editing, error | setters emit; save validate, trả ID/null; kiểm tra actor/chủ sở hữu |
| AiNutrition | messages, draft, quickActions, busy, error | submit trả Future<bool>; emit từng chunk; cancel kết thúc future đang chờ |
| TrialChat | limit.remaining, limit.depleted | override reserveTurn; quota được consume trước khi bắt đầu stream |
| MealPlanner | profile, bmiError, plan, selectedDay, shopping, busy, error | calculateBmi, syncCurrentWeek, generate, selectDay, toggleIngredient |
| NearbyShops | results, selected, mapMode | setQuery, setKind, selectShop, setMap; Haversine và sort trong ViewModel |
| UserProfile | profile, summary, tab, posts, comments | setTab, deletePost, editComment, deleteComment |
| AdminDashboard | metrics, logs, activity, alert, tableMode | refresh, dismissAlert, toggleTable; subscribe các repository |
| ContentModeration | flags, actions | act(id, decision), filter; admin guard |
| CategoryManagement | categories, tags, usage | save/delete, duplicate/in-use validation qua repository |
| AiOperations | logs, metrics, filter | setFilter, applyOverride(id, text, reason), admin/length validation |

`core/state/view_model.dart` cung cấp `LoadStatus`, `busy`, `error`, `fail`, `clearError`, `setBusy` và `emit`. `emit` không notify sau dispose. Seed feeds là nguồn đồng bộ nên không có loading giả khi mở feed; streaming và generate có loading thật trong mô phỏng.

## Bốn màn hình chính

- [CommunityFeedView](lib/src/features/community/presentation/views/community_feed_view.dart): editorial header, hero, search/chips, thẻ công thức thích ứng và pagination.
- [AiNutritionChatView](lib/src/features/ai_nutrition/presentation/views/ai_nutrition_chat_view.dart): bind `NutritionChatPanel`; quick prompts, lazy message stream, stop; composer cố định khi đủ chiều cao, cuộn được khi màn hình thấp/chữ lớn.
- [WeeklyMealCalendarView](lib/src/features/meal_planner/presentation/views/weekly_meal_calendar_view.dart): pantry form, day selector, ba thẻ bữa ăn, shopping checklist.
- [AdminDashboardView](lib/src/features/admin_dashboard/presentation/views/admin_dashboard_view.dart): metrics, alerts, activity chart/table và workspace links.

Material 3 dùng emerald `#2E7D32`, mint `#A5D6A7`, nền sáng `#F8FAF9`; dark theme được cấu hình riêng. Bottom navigation đổi thành rail từ 840px và rail mở rộng từ 1120px. Nội dung có max-width và cards wrap theo diện tích thực. Hình món ăn là CustomPainter offline, không phải ảnh sản phẩm thực. Biểu đồ một series dùng cùng màu cho mọi cột, có tooltip, semantics và bảng số liệu; màu chart dark `#43A047` đã được kiểm tra riêng trên nền tối.

## Kiểm thử

```sh
dart format lib test integration_test test_driver
flutter analyze
flutter test
# Cần emulator/thiết bị Android đã chạy; tạo PNG trong build/screenshots:
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_flow_test.dart -d emulator-5554
```

- `test/features/`: BMI/planner state isolation, week rollover/in-flight cancellation, trial quota, stream lifecycle, vote/comment, CRUD/ownership, pagination, 7-day plan, distances, moderation reconciliation, category sync, video clock/invalidation và AI review policy.
- `test/routing/`: guest/member deep-link guards; cancel khi rời chat; video không tồn tại/không phải video.
- `test/widgets/`: bốn flagship views và chart/table responsive; auth/video ở màn hình thấp, chữ lớn và keyboard inset; section navigation/Back; editor giữ draft; report bài đã xóa; chat snapshot immutable, lazy transcript, selective rebuild, stream/stop/error/clear, trial auth và scroll policy.
- `test/widget_test.dart`: Guest → Member → Admin → Guest.
- `integration_test/app_flow_test.dart`: actual Android flow cho trial/sign-in, publish/vote/comment/Back, member AI, pantry/BMI isolation, comment draft validation, owner-delete report reconciliation, admin moderation/AI override, chart/table, dark mode và sign out. Screenshot chỉ để xem thủ công, không phải golden comparison tự động.

Kết quả thực thi và cây thư mục source đầy đủ được ghi ở [docs/verification.md](docs/verification.md) và [docs/source-tree.md](docs/source-tree.md).

## Thay mock bằng backend

1. Implement interfaces trong `domain/repositories/`; thêm DTO mapping/datasources ở `data/` của feature đó. Không gọi HTTP trong View hoặc tự khởi tạo repository trong ViewModel.
2. Đổi dependency bindings ở `bootstrap.dart`. `core/network/backend_config.dart` chứa `API_BASE_URL` như một cấu hình seam, **hiện chưa được sử dụng để kết nối**.
3. Thay auth demo bằng session/token lifecycle thật. Backend phải kiểm tra quyền cho mọi mutation; đặt trial quota ở server để chống reset/reinstall.
4. Chat gọi backend của bạn; backend giữ API keys và áp dụng giới hạn, timeout, moderation, streaming protocol. Tuyệt đối không nhúng LLM secret trong Flutter app.
5. Thêm persistence, đồng bộ/offline policy và repository error types. Repo hiện là đồng bộ ngoại trừ response stream, nên API backend bất đồng bộ cũng cần cập nhật command signatures và loading/error flows tương ứng.
6. Thay schematic map/dummy coordinates bằng permission flow và map/GPS provider; thay mock video bằng upload/player có URL, trạng thái tải và lifecycle thật.
7. Trước phát hành: auth/server security, chính sách dữ liệu và nội dung, signing, app icons thương hiệu, monitoring, API tests, offline/network tests, iOS/device QA và accessibility audit thực tế.

## Giới hạn có chủ đích

- Không gọi LLM, backend, GPS, map SDK, video server hay gửi notification/email. Listings, ratings, telemetry và review confidence là dữ liệu mẫu.
- Không có lưu trữ sau restart, tài khoản thực hay đảm bảo an ninh production. BE/FE/.qodo sẵn có trong workspace không được sửa hoặc tích hợp bởi frontend này.
- BMI dành cho người xác nhận từ 20 tuổi; chỉ là tham chiếu kg/m², không chẩn đoán, không kê khẩu phần hay giảm cân.
- Planner dùng xếp hạng khớp pantry và xoay vòng bộ món seed, không bảo đảm chỉ dùng pantry, đủ dinh dưỡng hoặc an toàn dị ứng. Checklist không tính định lượng.
- Trợ lý trả lời bằng rule/keyword demo, không cá nhân hóa lâm sàng. Thông tin dinh dưỡng không thay thế tư vấn của chuyên gia.
- Web build dùng Flutter engine/font resources; nội dung seed/artwork không gọi mạng, nhưng việc khởi động web offline còn phụ thuộc cache/hosting tài nguyên engine. Không tuyên bố đây là offline PWA đã kiểm chứng.
- Platform scaffold còn icon Flutter mặc định; tên hiển thị đã đổi thành VeganLife. Không có deployment, remote repository hay release signing được tạo.
