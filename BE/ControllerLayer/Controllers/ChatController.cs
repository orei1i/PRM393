using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Chat;
using ApplicationLayer.Interfaces;
using ControllerLayer.Extensions;
using ControllerLayer.Models;
using DomainLayer.Exceptions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace ControllerLayer.Controllers
{
    [ApiController]
    [Route("api/v1/chat")]
    [AllowAnonymous]
    [EnableRateLimiting("chat")]
    public class ChatController : ControllerBase
    {
        private static readonly JsonSerializerOptions SseJson = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

        private readonly IChatService _chat;

        public ChatController(IChatService chat)
        {
            _chat = chat;
        }

        /// <summary>Số câu hỏi miễn phí còn lại của khách (header X-Guest-Token).</summary>
        [HttpGet("guest-trial")]
        [ProducesResponseType(typeof(ApiResponse<GuestTrialResponse>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<GuestTrialResponse>>> GetGuestTrial()
        {
            var result = await _chat.GetGuestTrialAsync(Request.Headers["X-Guest-Token"].ToString());
            return Ok(ApiResponse<GuestTrialResponse>.Ok(result));
        }

        /// <summary>Lịch sử của một phiên. Chỉ chủ phiên đọc được.</summary>
        [HttpGet("sessions/{sessionId}/messages")]
        [ProducesResponseType(typeof(ApiResponse<List<ChatHistoryMessage>>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<List<ChatHistoryMessage>>>> GetHistory(string sessionId)
        {
            var result = await _chat.GetHistoryAsync(Caller(), sessionId);
            return Ok(ApiResponse<List<ChatHistoryMessage>>.Ok(result));
        }

        /// <summary>
        /// Gửi câu hỏi, trả SSE với các sự kiện citation, token, done, error.
        /// Lỗi trước sự kiện đầu tiên là mã HTTP thường (402 hết lượt, 503 AI chưa sẵn sàng);
        /// sau đó không đổi được mã HTTP nữa nên lỗi là sự kiện error.
        /// </summary>
        [HttpPost("sessions/{sessionId}/messages")]
        [Produces("text/event-stream")]
        public async Task PostMessage(string sessionId, [FromBody] ChatMessageRequest request, CancellationToken ct)
        {
            var caller = Caller();
            await using var events = _chat.StreamReplyAsync(caller, sessionId, request, ct).GetAsyncEnumerator(ct);

            // Exception ở đây chưa gửi header nên ExceptionHandlingMiddleware vẫn trả được mã lỗi thật.
            var hasFirst = await events.MoveNextAsync();

            Response.StatusCode = StatusCodes.Status200OK;
            Response.ContentType = "text/event-stream; charset=utf-8";
            Response.Headers.CacheControl = "no-cache";
            Response.Headers["X-Accel-Buffering"] = "no";
            await Response.Body.FlushAsync(ct);

            if (!hasFirst) return;

            try
            {
                do
                {
                    await WriteEventAsync(events.Current, ct);
                }
                while (await MoveNextOrReportAsync(events, ct));
            }
            catch (System.OperationCanceledException) when (ct.IsCancellationRequested)
            {
                // App huỷ hoặc mất kết nối. Service đã lưu phần đã sinh để resumeFrom chạy tiếp.
            }
        }

        private async Task<bool> MoveNextOrReportAsync(IAsyncEnumerator<ChatSseEvent> events, CancellationToken ct)
        {
            try
            {
                return await events.MoveNextAsync();
            }
            catch (System.OperationCanceledException)
            {
                return false;
            }
            catch (DomainException ex)
            {
                await WriteEventAsync(new ChatSseEvent("error", new { code = ex.ErrorCode ?? "model_unavailable", message = ex.Message }), ct);
                return false;
            }
        }

        private async Task WriteEventAsync(ChatSseEvent evt, CancellationToken ct)
        {
            var data = JsonSerializer.Serialize(evt.Data, evt.Data.GetType(), SseJson);
            await Response.WriteAsync($"event: {evt.Name}\ndata: {data}\n\n", ct);
            await Response.Body.FlushAsync(ct);
        }

        /// <summary>
        /// Token hỏng hoặc hết hạn thì trả 401 để app làm mới phiên, không âm thầm coi là khách
        /// (nếu không, thành viên sẽ bị tính lượt dùng thử).
        /// </summary>
        private ChatCaller Caller()
        {
            var userId = User.GetUserIdOrDefault();
            if (userId == null && Request.Headers.Authorization.Any(h => !string.IsNullOrWhiteSpace(h)))
            {
                throw new UnauthorizedException("Phiên đăng nhập đã hết hạn.");
            }

            return new ChatCaller
            {
                UserId = userId,
                GuestToken = userId == null ? Request.Headers["X-Guest-Token"].ToString() : null
            };
        }
    }
}
