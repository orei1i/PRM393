using System.Collections.Generic;
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
    /// <summary>Khiếu nại, giữ tiền, đơn, rút tiền và ví ở Web admin. Thiếu token 401, không phải Admin 403.</summary>
    [Route("api/v1/admin")]
    [ApiController]
    [Authorize(Roles = AppRoles.Admin)]
    public class AdminMoneyController : ControllerBase
    {
        private readonly IAdminMoneyService _admin;

        public AdminMoneyController(IAdminMoneyService admin)
        {
            _admin = admin;
        }

        [HttpGet("complaints")]
        public async Task<ActionResult<ApiResponse<List<AdminComplaintResponse>>>> Complaints([FromQuery] string? status, [FromQuery] string? search) =>
            Ok(ApiResponse<List<AdminComplaintResponse>>.Ok(await _admin.ListComplaintsAsync(status, search)));

        [HttpGet("complaints/{id}")]
        public async Task<ActionResult<ApiResponse<AdminComplaintResponse>>> Complaint(string id) =>
            Ok(ApiResponse<AdminComplaintResponse>.Ok(await _admin.GetComplaintAsync(id)));

        [HttpPost("complaints/{id}/decision")]
        public async Task<ActionResult<ApiResponse<AdminComplaintResponse>>> Decide(string id, [FromBody] AdminDecisionRequest request) =>
            Ok(ApiResponse<AdminComplaintResponse>.Ok(await _admin.DecideComplaintAsync(User.GetUserId(), id, request)));

        [HttpGet("escrow/summary")]
        public async Task<ActionResult<ApiResponse<EscrowSummaryResponse>>> EscrowSummary() =>
            Ok(ApiResponse<EscrowSummaryResponse>.Ok(await _admin.GetEscrowSummaryAsync()));

        [HttpGet("escrow/holds")]
        public async Task<ActionResult<ApiResponse<List<AdminEscrowHoldResponse>>>> Holds([FromQuery] string? status, [FromQuery] string? search) =>
            Ok(ApiResponse<List<AdminEscrowHoldResponse>>.Ok(await _admin.ListHoldsAsync(status, search)));

        [HttpPost("escrow/holds/{id}/resolve")]
        public async Task<ActionResult<ApiResponse<EscrowResponse>>> ResolveHold(string id, [FromBody] AdminDecisionRequest request) =>
            Ok(ApiResponse<EscrowResponse>.Ok(await _admin.ResolveHoldAsync(User.GetUserId(), id, request)));

        [HttpGet("commerce/summary")]
        public async Task<ActionResult<ApiResponse<CommerceSummaryResponse>>> CommerceSummary() =>
            Ok(ApiResponse<CommerceSummaryResponse>.Ok(await _admin.GetCommerceSummaryAsync()));

        [HttpGet("orders")]
        public async Task<ActionResult<ApiResponse<List<AdminOrderResponse>>>> Orders([FromQuery] string? status, [FromQuery] string? search) =>
            Ok(ApiResponse<List<AdminOrderResponse>>.Ok(await _admin.ListOrdersAsync(status, search)));

        [HttpGet("orders/{id}")]
        public async Task<ActionResult<ApiResponse<AdminOrderResponse>>> Order(string id) =>
            Ok(ApiResponse<AdminOrderResponse>.Ok(await _admin.GetOrderAsync(id)));

        [HttpPost("orders/{id}/cancel")]
        public async Task<ActionResult<ApiResponse<AdminOrderResponse>>> CancelOrder(string id, [FromBody] AdminOrderCancelRequest request) =>
            Ok(ApiResponse<AdminOrderResponse>.Ok(await _admin.CancelOrderAsync(User.GetUserId(), id, request)));

        [HttpGet("withdrawals")]
        public async Task<ActionResult<ApiResponse<List<AdminWithdrawalResponse>>>> Withdrawals([FromQuery] string? status, [FromQuery] string? role, [FromQuery] string? search) =>
            Ok(ApiResponse<List<AdminWithdrawalResponse>>.Ok(await _admin.ListWithdrawalsAsync(status, role, search)));

        [HttpPost("withdrawals/{id}/complete")]
        public async Task<ActionResult<ApiResponse<AdminWithdrawalResponse>>> CompleteWithdrawal(string id, [FromBody] WithdrawalCompleteRequest request) =>
            Ok(ApiResponse<AdminWithdrawalResponse>.Ok(await _admin.CompleteWithdrawalAsync(User.GetUserId(), id, request)));

        [HttpPost("withdrawals/{id}/reject")]
        public async Task<ActionResult<ApiResponse<AdminWithdrawalResponse>>> RejectWithdrawal(string id, [FromBody] WithdrawalRejectRequest request) =>
            Ok(ApiResponse<AdminWithdrawalResponse>.Ok(await _admin.RejectWithdrawalAsync(User.GetUserId(), id, request)));

        [HttpGet("wallets")]
        public async Task<ActionResult<ApiResponse<List<AdminWalletResponse>>>> Wallets() =>
            Ok(ApiResponse<List<AdminWalletResponse>>.Ok(await _admin.ListWalletsAsync()));

        [HttpGet("wallets/{userId}/transactions")]
        public async Task<ActionResult<ApiResponse<List<WalletTransactionResponse>>>> WalletTransactions(string userId, [FromQuery] int? limit) =>
            Ok(ApiResponse<List<WalletTransactionResponse>>.Ok(await _admin.ListWalletTransactionsAsync(userId, limit)));

        [HttpGet("payouts/summary")]
        public async Task<ActionResult<ApiResponse<PayoutSummaryResponse>>> PayoutSummary() =>
            Ok(ApiResponse<PayoutSummaryResponse>.Ok(await _admin.GetPayoutSummaryAsync()));
    }
}
