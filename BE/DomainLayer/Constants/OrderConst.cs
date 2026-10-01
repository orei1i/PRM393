namespace DomainLayer.Constants
{
    public static class OrderStatus
    {
        public const string Ordered   = "Ordered";
        public const string Preparing = "Preparing";
        public const string Ready     = "Ready";
        public const string Completed = "Completed";
        public const string Cancelled = "Cancelled";

        public static readonly string[] ActiveStatuses = { Ordered, Preparing, Ready };
    }

    public static class OrderType
    {
        public const string Online = "Online";
        public const string POS    = "POS";
    }

    public static class PaymentStatus
    {
        public const string Pending   = "Pending";
        public const string Completed = "Completed";
        public const string Failed    = "Failed";
        public const string Refunded  = "Refunded";
    }

    public static class PaymentMethod
    {
        public const string Cash = "Cash";
        public const string MoMo = "MoMo";
        /// <summary>Đơn 0đ sau giảm giá/voucher — không qua cổng MoMo.</summary>
        public const string Free = "Free";
        public const string VNPay = "VNPay";
    }
}
