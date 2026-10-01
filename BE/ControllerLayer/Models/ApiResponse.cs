namespace ControllerLayer.Models
{
    /// <summary>
    /// Wrapper response chuẩn cho tất cả API — Flutter parse nhất quán.
    /// </summary>
    public class ApiResponse<T>
    {
        public bool Success { get; set; }
        public string? Message { get; set; }
        public T? Data { get; set; }
        public int StatusCode { get; set; }

        // ─── Static factory methods ──────────────────────────────────────

        public static ApiResponse<T> Ok(T data, string? message = null) => new()
        {
            Success    = true,
            Data       = data,
            Message    = message,
            StatusCode = 200
        };

        public static ApiResponse<T> Created(T data, string? message = "Tạo mới thành công.") => new()
        {
            Success    = true,
            Data       = data,
            Message    = message,
            StatusCode = 201
        };

        public static ApiResponse<T> Fail(string message, int statusCode = 400) => new()
        {
            Success    = false,
            Message    = message,
            Data       = default,
            StatusCode = statusCode
        };

        public static ApiResponse<T> NotFound(string message = "Không tìm thấy dữ liệu.") => new()
        {
            Success    = false,
            Message    = message,
            Data       = default,
            StatusCode = 404
        };

        public static ApiResponse<T> Unauthorized(string message = "Không có quyền truy cập.") => new()
        {
            Success    = false,
            Message    = message,
            Data       = default,
            StatusCode = 401
        };
    }
}
