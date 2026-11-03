using System;
using System.Collections.Generic;
using System.Linq;
using ApplicationLayer.DTOs.Commerce;
using DomainLayer.Constants;
using DomainLayer.Entities;
using DomainLayer.Helpers;

namespace ApplicationLayer.Services
{
    /// <summary>Đổi entity sang JSON đúng theo FE (types/bookings.ts, booking_models.dart).</summary>
    public static class BookingMapper
    {
        public static PersonResponse Member(ChefBooking b) => new() { Id = b.MemberId, FullName = b.MemberName, Email = b.MemberEmail };
        public static PersonResponse Chef(ChefBooking b) => new() { Id = b.ChefId, FullName = b.ChefName, Email = b.ChefEmail };

        public static OfferResponse Offer(BookingOffer o) => new()
        {
            Id = o.Id,
            ProposedBy = o.ProposedBy,
            Price = o.Price,
            PlanDays = o.PlanDays,
            BookingType = o.BookingType,
            StartDate = o.StartDate,
            Note = o.Note,
            Status = o.Status,
            CreatedAt = o.CreatedAt,
            RespondedAt = o.RespondedAt
        };

        public static ContractResponse Contract(ChefBooking b, BookingContract c) => new()
        {
            Id = c.Id,
            BookingId = b.Id,
            OfferId = c.OfferId,
            Price = c.Price,
            PlanDays = c.PlanDays,
            BookingType = c.BookingType,
            StartDate = c.StartDate,
            EndDate = c.EndDate,
            DeliveryDueAt = c.DeliveryDueAt,
            DailySendCutoff = CommerceRules.DailySendCutoff,
            FeedbackCutoff = CommerceRules.FeedbackCutoff,
            ScopeText = c.ScopeText,
            FeeRate = CommerceRules.FeeRate,
            HoldDays = CommerceRules.HoldDays,
            PaymentDueAt = c.PaymentDueAt,
            CreatedAt = c.CreatedAt
        };

        public static EscrowResponse Escrow(ChefBooking b, EscrowHold e) => Fill(new EscrowResponse(), b, e);

        private static T Fill<T>(T r, ChefBooking b, EscrowHold e) where T : EscrowResponse
        {
            r.Id = e.Id;
            r.BookingId = b.Id;
            r.PaymentId = e.PaymentId;
            r.Amount = e.Amount;
            r.Status = e.Status;
            r.HeldAt = e.HeldAt;
            r.CompletedAt = e.CompletedAt;
            r.ReleaseAt = e.ReleaseAt;
            r.ReleasedAt = e.ReleasedAt;
            r.ReleasedAmount = e.ReleasedAmount;
            r.FeeAmount = e.FeeAmount;
            r.RefundedAmount = e.RefundedAmount;
            r.RefundedAt = e.RefundedAt;
            r.ResolvedBy = e.ResolvedBy;
            r.ResolutionNote = e.ResolutionNote;
            return r;
        }

        public static ComplaintResponse Complaint(ChefBooking b, BookingComplaint c) => FillComplaint(new ComplaintResponse(), b, c);

        private static T FillComplaint<T>(T r, ChefBooking b, BookingComplaint c) where T : ComplaintResponse
        {
            r.Id = c.Id;
            r.BookingId = b.Id;
            r.Reason = c.Reason;
            r.Description = c.Description;
            r.RequestedOutcome = c.RequestedOutcome;
            r.RequestedAmount = c.RequestedAmount;
            r.Status = c.Status;
            r.Evidence = c.Evidence.Select(e => new EvidenceResponse
            {
                Id = e.Id,
                Kind = e.Kind,
                Url = e.Url,
                Caption = e.Caption,
                SubmittedBy = e.SubmittedBy,
                CreatedAt = e.CreatedAt
            }).ToList();
            r.ChefResponse = c.ChefResponse;
            r.ChefRespondedAt = c.ChefRespondedAt;
            r.Decision = c.Decision;
            r.RefundAmount = c.RefundAmount;
            r.AdminNote = c.AdminNote;
            r.DecidedBy = c.DecidedBy;
            r.DecidedAt = c.DecidedAt;
            r.CreatedAt = c.CreatedAt;
            return r;
        }

        public static BookingResponse Booking(ChefBooking b, MemberHealthResponse? health = null, bool includeComplaint = true) => new()
        {
            Id = b.Id,
            Member = Member(b),
            Chef = Chef(b),
            BookingType = b.BookingType,
            PlanDays = b.PlanDays,
            StartDate = b.StartDate,
            Audience = b.Audience,
            FamilySize = b.FamilySize,
            Goal = b.Goal,
            Allergies = b.Allergies,
            MealPattern = b.MealPattern,
            BudgetPerDay = b.BudgetPerDay,
            Needs = b.Needs,
            ShareHealthProfile = b.ShareHealthProfile,
            Status = b.Status,
            DeliveredDays = BookingLifecycle.DeliveredDays(b),
            CompletedAt = b.CompletedAt,
            AutoCompleted = b.AutoCompleted,
            CurrentOffer = b.Offers.Count > 0 ? Offer(b.Offers[^1]) : null,
            Contract = b.Contract != null ? Contract(b, b.Contract) : null,
            Escrow = b.Escrow != null ? Escrow(b, b.Escrow) : null,
            Complaint = includeComplaint && b.Complaint != null ? Complaint(b, b.Complaint) : null,
            PaymentOrderId = b.Order?.Id,
            DeclineReason = b.DeclineReason,
            CancelReason = b.CancelReason,
            MemberHealth = b.ShareHealthProfile && b.Audience == BookingAudiences.Self ? health : null,
            CreatedAt = b.CreatedAt,
            UpdatedAt = b.UpdatedAt ?? b.CreatedAt
        };

        public static BookingRefResponse Ref(ChefBooking b) => new()
        {
            Id = b.Id,
            Member = Member(b),
            Chef = Chef(b),
            BookingType = b.BookingType,
            PlanDays = b.PlanDays,
            StartDate = b.StartDate,
            EndDate = b.Contract?.EndDate,
            Audience = b.Audience,
            FamilySize = b.FamilySize,
            Allergies = b.Allergies,
            Status = b.Status,
            DeliveredDays = BookingLifecycle.DeliveredDays(b),
            CompletedAt = b.CompletedAt,
            AutoCompleted = b.AutoCompleted,
            ComplaintId = b.Complaint?.Id,
            PaymentOrderId = b.Order?.Id
        };

        public static PlanDayResponse PlanDay(BookingPlanDay d) => new()
        {
            DayIndex = d.DayIndex,
            Date = d.Date,
            Status = d.Status,
            ChefNote = d.ChefNote,
            SentAt = d.SentAt,
            Meals = d.Meals.Select(m => new PlanMealResponse
            {
                Slot = m.Slot,
                Note = m.Note,
                Recipe = new PlanRecipeResponse
                {
                    Id = m.Recipe.Id,
                    Name = m.Recipe.Name,
                    Calories = m.Recipe.Calories,
                    ProteinG = m.Recipe.ProteinG,
                    CarbsG = m.Recipe.CarbsG,
                    FatG = m.Recipe.FatG,
                    Ingredients = m.Recipe.Ingredients,
                    Instructions = m.Recipe.Instructions
                }
            }).ToList(),
            Feedback = d.Feedback == null ? null : new DayFeedbackResponse
            {
                Rating = d.Feedback.Rating,
                Adherence = d.Feedback.Adherence,
                Body = d.Feedback.Body,
                CreatedAt = d.Feedback.CreatedAt
            }
        };

        public static MessageResponse Message(ChefBooking b, BookingMessage m)
        {
            var offer = m.OfferId == null ? null : b.Offers.FirstOrDefault(o => o.Id == m.OfferId);
            return new MessageResponse
            {
                Id = m.Id,
                SenderId = m.SenderId,
                SenderRole = m.SenderRole,
                Kind = m.Kind,
                Body = m.Body,
                OfferId = m.OfferId,
                Offer = offer != null ? Offer(offer) : null,
                AttachmentUrl = m.AttachmentUrl,
                CreatedAt = m.CreatedAt
            };
        }

        /// <summary>QR quá hạn thì đọc là Expired, không cần job nào ghi lại.</summary>
        public static string EffectivePaymentStatus(BookingPayment p, DateTime now) =>
            p.Status == PaymentStatuses.Pending && p.ExpiresAt is { } expires && expires < now ? PaymentStatuses.Expired : p.Status;

        public static PaymentResponse Payment(BookingOrder o, BookingPayment p, DateTime now) => new()
        {
            Id = p.Id,
            OrderId = o.Id,
            Provider = p.Provider,
            TransactionRef = p.TransactionRef,
            QrCodeUrl = p.QrCodeUrl,
            Status = EffectivePaymentStatus(p, now),
            PaidAt = p.PaidAt,
            Amount = p.Amount,
            ExpiresAt = p.ExpiresAt,
            CreatedAt = p.CreatedAt
        };

        private static T FillOrderBooking<T>(T r, ChefBooking b) where T : OrderBookingResponse
        {
            r.Id = b.Id;
            r.ChefId = b.ChefId;
            r.ChefName = b.ChefName;
            r.BookingType = b.BookingType;
            r.PlanDays = b.PlanDays;
            r.StartDate = b.Contract?.StartDate ?? b.StartDate;
            r.EndDate = b.Contract?.EndDate;
            r.Status = b.Status;
            r.CompletedAt = b.CompletedAt;
            r.AutoCompleted = b.AutoCompleted;
            r.Audience = b.Audience;
            r.FamilySize = b.FamilySize;
            r.Allergies = b.Allergies;
            return r;
        }

        public static OrderResponse Order(ChefBooking b, DateTime now)
        {
            var o = b.Order!;
            var latest = o.Payments.Count > 0 ? o.Payments[^1] : null;
            return new OrderResponse
            {
                Id = o.Id,
                UserId = b.MemberId,
                BookingId = b.Id,
                Amount = o.Amount,
                Status = o.Status,
                CreatedAt = o.CreatedAt,
                Booking = FillOrderBooking(new OrderBookingResponse(), b),
                Payment = latest != null ? Payment(o, latest, now) : null,
                Escrow = b.Escrow != null ? Escrow(b, b.Escrow) : null
            };
        }

        public static AdminOrderResponse AdminOrder(ChefBooking b, DateTime now)
        {
            var o = b.Order!;
            var booking = FillOrderBooking(new AdminOrderBookingResponse(), b);
            booking.Chef = Chef(b);
            booking.DeliveredDays = BookingLifecycle.DeliveredDays(b);
            booking.ComplaintId = b.Complaint?.Id;
            return new AdminOrderResponse
            {
                Id = o.Id,
                UserId = b.MemberId,
                Buyer = Member(b),
                BookingId = b.Id,
                Booking = booking,
                Amount = o.Amount,
                Status = o.Status,
                CreatedAt = o.CreatedAt,
                Payments = o.Payments.OrderBy(p => p.CreatedAt).Select(p => Payment(o, p, now)).ToList(),
                Escrow = b.Escrow != null ? Escrow(b, b.Escrow) : null,
                RefundedAmount = o.RefundedAmount,
                Resolution = o.Resolution == null ? null : new OrderResolutionResponse
                {
                    Action = o.Resolution.Action,
                    Note = o.Resolution.Note,
                    By = o.Resolution.By,
                    At = o.Resolution.At,
                    ComplaintId = o.Resolution.ComplaintId
                }
            };
        }

        public static AdminComplaintResponse AdminComplaint(ChefBooking b, bool detail)
        {
            var r = FillComplaint(new AdminComplaintResponse(), b, b.Complaint!);
            r.Booking = Booking(b, null, includeComplaint: false);
            if (detail)
            {
                r.PlanDays = b.Days.OrderBy(d => d.DayIndex).Select(PlanDay).ToList();
                r.Messages = b.Messages.OrderBy(m => m.CreatedAt).Select(m => Message(b, m)).ToList();
            }
            return r;
        }

        public static AdminEscrowHoldResponse Hold(ChefBooking b, DateTime now)
        {
            var r = Fill(new AdminEscrowHoldResponse(), b, b.Escrow!);
            r.IsStuck = BookingLifecycle.IsStuck(b, now);
            r.Booking = Ref(b);
            return r;
        }

        public static BankAccountResponse? Bank(WalletBankAccount? a) => a == null ? null : new BankAccountResponse
        {
            BankName = a.BankName,
            AccountNumber = a.AccountNumber,
            AccountHolder = a.AccountHolder
        };

        public static WithdrawalResponse Withdrawal(WithdrawalRequest w) => new()
        {
            Id = w.Id,
            Amount = w.Amount,
            Status = w.Status,
            BankName = w.BankName,
            AccountNumber = CommerceText.MaskAccount(w.AccountNumber),
            CreatedAt = w.CreatedAt,
            ProcessedAt = w.ProcessedAt,
            Reason = w.Reason
        };

        public static AdminWithdrawalResponse AdminWithdrawal(WithdrawalRequest w) => new()
        {
            Id = w.Id,
            UserId = w.UserId,
            Role = w.Role,
            User = new PersonResponse { Id = w.UserId, FullName = w.UserName, Email = w.UserEmail },
            Amount = w.Amount,
            Status = w.Status,
            BankAccount = new BankAccountResponse { BankName = w.BankName, AccountNumber = w.AccountNumber, AccountHolder = w.AccountHolder },
            CreatedAt = w.CreatedAt,
            ProcessedAt = w.ProcessedAt,
            ProcessedBy = w.ProcessedBy,
            TransactionRef = w.TransactionRef,
            Reason = w.Reason
        };

        /// <summary>
        /// Lịch sử ví của một user, mới nhất trước. Dòng Income đi theo trạng thái giữ tiền của booking;
        /// Refund và Payment lấy từ sổ cái; Withdrawal lấy từ yêu cầu rút.
        /// </summary>
        public static List<WalletTransactionResponse> Transactions(
            IEnumerable<ChefBooking> chefBookings,
            IEnumerable<WalletLedgerEntry> ledger,
            IEnumerable<WithdrawalRequest> withdrawals)
        {
            var rows = new List<WalletTransactionResponse>();
            rows.AddRange(chefBookings.Where(b => b.Escrow != null).Select(IncomeRow));
            rows.AddRange(ledger
                .Where(e => e.Applied && e.Type is LedgerTypes.Refund or LedgerTypes.Payment)
                .Select(e => new WalletTransactionResponse
                {
                    Id = e.Id,
                    Type = e.Type,
                    Status = e.Type == LedgerTypes.Refund ? "Available" : "Completed",
                    CreatedAt = e.OccurredAt,
                    Net = e.DeltaAvailable,
                    BookingId = e.BookingId,
                    OrderId = e.OrderId,
                    TransactionRef = e.TransactionRef,
                    PlanTitle = e.PlanTitle,
                    CounterpartName = e.CounterpartName,
                    Note = e.Note,
                    ComplaintId = e.ComplaintId
                }));
            rows.AddRange(withdrawals.Select(w => new WalletTransactionResponse
            {
                Id = w.Id,
                Type = LedgerTypes.Withdrawal,
                Status = w.Status,
                CreatedAt = w.CreatedAt,
                Net = -w.Amount,
                TransactionRef = w.TransactionRef,
                BankName = $"{w.BankName} {CommerceText.MaskAccount(w.AccountNumber)}",
                Note = w.Reason
            }));
            return rows.OrderByDescending(r => r.CreatedAt).ToList();
        }

        private static WalletTransactionResponse IncomeRow(ChefBooking b)
        {
            var e = b.Escrow!;
            var complaintId = b.Complaint?.Id;
            var adminResolved = b.Complaint == null && !string.IsNullOrEmpty(e.ResolvedBy);
            var cancelled = b.Status == BookingStatuses.Cancelled && string.IsNullOrEmpty(e.ResolvedBy);

            var (status, gross, fee, at, note) = e.Status switch
            {
                EscrowStatuses.Held => ("Held", e.Amount, MoneyMath.Fee(e.Amount), e.HeldAt,
                    b.AutoCompleted ? "Hệ thống tự hoàn tất vì chuyên gia không xác nhận"
                    : e.ReleaseAt != null ? null : "VeganLife đang giữ, chờ chuyên gia xác nhận hoàn thành"),
                EscrowStatuses.Frozen => ("Frozen", e.Amount, MoneyMath.Fee(e.Amount), e.HeldAt, (string?)null),
                EscrowStatuses.Released => ("Available", e.ReleasedAmount, e.FeeAmount, e.ReleasedAt ?? e.HeldAt,
                    complaintId != null ? "Giải ngân theo quyết định khiếu nại"
                    : adminResolved ? "Giải ngân theo quyết định của Ban quản trị"
                    : b.AutoCompleted ? "Hệ thống tự hoàn tất vì chuyên gia không xác nhận" : null),
                EscrowStatuses.PartiallyRefunded => ("Available", e.ReleasedAmount, e.FeeAmount, e.ReleasedAt ?? e.HeldAt,
                    $"Hoàn {MoneyMath.Vnd(e.RefundedAmount)} vào ví thành viên theo quyết định {(adminResolved ? "của Ban quản trị" : "khiếu nại")}"),
                _ => ("Reversed", e.Amount, MoneyMath.Fee(e.Amount), e.RefundedAt ?? e.HeldAt,
                    cancelled ? $"Thành viên huỷ sau khi thanh toán, đã hoàn {MoneyMath.Vnd(e.RefundedAmount)} vào ví thành viên"
                    : $"Đã hoàn toàn bộ {MoneyMath.Vnd(e.RefundedAmount)} vào ví thành viên")
            };

            return new WalletTransactionResponse
            {
                Id = e.Id,
                Type = LedgerTypes.Income,
                Status = status,
                CreatedAt = at,
                Gross = gross,
                Fee = fee,
                Net = gross - fee,
                BookingId = b.Id,
                OrderId = b.Order?.Id,
                TransactionRef = b.Order?.Payments.FirstOrDefault(p => p.Id == e.PaymentId)?.TransactionRef,
                PlanTitle = BookingLifecycle.PlanTitle(b.PlanDays, b.BookingType),
                MemberName = b.MemberName,
                CounterpartName = b.MemberName,
                ReleaseAt = status == "Held" ? e.ReleaseAt : null,
                ComplaintId = complaintId,
                Note = note
            };
        }
    }
}
