# VeganLife BE: danh sách lỗi cần sửa

- **Bản BE đã test:** nhánh `main`, commit `fd12bde`, chạy thật với MongoDB.
- **Ngày test:** 31/10/2026.
- **Bên test:** FE (app mobile, web admin và bộ test tích hợp gọi thẳng API).
- **Tổng cộng:** 34 lỗi: 1 chặn, 3 cao, 16 trung bình, 14 thấp.

Mức độ tính theo ảnh hưởng tới người dùng. Cột "Cách sửa" chỉ là đề xuất, bạn cứ chọn cách khác nếu hợp hơn.

**Cách xác nhận:**
- B1–B4, B6–B30 có test ghim trong `FE/Mobile/integration_test_be/be_bug_pins_test.dart`. Test này khẳng định hành vi sai của hôm nay, nên khi bạn sửa xong thì test đó sẽ đỏ và FE biết chỗ nào cần gỡ phần né lỗi.
- B31–B34 thấy khi chạy app trên máy ảo, chưa có test ghim.
- B2 mới xác nhận qua đọc code và test "chưa có route đăng nhập admin"; chưa thử đăng nhập thật vì không có tài khoản admin. B5 xác nhận bằng cách đăng nhập tài khoản mẫu (401), không có test ghim.

## Nên sửa trước

| # | Mức | Lỗi | Cách sửa |
|---|---|---|---|
| B2 | **Chặn web** | Admin không đăng nhập được. `AuthService.LoginAsync` ném Forbidden khi `Role == "Admin"` (comment ghi là chặn đăng nhập qua Mobile), nhưng đây là endpoint login duy nhất nên Web admin cũng bị chặn | Thêm `POST /auth/admin/login` yêu cầu Admin, giữ chặn ở `/auth/login` |
| B4 | Cao, riêng tư | Tạo thực đơn và đổi món dùng cả công thức riêng của người khác. Thực đơn của tài khoản B có món riêng do tài khoản A tạo | Lọc `r.CreatedBy == null \|\| r.CreatedBy == userId` ở cả hai truy vấn |
| B3 | Cao | `AppRoles.AdminOrMember = "Admin,Member"` trong khi người dùng là `User`/`Chef`, nên GET/PUT `/users/{id}` trả 403 với mọi người và không đổi được tên | Đổi thành `"Admin,User,Chef"` **và** kiểm tra `id == sub \|\| Admin`. Chỉ nới vai trò sẽ thành lỗi IDOR, vì service chưa kiểm tra chủ sở hữu |
| B1 | Cao | `POST /api/v1/vision/scan` luôn 500: hai attribute `[Route]` tạo ra cùng một route. FE đang tạm gọi route gốc `/vision/scan` để né | Xoá `[Route("api/v1/[controller]")]`, giữ `api/v1/vision`, sau này bỏ `vision` ở gốc |
| B28 | TB | Like → bỏ like → like lại trả 500. Bỏ like xoá mềm dòng `PostLikes`, chỉ mục duy nhất `PostId_1_UserId_1` từ chối dòng mới (E11000) | Khôi phục dòng đã xoá mềm, hoặc dùng chỉ mục unique partial theo `IsDeleted = false` |
| B18 | TB | Không làm mới được token: `refreshToken` luôn null, không có `/auth/refresh`, JWT sống 60 phút, nên người dùng bị đăng xuất giữa chừng | Làm luồng refresh, hoặc tăng hạn ở dev |
| B5 | TB | Tài khoản mẫu trong tài liệu không tồn tại (đăng nhập 401); `DatabaseSeeder` chỉ tạo nguyên liệu và công thức | Seed một admin, một chef, một thành viên ở Development. Việc này cũng giúp FE test được B2 |

## Mức trung bình

| # | Lỗi | Cách sửa |
|---|---|---|
| B6 | PATCH meals bỏ qua `source`, `portion`; luôn lưu `manual` | Thêm vào `SwapMealRequestDto`, truyền cho `MapToMealSlotItem` |
| B7 | POST meals và meals/batch bỏ macro và `sourceName`; `recipeId` bị bỏ qua (chỉ đọc `sourceId`) | Thêm `ProteinG, CarbsG, FatG, FiberG, SourceName` vào `AddMealRequestDto` |
| B8 | PUT hồ sơ sức khoẻ không cập nhật `dailyTargets`/`goal` của thực đơn hiện tại | Cập nhật thực đơn tuần này trong `UpdateMyHealthProfileAsync` |
| B9 | PUT đặt lại trường bị thiếu: `gender` → Other, `birthYear` → 1998; gửi `null` → 400 tiếng Anh | Cho phép null trong DTO và giữ giá trị đã lưu |
| B10 | `goal` không được kiểm tra: `lose_weight`, `gain_weight`, `weight_loss` âm thầm thành 0 % | Thêm alias trong `GetGoalAdjustment` hoặc từ chối giá trị lạ |
| B11 | Tạo thực đơn bỏ qua `mealPattern`; `snack_am`, `snack_late` không bao giờ có món | Lặp theo `profile.MealPattern` |
| B12 | Ảnh/video tải lên 404 nếu thiếu `wwwroot` lúc khởi động; bản dev trả URL tương đối | Commit `wwwroot/.gitkeep` hoặc tạo thư mục trước `CreateBuilder` |
| B13 | Tủ lạnh lưu thực phẩm không thuần chay với `isVegan: true` | Kiểm tra từ khoá cho tên lạ, hoặc từ chối |
| B14 | `allergyWarning` không bao giờ bật với dị ứng chuẩn (thêm "Đậu phộng" khi dị ứng đậu phộng vẫn null): `FindConflicts` nhận tag rỗng | Truyền `matchedIngredient.Allergens` làm tag |
| B15 | Trả `nextCursor` nhưng bỏ qua `cursor`, `limit` | Làm theo hai tham số này, hoặc thôi trả `nextCursor` |
| B16 | Phản hồi thứ 3 trở đi không đọc được; xoá bình luận gốc để lại phản hồi mồ côi và `commentCount` chỉ giảm 1 | Thêm GET replies; xoá theo cả nhánh |
| B29 | `POST /meal-plans` trả nguyên tuần đang có, bỏ qua `empty`, nên không làm trống được tuần đã có món. FE đang ẩn "Tự lên thực đơn" vì lỗi này | Thêm `empty` vào `CreateMealPlanRequest` và xoá món khi `empty: true`, hoặc thêm endpoint xoá cả tuần |
| B31 | Tuần được tạo thấp hơn mục tiêu nhiều: 1.170–1.430 kcal/ngày so với 1.890 khi 3 bữa. Mới thấy trên một tài khoản, nên cần kiểm tra thêm | Chọn món theo mục tiêu từng bữa |

## Mức thấp

| # | Lỗi | Cách sửa |
|---|---|---|
| B17 | `updatedAt` của bình luận có ngay lúc tạo và khi thêm phản hồi, nên không biết đã sửa hay chưa | Để null tới khi có endpoint sửa |
| B19 | POST `/recipes` bỏ qua `prepMinutes` (20 → 15), đổi `calories: 0` thành 300 | Map `PrepMinutes`; giữ 0 |
| B20 | `/catalog/allergens` bỏ qua `q` | Lọc, hoặc ghi vào tài liệu |
| B21 | Bài video báo `aiStatus: "ready"`, `durationSeconds: 0`, `video.id` = id bài, không có API `/videos` phía sau | Trả `video: null` tới khi có pipeline; dùng `MediaAsset.DurationSeconds` |
| B22 | `stats` của `/users/me` luôn 0; `chefApplication` chỉ `none`/`approved` | Tính số thật |
| B23 | Quên mật khẩu không gửi email: mã nằm trong bộ nhớ và stdout, không giới hạn số lần thử; lỗi là `invalid_code` thô, không có trường `code` | Thêm `code`, thông báo tiếng Việt, giới hạn số lần |
| B24 | "Tuần hiện tại" tính theo UTC, và `/current` trả thực đơn cũ bất kỳ | Dùng Asia/Ho_Chi_Minh; 404 khi tuần này chưa có |
| B25 | Lỗi validation là ProblemDetails, không qua `ValidationFilter` (`[ApiController]` chặn trước) | `SuppressModelStateInvalidFilter = true` |
| B26 | swap-suggestions không kiểm tra thực đơn có tồn tại và thuộc về người gọi không (id sai vẫn 200) | Trả 404 |
| B27 | Ba báo cáo chuyển bài sang `Pending`, không có endpoint admin để khôi phục | Thêm endpoint kiểm duyệt |
| B30 | `swap-suggestions` gợi ý cả món đang có trong bữa đó | Loại `recipeId` hiện tại khỏi kết quả |
| B32 | `POST /media/videos` lưu `DurationSeconds: 15` cho mọi video | Đọc thời lượng thật |
| B33 | Món thêm qua `meals` và `meals/batch` nhận `PrepMinutes: 15` nên hiện "15 phút" không có thật | Giữ null khi không gửi |
| B34 | Tủ lạnh nhận hai dòng cho cùng một nguyên liệu | Gộp theo nguyên liệu, hoặc xác nhận trùng là hợp lệ |

## API app cần mà BE chưa có

- **Công thức:** `GET /recipes/{id}`; nguyên liệu có cấu trúc và `servings` (`Recipe.ingredients` hiện chỉ là `string[]`, nên không chia theo số người hay tính lại calo được); biến thể, đánh giá, ghi chú. `RecipesController` có hai route cấp lớp, nên thêm `[HttpGet("{id}")]` sẽ lộ cả `/users/me/recipes/{id}`: cần tách controller hoặc dùng route tuyệt đối.
- **Sức khoẻ:** `POST /health-profile/me/metrics` với `waistCm`, `bodyFatPct`, `source`.
- **Thực đơn:** `POST /meal-plans/current/adjust` ("Chỉnh thực đơn với AI").
- **Cộng đồng:** sửa bài, lưu bài, `/users/me/posts`, `/users/me/saved-posts`, `/users/me/comments`; sửa bình luận; GET phản hồi của bình luận.
- **Chuyên gia và thanh toán:** `/chef-applications`, chuyên gia, đặt chuyên gia, thanh toán, ví, tài liệu kiến thức.
- **Khác:** tìm kiếm, quán, vị trí, quảng cáo, chatbot, `/videos`.

## Sai trong tài liệu `TAI_LIEU_API_CHO_FRONTEND.md`

- Tài khoản mẫu không tồn tại (B5).
- Dị ứng ghi là chuỗi, trong khi API dùng object `{ allergenId, name }`.
- `/meal-plans/from-ingredients` ghi là trả 10 gợi ý, nhưng thực ra nó **ghi đè cả tuần**. FE không gọi endpoint này.
- Đường dẫn `/vision/scan` (B1).
- Tài liệu kế hoạch BE ghi ngưỡng BMI của WHO, còn code BE dùng chuẩn châu Á – Thái Bình Dương.

## Lưu ý thêm

- `BE/ControllerLayer/appsettings.json` trên `main` đang commit `JwtSettings:SecretKey` và `FranchiseOnboarding:DefaultManagerPassword`. Với dev thì tạm ổn, nhưng khi deploy thật phải thay bằng biến môi trường và đổi giá trị.
- Trang lỗi dev có in lại header `Authorization`, nên đừng dán log lỗi có token lên chỗ công khai.

## Cách chạy bộ test ghim

Bật BE ở `http://localhost:5001`, rồi chạy từ `FE/Mobile/integration_test_be`:

```bash
flutter test . --concurrency=1 --dart-define=USE_MOCK_DATA=false --dart-define=API_BASE_URL=http://localhost:5001/api/v1
```

Bộ test tự tạo tài khoản thử và ghi vào database BE đang dùng, nên hãy chạy với một database riêng (đặt biến môi trường `DatabaseName`).
