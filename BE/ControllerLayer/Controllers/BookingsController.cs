using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Commerce;
using ApplicationLayer.Interfaces;
using ControllerLayer.Authorization;
using ControllerLayer.Extensions;
using ControllerLayer.Models;
using DomainLayer.Exceptions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace ControllerLayer.Controllers
{
    /// <summary>Thành viên và dùng chung. Không phải hai bên của booking thì 404.</summary>
    [Route("api/v1/bookings")]
    [ApiController]
    [Authorize]
    public class BookingsController : ControllerBase
    {
        private readonly IBookingService _bookings;
        private readonly IOrderPaymentService _payments;

        public BookingsController(IBookingService bookings, IOrderPaymentService payments)
        {
            _bookings = bookings;
            _payments = payments;
        }

        [HttpPost]
        public async Task<ActionResult<ApiResponse<BookingResponse>>> Create([FromBody] CreateBookingRequest request)
        {
            var booking = await _bookings.CreateAsync(User.GetUserId(), request);
            return StatusCode(StatusCodes.Status201Created, ApiResponse<BookingResponse>.Created(booking));
        }

        [HttpGet("me")]
        public async Task<ActionResult<ApiResponse<List<BookingResponse>>>> Mine() =>
            Ok(ApiResponse<List<BookingResponse>>.Ok(await _bookings.ListMineAsync(User.GetUserId())));

        [HttpGet("{id}")]
        public async Task<ActionResult<ApiResponse<BookingResponse>>> Get(string id) =>
            Ok(ApiResponse<BookingResponse>.Ok(await _bookings.GetAsync(User.GetUserId(), id)));

        [HttpGet("{id}/messages")]
        public async Task<ActionResult<ApiResponse<List<MessageResponse>>>> Messages(string id, [FromQuery] DateTime? after) =>
            Ok(ApiResponse<List<MessageResponse>>.Ok(await _bookings.ListMessagesAsync(User.GetUserId(), id, after)));

        [HttpPost("{id}/messages")]
        public async Task<ActionResult<ApiResponse<MessageResponse>>> SendMessage(string id, [FromBody] SendMessageRequest request) =>
            Ok(ApiResponse<MessageResponse>.Ok(await _bookings.SendMessageAsync(User.GetUserId(), id, request)));

        [HttpPost("{id}/offers")]
        public async Task<ActionResult<ApiResponse<BookingResponse>>> SendOffer(string id, [FromBody] OfferRequest request) =>
            Ok(ApiResponse<BookingResponse>.Ok(await _bookings.SendOfferAsync(User.GetUserId(), id, request)));

        [HttpPost("{id}/offers/{offerId}/accept")]
        public async Task<ActionResult<ApiResponse<BookingResponse>>> AcceptOffer(string id, string offerId) =>
            Ok(ApiResponse<BookingResponse>.Ok(await _bookings.RespondToOfferAsync(User.GetUserId(), id, offerId, true)));

        [HttpPost("{id}/offers/{offerId}/reject")]
        public async Task<ActionResult<ApiResponse<BookingResponse>>> RejectOffer(string id, string offerId) =>
            Ok(ApiResponse<BookingResponse>.Ok(await _bookings.RespondToOfferAsync(User.GetUserId(), id, offerId, false)));

        [HttpPost("{id}/cancel")]
        public async Task<ActionResult<ApiResponse<BookingResponse>>> Cancel(string id, [FromBody] ReasonRequest request) =>
            Ok(ApiResponse<BookingResponse>.Ok(await _bookings.CancelAsync(User.GetUserId(), id, request)));

        [HttpPost("{id}/payments")]
        public async Task<ActionResult<ApiResponse<OrderResponse>>> StartPayment(string id) =>
            Ok(ApiResponse<OrderResponse>.Ok(await _payments.StartBookingPaymentAsync(User.GetUserId(), id)));

        [HttpGet("{id}/plan")]
        public async Task<ActionResult<ApiResponse<List<PlanDayResponse>>>> Plan(string id) =>
            Ok(ApiResponse<List<PlanDayResponse>>.Ok(await _bookings.GetPlanAsync(User.GetUserId(), id)));

        [HttpPut("{id}/plan/days/{dayIndex:int}/feedback")]
        public async Task<ActionResult<ApiResponse<PlanDayResponse>>> Feedback(string id, int dayIndex, [FromBody] DayFeedbackRequest request) =>
            Ok(ApiResponse<PlanDayResponse>.Ok(await _bookings.SendFeedbackAsync(User.GetUserId(), id, dayIndex, request)));

        [HttpGet("{id}/complaint")]
        public async Task<ActionResult<ApiResponse<ComplaintResponse>>> GetComplaint(string id) =>
            Ok(ApiResponse<ComplaintResponse>.Ok(await _bookings.GetComplaintAsync(User.GetUserId(), id)));

        [HttpPost("{id}/complaint")]
        public async Task<ActionResult<ApiResponse<BookingResponse>>> Complaint(string id, [FromBody] ComplaintRequest request) =>
            Ok(ApiResponse<BookingResponse>.Ok(await _bookings.FileComplaintAsync(User.GetUserId(), id, request)));
    }

    /// <summary>Phía chuyên gia. Sai vai trò trả 403 not_chef, nên kiểm tra trong action thay vì [Authorize(Roles)].</summary>
    [Route("api/v1/chefs/me/bookings")]
    [ApiController]
    [Authorize]
    public class ChefBookingsController : ControllerBase
    {
        private readonly IBookingService _bookings;

        public ChefBookingsController(IBookingService bookings)
        {
            _bookings = bookings;
        }

        private string ChefId() => ChefGuard.RequireChef(User);

        [HttpGet]
        public async Task<ActionResult<ApiResponse<List<BookingResponse>>>> Inbox([FromQuery] string? status) =>
            Ok(ApiResponse<List<BookingResponse>>.Ok(await _bookings.ListForChefAsync(ChefId(), status)));

        [HttpPost("{id}/decline")]
        public async Task<ActionResult<ApiResponse<BookingResponse>>> Decline(string id, [FromBody] ReasonRequest request) =>
            Ok(ApiResponse<BookingResponse>.Ok(await _bookings.DeclineAsync(ChefId(), id, request)));

        [HttpPost("{id}/complete")]
        public async Task<ActionResult<ApiResponse<BookingResponse>>> Complete(string id) =>
            Ok(ApiResponse<BookingResponse>.Ok(await _bookings.ConfirmCompletionAsync(ChefId(), id)));

        [HttpPut("{id}/plan/days/{dayIndex:int}")]
        public async Task<ActionResult<ApiResponse<PlanDayResponse>>> SaveDay(string id, int dayIndex, [FromBody] PlanDayRequest request) =>
            Ok(ApiResponse<PlanDayResponse>.Ok(await _bookings.SavePlanDayAsync(ChefId(), id, dayIndex, request)));

        [HttpPost("{id}/plan/days/{dayIndex:int}/send")]
        public async Task<ActionResult<ApiResponse<PlanDayResponse>>> SendDay(string id, int dayIndex) =>
            Ok(ApiResponse<PlanDayResponse>.Ok(await _bookings.SendPlanDayAsync(ChefId(), id, dayIndex)));

        [HttpPost("{id}/plan/send")]
        public async Task<ActionResult<ApiResponse<List<PlanDayResponse>>>> SendAll(string id) =>
            Ok(ApiResponse<List<PlanDayResponse>>.Ok(await _bookings.SendWholePlanAsync(ChefId(), id)));

        [HttpPost("{id}/complaint/response")]
        public async Task<ActionResult<ApiResponse<ComplaintResponse>>> RespondComplaint(string id, [FromBody] ComplaintChefResponseRequest request) =>
            Ok(ApiResponse<ComplaintResponse>.Ok(await _bookings.RespondToComplaintAsync(ChefId(), id, request)));
    }

    public static class ChefGuard
    {
        public static string RequireChef(System.Security.Claims.ClaimsPrincipal user)
        {
            var id = user.GetUserId();
            if (!user.IsInRole(AppRoles.Chef)) throw new ForbiddenException("Chỉ dành cho chuyên gia.", "not_chef");
            return id;
        }
    }
}
