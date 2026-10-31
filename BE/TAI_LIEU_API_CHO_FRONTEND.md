# 📱 TÀI LIỆU API BACKEND VEGANLIFE DÀNH CHO FRONTEND (FLUTTER)

> **Hệ thống**: VeganLife Backend (.NET 9 Clean Architecture + MongoDB + Google Gemini AI)  
> **Dành cho**: Đội ngũ phát triển Frontend (Flutter Mobile & Web Admin)  
> **Base URL**:
> - Máy thật hoặc Web: `http://localhost:5001/api/v1` (hoặc `http://localhost:7211/api/v1`)
> - Android Emulator: `http://10.0.2.2:5001/api/v1`
> - Swagger UI: `http://localhost:5001/swagger`

---

## 📌 MỤC LỤC
1. [Quy Chuẩn Chung & Cơ Chế Hoạt Động](#1-quy-chuẩn-chung--cơ-chế-hoạt-động)
2. [Module 1: Xác Thực & Tài Khoản (`/auth`, `/users`)](#2-module-1-xác-thực--tài-khoản-auth-users)
3. [Module 2: Hồ Sơ Sức Khỏe & Thể Trạng (`/health-profile`, `/catalog`)](#3-module-2-hồ-sơ-sức-khỏe--thể-trạng-health-profile-catalog)
4. [Module 3: Quản Lý Nguyên Liệu & Tủ Lạnh (`/catalog/ingredients`, `/pantry`)](#4-module-3-quản-lý-nguyên-liệu--tủ-lạnh-catalogingredients-pantry)
5. [Module 4: Thực Đơn Tuần & Gợi Ý Món Ăn (`/meal-plans`, `/recipes`)](#5-module-4-thực-đơn-tuần--gợi-ý-món-ăn-meal-plans-recipes)
6. [Module 5: Gemini AI Quét Ảnh Tủ Lạnh (`/vision/scan`)](#6-module-5-gemini-ai-quét-ảnh-tủ-lạnh-visionscan)
7. [Module 6: Tải Lên Đa Phương Tiện Ảnh & Video (`/media`)](#7-module-6-tải-lên-đa-phương-tiện-ảnh--video-media)
8. [Module 7: Bảng Tin Cộng Đồng & Bình Luận (`/posts`, `/comments`)](#8-module-7-bảng-tin-cộng-đồng--bình-luận-posts-comments)
9. [Bảng Tra Cứu Mã Lỗi HTTP & Cách Xử Lý](#9-bảng-tra-cứu-mã-lỗi-http--cách-xử-lý)

---

## 1. QUY CHUẨN CHUNG & CƠ CHẾ HOẠT ĐỘNG

### 1.1. Cấu trúc phản hồi chuẩn (`ApiResponse<T>`)
Mọi phản hồi từ Backend (thành công hoặc thất bại) đều được đóng gói theo định dạng chuẩn:
```json
{
  "success": true,
  "message": "Thông điệp thông báo từ máy chủ (hoặc null)",
  "statusCode": 200,
  "data": { ... }
}
```
* Phía Flutter, hàm `unwrapEnvelope()` trong `lib/core/network/api_envelope.dart` sẽ **tự động bóc tách và lấy trường `data`** khi `success == true`.
* Khi `success == false`, `DioClient` sẽ tự động ném ra `ApiException` chứa mã lỗi và thông báo để hiển thị SnackBar/Dialog cho người dùng.

### 1.2. Cơ chế Xác thực (Authentication)
* Các API yêu cầu quyền đăng nhập (`[Authorize]`) cần gửi kèm Header:
  ```http
  Authorization: Bearer <accessToken>
  ```
* Các API cho phép xem tự do (`[AllowAnonymous]`) vẫn có thể gửi kèm Token nếu người dùng đã đăng nhập; khi đó Backend sẽ nhận diện được danh tính (ví dụ: trả về cờ `likedByMe: true` trong bài viết).

---

## 2. MODULE 1: XÁC THỰC & TÀI KHOẢN (`/auth`, `/users`)

### 2.1. Đăng nhập (`POST /api/v1/auth/login`)
* **Mục đích**: Người dùng đăng nhập bằng Email và Mật khẩu.
* **Headers**: `Content-Type: application/json`
* **Request Body**:
```json
{
  "email": "minhanh.nguyen@gmail.com",
  "password": "Password123!"
}
```
* **API Cấp Gì Cho FE**:
  - `accessToken`: Chuỗi JWT Token dùng để gắn vào Header các request sau.
  - `refreshToken`: Token làm mới phiên khi accessToken hết hạn.
  - `expiresAt`: Thời điểm hết hạn của Token (UTC).
  - `user`: Thông tin cơ bản (`id`, `email`, `fullName`, `role`: `User`/`Chef`/`Admin`, `avatarUrl`, `phone`).
* **Cách FE Sử Dụng**:
  - Lưu `accessToken` và `refreshToken` vào `flutter_secure_storage`.
  - Lưu `role` và `userId` vào `UserNotifier` / Riverpod state để phân quyền giao diện (User thường hay Chef).
  - Điều hướng sang màn hình Trang chủ (Home) hoặc Onboarding (nếu là user mới).

---

### 2.2. Đăng ký tài khoản (`POST /api/v1/auth/register`)
* **Mục đích**: Người dùng đăng ký tài khoản mới (mặc định phân quyền `User`).
* **Request Body**:
```json
{
  "fullName": "Nguyễn Văn A",
  "email": "nguyenvana@gmail.com",
  "password": "Password123!",
  "phone": "0912345678"
}
```
* **API Cấp Gì Cho FE**: Cấu trúc trả về giống hệt `POST /auth/login` (tự động đăng nhập luôn sau khi đăng ký thành công).
* **Cách FE Sử Dụng**: Lưu token và đưa thẳng người dùng vào màn hình **Thiết lập hồ sơ sức khỏe ban đầu (Health Onboarding)**.

---

### 2.3. Quên và đặt lại mật khẩu
1. `POST /api/v1/auth/forgot-password`: Gửi `{ "email": "..." }`. Luôn trả về HTTP `204 No Content` (đảm bảo bảo mật không làm lộ email có tồn tại hay không).
2. `POST /api/v1/auth/verify-reset-code`: Gửi `{ "email": "...", "code": "123456" }`. Trả về `resetToken`.
3. `POST /api/v1/auth/reset-password`: Gửi `{ "resetToken": "...", "newPassword": "..." }`. Đặt lại mật khẩu thành công (HTTP 204).

---

### 2.4. Lấy thông tin tài khoản đang đăng nhập (`GET /api/v1/users/me`)
* **Headers**: `Authorization: Bearer <accessToken>`
* **API Cấp Gì Cho FE**: Chi tiết thông tin cá nhân: `id`, `email`, `fullName`, `phone`, `role`, `avatarUrl`, `isActive`, `createdAt`.
* **Cách FE Sử Dụng**: Hiển thị ở màn hình **Profile / Cá nhân**, kiểm tra trạng thái tài khoản.

---

## 3. MODULE 2: HỒ SƠ SỨC KHỎE & THỂ TRẠNG (`/health-profile`, `/catalog`)

### 3.1. Lấy danh mục dị ứng chuẩn (`GET /api/v1/catalog/allergens`)
* **Headers**: Không cần Token (Public)
* **API Cấp Gì Cho FE**: Danh sách 7 nhóm dị ứng chuẩn được hệ thống hỗ trợ:
```json
[
  { "id": "peanut", "name": "Đậu phộng (Lạc)" },
  { "id": "tree_nut", "name": "Hạt cây (Hạt điều, óc chó, hạnh nhân...)" },
  { "id": "soy", "name": "Đậu nành (Đậu tương)" },
  { "id": "gluten", "name": "Gluten (Lúa mì, lúa mạch)" },
  { "id": "sesame", "name": "Mè (Vừng)" },
  { "id": "mustard", "name": "Mù tạt" },
  { "id": "celery", "name": "Cần tây" }
]
```
* **Cách FE Sử Dụng**: Render danh sách các Filter Chip (nút chọn) trên màn hình thiết lập dị ứng để người dùng chạm chọn.

---

### 3.2. Lấy hồ sơ sức khỏe của tôi (`GET /api/v1/health-profile/me`)
* **Headers**: `Authorization: Bearer <accessToken>`
* **API Cấp Gì Cho FE**:
  - `gender`: `"male"` | `"female"`
  - `heightCm`, `weightKg`: Chiều cao, cân nặng hiện tại.
  - `bmi`: Chỉ số khối cơ thể (ví dụ: `22.45`).
  - `bmiCategory`: Đánh giá thể trạng (`"Bình thường"`, `"Thiếu cân"`, `"Thừa cân"`, `"Béo phì"`).
  - `bmr`: Năng lượng chuyển hóa cơ bản (kcal/ngày).
  - `tdee`: Tổng tiêu hao năng lượng hàng ngày dựa trên mức độ vận động.
  - `targetCalories`: **Calo mục tiêu mỗi ngày** (đã cộng/trừ theo mục tiêu giảm cân/tăng cơ/duy trì).
  - `allergies`: Mảng các mã dị ứng mà người dùng mắc phải (`["soy", "peanut"]`).
  - `mealPattern`: Các bữa ăn trong ngày (`["breakfast", "lunch", "dinner", "snack_pm"]`).
  - `dietaryRestrictions`: Chế độ ăn kiêng bổ sung (`"low_sodium"`, `"low_sugar"`, v.v.).
* **Cách FE Sử Dụng**:
  - Nếu API trả về `404 Not Found`: FE nhận diện tài khoản chưa tạo hồ sơ ➔ Chuyển hướng sang màn hình **Onboarding**.
  - Nếu `200 OK`: Hiển thị thanh tiến trình calo hàng ngày, các chỉ số BMI/BMR trên Dashboard.

---

### 3.3. Tạo mới hoặc cập nhật hồ sơ sức khỏe (`PUT /api/v1/health-profile/me`)
* **Mục đích**: Người dùng cập nhật cân nặng, mục tiêu hoặc thay đổi danh sách dị ứng.
* **Request Body**:
```json
{
  "gender": "male",
  "dob": "1998-05-15T00:00:00Z",
  "heightCm": 175,
  "weightKg": 70.5,
  "activityLevel": "moderately_active",
  "goal": "weight_loss",
  "allergies": ["peanut"],
  "mealPattern": ["breakfast", "lunch", "dinner", "snack_pm"],
  "dietaryRestrictions": ["low_sugar"]
}
```
* **API Cấp Gì Cho FE**: Toàn bộ hồ sơ đã được Backend tự động tính toán lại BMI, BMR, TDEE, Calo mục tiêu chuẩn xác 100%.
* **Đặc biệt**: Backend tự động ghi nhận cân nặng mới vào bảng lịch sử theo dõi tiến trình!

---

### 3.4. Lấy lịch sử biến thiên cân nặng (`GET /api/v1/health-profile/me/metrics?limit=30`)
* **API Cấp Gì Cho FE**: Danh sách các mốc cân nặng theo thời gian:
```json
[
  { "weightKg": 72.0, "loggedAt": "2026-10-01T08:00:00Z" },
  { "weightKg": 70.5, "loggedAt": "2026-10-29T08:00:00Z" }
]
```
* **Cách FE Sử Dụng**: Cung cấp dữ liệu vẽ biểu đồ đường (Line Chart) biểu diễn tiến trình giảm cân/tăng cân trên màn hình Health Tracking.

---

## 4. MODULE 3: QUẢN LÝ NGUYÊN LIỆU & TỦ LẠNH (`/catalog/ingredients`, `/pantry`)

### 4.1. Tìm kiếm nguyên liệu chuẩn (`GET /api/v1/catalog/ingredients`)
* **Tham số Query**: `?q=dau hu&veganOnly=true` (tìm kiếm thông minh không phân biệt dấu và chữ hoa/thường).
* **API Cấp Gì Cho FE**: Danh sách nguyên liệu trong từ điển chuẩn:
  - `id`: Mã định danh nguyên liệu.
  - `name`: Tên tiếng Việt chính xác (ví dụ: "Đậu hũ").
  - `category`: `"plant_protein"`, `"vegetable"`, `"grain"`, `"fruit"`, `"mushroom"`, `"nut_seed"`.
  - `caloriesPer100g`, `proteinG`, `carbsG`, `fatG`, `fiberG`: Thành phần dinh dưỡng trên 100g.
  - `allergies`: Mã chất dị ứng liên quan (ví dụ: `["soy"]`).
  - `isVegan`: Cờ xác nhận thuần chay (`true`).
  - `aliases`: Các tên gọi khác (ví dụ: `["tàu hũ", "tofu", "đậu phụ"]`).
* **Cách FE Sử Dụng**: Hiển thị trong ô tìm kiếm Auto-Complete khi người dùng gõ tên nguyên liệu muốn thêm vào tủ lạnh.

---

### 4.2. Lấy danh sách nguyên liệu trong tủ lạnh (`GET /api/v1/pantry`)
* **Headers**: `Authorization: Bearer <accessToken>`
* **Tham số Query**: `?expiringInDays=3` (tùy chọn: lọc những món sắp hết hạn trong X ngày tới).
* **API Cấp Gì Cho FE**: Mảng các nguyên liệu trong tủ lạnh:
  - `id`: Mã bản ghi trong tủ lạnh.
  - `ingredient`: Tên nguyên liệu.
  - `quantity`: Số lượng (ví dụ: `300.0`).
  - `unit`: Đơn vị (`"g"`, `"ml"`, `"piece"`, `"kg"`).
  - `expiryDate`: Ngày hết hạn.
  - `location`: Vị trí (`"fridge"` - ngăn mát, `"freezer"` - ngăn đông, `"pantry"` - tủ đồ khô).
  - `hasAllergyWarning`: `true`/`false`.
  - `allergyWarningNote`: Thông báo nếu nguyên liệu xung đột với hồ sơ dị ứng của người dùng.
* **Cách FE Sử Dụng**: Render màn hình **"Nguyên liệu trong tủ" (Pantry Screen)**, tô màu đỏ cảnh báo nếu sắp hết hạn hoặc xung đột dị ứng.

---

### 4.3. Thêm nguyên liệu vào tủ lạnh (`POST /api/v1/pantry`)
* **Hỗ trợ 2 kiểu Request Body linh hoạt**:
  - Dạng đơn lẻ:
    ```json
    {
      "ingredient": "Đậu hũ",
      "quantity": 200,
      "unit": "g",
      "expiryDate": "2026-11-05T00:00:00Z",
      "location": "fridge"
    }
    ```
  - Dạng danh sách (`batch` - hỗ trợ thêm nhanh nhiều món sau khi quét ảnh):
    ```json
    {
      "items": [
        { "ingredient": "Cà chua", "quantity": 300, "unit": "g" },
        { "ingredient": "Nấm rơm", "quantity": 150, "unit": "g" }
      ]
    }
    ```
* **Đặc tính thông minh của Backend**:
  - Nếu nguyên liệu đã có sẵn trong tủ, Backend **tự động cộng dồn số lượng** (không sinh bản ghi trùng rác).
  - Tự động đối soát dị ứng của người dùng và gán cờ `hasAllergyWarning` ngay lập tức.

---

### 4.4. Cập nhật và Xóa nguyên liệu trong tủ
* `PUT /api/v1/pantry/{id}`: Sửa số lượng, đơn vị, vị trí lưu trữ hoặc hạn dùng.
* `DELETE /api/v1/pantry/{id}`: Xóa một món đã ăn hết khỏi tủ lạnh.

---

## 5. MODULE 4: THỰC ĐƠN TUẦN & GỢI Ý MÓN ĂN (`/meal-plans`, `/recipes`)

### 5.1. Lấy thực đơn tuần hiện tại (`GET /api/v1/meal-plans/current`)
* **API Cấp Gì Cho FE**:
  - `id`: ID thực đơn tuần.
  - `startDate`: Ngày bắt đầu tuần (Thứ Hai, theo múi giờ Việt Nam UTC+7).
  - `dailyTargets`: Calo và macro mục tiêu hàng ngày (`calories`, `proteinG`, `carbsG`, `fatG`, `fiberG`).
  - `days`: Mảng 7 ngày trong tuần. Mỗi ngày gồm `date`, `totalCalories` của ngày và các slot bữa ăn:
    ```json
    "meals": {
      "breakfast": { "recipeId": "...", "name": "Phở chay nấm", "calories": 420, "prepMinutes": 20 },
      "lunch": { "recipeId": "...", "name": "Cơm chiên hạt sen", "calories": 550, "prepMinutes": 25 },
      "dinner": { "recipeId": "...", "name": "Canh chua đậu hũ", "calories": 380, "prepMinutes": 20 },
      "snack_pm": { "recipeId": "...", "name": "Sinh tố bơ chuối", "calories": 210, "prepMinutes": 5 }
    }
    ```
* **Cách FE Sử Dụng**: Render màn hình **Thực Đơn Tuần (Meal Planner Screen)** theo từng Tab ngày trong tuần.

---

### 5.2. Tự động sinh thực đơn tuần LỌC SẠCH DỊ ỨNG (`POST /api/v1/meal-plans/generate`)
* **Mục đích**: Người dùng bấm nút "Nhờ AI lên thực đơn tuần".
* **Request Body**:
```json
{
  "startDate": "2026-11-02",
  "goal": "weight_loss",
  "usePantry": false
}
```
* **Cam kết kỹ thuật của Backend**:
  - Các món được xếp vào 7 ngày **TUYỆT ĐỐI KHÔNG CHỨA DỊ ỨNG** của người dùng (chặn dị ứng từ gốc ở tầng thuật toán).
  - Tổng calo mỗi ngày cân đối quanh mức calo mục tiêu thể trạng (±10%).
  - Đảm bảo đủ các slot bữa ăn theo `mealPattern` đã cài đặt trong hồ sơ.

---

### 5.3. Gợi ý 10 món nấu từ nguyên liệu trong tủ lạnh (`POST /api/v1/meal-plans/from-ingredients`)
* **Mục đích**: Sau khi người dùng mở tủ lạnh chụp ảnh hoặc chọn các nguyên liệu đang có, hệ thống sẽ đề xuất các món ăn có thể nấu được ngay.
* **Request Body**:
```json
{
  "ingredients": [
    { "name": "Bông cải xanh" },
    { "name": "Đậu hũ" },
    { "name": "Cà rốt" }
  ],
  "excludeAllergens": ["peanut"]
}
```
* **API Cấp Gì Cho FE**: Mảng 10 món ăn thuần chay điểm cao nhất:
  - `id`, `name`, `calories`, `prepMinutes`.
  - `usedIngredients`: Các nguyên liệu trong tủ người dùng đã có sẵn cho món này.
  - `missingIngredients`: Các nguyên liệu cần mua thêm (nếu có).
  - `allergens`: Danh sách chất dị ứng có trong món.
* **Cách FE Sử Dụng**: Hiển thị thẻ món ăn kèm thanh đo tỷ lệ % nguyên liệu đã có (ví dụ: *"Có sẵn 3/4 nguyên liệu"*).

---

### 5.4. Đổi món và Gợi ý món thay thế
* `GET /api/v1/meal-plans/{id}/swap-suggestions?date=2026-11-02&slot=lunch&limit=3`:
  - Cấp danh sách 3 đến 5 món ăn cùng loại bữa trưa, chênh lệch calo không quá 15%, không chứa dị ứng để người dùng lựa chọn đổi.
* `PATCH /api/v1/meal-plans/{id}/meals`:
  - Request: `{ "date": "2026-11-02", "slot": "lunch", "recipeId": "b3" }`.
  - Đổi món mới vào ô đó và tự động cập nhật lại tổng calo ngày.
* `POST /api/v1/meal-plans/current/meals/batch`:
  - Áp dụng hàng loạt món từ thực đơn mẫu của Chuyên gia vào tuần hiện tại chỉ bằng 1 thao tác bấm.
* `DELETE /api/v1/meal-plans/{id}/meals?date=2026-11-02&slot=snack_pm`:
  - Đặt ô bữa ăn đó về rỗng (nếu người dùng hôm đó không ăn bữa phụ).

---

### 5.5. Quản lý công thức cá nhân ("Món của tôi")
* `GET /api/v1/users/me/recipes` (hoặc `GET /api/v1/recipes`): Lấy danh sách các công thức do chính người dùng tự tạo.
* `POST /api/v1/recipes`: Tạo một công thức nấu ăn mới gồm calo, dinh dưỡng, các bước nấu và nguyên liệu.

---

## 6. MODULE 5: GEMINI AI QUÉT ẢNH TỦ LẠNH (`/vision/scan`)

### Endpoint: `POST /api/v1/vision/scan`
* **Mục đích**: Người dùng chụp ảnh trực tiếp tủ lạnh bằng camera điện thoại, hệ thống AI tự động phát hiện tất cả thực phẩm nhìn thấy được, phân loại thuần chay, vẽ hộp định vị Bounding Box và đưa ra phương án thay thế nếu phát hiện đồ không thuần chay.
* **Headers**:
  - `Authorization: Bearer <accessToken>` (khuyến nghị để kiểm tra dị ứng người dùng)
  - `Content-Type: multipart/form-data`
* **Form-Data**:
  - `image`: File ảnh (JPEG, PNG, WEBP, tối đa 10 MB).

#### API Cấp Gì Cho FE:
```json
{
  "success": true,
  "message": "Quét nhận diện thực phẩm thành công.",
  "statusCode": 200,
  "data": {
    "scanId": "scn_8f3a1b2c",
    "items": [
      {
        "id": "det_1",
        "label": "Bông cải xanh",
        "confidence": 0.96,
        "isVegan": true,
        "nonVeganReason": null,
        "veganAlternatives": [],
        "bbox": {
          "x": 0.06,
          "y": 0.18,
          "w": 0.30,
          "h": 0.22
        },
        "alternatives": [
          { "label": "Súp lơ", "confidence": 0.03, "isVegan": true }
        ]
      },
      {
        "id": "det_2",
        "label": "Trứng gà",
        "confidence": 0.94,
        "isVegan": false,
        "nonVeganReason": "Có nguồn gốc động vật: trứng gia cầm",
        "veganAlternatives": [
          "Đậu hũ non",
          "Bột hạt lanh (pha nước)"
        ],
        "bbox": {
          "x": 0.05,
          "y": 0.43,
          "w": 0.36,
          "h": 0.12
        },
        "alternatives": []
      }
    ]
  }
}
```

#### Cách FE Sử Dụng:
1. **Render Bounding Box lên Camera Preview**:
   - Đối tượng `bbox` (`x`, `y`, `w`, `h`) đã được chuẩn hóa về hệ số `0.0..1.0`.
   - FE chỉ cần nhân tọa độ với kích thước màn hình:
     - `Left = x * screenWidth`
     - `Top = y * screenHeight`
     - `Width = w * screenWidth`
     - `Height = h * screenHeight`
   - Tô viền xanh lá cây cho món `isVegan: true` và viền đỏ cam cho món `isVegan: false`.
2. **Cảnh báo không thuần chay**:
   - Với các món `isVegan: false`, hiển thị nhãn lý do (`nonVeganReason`) và danh sách món thuần chay thay thế tương đương (`veganAlternatives`).
3. **Thêm vào tủ lạnh**:
   - Màn hình hiển thị danh sách các món tìm thấy kèm ô tích chọn. Sau khi người dùng xác nhận, FE gọi `POST /api/v1/pantry` (dạng batch `{ items: [...] }`) để lưu vào tủ lạnh.
4. **Cơ chế Smart Mock Fallback**:
   - Ngay cả khi backend chạy môi trường dev chưa nạp key Gemini thật, API vẫn trả về dữ liệu mẫu thực tế để FE thoải mái test UI mà không bao giờ bị lỗi kết nối!

---

## 7. MODULE 6: TẢI LÊN ĐA PHƯƠNG TIỆN ẢNH & VIDEO (`/media`)

### 7.1. Tải ảnh lên (`POST /api/v1/media/images`)
* **Headers**: `Authorization: Bearer <accessToken>`, `Content-Type: multipart/form-data`
* **Form-Data**: `file` (ảnh JPG, PNG, WEBP, HEIC; tối đa 10 MB).
* **API Cấp Gì Cho FE**:
```json
{
  "publicId": "veganlife/images/8301de93fdde4195aab9368dce5376fc",
  "url": "https://res.cloudinary.com/.../8301de93fdde4195aab9368dce5376fc.jpg",
  "width": 1080,
  "height": 1920,
  "sizeBytes": 452100
}
```
* **Cách FE Sử Dụng**: Lấy đường link `url` gán vào bài đăng hoặc đổi ảnh đại diện cá nhân.

---

### 7.2. Tải video ngắn lên (`POST /api/v1/media/videos`)
* **Headers**: `Authorization: Bearer <accessToken>`, `Content-Type: multipart/form-data`
* **Form-Data**: `file` (video MP4, MOV, WEBM; tối đa 100 MB).
* **API Cấp Gì Cho FE**: `url` video phát trực tiếp, `thumbnailUrl` (ảnh bìa video) và `durationSeconds`.

---

## 8. MODULE 7: BẢNG TIN CỘNG ĐỒNG & BÌNH LUẬN (`/posts`, `/comments`)

### 8.1. Lấy bảng tin cộng đồng (`GET /api/v1/posts`)
* **Query Params**:
  - `page`: Số trang (mặc định 1).
  - `pageSize`: Số bài mỗi trang (mặc định 10).
  - `type`: Lọc theo chủ đề bài viết.
  - `mediaType`: `"Image"` hoặc `"Video"` (để lọc riêng Reels/Video).
* **API Cấp Gì Cho FE**:
  - `items`: Danh sách bài viết đã kiểm duyệt (`Published`):
    - `id`: Mã bài viết.
    - `author`: Thông tin người đăng (`id`, `fullName`, `avatarUrl`, `role`).
    - `title`, `body`, `tags`.
    - `mediaType`: `"Text"`, `"Image"`, `"Video"`.
    - `mediaUrl`: Đường dẫn ảnh hoặc video.
    - `likeCount`, `commentCount`.
    - `likedByMe`: `true`/`false` (cho biết user hiện tại đã thả tim bài này chưa).
    - `createdAt`: Thời gian đăng.
  - `totalItems`, `totalPages`, `currentPage`.
* **Cách FE Sử Dụng**: Render danh sách Feed cuộn vô tận (Infinite Scroll), hiển thị trái tim đỏ khi `likedByMe == true`.

---

### 8.2. Đăng bài viết mới (`POST /api/v1/posts`)
* **Headers**: `Authorization: Bearer <accessToken>`
* **Request Body**:
```json
{
  "title": "Phở chay thanh đạm cuối tuần",
  "body": "Nước dùng ngọt từ củ cải và lê, ăn kèm nấm đùi gà áp chảo rất ngon!",
  "type": "RecipeShare",
  "tags": ["pho_chay", "mon_nuoc", "thanh_dam"],
  "mediaType": "Image",
  "mediaUrl": "https://res.cloudinary.com/.../8301de93fdde4195aab9368dce5376fc.jpg",
  "restaurantId": null
}
```
* **Lưu ý**: Trường `restaurantId` nếu không có hãy truyền `null` (không truyền chuỗi `"string"` của Swagger).

---

### 8.3. Thả tim / Bỏ thả tim bài viết (`POST /api/v1/posts/{id}/like`)
* **Mục đích**: Toggle Like.
* **API Cấp Gì Cho FE**:
```json
{
  "liked": true,
  "likeCount": 15
}
```
* **Cách FE Sử Dụng**: Cập nhật ngay biểu tượng trái tim và số đếm like trên màn hình mà không cần tải lại cả trang feed.

---

### 8.4. Bình luận bài viết (`/posts/{id}/comments`)
* `GET /api/v1/posts/{id}/comments?page=1&pageSize=10`:
  - Cấp danh sách bình luận gốc kèm tối đa 2 câu phản hồi con đầu tiên (`previewReplies`) và `replyCount`.
* `POST /api/v1/posts/{id}/comments`:
  - Request: `{ "content": "Món này nhìn ngon quá!", "parentId": null }` (nếu trả lời bình luận khác thì điền `parentId` là id của bình luận gốc).
* `DELETE /api/v1/comments/{id}`:
  - Xóa bình luận (chỉ tác giả bình luận hoặc Admin mới có quyền xóa).

---

## 9. BẢNG TRA CỨU MÃ LỖI HTTP & CÁCH XỬ LÝ TRÊN FRONTEND

| Mã HTTP | Ý nghĩa | Khi nào xảy ra? | Cách FE xử lý |
|:---:|---|---|---|
| **`200 OK`** | Thành công | Mọi truy vấn GET hoặc xử lý thành công | Đọc dữ liệu từ trường `data`. |
| **`201 Created`**| Tạo mới thành công | Đăng ký, tạo bài viết, tạo món ăn | Thông báo tạo thành công và làm mới danh sách. |
| **`400 Bad Request`** | Dữ liệu không hợp lệ | Thiếu trường bắt buộc, dữ liệu thể trạng ngoài ngưỡng | Hiển thị thông điệp từ trường `message` lên Form/Dialog. |
| **`401 Unauthorized`**| Chưa đăng nhập / Hết hạn | Token hết hạn hoặc không truyền header Authorization | Chuyển hướng người dùng về màn hình **Đăng nhập**. |
| **`403 Forbidden`** | Không có quyền | User thường cố gắng xóa bài viết của người khác | Báo lỗi "Bạn không có quyền thực hiện thao tác này". |
| **`404 Not Found`** | Không tìm thấy | ID không tồn tại hoặc tài khoản chưa có HealthProfile | Nếu ở `/health-profile/me` ➔ Chuyển hướng sang Onboarding. |
| **`409 Conflict`** | Xung đột dữ liệu | Báo cáo trùng bài viết, email đã tồn tại | Thông báo cho người dùng hành động đã được thực hiện trước đó. |
| **`413 Payload Too Large`** | Quá dung lượng | Ảnh > 10 MB hoặc Video > 100 MB | Yêu cầu người dùng chọn file nhỏ hơn hoặc nén file trước khi gửi. |
| **`415 Unsupported Media`** | Sai định dạng tệp | Tải lên file không phải ảnh/video cho phép | Báo lỗi định dạng tệp không được hỗ trợ. |
| **`429 Too Many Requests`** | Quá giới hạn tần suất | Quét tủ lạnh quá 10 lần/phút | Hiển thị: "Bạn đang thao tác quá nhanh. Vui lòng chờ 1 phút." |
| **`500 Internal Error`** | Lỗi máy chủ | Lỗi DB hoặc ngoại lệ chưa bắt | Hiển thị: "Đã xảy ra lỗi, vui lòng thử lại sau ít phút." |

---
## 10. CÁC ĐIỂM CẬP NHẬT MỚI NHẤT (BACKEND V4 & TOÀN BỘ 34 BUGS + 3 MISSING ITEMS)

### 10.1. Xác thực & Tài khoản Mẫu (Dev)
* **3 tài khoản mẫu mặc định (môi trường Development)**:
  - Admin: `admin@veganlife.vn` / `Password123!`
  - Chef: `chef.hoang@veganlife.vn` / `Password123!`
  - Member: `minhanh.nguyen@gmail.com` / `Password123!`
* **Admin Login**: `POST /api/v1/auth/admin/login` dành riêng cho Web Admin (chỉ chấp nhận vai trò Admin).
* **Refresh Token Rotation**: `POST /api/v1/auth/refresh` với `{ "refreshToken": "..." }` (đổi token mới và thu hồi token cũ).
* **Đăng xuất**: `POST /api/v1/auth/logout`.
* **Thống kê User Profile**: `/users/me` trả về `stats.posts` và `stats.likesReceived` tính từ dữ liệu thật.

### 10.2. Hồ sơ Sức khỏe & Catalog
* **Whitelist Mục tiêu (`goal`)**: Hỗ trợ đầy đủ: `lose_weight`, `maintain`, `lean_muscle`, `gain_weight`, `eat_clean`, `gain_muscle`.
* **Cập nhật Hồ sơ**: Cho phép bỏ qua `gender` và `birthYear` khi cập nhật (`PUT /health-profile/me`), Backend sẽ giữ nguyên giá trị đã lưu trước đó.
* **Ghi nhận Chỉ số Cơ thể**: `POST /api/v1/health-profile/me/metrics` nhận `{ "waistCm": 75.5, "bodyFatPct": 18.2, "source": "manual" }`.
* **Tìm kiếm Dị ứng**: `GET /api/v1/catalog/allergens?q=...` hỗ trợ lọc theo từ khóa tiếng Việt không phân biệt dấu/hoa thường.

### 10.3. Tủ lạnh & Nguyên liệu (Pantry)
* **Upsert thông minh (Chống nhân đôi số lượng)**: Quét hoặc thêm lại nguyên liệu cùng tên sẽ cập nhật số lượng mới nhất và `scannedAt`, không tự động nhân đôi (+1) như trước.
* **Phân loại Thuần chay 5 Tầng**: Nhận diện chuẩn xác các thực phẩm có tên chứa từ động vật nhưng là chay (ví dụ: `nấm đùi gà`, `sữa đậu nành`, `bơ đậu phộng`, `bò chay`, `yến mạch` đều là `isVegan: true`). Bắt chính xác từ khóa động vật (`thịt`, `bò`, `cá`, `trứng` -> `isVegan: false`).
* **Cảnh báo Dị ứng Chuẩn**: `AllergyWarning` tự động kích hoạt khi nguyên liệu khớp với dị ứng chuẩn (`peanut`, `soy`, `gluten`...) hoặc từ khóa tự do.

### 10.4. Thực đơn Tuần & Món ăn (MealPlan)
* **Gợi ý Món từ Tủ lạnh (Không ghi DB)**: `POST /api/v1/meal-plans/from-ingredients` trả về danh sách công thức phù hợp mà không làm biến đổi thực đơn đang có.
* **Làm trống Tuần**: `POST /api/v1/meal-plans` gửi `{ "empty": true, "startDate": "YYYY-MM-DD" }` sẽ làm trống toàn bộ các bữa ăn của tuần đã có.
* **Thời gian UTC+7**: Múi giờ Việt Nam được áp dụng chuẩn xác cho ngày Thứ Hai đầu tuần.
* **Bảo mật Quyền sở hữu (IDOR Fix)**: Mọi thao tác xem/sửa/xóa/đổi món đều kiểm tra nghiêm ngặt `UserId`.
* **Lấy chi tiết Món ăn**: `GET /api/v1/recipes/{id}`.
* **Bổ sung trường DTO**: `SwapMealRequestDto` và `AddMealRequestDto` hỗ trợ đầy đủ `Source`, `SourceName`, `Portion`, `ProteinG`, `CarbsG`, `FatG`, `FiberG`, `RecipeId`.

### 10.5. Bảng Tin Cộng Đồng & Quản Trị (Community & Moderation)
* **Cursor Pagination**: API Feed hỗ trợ cả `cursor` và `limit` (`GET /posts?cursor=...&limit=10`), trả `nextCursor` cho trang tiếp theo.
* **Toggle Like Không lỗi trùng khóa**: Thả tim, bỏ tim, thả tim lại an toàn tuyệt đối (tự động khôi phục bản ghi thay vì insert trùng).
* **Đọc Toàn Bộ Phản hồi**: `GET /api/v1/posts/{id}/comments/{commentId}/replies` và `GET /api/v1/comments/{id}/replies` cho phép đọc tất cả các phản hồi từ câu thứ 3 trở đi.
* **Xóa Bình Luận Phân Nhánh**: Xóa bình luận cha sẽ tự động xóa tất cả phản hồi con và giảm `commentCount` chính xác.
* **Thời gian Bình Luận**: Bình luận mới tạo có `updatedAt: null`.
* **Web Admin Kiểm Duyệt Bài Viết**:
  - `POST /api/v1/admin/posts/{id}/review`: `{ "decision": "Approve" | "Reject" }`
  - `POST /api/v1/admin/posts/{id}/actions`: `{ "action": "unhide" | "restore" | "hide" | "delete" }`
  - Khôi phục/duyệt bài tự động đặt lại `reportCount: 0`.
* **Video Media**: Tải lên video local lưu `durationSeconds: null` (không hardcode 15s). Bài viết video không trả trường `aiStatus` giả khi chưa có pipeline AI.

---
*Tài liệu được cập nhật tự động theo phiên bản Backend mới nhất của dự án VeganLife.*

