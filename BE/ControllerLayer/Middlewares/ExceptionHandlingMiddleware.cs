using System.Net;
using System.Text.Json;
using ControllerLayer.Models;
using DomainLayer.Exceptions;

namespace ControllerLayer.Middlewares
{
    /// <summary>
    /// Middleware bắt tất cả unhandled exceptions trong pipeline.
    /// Trả về ApiResponse chuẩn — có trường code và không lộ stack trace khi production.
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
            if (!context.Response.Headers.ContainsKey("Access-Control-Allow-Origin"))
            {
                context.Response.Headers.Append("Access-Control-Allow-Origin", "*");
                context.Response.Headers.Append("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS");
                context.Response.Headers.Append("Access-Control-Allow-Headers", "*");
            }

            context.Response.ContentType = "application/json";

            var (statusCode, rawMessage, defaultCode) = ex switch
            {
                BadRequestException           => (HttpStatusCode.BadRequest,          ex.Message, "bad_request"),
                UnauthorizedException         => (HttpStatusCode.Unauthorized,        ex.Message, "unauthorized"),
                ForbiddenException            => (HttpStatusCode.Forbidden,           ex.Message, "forbidden"),
                NotFoundException             => (HttpStatusCode.NotFound,            ex.Message, "not_found"),
                ConflictException             => (HttpStatusCode.Conflict,            ex.Message, "conflict"),
                AccountLockedException        => ((HttpStatusCode)423,                ex.Message, "account_locked"),
                TooManyRequestsException      => ((HttpStatusCode)429,                ex.Message, "too_many_requests"),
                PayloadTooLargeException      => ((HttpStatusCode)413,                ex.Message, "payload_too_large"),
                UnsupportedMediaTypeException => ((HttpStatusCode)415,                ex.Message, "unsupported_media_type"),
                TrialExhaustedException       => ((HttpStatusCode)402,                ex.Message, "trial_exhausted"),
                ServiceUnavailableException   => ((HttpStatusCode)503,                ex.Message, "ai_unavailable"),
                ServerFailureException        => (HttpStatusCode.InternalServerError, _env.IsDevelopment() ? ex.Message : "Đã xảy ra lỗi, vui lòng thử lại sau.", "internal_server_error"),
                DomainException               => (HttpStatusCode.BadRequest,          ex.Message, "bad_request"),
                KeyNotFoundException          => (HttpStatusCode.NotFound,            _env.IsDevelopment() ? ex.Message : "Không tìm thấy dữ liệu.", "not_found"),
                UnauthorizedAccessException   => (HttpStatusCode.Unauthorized,        _env.IsDevelopment() ? ex.Message : "Chưa xác thực hoặc token không hợp lệ.", "unauthorized"),
                BadHttpRequestException { StatusCode: 413 } => ((HttpStatusCode)413,  "Dữ liệu gửi lên vượt quá dung lượng cho phép.", "payload_too_large"),
                BadHttpRequestException       => (HttpStatusCode.BadRequest,          "Dữ liệu yêu cầu HTTP hoặc JSON không hợp lệ.", "bad_request"),
                JsonException                 => (HttpStatusCode.BadRequest,          "Định dạng JSON gửi lên không hợp lệ.", "invalid_json"),
                ArgumentException             => (HttpStatusCode.BadRequest,          _env.IsDevelopment() ? ex.Message : "Dữ liệu yêu cầu không hợp lệ.", "bad_request"),
                InvalidOperationException     => (HttpStatusCode.BadRequest,          _env.IsDevelopment() ? ex.Message : "Thao tác không hợp lệ trong trạng thái hiện tại.", "bad_request"),
                _                             => (HttpStatusCode.InternalServerError, "Đã xảy ra lỗi, vui lòng thử lại sau.", "internal_server_error")
            };

            // Trích xuất error code nếu exception có chỉ định rõ
            var code = (ex is DomainException de && !string.IsNullOrWhiteSpace(de.ErrorCode))
                ? de.ErrorCode
                : defaultCode;

            context.Response.StatusCode = (int)statusCode;

            // Chỉ hiện chi tiết lỗi trong môi trường Development
            var detail = _env.IsDevelopment() ? ex.ToString() : null;

            var response = new
            {
                success    = false,
                message    = rawMessage,
                code       = code,
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
