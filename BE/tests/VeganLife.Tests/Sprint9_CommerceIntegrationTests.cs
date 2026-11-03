using System.Net;
using System.Text.Json;
using DomainLayer.Interfaces;
using MongoDB.Bson;
using MongoDB.Driver;
using VeganLife.Tests.Fixtures;
using Xunit;
using static VeganLife.Tests.Fixtures.CommerceHarness;

namespace VeganLife.Tests
{
    /// <summary>
    /// Tích hợp thật: HTTP vào pipeline thật, Mongo thật (DB ngẫu nhiên, xoá khi xong), không mock service nào.
    /// Chỉ đồng hồ và điểm mô phỏng chết máy là của test. Không có Mongo thì test báo Skipped.
    /// </summary>
    public class Sprint9_BookingLifecycleTests : IClassFixture<CommerceWebApplicationFactory>
    {
        private readonly CommerceHarness H;

        public Sprint9_BookingLifecycleTests(CommerceWebApplicationFactory factory)
        {
            H = new CommerceHarness(factory);
            H.Clock.Set(T0);
        }

        private static void AssertHexId(JsonElement element) =>
            Assert.True(ObjectId.TryParse(element.GetString(), out _), $"Id không phải 24 hex: {element}");

        [MongoFact]
        public async Task HappyPath_RequestToChefWallet_WireShapesMatchFe()
        {
            var member = await H.UserAsync(name: "Minh Anh");
            var chef = await H.ChefAsync("Lê Quang Tâm");
            var admin = await H.AdminAsync();

            var created = await H.PostAsync("/bookings", member, BookingBody(chef.Id));
            Assert.Equal(HttpStatusCode.Created, created.Status);
            Assert.Equal(201, created.Root.GetProperty("statusCode").GetInt32());
            var booking = created.Data;
            var id = booking.GetProperty("id").GetString()!;
            AssertHexId(booking.GetProperty("id"));
            Assert.Equal("Requested", booking.GetProperty("status").GetString());
            Assert.Equal(member.Id, booking.GetProperty("member").GetProperty("id").GetString());
            Assert.Equal(chef.Id, booking.GetProperty("chef").GetProperty("id").GetString());
            Assert.Equal("Lê Quang Tâm", booking.GetProperty("chef").GetProperty("fullName").GetString());
            Assert.Equal("2026-10-10", booking.GetProperty("startDate").GetString());
            Assert.Equal(JsonValueKind.Null, booking.GetProperty("contract").ValueKind);
            Assert.Equal(0, booking.GetProperty("deliveredDays").GetInt32());
            Assert.False(booking.GetProperty("autoCompleted").GetBoolean());

            var offered = (await H.OkAsync(H.PostAsync($"/bookings/{id}/offers", chef, new { price = 900_000, planDays = 3, bookingType = "OneShot", startDate = "2026-10-10", note = "3 ngày" }))).Data;
            Assert.Equal("Negotiating", offered.GetProperty("status").GetString());
            var offerId = offered.GetProperty("currentOffer").GetProperty("id").GetString()!;
            Assert.Equal("chef", offered.GetProperty("currentOffer").GetProperty("proposedBy").GetString());

            var accepted = (await H.OkAsync(H.PostAsync($"/bookings/{id}/offers/{offerId}/accept", member))).Data;
            Assert.Equal("AwaitingPayment", accepted.GetProperty("status").GetString());
            var contract = accepted.GetProperty("contract");
            Assert.Equal(900_000, contract.GetProperty("price").GetInt64());
            Assert.Equal("2026-10-12", contract.GetProperty("endDate").GetString());
            Assert.Equal(0.1, contract.GetProperty("feeRate").GetDouble());
            Assert.Equal(7, contract.GetProperty("holdDays").GetInt32());
            Assert.Equal("06:00", contract.GetProperty("dailySendCutoff").GetString());
            Assert.EndsWith("Z", contract.GetProperty("paymentDueAt").GetString()!);
            var orderId = accepted.GetProperty("paymentOrderId").GetString()!;

            var order = (await H.OkAsync(H.PostAsync($"/bookings/{id}/payments", member))).Data;
            Assert.Equal(orderId, order.GetProperty("id").GetString());
            Assert.Equal("Pending", order.GetProperty("status").GetString());
            var payment = order.GetProperty("payment");
            Assert.Equal("Sandbox", payment.GetProperty("provider").GetString());
            Assert.StartsWith("SBX", payment.GetProperty("transactionRef").GetString()!);
            Assert.Equal(JsonValueKind.Null, payment.GetProperty("qrCodeUrl").ValueKind);
            Assert.Equal(H.Clock.UtcNow.AddMinutes(15), payment.GetProperty("expiresAt").GetDateTime().ToUniversalTime());
            var paymentId = payment.GetProperty("id").GetString()!;

            // Chưa xác nhận thì đơn vẫn chờ, tiền chưa vào đâu.
            Assert.Equal("Pending", (await H.OkAsync(H.GetAsync($"/payments/{paymentId}", member))).Data.GetProperty("status").GetString());

            await H.OkAsync(H.PostAsync($"/payments/{paymentId}/sandbox-confirm", admin, new { success = true }));
            var paid = await H.BookingAsync(id, member);
            Assert.Equal("Active", paid.GetProperty("status").GetString());
            var escrow = paid.GetProperty("escrow");
            Assert.Equal("Held", escrow.GetProperty("status").GetString());
            Assert.Equal(paymentId, escrow.GetProperty("paymentId").GetString());
            Assert.Equal(JsonValueKind.Null, escrow.GetProperty("releaseAt").ValueKind);

            var chefWallet = (await H.OkAsync(H.GetAsync("/chefs/me/wallet", chef))).Data;
            Assert.Equal(810_000, chefWallet.GetProperty("pending").GetInt64());
            Assert.Equal(0, chefWallet.GetProperty("available").GetInt64());

            var b = new PaidBooking(id, orderId, escrow.GetProperty("id").GetString()!, paymentId, member, chef, admin, 900_000, "2026-10-10", "2026-10-12");
            await H.DeliverAllAsync(b);
            H.Clock.Set(Vn(2026, 10, 12, 20));
            var ended = (await H.OkAsync(H.PostAsync($"/chefs/me/bookings/{id}/complete", chef))).Data;
            Assert.Equal("Ended", ended.GetProperty("status").GetString());
            Assert.Equal(3, ended.GetProperty("deliveredDays").GetInt32());

            H.Clock.Set(Vn(2026, 10, 19, 20));
            var done = await H.BookingAsync(id, chef);
            Assert.Equal("Completed", done.GetProperty("status").GetString());
            Assert.Equal("Released", done.GetProperty("escrow").GetProperty("status").GetString());
            Assert.Equal(90_000, done.GetProperty("escrow").GetProperty("feeAmount").GetInt64());
            Assert.Equal(810_000, (await H.OkAsync(H.GetAsync("/chefs/me/wallet", chef))).Data.GetProperty("available").GetInt64());
            Assert.Equal("Paid", (await H.OkAsync(H.GetAsync($"/orders/{orderId}", member))).Data.GetProperty("status").GetString());

            var rows = (await H.OkAsync(H.GetAsync("/chefs/me/wallet/transactions", chef))).Data;
            Assert.Equal(JsonValueKind.Array, rows.ValueKind);
            var income = rows.EnumerateArray().Single();
            Assert.Equal("Income", income.GetProperty("type").GetString());
            Assert.Equal("Available", income.GetProperty("status").GetString());
            Assert.Equal(900_000, income.GetProperty("gross").GetInt64());
            Assert.Equal(90_000, income.GetProperty("fee").GetInt64());
            Assert.Equal(810_000, income.GetProperty("net").GetInt64());
            Assert.Equal("Minh Anh", income.GetProperty("memberName").GetString());
            Assert.Equal("Minh Anh", income.GetProperty("counterpartName").GetString());
            await H.AssertBooksBalanceAsync(member, chef);
        }

        /* ---------------------------------------------------------------- mốc thời gian */

        [MongoFact]
        public async Task ChefConfirm_Boundaries_InVietnamTime()
        {
            var b = await H.PaidAsync();
            await H.DeliverAllAsync(b);

            H.Clock.Set(Vn(2026, 10, 11, 23, 59, 59));
            AssertError(await H.PostAsync($"/chefs/me/bookings/{b.Id}/complete", b.Chef), HttpStatusCode.Conflict, "plan_not_delivered");

            var at = Vn(2026, 10, 12);
            H.Clock.Set(at);
            var ended = (await H.OkAsync(H.PostAsync($"/chefs/me/bookings/{b.Id}/complete", b.Chef))).Data;
            Assert.Equal(at, ended.GetProperty("completedAt").GetDateTime().ToUniversalTime());
            Assert.Equal(at.AddDays(7), ended.GetProperty("escrow").GetProperty("releaseAt").GetDateTime().ToUniversalTime());
            Assert.False(ended.GetProperty("autoCompleted").GetBoolean());

            H.Clock.Advance(TimeSpan.FromSeconds(1));
            AssertError(await H.PostAsync($"/chefs/me/bookings/{b.Id}/complete", b.Chef), HttpStatusCode.Conflict, "not_active");
        }

        [MongoFact]
        public async Task ChefConfirm_WithMissingDays_IsRefused()
        {
            var b = await H.PaidAsync(type: "DailyFeedback");
            await H.SaveDayAsync(b.Id, b.Chef, 1);
            await H.OkAsync(H.PostAsync($"/chefs/me/bookings/{b.Id}/plan/days/1/send", b.Chef));
            H.Clock.Set(Vn(2026, 10, 12, 12));
            var result = await H.PostAsync($"/chefs/me/bookings/{b.Id}/complete", b.Chef);
            AssertError(result, HttpStatusCode.Conflict, "plan_not_delivered");
            Assert.Contains("2", result.Root.GetProperty("message").GetString());
        }

        [MongoFact]
        public async Task AutoComplete_BeforeExactlyAndAfter_AtVietnam2359()
        {
            var b = await H.PaidAsync();
            await H.DeliverAllAsync(b);
            var moment = Vn(2026, 10, 15, 23, 59);

            H.Clock.Set(moment.AddSeconds(-1));
            await H.RunJobAsync();
            var before = await H.BookingAsync(b.Id, b.Chef);
            Assert.Equal("Active", before.GetProperty("status").GetString());
            Assert.Equal(JsonValueKind.Null, before.GetProperty("completedAt").ValueKind);

            H.Clock.Set(moment);
            await H.RunJobAsync();
            var at = await H.BookingAsync(b.Id, b.Chef);
            Assert.Equal("Ended", at.GetProperty("status").GetString());
            Assert.True(at.GetProperty("autoCompleted").GetBoolean());
            Assert.Equal(moment, at.GetProperty("completedAt").GetDateTime().ToUniversalTime());
            Assert.Equal(moment.AddDays(7), at.GetProperty("escrow").GetProperty("releaseAt").GetDateTime().ToUniversalTime());

            AssertError(await H.PostAsync($"/chefs/me/bookings/{b.Id}/complete", b.Chef), HttpStatusCode.Conflict, "not_active");

            // Khiếu nại trong 7 ngày vẫn đóng băng, autoCompleted giữ true.
            H.Clock.Set(moment.AddDays(1));
            var complained = (await H.OkAsync(H.PostAsync($"/bookings/{b.Id}/complaint", b.Member, ComplaintBody()))).Data;
            Assert.Equal("Frozen", complained.GetProperty("escrow").GetProperty("status").GetString());
            Assert.True(complained.GetProperty("autoCompleted").GetBoolean());
        }

        [MongoFact]
        public async Task Release_BeforeExactlyAndAfter_SevenDays()
        {
            var b = await H.PaidAsync();
            await H.DeliverAllAsync(b);
            var completed = Vn(2026, 10, 13, 10, 30);
            H.Clock.Set(completed);
            await H.OkAsync(H.PostAsync($"/chefs/me/bookings/{b.Id}/complete", b.Chef));
            var releaseAt = completed.AddDays(7);

            H.Clock.Set(releaseAt.AddSeconds(-1));
            await H.RunJobAsync();
            Assert.Equal("Held", (await H.BookingAsync(b.Id, b.Chef)).GetProperty("escrow").GetProperty("status").GetString());
            Assert.Equal(0, await H.AvailableAsync(b.Chef));
            // Vẫn còn một giây để khiếu nại.
            H.Clock.Set(releaseAt);
            await H.RunJobAsync();
            var released = await H.BookingAsync(b.Id, b.Chef);
            Assert.Equal("Released", released.GetProperty("escrow").GetProperty("status").GetString());
            Assert.Equal(releaseAt, released.GetProperty("escrow").GetProperty("releasedAt").GetDateTime().ToUniversalTime());
            Assert.Equal(810_000, await H.AvailableAsync(b.Chef));

            H.Clock.Set(releaseAt.AddSeconds(1));
            await H.RunJobAsync();
            await H.RunJobAsync();
            Assert.Equal(810_000, await H.AvailableAsync(b.Chef));
            AssertError(await H.PostAsync($"/bookings/{b.Id}/complaint", b.Member, ComplaintBody()), HttpStatusCode.Conflict, "not_open");
            await H.AssertBooksBalanceAsync(b.Chef);
        }

        [MongoFact]
        public async Task Complaint_LastSecondBeforeRelease_Freezes_ExactlyAtRelease_TooLate()
        {
            var first = await H.PaidAsync();
            await H.DeliverAllAsync(first);
            var second = await H.PaidAsync();
            await H.DeliverAllAsync(second);
            var completed = Vn(2026, 10, 13, 10);
            H.Clock.Set(completed);
            await H.OkAsync(H.PostAsync($"/chefs/me/bookings/{first.Id}/complete", first.Chef));
            await H.OkAsync(H.PostAsync($"/chefs/me/bookings/{second.Id}/complete", second.Chef));

            H.Clock.Set(completed.AddDays(7).AddSeconds(-1));
            await H.OkAsync(H.PostAsync($"/bookings/{first.Id}/complaint", first.Member, ComplaintBody()));

            H.Clock.Set(completed.AddDays(7));
            AssertError(await H.PostAsync($"/bookings/{second.Id}/complaint", second.Member, ComplaintBody()), HttpStatusCode.Conflict, "not_open");
            await H.RunJobAsync();
            Assert.Equal("Frozen", (await H.BookingAsync(first.Id, first.Member)).GetProperty("escrow").GetProperty("status").GetString());
            Assert.Equal(0, await H.AvailableAsync(first.Chef));
            Assert.Equal(810_000, await H.AvailableAsync(second.Chef));
        }

        [MongoFact]
        public async Task LateJob_GivesTheSameDatesAsOnTime_AndPaysOnce()
        {
            var b = await H.PaidAsync();
            await H.DeliverAllAsync(b);
            var moment = Vn(2026, 10, 15, 23, 59);

            H.Clock.Set(moment.AddDays(40));
            await H.RunJobAsync();
            await H.RunJobAsync();

            var row = await H.BookingAsync(b.Id, b.Chef);
            Assert.Equal("Completed", row.GetProperty("status").GetString());
            Assert.True(row.GetProperty("autoCompleted").GetBoolean());
            Assert.Equal(moment, row.GetProperty("completedAt").GetDateTime().ToUniversalTime());
            Assert.Equal(moment.AddDays(7), row.GetProperty("escrow").GetProperty("releasedAt").GetDateTime().ToUniversalTime());
            Assert.Equal(810_000, await H.AvailableAsync(b.Chef));
            await H.AssertBooksBalanceAsync(b.Chef);
        }

        [MongoFact]
        public async Task OnRead_NoJobNeeded_ReloadSeesSettledMoney()
        {
            var b = await H.PaidAsync();
            await H.DeliverAllAsync(b);
            H.Clock.Set(Vn(2026, 12, 1));

            // Chỉ đọc ví, không đọc booking, không có job.
            Assert.Equal(810_000, await H.AvailableAsync(b.Chef));
            for (var i = 0; i < 3; i++)
            {
                var again = await H.BookingAsync(b.Id, b.Member);
                Assert.Equal("Completed", again.GetProperty("status").GetString());
                Assert.Equal(810_000, await H.AvailableAsync(b.Chef));
            }
            var messages = (await H.OkAsync(H.GetAsync($"/bookings/{b.Id}/messages", b.Member))).Data;
            Assert.Single(messages.EnumerateArray().Where(m => m.GetProperty("body").GetString()!.StartsWith("Hết 7 ngày")));
        }

        [MongoFact]
        public async Task VietnamMonthBoundary_ConfirmAtMidnightUtcEvening_AndAutoCompleteInNextMonth()
        {
            H.Clock.Set(new DateTime(2026, 10, 20, 3, 0, 0, DateTimeKind.Utc));
            var b = await H.PaidAsync(start: "2026-10-29", days: 3); // 29, 30, 31/10
            Assert.Equal("2026-10-31", b.EndDate);
            await H.DeliverAllAsync(b);

            // Theo UTC vẫn là 30/10; theo lịch Việt Nam đã là 31/10.
            H.Clock.Set(new DateTime(2026, 10, 30, 16, 59, 59, DateTimeKind.Utc));
            AssertError(await H.PostAsync($"/chefs/me/bookings/{b.Id}/complete", b.Chef), HttpStatusCode.Conflict, "plan_not_delivered");
            H.Clock.Set(new DateTime(2026, 10, 30, 17, 0, 0, DateTimeKind.Utc));

            var other = await PaidAtAsync(new DateTime(2026, 10, 20, 3, 0, 0, DateTimeKind.Utc), "2026-10-29");
            await H.DeliverAllAsync(other);

            H.Clock.Set(new DateTime(2026, 10, 30, 17, 0, 0, DateTimeKind.Utc));
            await H.OkAsync(H.PostAsync($"/chefs/me/bookings/{b.Id}/complete", b.Chef));

            // 31/10 + 3 ngày = 03/11, 23:59 VN = 16:59 UTC.
            var moment = new DateTime(2026, 11, 3, 16, 59, 0, DateTimeKind.Utc);
            H.Clock.Set(moment.AddSeconds(-1));
            await H.RunJobAsync();
            Assert.Equal("Active", (await H.BookingAsync(other.Id, other.Chef)).GetProperty("status").GetString());
            H.Clock.Set(moment);
            await H.RunJobAsync();
            var row = await H.BookingAsync(other.Id, other.Chef);
            Assert.Equal(moment, row.GetProperty("completedAt").GetDateTime().ToUniversalTime());

            var nov = (await H.OkAsync(H.GetAsync("/chefs/me/wallet/transactions?month=2026-10", other.Chef))).Data;
            Assert.Single(nov.EnumerateArray());
            Assert.Empty((await H.OkAsync(H.GetAsync("/chefs/me/wallet/transactions?month=2026-11", other.Chef))).Data.EnumerateArray());
        }

        private async Task<PaidBooking> PaidAtAsync(DateTime now, string start)
        {
            var keep = H.Clock.UtcNow;
            H.Clock.Set(now);
            var b = await H.PaidAsync(start: start);
            H.Clock.Set(keep);
            return b;
        }

        [MongoFact]
        public async Task PaymentWindow_AtDueStillPayable_AfterItExpired()
        {
            var member = await H.UserAsync();
            var chef = await H.ChefAsync();
            var id = await H.RequestAsync(member, chef);
            var orderId = await H.AgreeAsync(id, member, chef, 500_000);
            var due = T0.AddHours(48);

            H.Clock.Set(due);
            var open = await H.OkAsync(H.PostAsync($"/bookings/{id}/payments", member));
            Assert.Equal(due, open.Data.GetProperty("payment").GetProperty("expiresAt").GetDateTime().ToUniversalTime().AddMinutes(0));

            H.Clock.Set(due.AddSeconds(1));
            AssertError(await H.PostAsync($"/bookings/{id}/payments", member), HttpStatusCode.Conflict, "not_awaiting_payment");
            var row = await H.BookingAsync(id, member);
            Assert.Equal("Expired", row.GetProperty("status").GetString());
            var order = (await H.OkAsync(H.GetAsync($"/orders/{orderId}", member))).Data;
            Assert.Equal("Cancelled", order.GetProperty("status").GetString());
            Assert.Equal("Expired", order.GetProperty("payment").GetProperty("status").GetString());
        }

        [MongoFact]
        public async Task PaymentWindow_CappedAtStartOfPlan()
        {
            var member = await H.UserAsync();
            var chef = await H.ChefAsync();
            var id = await H.RequestAsync(member, chef, start: "2026-10-02");
            await H.AgreeAsync(id, member, chef, 500_000, start: "2026-10-02");
            var row = await H.BookingAsync(id, member);
            Assert.Equal(Vn(2026, 10, 2), row.GetProperty("contract").GetProperty("paymentDueAt").GetDateTime().ToUniversalTime());
        }

        /* ---------------------------------------------------------------- khoản kẹt */

        [MongoFact]
        public async Task MissingDays_BecomeStuck_AndNoJobMovesTheMoney()
        {
            var b = await H.PaidAsync(type: "DailyFeedback");
            await H.SaveDayAsync(b.Id, b.Chef, 1);
            await H.OkAsync(H.PostAsync($"/chefs/me/bookings/{b.Id}/plan/days/1/send", b.Chef));
            var moment = Vn(2026, 10, 15, 23, 59);

            H.Clock.Set(moment.AddSeconds(-1));
            Assert.DoesNotContain(await StuckIdsAsync(b.Admin), id => id == b.EscrowId);

            H.Clock.Set(moment.AddDays(60));
            await H.RunJobAsync();
            await H.RunJobAsync();
            var row = await H.BookingAsync(b.Id, b.Chef);
            Assert.Equal("Active", row.GetProperty("status").GetString());
            Assert.Equal("Held", row.GetProperty("escrow").GetProperty("status").GetString());
            Assert.Equal(JsonValueKind.Null, row.GetProperty("escrow").GetProperty("releaseAt").ValueKind);
            Assert.Equal(0, await H.AvailableAsync(b.Chef));
            Assert.Equal(0, await H.AvailableAsync(b.Member));
            Assert.Contains(await StuckIdsAsync(b.Admin), id => id == b.EscrowId);
        }

        [MongoFact]
        public async Task Stuck_MemberComplains_NoLongerStuck_AdminDecidesAsComplaint()
        {
            var b = await H.PaidAsync(type: "DailyFeedback");
            H.Clock.Set(Vn(2026, 10, 16));
            Assert.Contains(await StuckIdsAsync(b.Admin), id => id == b.EscrowId);

            var row = (await H.OkAsync(H.PostAsync($"/bookings/{b.Id}/complaint", b.Member, ComplaintBody()))).Data;
            Assert.Equal("Frozen", row.GetProperty("escrow").GetProperty("status").GetString());
            Assert.DoesNotContain(await StuckIdsAsync(b.Admin), id => id == b.EscrowId);
            AssertError(await H.PostAsync($"/admin/escrow/holds/{b.EscrowId}/resolve", b.Admin, Decision("RefundMember")), HttpStatusCode.Conflict, "not_stuck");

            var complaint = (await H.OkAsync(H.GetAsync($"/bookings/{b.Id}/complaint", b.Chef))).Data;
            await H.OkAsync(H.PostAsync($"/admin/complaints/{complaint.GetProperty("id").GetString()}/decision", b.Admin, Decision("RefundMember")));
            Assert.Equal("Resolved", (await H.BookingAsync(b.Id, b.Member)).GetProperty("status").GetString());
            Assert.Equal(900_000, await H.AvailableAsync(b.Member));
        }

        [MongoFact]
        public async Task Complaint_Read_And_InboxStatusFilter()
        {
            var b = await H.PaidAsync();
            AssertError(await H.GetAsync($"/bookings/{b.Id}/complaint", b.Member), HttpStatusCode.NotFound, "not_found");
            Assert.Single((await H.OkAsync(H.GetAsync("/chefs/me/bookings?status=Active", b.Chef))).Data.EnumerateArray());
            Assert.Empty((await H.OkAsync(H.GetAsync("/chefs/me/bookings?status=Requested", b.Chef))).Data.EnumerateArray());
        }

        private async Task<List<string>> StuckIdsAsync(TestUser admin) =>
            (await H.OkAsync(H.GetAsync("/admin/escrow/holds?status=stuck", admin))).Data.EnumerateArray()
                .Select(h => { Assert.True(h.GetProperty("isStuck").GetBoolean()); return h.GetProperty("id").GetString()!; }).ToList();

        [MongoFact]
        public async Task DayDeliveredAfterMoment_StaysStuck_ChefCanStillConfirm_ThenNormalHold()
        {
            var b = await H.PaidAsync();
            var moment = Vn(2026, 10, 15, 23, 59);
            H.Clock.Set(moment.AddSeconds(1));
            await H.DeliverAllAsync(b);
            await H.RunJobAsync();
            var row = await H.BookingAsync(b.Id, b.Chef);
            Assert.Equal("Active", row.GetProperty("status").GetString());
            Assert.Contains(await StuckIdsAsync(b.Admin), id => id == b.EscrowId);

            var at = moment.AddDays(2);
            H.Clock.Set(at);
            var ended = (await H.OkAsync(H.PostAsync($"/chefs/me/bookings/{b.Id}/complete", b.Chef))).Data;
            Assert.False(ended.GetProperty("autoCompleted").GetBoolean());
            Assert.Equal(at.AddDays(7), ended.GetProperty("escrow").GetProperty("releaseAt").GetDateTime().ToUniversalTime());
            Assert.DoesNotContain(await StuckIdsAsync(b.Admin), id => id == b.EscrowId);
            AssertError(await H.PostAsync($"/admin/escrow/holds/{b.EscrowId}/resolve", b.Admin, Decision("ReleaseToChef")), HttpStatusCode.Conflict, "not_stuck");
        }

        private async Task<PaidBooking> StuckAsync(long price = 900_000)
        {
            var b = await H.PaidAsync(price, type: "DailyFeedback");
            H.Clock.Set(Vn(2026, 10, 16));
            Assert.Contains(await StuckIdsAsync(b.Admin), id => id == b.EscrowId);
            return b;
        }

        private static object Decision(string decision, long? refundAmount = null, string note = "Ban quản trị đã xem xét đủ bằng chứng của hai bên.") =>
            new { decision, refundAmount, note };

        [MongoFact]
        public async Task ResolveHold_ReleaseToChef()
        {
            var b = await StuckAsync();
            var escrow = (await H.OkAsync(H.PostAsync($"/admin/escrow/holds/{b.EscrowId}/resolve", b.Admin, Decision("ReleaseToChef")))).Data;
            Assert.Equal("Released", escrow.GetProperty("status").GetString());
            Assert.Equal(900_000, escrow.GetProperty("releasedAmount").GetInt64());
            Assert.Equal(90_000, escrow.GetProperty("feeAmount").GetInt64());
            Assert.Equal(H.Clock.UtcNow, escrow.GetProperty("releasedAt").GetDateTime().ToUniversalTime());
            Assert.Equal(JsonValueKind.Null, escrow.GetProperty("releaseAt").ValueKind);
            Assert.Equal(b.Admin.Name, escrow.GetProperty("resolvedBy").GetString());

            var row = await H.BookingAsync(b.Id, b.Chef);
            Assert.Equal("Completed", row.GetProperty("status").GetString());
            Assert.Equal(H.Clock.UtcNow, row.GetProperty("completedAt").GetDateTime().ToUniversalTime());
            Assert.False(row.GetProperty("autoCompleted").GetBoolean());
            Assert.Equal(810_000, await H.AvailableAsync(b.Chef));

            var order = (await H.OkAsync(H.GetAsync($"/admin/orders/{b.OrderId}", b.Admin))).Data;
            Assert.Equal("Paid", order.GetProperty("status").GetString());
            Assert.Equal("admin_resolve", order.GetProperty("resolution").GetProperty("action").GetString());
            Assert.Equal(JsonValueKind.Null, order.GetProperty("resolution").GetProperty("complaintId").ValueKind);

            AssertError(await H.PostAsync($"/chefs/me/bookings/{b.Id}/complete", b.Chef), HttpStatusCode.Conflict, "not_active");
            AssertError(await H.PostAsync($"/bookings/{b.Id}/complaint", b.Member, ComplaintBody()), HttpStatusCode.Conflict, "not_open");
            AssertError(await H.PostAsync($"/admin/escrow/holds/{b.EscrowId}/resolve", b.Admin, Decision("RefundMember")), HttpStatusCode.Conflict, "not_stuck");
            Assert.Equal(810_000, await H.AvailableAsync(b.Chef));
            Assert.Equal(0, await H.AvailableAsync(b.Member));
            await H.AssertBooksBalanceAsync(b.Chef, b.Member);
        }

        [MongoFact]
        public async Task ResolveHold_RefundMember()
        {
            var b = await StuckAsync();
            var escrow = (await H.OkAsync(H.PostAsync($"/admin/escrow/holds/{b.EscrowId}/resolve", b.Admin, Decision("RefundMember")))).Data;
            Assert.Equal("Refunded", escrow.GetProperty("status").GetString());
            Assert.Equal(900_000, escrow.GetProperty("refundedAmount").GetInt64());
            Assert.Equal(0, escrow.GetProperty("releasedAmount").GetInt64());
            Assert.Equal(0, escrow.GetProperty("feeAmount").GetInt64());

            var row = await H.BookingAsync(b.Id, b.Member);
            Assert.Equal("Cancelled", row.GetProperty("status").GetString());
            Assert.Contains("Ban quản trị", row.GetProperty("cancelReason").GetString());
            Assert.Equal(JsonValueKind.Null, row.GetProperty("completedAt").ValueKind);
            Assert.Equal(900_000, await H.AvailableAsync(b.Member));
            Assert.Equal(0, await H.AvailableAsync(b.Chef));

            var income = (await H.OkAsync(H.GetAsync("/chefs/me/wallet/transactions", b.Chef))).Data.EnumerateArray().Single();
            Assert.Equal("Reversed", income.GetProperty("status").GetString());
            Assert.Equal("Refunded", (await H.OkAsync(H.GetAsync($"/orders/{b.OrderId}", b.Member))).Data.GetProperty("status").GetString());
        }

        [MongoFact]
        public async Task ResolveHold_Split_RoundingAddsUpExactly()
        {
            var b = await StuckAsync(123_457);
            var escrow = (await H.OkAsync(H.PostAsync($"/admin/escrow/holds/{b.EscrowId}/resolve", b.Admin, Decision("Split", 1_001)))).Data;
            Assert.Equal("PartiallyRefunded", escrow.GetProperty("status").GetString());
            Assert.Equal(1_001, escrow.GetProperty("refundedAmount").GetInt64());
            Assert.Equal(122_456, escrow.GetProperty("releasedAmount").GetInt64());
            Assert.Equal(12_246, escrow.GetProperty("feeAmount").GetInt64());

            var member = await H.AvailableAsync(b.Member);
            var chef = await H.AvailableAsync(b.Chef);
            Assert.Equal(1_001, member);
            Assert.Equal(110_210, chef);
            Assert.Equal(123_457, member + chef + escrow.GetProperty("feeAmount").GetInt64());

            var row = await H.BookingAsync(b.Id, b.Member);
            Assert.Equal("Completed", row.GetProperty("status").GetString());
            Assert.Equal(H.Clock.UtcNow, row.GetProperty("completedAt").GetDateTime().ToUniversalTime());
            var order = (await H.OkAsync(H.GetAsync($"/admin/orders/{b.OrderId}", b.Admin))).Data;
            Assert.Equal("PartiallyRefunded", order.GetProperty("status").GetString());
            Assert.Equal(1_001, order.GetProperty("refundedAmount").GetInt64());
        }

        [MongoFact]
        public async Task ResolveHold_ChecksIn404Then400Then409Order()
        {
            var admin = await H.AdminAsync();
            AssertError(await H.PostAsync($"/admin/escrow/holds/{ObjectId.GenerateNewId()}/resolve", admin, Decision("ReleaseToChef")), HttpStatusCode.NotFound, "not_found");

            var notStuck = await H.PaidAsync(admin: admin);
            AssertError(await H.PostAsync($"/admin/escrow/holds/{notStuck.EscrowId}/resolve", admin, Decision("ReleaseToChef", note: "ngắn")), HttpStatusCode.BadRequest, "note_too_short");
            AssertError(await H.PostAsync($"/admin/escrow/holds/{notStuck.EscrowId}/resolve", admin, Decision("Split", 999)), HttpStatusCode.BadRequest, "invalid_refund_amount");
            AssertError(await H.PostAsync($"/admin/escrow/holds/{notStuck.EscrowId}/resolve", admin, Decision("Split", 900_000)), HttpStatusCode.BadRequest, "invalid_refund_amount");
            AssertError(await H.PostAsync($"/admin/escrow/holds/{notStuck.EscrowId}/resolve", admin, Decision("Nothing")), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync($"/admin/escrow/holds/{notStuck.EscrowId}/resolve", admin, Decision("ReleaseToChef")), HttpStatusCode.Conflict, "not_stuck");
        }

        /* ---------------------------------------------------------------- khiếu nại */

        private static object ComplaintBody() => new
        {
            reason = "not_as_agreed",
            description = "Thực đơn không đúng như đã thoả thuận, thiếu lượng đạm mỗi ngày.",
            requestedOutcome = "FullRefund",
            evidence = new[] { new { kind = "Link", url = "https://example.com/bang-chung", caption = "Bảng tính" } }
        };

        private async Task<(PaidBooking B, string ComplaintId)> DisputedAsync(long price = 1_050_000)
        {
            var b = await H.PaidAsync(price);
            var row = (await H.OkAsync(H.PostAsync($"/bookings/{b.Id}/complaint", b.Member, ComplaintBody()))).Data;
            Assert.Equal("Disputed", row.GetProperty("status").GetString());
            Assert.Equal("Frozen", row.GetProperty("escrow").GetProperty("status").GetString());
            return (b, row.GetProperty("complaint").GetProperty("id").GetString()!);
        }

        [MongoFact]
        public async Task Complaint_Freezes_WalletShowsFrozen_NoJobReleases()
        {
            var b = await H.PaidAsync(1_050_000);
            await H.DeliverAllAsync(b);
            H.Clock.Set(Vn(2026, 10, 13));
            await H.OkAsync(H.PostAsync($"/chefs/me/bookings/{b.Id}/complete", b.Chef));
            H.Clock.Set(Vn(2026, 10, 14));
            await H.OkAsync(H.PostAsync($"/bookings/{b.Id}/complaint", b.Member, ComplaintBody()));

            var wallet = (await H.OkAsync(H.GetAsync("/chefs/me/wallet", b.Chef))).Data;
            Assert.Equal(945_000, wallet.GetProperty("frozen").GetInt64());
            Assert.Equal(0, wallet.GetProperty("pending").GetInt64());

            H.Clock.Set(Vn(2027, 1, 1));
            await H.RunJobAsync();
            var row = await H.BookingAsync(b.Id, b.Member);
            Assert.Equal("Disputed", row.GetProperty("status").GetString());
            Assert.Equal("Frozen", row.GetProperty("escrow").GetProperty("status").GetString());
            Assert.Equal(Vn(2026, 10, 20), row.GetProperty("escrow").GetProperty("releaseAt").GetDateTime().ToUniversalTime());
            Assert.Equal(0, await H.AvailableAsync(b.Chef));
            AssertError(await H.PostAsync($"/bookings/{b.Id}/complaint", b.Member, ComplaintBody()), HttpStatusCode.Conflict, "not_open");
        }

        [MongoFact]
        public async Task Complaint_BeforeCompletion_BlocksChefConfirm()
        {
            var (b, _) = await DisputedAsync();
            H.Clock.Set(Vn(2026, 10, 12, 12));
            AssertError(await H.PostAsync($"/chefs/me/bookings/{b.Id}/complete", b.Chef), HttpStatusCode.Conflict, "has_open_complaint");
        }

        [MongoFact]
        public async Task Complaint_Validation_AndUnpaidBooking()
        {
            var member = await H.UserAsync();
            var chef = await H.ChefAsync();
            var id = await H.RequestAsync(member, chef);
            AssertError(await H.PostAsync($"/bookings/{id}/complaint", member, ComplaintBody()), HttpStatusCode.Conflict, "not_open");

            var b = await H.PaidAsync();
            AssertError(await H.PostAsync($"/bookings/{b.Id}/complaint", b.Member, new { reason = "other", description = "ngắn", requestedOutcome = "FullRefund", evidence = new[] { new { kind = "Link", url = "https://a.vn" } } }), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync($"/bookings/{b.Id}/complaint", b.Member, new { reason = "health_risk", description = new string('x', 40), requestedOutcome = "FullRefund", evidence = new[] { new { kind = "Image", url = "https://a.vn/a.jpg" } } }), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync($"/bookings/{b.Id}/complaint", b.Member, new { reason = "other", description = new string('x', 40), requestedOutcome = "FullRefund", evidence = Array.Empty<object>() }), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync($"/bookings/{b.Id}/complaint", b.Member, new { reason = "other", description = new string('x', 40), requestedOutcome = "PartialRefund", requestedAmount = 999, evidence = new[] { new { kind = "Link", url = "https://a.vn" } } }), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync($"/bookings/{b.Id}/complaint", b.Member, new { reason = "other", description = new string('x', 40), requestedOutcome = "FullRefund", evidence = new[] { new { kind = "Link", url = "javascript:alert(1)" } } }), HttpStatusCode.BadRequest, "validation");
        }

        [MongoFact]
        public async Task ChefResponse_ReturnsComplaint_AndNoComplaintIs409()
        {
            var plain = await H.PaidAsync();
            AssertError(await H.PostAsync($"/chefs/me/bookings/{plain.Id}/complaint/response", plain.Chef, new { text = new string('a', 25), links = Array.Empty<object>() }), HttpStatusCode.Conflict, "no_complaint");

            var (b, complaintId) = await DisputedAsync();
            AssertError(await H.PostAsync($"/chefs/me/bookings/{b.Id}/complaint/response", b.Chef, new { text = "quá ngắn" }), HttpStatusCode.BadRequest, "validation");
            var complaint = (await H.OkAsync(H.PostAsync($"/chefs/me/bookings/{b.Id}/complaint/response", b.Chef, new
            {
                text = "Tôi đã gửi đủ hướng dẫn trong ghi chú ngày 1.",
                links = new[] { new { kind = "Link", url = "https://example.com/ghi-chu", caption = "Ghi chú" } }
            }))).Data;
            Assert.Equal(complaintId, complaint.GetProperty("id").GetString());
            Assert.NotEqual(JsonValueKind.Null, complaint.GetProperty("chefRespondedAt").ValueKind);
            Assert.Contains(complaint.GetProperty("evidence").EnumerateArray(), e => e.GetProperty("submittedBy").GetString() == "chef");
        }

        [MongoTheory]
        [InlineData("ReleaseToChef", null, 0, 945_000, 105_000, "Released", "release", "Paid")]
        [InlineData("RefundMember", null, 1_050_000, 0, 0, "Refunded", "refund", "Refunded")]
        [InlineData("Split", 300_000L, 300_000, 675_000, 75_000, "PartiallyRefunded", "partial_refund", "PartiallyRefunded")]
        public async Task ComplaintDecision_MovesExactlyTheRightMoney(string decision, long? refund, long memberGets, long chefGets, long fee, string escrowStatus, string action, string orderStatus)
        {
            var (b, complaintId) = await DisputedAsync();
            var result = (await H.OkAsync(H.PostAsync($"/admin/complaints/{complaintId}/decision", b.Admin, Decision(decision, refund)))).Data;

            Assert.Equal("Resolved", result.GetProperty("status").GetString());
            Assert.Equal(decision, result.GetProperty("decision").GetString());
            Assert.Equal(memberGets, result.GetProperty("refundAmount").GetInt64());
            Assert.Equal(b.Admin.Name, result.GetProperty("decidedBy").GetString());
            Assert.Equal("Resolved", result.GetProperty("booking").GetProperty("status").GetString());
            Assert.Equal(JsonValueKind.Null, result.GetProperty("booking").GetProperty("complaint").ValueKind);
            Assert.NotEmpty(result.GetProperty("planDays").EnumerateArray());
            Assert.NotEmpty(result.GetProperty("messages").EnumerateArray());
            var escrow = result.GetProperty("booking").GetProperty("escrow");
            Assert.Equal(escrowStatus, escrow.GetProperty("status").GetString());
            Assert.Equal(fee, escrow.GetProperty("feeAmount").GetInt64());

            Assert.Equal(memberGets, await H.AvailableAsync(b.Member));
            Assert.Equal(chefGets, await H.AvailableAsync(b.Chef));
            Assert.Equal(b.Price, memberGets + chefGets + fee);

            var order = (await H.OkAsync(H.GetAsync($"/admin/orders/{b.OrderId}", b.Admin))).Data;
            Assert.Equal(orderStatus, order.GetProperty("status").GetString());
            Assert.Equal(action, order.GetProperty("resolution").GetProperty("action").GetString());
            Assert.Equal(complaintId, order.GetProperty("resolution").GetProperty("complaintId").GetString());

            // Gửi lại y hệt, hoặc admin khác quyết định khác: không đổi gì.
            AssertError(await H.PostAsync($"/admin/complaints/{complaintId}/decision", b.Admin, Decision("RefundMember")), HttpStatusCode.Conflict, "already_decided");
            await H.RunJobAsync();
            Assert.Equal(memberGets, await H.AvailableAsync(b.Member));
            Assert.Equal(chefGets, await H.AvailableAsync(b.Chef));
            await H.AssertBooksBalanceAsync(b.Member, b.Chef);
        }

        [MongoFact]
        public async Task ComplaintDecision_Validation()
        {
            var (b, complaintId) = await DisputedAsync();
            AssertError(await H.PostAsync($"/admin/complaints/{ObjectId.GenerateNewId()}/decision", b.Admin, Decision("ReleaseToChef")), HttpStatusCode.NotFound, "not_found");
            AssertError(await H.PostAsync($"/admin/complaints/{complaintId}/decision", b.Admin, Decision("ReleaseToChef", note: "ngắn")), HttpStatusCode.BadRequest, "note_too_short");
            AssertError(await H.PostAsync($"/admin/complaints/{complaintId}/decision", b.Admin, Decision("Split", 999)), HttpStatusCode.BadRequest, "invalid_refund_amount");
            AssertError(await H.PostAsync($"/admin/complaints/{complaintId}/decision", b.Admin, Decision("Split", 1_050_000)), HttpStatusCode.BadRequest, "invalid_refund_amount");
            AssertError(await H.PostAsync($"/admin/complaints/{complaintId}/decision", b.Admin, Decision("Split")), HttpStatusCode.BadRequest, "invalid_refund_amount");
        }

        /* ---------------------------------------------------------------- huỷ */

        [MongoFact]
        public async Task CancelBeforePay_NoMoneyMoves_AndOrderCancelled()
        {
            var member = await H.UserAsync();
            var chef = await H.ChefAsync();
            var id = await H.RequestAsync(member, chef);
            var orderId = await H.AgreeAsync(id, member, chef, 500_000);
            await H.OpenQrAsync(id, member);
            AssertError(await H.PostAsync($"/bookings/{id}/cancel", member, new { reason = "abc" }), HttpStatusCode.BadRequest, "validation");
            var row = (await H.OkAsync(H.PostAsync($"/bookings/{id}/cancel", member, new { reason = "Đổi ý rồi" }))).Data;
            Assert.Equal("Cancelled", row.GetProperty("status").GetString());
            Assert.Equal(JsonValueKind.Null, row.GetProperty("escrow").ValueKind);
            var order = (await H.OkAsync(H.GetAsync($"/orders/{orderId}", member))).Data;
            Assert.Equal("Cancelled", order.GetProperty("status").GetString());
            Assert.Equal("Expired", order.GetProperty("payment").GetProperty("status").GetString());
            Assert.Equal(0, await H.AvailableAsync(member));
            AssertError(await H.PostAsync($"/bookings/{id}/cancel", member, new { reason = "Đổi ý rồi" }), HttpStatusCode.Conflict, "invalid_status");
        }

        [MongoFact]
        public async Task CancelAfterPay_ZeroDays_FullRefundOnce_ResolvedByStaysNull()
        {
            var b = await H.PaidAsync(980_000);
            var row = (await H.OkAsync(H.PostAsync($"/bookings/{b.Id}/cancel", b.Member, new { reason = "Bác sĩ đổi chế độ ăn" }))).Data;
            Assert.Equal("Cancelled", row.GetProperty("status").GetString());
            var escrow = row.GetProperty("escrow");
            Assert.Equal("Refunded", escrow.GetProperty("status").GetString());
            Assert.Equal(980_000, escrow.GetProperty("refundedAmount").GetInt64());
            Assert.Equal(JsonValueKind.Null, escrow.GetProperty("resolvedBy").ValueKind);
            Assert.Equal("Bác sĩ đổi chế độ ăn", escrow.GetProperty("resolutionNote").GetString());
            Assert.Equal(980_000, await H.AvailableAsync(b.Member));

            var admin = (await H.OkAsync(H.GetAsync($"/admin/orders/{b.OrderId}", b.Admin))).Data;
            Assert.Equal("Refunded", admin.GetProperty("status").GetString());
            Assert.Equal("member_cancel", admin.GetProperty("resolution").GetProperty("action").GetString());

            var refund = (await H.OkAsync(H.GetAsync("/users/me/wallet/transactions", b.Member))).Data.EnumerateArray().Single();
            Assert.Equal("Refund", refund.GetProperty("type").GetString());
            Assert.Equal("Available", refund.GetProperty("status").GetString());
            Assert.Equal(980_000, refund.GetProperty("net").GetInt64());

            AssertError(await H.PostAsync($"/bookings/{b.Id}/cancel", b.Member, new { reason = "Bấm lại lần nữa" }), HttpStatusCode.Conflict, "plan_started");
            Assert.Equal(980_000, await H.AvailableAsync(b.Member));
            await H.AssertBooksBalanceAsync(b.Member);
        }

        [MongoFact]
        public async Task CancelAfterPay_OneDayDelivered_IsRefused()
        {
            var b = await H.PaidAsync(type: "DailyFeedback");
            await H.SaveDayAsync(b.Id, b.Chef, 1);
            await H.OkAsync(H.PostAsync($"/chefs/me/bookings/{b.Id}/plan/days/1/send", b.Chef));
            AssertError(await H.PostAsync($"/bookings/{b.Id}/cancel", b.Member, new { reason = "Muốn huỷ" }), HttpStatusCode.Conflict, "plan_started");
            Assert.Equal(0, await H.AvailableAsync(b.Member));
        }

        /* ---------------------------------------------------------------- đề xuất, kế hoạch, chat */

        [MongoFact]
        public async Task Offers_SupersedeOwnOfferClosedAndStartDate()
        {
            var member = await H.UserAsync();
            var chef = await H.ChefAsync();
            var id = await H.RequestAsync(member, chef);
            var body = new { price = 500_000, planDays = 3, bookingType = "OneShot", startDate = "2026-10-10", note = "Giá đầu" };
            var first = (await H.OkAsync(H.PostAsync($"/bookings/{id}/offers", chef, body))).Data.GetProperty("currentOffer").GetProperty("id").GetString()!;
            AssertError(await H.PostAsync($"/bookings/{id}/offers/{first}/accept", chef), HttpStatusCode.Conflict, "own_offer");
            var second = (await H.OkAsync(H.PostAsync($"/bookings/{id}/offers", member, new { price = 450_000, planDays = 3, bookingType = "OneShot", startDate = "2026-10-10", note = "Trả giá" }))).Data.GetProperty("currentOffer").GetProperty("id").GetString()!;
            AssertError(await H.PostAsync($"/bookings/{id}/offers/{first}/accept", member), HttpStatusCode.Conflict, "offer_closed");
            var rejected = (await H.OkAsync(H.PostAsync($"/bookings/{id}/offers/{second}/reject", chef))).Data;
            Assert.Equal("Rejected", rejected.GetProperty("currentOffer").GetProperty("status").GetString());
            AssertError(await H.PostAsync($"/bookings/{id}/offers/{second}/accept", chef), HttpStatusCode.Conflict, "offer_closed");

            var third = (await H.OkAsync(H.PostAsync($"/bookings/{id}/offers", chef, new { price = 480_000, planDays = 3, bookingType = "OneShot", startDate = "2026-10-03", note = (string?)null }))).Data.GetProperty("currentOffer").GetProperty("id").GetString()!;
            H.Clock.Set(Vn(2026, 10, 3));
            AssertError(await H.PostAsync($"/bookings/{id}/offers/{third}/accept", member), HttpStatusCode.Conflict, "start_date_passed");
            H.Clock.Set(T0);

            AssertError(await H.PostAsync($"/bookings/{id}/offers", chef, new { price = 99_999, planDays = 3, bookingType = "OneShot", startDate = "2026-10-10" }), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync($"/bookings/{id}/offers", chef, new { price = 100_000, planDays = 31, bookingType = "OneShot", startDate = "2026-10-10" }), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync($"/bookings/{id}/offers", chef, new { price = 100_000, planDays = 3, bookingType = "OneShot", startDate = "2026-10-01" }), HttpStatusCode.BadRequest, "validation");

            var messages = (await H.OkAsync(H.GetAsync($"/bookings/{id}/messages", member))).Data.EnumerateArray().ToList();
            Assert.Contains(messages, m => m.GetProperty("kind").GetString() == "Offer" && m.GetProperty("offer").GetProperty("id").GetString() == first);
        }

        [MongoFact]
        public async Task Create_ValidationSelfBookingAndPersonalDataRules()
        {
            var member = await H.UserAsync();
            var chef = await H.ChefAsync();

            AssertError(await H.PostAsync("/bookings", chef, BookingBody(chef.Id)), HttpStatusCode.Conflict, "self_booking");
            AssertError(await H.PostAsync("/bookings", member, BookingBody(member.Id)), HttpStatusCode.NotFound, "not_found");
            AssertError(await H.PostAsync("/bookings", member, BookingBody(ObjectId.GenerateNewId().ToString())), HttpStatusCode.NotFound, "not_found");
            AssertError(await H.PostAsync("/bookings", member, BookingBody(chef.Id, days: 2)), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync("/bookings", member, BookingBody(chef.Id, start: "2026-10-01")), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync("/bookings", member, new { chefId = chef.Id, bookingType = "OneShot", planDays = 3, startDate = "2026-10-10", mealPattern = new[] { "lunch" }, needs = "ngắn" }), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync("/bookings", member, new { chefId = chef.Id, bookingType = "OneShot", planDays = 3, startDate = "2026-10-10", mealPattern = Array.Empty<string>(), needs = new string('x', 30) }), HttpStatusCode.BadRequest, "validation");

            await H.Db.HealthProfiles.InsertOneAsync(new DomainLayer.Entities.HealthProfile { UserId = member.Id, HeightCm = 160, WeightKg = 55, Bmi = 21.5, Gender = "Female", BirthYear = 1997, TargetCalories = 1600 });

            // Gia đình: bỏ dữ liệu cá nhân dù app vẫn gửi lên.
            var family = (await H.OkAsync(H.PostAsync("/bookings", member, new
            {
                chefId = chef.Id, bookingType = "OneShot", planDays = 5, startDate = "2026-10-10", audience = "Family", familySize = 4,
                goal = "lose_weight", allergies = new[] { "peanut" }, mealPattern = new[] { "dinner", "lunch" }, needs = "", shareHealthProfile = true
            }))).Data;
            Assert.Equal(4, family.GetProperty("familySize").GetInt32());
            Assert.Equal(JsonValueKind.Null, family.GetProperty("goal").ValueKind);
            Assert.False(family.GetProperty("shareHealthProfile").GetBoolean());
            Assert.Equal(JsonValueKind.Null, family.GetProperty("memberHealth").ValueKind);
            Assert.Equal(new[] { "lunch", "dinner" }, family.GetProperty("mealPattern").EnumerateArray().Select(s => s.GetString()));

            // Chia sẻ: chuyên gia thấy chỉ số; không chia sẻ thì không có gì.
            var shared = (await H.OkAsync(H.PostAsync("/bookings", member, BookingBody(chef.Id)))).Data;
            var seenByChef = await H.BookingAsync(shared.GetProperty("id").GetString()!, chef);
            Assert.Equal(160, seenByChef.GetProperty("memberHealth").GetProperty("heightCm").GetDouble());
            Assert.Equal(29, seenByChef.GetProperty("memberHealth").GetProperty("age").GetInt32());
            Assert.Equal("lose_weight", seenByChef.GetProperty("goal").GetString());

            var notShared = (await H.OkAsync(H.PostAsync("/bookings", member, new
            {
                chefId = chef.Id, bookingType = "OneShot", planDays = 5, startDate = "2026-10-10", audience = "Self", familySize = 4,
                goal = "lose_weight", mealPattern = new[] { "lunch" }, needs = new string('x', 30), shareHealthProfile = false
            }))).Data;
            Assert.Equal(JsonValueKind.Null, notShared.GetProperty("goal").ValueKind);
            Assert.Equal(JsonValueKind.Null, notShared.GetProperty("familySize").ValueKind);
            Assert.Equal(JsonValueKind.Null, notShared.GetProperty("memberHealth").ValueKind);
        }

        [MongoFact]
        public async Task Decline_ClosesOffersAndOrder_OnlyBeforePayment()
        {
            var member = await H.UserAsync();
            var chef = await H.ChefAsync();
            var id = await H.RequestAsync(member, chef);
            var orderId = await H.AgreeAsync(id, member, chef, 500_000);
            AssertError(await H.PostAsync($"/chefs/me/bookings/{id}/decline", chef, new { reason = "ngắn" }), HttpStatusCode.BadRequest, "validation");
            var row = (await H.OkAsync(H.PostAsync($"/chefs/me/bookings/{id}/decline", chef, new { reason = "Tuần này tôi kín lịch" }))).Data;
            Assert.Equal("Declined", row.GetProperty("status").GetString());
            Assert.Equal("Tuần này tôi kín lịch", row.GetProperty("declineReason").GetString());
            Assert.Equal("Cancelled", (await H.OkAsync(H.GetAsync($"/orders/{orderId}", member))).Data.GetProperty("status").GetString());
            AssertError(await H.PostAsync($"/bookings/{id}/messages", member, new { body = "Còn đó không?" }), HttpStatusCode.Conflict, "invalid_status");

            var paid = await H.PaidAsync();
            AssertError(await H.PostAsync($"/chefs/me/bookings/{paid.Id}/decline", paid.Chef, new { reason = "Tuần này tôi kín lịch" }), HttpStatusCode.Conflict, "invalid_status");
        }

        [MongoFact]
        public async Task Plan_Visibility_SendOrder_AndFeedback()
        {
            var b = await H.PaidAsync(type: "DailyFeedback");
            AssertError(await H.PostAsync($"/chefs/me/bookings/{b.Id}/plan/send", b.Chef), HttpStatusCode.Conflict, "daily");
            AssertError(await H.PostAsync($"/chefs/me/bookings/{b.Id}/plan/days/1/send", b.Chef), HttpStatusCode.Conflict, "day_incomplete");
            AssertError(await H.PutAsync($"/chefs/me/bookings/{b.Id}/plan/days/9", b.Chef, new { meals = Array.Empty<object>() }), HttpStatusCode.NotFound, "not_found");
            AssertError(await H.PutAsync($"/chefs/me/bookings/{b.Id}/plan/days/1", b.Chef, new { meals = new[] { new { slot = "breakfast", recipe = new { name = "ab" } } } }), HttpStatusCode.BadRequest, "validation");

            await H.SaveDayAsync(b.Id, b.Chef, 1);
            await H.SaveDayAsync(b.Id, b.Chef, 2);
            AssertError(await H.PostAsync($"/chefs/me/bookings/{b.Id}/plan/days/2/send", b.Chef), HttpStatusCode.Conflict, "previous_day_unsent");

            Assert.Empty((await H.OkAsync(H.GetAsync($"/bookings/{b.Id}/plan", b.Member))).Data.EnumerateArray());
            var chefView = (await H.OkAsync(H.GetAsync($"/bookings/{b.Id}/plan", b.Chef))).Data.EnumerateArray().ToList();
            Assert.Equal(3, chefView.Count);
            Assert.Equal("Draft", chefView[0].GetProperty("status").GetString());
            Assert.Equal(JsonValueKind.Null, chefView[2].GetProperty("status").ValueKind);
            Assert.Equal("Yến mạch chuối", chefView[0].GetProperty("meals")[0].GetProperty("recipe").GetProperty("name").GetString());

            var sent = (await H.OkAsync(H.PostAsync($"/chefs/me/bookings/{b.Id}/plan/days/1/send", b.Chef))).Data;
            Assert.Equal("Sent", sent.GetProperty("status").GetString());
            AssertError(await H.PostAsync($"/chefs/me/bookings/{b.Id}/plan/days/1/send", b.Chef), HttpStatusCode.Conflict, "day_sent");
            AssertError(await H.PutAsync($"/chefs/me/bookings/{b.Id}/plan/days/1", b.Chef, new { meals = Array.Empty<object>() }), HttpStatusCode.Conflict, "day_sent");
            Assert.Single((await H.OkAsync(H.GetAsync($"/bookings/{b.Id}/plan", b.Member))).Data.EnumerateArray());

            var feedback = new { rating = 4, adherence = "Partly", body = "Hơi nhạt" };
            AssertError(await H.PutAsync($"/bookings/{b.Id}/plan/days/1/feedback", b.Member, feedback), HttpStatusCode.Conflict, "day_not_started");
            AssertError(await H.PutAsync($"/bookings/{b.Id}/plan/days/2/feedback", b.Member, feedback), HttpStatusCode.Conflict, "day_not_sent");
            H.Clock.Set(Vn(2026, 10, 10));
            AssertError(await H.PutAsync($"/bookings/{b.Id}/plan/days/1/feedback", b.Member, new { rating = 6, adherence = "All", body = "" }), HttpStatusCode.BadRequest, "validation");
            var ok = (await H.OkAsync(H.PutAsync($"/bookings/{b.Id}/plan/days/1/feedback", b.Member, feedback))).Data;
            Assert.Equal(4, ok.GetProperty("feedback").GetProperty("rating").GetInt32());

            H.Clock.Set(T0);
            var oneShot = await H.PaidAsync();
            AssertError(await H.PostAsync($"/chefs/me/bookings/{oneShot.Id}/plan/days/1/send", oneShot.Chef), HttpStatusCode.Conflict, "one_shot");
            AssertError(await H.PutAsync($"/bookings/{oneShot.Id}/plan/days/1/feedback", oneShot.Member, feedback), HttpStatusCode.Conflict, "one_shot");
            AssertError(await H.PostAsync($"/chefs/me/bookings/{oneShot.Id}/plan/send", oneShot.Chef), HttpStatusCode.Conflict, "day_incomplete");
            await H.DeliverAllAsync(oneShot);
            AssertError(await H.PostAsync($"/chefs/me/bookings/{oneShot.Id}/plan/send", oneShot.Chef), HttpStatusCode.Conflict, "day_sent");
        }

        [MongoFact]
        public async Task Messages_OrderAfterAndLength()
        {
            var member = await H.UserAsync();
            var chef = await H.ChefAsync();
            var id = await H.RequestAsync(member, chef);
            var startCount = (await H.OkAsync(H.GetAsync($"/bookings/{id}/messages", member))).Data.GetArrayLength();
            Assert.Equal(2, startCount);

            H.Clock.Advance(TimeSpan.FromMinutes(1));
            var mine = (await H.OkAsync(H.PostAsync($"/bookings/{id}/messages", member, new { body = "Chào anh" }))).Data;
            Assert.Equal("Text", mine.GetProperty("kind").GetString());
            Assert.Equal("member", mine.GetProperty("senderRole").GetString());
            var cutoff = Uri.EscapeDataString(H.Clock.UtcNow.ToString("O"));

            H.Clock.Advance(TimeSpan.FromMinutes(1));
            await H.OkAsync(H.PostAsync($"/bookings/{id}/messages", chef, new { body = "Chào bạn" }));
            var newer = (await H.OkAsync(H.GetAsync($"/bookings/{id}/messages?after={cutoff}", member))).Data.EnumerateArray().ToList();
            Assert.Equal("Chào bạn", newer.Single().GetProperty("body").GetString());

            var all = (await H.OkAsync(H.GetAsync($"/bookings/{id}/messages", member))).Data.EnumerateArray().Select(m => m.GetProperty("createdAt").GetDateTime()).ToList();
            Assert.Equal(all.OrderBy(d => d), all);

            AssertError(await H.PostAsync($"/bookings/{id}/messages", member, new { body = "  " }), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync($"/bookings/{id}/messages", member, new { body = new string('x', 1001) }), HttpStatusCode.BadRequest, "validation");
            var attachment = (await H.OkAsync(H.PostAsync($"/bookings/{id}/messages", member, new { body = "", attachmentUrl = "https://cdn.vn/a.jpg" }))).Data;
            Assert.Equal("Attachment", attachment.GetProperty("kind").GetString());
        }

        [MongoFact]
        public async Task Lists_NewestFirst_AndInvalidIdIs404()
        {
            var member = await H.UserAsync();
            var chef = await H.ChefAsync();
            var older = await H.RequestAsync(member, chef);
            H.Clock.Advance(TimeSpan.FromMinutes(1));
            var newer = await H.RequestAsync(member, chef);
            var mine = (await H.OkAsync(H.GetAsync("/bookings/me", member))).Data;
            Assert.Equal(JsonValueKind.Array, mine.ValueKind);
            Assert.Equal(new[] { newer, older }, mine.EnumerateArray().Select(b => b.GetProperty("id").GetString()));
            var inbox = (await H.OkAsync(H.GetAsync("/chefs/me/bookings", chef))).Data;
            Assert.Equal(new[] { newer, older }, inbox.EnumerateArray().Select(b => b.GetProperty("id").GetString()));
            AssertError(await H.GetAsync("/bookings/khong-phai-objectid", member), HttpStatusCode.NotFound, "not_found");
            AssertError(await H.GetAsync("/orders/khong-phai-objectid", member), HttpStatusCode.NotFound, "not_found");
            AssertError(await H.GetAsync("/payments/khong-phai-objectid", member), HttpStatusCode.NotFound, "not_found");
        }

        [MongoFact]
        public async Task MalformedJson_Is400_NotServerError()
        {
            var member = await H.UserAsync();
            var bad = await H.PostAsync("/bookings", member, new { chefId = 12345, planDays = "ba" });
            Assert.Equal(HttpStatusCode.BadRequest, bad.Status);
        }
    }

    /* ==================================================================== ví, rút tiền */

    public class Sprint9_WalletTests : IClassFixture<CommerceWebApplicationFactory>
    {
        private readonly CommerceHarness H;

        public Sprint9_WalletTests(CommerceWebApplicationFactory factory)
        {
            H = new CommerceHarness(factory);
            H.Clock.Set(T0);
        }

        private async Task<TestUser> FundedMemberAsync(long amount)
        {
            var member = await H.UserAsync();
            await H.FundWalletAsync(member, amount);
            await H.SaveBankAsync(member);
            return member;
        }

        [MongoFact]
        public async Task EmptyWallet_ReadsAsZero_AndChefRouteNeedsChefRole()
        {
            var member = await H.UserAsync();
            var wallet = (await H.OkAsync(H.GetAsync("/users/me/wallet", member))).Data;
            Assert.Equal(0, wallet.GetProperty("available").GetInt64());
            Assert.Equal(0.1, wallet.GetProperty("feeRate").GetDouble());
            Assert.Equal(7, wallet.GetProperty("holdDays").GetInt32());
            Assert.Equal(JsonValueKind.Null, wallet.GetProperty("bankAccount").ValueKind);
            Assert.Empty((await H.OkAsync(H.GetAsync("/users/me/wallet/transactions", member))).Data.EnumerateArray());
            AssertError(await H.GetAsync("/chefs/me/wallet", member), HttpStatusCode.Forbidden, "not_chef");
        }

        [MongoFact]
        public async Task BankAccount_Validation_AndOwnerSeesFullNumber()
        {
            var member = await H.UserAsync();
            AssertError(await H.PutAsync("/users/me/bank-account", member, new { bankName = "", accountNumber = "0071000456789", accountHolder = "Nguyen Van A" }), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PutAsync("/users/me/bank-account", member, new { bankName = "ACB", accountNumber = "12345", accountHolder = "Nguyen Van A" }), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PutAsync("/users/me/bank-account", member, new { bankName = "ACB", accountNumber = "12345678901234567890", accountHolder = "Nguyen Van A" }), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PutAsync("/users/me/bank-account", member, new { bankName = "ACB", accountNumber = "abc123456", accountHolder = "Nguyen Van A" }), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PutAsync("/users/me/bank-account", member, new { bankName = "ACB", accountNumber = "123456", accountHolder = "AB" }), HttpStatusCode.BadRequest, "validation");
            var saved = (await H.OkAsync(H.PutAsync("/users/me/bank-account", member, new { bankName = "ACB", accountNumber = "0071 0004 56789", accountHolder = "Nguyen Van A" }))).Data;
            Assert.Equal("0071000456789", saved.GetProperty("accountNumber").GetString());
            Assert.Equal("NGUYEN VAN A", saved.GetProperty("accountHolder").GetString());
            var wallet = (await H.OkAsync(H.GetAsync("/users/me/wallet", member))).Data;
            Assert.Equal("0071000456789", wallet.GetProperty("bankAccount").GetProperty("accountNumber").GetString());
        }

        [MongoFact]
        public async Task Withdrawal_Errors()
        {
            var noBank = await H.UserAsync();
            AssertError(await H.PostAsync("/users/me/withdrawals", noBank, new { amount = 100_000 }), HttpStatusCode.Conflict, "no_bank_account");

            var member = await FundedMemberAsync(500_000);
            AssertError(await H.PostAsync("/users/me/withdrawals", member, new { amount = 99_999 }), HttpStatusCode.BadRequest, "amount_too_small");
            AssertError(await H.PostAsync("/users/me/withdrawals", member, new { amount = 500_001 }), HttpStatusCode.Conflict, "insufficient_balance");
            Assert.Equal((500_000L, 0L, 0L), await H.FiguresAsync(member));
        }

        [MongoFact]
        public async Task Withdrawal_PendingThenApproved_MovesProcessingToWithdrawn()
        {
            var member = await FundedMemberAsync(500_000);
            var created = await H.PostAsync("/users/me/withdrawals", member, new { amount = 200_000 });
            Assert.Equal(HttpStatusCode.Created, created.Status);
            var w = created.Data;
            Assert.Equal("Processing", w.GetProperty("status").GetString());
            Assert.Equal("•••• 6789", w.GetProperty("accountNumber").GetString());
            Assert.Equal("Vietcombank", w.GetProperty("bankName").GetString());
            var id = w.GetProperty("id").GetString()!;
            Assert.Equal((300_000L, 200_000L, 0L), await H.FiguresAsync(member));

            var admin = await H.AdminAsync();
            var queue = (await H.OkAsync(H.GetAsync("/admin/withdrawals?status=Processing&role=member", admin))).Data.EnumerateArray().Single(r => r.GetProperty("id").GetString() == id);
            Assert.Equal("0071000456789", queue.GetProperty("bankAccount").GetProperty("accountNumber").GetString());
            Assert.Equal("member", queue.GetProperty("role").GetString());
            Assert.Equal(member.Id, queue.GetProperty("user").GetProperty("id").GetString());

            AssertError(await H.PostAsync($"/admin/withdrawals/{id}/complete", admin, new { transactionRef = "abc" }), HttpStatusCode.BadRequest, "invalid_transaction_ref");
            AssertError(await H.PostAsync($"/admin/withdrawals/{id}/complete", admin, new { transactionRef = "có dấu cách" }), HttpStatusCode.BadRequest, "invalid_transaction_ref");
            AssertError(await H.PostAsync($"/admin/withdrawals/{ObjectId.GenerateNewId()}/complete", admin, new { transactionRef = "FT26101" }), HttpStatusCode.NotFound, "not_found");

            var done = (await H.OkAsync(H.PostAsync($"/admin/withdrawals/{id}/complete", admin, new { transactionRef = "FT.261001/99" }))).Data;
            Assert.Equal("Completed", done.GetProperty("status").GetString());
            Assert.Equal("FT.261001/99", done.GetProperty("transactionRef").GetString());
            Assert.Equal(admin.Name, done.GetProperty("processedBy").GetString());
            Assert.Equal((300_000L, 0L, 200_000L), await H.FiguresAsync(member));

            AssertError(await H.PostAsync($"/admin/withdrawals/{id}/complete", admin, new { transactionRef = "FT.261001/99" }), HttpStatusCode.Conflict, "already_processed");
            AssertError(await H.PostAsync($"/admin/withdrawals/{id}/reject", admin, new { reason = "Đổi ý, muốn từ chối" }), HttpStatusCode.Conflict, "already_processed");
            Assert.Equal((300_000L, 0L, 200_000L), await H.FiguresAsync(member));

            var history = (await H.OkAsync(H.GetAsync("/users/me/wallet/transactions", member))).Data.EnumerateArray().ToList();
            var row = history.Single(r => r.GetProperty("type").GetString() == "Withdrawal");
            Assert.Equal(-200_000, row.GetProperty("net").GetInt64());
            Assert.Equal("Completed", row.GetProperty("status").GetString());
            Assert.Equal("Vietcombank •••• 6789", row.GetProperty("bankName").GetString());
            await H.AssertBooksBalanceAsync(member);
        }

        [MongoFact]
        public async Task Withdrawal_Rejected_MoneyReturnsToAvailable()
        {
            var member = await FundedMemberAsync(500_000);
            var id = (await H.OkAsync(H.PostAsync("/users/me/withdrawals", member, new { amount = 500_000 }))).Data.GetProperty("id").GetString()!;
            Assert.Equal((0L, 500_000L, 0L), await H.FiguresAsync(member));
            var admin = await H.AdminAsync();

            AssertError(await H.PostAsync($"/admin/withdrawals/{id}/reject", admin, new { reason = "ngắn" }), HttpStatusCode.BadRequest, "reason_too_short");
            var rejected = (await H.OkAsync(H.PostAsync($"/admin/withdrawals/{id}/reject", admin, new { reason = "Tên chủ tài khoản không khớp" }))).Data;
            Assert.Equal("Rejected", rejected.GetProperty("status").GetString());
            Assert.Equal((500_000L, 0L, 0L), await H.FiguresAsync(member));

            var list = (await H.OkAsync(H.GetAsync("/users/me/withdrawals", member))).Data.EnumerateArray().Single();
            Assert.Equal("Rejected", list.GetProperty("status").GetString());
            Assert.Equal("Tên chủ tài khoản không khớp", list.GetProperty("reason").GetString());

            // Từ chối rồi gửi lại đúng số tiền đó, ngay lập tức: vẫn được, vì tiền đã về.
            var again = await H.PostAsync("/users/me/withdrawals", member, new { amount = 500_000 });
            Assert.Equal(HttpStatusCode.Created, again.Status);
            Assert.NotEqual(id, again.Data.GetProperty("id").GetString());
            Assert.Equal((0L, 500_000L, 0L), await H.FiguresAsync(member));
            await H.AssertBooksBalanceAsync(member);
        }

        [MongoFact]
        public async Task Withdrawal_RepeatedRequest_WithinWindow_ReturnsTheSameOne()
        {
            var member = await FundedMemberAsync(500_000);
            var first = (await H.OkAsync(H.PostAsync("/users/me/withdrawals", member, new { amount = 100_000 }))).Data.GetProperty("id").GetString();
            var second = (await H.OkAsync(H.PostAsync("/users/me/withdrawals", member, new { amount = 100_000 }))).Data.GetProperty("id").GetString();
            Assert.Equal(first, second);
            Assert.Equal((400_000L, 100_000L, 0L), await H.FiguresAsync(member));

            // Số tiền khác, hoặc sau khoảng chặn bấm đúp, là yêu cầu mới.
            await H.OkAsync(H.PostAsync("/users/me/withdrawals", member, new { amount = 150_000 }));
            H.Clock.Advance(TimeSpan.FromSeconds(11));
            var later = (await H.OkAsync(H.PostAsync("/users/me/withdrawals", member, new { amount = 100_000 }))).Data.GetProperty("id").GetString();
            Assert.NotEqual(first, later);
            Assert.Equal((150_000L, 350_000L, 0L), await H.FiguresAsync(member));
            Assert.Equal(3, (await H.OkAsync(H.GetAsync("/users/me/withdrawals", member))).Data.GetArrayLength());
        }

        [MongoFact]
        public async Task ChefWithdrawal_FromReleasedIncome_OneWalletPerUser()
        {
            var b = await H.PaidAsync(1_000_000);
            await H.DeliverAllAsync(b);
            H.Clock.Set(Vn(2026, 12, 1));
            await H.OkAsync(H.PutAsync("/chefs/me/bank-account", b.Chef, new { bankName = "MB Bank", accountNumber = "1234567890", accountHolder = "Le Quang Tam" }));
            Assert.Equal(900_000, (await H.OkAsync(H.GetAsync("/chefs/me/wallet", b.Chef))).Data.GetProperty("available").GetInt64());

            var w = (await H.OkAsync(H.PostAsync("/chefs/me/withdrawals", b.Chef, new { amount = 400_000 }))).Data;
            Assert.Equal("•••• 7890", w.GetProperty("accountNumber").GetString());
            Assert.Equal(400_000, (await H.OkAsync(H.GetAsync("/chefs/me/wallet", b.Chef))).Data.GetProperty("processing").GetInt64());

            // Route thành viên của cùng user đọc cùng một số dư.
            Assert.Equal((500_000L, 400_000L, 0L), await H.FiguresAsync(b.Chef));
            Assert.Equal(1, await H.Db.Wallets.CountDocumentsAsync(x => x.Id == b.Chef.Id));
            var chefRows = (await H.OkAsync(H.GetAsync("/admin/withdrawals?role=chef", b.Admin))).Data.EnumerateArray();
            Assert.Contains(chefRows, r => r.GetProperty("id").GetString() == w.GetProperty("id").GetString());
            await H.AssertBooksBalanceAsync(b.Chef);
        }

        [MongoFact]
        public async Task WalletPayment_PaysInFull_ClosesOpenQr_AndWritesNegativeRow()
        {
            var member = await H.UserAsync();
            await H.FundWalletAsync(member, 800_000);
            var chef = await H.ChefAsync();
            var id = await H.RequestAsync(member, chef);
            var orderId = await H.AgreeAsync(id, member, chef, 600_000);
            var qr = await H.OpenQrAsync(id, member);
            H.Clock.Advance(TimeSpan.FromMinutes(1));

            var order = (await H.OkAsync(H.PostAsync($"/orders/{orderId}/wallet-payment", member))).Data;
            Assert.Equal("Paid", order.GetProperty("status").GetString());
            Assert.Equal("Wallet", order.GetProperty("payment").GetProperty("provider").GetString());
            Assert.Equal(JsonValueKind.Null, order.GetProperty("payment").GetProperty("qrCodeUrl").ValueKind);
            Assert.Equal("Held", order.GetProperty("escrow").GetProperty("status").GetString());
            Assert.Equal("Expired", (await H.OkAsync(H.GetAsync($"/payments/{qr}", member))).Data.GetProperty("status").GetString());
            Assert.Equal("Active", (await H.BookingAsync(id, member)).GetProperty("status").GetString());
            Assert.Equal(200_000, await H.AvailableAsync(member));

            var row = (await H.OkAsync(H.GetAsync("/users/me/wallet/transactions?limit=1", member))).Data.EnumerateArray().Single();
            Assert.Equal("Payment", row.GetProperty("type").GetString());
            Assert.Equal("Completed", row.GetProperty("status").GetString());
            Assert.Equal(-600_000, row.GetProperty("net").GetInt64());

            AssertError(await H.PostAsync($"/orders/{orderId}/wallet-payment", member), HttpStatusCode.Conflict, "not_awaiting_payment");
            Assert.Equal(200_000, await H.AvailableAsync(member));
            await H.AssertBooksBalanceAsync(member);
        }

        [MongoFact]
        public async Task WalletPayment_NotEnough_NoPartialPayment_ThenTopUpWorks()
        {
            var member = await H.UserAsync();
            await H.FundWalletAsync(member, 500_000);
            var chef = await H.ChefAsync();
            var id = await H.RequestAsync(member, chef);
            var orderId = await H.AgreeAsync(id, member, chef, 600_000);

            AssertError(await H.PostAsync($"/orders/{orderId}/wallet-payment", member), HttpStatusCode.Conflict, "insufficient_balance");
            Assert.Equal(500_000, await H.AvailableAsync(member));
            Assert.Equal("AwaitingPayment", (await H.BookingAsync(id, member)).GetProperty("status").GetString());
            Assert.DoesNotContain((await H.OkAsync(H.GetAsync("/users/me/wallet/transactions", member))).Data.EnumerateArray(), r => r.GetProperty("type").GetString() == "Payment");

            await H.FundWalletAsync(member, 100_000);
            await H.OkAsync(H.PostAsync($"/orders/{orderId}/wallet-payment", member));
            Assert.Equal(0, await H.AvailableAsync(member));
            await H.AssertBooksBalanceAsync(member);
        }

        [MongoFact]
        public async Task LatePayment_AfterBookingClosed_RefundsToWalletOnce()
        {
            var member = await H.UserAsync();
            var chef = await H.ChefAsync();
            var admin = await H.AdminAsync();
            var id = await H.RequestAsync(member, chef);
            var orderId = await H.AgreeAsync(id, member, chef, 700_000);
            var qr = await H.OpenQrAsync(id, member);
            await H.OkAsync(H.PostAsync($"/bookings/{id}/cancel", member, new { reason = "Huỷ trước khi trả" }));

            await H.OkAsync(H.PostAsync($"/payments/{qr}/sandbox-confirm", admin, new { success = true }));
            await H.OkAsync(H.PostAsync($"/payments/{qr}/sandbox-confirm", admin, new { success = true }));
            await H.RunJobAsync();
            Assert.Equal(700_000, await H.AvailableAsync(member));
            var row = await H.BookingAsync(id, member);
            Assert.Equal("Cancelled", row.GetProperty("status").GetString());
            Assert.Equal(JsonValueKind.Null, row.GetProperty("escrow").ValueKind);
            Assert.Equal("Refunded", (await H.OkAsync(H.GetAsync($"/orders/{orderId}", member))).Data.GetProperty("status").GetString());
            await H.AssertBooksBalanceAsync(member);
        }

        [MongoFact]
        public async Task SandboxConfirm_FailedThenExpired_QrRenewal()
        {
            var member = await H.UserAsync();
            var chef = await H.ChefAsync();
            var admin = await H.AdminAsync();
            var id = await H.RequestAsync(member, chef);
            var orderId = await H.AgreeAsync(id, member, chef, 700_000);

            var first = await H.OpenQrAsync(id, member);
            Assert.Equal(first, await H.OpenQrAsync(id, member));
            var renewed = (await H.OkAsync(H.PostAsync($"/orders/{orderId}/payments", member))).Data;
            Assert.Equal(first, renewed.GetProperty("id").GetString());

            var failed = (await H.OkAsync(H.PostAsync($"/payments/{first}/sandbox-confirm", admin, new { success = false }))).Data;
            Assert.Equal("Failed", failed.GetProperty("status").GetString());
            AssertError(await H.PostAsync($"/payments/{first}/sandbox-confirm", admin, new { success = true }), HttpStatusCode.Conflict, "payment_failed");

            var second = (await H.OkAsync(H.PostAsync($"/orders/{orderId}/payments", member))).Data.GetProperty("id").GetString()!;
            Assert.NotEqual(first, second);

            H.Clock.Advance(TimeSpan.FromMinutes(15));
            Assert.Equal("Pending", (await H.OkAsync(H.GetAsync($"/payments/{second}", member))).Data.GetProperty("status").GetString());
            H.Clock.Advance(TimeSpan.FromSeconds(1));
            Assert.Equal("Expired", (await H.OkAsync(H.GetAsync($"/payments/{second}", member))).Data.GetProperty("status").GetString());
            AssertError(await H.PostAsync($"/payments/{second}/sandbox-confirm", admin, new { success = true }), HttpStatusCode.Conflict, "payment_expired");

            var third = (await H.OkAsync(H.PostAsync($"/orders/{orderId}/payments", member))).Data.GetProperty("id").GetString()!;
            await H.OkAsync(H.PostAsync($"/payments/{third}/sandbox-confirm", admin, new { success = true }));
            var admins = (await H.OkAsync(H.GetAsync($"/admin/orders/{orderId}", admin))).Data;
            Assert.Equal(new[] { "Failed", "Expired", "Paid" }, admins.GetProperty("payments").EnumerateArray().Select(p => p.GetProperty("status").GetString()));
            AssertError(await H.PostAsync($"/orders/{orderId}/payments", member), HttpStatusCode.Conflict, "not_awaiting_payment");
        }
    }

    /* ==================================================================== bấm đúp, hai phiên, chết máy */

    public class Sprint9_SandboxSelfConfirmTests : IClassFixture<SelfConfirmFactory>
    {
        private readonly CommerceHarness H;

        public Sprint9_SandboxSelfConfirmTests(SelfConfirmFactory factory)
        {
            H = new CommerceHarness(factory);
        }

        [MongoFact]
        public async Task Buyer_ConfirmsOwnTestPayment_OthersCannot_AndRepeatIsSafe()
        {
            var member = await H.UserAsync();
            var chef = await H.ChefAsync();
            var stranger = await H.UserAsync();
            var id = await H.RequestAsync(member, chef);
            await H.AgreeAsync(id, member, chef, 500_000);
            var qr = await H.OpenQrAsync(id, member);

            AssertError(await H.PostAsync($"/payments/{qr}/sandbox-confirm", null, new { success = true }), HttpStatusCode.Unauthorized, "unauthorized");
            Assert.Equal(HttpStatusCode.NotFound, (await H.PostAsync($"/payments/{qr}/sandbox-confirm", stranger, new { success = true })).Status);
            Assert.Equal(HttpStatusCode.NotFound, (await H.PostAsync($"/payments/{qr}/sandbox-confirm", chef, new { success = true })).Status);
            Assert.Equal("AwaitingPayment", (await H.BookingAsync(id, member)).GetProperty("status").GetString());

            await H.OkAsync(H.PostAsync($"/payments/{qr}/sandbox-confirm", member, new { success = true }));
            await H.OkAsync(H.PostAsync($"/payments/{qr}/sandbox-confirm", member, new { success = true }));

            var booking = await H.BookingAsync(id, member);
            Assert.NotEqual("AwaitingPayment", booking.GetProperty("status").GetString());
            Assert.Equal("Held", booking.GetProperty("escrow").GetProperty("status").GetString());
        }
    }

    public class Sprint9_MoneySafetyTests : IClassFixture<CommerceWebApplicationFactory>
    {
        private readonly CommerceHarness H;
        private const int Parallel = 8;
        private const string LongNote = "Ban quản trị đã xem xét đủ bằng chứng của hai bên.";

        public Sprint9_MoneySafetyTests(CommerceWebApplicationFactory factory)
        {
            H = new CommerceHarness(factory);
            H.Clock.Set(T0);
        }

        private static object ComplaintBody() => new
        {
            reason = "other",
            description = "Kế hoạch không đúng như đã thoả thuận trong hợp đồng.",
            requestedOutcome = "FullRefund",
            evidence = new[] { new { kind = "Link", url = "https://example.com/bang-chung" } }
        };

        private async Task<ApiResult[]> BurstAsync(Func<int, Task<ApiResult>> call) =>
            await Task.WhenAll(Enumerable.Range(0, Parallel).Select(call));

        private static int Successes(ApiResult[] results) => results.Count(r => r.Status is HttpStatusCode.OK or HttpStatusCode.Created);

        private static void AssertNoServerError(ApiResult[] results)
        {
            foreach (var r in results) Assert.True((int)r.Status < 500, $"Lỗi máy chủ khi chạy đồng thời: {r.Root}");
        }

        [MongoFact]
        public async Task DoubleClick_Complaint_DecisionPaysOnce()
        {
            var b = await H.PaidAsync(1_000_000);
            var complaintId = (await H.OkAsync(H.PostAsync($"/bookings/{b.Id}/complaint", b.Member, ComplaintBody()))).Data.GetProperty("complaint").GetProperty("id").GetString()!;
            var results = await BurstAsync(_ => H.PostAsync($"/admin/complaints/{complaintId}/decision", b.Admin, new { decision = "RefundMember", note = LongNote }));
            AssertNoServerError(results);
            Assert.Equal(1, Successes(results));
            Assert.All(results.Where(r => r.Status != HttpStatusCode.OK), r => Assert.Equal("already_decided", r.Code));
            Assert.Equal(1_000_000, await H.AvailableAsync(b.Member));
            await H.AssertBooksBalanceAsync(b.Member);
        }

        [MongoFact]
        public async Task TwoAdminSessions_DifferentDecisions_OnlyOneMoneyOutcome()
        {
            var b = await H.PaidAsync(1_000_000);
            var other = await H.AdminAsync("Trần Thu Hằng");
            var complaintId = (await H.OkAsync(H.PostAsync($"/bookings/{b.Id}/complaint", b.Member, ComplaintBody()))).Data.GetProperty("complaint").GetProperty("id").GetString()!;

            var results = await Task.WhenAll(
                H.PostAsync($"/admin/complaints/{complaintId}/decision", b.Admin, new { decision = "RefundMember", note = LongNote }),
                H.PostAsync($"/admin/complaints/{complaintId}/decision", other, new { decision = "ReleaseToChef", note = LongNote }),
                H.PostAsync($"/admin/complaints/{complaintId}/decision", b.Admin, new { decision = "Split", refundAmount = 300_000, note = LongNote }),
                H.PostAsync($"/admin/complaints/{complaintId}/decision", other, new { decision = "RefundMember", note = LongNote }));
            AssertNoServerError(results);
            Assert.Equal(1, Successes(results));

            var member = await H.AvailableAsync(b.Member);
            var chef = await H.AvailableAsync(b.Chef);
            var escrow = (await H.BookingAsync(b.Id, b.Member)).GetProperty("escrow");
            Assert.Equal(1_000_000, member + chef + escrow.GetProperty("feeAmount").GetInt64());
            Assert.Equal(member, escrow.GetProperty("refundedAmount").GetInt64());
            await H.AssertBooksBalanceAsync(b.Member, b.Chef);
        }

        [MongoFact]
        public async Task TwoAdminSessions_OnOneStuckHold_OneWinsRestNotStuck()
        {
            var b = await H.PaidAsync(1_000_000, type: "DailyFeedback");
            H.Clock.Set(Vn(2026, 10, 16));
            var results = await BurstAsync(i => H.PostAsync($"/admin/escrow/holds/{b.EscrowId}/resolve", b.Admin,
                i % 2 == 0 ? new { decision = "ReleaseToChef", refundAmount = (long?)null, note = LongNote } : new { decision = "RefundMember", refundAmount = (long?)null, note = LongNote }));
            AssertNoServerError(results);
            Assert.Equal(1, Successes(results));
            Assert.All(results.Where(r => r.Status != HttpStatusCode.OK), r => Assert.Equal("not_stuck", r.Code));
            var member = await H.AvailableAsync(b.Member);
            var chef = await H.AvailableAsync(b.Chef);
            Assert.True((member == 1_000_000 && chef == 0) || (member == 0 && chef == 900_000), $"member {member}, chef {chef}");
            await H.AssertBooksBalanceAsync(b.Member, b.Chef);
        }

        [MongoFact]
        public async Task ChefConfirm_ConcurrentWithComplaint_ExactlyOneOutcomeIsConsistent()
        {
            var b = await H.PaidAsync();
            await H.DeliverAllAsync(b);
            H.Clock.Set(Vn(2026, 10, 13));
            var results = await Task.WhenAll(
                H.PostAsync($"/chefs/me/bookings/{b.Id}/complete", b.Chef),
                H.PostAsync($"/bookings/{b.Id}/complaint", b.Member, ComplaintBody()),
                H.PostAsync($"/chefs/me/bookings/{b.Id}/complete", b.Chef));
            AssertNoServerError(results);
            var row = await H.BookingAsync(b.Id, b.Member);
            // Khiếu nại luôn thắng về tiền: có khiếu nại thì Frozen, kể cả khi chuyên gia xác nhận trước.
            Assert.Equal("Frozen", row.GetProperty("escrow").GetProperty("status").GetString());
            Assert.Equal("Disputed", row.GetProperty("status").GetString());
        }

        [MongoFact]
        public async Task DoubleClick_ChefComplete_OnlyOneSucceeds()
        {
            var b = await H.PaidAsync();
            await H.DeliverAllAsync(b);
            H.Clock.Set(Vn(2026, 10, 13));
            var results = await BurstAsync(_ => H.PostAsync($"/chefs/me/bookings/{b.Id}/complete", b.Chef));
            AssertNoServerError(results);
            Assert.Equal(1, Successes(results));
            Assert.All(results.Where(r => r.Status != HttpStatusCode.OK), r => Assert.Equal("not_active", r.Code));
            var messages = (await H.OkAsync(H.GetAsync($"/bookings/{b.Id}/messages", b.Chef))).Data.EnumerateArray();
            Assert.Single(messages.Where(m => m.GetProperty("body").GetString()!.Contains("xác nhận hoàn thành")));
        }

        [MongoFact]
        public async Task ConcurrentJobsAndReads_ReleasePaysOnce()
        {
            var b = await H.PaidAsync(1_000_000);
            await H.DeliverAllAsync(b);
            H.Clock.Set(Vn(2026, 12, 1));
            await Task.WhenAll(
                H.RunJobAsync(), H.RunJobAsync(), H.RunJobAsync(),
                H.GetAsync($"/bookings/{b.Id}", b.Chef), H.GetAsync($"/bookings/{b.Id}", b.Member),
                H.GetAsync("/chefs/me/wallet", b.Chef), H.GetAsync("/admin/escrow/holds", b.Admin));
            await H.RunJobAsync();
            Assert.Equal(900_000, await H.AvailableAsync(b.Chef));
            await H.AssertBooksBalanceAsync(b.Chef);
            var messages = (await H.OkAsync(H.GetAsync($"/bookings/{b.Id}/messages", b.Chef))).Data.EnumerateArray();
            Assert.Single(messages.Where(m => m.GetProperty("body").GetString()!.StartsWith("Hết 7 ngày")));
        }

        [MongoFact]
        public async Task DoubleClick_Cancel_RefundsOnce()
        {
            var b = await H.PaidAsync(1_000_000);
            var results = await BurstAsync(_ => H.PostAsync($"/bookings/{b.Id}/cancel", b.Member, new { reason = "Đổi kế hoạch" }));
            AssertNoServerError(results);
            Assert.Equal(1, Successes(results));
            Assert.Equal(1_000_000, await H.AvailableAsync(b.Member));
            await H.AssertBooksBalanceAsync(b.Member);
        }

        [MongoFact]
        public async Task DoubleClick_WalletPayment_DebitsOnce()
        {
            var member = await H.UserAsync();
            await H.FundWalletAsync(member, 2_000_000);
            var chef = await H.ChefAsync();
            var id = await H.RequestAsync(member, chef);
            var orderId = await H.AgreeAsync(id, member, chef, 600_000);

            var results = await BurstAsync(_ => H.PostAsync($"/orders/{orderId}/wallet-payment", member));
            AssertNoServerError(results);
            Assert.True(Successes(results) >= 1);
            Assert.All(results.Where(r => r.Status != HttpStatusCode.OK), r => Assert.Equal("not_awaiting_payment", r.Code));
            Assert.Equal(1_400_000, await H.AvailableAsync(member));
            Assert.Equal(1, (await H.Db.WalletLedger.Find(e => e.BookingId == id && e.UserId == member.Id).ToListAsync()).Count(e => e.DeltaAvailable < 0));
            var order = await H.OkAsync(H.GetAsync($"/orders/{orderId}", member));
            Assert.Equal("Paid", order.Data.GetProperty("status").GetString());
            var booking = await H.Db.Bookings.Find(x => x.Id == id).FirstAsync();
            Assert.Single(booking.Order!.Payments, p => p.Status == "Paid");
            await H.AssertBooksBalanceAsync(member);
        }

        [MongoFact]
        public async Task SameBalance_TwoBookingsAtOnce_OnlyOneCanSpendIt()
        {
            var member = await H.UserAsync();
            await H.FundWalletAsync(member, 600_000);
            var chef = await H.ChefAsync();
            var ids = new List<string>();
            var orders = new List<string>();
            for (var i = 0; i < 4; i++)
            {
                var id = await H.RequestAsync(member, chef);
                ids.Add(id);
                orders.Add(await H.AgreeAsync(id, member, chef, 600_000));
            }
            var results = await Task.WhenAll(orders.Select(o => H.PostAsync($"/orders/{o}/wallet-payment", member)));
            AssertNoServerError(results);
            Assert.Equal(1, Successes(results));
            Assert.All(results.Where(r => r.Status != HttpStatusCode.OK), r => Assert.Equal("insufficient_balance", r.Code));
            Assert.Equal(0, await H.AvailableAsync(member));
            await H.AssertBooksBalanceAsync(member);
        }

        [MongoFact]
        public async Task SandboxAndWallet_RaceOnOneOrder_MemberNeverPaysTwice()
        {
            var member = await H.UserAsync();
            var admin = await H.AdminAsync();
            await H.FundWalletAsync(member, 600_000);
            var chef = await H.ChefAsync();
            var id = await H.RequestAsync(member, chef);
            var orderId = await H.AgreeAsync(id, member, chef, 600_000);
            var qr = await H.OpenQrAsync(id, member);

            var results = await Task.WhenAll(
                H.PostAsync($"/orders/{orderId}/wallet-payment", member),
                H.PostAsync($"/payments/{qr}/sandbox-confirm", admin, new { success = true }));
            AssertNoServerError(results);
            await H.RunJobAsync();

            var booking = await H.Db.Bookings.Find(x => x.Id == id).FirstAsync();
            Assert.Equal("Active", booking.Status);
            Assert.Equal(600_000, booking.Escrow!.Amount);
            // Khoản thua được trả lại ví: thành viên cuối cùng chỉ mất đúng một lần giá.
            var sandboxPaid = booking.Order!.Payments.Any(p => p.Provider == "Sandbox" && p.Status == "Paid");
            var walletPaid = booking.Order.Payments.Any(p => p.Provider == "Wallet" && p.Status == "Paid");
            var expected = (sandboxPaid, walletPaid) switch
            {
                (true, false) => 600_000,      // ví không bị trừ, hoặc đã hoàn lại
                (false, true) => 0,            // trả bằng ví
                _ => 600_000                   // cổng về sau ví: khoản của cổng hoàn vào ví
            };
            Assert.Equal(expected, await H.AvailableAsync(member));
            await H.AssertBooksBalanceAsync(member);
        }

        [MongoFact]
        public async Task DoubleClick_Withdrawal_OneRequestOneHold()
        {
            var member = await H.UserAsync();
            await H.FundWalletAsync(member, 500_000);
            await H.SaveBankAsync(member);
            var results = await BurstAsync(_ => H.PostAsync("/users/me/withdrawals", member, new { amount = 200_000 }));
            AssertNoServerError(results);
            Assert.True(results.All(r => r.Status == HttpStatusCode.Created), string.Join(" | ", results.Select(r => $"{(int)r.Status} {r.Code}")));
            Assert.Single(results.Select(r => r.Data.GetProperty("id").GetString()).Distinct());
            Assert.Equal((300_000L, 200_000L, 0L), await H.FiguresAsync(member));
            await H.AssertBooksBalanceAsync(member);
        }

        [MongoFact]
        public async Task WithdrawalsAtOnce_DifferentAmounts_CannotOverdraw()
        {
            var member = await H.UserAsync();
            await H.FundWalletAsync(member, 500_000);
            await H.SaveBankAsync(member);
            var results = await Task.WhenAll(Enumerable.Range(0, Parallel).Select(i => H.PostAsync("/users/me/withdrawals", member, new { amount = 300_000 + i })));
            AssertNoServerError(results);
            Assert.Equal(1, Successes(results));
            Assert.All(results.Where(r => r.Status != HttpStatusCode.Created), r => Assert.Equal("insufficient_balance", r.Code));
            var figures = await H.FiguresAsync(member);
            Assert.Equal(500_000, figures.Available + figures.Processing);
            Assert.Single((await H.OkAsync(H.GetAsync("/users/me/withdrawals", member))).Data.EnumerateArray());
            await H.AssertBooksBalanceAsync(member);
        }

        [MongoFact]
        public async Task TwoAdmins_ApproveAndReject_OneWithdrawal_OneOutcome()
        {
            var member = await H.UserAsync();
            await H.FundWalletAsync(member, 500_000);
            await H.SaveBankAsync(member);
            var admin = await H.AdminAsync();
            var other = await H.AdminAsync("Trần Thu Hằng");
            var id = (await H.OkAsync(H.PostAsync("/users/me/withdrawals", member, new { amount = 500_000 }))).Data.GetProperty("id").GetString()!;

            var results = await Task.WhenAll(
                H.PostAsync($"/admin/withdrawals/{id}/complete", admin, new { transactionRef = "FT26100101" }),
                H.PostAsync($"/admin/withdrawals/{id}/reject", other, new { reason = "Tên chủ tài khoản không khớp" }),
                H.PostAsync($"/admin/withdrawals/{id}/complete", other, new { transactionRef = "FT26100102" }),
                H.PostAsync($"/admin/withdrawals/{id}/reject", admin, new { reason = "Tên chủ tài khoản không khớp" }));
            AssertNoServerError(results);
            Assert.Equal(1, Successes(results));
            Assert.All(results.Where(r => r.Status != HttpStatusCode.OK), r => Assert.Equal("already_processed", r.Code));
            var figures = await H.FiguresAsync(member);
            Assert.True(figures == (500_000, 0, 0) || figures == (0, 0, 500_000), figures.ToString());
            await H.AssertBooksBalanceAsync(member);
        }

        /* ---------------------------------------------------------------- chết máy, mất phản hồi */

        [MongoTheory]
        [InlineData(CommerceFailpointNames.BookingAfterCommit)]
        [InlineData(CommerceFailpointNames.LedgerAfterInsert)]
        [InlineData(CommerceFailpointNames.LedgerAfterApply)]
        public async Task Crash_DuringDecision_ResponseLost_RetryRefused_JobFinishes_PaysOnce(string point)
        {
            var b = await H.PaidAsync(1_000_000);
            var complaintId = (await H.OkAsync(H.PostAsync($"/bookings/{b.Id}/complaint", b.Member, ComplaintBody()))).Data.GetProperty("complaint").GetProperty("id").GetString()!;

            H.Failpoints.Arm(point);
            var crashed = await H.PostAsync($"/admin/complaints/{complaintId}/decision", b.Admin, new { decision = "Split", refundAmount = 400_000, note = LongNote });
            Assert.Equal(HttpStatusCode.InternalServerError, crashed.Status);

            // Máy chủ đã ghi quyết định dù client không nhận được phản hồi: thử lại bị từ chối, không trả lần hai.
            AssertError(await H.PostAsync($"/admin/complaints/{complaintId}/decision", b.Admin, new { decision = "RefundMember", note = LongNote }), HttpStatusCode.Conflict, "already_decided");

            await H.RunJobAsync();
            await H.RunJobAsync();
            Assert.Equal(400_000, await H.AvailableAsync(b.Member));
            Assert.Equal(540_000, await H.AvailableAsync(b.Chef));
            await H.AssertBooksBalanceAsync(b.Member, b.Chef);
            var booking = await H.Db.Bookings.Find(x => x.Id == b.Id).FirstAsync();
            Assert.Empty(booking.Outbox);
            Assert.All(await H.Db.WalletLedger.Find(e => e.BookingId == b.Id).ToListAsync(), e => Assert.True(e.Applied));
        }

        [MongoTheory]
        [InlineData(CommerceFailpointNames.BookingAfterCommit)]
        [InlineData(CommerceFailpointNames.LedgerAfterInsert)]
        [InlineData(CommerceFailpointNames.LedgerAfterApply)]
        public async Task Crash_DuringAutomaticRelease_NextReadOrJobFinishes_PaysOnce(string point)
        {
            var b = await H.PaidAsync(1_000_000);
            await H.DeliverAllAsync(b);
            H.Clock.Set(Vn(2026, 12, 1));

            H.Failpoints.Arm(point);
            var crashed = await H.GetAsync($"/bookings/{b.Id}", b.Chef);
            Assert.Equal(HttpStatusCode.InternalServerError, crashed.Status);

            Assert.Equal("Completed", (await H.BookingAsync(b.Id, b.Member)).GetProperty("status").GetString());
            await H.RunJobAsync();
            Assert.Equal(900_000, await H.AvailableAsync(b.Chef));
            await H.AssertBooksBalanceAsync(b.Chef);
        }

        [MongoFact]
        public async Task Crash_BetweenLedgerInsertAndBalance_ReconcileAppliesFromTheLedger()
        {
            var b = await H.PaidAsync(1_000_000);
            H.Failpoints.Arm(CommerceFailpointNames.LedgerAfterInsert);
            var crashed = await H.PostAsync($"/bookings/{b.Id}/cancel", b.Member, new { reason = "Đổi kế hoạch" });
            Assert.Equal(HttpStatusCode.InternalServerError, crashed.Status);

            var entry = await H.Db.WalletLedger.Find(e => e.BookingId == b.Id).SingleAsync();
            Assert.False(entry.Applied);
            var before = await H.Db.Wallets.Find(w => w.Id == b.Member.Id).FirstOrDefaultAsync();
            Assert.Equal(0, before?.Available ?? 0);

            await H.RunJobAsync();
            var after = await H.Db.Wallets.Find(w => w.Id == b.Member.Id).FirstAsync();
            Assert.Equal(1_000_000, after.Available);
            Assert.True((await H.Db.WalletLedger.Find(e => e.BookingId == b.Id).SingleAsync()).Applied);
            await H.RunJobAsync();
            Assert.Equal(1_000_000, (await H.Db.Wallets.Find(w => w.Id == b.Member.Id).FirstAsync()).Available);
        }

        [MongoFact]
        public async Task Crash_AfterBalanceBeforeMark_ReconcileDoesNotApplyTwice()
        {
            var b = await H.PaidAsync(1_000_000);
            H.Failpoints.Arm(CommerceFailpointNames.LedgerAfterApply);
            Assert.Equal(HttpStatusCode.InternalServerError, (await H.PostAsync($"/bookings/{b.Id}/cancel", b.Member, new { reason = "Đổi kế hoạch" })).Status);

            var entry = await H.Db.WalletLedger.Find(e => e.BookingId == b.Id).SingleAsync();
            Assert.False(entry.Applied);
            Assert.Equal(1_000_000, (await H.Db.Wallets.Find(w => w.Id == b.Member.Id).FirstAsync()).Available);

            await H.RunJobAsync();
            await H.RunJobAsync();
            Assert.Equal(1_000_000, await H.AvailableAsync(b.Member));
            await H.AssertBooksBalanceAsync(b.Member);
        }

        [MongoFact]
        public async Task LedgerKey_SecondInsertWithSameKey_IsRefusedByMongo()
        {
            var key = $"booking:{ObjectId.GenerateNewId()}:income";
            var entry = new DomainLayer.Entities.WalletLedgerEntry { Id = DomainLayer.Entities.WalletLedgerEntry.IdForKey(key), IdempotencyKey = key, UserId = "u", Kind = "income", Type = "Income", DeltaAvailable = 1 };
            await H.Db.WalletLedger.InsertOneAsync(entry);
            await Assert.ThrowsAsync<MongoWriteException>(() => H.Db.WalletLedger.InsertOneAsync(entry));

            // Chỉ mục riêng cũng chặn, kể cả khi _id khác.
            var indexes = await (await H.Db.WalletLedger.Indexes.ListAsync()).ToListAsync();
            Assert.Contains(indexes, i => i.Contains("unique") && i["unique"].AsBoolean && i["key"].AsBsonDocument.Contains("IdempotencyKey"));
            var clone = new DomainLayer.Entities.WalletLedgerEntry { Id = ObjectId.GenerateNewId().ToString(), IdempotencyKey = key, UserId = "u", Kind = "income", Type = "Income" };
            await Assert.ThrowsAsync<MongoWriteException>(() => H.Db.WalletLedger.InsertOneAsync(clone));
        }

        [MongoFact]
        public async Task Crash_WalletPayment_AfterDebit_JobFundsBooking_RetryDoesNotDebitAgain()
        {
            var member = await H.UserAsync();
            await H.FundWalletAsync(member, 1_000_000);
            var chef = await H.ChefAsync();
            var id = await H.RequestAsync(member, chef);
            var orderId = await H.AgreeAsync(id, member, chef, 600_000);

            H.Failpoints.Arm(CommerceFailpointNames.WalletPayAfterDebit);
            Assert.Equal(HttpStatusCode.InternalServerError, (await H.PostAsync($"/orders/{orderId}/wallet-payment", member)).Status);
            Assert.Equal(400_000, await H.AvailableAsync(member));
            Assert.Equal("AwaitingPayment", (await H.BookingAsync(id, member)).GetProperty("status").GetString());

            // Client thử lại ngay: cùng bút toán, không trừ lần hai, booking được nhận tiền.
            var retried = await H.OkAsync(H.PostAsync($"/orders/{orderId}/wallet-payment", member));
            Assert.Equal("Paid", retried.Data.GetProperty("status").GetString());
            Assert.Equal(400_000, await H.AvailableAsync(member));
            await H.AssertBooksBalanceAsync(member);
        }

        [MongoFact]
        public async Task Crash_WalletPayment_NoRetry_JobFinishesAfterGrace()
        {
            var member = await H.UserAsync();
            await H.FundWalletAsync(member, 1_000_000);
            var chef = await H.ChefAsync();
            var id = await H.RequestAsync(member, chef);
            var orderId = await H.AgreeAsync(id, member, chef, 600_000);

            H.Failpoints.Arm(CommerceFailpointNames.WalletPayAfterDebit);
            Assert.Equal(HttpStatusCode.InternalServerError, (await H.PostAsync($"/orders/{orderId}/wallet-payment", member)).Status);

            await H.RunJobAsync();
            Assert.Equal("AwaitingPayment", (await H.BookingAsync(id, member)).GetProperty("status").GetString());

            H.Clock.Advance(TimeSpan.FromMinutes(3));
            await H.RunJobAsync();
            Assert.Equal("Active", (await H.BookingAsync(id, member)).GetProperty("status").GetString());
            Assert.Equal(400_000, await H.AvailableAsync(member));
            AssertError(await H.PostAsync($"/orders/{orderId}/wallet-payment", member), HttpStatusCode.Conflict, "not_awaiting_payment");
            await H.AssertBooksBalanceAsync(member);
        }

        [MongoFact]
        public async Task Crash_WalletPayment_BookingClosedMeanwhile_JobGivesMoneyBack()
        {
            var member = await H.UserAsync();
            await H.FundWalletAsync(member, 1_000_000);
            var chef = await H.ChefAsync();
            var id = await H.RequestAsync(member, chef);
            var orderId = await H.AgreeAsync(id, member, chef, 600_000);

            H.Failpoints.Arm(CommerceFailpointNames.WalletPayAfterDebit);
            Assert.Equal(HttpStatusCode.InternalServerError, (await H.PostAsync($"/orders/{orderId}/wallet-payment", member)).Status);
            await H.OkAsync(H.PostAsync($"/bookings/{id}/cancel", member, new { reason = "Huỷ khi đang lỗi" }));

            H.Clock.Advance(TimeSpan.FromMinutes(3));
            await H.RunJobAsync();
            await H.RunJobAsync();
            Assert.Equal(1_000_000, await H.AvailableAsync(member));
            Assert.Equal("Cancelled", (await H.BookingAsync(id, member)).GetProperty("status").GetString());
            await H.AssertBooksBalanceAsync(member);
        }

        [MongoFact]
        public async Task Crash_WalletPayment_BeforeDebit_VoidedAfterGrace_ThenCanPayAgain()
        {
            var member = await H.UserAsync();
            await H.FundWalletAsync(member, 1_000_000);
            var chef = await H.ChefAsync();
            var id = await H.RequestAsync(member, chef);
            var orderId = await H.AgreeAsync(id, member, chef, 600_000);

            H.Failpoints.Arm(CommerceFailpointNames.LedgerAfterInsert);
            Assert.Equal(HttpStatusCode.InternalServerError, (await H.PostAsync($"/orders/{orderId}/wallet-payment", member)).Status);
            Assert.Equal(1_000_000, await H.AvailableAsync(member));

            H.Clock.Advance(TimeSpan.FromMinutes(3));
            await H.RunJobAsync();
            Assert.Equal(1_000_000, await H.AvailableAsync(member));
            var entries = await H.Db.WalletLedger.Find(e => e.BookingId == id && e.UserId == member.Id).ToListAsync();
            Assert.True(entries.Single(e => e.Kind == "wallet_payment").Voided);

            await H.OkAsync(H.PostAsync($"/orders/{orderId}/wallet-payment", member));
            Assert.Equal(400_000, await H.AvailableAsync(member));
            await H.AssertBooksBalanceAsync(member);
        }

        [MongoFact]
        public async Task Crash_Withdrawal_BeforeDebit_NothingStuck_RequestDiscarded()
        {
            var member = await H.UserAsync();
            await H.FundWalletAsync(member, 500_000);
            await H.SaveBankAsync(member);

            H.Failpoints.Arm(CommerceFailpointNames.WithdrawalAfterInsert);
            Assert.Equal(HttpStatusCode.InternalServerError, (await H.PostAsync("/users/me/withdrawals", member, new { amount = 200_000 })).Status);
            Assert.Equal((500_000L, 0L, 0L), await H.FiguresAsync(member));
            Assert.Empty((await H.OkAsync(H.GetAsync("/users/me/withdrawals", member))).Data.EnumerateArray());

            H.Clock.Advance(TimeSpan.FromMinutes(3));
            await H.RunJobAsync();
            Assert.Equal((500_000L, 0L, 0L), await H.FiguresAsync(member));
            Assert.Empty((await H.OkAsync(H.GetAsync("/users/me/withdrawals", member))).Data.EnumerateArray());

            await H.OkAsync(H.PostAsync("/users/me/withdrawals", member, new { amount = 200_000 }));
            Assert.Equal((300_000L, 200_000L, 0L), await H.FiguresAsync(member));
            await H.AssertBooksBalanceAsync(member);
        }

        [MongoFact]
        public async Task Crash_Withdrawal_AfterDebit_JobRevealsRequest_NoMoneyLost()
        {
            var member = await H.UserAsync();
            await H.FundWalletAsync(member, 500_000);
            await H.SaveBankAsync(member);

            H.Failpoints.Arm(CommerceFailpointNames.WithdrawalAfterDebit);
            Assert.Equal(HttpStatusCode.InternalServerError, (await H.PostAsync("/users/me/withdrawals", member, new { amount = 200_000 })).Status);
            Assert.Equal((300_000L, 200_000L, 0L), await H.FiguresAsync(member));

            H.Clock.Advance(TimeSpan.FromMinutes(3));
            await H.RunJobAsync();
            var row = (await H.OkAsync(H.GetAsync("/users/me/withdrawals", member))).Data.EnumerateArray().Single();
            Assert.Equal("Processing", row.GetProperty("status").GetString());
            var admin = await H.AdminAsync();
            await H.OkAsync(H.PostAsync($"/admin/withdrawals/{row.GetProperty("id").GetString()}/reject", admin, new { reason = "Tên chủ tài khoản không khớp" }));
            Assert.Equal((500_000L, 0L, 0L), await H.FiguresAsync(member));
            await H.AssertBooksBalanceAsync(member);
        }

        [MongoTheory]
        [InlineData("reject", 500_000, 0, 0)]
        [InlineData("complete", 0, 0, 500_000)]
        public async Task Crash_WithdrawalDecision_ResponseLost_JobPostsOnce(string action, long available, long processing, long withdrawn)
        {
            var member = await H.UserAsync();
            await H.FundWalletAsync(member, 500_000);
            await H.SaveBankAsync(member);
            var admin = await H.AdminAsync();
            var id = (await H.OkAsync(H.PostAsync("/users/me/withdrawals", member, new { amount = 500_000 }))).Data.GetProperty("id").GetString()!;
            object body = action == "reject" ? new { reason = "Tên chủ tài khoản không khớp" } : new { transactionRef = "FT26100103" };

            H.Failpoints.Arm(CommerceFailpointNames.WithdrawalAfterDecision);
            Assert.Equal(HttpStatusCode.InternalServerError, (await H.PostAsync($"/admin/withdrawals/{id}/{action}", admin, body)).Status);
            AssertError(await H.PostAsync($"/admin/withdrawals/{id}/{action}", admin, body), HttpStatusCode.Conflict, "already_processed");

            await H.RunJobAsync();
            await H.RunJobAsync();
            Assert.Equal((available, processing, withdrawn), await H.FiguresAsync(member));
            await H.AssertBooksBalanceAsync(member);
        }
    }

    /* ==================================================================== quyền */

    public class Sprint9_AuthorizationTests : IClassFixture<CommerceWebApplicationFactory>
    {
        private readonly CommerceHarness H;

        public Sprint9_AuthorizationTests(CommerceWebApplicationFactory factory)
        {
            H = new CommerceHarness(factory);
            H.Clock.Set(T0);
        }

        private const string Fake = "507f1f77bcf86cd799439011";

        public static IEnumerable<object[]> AdminRoutes() => new[]
        {
            new object[] { "GET", "/admin/complaints" },
            new object[] { "GET", $"/admin/complaints/{Fake}" },
            new object[] { "POST", $"/admin/complaints/{Fake}/decision" },
            new object[] { "GET", "/admin/escrow/summary" },
            new object[] { "GET", "/admin/escrow/holds" },
            new object[] { "POST", $"/admin/escrow/holds/{Fake}/resolve" },
            new object[] { "GET", "/admin/commerce/summary" },
            new object[] { "GET", "/admin/orders" },
            new object[] { "GET", $"/admin/orders/{Fake}" },
            new object[] { "POST", $"/admin/orders/{Fake}/cancel" },
            new object[] { "GET", "/admin/withdrawals" },
            new object[] { "POST", $"/admin/withdrawals/{Fake}/complete" },
            new object[] { "POST", $"/admin/withdrawals/{Fake}/reject" },
            new object[] { "GET", "/admin/wallets" },
            new object[] { "GET", $"/admin/wallets/{Fake}/transactions" },
            new object[] { "GET", "/admin/payouts/summary" },
        };

        [MongoTheory]
        [MemberData(nameof(AdminRoutes))]
        public async Task AdminRoutes_401WithoutToken_403ForMemberAndChef(string method, string path)
        {
            var m = new HttpMethod(method);
            object? body = method == "POST" ? new { } : null;
            AssertError(await H.CallAsync(m, path, null, body), HttpStatusCode.Unauthorized, "unauthorized");
            AssertError(await H.CallAsync(m, path, await H.UserAsync(), body), HttpStatusCode.Forbidden, "forbidden");
            AssertError(await H.CallAsync(m, path, await H.ChefAsync(), body), HttpStatusCode.Forbidden, "forbidden");
        }

        public static IEnumerable<object[]> LoggedInRoutes() => new[]
        {
            new object[] { "POST", "/bookings" },
            new object[] { "GET", "/bookings/me" },
            new object[] { "GET", $"/bookings/{Fake}" },
            new object[] { "GET", "/chefs/me/bookings" },
            new object[] { "GET", "/users/me/wallet" },
            new object[] { "GET", "/chefs/me/wallet" },
            new object[] { "POST", "/users/me/withdrawals" },
            new object[] { "POST", "/chefs/me/withdrawals" },
            new object[] { "GET", $"/orders/{Fake}" },
            new object[] { "POST", $"/orders/{Fake}/wallet-payment" },
            new object[] { "GET", $"/payments/{Fake}" },
            new object[] { "POST", $"/payments/{Fake}/sandbox-confirm" },
        };

        [MongoTheory]
        [MemberData(nameof(LoggedInRoutes))]
        public async Task EveryMoneyRoute_RequiresToken(string method, string path)
        {
            var m = new HttpMethod(method);
            AssertError(await H.CallAsync(m, path, null, method == "POST" ? new { } : null), HttpStatusCode.Unauthorized, "unauthorized");
        }

        [MongoFact]
        public async Task ChefRoutes_ForMember_Are403NotChef()
        {
            var member = await H.UserAsync();
            AssertError(await H.GetAsync("/chefs/me/bookings", member), HttpStatusCode.Forbidden, "not_chef");
            AssertError(await H.GetAsync("/chefs/me/wallet", member), HttpStatusCode.Forbidden, "not_chef");
            AssertError(await H.GetAsync("/chefs/me/wallet/transactions", member), HttpStatusCode.Forbidden, "not_chef");
            AssertError(await H.GetAsync("/chefs/me/withdrawals", member), HttpStatusCode.Forbidden, "not_chef");
            AssertError(await H.PostAsync("/chefs/me/withdrawals", member, new { amount = 100_000 }), HttpStatusCode.Forbidden, "not_chef");
            AssertError(await H.PutAsync("/chefs/me/bank-account", member, new { bankName = "ACB", accountNumber = "123456", accountHolder = "ABC" }), HttpStatusCode.Forbidden, "not_chef");
            AssertError(await H.PostAsync($"/chefs/me/bookings/{Fake}/complete", member), HttpStatusCode.Forbidden, "not_chef");
        }

        [MongoFact]
        public async Task Stranger_Gets404_OnEveryBookingOrderAndPaymentRoute()
        {
            var b = await H.PaidAsync();
            var stranger = await H.UserAsync();
            var otherChef = await H.ChefAsync();
            var complaint = new { reason = "other", description = new string('x', 40), requestedOutcome = "FullRefund", evidence = new[] { new { kind = "Link", url = "https://a.vn" } } };

            foreach (var user in new[] { stranger, otherChef })
            {
                AssertError(await H.GetAsync($"/bookings/{b.Id}", user), HttpStatusCode.NotFound, "not_found");
                AssertError(await H.GetAsync($"/bookings/{b.Id}/messages", user), HttpStatusCode.NotFound, "not_found");
                AssertError(await H.PostAsync($"/bookings/{b.Id}/messages", user, new { body = "xin chào" }), HttpStatusCode.NotFound, "not_found");
                AssertError(await H.PostAsync($"/bookings/{b.Id}/offers", user, new { price = 500_000, planDays = 3, bookingType = "OneShot", startDate = "2026-10-10" }), HttpStatusCode.NotFound, "not_found");
                AssertError(await H.PostAsync($"/bookings/{b.Id}/cancel", user, new { reason = "Muốn huỷ hộ" }), HttpStatusCode.NotFound, "not_found");
                AssertError(await H.PostAsync($"/bookings/{b.Id}/payments", user), HttpStatusCode.NotFound, "not_found");
                AssertError(await H.GetAsync($"/bookings/{b.Id}/plan", user), HttpStatusCode.NotFound, "not_found");
                AssertError(await H.PutAsync($"/bookings/{b.Id}/plan/days/1/feedback", user, new { rating = 5, adherence = "All", body = "" }), HttpStatusCode.NotFound, "not_found");
                AssertError(await H.PostAsync($"/bookings/{b.Id}/complaint", user, complaint), HttpStatusCode.NotFound, "not_found");
                AssertError(await H.GetAsync($"/orders/{b.OrderId}", user), HttpStatusCode.NotFound, "not_found");
                AssertError(await H.PostAsync($"/orders/{b.OrderId}/payments", user), HttpStatusCode.NotFound, "not_found");
                AssertError(await H.PostAsync($"/orders/{b.OrderId}/wallet-payment", user), HttpStatusCode.NotFound, "not_found");
                AssertError(await H.GetAsync($"/payments/{b.PaymentId}", user), HttpStatusCode.NotFound, "not_found");
            }

            AssertError(await H.PostAsync($"/chefs/me/bookings/{b.Id}/complete", otherChef), HttpStatusCode.NotFound, "not_found");
            AssertError(await H.PostAsync($"/chefs/me/bookings/{b.Id}/decline", otherChef, new { reason = "Không muốn làm nữa" }), HttpStatusCode.NotFound, "not_found");
            AssertError(await H.PutAsync($"/chefs/me/bookings/{b.Id}/plan/days/1", otherChef, new { meals = Array.Empty<object>() }), HttpStatusCode.NotFound, "not_found");
            AssertError(await H.PostAsync($"/chefs/me/bookings/{b.Id}/plan/send", otherChef), HttpStatusCode.NotFound, "not_found");
            AssertError(await H.PostAsync($"/chefs/me/bookings/{b.Id}/complaint/response", otherChef, new { text = new string('a', 25) }), HttpStatusCode.NotFound, "not_found");
            Assert.Empty((await H.OkAsync(H.GetAsync("/chefs/me/bookings", otherChef))).Data.EnumerateArray());
            Assert.Empty((await H.OkAsync(H.GetAsync("/bookings/me", stranger))).Data.EnumerateArray());
        }

        [MongoFact]
        public async Task WrongParty_Gets403()
        {
            var b = await H.PaidAsync();
            AssertError(await H.PostAsync($"/bookings/{b.Id}/cancel", b.Chef, new { reason = "Chuyên gia muốn huỷ" }), HttpStatusCode.Forbidden, "wrong_party");
            AssertError(await H.PostAsync($"/bookings/{b.Id}/payments", b.Chef), HttpStatusCode.Forbidden, "wrong_party");
            AssertError(await H.PutAsync($"/bookings/{b.Id}/plan/days/1/feedback", b.Chef, new { rating = 5, adherence = "All", body = "" }), HttpStatusCode.Forbidden, "wrong_party");
            AssertError(await H.PostAsync($"/bookings/{b.Id}/complaint", b.Chef, new { reason = "other" }), HttpStatusCode.Forbidden, "wrong_party");

            // Thành viên cũng là chuyên gia của booking khác: vẫn không thao tác được phía chuyên gia của booking này.
            var chefAsMember = await H.ChefAsync();
            var booking = await H.PaidAsync(member: chefAsMember, chef: b.Chef, admin: b.Admin);
            AssertError(await H.PostAsync($"/chefs/me/bookings/{booking.Id}/complete", chefAsMember), HttpStatusCode.Forbidden, "wrong_party");
            AssertError(await H.PostAsync($"/chefs/me/bookings/{booking.Id}/decline", chefAsMember, new { reason = "Tôi là người đặt mà" }), HttpStatusCode.Forbidden, "wrong_party");
        }

        [MongoFact]
        public async Task Wallets_AreIsolatedPerUser()
        {
            var b = await H.PaidAsync(1_000_000);
            await H.OkAsync(H.PostAsync($"/bookings/{b.Id}/cancel", b.Member, new { reason = "Đổi kế hoạch" }));
            var stranger = await H.UserAsync();
            Assert.Equal(0, await H.AvailableAsync(stranger));
            Assert.Empty((await H.OkAsync(H.GetAsync("/users/me/wallet/transactions", stranger))).Data.EnumerateArray());
            Assert.Empty((await H.OkAsync(H.GetAsync("/users/me/withdrawals", stranger))).Data.EnumerateArray());
        }

        [MongoFact]
        public async Task SandboxConfirm_ForbiddenForBuyerAndChef_OrderStaysUnpaid()
        {
            var member = await H.UserAsync();
            var chef = await H.ChefAsync();
            var id = await H.RequestAsync(member, chef);
            var orderId = await H.AgreeAsync(id, member, chef, 500_000);
            var qr = await H.OpenQrAsync(id, member);

            AssertError(await H.PostAsync($"/payments/{qr}/sandbox-confirm", null, new { success = true }), HttpStatusCode.Unauthorized, "unauthorized");
            AssertError(await H.PostAsync($"/payments/{qr}/sandbox-confirm", member, new { success = true }), HttpStatusCode.Forbidden, "forbidden");
            AssertError(await H.PostAsync($"/payments/{qr}/sandbox-confirm", chef, new { success = true }), HttpStatusCode.Forbidden, "forbidden");

            // Không có route webhook nào nhận yêu cầu không xác thực.
            foreach (var path in new[] { "/payments/webhook", "/payments/payos/webhook", "/webhooks/payment", $"/payments/{qr}/confirm", $"/orders/{orderId}/confirm" })
            {
                var attempt = await H.PostAsync(path, null, new { orderId, paymentId = qr, status = "PAID" });
                Assert.True(attempt.Status is HttpStatusCode.NotFound or HttpStatusCode.Unauthorized or HttpStatusCode.MethodNotAllowed, $"{path}: {(int)attempt.Status}");
            }
            Assert.Equal("Pending", (await H.OkAsync(H.GetAsync($"/orders/{orderId}", member))).Data.GetProperty("status").GetString());
            Assert.Equal("AwaitingPayment", (await H.BookingAsync(id, member)).GetProperty("status").GetString());
        }
    }

    /* ==================================================================== không có cổng thanh toán */

    public class Sprint9_NoPaymentProviderTests : IClassFixture<NoProviderFactory>
    {
        private readonly CommerceHarness H;

        public Sprint9_NoPaymentProviderTests(NoProviderFactory factory)
        {
            H = new CommerceHarness(factory);
            H.Clock.Set(T0);
        }

        [MongoFact]
        public async Task NoProvider_QrRoutesReturn503_WalletStillPays_SandboxRouteIs404()
        {
            var member = await H.UserAsync();
            var chef = await H.ChefAsync();
            var admin = await H.AdminAsync();
            var id = await H.RequestAsync(member, chef);
            var orderId = await H.AgreeAsync(id, member, chef, 500_000);

            var start = await H.PostAsync($"/bookings/{id}/payments", member);
            AssertError(start, HttpStatusCode.ServiceUnavailable, "payment_unavailable");
            Assert.Contains("Cổng thanh toán chưa được cấu hình", start.Root.GetProperty("message").GetString());
            AssertError(await H.PostAsync($"/orders/{orderId}/payments", member), HttpStatusCode.ServiceUnavailable, "payment_unavailable");
            AssertError(await H.PostAsync($"/payments/{ObjectId.GenerateNewId()}/sandbox-confirm", admin, new { success = true }), HttpStatusCode.NotFound, "not_found");

            Assert.Equal("Pending", (await H.OkAsync(H.GetAsync($"/orders/{orderId}", member))).Data.GetProperty("status").GetString());
            AssertError(await H.PostAsync($"/orders/{orderId}/wallet-payment", member), HttpStatusCode.Conflict, "insufficient_balance");

            // Không có cổng để nạp tiền, nên ghi một khoản hoàn qua đúng đường sổ cái.
            await H.CreditAsync(member, 500_000);
            var paid = (await H.OkAsync(H.PostAsync($"/orders/{orderId}/wallet-payment", member))).Data;
            Assert.Equal("Paid", paid.GetProperty("status").GetString());
            Assert.Equal("Wallet", paid.GetProperty("payment").GetProperty("provider").GetString());
        }
    }

    /* ==================================================================== job nền thật */

    public class Sprint9_HostedJobTests : IClassFixture<JobOnFactory>
    {
        private readonly CommerceHarness H;

        public Sprint9_HostedJobTests(JobOnFactory factory)
        {
            H = new CommerceHarness(factory);
            H.Clock.Set(T0);
        }

        [MongoFact]
        public async Task BackgroundService_ReleasesMoney_WithoutAnyRead()
        {
            var b = await H.PaidAsync(1_000_000);
            await H.DeliverAllAsync(b);
            H.Clock.Set(Vn(2026, 12, 1));

            var deadline = DateTime.UtcNow.AddSeconds(15);
            DomainLayer.Entities.Wallet? wallet = null;
            while (DateTime.UtcNow < deadline)
            {
                wallet = await H.Db.Wallets.Find(w => w.Id == b.Chef.Id).FirstOrDefaultAsync();
                if (wallet?.Available > 0) break;
                await Task.Delay(200);
            }
            Assert.Equal(900_000, wallet?.Available);
            var booking = await H.Db.Bookings.Find(x => x.Id == b.Id).FirstAsync();
            Assert.Equal("Completed", booking.Status);
            Assert.True(booking.AutoCompleted);
        }
    }

    /* ==================================================================== các route đọc của admin */

    public class Sprint9_AdminReadTests
    {
        [MongoFact]
        public async Task Swagger_Generates_AndListsEveryContractRoute()
        {
            using var factory = new CommerceWebApplicationFactory();
            var H = new CommerceHarness(factory);
            var (status, body) = await H.RawGetAsync("/swagger/v1/swagger.json");
            Assert.Equal(HttpStatusCode.OK, status);
            var paths = JsonDocument.Parse(body).RootElement.GetProperty("paths");

            var expected = new (string Method, string Path)[]
            {
                ("post", "/bookings"), ("get", "/bookings/me"), ("get", "/bookings/{id}"),
                ("get", "/bookings/{id}/messages"), ("post", "/bookings/{id}/messages"),
                ("post", "/bookings/{id}/offers"), ("post", "/bookings/{id}/offers/{offerId}/accept"), ("post", "/bookings/{id}/offers/{offerId}/reject"),
                ("post", "/bookings/{id}/cancel"), ("post", "/bookings/{id}/payments"), ("get", "/bookings/{id}/plan"),
                ("put", "/bookings/{id}/plan/days/{dayIndex}/feedback"), ("post", "/bookings/{id}/complaint"), ("get", "/bookings/{id}/complaint"),
                ("get", "/chefs/me/bookings"), ("post", "/chefs/me/bookings/{id}/decline"), ("put", "/chefs/me/bookings/{id}/plan/days/{dayIndex}"),
                ("post", "/chefs/me/bookings/{id}/plan/days/{dayIndex}/send"), ("post", "/chefs/me/bookings/{id}/plan/send"),
                ("post", "/chefs/me/bookings/{id}/complete"), ("post", "/chefs/me/bookings/{id}/complaint/response"),
                ("get", "/orders/{id}"), ("post", "/orders/{id}/payments"), ("post", "/orders/{id}/wallet-payment"), ("get", "/payments/{id}"),
                ("get", "/users/me/wallet"), ("get", "/users/me/wallet/transactions"), ("put", "/users/me/bank-account"), ("get", "/users/me/withdrawals"), ("post", "/users/me/withdrawals"),
                ("get", "/chefs/me/wallet"), ("get", "/chefs/me/wallet/transactions"), ("put", "/chefs/me/bank-account"), ("get", "/chefs/me/withdrawals"), ("post", "/chefs/me/withdrawals"),
                ("get", "/admin/complaints"), ("get", "/admin/complaints/{id}"), ("post", "/admin/complaints/{id}/decision"),
                ("get", "/admin/escrow/summary"), ("get", "/admin/escrow/holds"), ("post", "/admin/escrow/holds/{id}/resolve"),
                ("get", "/admin/commerce/summary"), ("get", "/admin/orders"), ("get", "/admin/orders/{id}"), ("post", "/admin/orders/{id}/cancel"),
                ("get", "/admin/withdrawals"), ("post", "/admin/withdrawals/{id}/complete"), ("post", "/admin/withdrawals/{id}/reject"),
                ("get", "/admin/wallets"), ("get", "/admin/wallets/{userId}/transactions"), ("get", "/admin/payouts/summary"),
            };
            foreach (var (method, path) in expected)
            {
                Assert.True(paths.TryGetProperty($"/api/v1{path}", out var item) && item.TryGetProperty(method, out _), $"Thiếu route {method} {path}");
            }
            // Không có đường nào đánh dấu đã trả ngoài route sandbox dành cho Admin.
            Assert.DoesNotContain(paths.EnumerateObject(), p => p.Name.Contains("webhook", StringComparison.OrdinalIgnoreCase));
        }

        [MongoFact]
        public async Task ServerLogs_NeverContainAccountNumbersTokensOrConnectionStrings()
        {
            using var factory = new CommerceWebApplicationFactory();
            var H = new CommerceHarness(factory);
            H.Clock.Set(T0);

            var member = await H.UserAsync();
            await H.FundWalletAsync(member, 500_000);
            await H.SaveBankAsync(member);
            await H.OkAsync(H.PostAsync("/users/me/withdrawals", member, new { amount = 200_000 }));
            // Cả đường lỗi: yêu cầu chết giữa chừng thì stack trace vào log.
            H.Failpoints.Arm(CommerceFailpointNames.WithdrawalAfterDebit);
            Assert.Equal(HttpStatusCode.InternalServerError, (await H.PostAsync("/users/me/withdrawals", member, new { amount = 150_000 })).Status);
            AssertError(await H.PutAsync("/users/me/bank-account", member, new { bankName = "ACB", accountNumber = "99999999999999999999999", accountHolder = "ABC" }), HttpStatusCode.BadRequest, "validation");
            H.Clock.Advance(TimeSpan.FromMinutes(3));
            await H.RunJobAsync();

            var logs = string.Join("\n", H.ServerLogs);
            Assert.Contains("SimulatedCrash", logs); // log thật sự được thu lại
            Assert.DoesNotContain("0071000456789", logs);
            Assert.DoesNotContain("99999999999999999999999", logs);
            Assert.DoesNotContain(member.Token, logs);
            Assert.DoesNotContain("VeganLife_Integration_Test_Secret_Key", logs);
            Assert.DoesNotContain("mongodb://", logs);
        }

        [MongoFact]
        public async Task Summaries_ListsAndSearch_OnAFreshDatabase_ExactNumbers()
        {
            using var factory = new CommerceWebApplicationFactory();
            var H = new CommerceHarness(factory);
            H.Clock.Set(T0);

            var admin = await H.AdminAsync();
            var chef = await H.ChefAsync("Lê Quang Tâm");
            var member = await H.UserAsync(name: "Ngọc Trâm");

            // 1. Đang giữ, chưa xác nhận.
            var active = await H.PaidAsync(1_000_000, member: member, chef: chef, admin: admin);
            // 2. Đang khiếu nại.
            var disputed = await H.PaidAsync(2_000_000, member: member, chef: chef, admin: admin);
            var complaintId = (await H.OkAsync(H.PostAsync($"/bookings/{disputed.Id}/complaint", member, new
            {
                reason = "allergen",
                description = "Ngày 2 có món chứa chất tôi đã khai dị ứng.",
                requestedOutcome = "PartialRefund",
                requestedAmount = 500_000,
                evidence = new[] { new { kind = "Link", url = "https://example.com/a" } }
            }))).Data.GetProperty("complaint").GetProperty("id").GetString()!;
            // 3. Chưa trả.
            var expiringId = await H.RequestAsync(member, chef);
            await H.AgreeAsync(expiringId, member, chef, 300_000);

            var escrow = (await H.OkAsync(H.GetAsync("/admin/escrow/summary", admin))).Data;
            Assert.Equal(3_000_000, escrow.GetProperty("totalHeld").GetInt64());
            Assert.Equal(2, escrow.GetProperty("totalHeldCount").GetInt32());
            Assert.Equal(2_000_000, escrow.GetProperty("frozen").GetInt64());
            Assert.Equal(1_000_000, escrow.GetProperty("awaitingCompletion").GetInt64());
            Assert.Equal(1, escrow.GetProperty("openComplaints").GetInt32());
            Assert.Equal(0, escrow.GetProperty("stuckCount").GetInt32());
            Assert.Equal(7, escrow.GetProperty("holdDays").GetInt32());

            var commerce = (await H.OkAsync(H.GetAsync("/admin/commerce/summary", admin))).Data;
            Assert.Equal(3_000_000, commerce.GetProperty("revenue").GetInt64());
            Assert.Equal(300_000, commerce.GetProperty("pendingAmount").GetInt64());
            Assert.Equal(3, commerce.GetProperty("totalOrders").GetInt32());
            Assert.Equal(2, commerce.GetProperty("byStatus").GetProperty("Paid").GetInt32());
            Assert.Equal(1, commerce.GetProperty("byStatus").GetProperty("Pending").GetInt32());
            Assert.Equal(0, commerce.GetProperty("byStatus").GetProperty("Refunded").GetInt32());
            Assert.Equal(3_000_000, commerce.GetProperty("heldAmount").GetInt64());

            // Khiếu nại: danh sách không có planDays/messages, chi tiết có; tìm không dấu.
            var open = (await H.OkAsync(H.GetAsync("/admin/complaints?status=Open", admin))).Data.EnumerateArray().Single();
            Assert.Equal(complaintId, open.GetProperty("id").GetString());
            Assert.Empty(open.GetProperty("planDays").EnumerateArray());
            Assert.Empty(open.GetProperty("messages").EnumerateArray());
            Assert.Equal("Ngọc Trâm", open.GetProperty("booking").GetProperty("member").GetProperty("fullName").GetString());
            Assert.Single((await H.OkAsync(H.GetAsync("/admin/complaints?status=Open&search=ngoc%20tram", admin))).Data.EnumerateArray());
            Assert.Single((await H.OkAsync(H.GetAsync("/admin/complaints?search=di%20ung", admin))).Data.EnumerateArray());
            Assert.Empty((await H.OkAsync(H.GetAsync("/admin/complaints?status=Resolved", admin))).Data.EnumerateArray());
            Assert.Empty((await H.OkAsync(H.GetAsync("/admin/complaints?search=khong-co-ai", admin))).Data.EnumerateArray());
            var detail = (await H.OkAsync(H.GetAsync($"/admin/complaints/{complaintId}", admin))).Data;
            Assert.Equal(3, detail.GetProperty("planDays").GetArrayLength());
            Assert.NotEmpty(detail.GetProperty("messages").EnumerateArray());
            AssertError(await H.GetAsync($"/admin/complaints/{ObjectId.GenerateNewId()}", admin), HttpStatusCode.NotFound, "not_found");

            // Giữ tiền: active xếp theo releaseAt, null xuống cuối.
            var withDate = await H.PaidAsync(500_000, member: member, chef: chef, admin: admin);
            await H.DeliverAllAsync(withDate);
            H.Clock.Set(Vn(2026, 10, 12));
            await H.OkAsync(H.PostAsync($"/chefs/me/bookings/{withDate.Id}/complete", chef));
            var holds = (await H.OkAsync(H.GetAsync("/admin/escrow/holds?status=active", admin))).Data.EnumerateArray().ToList();
            Assert.Equal(3, holds.Count);
            Assert.Equal(withDate.EscrowId, holds[0].GetProperty("id").GetString());
            Assert.Equal(JsonValueKind.Null, holds[^1].GetProperty("releaseAt").ValueKind);
            Assert.Equal(member.Id, holds[0].GetProperty("booking").GetProperty("member").GetProperty("id").GetString());
            Assert.False(holds[0].GetProperty("isStuck").GetBoolean());
            Assert.Single((await H.OkAsync(H.GetAsync("/admin/escrow/holds?status=Frozen", admin))).Data.EnumerateArray());
            Assert.Single((await H.OkAsync(H.GetAsync($"/admin/escrow/holds?search={active.Id}", admin))).Data.EnumerateArray());

            // Đơn: tìm theo mã giao dịch, huỷ đơn chưa trả, không huỷ được đơn đã trả. Đơn chưa trả ở trên đã quá hạn.
            Assert.Equal("Expired", (await H.BookingAsync(expiringId, member)).GetProperty("status").GetString());
            var pendingId = await H.RequestAsync(member, chef, start: "2026-10-20");
            var pendingOrder = await H.AgreeAsync(pendingId, member, chef, 300_000, start: "2026-10-20");
            var orders = (await H.OkAsync(H.GetAsync("/admin/orders", admin))).Data.EnumerateArray().ToList();
            Assert.Equal(5, orders.Count);
            var paidOrder = orders.Single(o => o.GetProperty("id").GetString() == active.OrderId);
            Assert.Equal(member.Id, paidOrder.GetProperty("buyer").GetProperty("id").GetString());
            Assert.Equal(chef.Id, paidOrder.GetProperty("booking").GetProperty("chef").GetProperty("id").GetString());
            Assert.Equal(chef.Id, paidOrder.GetProperty("booking").GetProperty("chefId").GetString());
            Assert.Equal("Paid", paidOrder.GetProperty("payments")[0].GetProperty("status").GetString());
            var reference = paidOrder.GetProperty("payments")[0].GetProperty("transactionRef").GetString()!;
            Assert.Single((await H.OkAsync(H.GetAsync($"/admin/orders?search={reference}", admin))).Data.EnumerateArray());
            Assert.Single((await H.OkAsync(H.GetAsync("/admin/orders?status=Pending", admin))).Data.EnumerateArray());

            AssertError(await H.PostAsync($"/admin/orders/{active.OrderId}/cancel", admin, new { note = "Không nên huỷ đơn này" }), HttpStatusCode.Conflict, "not_pending");
            AssertError(await H.PostAsync($"/admin/orders/{pendingOrder}/cancel", admin, new { note = "ngắn" }), HttpStatusCode.BadRequest, "note_too_short");
            AssertError(await H.PostAsync($"/admin/orders/{ObjectId.GenerateNewId()}/cancel", admin, new { note = "Đơn không tồn tại" }), HttpStatusCode.NotFound, "not_found");
            var cancelled = (await H.OkAsync(H.PostAsync($"/admin/orders/{pendingOrder}/cancel", admin, new { note = "Thành viên nhờ huỷ giúp" }))).Data;
            Assert.Equal("Cancelled", cancelled.GetProperty("status").GetString());
            Assert.Equal("cancel", cancelled.GetProperty("resolution").GetProperty("action").GetString());
            Assert.Equal("Cancelled", (await H.BookingAsync(pendingId, member)).GetProperty("status").GetString());

            // Ví và rút tiền.
            await H.OkAsync(H.PostAsync($"/admin/complaints/{complaintId}/decision", admin, new { decision = "Split", refundAmount = 500_000, note = "Hoàn một phần theo bằng chứng đã gửi." }));
            H.Clock.Set(Vn(2026, 10, 19));
            await H.SaveBankAsync(member);
            await H.OkAsync(H.PostAsync("/users/me/withdrawals", member, new { amount = 200_000 }));
            await H.OkAsync(H.PutAsync("/chefs/me/bank-account", chef, new { bankName = "MB Bank", accountNumber = "1234567890", accountHolder = "Le Quang Tam" }));
            var chefWithdrawal = (await H.OkAsync(H.PostAsync("/chefs/me/withdrawals", chef, new { amount = 100_000 }))).Data.GetProperty("id").GetString()!;
            await H.OkAsync(H.PostAsync($"/admin/withdrawals/{chefWithdrawal}/complete", admin, new { transactionRef = "FT26101901" }));

            var wallets = (await H.OkAsync(H.GetAsync("/admin/wallets", admin))).Data.EnumerateArray().ToList();
            var chefRow = wallets.Single(w => w.GetProperty("userId").GetString() == chef.Id);
            Assert.Equal("chef", chefRow.GetProperty("role").GetString());
            // Split 2.000.000 hoàn 500.000: gross 1.500.000, net 1.350.000. withDate 500.000 đã nhả: net 450.000.
            Assert.Equal(1_350_000 + 450_000 - 100_000, chefRow.GetProperty("available").GetInt64());
            Assert.Equal(100_000, chefRow.GetProperty("withdrawn").GetInt64());
            Assert.Equal(900_000, chefRow.GetProperty("pending").GetInt64());
            Assert.Equal("1234567890", chefRow.GetProperty("bankAccount").GetProperty("accountNumber").GetString());
            Assert.NotEqual(JsonValueKind.Null, chefRow.GetProperty("lastWithdrawalAt").ValueKind);
            Assert.Equal(1_000_000 + 1_500_000 + 500_000, chefRow.GetProperty("grossSales").GetInt64());
            Assert.Equal(100_000 + 150_000 + 50_000, chefRow.GetProperty("feeTotal").GetInt64());
            var memberRow = wallets.Single(w => w.GetProperty("userId").GetString() == member.Id);
            Assert.Equal("member", memberRow.GetProperty("role").GetString());
            Assert.Equal(300_000, memberRow.GetProperty("available").GetInt64());
            Assert.Equal(200_000, memberRow.GetProperty("processing").GetInt64());
            Assert.Equal(500_000, memberRow.GetProperty("refundTotal").GetInt64());
            Assert.DoesNotContain(wallets, w => w.GetProperty("userId").GetString() == admin.Id);

            var tx = (await H.OkAsync(H.GetAsync($"/admin/wallets/{chef.Id}/transactions?limit=2", admin))).Data.EnumerateArray().ToList();
            Assert.Equal(2, tx.Count);
            Assert.True(tx[0].GetProperty("createdAt").GetDateTime() >= tx[1].GetProperty("createdAt").GetDateTime());
            AssertError(await H.GetAsync($"/admin/wallets/{ObjectId.GenerateNewId()}/transactions", admin), HttpStatusCode.NotFound, "not_found");

            var searchBank = (await H.OkAsync(H.GetAsync("/admin/withdrawals?search=vietcombank", admin))).Data.EnumerateArray().Single();
            Assert.Equal(member.Id, searchBank.GetProperty("userId").GetString());
            Assert.Single((await H.OkAsync(H.GetAsync("/admin/withdrawals?search=FT26101901", admin))).Data.EnumerateArray());
            Assert.Single((await H.OkAsync(H.GetAsync("/admin/withdrawals?status=Completed", admin))).Data.EnumerateArray());

            var payouts = (await H.OkAsync(H.GetAsync("/admin/payouts/summary", admin))).Data;
            Assert.Equal(1_700_000 + 300_000, payouts.GetProperty("totalAvailable").GetInt64());
            Assert.Equal(300_000, payouts.GetProperty("availableByRole").GetProperty("member").GetInt64());
            Assert.Equal(1_700_000, payouts.GetProperty("availableByRole").GetProperty("chef").GetInt64());
            Assert.Equal(200_000, payouts.GetProperty("totalProcessing").GetInt64());
            Assert.Equal(100_000, payouts.GetProperty("paidOutThisMonth").GetInt64());
            Assert.Equal(1, payouts.GetProperty("paidOutThisMonthCount").GetInt32());
            Assert.Equal(200_000, payouts.GetProperty("platformFee").GetInt64());
            Assert.Equal(2_000_000, payouts.GetProperty("releasedGross").GetInt64());
            Assert.Equal(2, payouts.GetProperty("releasedCount").GetInt32());
            Assert.Equal(1, payouts.GetProperty("byStatus").GetProperty("Processing").GetInt32());
            Assert.Equal(1, payouts.GetProperty("byRole").GetProperty("chef").GetProperty("Completed").GetInt32());
            Assert.Equal(1, payouts.GetProperty("awaitingApproval").GetInt32());
            Assert.Equal(200_000, payouts.GetProperty("awaitingApprovalAmount").GetInt64());

            await H.AssertBooksBalanceAsync(member, chef);

            // Bảo toàn tiền toàn hệ thống: tiền vào = ví + phí + đang giữ + đã rút.
            var inflow = 1_000_000L + 2_000_000L + 500_000L;
            var fee = 200_000L;
            var heldNow = 1_000_000L;
            var inWallets = await H.AvailableAsync(member) + 200_000L + 1_700_000L + 100_000L;
            Assert.Equal(inflow, inWallets + fee + heldNow);
        }
    }
}
