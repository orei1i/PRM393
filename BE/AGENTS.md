# 🤖 AGENTS.md — VeganLife Backend Context for AI Assistants

> **Đọc file này trước khi làm bất kỳ thứ gì trong project.**
> File này mô tả kiến trúc, convention, pattern và quy tắc code của VeganLife Backend.
> Tuân thủ tuyệt đối để tránh phá vỡ tính nhất quán của project.

---

## 1. Tổng Quan Project

| Thông tin | Giá trị |
|-----------|---------|
| **Tên project** | VeganLife Backend |
| **Runtime** | .NET 9.0 |
| **Kiến trúc** | Clean Architecture (4 layers) |
| **Database chính** | MongoDB 8.0 — `VeganLifeDB` |
| **Cache** | Redis (StackExchange.Redis 2.10.1) — chưa implement service |
| **Client** | Flutter mobile app |
| **API style** | RESTful, JSON, versioned (`/api/v1/`) |
| **Auth** | JWT Bearer + Google OAuth 2.0 |
| **Container** | Docker + docker-compose |

---

## 2. Kiến Trúc — Clean Architecture

```
ControllerLayer   ← Entry point: HTTP, Middleware, Filters, Controllers
      ↓ depends on
ApplicationLayer  ← Business logic: Services, DTOs, Interfaces
      ↓ depends on
DomainLayer       ← Core: Entities, Enums, Exceptions, Interfaces (không phụ thuộc ai)
      ↑ depends on
InfrastructureLayer ← DB, Repository, External libs (depends on DomainLayer)
```

### Quy tắc phụ thuộc (KHÔNG được vi phạm):
- `DomainLayer` **không được** import bất kỳ layer nào khác
- `ApplicationLayer` **không được** import `InfrastructureLayer`
- `InfrastructureLayer` **không được** import `ApplicationLayer`
- `ControllerLayer` được phép import tất cả (entry point)

---

## 3. Cấu Trúc Thư Mục

```
BE/
├── DomainLayer/
│   ├── Entities/          ← Tất cả MongoDB document models (kế thừa BaseEntity)
│   ├── Enums/             ← Tất cả enum của project
│   ├── Exceptions/        ← Custom exception hierarchy
│   ├── Interfaces/        ← IEntity, IGenericRepository<T>
│   ├── Constants/         ← Hằng số toàn app
│   └── Helpers/           ← Pure utility functions (không inject DI)
│
├── ApplicationLayer/
│   ├── DTOs/
│   │   ├── Auth/          ← AuthResponse, LoginRequest, RegisterRequest...
│   │   └── [Module]/      ← Mỗi module có folder DTO riêng
│   ├── Interfaces/        ← IXxxService (contract cho mỗi service)
│   └── Services/          ← XxxService (implement IXxxService)
│
├── InfrastructureLayer/
│   ├── Database/          ← MongoDbContext.cs (kết nối MongoDB, expose collections)
│   └── Repository/        ← GenericRepository<T> (implement IGenericRepository)
│
├── ControllerLayer/
│   ├── Controllers/       ← XxxController.cs (HTTP endpoints)
│   ├── Middlewares/       ← ExceptionHandlingMiddleware
│   ├── Filters/           ← ValidationFilter (global ModelState)
│   ├── Authorization/     ← AppRoles constants
│   ├── Models/            ← ApiResponse<T> wrapper
│   └── Program.cs         ← DI registration + middleware pipeline
│
├── docker-compose.yml     ← MongoDB + Redis + API containers
└── AGENTS.md              ← File này
```

---

## 4. Quy Tắc Tạo Feature Mới

Mỗi khi thêm một module mới (ví dụ: `Product`), PHẢI làm đủ 6 bước theo thứ tự:

### Bước 1 — Domain Layer: Tạo Entity
```csharp
// DomainLayer/Entities/Product.cs
public class Product : BaseEntity   // PHẢI kế thừa BaseEntity
{
    public string Name { get; set; } = string.Empty;
    // ... các field khác
}
```

### Bước 2 — Infrastructure Layer: Expose Collection
```csharp
// InfrastructureLayer/Database/MongoDbContext.cs — THÊM collection mới
public IMongoCollection<Product> Products
    => _database.GetCollection<Product>("Products");
```

### Bước 3 — Application Layer: Tạo DTOs
```
ApplicationLayer/DTOs/Products/
├── ProductRequestDto.cs   ← CreateProductRequest, UpdateProductRequest (có DataAnnotations)
└── ProductResponseDto.cs  ← ProductResponse (chỉ expose field cần thiết cho client)
```

### Bước 4 — Application Layer: Tạo Interface + Service
```csharp
// ApplicationLayer/Interfaces/IProductService.cs
public interface IProductService
{
    Task<IEnumerable<ProductResponse>> GetAllAsync();
    Task<ProductResponse?> GetByIdAsync(string id);
    Task<ProductResponse> CreateAsync(CreateProductRequest request);
    Task<ProductResponse> UpdateAsync(string id, UpdateProductRequest request);
    Task<bool> DeleteAsync(string id);
}

// ApplicationLayer/Services/ProductService.cs
public class ProductService : IProductService
{
    private readonly IGenericRepository<Product> _repo;
    // Inject thêm repository khác nếu cần (KHÔNG inject DbContext trực tiếp)
}
```

### Bước 5 — Controller Layer: Tạo Controller
```csharp
// ControllerLayer/Controllers/ProductsController.cs
[Route("api/v1/[controller]")]
[ApiController]
public class ProductsController : ControllerBase
{
    // Inject IProductService — KHÔNG inject Repository trực tiếp vào Controller
}
```

### Bước 6 — DI Registration trong Program.cs
```csharp
// Thêm vào phần "Application Services" trong Program.cs
builder.Services.AddScoped<IProductService, ProductService>();
// GenericRepository<T> đã đăng ký global — không cần đăng ký thêm
```

---

## 5. Conventions & Coding Standards

### Naming Convention

| Loại | Pattern | Ví dụ |
|------|---------|-------|
| Entity | `PascalCase` | `User`, `Product`, `Order` |
| DTO Request | `[Action][Entity]Request` | `CreateProductRequest`, `UpdateUserRequest` |
| DTO Response | `[Entity]Response` | `UserResponse`, `ProductResponse` |
| Service Interface | `I[Entity]Service` | `IUserService`, `IProductService` |
| Service Implementation | `[Entity]Service` | `UserService`, `ProductService` |
| Controller | `[Entity]sController` | `UsersController`, `ProductsController` |
| Repository | Dùng `IGenericRepository<T>` | Generic, không tạo riêng trừ khi cần query phức tạp |

### API Route Convention
```
GET    /api/v1/products          ← Lấy danh sách
GET    /api/v1/products/{id}     ← Lấy theo id
POST   /api/v1/products          ← Tạo mới
PUT    /api/v1/products/{id}     ← Cập nhật
DELETE /api/v1/products/{id}     ← Xóa (soft delete)
```

### Response Format — BẮT BUỘC dùng ApiResponse<T>
```csharp
// ĐÚNG
return Ok(ApiResponse<ProductResponse>.Ok(product));
return Ok(ApiResponse<ProductResponse>.Created(product));
return NotFound(ApiResponse<ProductResponse>.NotFound($"Không tìm thấy product: {id}"));

// SAI — không trả raw object
return Ok(product);
return NotFound();
```

### Soft Delete — BẮT BUỘC (không hard delete)
```csharp
// ĐÚNG — soft delete
entity.IsDeleted = true;
entity.DeletedAt = DateTime.UtcNow;
entity.UpdatedAt = DateTime.UtcNow;
await _repo.UpdateAsync(id, entity);

// SAI — không dùng DeleteAsync trừ khi có lý do đặc biệt
await _repo.DeleteAsync(id);
```

### Filter IsDeleted khi query
```csharp
// ĐÚNG — luôn filter IsDeleted
var items = await _repo.GetAllAsync();
return items.Where(x => !x.IsDeleted);

// ĐÚNG — khi FindById cũng phải check
var item = await _repo.FindByIdAsync(id);
if (item == null || item.IsDeleted) return null;
```

### Exception — dùng Domain Exceptions (không throw Exception thô)
```csharp
// ĐÚNG
throw new NotFoundException($"Không tìm thấy product với id: {id}");
throw new ConflictException("Email đã tồn tại.");
throw new BadRequestException("Dữ liệu không hợp lệ.");

// SAI
throw new Exception("Not found");
return BadRequest("lỗi");   // bỏ qua ExceptionHandlingMiddleware
```

### Async/Await — tất cả I/O phải async
```csharp
// ĐÚNG
public async Task<ProductResponse> GetByIdAsync(string id) { ... }

// SAI
public ProductResponse GetById(string id) { ... }
```

---

## 6. BaseEntity — Fields Chuẩn

Mọi MongoDB Document Entity PHẢI kế thừa BaseEntity:

```csharp
public abstract class BaseEntity : IEntity
{
    [BsonId]
    [BsonRepresentation(BsonType.ObjectId)]
    public string Id { get; set; }          // MongoDB ObjectId — string dạng hex

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? UpdatedAt { get; set; } = DateTime.UtcNow;
    public bool IsDeleted { get; set; } = false;
    public DateTime? DeletedAt { get; set; }
}
```

- `Id` luôn là `string` (không dùng `ObjectId` trực tiếp)
- Tất cả DateTime dùng UTC (`DateTime.UtcNow`)

---

## 7. Authentication & Authorization

### JWT Config (appsettings.json)
```json
"JwtSettings": {
  "SecretKey": "...",
  "Issuer": "VeganLifeAuthService",
  "Audience": "VeganLifeClients",
  "ExpiryMinutes": 60,
  "RefreshTokenExpiryDays": 7
}
```

### Roles — chỉ dùng AppRoles constants
```csharp
// ĐÚNG
[Authorize(Roles = AppRoles.Admin)]
[Authorize(Roles = AppRoles.Member)]
[Authorize(Roles = AppRoles.AdminOrMember)]

// SAI — hardcode string
[Authorize(Roles = "Admin")]
```

### Roles hiện có
| Role | Mô tả |
|------|-------|
| `Admin` | Quản trị viên hệ thống |
| `Member` | Người dùng thông thường |

### Google OAuth
- Field `User.GoogleId` lưu sub từ Google token
- Field `User.AuthType` = `AuthTypeEnum.Google` để phân biệt với login thường
- Khi Google login: không set `PasswordHash`

---

## 8. MongoDB — IGenericRepository<T>

```csharp
// Interface có sẵn — dùng cho mọi entity
Task<T> CreateAsync(T entity);
Task<T?> FindByIdAsync(string id);
Task<IEnumerable<T>> FindAsync(Expression<Func<T, bool>> predicate);
Task<T?> FirstOrDefaultAsync(Expression<Func<T, bool>> predicate);
Task UpdateAsync(string id, T entity);
Task DeleteAsync(string id);
Task<IEnumerable<T>> GetAllAsync();
```

Inject trong Service:
```csharp
public class ProductService : IProductService
{
    private readonly IGenericRepository<Product> _productRepo;

    public ProductService(IGenericRepository<Product> productRepo)
    {
        _productRepo = productRepo;
    }
}
```

> Nếu cần query phức tạp (aggregation): tạo IProductRepository : IGenericRepository<Product>
> và implement trong InfrastructureLayer/Repository/.

---

## 9. DTOs — Quy Tắc

### Request DTO — BẮT BUỘC có DataAnnotations
```csharp
public class CreateProductRequest
{
    [Required(ErrorMessage = "Tên sản phẩm là bắt buộc.")]
    [MaxLength(200, ErrorMessage = "Tên không được vượt quá 200 ký tự.")]
    public string Name { get; set; } = string.Empty;

    [Required(ErrorMessage = "Giá là bắt buộc.")]
    [Range(0, double.MaxValue, ErrorMessage = "Giá phải >= 0.")]
    public decimal Price { get; set; }
}
```

### Response DTO — chỉ expose field cần thiết
```csharp
// ĐÚNG — không expose PasswordHash, GoogleId nội bộ...
public class ProductResponse
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public decimal Price { get; set; }
    public DateTime CreatedAt { get; set; }
}
```

### Mapping — dùng private static method (không dùng AutoMapper cho CRUD đơn giản)
```csharp
private static ProductResponse MapToResponse(Product p) => new()
{
    Id        = p.Id,
    Name      = p.Name,
    Price     = p.Price,
    CreatedAt = p.CreatedAt
};
```

AutoMapper đã cài (v16.1.1) — dùng khi mapping phức tạp hoặc nhiều fields.

---

## 10. Enums — Vị Trí & Sử Dụng

Tất cả enums đặt trong DomainLayer/Enums/. Các enums hiện có:

| File | Enums |
|------|-------|
| `GeneralEnum.cs` | `UserStatusEnum`, `AuthTypeEnum`, `OrderStatusEnum`, `OrderTypeEnum`, `PaymentMethodEnum`, `PaymentStatusEnum`, `DiscountType`, `TransactionType`, `PromotionType` |
| `PriceStatus.cs` | Trạng thái giá |
| `SupplierStatus.cs` | Trạng thái nhà cung cấp |
| `UnitOfMeasure.cs` | Đơn vị đo lường |
| `UnitType.cs` | Loại đơn vị |

> Khi thêm enum mới: nếu thuộc module chung → thêm vào GeneralEnum.cs. Nếu chuyên biệt → tạo file riêng.

---

## 11. External Services — Config & Trạng Thái

| Service | Config Key | Package | Trạng thái |
|---------|-----------|---------|-----------|
| **MongoDB** | `ConnectionStrings:MongoConnection`, `DatabaseName` | `MongoDB.Driver` | Hoạt động |
| **Redis** | *(chưa có config key)* | `StackExchange.Redis` | Package cài sẵn, chưa implement |
| **JWT** | `JwtSettings` | `Microsoft.AspNetCore.Authentication.JwtBearer` | Hoạt động |
| **Google OAuth** | `GoogleClientId`, `GoogleClientSecret` | `Microsoft.AspNetCore.Authentication.Google` | Config sẵn, chưa implement |
| **Email** | `Email` (SmtpServer, Port, Username, Password) | `MailKit` + `MimeKit` | Package cài sẵn, chưa implement |
| **Cloudinary** | `Cloudinary` (CloudName, ApiKey, ApiSecret) | `CloudinaryDotNet` | Package cài sẵn, chưa implement |
| **MoMo** | `MoMo` | gọi REST trực tiếp | Config sẵn, chưa implement |
| **VNPay** | `VNPay` | gọi REST trực tiếp | Config sẵn, chưa implement |
| **Gemini AI** | `Gemini:ApiKey`, `Gemini:Model` | gọi REST trực tiếp | Config sẵn, chưa implement |
| **PDF** | — | `QuestPDF` + `PuppeteerSharp` | Package cài sẵn, chưa implement |
| **BCrypt** | — | `BCrypt.Net-Next` | Dùng khi implement AuthService |

---

## 12. Exception Handling — Cơ Chế Hoạt Động

ExceptionHandlingMiddleware tự động bắt exception và trả về ApiResponse chuẩn:

| Exception | HTTP Status |
|-----------|------------|
| `KeyNotFoundException` | 404 Not Found |
| `UnauthorizedAccessException` | 401 Unauthorized |
| `ArgumentException` | 400 Bad Request |
| `InvalidOperationException` | 400 Bad Request |
| `Exception` (mọi loại khác) | 500 Internal Server Error |

> Development: trả về `detail` chứa stack trace.
> Production: `detail` = null.

---

## 13. DI Registration Pattern (Program.cs)

```csharp
// MongoDB
builder.Services.AddSingleton<MongoDbContext>();
builder.Services.AddScoped(typeof(IGenericRepository<>), typeof(GenericRepository<>));

// Application Services
builder.Services.AddScoped<IUserService, UserService>();
builder.Services.AddScoped<IProductService, ProductService>();  // Thêm service mới ở đây

// External Services (khi implement)
// builder.Services.AddSingleton<IConnectionMultiplexer>(...);  // Redis
// builder.Services.AddScoped<IEmailService, EmailService>();
// builder.Services.AddScoped<ICloudinaryService, CloudinaryService>();
```

Lifetime rules:
- `Singleton` — connection (MongoDbContext, Redis multiplexer)
- `Scoped` — Services, Repositories (mặc định)
- `Transient` — chỉ dùng khi service rất nhẹ và stateless

---

## 14. Middleware Pipeline Order (KHÔNG thay đổi thứ tự)

```csharp
app.UseMiddleware<ExceptionHandlingMiddleware>();  // 1. Phải là đầu tiên
app.UseSwagger();                                  // 2. Swagger (dev only)
app.UseSwaggerUI();
app.UseHttpsRedirection();                         // 3. HTTPS redirect
app.UseCors("MobilePolicy");                       // 4. CORS trước Auth
app.UseAuthentication();                           // 5. Auth trước Authorization
app.UseAuthorization();                            // 6.
app.MapControllers();                              // 7. Route
```

---

## 15. Module Roadmap (Dự kiến)

| Module | Entity cần tạo | Service cần tạo | Trạng thái |
|--------|---------------|----------------|-----------|
| **Auth** | (dùng User) | `AuthService` | Chưa có |
| **User** | `User` | `UserService` | Cơ bản done |
| **Product/Menu** | `Product`, `Category` | `ProductService` | Chưa có |
| **Order** | `Order`, `OrderItem` | `OrderService` | Chưa có |
| **Payment** | `Payment` | `PaymentService` | Chưa có |
| **Inventory** | `Ingredient`, `StockTransaction` | `InventoryService` | Chưa có |
| **Promotion** | `Promotion`, `Coupon` | `PromotionService` | Chưa có |
| **Report** | — | `ReportService` | Chưa có |
| **Email/Notification** | — | `EmailService` | Chưa có |

---

*Cập nhật lần cuối: 2026-09-29 | VeganLife Team*
