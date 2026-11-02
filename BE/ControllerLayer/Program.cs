using ApplicationLayer.Interfaces;
using ApplicationLayer.Services;
using CloudinaryDotNet;
using ControllerLayer.Filters;
using ControllerLayer.Middlewares;
using DomainLayer.Entities;
using DomainLayer.Interfaces;
using InfrastructureLayer.Configuration;
using InfrastructureLayer.Database;
using InfrastructureLayer.ExternalServices.Gemini;
using InfrastructureLayer.Repository;
using InfrastructureLayer.Seed;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;

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
        var hasJsonError = context.ModelState.Values.Any(v => v.Errors.Any(e =>
            e.ErrorMessage.Contains("JSON", StringComparison.OrdinalIgnoreCase) ||
            e.ErrorMessage.Contains("converted", StringComparison.OrdinalIgnoreCase) ||
            e.Exception is System.Text.Json.JsonException));

        var errors = context.ModelState
            .Where(e => e.Value?.Errors.Count > 0)
            .ToDictionary(
                kvp => kvp.Key,
                kvp => kvp.Value!.Errors.Select(e =>
                {
                    if (e.ErrorMessage.Contains("JSON", StringComparison.OrdinalIgnoreCase) ||
                        e.ErrorMessage.Contains("converted", StringComparison.OrdinalIgnoreCase) ||
                        e.Exception is System.Text.Json.JsonException)
                    {
                        return "Định dạng JSON gửi lên không hợp lệ.";
                    }
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
                if (!cache.TryGetValue(cacheKey, out (bool IsActive, string? Reason) cachedStatus))
                {
                    try
                    {
                        var user = await userRepo.FindByIdAsync(userId);
                        if (user != null)
                        {
                            if (user.IsDeleted)
                            {
                                cachedStatus = (false, "Tài khoản không tồn tại hoặc đã bị xóa.");
                            }
                            else if (user.Status == DomainLayer.Enums.GeneralEnum.UserStatusEnum.Locked ||
                                     user.Status == DomainLayer.Enums.GeneralEnum.UserStatusEnum.Banned)
                            {
                                cachedStatus = (false, "Tài khoản đã bị tạm khóa hoặc cấm.");
                            }
                            else
                            {
                                cachedStatus = (true, null);
                            }
                        }
                        else
                        {
                            // User không tìm thấy (ví dụ mock user trong integration test)
                            cachedStatus = (true, null);
                        }
                    }
                    catch
                    {
                        // Mongo offline hoặc connection timeout
                        cachedStatus = (true, null);
                    }

                    cache.Set(cacheKey, cachedStatus, TimeSpan.FromSeconds(45));
                }

                if (!cachedStatus.IsActive)
                {
                    context.Fail(cachedStatus.Reason ?? "Tài khoản không thể truy cập.");
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

// ─── Gemini AI Client ────────────────────────────────────────────────────────
builder.Services.Configure<GeminiSettings>(builder.Configuration.GetSection(GeminiSettings.SectionName));
builder.Services.AddHttpClient<IGeminiClient, GeminiClient>(client =>
{
    client.Timeout = TimeSpan.FromSeconds(25);
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
        statusCode == StatusCodes.Status404NotFound)
    {
        httpContext.Response.ContentType = "application/json";

        var (message, code) = statusCode switch
        {
            StatusCodes.Status401Unauthorized => ("Chưa xác thực hoặc token không hợp lệ.", "unauthorized"),
            StatusCodes.Status403Forbidden => ("Không có quyền truy cập tài nguyên này.", "forbidden"),
            StatusCodes.Status404NotFound => ("Đường dẫn hoặc tài nguyên không tồn tại.", "not_found"),
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
