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
await app.Services.EnsureIndexesAsync();
await app.Services.SeedAsync();

app.Run();