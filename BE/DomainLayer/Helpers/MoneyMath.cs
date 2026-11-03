using System.Globalization;
using DomainLayer.Constants;

namespace DomainLayer.Helpers
{
    public readonly record struct DecisionOutcome(long Refund, long ChefGross, long Fee, long ChefNet);

    /// <summary>
    /// Tiền là số nguyên VND, không dùng số thực.
    /// Quy tắc làm tròn: phí = gross × 10 % làm tròn nửa lên đồng (giống Math.round ở FE);
    /// chuyên gia nhận phần còn lại (gross − phí). Nhờ vậy thành viên + chuyên gia + phí luôn đúng bằng giá.
    /// </summary>
    public static class MoneyMath
    {
        public static long Fee(long gross) => gross <= 0 ? 0 : (gross + 5) / 10;

        public static long Net(long gross) => gross - Fee(gross);

        public static DecisionOutcome Decide(long price, string decision, long? refundAmount)
        {
            var refund = decision switch
            {
                ComplaintDecisions.RefundMember => price,
                ComplaintDecisions.Split => refundAmount ?? 0,
                _ => 0
            };
            var gross = price - refund;
            var fee = Fee(gross);
            return new DecisionOutcome(refund, gross, fee, gross - fee);
        }

        /// <summary>Hợp lệ khi 1.000đ ≤ X &lt; giá.</summary>
        public static bool IsValidPartialRefund(long? amount, long price) =>
            amount is { } x && x >= CommerceRules.MinPartialRefund && x < price;

        /// <summary>"1.500.000đ".</summary>
        public static string Vnd(long amount) => amount.ToString("#,##0", CultureInfo.InvariantCulture).Replace(',', '.') + "đ";
    }
}
