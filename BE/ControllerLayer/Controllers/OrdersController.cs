using System.Threading.Tasks;
using ApplicationLayer.DTOs.Commerce;
using ApplicationLayer.Interfaces;
using ControllerLayer.Authorization;
using ControllerLayer.Extensions;
using ControllerLayer.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace ControllerLayer.Controllers
{
    /// <summary>
    /// Đơn và thanh toán của người mua. Cố ý không có route webhook: chưa có cổng thật nên chưa có chữ ký để xác minh,
    /// và không route không xác thực nào được đánh dấu đơn đã trả.
    /// </summary>
    [Route("api/v1")]
    [ApiController]
    [Authorize]
    public class OrdersController : ControllerBase
    {
        private readonly IOrderPaymentService _payments;

        public OrdersController(IOrderPaymentService payments)
        {
            _payments = payments;
        }

        [HttpGet("orders/{id}")]
        public async Task<ActionResult<ApiResponse<OrderResponse>>> GetOrder(string id) =>
            Ok(ApiResponse<OrderResponse>.Ok(await _payments.GetOrderAsync(User.GetUserId(), id)));

        [HttpPost("orders/{id}/payments")]
        public async Task<ActionResult<ApiResponse<PaymentResponse>>> Renew(string id) =>
            Ok(ApiResponse<PaymentResponse>.Ok(await _payments.RenewPaymentAsync(User.GetUserId(), id)));

        [HttpPost("orders/{id}/wallet-payment")]
        public async Task<ActionResult<ApiResponse<OrderResponse>>> PayWithWallet(string id) =>
            Ok(ApiResponse<OrderResponse>.Ok(await _payments.PayWithWalletAsync(User.GetUserId(), id)));

        [HttpGet("payments/{id}")]
        public async Task<ActionResult<ApiResponse<PaymentResponse>>> GetPayment(string id) =>
            Ok(ApiResponse<PaymentResponse>.Ok(await _payments.GetPaymentAsync(User.GetUserId(), id)));

        /// <summary>
        /// CỔNG THỬ NGHIỆM, không có tiền thật. Chỉ tồn tại khi Payment:Provider=Sandbox (không thì 404).
        /// Admin xác nhận được mọi giao dịch. Người mua tự xác nhận giao dịch của mình chỉ khi bật
        /// Payment:SandboxSelfConfirm (bản demo, không có ai đóng vai cổng thanh toán).
        /// </summary>
        [HttpPost("payments/{id}/sandbox-confirm")]
        public async Task<ActionResult<ApiResponse<PaymentResponse>>> SandboxConfirm(
            string id,
            [FromBody] SandboxConfirmRequest request,
            [FromServices] Microsoft.Extensions.Configuration.IConfiguration configuration)
        {
            var isAdmin = User.IsInRole(AppRoles.Admin);
            if (!isAdmin && !configuration.GetValue("Payment:SandboxSelfConfirm", false))
            {
                throw new DomainLayer.Exceptions.ForbiddenException("Không có quyền truy cập tài nguyên này.", "forbidden");
            }
            return Ok(ApiResponse<PaymentResponse>.Ok(await _payments.SandboxConfirmAsync(id, request.Success, isAdmin ? null : User.GetUserId())));
        }
    }
}
