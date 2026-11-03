using System;
using System.Linq;
using DomainLayer.Constants;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using MongoDB.Bson;

namespace DomainLayer.Helpers
{
    /// <summary>
    /// Mọi bước đổi trạng thái có dính tới tiền, viết thành hàm thuần trên một document: không đọc đồng hồ,
    /// không chạm DB. Bên gọi tính xong rồi lưu nguyên document bằng một lần ghi có điều kiện theo Version.
    /// </summary>
    public static class BookingLifecycle
    {
        public static string NewId() => ObjectId.GenerateNewId().ToString();

        public static int DeliveredDays(ChefBooking b) => b.Days.Count(d => d.Status == PlanDayStatuses.Sent);

        public static int DeliveredBy(ChefBooking b, DateTime at) =>
            b.Days.Count(d => d.Status == PlanDayStatuses.Sent && d.SentAt is { } sent && sent <= at);

        public static bool HasOpenComplaint(ChefBooking b) => b.Complaint?.Status == ComplaintStatuses.Open;

        public static string PlanTitle(int planDays, string bookingType) => $"Thực đơn {planDays} ngày · {BookingTypes.Label(bookingType)}";

        public static BookingMessage Say(ChefBooking b, string role, string body, DateTime at, string? offerId = null, string? attachmentUrl = null)
        {
            var message = new BookingMessage
            {
                Id = NewId(),
                SenderId = role == BookingParties.Member ? b.MemberId : role == BookingParties.Chef ? b.ChefId : null,
                SenderRole = role,
                Kind = offerId != null ? "Offer" : attachmentUrl != null ? "Attachment" : role == BookingParties.System ? "System" : "Text",
                Body = body,
                OfferId = offerId,
                AttachmentUrl = attachmentUrl,
                CreatedAt = at
            };
            b.Messages.Add(message);
            return message;
        }

        /* ------------------------------------------------------------ quy tắc theo thời gian */

        /// <summary>
        /// Áp các quy tắc thời gian theo dữ liệu đã lưu. Mọi mốc lấy từ dữ liệu, không lấy từ lúc job chạy,
        /// nên chạy trễ cho cùng kết quả với chạy đúng giờ. Không còn gì để làm thì trả false.
        /// </summary>
        public static bool Settle(ChefBooking b, DateTime now)
        {
            var changed = false;
            var contract = b.Contract;
            if (b.Status == BookingStatuses.AwaitingPayment && contract != null && now > contract.PaymentDueAt)
            {
                Expire(b, contract);
                changed = true;
            }

            var escrow = b.Escrow;
            if (escrow == null || escrow.Status != EscrowStatuses.Held || contract == null) return changed;

            if (escrow.CompletedAt == null && b.Status == BookingStatuses.Active && !HasOpenComplaint(b))
            {
                var at = VnTime.AutoCompleteAt(contract.EndDate);
                // Chỉ tính ngày đã giao trước mốc: gửi muộn sau đó không làm khoản này tự hoàn tất nữa.
                if (at <= now && DeliveredBy(b, at) >= b.PlanDays)
                {
                    AutoComplete(b, escrow, at);
                    changed = true;
                }
            }

            if (escrow.ReleaseAt is { } releaseAt && releaseAt <= now)
            {
                Release(b, escrow, releaseAt);
                changed = true;
            }
            return changed;
        }

        /// <summary>Khoản kẹt: đã qua lúc tự hoàn tất mà không có đường tự đi. Gọi sau <see cref="Settle"/>.</summary>
        public static bool IsStuck(ChefBooking b, DateTime now)
        {
            var escrow = b.Escrow;
            var contract = b.Contract;
            return escrow != null && contract != null
                   && escrow.Status == EscrowStatuses.Held
                   && escrow.CompletedAt == null && b.CompletedAt == null && escrow.ReleaseAt == null
                   && !HasOpenComplaint(b)
                   && VnTime.AutoCompleteAt(contract.EndDate) <= now;
        }

        private static void Expire(ChefBooking b, BookingContract contract)
        {
            b.Status = BookingStatuses.Expired;
            b.UpdatedAt = contract.PaymentDueAt;
            CancelUnpaidOrder(b);
            Say(b, BookingParties.System,
                $"Quá hạn thanh toán {CommerceRules.PaymentWindowHours} giờ, yêu cầu đã hết hiệu lực. Thành viên có thể gửi yêu cầu mới.",
                contract.PaymentDueAt);
        }

        private static void AutoComplete(ChefBooking b, EscrowHold escrow, DateTime at)
        {
            var releaseAt = VnTime.ReleaseAt(at);
            b.CompletedAt = at;
            b.AutoCompleted = true;
            b.Status = BookingStatuses.Ended;
            b.UpdatedAt = at;
            escrow.CompletedAt = at;
            escrow.ReleaseAt = releaseAt;
            Say(b, BookingParties.System,
                $"Chuyên gia chưa xác nhận sau {CommerceRules.AutoCompleteDays} ngày kể từ ngày kết thúc kế hoạch, hệ thống tự hoàn tất hợp đồng. " +
                $"VeganLife giữ {MoneyMath.Vnd(escrow.Amount)} đến {VnTime.Stamp(releaseAt)} ({CommerceRules.HoldDays} ngày); không có khiếu nại thì tiền vào ví chuyên gia.",
                at);
        }

        private static void Release(ChefBooking b, EscrowHold escrow, DateTime at)
        {
            var fee = MoneyMath.Fee(escrow.Amount);
            escrow.Status = EscrowStatuses.Released;
            escrow.ReleasedAt = at;
            escrow.ReleasedAmount = escrow.Amount;
            escrow.FeeAmount = fee;
            escrow.ResolvedBy = null;
            escrow.ResolutionNote = null;
            if (b.Status is BookingStatuses.Active or BookingStatuses.Ended) b.Status = BookingStatuses.Completed;
            b.UpdatedAt = at;
            AddIncome(b, escrow, escrow.Amount, fee, at, b.AutoCompleted ? "Hệ thống tự hoàn tất vì chuyên gia không xác nhận" : null, null);
            Say(b, BookingParties.System,
                $"Hết {CommerceRules.HoldDays} ngày giữ tiền, không có khiếu nại: {MoneyMath.Vnd(escrow.Amount - fee)} đã vào ví chuyên gia (sau phí 10%).",
                at);
        }

        /* ------------------------------------------------------------ thanh toán */

        public static void CancelUnpaidOrder(ChefBooking b)
        {
            var order = b.Order;
            if (order == null || order.Status != OrderStatuses.Pending) return;
            order.Status = OrderStatuses.Cancelled;
            foreach (var p in order.Payments.Where(p => p.Status == PaymentStatuses.Pending)) p.Status = PaymentStatuses.Expired;
        }

        /// <summary>Tiền đã về: VeganLife giữ, chưa có ngày chuyển, booking Active.</summary>
        public static void Fund(ChefBooking b, BookingPayment payment, DateTime paidAt)
        {
            var contract = b.Contract!;
            var order = b.Order!;
            foreach (var p in order.Payments.Where(p => p.Status == PaymentStatuses.Pending && p.Id != payment.Id)) p.Status = PaymentStatuses.Expired;
            payment.Status = PaymentStatuses.Paid;
            payment.PaidAt = paidAt;
            order.Status = OrderStatuses.Paid;
            contract.DeliveryDueAt = VnTime.DeliveryDueAt(contract.BookingType, contract.StartDate, paidAt);
            b.Escrow = new EscrowHold
            {
                Id = NewId(),
                PaymentId = payment.Id,
                Amount = contract.Price,
                Status = EscrowStatuses.Held,
                HeldAt = paidAt,
                AutoCompleteAt = VnTime.AutoCompleteAt(contract.EndDate)
            };
            b.Status = BookingStatuses.Active;
            b.UpdatedAt = paidAt;
            var via = payment.Provider == PaymentProviderNames.Wallet ? "bằng ví VeganLife"
                : payment.Provider == PaymentProviderNames.Sandbox ? "qua cổng thử nghiệm (không có tiền thật)"
                : $"qua {payment.Provider}";
            Say(b, BookingParties.System,
                $"Đã thanh toán {MoneyMath.Vnd(contract.Price)} {via}. VeganLife giữ tiền đến {CommerceRules.HoldDays} ngày sau khi hợp đồng hoàn thành.",
                paidAt);
        }

        /// <summary>Tiền về khi booking đã đóng: hoàn thẳng vào ví người trả.</summary>
        public static void RefundLatePayment(ChefBooking b, BookingPayment payment, DateTime at)
        {
            var order = b.Order!;
            payment.Status = PaymentStatuses.Paid;
            payment.PaidAt = at;
            if (b.Escrow == null)
            {
                // Booking đã đóng khi chưa trả. Có giữ tiền rồi thì đơn đã được khoản khác trả: đơn giữ nguyên.
                order.Status = OrderStatuses.Refunded;
                order.RefundedAmount += payment.Amount;
            }
            b.UpdatedAt = at;
            AddIntent(b, new LedgerIntent
            {
                Key = LedgerKinds.BookingKey(b.Id, $"{LedgerKinds.LateRefund}:{payment.Id}"),
                Kind = LedgerKinds.LateRefund,
                Type = LedgerTypes.Refund,
                UserId = b.MemberId,
                Net = payment.Amount,
                Note = "Khoản thanh toán đến sau khi yêu cầu đã đóng",
                PaymentId = payment.Id,
                TransactionRef = payment.TransactionRef,
                CounterpartName = b.ChefName,
                OccurredAt = at
            });
            Say(b, BookingParties.System, "Khoản thanh toán đến sau khi yêu cầu đã đóng nên được hoàn vào ví của thành viên.", at);
        }

        /* ------------------------------------------------------------ hoàn thành, huỷ */

        public static void ConfirmCompletion(ChefBooking b, DateTime now)
        {
            if (HasOpenComplaint(b)) throw new ConflictException("Đang có khiếu nại chờ Ban quản trị xử lý.", "has_open_complaint");
            if (b.Status != BookingStatuses.Active)
                throw new ConflictException(b.CompletedAt == null ? "Chỉ xác nhận được khi kế hoạch đang thực hiện." : "Hợp đồng đã hoàn thành.", "not_active");
            var contract = b.Contract!;
            var escrow = b.Escrow!;
            var missing = b.PlanDays - DeliveredDays(b);
            if (missing > 0)
                throw new ConflictException($"Còn {missing} ngày chưa gửi cho thành viên. Gửi đủ rồi xác nhận nhé.", "plan_not_delivered");
            if (string.CompareOrdinal(VnTime.DateOf(now), contract.EndDate) < 0)
                throw new ConflictException($"Bạn xác nhận hoàn thành được từ ngày kết thúc kế hoạch ({VnTime.DayMonth(contract.EndDate)}).", "plan_not_delivered");

            var releaseAt = VnTime.ReleaseAt(now);
            b.CompletedAt = now;
            b.Status = BookingStatuses.Ended;
            b.UpdatedAt = now;
            escrow.CompletedAt = now;
            escrow.ReleaseAt = releaseAt;
            Say(b, BookingParties.System,
                $"{b.ChefName} đã xác nhận hoàn thành hợp đồng. VeganLife giữ {MoneyMath.Vnd(escrow.Amount)} đến {VnTime.Stamp(releaseAt)} ({CommerceRules.HoldDays} ngày); không có khiếu nại thì tiền vào ví chuyên gia.",
                now);
        }

        /// <summary>Đã trả, chưa giao ngày nào: hoàn toàn bộ vào ví. resolvedBy phải null để app biết thành viên tự huỷ.</summary>
        public static void CancelPaid(ChefBooking b, string reason, DateTime now)
        {
            var escrow = b.Escrow!;
            if (DeliveredDays(b) > 0 || escrow.Status != EscrowStatuses.Held)
                throw new ConflictException("Chuyên gia đã giao kế hoạch nên không huỷ được nữa. Có vấn đề thì bạn gửi khiếu nại nhé.", "plan_started");
            escrow.Status = EscrowStatuses.Refunded;
            escrow.RefundedAmount = escrow.Amount;
            escrow.RefundedAt = now;
            escrow.ResolutionNote = reason;
            escrow.ResolvedBy = null;
            b.Status = BookingStatuses.Cancelled;
            b.CancelReason = reason;
            b.UpdatedAt = now;
            var order = b.Order!;
            order.Status = OrderStatuses.Refunded;
            order.RefundedAmount = escrow.Amount;
            order.Resolution = new OrderResolution { Action = "member_cancel", Note = reason, By = b.MemberName, At = now };
            AddRefund(b, escrow, escrow.Amount, now, "Hoàn do thành viên huỷ sau khi thanh toán", null);
            Say(b, BookingParties.System, $"{b.MemberName} đã huỷ yêu cầu: \"{reason}\". {MoneyMath.Vnd(escrow.Amount)} đã hoàn vào ví của thành viên.", now);
        }

        /* ------------------------------------------------------------ quyết định của admin */

        /// <summary>Tiền đi đâu: giống nhau giữa quyết định khiếu nại và xử lý khoản kẹt.</summary>
        private static DecisionOutcome SettleEscrow(ChefBooking b, string decision, long? refundAmount, string note, string actor, DateTime at, string? complaintId, string refundNote, string incomeNote)
        {
            var escrow = b.Escrow!;
            var outcome = MoneyMath.Decide(escrow.Amount, decision, refundAmount);
            escrow.Status = decision switch
            {
                ComplaintDecisions.ReleaseToChef => EscrowStatuses.Released,
                ComplaintDecisions.RefundMember => EscrowStatuses.Refunded,
                _ => EscrowStatuses.PartiallyRefunded
            };
            escrow.ReleasedAt = outcome.ChefGross > 0 ? at : null;
            escrow.ReleasedAmount = outcome.ChefGross;
            escrow.FeeAmount = outcome.Fee;
            escrow.RefundedAmount = outcome.Refund;
            escrow.RefundedAt = outcome.Refund > 0 ? at : null;
            escrow.ResolvedBy = actor;
            escrow.ResolutionNote = note;
            var order = b.Order!;
            order.RefundedAmount = outcome.Refund;
            order.Status = decision switch
            {
                ComplaintDecisions.RefundMember => OrderStatuses.Refunded,
                ComplaintDecisions.Split => OrderStatuses.PartiallyRefunded,
                _ => order.Status
            };
            if (outcome.ChefGross > 0) AddIncome(b, escrow, outcome.ChefGross, outcome.Fee, at, incomeNote, complaintId);
            if (outcome.Refund > 0) AddRefund(b, escrow, outcome.Refund, at, refundNote, complaintId);
            return outcome;
        }

        private static string DecisionDetail(string decision, DecisionOutcome o) => decision switch
        {
            ComplaintDecisions.ReleaseToChef => $"{MoneyMath.Vnd(o.ChefNet)} vào ví chuyên gia sau phí",
            ComplaintDecisions.RefundMember => $"hoàn {MoneyMath.Vnd(o.Refund)} vào ví thành viên",
            _ => $"hoàn {MoneyMath.Vnd(o.Refund)} vào ví thành viên, {MoneyMath.Vnd(o.ChefNet)} vào ví chuyên gia sau phí"
        };

        public static void ApplyComplaintDecision(ChefBooking b, string decision, long? refundAmount, string note, string actor, DateTime at)
        {
            var complaint = b.Complaint!;
            var outcome = SettleEscrow(b, decision, refundAmount, note, actor, at, complaint.Id,
                "Hoàn theo quyết định khiếu nại", "Giải ngân theo quyết định khiếu nại");
            complaint.Status = ComplaintStatuses.Resolved;
            complaint.Decision = decision;
            complaint.RefundAmount = outcome.Refund;
            complaint.AdminNote = note;
            complaint.DecidedBy = actor;
            complaint.DecidedAt = at;
            b.Status = BookingStatuses.Resolved;
            b.UpdatedAt = at;
            b.Order!.Resolution = new OrderResolution
            {
                Action = decision == ComplaintDecisions.ReleaseToChef ? "release" : decision == ComplaintDecisions.RefundMember ? "refund" : "partial_refund",
                Note = note,
                By = actor,
                At = at,
                ComplaintId = complaint.Id
            };
            Say(b, BookingParties.System, $"Ban quản trị đã quyết định: {ComplaintDecisions.Label(decision)}, {DecisionDetail(decision, outcome)}. Ghi chú: \"{note}\"", at);
        }

        /// <summary>
        /// Xử lý khoản kẹt, không có khiếu nại. ReleaseToChef và Split kết thúc booking Completed, completedAt = now;
        /// RefundMember kết thúc Cancelled. releaseAt vẫn null, autoCompleted vẫn false.
        /// </summary>
        public static void ResolveHold(ChefBooking b, string decision, long? refundAmount, string note, string actor, DateTime at)
        {
            var escrow = b.Escrow!;
            var outcome = SettleEscrow(b, decision, refundAmount, note, actor, at, null,
                "Hoàn theo quyết định của Ban quản trị", "Giải ngân theo quyết định của Ban quản trị");
            if (decision == ComplaintDecisions.RefundMember)
            {
                b.Status = BookingStatuses.Cancelled;
                b.CancelReason = note;
            }
            else
            {
                b.Status = BookingStatuses.Completed;
                b.CompletedAt ??= at;
                escrow.CompletedAt ??= at;
            }
            b.UpdatedAt = at;
            b.Order!.Resolution = new OrderResolution { Action = "admin_resolve", Note = note, By = actor, At = at };
            Say(b, BookingParties.System, $"Ban quản trị đã xử lý khoản giữ tiền: {ComplaintDecisions.Label(decision)}, {DecisionDetail(decision, outcome)}. Ghi chú: \"{note}\"", at);
        }

        /* ------------------------------------------------------------ sổ ví */

        private static string? PaidRef(ChefBooking b, EscrowHold escrow) =>
            b.Order?.Payments.FirstOrDefault(p => p.Id == escrow.PaymentId)?.TransactionRef;

        private static void AddIncome(ChefBooking b, EscrowHold escrow, long gross, long fee, DateTime at, string? note, string? complaintId) =>
            AddIntent(b, new LedgerIntent
            {
                Key = LedgerKinds.BookingKey(b.Id, LedgerKinds.Income),
                Kind = LedgerKinds.Income,
                Type = LedgerTypes.Income,
                UserId = b.ChefId,
                Gross = gross,
                Fee = fee,
                Net = gross - fee,
                Note = note,
                ComplaintId = complaintId,
                PaymentId = escrow.PaymentId,
                TransactionRef = PaidRef(b, escrow),
                CounterpartName = b.MemberName,
                OccurredAt = at
            });

        private static void AddRefund(ChefBooking b, EscrowHold escrow, long amount, DateTime at, string note, string? complaintId) =>
            AddIntent(b, new LedgerIntent
            {
                Key = LedgerKinds.BookingKey(b.Id, LedgerKinds.Refund),
                Kind = LedgerKinds.Refund,
                Type = LedgerTypes.Refund,
                UserId = b.MemberId,
                Net = amount,
                Note = note,
                ComplaintId = complaintId,
                PaymentId = escrow.PaymentId,
                TransactionRef = PaidRef(b, escrow),
                CounterpartName = b.ChefName,
                OccurredAt = at
            });

        private static void AddIntent(ChefBooking b, LedgerIntent intent)
        {
            if (b.Outbox.All(i => i.Key != intent.Key)) b.Outbox.Add(intent);
        }
    }
}
