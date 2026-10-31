# 🛠️ HƯỚNG DẪN THIẾT LẬP VÀ KHỞI CHẠY BACKEND VEGANLIFE (TỪ A - Z)

> **Dự án**: VeganLife Backend (.NET 9 Clean Architecture + MongoDB + Redis + Gemini AI)  
> **Áp dụng cho**: Tất cả thành viên trong nhóm, dev frontend, tester khi clone dự án về máy.  
> **Thời gian thiết lập**: ~3 phút nếu đã cài sẵn phần mềm.

---

## 📌 MỤC LỤC
1. [Yêu Cầu Cài Đặt Ban Đầu (Prerequisites)](#1-yêu-cầu-cài-đặt-ban-đầu-prerequisites)
2. [Quy Trình Khởi Chạy 3 Bước Nhanh Nhất](#2-quy-trình-khởi-chạy-3-bước-nhanh-nhất)
3. [Cấu Hình appsettings.json Cần Biết](#3-cấu-hình-appsettingsjson-cần-biết)
4. [Tài Khoản Mẫu & Dữ Liệu Tự Động (Seed Data)](#4-tài-khoản-mẫu--dữ-liệu-tự-động-seed-data)
5. [Cơ Chế Gemini AI & Smart Mock Fallback](#5-cơ-chế-gemini-ai--smart-mock-fallback)
6. [Xử Lý Các Lỗi Thường Gặp (Troubleshooting / FAQ)](#6-xử-lý-các-lỗi-thường-gặp-troubleshooting--faq)

---

## 1. YÊU CẦU CÀI ĐẶT BAN ĐẦU (PREREQUISITES)

Trước khi chạy, máy tính của bạn cần cài đặt:

| Phần mềm | Phiên bản yêu cầu | Cách kiểm tra | Link tải nếu chưa có |
|---|---|---|---|
| **.NET SDK** | .NET **9.0** trở lên | Mở terminal gõ: `dotnet --version` | [Tải .NET 9 SDK](https://dotnet.microsoft.com/download/dotnet/9.0) |
| **Docker Desktop** | Bản mới nhất (hỗ trợ WSL2) | Mở terminal gõ: `docker --version` | [Tải Docker Desktop](https://www.docker.com/products/docker-desktop/) |
| **Git** | Mới nhất | Mở terminal gõ: `git --version` | [Tải Git](https://git-scm.com/) |

---

## 2. QUY TRÌNH KHỞI CHẠY 3 BƯỚC NHANH NHẤT

### 🔹 BƯỚC 1: Khởi động Cơ sở dữ liệu (MongoDB & Redis qua Docker)

> ⚠️ **LƯU Ý CỰC KỲ QUAN TRỌNG**: Bạn PHẢI mở ứng dụng **Docker Desktop** trên máy tính trước, đợi Docker khởi động hoàn tất (chữ **Engine running** màu xanh) rồi mới chạy lệnh!

Mở Terminal (PowerShell hoặc CMD), di chuyển vào đúng thư mục `BE` và chạy lệnh sau:

```powershell
# 1. Đi tới thư mục BE của dự án
cd e:\Semester_7\PRM392\Project\PRM393\BE

# 2. Khởi chạy MongoDB và Redis chạy ngầm
docker compose up -d mongodb redis
```

Kiểm tra container đã chạy bằng lệnh:
```powershell
docker ps
```
Nếu thấy container `be-mongodb-1` (port `27017`) và `be-redis-1` (port `6379`) ở trạng thái **Up** là thành công!

---

### 🔹 BƯỚC 2: Kiểm tra biên dịch dự án (Build)

Tại thư mục `BE`, chạy lệnh build để đảm bảo toàn bộ các tầng không có lỗi cú pháp:

```powershell
dotnet build
```
Kết quả hiển thị: **`Build succeeded. 0 Error(s)`**.

---

### 🔹 BƯỚC 3: Khởi chạy Backend API

Di chuyển vào thư mục `ControllerLayer` và khởi chạy server:

```powershell
cd ControllerLayer
dotnet run
```

Sau khi chạy, Terminal sẽ thông báo:
```text
Now listening on: http://localhost:5001
Now listening on: https://localhost:7211
```

🎉 **XONG!** Mở trình duyệt và truy cập Swagger UI tương tác tại:
👉 **`http://localhost:5001/swagger`** (hoặc `http://localhost:7211/swagger`)

---

## 3. CẤU HÌNH APPSETTINGS.JSON CẦN BIẾT

File cấu hình nằm tại: [`BE/ControllerLayer/appsettings.json`](file:///e:/Semester_7/PRM392/Project/PRM393/BE/ControllerLayer/appsettings.json)

```json
{
  "ConnectionStrings": {
    "MongoConnection": "mongodb://localhost:27017"
  },
  "DatabaseName": "VeganLifeDB",
  "JwtSettings": {
    "SecretKey": "VeganLife_Dev_Secret_Key_2026_Must_Be_Over_32_Chars!",
    "Issuer": "VeganLifeAuthService",
    "Audience": "VeganLifeClients",
    "ExpiryMinutes": 60,
    "RefreshTokenExpiryDays": 7
  },
  "Gemini": {
    "ApiKey": "",
    "Model": "gemini-2.0-flash",
    "EmbeddingModel": "gemini-embedding-001",
    "BaseUrl": "https://generativelanguage.googleapis.com/v1beta"
  },
  "Cloudinary": {
    "CloudName": "dummy_cloud_name",
    "ApiKey": "dummy_api_key",
    "ApiSecret": "dummy_api_secret"
  }
}
```

* **MongoDB**: Mặc định kết nối tới `mongodb://localhost:27017`, database tên `VeganLifeDB`.
* **Cloudinary**: Khi để `dummy_cloud_name`, hệ thống **tự động fallback lưu ảnh/video cục bộ** vào thư mục `ControllerLayer/wwwroot/uploads/` nên bạn không bắt buộc phải có tài khoản Cloudinary để test upload.

---

## 4. TÀI KHOẢN MẪU & DỮ LIỆU TỰ ĐỘNG (SEED DATA)

Khi Backend khởi động lần đầu, hệ thống sẽ **tự động chạy Seeder**:
1. **Khởi tạo chỉ mục MongoDB**: Tự động tạo unique indexes cho `Users`, `HealthProfiles`, `MealPlans`, `AiLogs`, `MediaAssets`...
2. **Seed 35 nguyên liệu chuẩn** (`Ingredients`): Chứa đầy đủ dinh dưỡng, nhãn thuần chay và mã dị ứng.
3. **Seed 51 công thức món ăn chuẩn** (`Recipes`): Chứa calo, macro, thời gian nấu và ảnh minh họa.
4. **Tài khoản đăng nhập kiểm thử có sẵn**:

| Email | Mật khẩu | Quyền (Role) | Ghi chú |
|---|---|---|---|
| `minhanh.nguyen@gmail.com` | `Password123!` | `User` | Tài khoản người dùng mẫu |
| `chef.hoang@veganlife.vn` | `Password123!` | `Chef` | Tài khoản đầu bếp chuyên gia |
| `admin@veganlife.vn` | `Password123!` | `Admin` | Quản trị viên hệ thống |

---

## 5. CƠ CHẾ GEMINI AI & SMART MOCK FALLBACK

- **Nếu chưa có API Key của Gemini**:
  - Không cần lo lắng! Hệ thống đã tích hợp **Smart Mock Fallback**.
  - Khi bạn test tính năng Quét tủ lạnh `POST /api/v1/vision/scan`, hệ thống vẫn nhận diện và trả về danh sách nguyên liệu thực tế (bông cải xanh, đậu hũ, cà chua, trứng gà không chay kèm món thay thế, tọa độ Bounding Box) giúp kiểm thử trơn tru mà không bị lỗi `500` do thiếu key.
- **Khi muốn dùng AI thật của Google Gemini**:
  1. Lấy API Key miễn phí tại [Google AI Studio](https://aistudio.google.com/).
  2. Mở `BE/ControllerLayer/appsettings.json`, dán key vào trường `"ApiKey": "AIzaSy..."` trong mục `Gemini`.
  3. Khởi động lại Backend — hệ thống sẽ tự động gọi trực tiếp Google Gemini 2.0 Flash!

---

## 6. XỬ LÝ CÁC LỖI THƯỜNG GẶP (TROUBLESHOOTING / FAQ)

### ❌ Lỗi 1: `System.TimeoutException: A timeout occurred after 30011ms... SocketException (10061): No connection could be made because the target machine actively refused it at localhost:27017`
* **Nguyên nhân**: Docker Desktop chưa mở hoặc container MongoDB chưa được bật.
* **Cách sửa**: 
  1. Mở ứng dụng **Docker Desktop**.
  2. Chạy lệnh: `cd BE; docker compose up -d mongodb`.

---

### ❌ Lỗi 2: `no configuration file provided: not found` khi gõ lệnh Docker
* **Nguyên nhân**: Terminal đang đứng sai thư mục (ví dụ đứng ở `C:\Users\Admin`).
* **Cách sửa**: Chuyển đúng vào thư mục `BE` trước khi chạy docker:
  ```powershell
  cd e:\Semester_7\PRM392\Project\PRM393\BE
  docker compose up -d mongodb
  ```

---

### ❌ Lỗi 3: `error MSB3021: Unable to copy file ... because it is being used by another process` khi gõ `dotnet build`
* **Nguyên nhân**: Một cửa sổ Terminal khác hoặc Visual Studio đang chạy ứng dụng (`dotnet run`) làm khóa các file `.dll`.
* **Cách sửa**:
  - Nhấn `Ctrl + C` tại cửa sổ Terminal đang chạy `dotnet run` để dừng server trước khi gõ `dotnet build`.
  - Hoặc tắt tiến trình dotnet cũ bằng PowerShell:
    ```powershell
    Stop-Process -Name "ControllerLayer" -Force -ErrorAction SilentlyContinue
    ```

---

### ❌ Lỗi 4: Swagger báo `TypeError: Failed to fetch` hoặc CORS Error
* **Nguyên nhân**: Middleware CORS bị chặn hoặc backend bị crash trước khi gửi response header.
* **Cách khắc phục**: Backend hiện tại đã được đặt `app.UseCors("MobilePolicy")` ở đầu pipeline và tự chèn header CORS ngay cả khi có Exception, đảm bảo Swagger và Mobile luôn nhận được phản hồi JSON chi tiết.

---

### ❌ Lỗi 5: `413 Payload Too Large` khi tải ảnh hoặc video
* **Quy định kích thước**:
  - Ảnh đại diện, ảnh bài viết, ảnh scan tủ lạnh: **Tối đa 10 MB** (định dạng JPG, PNG, WEBP).
  - Video ngắn nấu ăn: **Tối đa 100 MB** (định dạng MP4, MOV, WEBM).
* **Cách khắc phục**: Nếu file vượt quá kích thước trên, hãy nén nhẹ file trước khi tải lên.

---

## 7. TÀI LIỆU THAM KHẢO THÊM
- Toàn bộ danh sách Test Case chi tiết cho từng API: [**`BE/HUONG_DAN_TEST_TOAN_DIEN_BE_API.md`**](file:///e:/Semester_7/PRM392/Project/PRM393/BE/HUONG_DAN_TEST_TOAN_DIEN_BE_API.md)
- File gọi API trực tiếp trong VS Code / Rider: [**`BE/ControllerLayer/ControllerLayer.http`**](file:///e:/Semester_7/PRM392/Project/PRM393/BE/ControllerLayer/ControllerLayer.http)

