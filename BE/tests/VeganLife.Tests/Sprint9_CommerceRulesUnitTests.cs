using DomainLayer.Constants;
using DomainLayer.Entities;
using DomainLayer.Helpers;
using Xunit;

namespace VeganLife.Tests
{
    public class Sprint9_MoneyMathTests
    {
        [Theory]
        [InlineData(0, 0)]
        [InlineData(4, 0)]      // 0,4 làm tròn xuống
        [InlineData(5, 1)]      // 0,5 làm tròn lên, giống Math.round ở FE
        [InlineData(14, 1)]
        [InlineData(15, 2)]
        [InlineData(100_000, 10_000)]
        [InlineData(123_456, 12_346)]
        [InlineData(122_456, 12_246)]
        [InlineData(1_050_000, 105_000)]
        [InlineData(50_000_000, 5_000_000)]
        public void Fee_IsTenPercentRoundedHalfUp(long gross, long fee) => Assert.Equal(fee, MoneyMath.Fee(gross));

        [Fact]
        public void ReleaseToChef_KeepsNinetyPercent()
        {
            var o = MoneyMath.Decide(1_500_000, ComplaintDecisions.ReleaseToChef, null);
            Assert.Equal(0, o.Refund);
            Assert.Equal(1_500_000, o.ChefGross);
            Assert.Equal(150_000, o.Fee);
            Assert.Equal(1_350_000, o.ChefNet);
        }

        [Fact]
        public void RefundMember_TakesNoFee()
        {
            var o = MoneyMath.Decide(1_500_000, ComplaintDecisions.RefundMember, 999);
            Assert.Equal(1_500_000, o.Refund);
            Assert.Equal(0, o.ChefGross);
            Assert.Equal(0, o.Fee);
            Assert.Equal(0, o.ChefNet);
        }

        [Fact]
        public void Split_FeeIsOnChefPortionOnly()
        {
            var o = MoneyMath.Decide(1_050_000, ComplaintDecisions.Split, 300_000);
            Assert.Equal(300_000, o.Refund);
            Assert.Equal(750_000, o.ChefGross);
            Assert.Equal(75_000, o.Fee);
            Assert.Equal(675_000, o.ChefNet);
        }

        [Fact]
        public void Conservation_MemberPlusChefPlusFee_EqualsPrice_ForEveryRoundingCase()
        {
            var random = new Random(20261102);
            for (var i = 0; i < 200_000; i++)
            {
                var price = random.NextInt64(CommerceRules.MinPrice, CommerceRules.MaxPrice + 1);
                var x = random.NextInt64(CommerceRules.MinPartialRefund, price);
                var o = MoneyMath.Decide(price, ComplaintDecisions.Split, x);
                Assert.Equal(price, o.Refund + o.ChefNet + o.Fee);
                Assert.Equal(MoneyMath.Fee(price - x), o.Fee);
                Assert.True(o.ChefNet >= 0 && o.Fee >= 0);
            }
            // Các số cuối 1..9 đi qua mọi trường hợp làm tròn.
            for (long tail = 0; tail < 20; tail++)
            {
                var o = MoneyMath.Decide(100_000 + tail, ComplaintDecisions.Split, 1_000);
                Assert.Equal(100_000 + tail, o.Refund + o.ChefNet + o.Fee);
            }
        }

        [Theory]
        [InlineData(999, 100_000, false)]
        [InlineData(1_000, 100_000, true)]
        [InlineData(99_999, 100_000, true)]
        [InlineData(100_000, 100_000, false)]
        public void PartialRefund_MustBeAtLeast1000AndBelowPrice(long x, long price, bool valid) =>
            Assert.Equal(valid, MoneyMath.IsValidPartialRefund(x, price));

        [Fact]
        public void PartialRefund_Missing_IsInvalid() => Assert.False(MoneyMath.IsValidPartialRefund(null, 100_000));

        [Fact]
        public void Vnd_FormatsLikeTheApp() => Assert.Equal("1.500.000đ", MoneyMath.Vnd(1_500_000));
    }

    public class Sprint9_VnTimeTests
    {
        private static DateTime Utc(int y, int mo, int d, int h = 0, int mi = 0, int s = 0) => new(y, mo, d, h, mi, s, DateTimeKind.Utc);

        [Fact]
        public void DateOf_RollsOverAt17Utc()
        {
            Assert.Equal("2026-10-20", VnTime.DateOf(Utc(2026, 10, 20, 16, 59, 59)));
            Assert.Equal("2026-10-21", VnTime.DateOf(Utc(2026, 10, 20, 17, 0, 0)));
        }

        [Fact]
        public void DateOf_CrossesMonthAndYear()
        {
            Assert.Equal("2026-11-01", VnTime.DateOf(Utc(2026, 10, 31, 17)));
            Assert.Equal("2027-01-01", VnTime.DateOf(Utc(2026, 12, 31, 17)));
            Assert.Equal("2028-02-29", VnTime.DateOf(Utc(2028, 2, 28, 17)));
        }

        [Fact]
        public void At_ConvertsVnWallClockToUtc()
        {
            Assert.Equal(Utc(2026, 10, 19, 23), VnTime.At("2026-10-20", 6, 0));
            Assert.Equal(Utc(2026, 10, 19, 17), VnTime.At("2026-10-20", 0, 0));
            Assert.Equal(DateTimeKind.Utc, VnTime.At("2026-10-20", 0, 0).Kind);
        }

        [Fact]
        public void PlanEndDate_CrossesMonth() => Assert.Equal("2026-11-02", VnTime.PlanEndDate("2026-10-28", 6));

        [Fact]
        public void AutoCompleteAndRelease_MatchDocumentedExample()
        {
            // Tài liệu: kết thúc 30/10, tự hoàn tất 23:59 ngày 02/11, nhả tiền 23:59 ngày 09/11.
            var at = VnTime.AutoCompleteAt("2026-10-30");
            Assert.Equal(Utc(2026, 11, 2, 16, 59), at);
            Assert.Equal(Utc(2026, 11, 9, 16, 59), VnTime.ReleaseAt(at));
        }

        [Fact]
        public void PaymentDueAt_IsTheEarlierOfWindowAndStart()
        {
            var accepted = Utc(2026, 10, 1, 3);
            Assert.Equal(accepted.AddHours(48), VnTime.PaymentDueAt(accepted, "2026-10-10"));
            Assert.Equal(VnTime.At("2026-10-02", 0, 0), VnTime.PaymentDueAt(accepted, "2026-10-02"));
        }

        [Fact]
        public void DeliveryDueAt_FollowsBookingType()
        {
            var start = "2026-10-10";
            Assert.Equal(VnTime.At(start, 6, 0), VnTime.DeliveryDueAt(BookingTypes.DailyFeedback, start, Utc(2026, 10, 1)));
            Assert.Equal(VnTime.At(start, 0, 0), VnTime.DeliveryDueAt(BookingTypes.OneShot, start, Utc(2026, 10, 1)));
            var late = VnTime.At(start, 0, 0).AddHours(-1);
            Assert.Equal(late.AddHours(24), VnTime.DeliveryDueAt(BookingTypes.OneShot, start, late));
        }

        [Theory]
        [InlineData("2026-10-20", true)]
        [InlineData("2026-02-30", false)]
        [InlineData("20/10/2026", false)]
        [InlineData("", false)]
        [InlineData(null, false)]
        public void TryParseDate_AcceptsOnlyRealIsoDates(string? raw, bool valid) => Assert.Equal(valid, VnTime.TryParseDate(raw, out _));

        [Fact]
        public void MonthStart_UsesVietnamCalendar()
        {
            // 17:00 UTC ngày 31/10 đã là tháng 11 ở Việt Nam.
            Assert.Equal(Utc(2026, 10, 31, 17), VnTime.MonthStart(Utc(2026, 10, 31, 17)));
            Assert.Equal(Utc(2026, 9, 30, 17), VnTime.MonthStart(Utc(2026, 10, 31, 16, 59, 59)));
        }
    }

    public class Sprint9_SettlementRuleTests
    {
        private const string End = "2026-10-12";
        private static readonly DateTime Moment = VnTime.AutoCompleteAt(End);

        private static ChefBooking Paid(int delivered = 3, DateTime? sentAt = null)
        {
            var sent = sentAt ?? VnTime.At("2026-10-09", 20, 0);
            var b = new ChefBooking
            {
                Id = BookingLifecycle.NewId(),
                MemberId = "m",
                ChefId = "c",
                MemberName = "Minh Anh",
                ChefName = "Quang Tâm",
                BookingType = BookingTypes.OneShot,
                PlanDays = 3,
                StartDate = "2026-10-10",
                Status = BookingStatuses.Active,
                Contract = new BookingContract { Id = "ct", Price = 900_000, PlanDays = 3, BookingType = BookingTypes.OneShot, StartDate = "2026-10-10", EndDate = End, PaymentDueAt = VnTime.At("2026-10-10", 0, 0) },
                Escrow = new EscrowHold { Id = "eh", PaymentId = "p", Amount = 900_000, Status = EscrowStatuses.Held, HeldAt = VnTime.At("2026-10-05", 9, 0), AutoCompleteAt = Moment },
                Order = new BookingOrder { Id = "o", Amount = 900_000, Status = OrderStatuses.Paid }
            };
            for (var i = 1; i <= 3; i++)
            {
                b.Days.Add(new BookingPlanDay
                {
                    DayIndex = i,
                    Date = VnTime.AddDays("2026-10-10", i - 1),
                    Status = i <= delivered ? PlanDayStatuses.Sent : null,
                    SentAt = i <= delivered ? sent : null
                });
            }
            return b;
        }

        [Fact]
        public void AutoComplete_OneSecondBefore_DoesNothing()
        {
            var b = Paid();
            Assert.False(BookingLifecycle.Settle(b, Moment.AddSeconds(-1)));
            Assert.Null(b.CompletedAt);
            Assert.Equal(BookingStatuses.Active, b.Status);
        }

        [Fact]
        public void AutoComplete_ExactlyAtMoment_Completes()
        {
            var b = Paid();
            Assert.True(BookingLifecycle.Settle(b, Moment));
            Assert.Equal(Moment, b.CompletedAt);
            Assert.True(b.AutoCompleted);
            Assert.Equal(BookingStatuses.Ended, b.Status);
            Assert.Equal(Moment, b.Escrow!.CompletedAt);
            Assert.Equal(Moment.AddDays(7), b.Escrow.ReleaseAt);
            Assert.Equal(EscrowStatuses.Held, b.Escrow.Status);
            Assert.Empty(b.Outbox);
            Assert.Single(b.Messages);
        }

        [Fact]
        public void AutoComplete_OneSecondAfter_UsesTheMomentNotTheClock()
        {
            var b = Paid();
            BookingLifecycle.Settle(b, Moment.AddSeconds(1));
            Assert.Equal(Moment, b.CompletedAt);
            Assert.Equal(Moment, b.UpdatedAt);
        }

        [Fact]
        public void RunningLate_GivesTheSameResultAsRunningOnTime()
        {
            var onTime = Paid();
            BookingLifecycle.Settle(onTime, Moment);
            BookingLifecycle.Settle(onTime, Moment.AddDays(7));

            var late = Paid();
            BookingLifecycle.Settle(late, Moment.AddDays(40));

            Assert.Equal(onTime.CompletedAt, late.CompletedAt);
            Assert.Equal(onTime.Escrow!.ReleaseAt, late.Escrow!.ReleaseAt);
            Assert.Equal(onTime.Escrow.ReleasedAt, late.Escrow.ReleasedAt);
            Assert.Equal(onTime.Escrow.Status, late.Escrow.Status);
            Assert.Equal(onTime.Status, late.Status);
            Assert.Equal(onTime.Outbox.Single().Net, late.Outbox.Single().Net);
            Assert.Equal(onTime.Outbox.Single().OccurredAt, late.Outbox.Single().OccurredAt);
            Assert.Equal(onTime.Messages.Select(m => m.CreatedAt), late.Messages.Select(m => m.CreatedAt));
        }

        [Fact]
        public void Settle_RunTwice_ChangesNothingTheSecondTime()
        {
            var b = Paid();
            Assert.True(BookingLifecycle.Settle(b, Moment.AddDays(8)));
            var messages = b.Messages.Count;
            Assert.False(BookingLifecycle.Settle(b, Moment.AddDays(9)));
            Assert.Equal(messages, b.Messages.Count);
            Assert.Single(b.Outbox);
        }

        [Fact]
        public void MissingDays_DoNotAutoComplete_AndBecomeStuck()
        {
            var b = Paid(delivered: 2);
            Assert.False(BookingLifecycle.Settle(b, Moment.AddDays(30)));
            Assert.Null(b.CompletedAt);
            Assert.False(b.AutoCompleted);
            Assert.False(BookingLifecycle.IsStuck(b, Moment.AddSeconds(-1)));
            Assert.True(BookingLifecycle.IsStuck(b, Moment));
        }

        [Fact]
        public void DayDeliveredAfterTheMoment_DoesNotAutoComplete()
        {
            var b = Paid(delivered: 3, sentAt: Moment.AddSeconds(1));
            Assert.False(BookingLifecycle.Settle(b, Moment.AddDays(30)));
            Assert.True(BookingLifecycle.IsStuck(b, Moment.AddDays(30)));
        }

        [Fact]
        public void DayDeliveredExactlyAtTheMoment_Counts()
        {
            var b = Paid(delivered: 3, sentAt: Moment);
            Assert.True(BookingLifecycle.Settle(b, Moment));
            Assert.True(b.AutoCompleted);
        }

        [Fact]
        public void Release_OneSecondBefore_StaysHeld_ExactlyAt_Released()
        {
            var b = Paid();
            BookingLifecycle.Settle(b, Moment);
            var releaseAt = b.Escrow!.ReleaseAt!.Value;

            Assert.False(BookingLifecycle.Settle(b, releaseAt.AddSeconds(-1)));
            Assert.Equal(EscrowStatuses.Held, b.Escrow.Status);

            Assert.True(BookingLifecycle.Settle(b, releaseAt));
            Assert.Equal(EscrowStatuses.Released, b.Escrow.Status);
            Assert.Equal(releaseAt, b.Escrow.ReleasedAt);
            Assert.Equal(900_000, b.Escrow.ReleasedAmount);
            Assert.Equal(90_000, b.Escrow.FeeAmount);
            Assert.Equal(BookingStatuses.Completed, b.Status);
            var income = b.Outbox.Single();
            Assert.Equal(810_000, income.Net);
            Assert.Equal("c", income.UserId);
            Assert.Equal($"booking:{b.Id}:income", income.Key);
        }

        [Fact]
        public void OpenComplaint_FreezesEverything()
        {
            var b = Paid();
            BookingLifecycle.Settle(b, Moment);
            b.Complaint = new BookingComplaint { Id = "cp", Status = ComplaintStatuses.Open };
            b.Escrow!.Status = EscrowStatuses.Frozen;
            b.Status = BookingStatuses.Disputed;

            Assert.False(BookingLifecycle.Settle(b, Moment.AddDays(100)));
            Assert.Equal(EscrowStatuses.Frozen, b.Escrow.Status);
            Assert.Empty(b.Outbox);
            Assert.False(BookingLifecycle.IsStuck(b, Moment.AddDays(100)));
        }

        [Fact]
        public void PaymentDue_ExactlyAtDue_StillOpen_AfterIt_Expired()
        {
            var b = Paid();
            b.Status = BookingStatuses.AwaitingPayment;
            b.Escrow = null;
            b.Order!.Status = OrderStatuses.Pending;
            b.Order.Payments.Add(new BookingPayment { Id = "p", Status = PaymentStatuses.Pending });
            var due = b.Contract!.PaymentDueAt;

            Assert.False(BookingLifecycle.Settle(b, due));
            Assert.Equal(BookingStatuses.AwaitingPayment, b.Status);

            Assert.True(BookingLifecycle.Settle(b, due.AddMilliseconds(1)));
            Assert.Equal(BookingStatuses.Expired, b.Status);
            Assert.Equal(due, b.UpdatedAt);
            Assert.Equal(OrderStatuses.Cancelled, b.Order.Status);
            Assert.Equal(PaymentStatuses.Expired, b.Order.Payments[0].Status);
        }

        [Fact]
        public void ConfirmCompletion_OneSecondBeforeEndDateInVietnam_IsRefused()
        {
            var b = Paid();
            var ex = Assert.Throws<DomainLayer.Exceptions.ConflictException>(() => BookingLifecycle.ConfirmCompletion(b, VnTime.At(End, 0, 0).AddSeconds(-1)));
            Assert.Equal("plan_not_delivered", ex.ErrorCode);
        }

        [Fact]
        public void ConfirmCompletion_AtMidnightOfEndDate_Works_AndReleaseIsExactlySevenDaysLater()
        {
            var b = Paid();
            var at = VnTime.At(End, 0, 0);
            BookingLifecycle.ConfirmCompletion(b, at);
            Assert.Equal(at, b.CompletedAt);
            Assert.Equal(at.AddDays(7), b.Escrow!.ReleaseAt);
            Assert.False(b.AutoCompleted);
        }

        [Fact]
        public void LedgerId_IsDerivedFromTheKey()
        {
            var a = WalletLedgerEntry.IdForKey("booking:abc:income");
            Assert.Equal(a, WalletLedgerEntry.IdForKey("booking:abc:income"));
            Assert.NotEqual(a, WalletLedgerEntry.IdForKey("booking:abc:refund"));
            Assert.True(MongoDB.Bson.ObjectId.TryParse(a, out _));
        }
    }
}
