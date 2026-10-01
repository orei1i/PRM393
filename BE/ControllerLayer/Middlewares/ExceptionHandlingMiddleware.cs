using System.Net;
using System.Text.Json;
using ControllerLayer.Models;

namespace ControllerLayer.Middlewares
{
    /// <summary>
    /// Middleware bắt tất cả unhandled exceptions trong pipeline.
    /// Trả về ApiResponse chuẩn — không lộ stack trace khi production.
    /// </summary>
    public class ExceptionHandlingMiddleware
    {
        private readonly RequestDelegate _next;
        private readonly ILogger<ExceptionHandlingMiddleware> _logger;
        private readonly IWebHostEnvironment _env;

        public ExceptionHandlingMiddleware(
            RequestDelegate next,
            ILogger<ExceptionHandlingMiddleware> logger,
            IWebHostEnvironment env)
        {
            _next   = next;
            _logger = logger;
            _env    = env;
        }

        public async Task InvokeAsync(HttpContext context)
        {
            try
            {
                await _next(context);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Unhandled exception: {Message}", ex.Message);
                await HandleExceptionAsync(context, ex);
            }
        }

        private async Task HandleExceptionAsync(HttpContext context, Exception ex)
        {
            context.Response.ContentType = "application/json";

            var (statusCode, message) = ex switch
            {
                KeyNotFoundException     => (HttpStatusCode.NotFound,           ex.Message),
                UnauthorizedAccessException => (HttpStatusCode.Unauthorized,    ex.Message),
                ArgumentException        => (HttpStatusCode.BadRequest,         ex.Message),
                InvalidOperationException => (HttpStatusCode.BadRequest,        ex.Message),
                _                        => (HttpStatusCode.InternalServerError,"Đã xảy ra lỗi, vui lòng thử lại sau.")
            };

            context.Response.StatusCode = (int)statusCode;

            // Chỉ hiện chi tiết lỗi trong môi trường Development
            var detail = _env.IsDevelopment() ? ex.ToString() : null;

            var response = new
            {
                success    = false,
                message    = message,
                statusCode = (int)statusCode,
                detail     = detail
            };

            var json = JsonSerializer.Serialize(response, new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase
            });

            await context.Response.WriteAsync(json);
        }
    }
}
