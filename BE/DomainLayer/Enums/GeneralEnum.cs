using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.ComponentModel;

namespace DomainLayer.Enums
{
    public class GeneralEnum
    {
        public enum UserStatusEnum
        {
            Active,
            Inactive,
            Locked,
            Banned
        }

        public enum AuthTypeEnum
        {
            System, // Đăng nhập thường (Email/Pass)
            Google,
        }

        // Order Status Enum
        public enum OrderStatusEnum
        {
            Ordered,    // Đơn hàng mới tạo
            Preparing,  // Đang chuẩn bị
            Ready,      // Sẵn sàng để lấy
            Completed,  // Đã hoàn thành
            Cancelled   // Đã hủy
        }

        // Order Type Enum
        public enum OrderTypeEnum
        {
            Online,     // Đơn hàng online
            POS         // Đơn hàng tại quầy
        }

        // Payment Method Enum
        public enum PaymentMethodEnum
        {
            Cash,       // Tiền mặt
            VNPay,      // VNPay Gateway
            CreditCard, // Thẻ tín dụng
            EWallet     // Ví điện tử
        }

        // Payment Status Enum
        public enum PaymentStatusEnum
        {
            Pending,    // Chờ thanh toán
            Completed,  // Đã thanh toán
            Failed,     // Thanh toán thất bại
            Refunded,   // Đã hoàn tiền
            Cancelled   // Đã hủy
        }

        // Discount type enum
        public enum DiscountType
        {
            FixedAmount,
            Percentage
        }


        public enum TransactionType
        {
            AddStock,           // Confirm Receipt / Inbound (nhập kho)
            ReturnStock,        // Approve Return Order
            DeductStock,        // Deduct từ Order (xuất kho)
            Adjustment,         // Waste, damage, manual outbound
            StockCount,         // Kiểm kê — đặt số lượng thực tế
            UpdateThreshold,
            EditIngredientDetail
        }
        // Promotion Campaign Type Enum
        public enum PromotionType
        {
            FixedAmount,    // Giảm tiền mặt cố định
            Percentage,     // Giảm theo %
            BuyOneGetOne,   // Mua 1 tặng 1
            FreeShip        // Miễn phí giao hàng
        }
    }
}
