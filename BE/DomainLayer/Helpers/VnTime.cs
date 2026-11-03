using System;
using System.Globalization;
using DomainLayer.Constants;

namespace DomainLayer.Helpers
{
    /// <summary>
    /// Lịch Việt Nam. Asia/Ho_Chi_Minh là UTC+7 quanh năm, không có giờ mùa hè, nên cộng thẳng
    /// mà không phụ thuộc múi giờ của máy chủ. Ngày thuần là chuỗi yyyy-MM-dd.
    /// </summary>
    public static class VnTime
    {
        private static readonly TimeSpan Offset = TimeSpan.FromHours(7);
        private const string DateFormat = "yyyy-MM-dd";

        public static string DateOf(DateTime utc) => (Utc(utc) + Offset).ToString(DateFormat, CultureInfo.InvariantCulture);

        public static string MonthOf(DateTime utc) => (Utc(utc) + Offset).ToString("yyyy-MM", CultureInfo.InvariantCulture);

        public static string AddDays(string date, int days) =>
            DateTime.ParseExact(date, DateFormat, CultureInfo.InvariantCulture).AddDays(days).ToString(DateFormat, CultureInfo.InvariantCulture);

        /// <summary>Thời điểm (UTC) của giờ Việt Nam: At("2026-10-20", 6, 0) là 2026-10-19T23:00:00Z.</summary>
        public static DateTime At(string date, int hour, int minute)
        {
            var wall = DateTime.ParseExact(date, DateFormat, CultureInfo.InvariantCulture).AddHours(hour).AddMinutes(minute);
            return DateTime.SpecifyKind(wall - Offset, DateTimeKind.Utc);
        }

        public static bool TryParseDate(string? raw, out string normalized)
        {
            normalized = string.Empty;
            if (string.IsNullOrWhiteSpace(raw)) return false;
            if (!DateTime.TryParseExact(raw.Trim(), DateFormat, CultureInfo.InvariantCulture, DateTimeStyles.None, out var d)) return false;
            normalized = d.ToString(DateFormat, CultureInfo.InvariantCulture);
            return true;
        }

        public static string PlanEndDate(string startDate, int planDays) => AddDays(startDate, planDays - 1);

        /// <summary>23:59 giờ VN của ngày kết thúc + 3 ngày.</summary>
        public static DateTime AutoCompleteAt(string endDate) => At(AddDays(endDate, CommerceRules.AutoCompleteDays), 23, 59);

        /// <summary>Đúng 7 ngày kể từ lúc hoàn thành, không làm tròn theo ngày.</summary>
        public static DateTime ReleaseAt(DateTime completedAt) => Utc(completedAt).AddDays(CommerceRules.HoldDays);

        /// <summary>min(lúc đồng ý + 48 giờ, 00:00 giờ VN của ngày bắt đầu).</summary>
        public static DateTime PaymentDueAt(DateTime acceptedAt, string startDate)
        {
            var afterWindow = Utc(acceptedAt).AddHours(CommerceRules.PaymentWindowHours);
            var start = At(startDate, 0, 0);
            return afterWindow > start ? start : afterWindow;
        }

        /// <summary>OneShot: max(00:00 ngày bắt đầu, lúc trả + 24 giờ). DailyFeedback: 06:00 ngày bắt đầu.</summary>
        public static DateTime DeliveryDueAt(string bookingType, string startDate, DateTime paidAt)
        {
            if (bookingType == BookingTypes.DailyFeedback) return At(startDate, CommerceRules.SendCutoffHour, 0);
            var start = At(startDate, 0, 0);
            var afterPayment = Utc(paidAt).AddHours(24);
            return afterPayment > start ? afterPayment : start;
        }

        /// <summary>"23:59, 02/11/2026".</summary>
        public static string Stamp(DateTime utc) => (Utc(utc) + Offset).ToString("HH:mm, dd/MM/yyyy", CultureInfo.InvariantCulture);

        /// <summary>"02/11".</summary>
        public static string DayMonth(string date) => $"{date.Substring(8, 2)}/{date.Substring(5, 2)}";

        /// <summary>Đầu tháng hiện tại theo lịch VN, ở dạng UTC.</summary>
        public static DateTime MonthStart(DateTime utc) => At($"{MonthOf(utc)}-01", 0, 0);

        private static DateTime Utc(DateTime value) => value.Kind == DateTimeKind.Utc ? value : DateTime.SpecifyKind(value, DateTimeKind.Utc);
    }
}
