using ApplicationLayer.Interfaces;
using ApplicationLayer.Services;
using CloudinaryDotNet;
using ControllerLayer.Filters;
using ControllerLayer.Middlewares;
using DomainLayer.Entities;
using DomainLayer.Interfaces;
using InfrastructureLayer.Configuration;
using InfrastructureLayer.Database;
using InfrastructureLayer.ExternalServices;
using InfrastructureLayer.ExternalServices.Gemini;
using InfrastructureLayer.Repository;
using InfrastructureLayer.Seed;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.RateLimiting;

// B12: Tạo sẵn thư mục wwwroot và uploads trước khi CreateBuilder khởi tạo web root
var webRoot = Path.Combine(Directory.GetCurrentDirectory(), "wwwroot");
Directory.CreateDirectory(Path.Combine(webRoot, "uploads", "images"));
Directory.CreateDirectory(Path.Combine(webRoot, "uploads", "videos"));

var builder = WebApplication.CreateBuilder(args);

builder.WebHost.ConfigureKestrel(options =>
{
    options.Limits.MaxRequestBodySize = 104_857_600; // 100 MB
});

// ─── In-Memory Cache (cho B54 Token Validation Cache) ──────────────────────────
builder.Services.AddMemoryCache();

// ─── Controllers + Filters ────────────────────────────────────────────────────
builder.Services.AddControllers(options =>
{
    // Áp dụng ValidationFilter toàn bộ app — không cần gắn từng action
    options.Filters.Add<ValidationFilter>();
});

// B25 & B64: Chuẩn hoá lỗi ModelState và JSON Parser thành envelope ApiResponse thống nhất
builder.Services.Configure<Microsoft.AspNetCore.Mvc.ApiBehaviorOptions>(options =>
{
    options.InvalidModelStateResponseFactory = context =>
    {
        // B64: lỗi của parser nằm ở khoá "$" hoặc "$.tenTruong", lời tiếng Anh của nó không được lọt ra ngoài.
        static bool IsParserKey(string key) => key == "$" || key.StartsWith("$.") || key.StartsWith("$[");
        static bool IsParserError(string key, Microsoft.AspNetCore.Mvc.ModelBinding.ModelError e) =>
            IsParserKey(key) ||
            e.ErrorMessage.Contains("JSON", StringComparison.OrdinalIgnoreCase) ||
            e.ErrorMessage.Contains("converted", StringComparison.OrdinalIgnoreCase) ||
            e.Exception is System.Text.Json.JsonException;

        var hasJsonError = context.ModelState.Any(kvp => kvp.Value!.Errors.Any(e => IsParserError(kvp.Key, e)));

        // JSON hỏng thì ASP.NET còn báo thêm "The request field is required" bằng tiếng Anh: bỏ, chỉ giữ lỗi JSON.
        var errors = context.ModelState
            .Where(e => e.Value?.Errors.Count > 0 && (!hasJsonError || e.Value.Errors.Any(x => IsParserError(e.Key, x))))
            .ToDictionary(
                kvp => kvp.Key,
                kvp => kvp.Value!.Errors.Select(e =>
                {
                    if (IsParserError(kvp.Key, e)) return "Định dạng JSON gửi lên không hợp lệ.";
                    if (e.ErrorMessage.Contains("non-empty request body", StringComparison.OrdinalIgnoreCase)) return "Thiếu nội dung yêu cầu.";
                    return string.IsNullOrWhiteSpace(e.ErrorMessage) ? "Dữ liệu không hợp lệ." : e.ErrorMessage;
                }).ToArray()
            );

        var response = new ControllerLayer.Models.ApiResponse<object>
        {
            Success = false,
            StatusCode = StatusCodes.Status400BadRequest,
            Code = hasJsonError ? "invalid_json" : "validation_error",
            Message = hasJsonError ? "Định dạng JSON gửi lên không hợp lệ." : "Dữ liệu yêu cầu không hợp lệ.",
            Errors = errors
        };
        return new Microsoft.AspNetCore.Mvc.BadRequestObjectResult(response);
    };
});

// ─── Swagger / OpenAPI ────────────────────────────────────────────────────────
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new Microsoft.OpenApi.Models.OpenApiInfo
    {
        Title   = "VeganLife API",
        Version = "v1"
    });

    c.AddSecurityDefinition("Bearer", new Microsoft.OpenApi.Models.OpenApiSecurityScheme
    {
        Name         = "Authorization",
        Type         = Microsoft.OpenApi.Models.SecuritySchemeType.Http,
        Scheme       = "bearer",
        BearerFormat = "JWT",
        In           = Microsoft.OpenApi.Models.ParameterLocation.Header,
        Description  = "Chỉ cần paste token (không cần gõ 'Bearer ')"
    });
    c.AddSecurityRequirement(new Microsoft.OpenApi.Models.OpenApiSecurityRequirement
    {
        {
            new Microsoft.OpenApi.Models.OpenApiSecurityScheme
            {
                Reference = new Microsoft.OpenApi.Models.OpenApiReference
                {
                    Type = Microsoft.OpenApi.Models.ReferenceType.SecurityScheme,
                    Id   = "Bearer"
                }
            },
            Array.Empty<string>()
        }
    });
});

// ─── CORS — cho phép Flutter & Web Admin gọi API (B65 WithExposedHeaders) ──────
builder.Services.AddCors(options =>
{
    options.AddPolicy("MobilePolicy", policy =>
    {
        policy
            .AllowAnyOrigin()
            .AllowAnyMethod()
            .AllowAnyHeader()
            .WithExposedHeaders("X-Total-Count", "X-Page", "X-Page-Size");
    });
});

// ─── JWT Authentication ───────────────────────────────────────────────────────
var jwtSettings = builder.Configuration.GetSection("JwtSettings");
var secretKey   = jwtSettings["SecretKey"] ?? throw new InvalidOperationException("JWT SecretKey chưa cấu hình.");

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer           = true,
            ValidateAudience         = true,
            ValidateLifetime         = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer              = jwtSettings["Issuer"],
            ValidAudience            = jwtSettings["Audience"],
            IssuerSigningKey         = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secretKey))
        };

        // B54: OnTokenValidated kiểm tra trạng thái hoạt động của User và cache 45 giây
        options.Events = new JwtBearerEvents
        {
            OnTokenValidated = async context =>
            {
                var userId = context.Principal?.FindFirst(ClaimTypes.NameIdentifier)?.Value
                             ?? context.Principal?.FindFirst(JwtRegisteredClaimNames.Sub)?.Value
                             ?? context.Principal?.FindFirst("sub")?.Value;

                if (string.IsNullOrEmpty(userId))
                {
                    context.Fail("Token không chứa thông tin định danh người dùng.");
                    return;
                }

                var cache = context.HttpContext.RequestServices.GetRequiredService<IMemoryCache>();
                var userRepo = context.HttpContext.RequestServices.GetRequiredService<IGenericRepository<User>>();

                var cacheKey = DomainLayer.Constants.UserCacheKeys.UserStatus(userId);
                if (!cache.TryGetValue(cacheKey, out (bool IsActive, string? Reason, string? Role) cachedStatus))
                {
                    try
                    {
                        var user = await userRepo.FindByIdAsync(userId);
                        if (user != null)
                        {
                            if (user.IsDeleted)
                            {
                                cachedStatus = (false, "Tài khoản không tồn tại hoặc đã bị xóa.", null);
                            }
                            else if (user.Status == DomainLayer.Enums.GeneralEnum.UserStatusEnum.Locked ||
                                     user.Status == DomainLayer.Enums.GeneralEnum.UserStatusEnum.Banned)
                            {
                                cachedStatus = (false, "Tài khoản đã bị tạm khóa hoặc cấm.", null);
                            }
                            else
                            {
                                cachedStatus = (true, null, user.Role);
                            }
                        }
                        else
                        {
                            // User không tìm thấy (ví dụ mock user trong integration test)
                            cachedStatus = (true, null, null);
                        }
                    }
                    catch
                    {
                        // Mongo offline hoặc connection timeout
                        cachedStatus = (true, null, null);
                    }

                    cache.Set(cacheKey, cachedStatus, TimeSpan.FromSeconds(45));
                }

                if (!cachedStatus.IsActive)
                {
                    context.Fail(cachedStatus.Reason ?? "Tài khoản không thể truy cập.");
                    return;
                }

                // Vai trò trong token phải khớp hiện tại: người vừa bị gỡ quyền admin không còn dùng được token cũ.
                var tokenRole = context.Principal?.FindFirst(ClaimTypes.Role)?.Value;
                if (cachedStatus.Role != null && !string.Equals(tokenRole, cachedStatus.Role, StringComparison.Ordinal))
                {
                    context.Fail("Vai trò của tài khoản đã thay đổi. Vui lòng đăng nhập lại.");
                }
            }
        };
    });

builder.Services.AddAuthorization();

// ─── MongoDB ──────────────────────────────────────────────────────────────────
builder.Services.AddSingleton<MongoDbContext>();
builder.Services.AddScoped(typeof(IGenericRepository<>), typeof(GenericRepository<>));

// ─── Cloudinary ───────────────────────────────────────────────────────────────
var cloudinarySettings = builder.Configuration.GetSection(CloudinarySettings.SectionName).Get<CloudinarySettings>() 
    ?? new CloudinarySettings();
var cloudinaryAccount = new Account(
    cloudinarySettings.CloudName,
    cloudinarySettings.ApiKey,
    cloudinarySettings.ApiSecret
);
var cloudinary = new Cloudinary(cloudinaryAccount);
cloudinary.Api.Secure = true;
builder.Services.AddSingleton(cloudinary);

// ─── Application Services ─────────────────────────────────────────────────────
builder.Services.AddScoped<IUserService, UserService>();
builder.Services.AddScoped<IAuthService, AuthService>();
builder.Services.AddScoped<IMediaService, MediaService>();
builder.Services.AddScoped<IPostService, PostService>();
builder.Services.AddScoped<ICommentService, CommentService>();
builder.Services.AddScoped<IHealthProfileService, HealthProfileService>();
builder.Services.AddScoped<IPantryService, PantryService>();
builder.Services.AddScoped<IMealPlanService, MealPlanService>();
builder.Services.AddScoped<IVisionService, VisionService>();
builder.Services.AddScoped<IRecipeService, RecipeService>();
builder.Services.AddScoped<IMealPlanAdjustService, MealPlanAdjustService>();

// Chưa có email thật. Lối đọc mã chỉ có ở Development và khi bật Auth:DevResetCodes.
builder.Services.AddSingleton<IPasswordResetNotifier>(sp =>
    sp.GetRequiredService<IHostEnvironment>().IsDevelopment()
    && string.Equals(sp.GetRequiredService<IConfiguration>()["Auth:DevResetCodes"], "true", StringComparison.OrdinalIgnoreCase)
        ? new DevResetCodeOutbox()
        : new NoPasswordResetNotifier());

// ─── Đặt chuyên gia, giữ tiền, ví, rút tiền, đơn ──────────────────────────────
builder.Services.AddSingleton<IClock, SystemClock>();
builder.Services.AddSingleton<ICommerceFailpoints, NoCommerceFailpoints>();
builder.Services.AddSingleton<IPaymentProvider>(sp => PaymentProviderFactory.Create(
    sp.GetRequiredService<IConfiguration>(),
    sp.GetRequiredService<IHostEnvironment>(),
    sp.GetRequiredService<ILoggerFactory>().CreateLogger("Payment")));
builder.Services.AddScoped<IBookingRepository, BookingRepository>();
builder.Services.AddScoped<IWalletRepository, WalletRepository>();
builder.Services.AddScoped<IWalletLedgerRepository, WalletLedgerRepository>();
builder.Services.AddScoped<IWithdrawalRepository, WithdrawalRepository>();
builder.Services.AddScoped<IWalletLedgerService, WalletLedgerService>();
builder.Services.AddScoped<IBookingEngine, BookingEngine>();
builder.Services.AddScoped<IBookingService, BookingService>();
builder.Services.AddScoped<IOrderPaymentService, OrderPaymentService>();
builder.Services.AddScoped<IWalletService, WalletService>();
builder.Services.AddScoped<IAdminMoneyService, AdminMoneyService>();
builder.Services.AddHostedService<CommerceSettlementHostedService>();

// ─── RAG & Chat ───────────────────────────────────────────────────────────────
// Kho tri thức nằm ở DB riêng (RagDatabaseName), không có tên mặc định.
builder.Services.AddSingleton<RagDbContext>();
builder.Services.AddSingleton<IKnowledgeRepository, KnowledgeRepository>();
builder.Services.AddSingleton<RagVectorIndex>();
builder.Services.AddSingleton<IDocumentTextExtractor, PdfPigTextExtractor>();
builder.Services.AddSingleton<ChatStreamRegistry>();
builder.Services.AddScoped<IChatStore, ChatStore>();
builder.Services.AddScoped<IKnowledgeService, KnowledgeService>();
builder.Services.AddScoped<IChatService, ChatService>();
builder.Services.AddScoped<AiModelGate>();

// Giới hạn /chat theo người dùng hoặc IP: đổi X-Guest-Token không lách được giới hạn này.
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.OnRejected = async (context, ct) =>
    {
        context.HttpContext.Response.ContentType = "application/json";
        await context.HttpContext.Response.WriteAsync(
            "{\"success\":false,\"message\":\"Bạn hỏi hơi nhanh, thử lại sau ít phút nhé.\",\"code\":\"too_many_requests\",\"statusCode\":429}", ct);
    };
    options.AddPolicy("chat", httpContext => RateLimitPartition.GetFixedWindowLimiter(
        httpContext.User.FindFirst(ClaimTypes.NameIdentifier)?.Value
            ?? httpContext.Connection.RemoteIpAddress?.ToString()
            ?? "unknown",
        _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = httpContext.RequestServices.GetRequiredService<IConfiguration>().GetValue("Rag:RateLimitPerMinute", 20),
            Window = TimeSpan.FromMinutes(1),
            QueueLimit = 0
        }));
});

// ─── Chuyên gia, quán ăn, vị trí, tìm kiếm, quảng cáo, video, trang quản trị ──
builder.Services.AddScoped<IChefRepository, ChefRepository>();
builder.Services.AddScoped<IRestaurantRepository, RestaurantRepository>();
builder.Services.AddScoped<IAdRepository, AdRepository>();
builder.Services.AddScoped<IVideoExtractionRepository, VideoExtractionRepository>();
builder.Services.AddScoped<IAdminContentRepository, AdminContentRepository>();
builder.Services.AddScoped<IAdminAuditService, AdminAuditService>();
builder.Services.AddScoped<IChefService, ChefService>();
builder.Services.AddScoped<IRestaurantService, RestaurantService>();
builder.Services.AddScoped<IGeoService, GeoService>();
builder.Services.AddScoped<ISearchService, SearchService>();
builder.Services.AddScoped<IAdService, AdService>();
builder.Services.AddScoped<IVideoService, VideoService>();
builder.Services.AddScoped<IAdminDashboardService, AdminDashboardService>();
builder.Services.AddScoped<IModerationService, ModerationService>();
builder.Services.AddScoped<IAdminAiService, AdminAiService>();
builder.Services.AddHttpClient<IGeocodingClient, NominatimGeocodingClient>();
builder.Services.AddHttpClient<IVideoContentReader, VideoContentReader>();
builder.Services.AddHostedService<VideoExtractionHostedService>();

// Route công khai có thể bị gọi lặp: giới hạn theo người dùng hoặc IP.
static RateLimitPartition<string> PerClient(HttpContext httpContext, string configKey, int defaultLimit) =>
    RateLimitPartition.GetFixedWindowLimiter(
        httpContext.User.FindFirst(ClaimTypes.NameIdentifier)?.Value
            ?? httpContext.Connection.RemoteIpAddress?.ToString()
            ?? "unknown",
        _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = httpContext.RequestServices.GetRequiredService<IConfiguration>().GetValue(configKey, defaultLimit),
            Window = TimeSpan.FromMinutes(1),
            QueueLimit = 0
        });
builder.Services.AddRateLimiter(options =>
{
    options.AddPolicy("geo", httpContext => PerClient(httpContext, "Geo:RateLimitPerMinute", 30));
    options.AddPolicy("ads", httpContext => PerClient(httpContext, "Ads:RateLimitPerMinute", 120));
});

// ─── Gemini AI Client ────────────────────────────────────────────────────────
builder.Services.Configure<GeminiSettings>(builder.Configuration.GetSection(GeminiSettings.SectionName));
builder.Services.AddHttpClient<IGeminiClient, GeminiClient>(client =>
{
    // Mô hình đôi lúc mất hơn 25 giây mới bắt đầu trả lời. Từng tác vụ tự đặt giới hạn riêng (quét ảnh 25 giây).
    client.Timeout = TimeSpan.FromSeconds(120);
});

// ─────────────────────────────────────────────────────────────────────────────
// ─── Kiểm tra an toàn khoá bí mật khi khởi động ─────────────────────────────
var configuredJwtSecret = builder.Configuration["JwtSettings:SecretKey"];
var configuredManagerPass = builder.Configuration["FranchiseOnboarding:DefaultManagerPassword"];
if (!builder.Environment.IsDevelopment())
{
    if (string.IsNullOrWhiteSpace(configuredJwtSecret) || configuredJwtSecret.Contains("PLACEHOLDER", StringComparison.OrdinalIgnoreCase))
    {
        throw new InvalidOperationException("CRITICAL: JwtSettings:SecretKey chưa được cấu hình hoặc vẫn mang giá trị placeholder!");
    }
    if (string.IsNullOrWhiteSpace(configuredManagerPass) || configuredManagerPass.Contains("PLACEHOLDER", StringComparison.OrdinalIgnoreCase))
    {
        throw new InvalidOperationException("CRITICAL: FranchiseOnboarding:DefaultManagerPassword chưa được cấu hình hoặc vẫn mang giá trị placeholder!");
    }
}

var app = builder.Build();

// ─── Exception Handling & CORS ────────────────────────────────────────────────
app.UseCors("MobilePolicy");
app.UseMiddleware<ExceptionHandlingMiddleware>();

// B63: Bọc 401/403/404 từ framework middleware vào envelope ApiResponse
app.UseStatusCodePages(async statusCodeContext =>
{
    var httpContext = statusCodeContext.HttpContext;
    var statusCode = httpContext.Response.StatusCode;

    if (statusCode == StatusCodes.Status401Unauthorized ||
        statusCode == StatusCodes.Status403Forbidden ||
        statusCode == StatusCodes.Status404NotFound ||
        statusCode == StatusCodes.Status405MethodNotAllowed)
    {
        httpContext.Response.ContentType = "application/json";

        var (message, code) = statusCode switch
        {
            StatusCodes.Status401Unauthorized => ("Chưa xác thực hoặc token không hợp lệ.", "unauthorized"),
            StatusCodes.Status403Forbidden => ("Không có quyền truy cập tài nguyên này.", "forbidden"),
            StatusCodes.Status404NotFound => ("Đường dẫn hoặc tài nguyên không tồn tại.", "not_found"),
            StatusCodes.Status405MethodNotAllowed => ("Đường dẫn này không hỗ trợ phương thức đã gửi.", "method_not_allowed"),
            _ => ("Yêu cầu không hợp lệ.", "bad_request")
        };

        var envelope = new
        {
            success = false,
            message = message,
            code = code,
            statusCode = statusCode
        };

        var json = System.Text.Json.JsonSerializer.Serialize(envelope, new System.Text.Json.JsonSerializerOptions
        {
            PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase
        });

        await httpContext.Response.WriteAsync(json);
    }
});

app.UseStaticFiles();

// ─── Swagger ──────────────────────────────────────────────────────────────────
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
    app.MapGet("/", () => Results.Redirect("/swagger"));
}

// ─── Pipeline ─────────────────────────────────────────────────────────────────
app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter();
app.MapControllers();

// ─── Khởi tạo chỉ mục MongoDB & Dữ liệu Seed ban đầu ──────────────────────────
try
{
    await app.Services.EnsureIndexesAsync();
    await app.Services.SeedAsync();
}
catch (Exception ex)
{
    var logger = app.Services.GetService<ILogger<Program>>();
    logger?.LogWarning(ex, "Không thể kết nối MongoDB lúc khởi động để tạo index/seed. Bỏ qua để ứng dụng tiếp tục.");
}

app.Run();

public partial class Program { }
