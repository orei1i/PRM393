# 🧪 TÀI LIỆU TEST CASES: HEALTHPROFILE, PANTRY & MEALPLAN

> **Hệ thống**: VeganLife Backend (.NET 9 Clean Architecture)  
> **Các module**: 
> 1. **HealthProfile**: Hồ sơ thể trạng, năng lượng Mifflin-St Jeor, BMI, danh mục dị ứng.
> 2. **Pantry**: Quản lý tủ lạnh, tìm kiếm nguyên liệu chuẩn, cộng dồn số lượng, cảnh báo dị ứng.
> 3. **MealPlan & Recipes**: Thực đơn 7 ngày, AI/thuật toán sinh thực đơn lọc sạch dị ứng, đổi món, xếp món từ tủ lạnh, công thức cá nhân.  
> **Base URL**: `http://localhost:5001/api/v1`  
> **Swagger UI**: `http://localhost:5001/swagger`  
> **File HTTP Request mẫu**: [ControllerLayer.http](file:///e:/Semester_7/PRM392/Project/PRM393/BE/ControllerLayer/ControllerLayer.http)

---

## 📌 MỤC LỤC
1. [Chuẩn bị môi trường & Đăng nhập](#1-chuẩn-bị-môi-trường--đăng-nhập)
2. [Phần 1: Test Cases Module HealthProfile](#phần-1-test-cases-module-healthprofile)
3. [Phần 2: Test Cases Module Pantry & Ingredients](#phần-2-test-cases-module-pantry--ingredients)
4. [Phần 3: Test Cases Module MealPlan & Recipes](#phần-3-test-cases-module-mealplan--recipes)
5. [Bảng Checklist Tổng Hợp Nghiệm Thu](#5-bảng-checklist-tổng-hợp-nghiệm-thu)

---

## 1. Chuẩn Bị Môi Trường & Đăng Nhập

### 1.1. Khởi động Backend
Mở Terminal tại thư mục `BE/ControllerLayer`:
```powershell
cd e:\Semester_7\PRM392\Project\PRM393\BE\ControllerLayer
dotnet run
```
Truy cập Swagger tại trình duyệt: 👉 `http://localhost:5001/swagger`

### 1.2. Đăng nhập lấy Token
* **Endpoint**: `POST /api/v1/auth/login`
* **Request Body**:
```json
{
  "email": "minhanh.nguyen@gmail.com",
  "password": "Password123!"
}
```
* **Lấy `accessToken`** từ response và dán vào nút **Authorize 🔒** trên Swagger UI (chỉ cần dán chuỗi token, Swagger đã tự thêm tiền tố `Bearer `).

---

## Phần 1: Test Cases Module HealthProfile

### Test Case H1: Lấy danh mục dị ứng chuẩn (Guest - Không cần Token)
* **Mục tiêu**: Kiểm tra danh mục chất dị ứng chuẩn được hệ thống hỗ trợ.
* **Method & Endpoint**: `GET /api/v1/catalog/allergens`
* **Kết quả mong đợi**:
  - Status code: `200 OK`
  - Response trả về 7 nhóm dị ứng chuẩn: `peanut`, `tree_nut`, `soy`, `gluten`, `sesame`, `mustard`, `celery` kèm nhãn tiếng Việt rõ ràng.

---

### Test Case H2: Xem hồ sơ khi chưa khởi tạo (Kiểm tra 404)
* **Mục tiêu**: Khi tài khoản mới chưa từng cập nhật hồ sơ, server phải trả về `404` để app Flutter điều hướng sang màn hình thiết lập hồ sơ.
* **Method & Endpoint**: `GET /api/v1/health-profile/me`
* **Headers**: `Authorization: Bearer {{Token}}` (dùng tài khoản mới chưa tạo profile)
* **Kết quả mong đợi**:
  - Status code: `404 Not Found`
  - Response: `"Bạn chưa tạo hồ sơ sức khỏe."`

---

### Test Case H3: Khởi tạo hồ sơ thể trạng Nam (Công thức Mifflin-St Jeor Ca 1)
* **Mục tiêu**: Kiểm tra tính toán BMR, TDEE, Calo mục tiêu và BMI cho Nam 25 tuổi, 170cm, 70kg, vận động vừa, giữ cân, dị ứng đậu phộng và nấm.
* **Method & Endpoint**: `PUT /api/v1/health-profile/me`
* **Headers**: `Authorization: Bearer {{Token}}`
* **Request Body**:
```json
{
  "heightCm": 170.0,
  "weightKg": 70.0,
  "goal": "maintain",
  "gender": "Male",
  "birthYear": 2001,
  "activityLevel": "moderate",
  "mealPattern": ["breakfast", "lunch", "snack_pm", "dinner"],
  "allergies": [
    { "allergenId": "peanut", "name": "Đậu phộng (Lạc)" },
    { "allergenId": null, "name": "nấm rơm" }
  ],
  "dietaryRestrictions": ["low_sodium"]
}
```
* **Kết quả mong đợi**:
  - Status code: `200 OK`
  - `data.bmi`: `24.2` (Phân loại Châu Á: `overweight`, WHO: `normal`)
  - `data.bmr`: `1642.5`
  - `data.tdee`: `2545.9`
  - `data.targetCalories`: `2550` (làm tròn hàng chục chuẩn `energy.dart`)
  - `allergies` chứa cả mã chuẩn `peanut` và chuỗi tự do `nấm rơm`.

---

### Test Case H4: Cập nhật hồ sơ thể trạng Nữ (Công thức Ca 2)
* **Mục tiêu**: Kiểm tra tính toán Nữ 30 tuổi, 160cm, 55kg, vận động nhẹ, giảm cân (-15% calo).
* **Method & Endpoint**: `PUT /api/v1/health-profile/me`
* **Headers**: `Authorization: Bearer {{Token}}`
* **Request Body**:
```json
{
  "heightCm": 160.0,
  "weightKg": 55.0,
  "goal": "lose",
  "gender": "Female",
  "birthYear": 1996,
  "activityLevel": "light",
  "mealPattern": ["breakfast", "lunch", "dinner"],
  "allergies": [
    { "allergenId": "soy", "name": "Đậu nành" }
  ]
}
```
* **Kết quả mong đợi**:
  - Status code: `200 OK`
  - `data.bmi`: `21.5` (`normal`)
  - `data.bmr`: `1239.0`
  - `data.tdee`: `1703.6`
  - `data.targetCalories`: `1450` (1703.6 * 0.85 = 1448.08 -> làm tròn 1450)

---

### Test Case H5: Xem lịch sử biến thiên cân nặng
* **Mục tiêu**: Sau khi tạo hoặc thay đổi cân nặng ở Test Case H3 và H4, lịch sử phải ghi nhận sự thay đổi để vẽ biểu đồ tiến trình.
* **Method & Endpoint**: `GET /api/v1/health-profile/me/metrics?limit=10`
* **Headers**: `Authorization: Bearer {{Token}}`
* **Kết quả mong đợi**:
  - Status code: `200 OK`
  - Trả về danh sách các lần cân đo (`weightKg`, `heightCm`, `bmi`, `loggedAt`), sắp xếp mới nhất trước.

---

### Test Case H6: Chặn dữ liệu thể trạng không hợp lệ
* **Mục tiêu**: Validation khoảng giá trị sinh học (chiều cao 50-250cm, cân nặng 20-300kg, tuổi 13-100).
* **Method & Endpoint**: `PUT /api/v1/health-profile/me`
* **Request Body**: Gửi `heightCm: 20` hoặc `weightKg: 500` hoặc `birthYear: 2025`
* **Kết quả mong đợi**:
  - Status code: `400 Bad Request`
  - Response thông báo rõ trường lỗi dữ liệu không hợp lệ.

---

## Phần 2: Test Cases Module Pantry & Ingredients

### Test Case P1: Tìm kiếm danh mục nguyên liệu chuẩn (Không phân biệt dấu)
* **Mục tiêu**: Tìm kiếm nguyên liệu chuẩn và thông tin dinh dưỡng 100g.
* **Method & Endpoint**: `GET /api/v1/ingredients?q=dau hu&veganOnly=true`
* **Headers**: Không cần token
* **Kết quả mong đợi**:
  - Status code: `200 OK`
  - Tìm "dau hu" (không dấu) trả về các món: "Đậu hũ", "Đậu hũ chiên", "Đậu hũ non", "Đậu hũ ky".
  - Có đủ thông tin: `caloriesPer100g`, `proteinG`, `carbsG`, `fatG`, `fiberG`, `allergens`.

---

### Test Case P2: Lấy danh sách tủ lạnh rỗng (Lần đầu)
* **Method & Endpoint**: `GET /api/v1/pantry`
* **Headers**: `Authorization: Bearer {{Token}}`
* **Kết quả mong đợi**:
  - Status code: `200 OK`
  - Response body: `data: []`

---

### Test Case P3: Thêm 1 nguyên liệu thủ công vào tủ lạnh
* **Method & Endpoint**: `POST /api/v1/pantry`
* **Headers**: `Authorization: Bearer {{Token}}`
* **Request Body**:
```json
{
  "ingredient": "Đậu hũ",
  "quantity": 2.0,
  "unit": "miếng",
  "expiryDate": "2026-11-05T00:00:00Z"
}
```
* **Kết quả mong đợi**:
  - Status code: `200 OK`
  - Tự động khớp `ingredientId` và `category: "plant_protein"`, `caloriesPer100g: 76` từ danh mục chuẩn.
  - Số lượng: `2.0 miếng`.

---

### Test Case P4: Thêm trùng nguyên liệu -> Tự động cộng dồn số lượng
* **Mục tiêu**: Thêm tiếp 3 miếng "Đậu hũ" vào tủ lạnh. Hệ thống không tạo dòng mới mà cộng dồn thành 5 miếng.
* **Method & Endpoint**: `POST /api/v1/pantry`
* **Headers**: `Authorization: Bearer {{Token}}`
* **Request Body**:
```json
{
  "ingredient": "Đậu hũ",
  "quantity": 3.0,
  "unit": "miếng"
}
```
* **Kết quả mong đợi**:
  - Status code: `200 OK`
  - Gọi lại `GET /api/v1/pantry`: Chỉ có 1 dòng "Đậu hũ", `quantity: 5.0 miếng`.

---

### Test Case P5: Thêm hàng loạt từ kết quả scan tủ lạnh (Khớp hợp đồng Flutter)
* **Mục tiêu**: Flutter gửi mảng `{ "items": [ ... ] }` sau khi người dùng xác nhận kết quả quét ảnh tủ lạnh.
* **Method & Endpoint**: `POST /api/v1/users/me/ingredients`
* **Headers**: `Authorization: Bearer {{Token}}`
* **Request Body**:
```json
{
  "items": [
    { "ingredient": "Nấm rơm", "scannedAt": "2026-10-29T08:00:00Z" },
    { "ingredient": "Bông cải xanh", "scannedAt": "2026-10-29T08:00:00Z" },
    { "ingredient": "Cà rốt", "scannedAt": "2026-10-29T08:00:00Z" },
    { "ingredient": "Đậu phộng", "scannedAt": "2026-10-29T08:00:00Z" }
  ]
}
```
* **Kết quả mong đợi**:
  - Status code: `200 OK`
  - Thêm thành công cả 4 món vào tủ lạnh với `source: "vision"`.

---

### Test Case P6: Cảnh báo dị ứng tự động trong tủ lạnh
* **Mục tiêu**: Với tài khoản đã khai báo dị ứng đậu phộng và nấm rơm ở Test Case H3:
* **Method & Endpoint**: `GET /api/v1/pantry`
* **Headers**: `Authorization: Bearer {{Token}}`
* **Kết quả mong đợi**:
  - Trong danh sách trả về:
    - Món "Đậu phộng": có `allergyWarning: "Cảnh báo dị ứng: peanut"`.
    - Món "Nấm rơm": có `allergyWarning: "Cảnh báo dị ứng: nấm rơm"`.
    - Món "Bông cải xanh": `allergyWarning: null`.

---

### Test Case P7: Sửa thông tin nguyên liệu trong tủ
* **Method & Endpoint**: `PUT /api/v1/pantry/{id}` (Lấy `id` từ Test Case P5)
* **Request Body**:
```json
{
  "quantity": 3.5,
  "unit": "bó",
  "expiryDate": "2026-11-15T00:00:00Z"
}
```
* **Kết quả mong đợi**:
  - Status code: `200 OK`, số lượng và đơn vị được cập nhật.

---

### Test Case P8: Xóa 1 nguyên liệu và Xóa toàn bộ tủ lạnh
* **Xóa 1 món**: `DELETE /api/v1/pantry/{id}` → Status `200 OK`. Gọi lại `GET /pantry` món này không còn.
* **Xóa tất cả**: `DELETE /api/v1/pantry` (hoặc `DELETE /api/v1/users/me/ingredients`) → Status `200 OK`. Tủ lạnh trở về rỗng `[]`.

---

## Phần 3: Test Cases Module MealPlan & Recipes

### Test Case M1: Lấy thực đơn tuần khi chưa có (Kiểm tra 404)
* **Method & Endpoint**: `GET /api/v1/meal-plans/current`
* **Headers**: `Authorization: Bearer {{Token}}` (chưa tạo tuần nào)
* **Kết quả mong đợi**:
  - Status code: `404 Not Found`
  - Response: `"Bạn chưa có thực đơn cho tuần này."`

---

### Test Case M2: Tạo tuần mới với các ô bữa trống (Tự lên thực đơn)
* **Method & Endpoint**: `POST /api/v1/meal-plans`
* **Headers**: `Authorization: Bearer {{Token}}`
* **Request Body**:
```json
{
  "startDate": "2026-10-26",
  "empty": true
}
```
* **Kết quả mong đợi**:
  - Status code: `200 OK`
  - Tạo cấu trúc 7 ngày (`2026-10-26` đến `2026-11-01`), mỗi ngày có mảng `meals: {}` rỗng để người dùng tự chọn món.

---

### Test Case M3: Tự động sinh thực đơn 7 ngày (AI/Thuật toán lọc sạch dị ứng)
* **Mục tiêu**: Điền đầy 7 ngày với các bữa `breakfast`, `lunch`, `dinner`, `snack_pm`. Đảm bảo calo cân bằng và **tuyệt đối không có món chứa đậu phộng hoặc nấm rơm** (dị ứng của user ở Test Case H3).
* **Method & Endpoint**: `POST /api/v1/meal-plans/generate`
* **Headers**: `Authorization: Bearer {{Token}}`
* **Request Body**:
```json
{
  "startDate": "2026-10-26",
  "usePantry": false
}
```
* **Kết quả mong đợi**:
  - Status code: `200 OK`
  - Cả 7 ngày đều được điền đầy đủ các món ăn.
  - Tổng calo mỗi ngày (`totalCalories`) nằm trong dải xấp xỉ calo mục tiêu (90% - 110% của 2550 kcal).
  - **Kiểm tra an toàn dị ứng**: Trong toàn bộ 7 ngày, **KHÔNG CÓ BẤT KỲ MÓN NÀO** chứa đậu phộng (như "Sinh tố chuối bơ đậu phộng") hay nấm rơm (như "Canh chua nấm đậu bắp").

---

### Test Case M4: Tự động xếp thực đơn ưu tiên nguyên liệu trong tủ lạnh
* **Mục tiêu**: Xếp thực đơn ưu tiên sử dụng nguyên liệu đang có trong tủ (Test Case P5).
* **Method & Endpoint**: `POST /api/v1/meal-plans/from-ingredients`
* **Headers**: `Authorization: Bearer {{Token}}`
* **Request Body**:
```json
{
  "startDate": "2026-10-26"
}
```
* **Kết quả mong đợi**:
  - Status code: `200 OK`
  - Thực đơn được xếp ưu tiên các món chứa bông cải xanh, cà rốt, đậu hũ (những nguyên liệu user đang có).

---

### Test Case M5: Lấy gợi ý 3 món thay thế cho ô bữa (Swap Suggestions)
* **Mục tiêu**: Đang xem bữa trưa ngày `2026-10-26`, muốn đổi sang món khác.
* **Method & Endpoint**: `GET /api/v1/meal-plans/{planId}/swap-suggestions?date=2026-10-26&slot=lunch&limit=3`
* **Headers**: `Authorization: Bearer {{Token}}`
* **Kết quả mong đợi**:
  - Status code: `200 OK`
  - Trả về đúng 3 công thức món trưa phù hợp, lượng calo tương đồng (lệch tối đa ±15%) và tuyệt đối không dính dị ứng.

---

### Test Case M6: Đổi món trong thực đơn
* **Mục tiêu**: Đổi món bữa trưa ngày `2026-10-26` thành công thức vừa chọn ở Test Case M5.
* **Method & Endpoint**: `PATCH /api/v1/meal-plans/{planId}/meals`
* **Headers**: `Authorization: Bearer {{Token}}`
* **Request Body**:
```json
{
  "date": "2026-10-26",
  "slot": "lunch",
  "recipeId": "672000000000000000000033"
}
```
* **Kết quả mong đợi**:
  - Status code: `200 OK`
  - Trả về ngày `2026-10-26` đã được cập nhật với món ăn mới và tính lại `totalCalories` cho cả ngày.

---

### Test Case M7: Bỏ một món khỏi bữa ăn (Empties a slot)
* **Mục tiêu**: Người dùng bỏ món ăn vặt bữa xế `snack_pm`.
* **Method & Endpoint**: `DELETE /api/v1/meal-plans/{planId}/meals?date=2026-10-26&slot=snack_pm`
* **Headers**: `Authorization: Bearer {{Token}}`
* **Kết quả mong đợi**:
  - Status code: `200 OK`
  - Slot `snack_pm` bị xóa khỏi ngày đó, `totalCalories` giảm tương ứng.

---

### Test Case M8: Gán hàng loạt món vào thực đơn hiện tại (Batch)
* **Mục tiêu**: Áp dụng hàng loạt món từ thực đơn chuyên gia hoặc kế hoạch tuần có sẵn.
* **Method & Endpoint**: `POST /api/v1/meal-plans/current/meals/batch`
* **Headers**: `Authorization: Bearer {{Token}}`
* **Request Body**:
```json
{
  "meals": [
    {
      "date": "2026-10-27",
      "slot": "breakfast",
      "name": "Bánh mì đậu hũ sả ớt",
      "calories": 460,
      "prepMinutes": 15
    },
    {
      "date": "2026-10-27",
      "slot": "lunch",
      "name": "Cơm chiên hạt sen bông cải xanh",
      "calories": 480,
      "prepMinutes": 20
    }
  ]
}
```
* **Kết quả mong đợi**:
  - Status code: `200 OK`
  - Trả về: `{ "placed": 2, "skipped": 0, "days": [ ... ] }`.

---

### Test Case M9: Tạo và xem công thức của riêng tôi ("Món của tôi")
* **Tạo công thức mới**: `POST /api/v1/recipes`
```json
{
  "name": "Nấm mối đen xào gừng ấm bụng",
  "calories": 280,
  "proteinG": 12.0,
  "carbsG": 20.0,
  "fatG": 8.0,
  "fiberG": 6.0,
  "prepMinutes": 15,
  "ingredients": ["Nấm mối đen", "Gừng tươi", "Nước tương", "Hành boa-rô"]
}
```
  - Status code: `201 Created`
* **Lấy danh sách món của tôi**: `GET /api/v1/users/me/recipes` (hoặc `GET /api/v1/recipes`)
  - Status code: `200 OK`, hiển thị món vừa tạo và chỉ thuộc về tài khoản này.

---

## 5. Bảng Checklist Tổng Hợp Nghiệm Thu

| Nhóm | Mã Test Case | Tên Chức Năng | Trạng Thái |
|:---:|:---:|---|:---:|
| **Health** | H1 | Lấy danh mục 7 chất dị ứng chuẩn | [ ] |
| | H2 | Kiểm tra 404 khi chưa khởi tạo hồ sơ | [ ] |
| | H3 | Tính BMR, TDEE, Calo cho Nam (2550 kcal) | [ ] |
| | H4 | Tính BMR, TDEE, Calo cho Nữ giảm cân (1450 kcal) | [ ] |
| | H5 | Xem lịch sử theo dõi cân nặng | [ ] |
| | H6 | Chặn dữ liệu thể trạng ngoài ngưỡng sinh học (400) | [ ] |
| **Pantry** | P1 | Tìm nguyên liệu không dấu & chữ hoa | [ ] |
| | P2 | Lấy danh sách tủ lạnh rỗng | [ ] |
| | P3 | Thêm 1 nguyên liệu khớp dinh dưỡng chuẩn | [ ] |
| | P4 | Tự động cộng dồn số lượng khi thêm trùng món | [ ] |
| | P5 | Thêm hàng loạt từ kết quả scan tủ lạnh | [ ] |
| | P6 | Cảnh báo dị ứng tự động cho món trong tủ | [ ] |
| | P7 | Cập nhật số lượng, đơn vị, hạn dùng | [ ] |
| | P8 | Xóa 1 nguyên liệu và làm trống tủ lạnh | [ ] |
| **MealPlan** | M1 | Kiểm tra 404 khi chưa có thực đơn tuần | [ ] |
| | M2 | Tạo tuần mới với các ô bữa trống | [ ] |
| | M3 | Tự động sinh 7 ngày tuyệt đối lọc sạch dị ứng | [ ] |
| | M4 | Xếp thực đơn ưu tiên nguyên liệu trong tủ | [ ] |
| | M5 | Gợi ý 3 món thay thế khớp calo và loại bữa | [ ] |
| | M6 | Đổi món trong thực đơn tuần | [ ] |
| | M7 | Bỏ một món khỏi ô bữa | [ ] |
| | M8 | Gán hàng loạt món vào tuần hiện tại | [ ] |
| | M9 | Quản lý công thức cá nhân ("Món của tôi") | [ ] |

