using System.Collections.Generic;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Commerce;
using ApplicationLayer.Interfaces;
using ControllerLayer.Extensions;
using ControllerLayer.Models;
using DomainLayer.Constants;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace ControllerLayer.Controllers
{
    /// <summary>Ví của thành viên. Một user một ví: route chuyên gia đọc cùng số dư.</summary>
    [Route("api/v1/users/me")]
    [ApiController]
    [Authorize]
    public class MemberWalletController : ControllerBase
    {
        private readonly IWalletService _wallets;

        public MemberWalletController(IWalletService wallets)
        {
            _wallets = wallets;
        }

        [HttpGet("wallet")]
        public async Task<ActionResult<ApiResponse<WalletResponse>>> Wallet() =>
            Ok(ApiResponse<WalletResponse>.Ok(await _wallets.GetWalletAsync(User.GetUserId(), WalletRoles.Member)));

        [HttpGet("wallet/transactions")]
        public async Task<ActionResult<ApiResponse<List<WalletTransactionResponse>>>> Transactions([FromQuery] int? limit) =>
            Ok(ApiResponse<List<WalletTransactionResponse>>.Ok(await _wallets.ListTransactionsAsync(User.GetUserId(), limit, null)));

        [HttpPut("bank-account")]
        public async Task<ActionResult<ApiResponse<BankAccountResponse>>> SaveBank([FromBody] BankAccountRequest request) =>
            Ok(ApiResponse<BankAccountResponse>.Ok(await _wallets.SaveBankAccountAsync(User.GetUserId(), request)));

        [HttpGet("withdrawals")]
        public async Task<ActionResult<ApiResponse<List<WithdrawalResponse>>>> Withdrawals() =>
            Ok(ApiResponse<List<WithdrawalResponse>>.Ok(await _wallets.ListWithdrawalsAsync(User.GetUserId())));

        [HttpPost("withdrawals")]
        public async Task<ActionResult<ApiResponse<WithdrawalResponse>>> RequestWithdrawal([FromBody] WithdrawalCreateRequest request)
        {
            var created = await _wallets.RequestWithdrawalAsync(User.GetUserId(), WalletRoles.Member, request);
            return StatusCode(StatusCodes.Status201Created, ApiResponse<WithdrawalResponse>.Created(created));
        }
    }

    [Route("api/v1/chefs/me")]
    [ApiController]
    [Authorize]
    public class ChefWalletController : ControllerBase
    {
        private readonly IWalletService _wallets;

        public ChefWalletController(IWalletService wallets)
        {
            _wallets = wallets;
        }

        private string ChefId() => ChefGuard.RequireChef(User);

        [HttpGet("wallet")]
        public async Task<ActionResult<ApiResponse<WalletResponse>>> Wallet() =>
            Ok(ApiResponse<WalletResponse>.Ok(await _wallets.GetWalletAsync(ChefId(), WalletRoles.Chef)));

        [HttpGet("wallet/transactions")]
        public async Task<ActionResult<ApiResponse<List<WalletTransactionResponse>>>> Transactions([FromQuery] string? month) =>
            Ok(ApiResponse<List<WalletTransactionResponse>>.Ok(await _wallets.ListTransactionsAsync(ChefId(), null, month)));

        [HttpPut("bank-account")]
        public async Task<ActionResult<ApiResponse<BankAccountResponse>>> SaveBank([FromBody] BankAccountRequest request) =>
            Ok(ApiResponse<BankAccountResponse>.Ok(await _wallets.SaveBankAccountAsync(ChefId(), request)));

        [HttpGet("withdrawals")]
        public async Task<ActionResult<ApiResponse<List<WithdrawalResponse>>>> Withdrawals() =>
            Ok(ApiResponse<List<WithdrawalResponse>>.Ok(await _wallets.ListWithdrawalsAsync(ChefId())));

        [HttpPost("withdrawals")]
        public async Task<ActionResult<ApiResponse<WithdrawalResponse>>> RequestWithdrawal([FromBody] WithdrawalCreateRequest request)
        {
            var created = await _wallets.RequestWithdrawalAsync(ChefId(), WalletRoles.Chef, request);
            return StatusCode(StatusCodes.Status201Created, ApiResponse<WithdrawalResponse>.Created(created));
        }
    }
}
