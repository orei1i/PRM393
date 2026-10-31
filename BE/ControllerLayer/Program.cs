using ApplicationLayer.Interfaces;
using ApplicationLayer.Services;
using CloudinaryDotNet;
using ControllerLayer.Filters;
using ControllerLayer.Middlewares;
using DomainLayer.Interfaces;
using InfrastructureLayer.Configuration;
using InfrastructureLayer.Database;
using InfrastructureLayer.ExternalServices.Gemini;
using InfrastructureLayer.Repository;
using InfrastructureLayer.Seed;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
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

// ─── Controllers + Filters ────────────────────────────────────────────────────
builder.Services.AddControllers(options =>
{
    // Áp dụng ValidationFilter toàn bộ app — không cần gắn từng action
    options.Filters.Add<ValidationFilter>();
});

// B25: Chuẩn hoá lỗi ModelState thành envelope ApiResponse thống nhất
builder.Services.Configure<Microsoft.AspNetCore.Mvc.ApiBehaviorOptions>(options =>
{
    options.InvalidModelStateResponseFactory = context =>
    {
        var errors = context.ModelState
            .Where(e => e.Value?.Errors.Count > 0)
            .ToDictionary(
                kvp => kvp.Key,
                kvp => kvp.Value!.Errors.Select(e => e.ErrorMessage).ToArray()
            );
        var response = new ControllerLayer.Models.ApiResponse<object>
        {
            Success = false,
            StatusCode = StatusCodes.Status400BadRequest,
            Message = "Dữ liệu yêu cầu không hợp lệ.",
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

    // Swagger hỗ trợ JWT Bearer — chỉ cần paste token, Swagger tự thêm "Bearer "
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

// ─── CORS — cho phép Flutter gọi API ─────────────────────────────────────────
builder.Services.AddCors(options =>
{
    options.AddPolicy("MobilePolicy", policy =>
    {
        policy
            .AllowAnyOrigin()   // Flutter mobile không cần restrict origin
            .AllowAnyMethod()
            .AllowAnyHeader();
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
if (!builder.Environment.IsDevelopment())
{
    if (string.IsNullOrWhiteSpace(configuredJwtSecret) || configuredJwtSecret.Contains("PLACEHOLDER"))
    {
        throw new InvalidOperationException("CRITICAL: JwtSettings:SecretKey chưa được cấu hình hoặc vẫn mang giá trị placeholder!");
    }
}

var app = builder.Build();

// ─── Exception Handling (phải là middleware đầu tiên) ─────────────────────────

app.UseCors("MobilePolicy");
app.UseMiddleware<ExceptionHandlingMiddleware>();
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