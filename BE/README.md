# 🌿 VeganLife Backend

Backend API cho ứng dụng **VeganLife** — hệ thống quản lý chuỗi nhà hàng thuần chay (franchise), xây dựng bằng **ASP.NET Core** theo kiến trúc **Clean Architecture** (N-Layer).

---

## 📐 Kiến trúc tổng quan

```
VeganLife.Backend
├── DomainLayer          # Tầng nghiệp vụ cốt lõi (không phụ thuộc gì)
├── ApplicationLayer     # Tầng ứng dụng (use-cases, services, DTOs, interfaces)
├── InfrastructureLayer  # Tầng hạ tầng (DB, repository, external services)
└── ControllerLayer      # Tầng API (controllers, middleware, filters, auth)
```

Luồng phụ thuộc tuân theo nguyên tắc **Dependency Inversion**:

```
ControllerLayer → ApplicationLayer → DomainLayer
InfrastructureLayer → ApplicationLayer → DomainLayer
```

---

## 📁 Cấu trúc thư mục

### DomainLayer/
> Tầng cốt lõi — không phụ thuộc vào bất kỳ layer nào khác.

| Thư mục | Mô tả |
|---------|-------|
| Entities/ | Các entity chính: BaseEntity, User |
| Enums/ | Enum dùng chung: GeneralEnum, PriceStatus, SupplierStatus, UnitOfMeasure, UnitType |
| Exceptions/ | Custom exceptions: NotFoundException, BadRequestException, ConflictException, ForbiddenException, UnauthorizedException, ServerFailureException, v.v. |
| Constants/ | Hằng số toàn hệ thống: JwtConst, RoleHierarchy, OrderConst, LoyaltyConstants, GeneralConst |
| Helpers/ | Utility helpers: Str (string), FileHelpers |
| Interfaces/ | Contract cơ bản: IEntity, IGenericRepository<T> |

---

### ApplicationLayer/
> Tầng use-case — định nghĩa logic ứng dụng, không phụ thuộc vào hạ tầng.

| Thư mục | Mô tả |
|---------|-------|
| Services/ | Triển khai business logic: UserService |
| Interfaces/ | Interface cho services: IUserService |
| DTOs/Auth/ | AuthResponseDto — phản hồi sau đăng nhập/đăng ký |
| DTOs/Users/ | UserRequestDto, UserResponseDto |

---

### InfrastructureLayer/
> Tầng hạ tầng — kết nối với MongoDB và xử lý lưu trữ dữ liệu.

| Thư mục | Mô tả |
|---------|-------|
| Database/ | MongoDbContext — khởi tạo và quản lý kết nối MongoDB |
| Repository/ | GenericRepository<T> — CRUD generic theo IGenericRepository<T> |

---

### ControllerLayer/
> Tầng API — entry point của ứng dụng.

| Thư mục / File | Mô tả |
|----------------|-------|
| Controllers/ | UsersController — endpoint CRUD/auth cho User |
| Authorization/ | AppRoles — định nghĩa vai trò trong hệ thống |
| Middlewares/ | ExceptionHandlingMiddleware — chuẩn hóa exception thành JSON |
| Filters/ | ValidationFilter — validate request model tự động |
| Models/ | ApiResponse<T> — chuẩn hóa format response |
| Program.cs | Khởi tạo app: DI, Middleware pipeline, Auth |

---

## 🛠️ Công nghệ sử dụng

| Công nghệ | Mục đích |
|-----------|----------|
| **ASP.NET Core 8** | Web API framework |
| **MongoDB** | Cơ sở dữ liệu NoSQL chính |
| **JWT Bearer** | Xác thực stateless |
| **Google OAuth 2.0** | Đăng nhập bằng Google |
| **MoMo API** | Thanh toán qua ví MoMo |
| **VNPay** | Thanh toán qua VNPay |
| **Cloudinary** | Lưu trữ và quản lý ảnh |
| **SMTP Gmail** | Gửi email thông báo |
| **Docker / Docker Compose** | Container hóa và triển khai |

---

## ⚙️ Cấu hình môi trường

Sao chép ppsettings.json và điền giá trị thật. **Không commit secrets vào git.**

```json
{
  "ConnectionStrings": { "MongoConnection": "YOUR_MONGODB_CONNECTION_STRING" },
  "JwtSettings": { "SecretKey": "YOUR_JWT_SECRET_KEY" },
  "GoogleClientId": "YOUR_GOOGLE_CLIENT_ID",
  "GoogleClientSecret": "YOUR_GOOGLE_CLIENT_SECRET",
  "MoMo": { "AccessKey": "YOUR_MOMO_ACCESS_KEY", "SecretKey": "YOUR_MOMO_SECRET_KEY" },
  "VNPay": { "TmnCode": "YOUR_VNPAY_TMN_CODE", "HashSecret": "YOUR_VNPAY_HASH_SECRET" },
  "Email": { "SmtpUsername": "YOUR_EMAIL", "SmtpPassword": "YOUR_APP_PASSWORD" }
}
```

---

## 🚀 Hướng Dẫn Thiết Lập & Chạy Ứng Dụng

👉 Xem hướng dẫn chi tiết từng bước tại: [**`SETUP_HUONG_DAN_CHAY_BACKEND.md`**](SETUP_HUONG_DAN_CHAY_BACKEND.md)  
👉 Xem toàn bộ bộ Test Cases API tại: [**`HUONG_DAN_TEST_TOAN_DIEN_BE_API.md`**](HUONG_DAN_TEST_TOAN_DIEN_BE_API.md)

### Tóm tắt khởi chạy nhanh (3 bước):
```bash
# 1. Bật Docker Desktop, sau đó chạy database (MongoDB & Redis):
docker compose up -d mongodb redis

# 2. Biên dịch dự án:
dotnet build

# 3. Chạy Backend:
cd ControllerLayer
dotnet run
```
Mở Swagger UI tại: `http://localhost:5001/swagger` (hoặc `http://localhost:7211/swagger`)

---

## 👥 Nhóm phát triển

Dự án môn học **PRM392 — Mobile Application Development**  
Học kỳ 7 — FPT University
