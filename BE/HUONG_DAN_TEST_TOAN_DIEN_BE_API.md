# 🚀 BÁO CÁO CÔNG VIỆC ĐÃ HOÀN THÀNH & TÀI LIỆU TEST CASES TOÀN DIỆN BACKEND VEGANLIFE

> **Hệ thống**: VeganLife Backend (.NET 9 Clean Architecture + MongoDB + Google Gemini AI)  
> **Địa chỉ API (Base URL)**: `http://localhost:5001/api/v1` (hoặc `http://localhost:7211/api/v1`)  
> **Swagger UI tương tác**: `http://localhost:5001/swagger`  
> **Tài liệu gốc tham chiếu**: `BE/Kế hoạch backend VeganLifeV2.md` và hợp đồng ứng dụng Mobile Flutter (`FE/Mobile/lib/...`)

---

## 📌 MỤC LỤC
1. [TỔNG KẾT NHỮNG GÌ ĐÃ TRIỂN KHAI VÀ SỬA ĐỔI](#1-tổng-kết-những-gì-đã-triển-khai-và-sửa-đổi)
2. [HƯỚNG DẪN KHỞI ĐỘNG VÀ ĐĂNG NHẬP LẤY TOKEN](#2-hướng-dẫn-khởi-động-và-đăng-nhập-lấy-token)
3. [TEST CASES MODULE 1: HEALTHPROFILE (THỂ TRẠNG, CALO, DỊ ỨNG)](#3-test-cases-module-1-healthprofile-thể-trạng-calo-dị-ứng)
4. [TEST CASES MODULE 2: PANTRY (QUẢN LÝ NGUYÊN LIỆU TỦ LẠNH)](#4-test-cases-module-2-pantry-quản-lý-nguyên-liệu-tủ-lạnh)
5. [TEST CASES MODULE 3: MEALPLAN (THỰC ĐƠN TUẦN 7 NGÀY & GỢI Ý)](#5-test-cases-module-3-mealplan-thực-đơn-tuần-7-ngày--gợi-ý)
6. [TEST CASES MODULE 4: GEMINI VISION SCAN QUÉT TỦ LẠNH (/vision/scan)](#6-test-cases-module-4-gemini-vision-scan-quét-tủ-lạnh-visionscan)
7. [ĐẶC TẢ VÀ TEST CASES MODULE 5: GEMINI CHATBOT RAG (/chat)](#7-đặc-tả-và-test-cases-module-5-gemini-chatbot-rag-chat)
8. [ĐẶC TẢ VÀ TEST CASES MODULE 6: TRÍCH XUẤT CÔNG THỨC TỪ VIDEO NGẮN](#8-đặc-tả-và-test-cases-module-6-trích-xuất-công-thức-từ-video-ngắn)
9. [BẢNG CHECKLIST NGHIỆM THU TỔNG HỢP](#9-bảng-checklist-nghiệm-thu-tổng-hợp)

---

## 1. TỔNG KẾT NHỮNG GÌ ĐÃ TRIỂN KHAI VÀ SỬA ĐỔI

Trong suốt quá trình vừa qua, hệ thống Backend đã được nâng cấp, sửa lỗi và hoàn thiện toàn diện theo tài liệu kế hoạch V2:

### 1.1. Sửa lỗi hệ thống & Tối ưu hạ tầng (Infrastructure Fixes)
1. **Khắc phục lỗi Swagger Swashbuckle v9**:
   - Loại bỏ thuộc tính `[FromForm]` gây xung đột trên các tham số `IFormFile image` và `IFormFile video` tại `MediaController` và `VisionController`. Swagger UI hiển thị đúng nút chọn file mà không ném ngoại lệ `SwaggerGeneratorException`.
2. **CORS & Pipeline Middleware**:
   - Đưa `app.UseCors("MobilePolicy")` lên vị trí đầu tiên của pipeline; bổ sung headers CORS trực tiếp trong `ExceptionHandlingMiddleware` để ngăn chặn lỗi `Failed to fetch` khi có exception.
3. **Kestrel Request Limit & Static File Fallback**:
   - Tăng dung lượng tối đa của Kestrel lên 100 MB (`MaxRequestBodySize = 104_857_600`) cho phép tải video nấu ăn ngắn.
   - Thêm cơ chế Fallback lưu trữ ảnh/video cục bộ vào `wwwroot/uploads/` khi tài khoản Cloudinary chưa được nạp key thật (`dummy_cloud_name`).
4. **Sửa lỗi MongoDB BsonSerializationException / FormatException (500)**:
   - Các trường `RestaurantId` trong `Post` và `ParentId` trong `Comment` được thêm `[BsonIgnoreIfNull]` và được hàm xử lý làm sạch (sanitization) tự động: chuỗi rỗng hoặc giá trị placeholder `"string"` mặc định của Swagger sẽ tự động chuyển thành `null` thay vì gây crash `500 Internal Server Error`.
   - `GenericRepository` được bổ sung chốt chặn `ObjectId.TryParse(id, out _)`.
5. **Git Synchronization**:
   - Đã commit và đồng bộ toàn bộ codebase sạch lên branch `Kiet` và merge fast-forward vào `main` trên GitHub remote.

---

### 1.2. Triển khai các Module nghiệp vụ cốt lõi
1. **HealthProfile**:
   - Tính toán chỉ số thể trạng: BMR (công thức Mifflin-St Jeor), TDEE, Calo mục tiêu và BMI chuẩn xác theo `energy.dart` của Flutter.
   - Danh mục 7 chất dị ứng chuẩn (`peanut`, `tree_nut`, `soy`, `gluten`, `sesame`, `mustard`, `celery`).
   - Lịch sử cân nặng theo dõi tiến trình qua `HealthMetricLogs`.
2. **Pantry & Ingredients**:
   - Quản lý nguyên liệu trong tủ lạnh của người dùng: thêm, sửa, xóa, tìm kiếm không dấu (`AllergyMatcher.NormalizeForSearch`).
   - Tự động cộng dồn số lượng khi nhập trùng nguyên liệu; tự động cảnh báo dị ứng nếu nguyên liệu trong tủ xung đột với hồ sơ sức khỏe.
3. **MealPlan & Recipes**:
   - Tạo thực đơn tuần 7 ngày (tính theo tuần hiện tại UTC+7).
   - Tự động sinh thực đơn AI/Greedy lọc sạch tuyệt đối các món chứa dị ứng của người dùng.
   - Gợi ý món từ nguyên liệu có sẵn trong tủ lạnh (`/from-ingredients`).
   - Gợi ý món thay thế cùng bữa (`/swap-suggestions`), đổi món (`/meals`), gán hàng loạt (`/meals/batch`).
   - Quản lý công thức cá nhân ("Món của tôi").

---

### 1.3. Triển khai Module Gemini AI (`IGeminiClient` & `/vision/scan`)
1. **`IGeminiClient` dùng chung (`GeminiClient.cs`)**:
   - Kết nối trực tiếp Google Gemini REST API qua header `x-goog-api-key` (không lộ trên URL).
   - Cơ chế tự động thử lại (Retry) tối đa 3 lần với exponential backoff khi gặp mã `429` (Too Many Requests) hoặc `503` (Service Unavailable).
   - **Smart Mock Fallback**: Nếu chưa cấu hình `ApiKey` hoặc dùng key giả định, client tự động sinh dữ liệu thực tế (bông cải xanh, đậu hũ, cà chua, trứng gà không thuần chay kèm món thay thế) giúp dev/tester chạy kiểm thử trơn tru mà không cần tốn quota API key. Khi điền API Key thật vào `appsettings.json`, hệ thống lập tức gọi Google Gemini 2.0 Flash thật!
   - Tự động ghi nhật ký gọi AI vào collection `ai_logs` (`TaskType`, `Model`, `InputTokens`, `OutputTokens`, `LatencyMs`, `ScanId`).
2. **API Quét Tủ Lạnh (`POST /api/v1/vision/scan`)**:
   - Tiếp nhận ảnh chụp tủ lạnh qua `multipart/form-data`, trường `image`.
   - Giới hạn kích thước file <= 10 MB, lọc magic bytes.
   - Gọi Gemini nhận diện nhãn tiếng Việt (`label`), độ tự tin (`confidence`), cờ thuần chay (`isVegan`), lý do không thuần chay (`nonVeganReason`), phương án thay thế thuần chay (`veganAlternatives`), và bounding box (`bbox: {x, y, w, h}` chuẩn hóa về `0.0..1.0`).
   - Đối soát nhãn với danh mục `ingredients` trong MongoDB (chuẩn hóa không dấu) để lấy nhãn chay chuẩn từ hệ thống.
   - Kiểm tra xung đột dị ứng với `HealthProfile` của người dùng.
   - Giới hạn tần suất: **10 lần/phút per user** (vượt quá trả HTTP 429).

---

## 2. HƯỚNG DẪN KHỞI ĐỘNG VÀ ĐĂNG NHẬP LẤY TOKEN

### 2.1. Khởi động MongoDB Docker & Backend
1. Đảm bảo MongoDB container đang chạy:
```powershell
docker compose up -d mongodb
```
2. Mở Terminal tại `BE/ControllerLayer` và khởi chạy server:
```powershell
cd e:\Semester_7\PRM392\Project\PRM393\BE\ControllerLayer
dotnet run
```
3. Mở Swagger UI tại trình duyệt: 👉 **`http://localhost:5001/swagger`** (hoặc `http://localhost:7211/swagger`)

### 2.2. Đăng nhập để lấy JWT Token
* **Endpoint**: `POST /api/v1/auth/login`
* **Request Body**:
```json
{
  "email": "minhanh.nguyen@gmail.com",
  "password": "Password123!"
}
```
* **Lấy token**: Sao chép giá trị `accessToken` trong JSON trả về.
* **Gắn token trên Swagger**: Bấm nút **Authorize 🔒** ở góc trên bên phải Swagger UI, dán chuỗi token vào và bấm **Authorize**.

---

## 3. TEST CASES MODULE 1: HEALTHPROFILE (THỂ TRẠNG, CALO, DỊ ỨNG)

### Test Case H1: Lấy danh mục 7 chất dị ứng chuẩn
* **Mục tiêu**: Kiểm tra danh mục dị ứng chuẩn cho hệ thống.
* **Method & Endpoint**: `GET /api/v1/catalog/allergens`
* **Headers**: Không cần Token (Public)
* **Kết quả mong đợi**:
  - `StatusCode`: `200 OK`
  - Body trả về danh sách 7 dị ứng: `peanut`, `tree_nut`, `soy`, `gluten`, `sesame`, `mustard`, `celery` kèm nhãn tiếng Việt.

---

### Test Case H2: Cập nhật hồ sơ sức khỏe & Tính BMR, TDEE, Calo mục tiêu
* **Mục tiêu**: Cập nhật thể trạng Nam (28 tuổi, cao 175cm, nặng 72kg, tập luyện vừa phải, dị ứng đậu nành và đậu phộng).
* **Method & Endpoint**: `PUT /api/v1/health-profile/me`
* **Headers**: `Authorization: Bearer {{Token}}`
* **Request Body**:
```json
{
  "gender": "male",
  "dob": "1998-05-15T00:00:00Z",
  "heightCm": 175,
  "weightKg": 72.0,
  "activityLevel": "moderately_active",
  "goal": "maintenance",
  "allergies": ["soy", "peanut"],
  "mealPattern": ["breakfast", "lunch", "dinner", "snack_pm"],
  "dietaryRestrictions": ["low_sugar"]
}
```
* **Kết quả mong đợi**:
  - `StatusCode`: `200 OK`
  - `Data.bmi`: `23.51` (Thể trạng bình thường)
  - `Data.bmr`: `1686 kcal`
  - `Data.tdee`: `2614 kcal`
  - `Data.targetCalories`: `2614 kcal` (Mục tiêu duy trì cân nặng)
  - `Data.allergies`: Chứa `["soy", "peanut"]`

---

### Test Case H3: Xem lịch sử biến thiên cân nặng
* **Method & Endpoint**: `GET /api/v1/health-profile/me/metrics`
* **Headers**: `Authorization: Bearer {{Token}}`
* **Kết quả mong đợi**: `200 OK`, danh sách bản ghi cân nặng kèm ngày giờ ghi nhận.

---

## 4. TEST CASES MODULE 2: PANTRY (QUẢN LÝ NGUYÊN LIỆU TỦ LẠNH)

### Test Case P1: Tìm kiếm nguyên liệu chuẩn không dấu
* **Method & Endpoint**: `GET /api/v1/catalog/ingredients?q=dau hu`
* **Kết quả mong đợi**: `200 OK`, tìm thấy nguyên liệu `Đậu hũ` (mã dị ứng `["soy"]`, `isVegan: true`).

---

### Test Case P2: Thêm nguyên liệu vào tủ lạnh & Tự động cảnh báo dị ứng
* **Mục tiêu**: Thêm `Đậu hũ` vào tủ của người dùng đã khai báo dị ứng `soy`.
* **Method & Endpoint**: `POST /api/v1/pantry`
* **Headers**: `Authorization: Bearer {{Token}}`
* **Request Body**:
```json
{
  "ingredientName": "Đậu hũ",
  "quantity": 300,
  "unit": "g",
  "expiryDate": "2026-11-05T00:00:00Z",
  "location": "fridge"
}
```
* **Kết quả mong đợi**:
  - `StatusCode`: `201 Created`
  - `Data.hasAllergyWarning`: `true` (Hệ thống tự động phát hiện xung đột dị ứng đậu nành).
  - `Data.allergyWarningNote`: Thông báo cảnh báo dị ứng rõ ràng.

---

### Test Case P3: Thêm trùng món để kiểm tra cộng dồn số lượng
* **Mục tiêu**: Gửi lại request thêm `Đậu hũ` với số lượng `200 g`.
* **Method & Endpoint**: `POST /api/v1/pantry`
* **Kết quả mong đợi**:
  - `StatusCode`: `200 OK` hoặc `201 Created`
  - `Data.quantity`: `500.0` (300g ban đầu + 200g mới thêm = 500g).

---

### Test Case P4: Lấy danh sách nguyên liệu trong tủ
* **Method & Endpoint**: `GET /api/v1/pantry` (hoặc `GET /api/v1/users/me/ingredients`)
* **Headers**: `Authorization: Bearer {{Token}}`
* **Kết quả mong đợi**: `200 OK`, danh sách món trong tủ, sắp xếp theo hạn sử dụng gần nhất lên đầu.

---

## 5. TEST CASES MODULE 3: MEALPLAN (THỰC ĐƠN TUẦN 7 NGÀY & GỢI Ý)

### Test Case M1: Tự động sinh thực đơn 7 ngày LỌC SẠCH DỊ ỨNG
* **Mục tiêu**: Hệ thống tự động xếp 7 ngày thực đơn cho người dùng, đảm bảo KHÔNG BAO GIỜ xuất hiện món có chứa `soy` và `peanut`.
* **Method & Endpoint**: `POST /api/v1/meal-plans/generate`
* **Headers**: `Authorization: Bearer {{Token}}`
* **Request Body**: `{}` (rỗng)
* **Kết quả mong đợi**:
  - `StatusCode`: `200 OK`
  - Thực đơn 7 ngày đầy đủ các slot: `breakfast`, `lunch`, `dinner`, `snack_pm`.
  - Toàn bộ các món ăn trong 7 ngày **KHÔNG** chứa dị ứng `soy` và `peanut`.
  - Tổng calo mỗi ngày dao động quanh mục tiêu thể trạng (±10%).

---

### Test Case M2: Gợi ý món nấu từ nguyên liệu trong tủ lạnh
* **Mục tiêu**: Gửi danh sách nguyên liệu vừa quét được từ tủ lạnh để AI gợi ý 10 món ăn thuần chay phù hợp nhất.
* **Method & Endpoint**: `POST /api/v1/meal-plans/from-ingredients`
* **Request Body**:
```json
{
  "ingredients": [
    { "name": "Bông cải xanh" },
    { "name": "Cà rốt" },
    { "name": "Nấm rơm" }
  ],
  "excludeAllergens": ["peanut"]
}
```
* **Kết quả mong đợi**:
  - `StatusCode`: `200 OK`
  - Trả về mảng các món ăn điểm cao nhất: `id`, `name`, `calories`, `prepMinutes`, `usedIngredients`, `missingIngredients`.

---

### Test Case M3: Gợi ý món thay thế cho 1 bữa ăn
* **Method & Endpoint**: `GET /api/v1/meal-plans/{planId}/swap-suggestions?date=2026-10-26&slot=lunch`
* **Headers**: `Authorization: Bearer {{Token}}`
* **Kết quả mong đợi**: `200 OK`, danh sách tối đa 5 món chay cùng loại bữa trưa, chênh lệch calo không quá 15%, không chứa dị ứng.

---

## 6. TEST CASES MODULE 4: GEMINI VISION SCAN QUÉT TỦ LẠNH (`/vision/scan`)

### Test Case V1: Quét ảnh tủ lạnh thành công (Hỗ trợ Smart Mock Fallback & Real Gemini)
* **Mục tiêu**: Người dùng chụp ảnh tủ lạnh gửi lên để hệ thống nhận diện thực phẩm, phân loại thuần chay và trả về Bounding Box.
* **Method & Endpoint**: `POST /api/v1/vision/scan`
* **Headers**: 
  - `Authorization: Bearer {{Token}}`
  - `Content-Type: multipart/form-data`
* **Form-Data**:
  - `image`: Chọn 1 file ảnh (JPG, PNG hoặc WEBP) bất kỳ dưới 10 MB.
* **Kết quả mong đợi**:
  - `StatusCode`: `200 OK`
  - Cấu trúc JSON trả về bọc trong `ApiResponse<ScanResultDto>`:
```json
{
  "success": true,
  "message": "Quét nhận diện thực phẩm thành công.",
  "statusCode": 200,
  "data": {
    "scanId": "scn_a1b2c3d4",
    "items": [
      {
        "id": "det_1",
        "label": "Bông cải xanh",
        "confidence": 0.96,
        "isVegan": true,
        "nonVeganReason": null,
        "veganAlternatives": [],
        "bbox": { "x": 0.06, "y": 0.18, "w": 0.3, "h": 0.22 },
        "alternatives": [
          { "label": "Súp lơ", "confidence": 0.03, "isVegan": true }
        ]
      },
      {
        "id": "det_4",
        "label": "Trứng gà",
        "confidence": 0.94,
        "isVegan": false,
        "nonVeganReason": "Có nguồn gốc động vật: trứng",
        "veganAlternatives": ["Đậu hũ non", "Bột hạt lanh"],
        "bbox": { "x": 0.05, "y": 0.43, "w": 0.36, "h": 0.12 },
        "alternatives": []
      }
    ]
  }
}
```
* **Ghi chú**: Flutter Mobile tự động bóc tách `data` qua `EnvelopeInterceptor` và render các hộp Bounding Box lên màn hình camera!

---

### Test Case V2: Kiểm tra chốt chặn Rate Limit (10 requests/phút per user)
* **Mục tiêu**: Gửi liên tiếp 11 requests `POST /api/v1/vision/scan` trong vòng dưới 60 giây.
* **Kết quả mong đợi**:
  - Request thứ 1 đến 10: `200 OK`.
  - Request thứ 11: `StatusCode: 429 Too Many Requests`
```json
{
  "success": false,
  "message": "Quá giới hạn quét tủ lạnh (tối đa 10 lần/phút). Vui lòng thử lại sau ít phút.",
  "statusCode": 429
}
```

---

### Test Case V3: Chặn file ảnh quá cỡ (> 10 MB)
* **Mục tiêu**: Tải file ảnh có kích thước 12 MB.
* **Kết quả mong đợi**:
  - `StatusCode`: `413 Payload Too Large`
  - Message: `"Dung lượng ảnh vượt quá 10 MB."`

---

## 7. ĐẶC TẢ VÀ TEST CASES MODULE 5: GEMINI CHATBOT RAG (`/chat`)

### 7.1. Kiến trúc & Hợp đồng Kỹ thuật (Theo Roadmap V2)
- **Cơ chế**: Stream Server-Sent Events (SSE) theo chuẩn `text/event-stream`.
- **Database**: Sử dụng cơ sở tri thức dinh dưỡng thuần chay được vector hóa bằng model `gemini-embedding-001` (768 chiều).
- **Phân quyền**:
  - Guest: Nhận diện qua header `X-Guest-Token` (tối đa 3 câu hỏi thử nghiệm). Câu thứ 4 trả `429` kèm mã lỗi yêu cầu đăng ký tài khoản.
  - User / Chef: Không giới hạn lượt hỏi.

### 7.2. Test Cases Chi Tiết
* **Endpoint 1 (Kiểm tra lượt dùng thử Guest)**: `GET /api/v1/chat/guest-trial`
  - Header: `X-Guest-Token: 3fa85f64-5717-4562-b3fc-2c963f66afa6`
  - Kết quả: `200 OK`, `{ "limit": 3, "used": 0, "remaining": 3 }`.
* **Endpoint 2 (Hỏi đáp Chatbot RAG Stream SSE)**: `POST /api/v1/chat/sessions/{sessionId}/messages`
  - Header: `Accept: text/event-stream`
  - Request Body:
```json
{
  "message": "Tôi bị dị ứng đậu nành thì nên bổ sung chất đạm từ những nguồn thực vật nào?",
  "context": {
    "includeMealPlan": true,
    "includeHealthProfile": true
  }
}
```
  - **Dòng SSE Stream trả về**:
```
event: citation
data: {"index": 1, "title": "Hướng dẫn dinh dưỡng thực vật WHO", "url": "https://who.int/vegan-nutrition"}

event: token
data: {"text": "Chào bạn, "}

event: token
data: {"text": "khi bị dị ứng đậu nành, bạn có thể bổ sung đạm từ nấm, hạt bí, hạt quinoa [1]..."}

event: done
data: {"messageId": "msg_9981", "trialRemaining": 2}
```

---

## 8. ĐẶC TẢ VÀ TEST CASES MODULE 6: TRÍCH XUẤT CÔNG THỨC TỪ VIDEO NGẮN

### 8.1. Luồng xử lý Pipeline Background
1. Người dùng tải video lên qua `POST /api/v1/media/videos` (tối đa 100 MB).
2. App gọi `POST /api/v1/videos/{id}/extraction` để kích hoạt AI trích xuất.
3. Trạng thái chạy ngầm: `queued` ➔ `transcribing` ➔ `extracting` ➔ `ready` (hoặc `failed`).
4. App gọi `GET /api/v1/videos/{id}` để cập nhật thanh tiến trình.

### 8.2. Test Cases Chi Tiết
* **Tải video**: `POST /api/v1/media/videos` (file `.mp4`, dung lượng 15 MB) ➔ Nhận về `videoUrl` và `mediaAssetId`.
* **Yêu cầu trích xuất**: `POST /api/v1/videos/{id}/extraction` ➔ `202 Accepted`.
* **Truy vấn kết quả công thức**: `GET /api/v1/videos/{id}` ➔ Trả về:
```json
{
  "status": "ready",
  "summary": "Hướng dẫn nấu canh rong biển hạt sen thanh mát",
  "totalMinutes": 20,
  "kcalPerServing": 180,
  "ingredients": [
    { "name": "Rong biển khô", "quantity": "30 g", "atSecond": 15 },
    { "name": "Hạt sen tươi", "quantity": "100 g", "atSecond": 28 }
  ],
  "steps": [
    { "index": 1, "text": "Ngâm rong biển trong nước ấm 10 phút", "atSecond": 12 },
    { "index": 2, "text": "Hầm hạt sen chín mềm rồi cho rong biển vào", "atSecond": 45 }
  ]
}
```

---

## 9. BẢNG CHECKLIST NGHIỆM THU TỔNG HỢP

| Nhóm chức năng | Mã Test | Nội dung kiểm thử | Phương thức | Trạng thái hiện tại |
|:---:|:---:|---|:---:|:---:|
| **Health** | H1 | Lấy danh mục 7 chất dị ứng chuẩn | `GET` | ✅ Hoàn thành |
| | H2 | Cập nhật thể trạng & Tính BMR, TDEE, Calo | `PUT` | ✅ Hoàn thành |
| | H3 | Xem lịch sử theo dõi cân nặng | `GET` | ✅ Hoàn thành |
| **Pantry** | P1 | Tìm kiếm nguyên liệu chuẩn không dấu | `GET` | ✅ Hoàn thành |
| | P2 | Thêm nguyên liệu & Cảnh báo dị ứng tự động | `POST` | ✅ Hoàn thành |
| | P3 | Tự động cộng dồn số lượng khi thêm trùng | `POST` | ✅ Hoàn thành |
| | P4 | Lấy danh sách nguyên liệu trong tủ lạnh | `GET` | ✅ Hoàn thành |
| **MealPlan** | M1 | Tự sinh thực đơn 7 ngày LỌC SẠCH DỊ ỨNG | `POST` | ✅ Hoàn thành |
| | M2 | Xếp gợi ý món từ nguyên liệu trong tủ | `POST` | ✅ Hoàn thành |
| | M3 | Gợi ý món thay thế cùng loại bữa | `GET` | ✅ Hoàn thành |
| **Vision** | V1 | Quét tủ lạnh (`/vision/scan`) nhận diện món & Bounding Box | `POST` | ✅ Đã sẵn sàng (Sẵn Mock + Real Gemini) |
| | V2 | Chặn Rate Limit (tối đa 10 lần/phút) | `POST` | ✅ Đã sẵn sàng |
| | V3 | Chặn ảnh vượt quá dung lượng 10 MB | `POST` | ✅ Đã sẵn sàng |
| **Chatbot RAG** | C1 | Kiểm tra số lượt dùng thử của Guest | `GET` | ⏳ Đặc tả chuẩn bị kết nối |
| | C2 | Stream trả lời SSE kèm trích dẫn tài liệu | `POST` | ⏳ Đặc tả chuẩn bị kết nối |
| **Video AI** | VD1 | Tải video ngắn lên hệ thống (tối đa 100 MB) | `POST` | ✅ Đã có API upload |
| | VD2 | Trích xuất công thức & mốc giây bước nấu | `GET/POST`| ⏳ Đặc tả chuẩn bị kết nối |

---
*Tài liệu này được tạo tự động bởi Antigravity Agent phục vụ công tác bàn giao và kiểm thử API Backend VeganLife.*

