using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using MongoDB.Bson.Serialization.Attributes;

namespace DomainLayer.Entities
{
    /// <summary>
    /// Mỗi user một ví: _id chính là id user, nên không thể có hai ví.
    /// Số dư là kết quả cộng dồn các bút toán có id trong <see cref="AppliedEntryIds"/>; id và số dư đổi trong
    /// cùng một lần ghi nguyên tử, nên một bút toán không thể được cộng hai lần, dù áp dụng lại bao nhiêu lần.
    /// </summary>
    [BsonIgnoreExtraElements]
    public class Wallet : BaseEntity
    {
        public long Available { get; set; }
        public long Processing { get; set; }
        public long Withdrawn { get; set; }
        public WalletBankAccount? BankAccount { get; set; }
        public List<string> AppliedEntryIds { get; set; } = new();
    }

    public class WalletBankAccount
    {
        public string BankName { get; set; } = string.Empty;
        public string AccountNumber { get; set; } = string.Empty;
        public string AccountHolder { get; set; } = string.Empty;
    }

    /// <summary>
    /// Sổ cái. _id suy ra từ khoá chống trùng (booking, loại), nên bản ghi thứ hai cùng khoá luôn bị Mongo
    /// từ chối ngay cả khi chỉ mục phụ chưa kịp tạo.
    /// </summary>
    [BsonIgnoreExtraElements]
    public class WalletLedgerEntry : BaseEntity
    {
        public string UserId { get; set; } = string.Empty;
        public string IdempotencyKey { get; set; } = string.Empty;
        public string Kind { get; set; } = string.Empty;
        public string Type { get; set; } = string.Empty;
        public string? BookingId { get; set; }
        public string? OrderId { get; set; }
        public string? WithdrawalId { get; set; }
        public string? ComplaintId { get; set; }
        public string? PaymentId { get; set; }
        public string? TransactionRef { get; set; }
        public string? PlanTitle { get; set; }
        public string? CounterpartName { get; set; }
        public long? Gross { get; set; }
        public long? Fee { get; set; }
        public long DeltaAvailable { get; set; }
        public long DeltaProcessing { get; set; }
        public long DeltaWithdrawn { get; set; }
        public string? Note { get; set; }
        public DateTime OccurredAt { get; set; }

        /// <summary>Đã ghi vào số dư và đã được đánh dấu.</summary>
        public bool Applied { get; set; }
        /// <summary>Khoản trừ không thực hiện được (không đủ số dư): không tính vào đâu.</summary>
        public bool Voided { get; set; }
        /// <summary>Trả bằng ví: booking đã được nhận tiền hoặc tiền đã hoàn lại.</summary>
        public bool SagaDone { get; set; }

        [BsonIgnore]
        public bool IsDebit => DeltaAvailable < 0;

        public static string IdForKey(string key)
        {
            var hash = SHA256.HashData(Encoding.UTF8.GetBytes(key));
            return Convert.ToHexString(hash, 0, 12).ToLowerInvariant();
        }
    }

    [BsonIgnoreExtraElements]
    public class WithdrawalRequest : BaseEntity
    {
        public string UserId { get; set; } = string.Empty;
        public string UserName { get; set; } = string.Empty;
        public string UserEmail { get; set; } = string.Empty;
        /// <summary>"member" | "chef": chỉ là nhãn, vẫn là một ví.</summary>
        public string Role { get; set; } = string.Empty;
        public long Amount { get; set; }
        public string Status { get; set; } = string.Empty;
        public string BankName { get; set; } = string.Empty;
        public string AccountNumber { get; set; } = string.Empty;
        public string AccountHolder { get; set; } = string.Empty;
        public DateTime? ProcessedAt { get; set; }
        public string? ProcessedBy { get; set; }
        public string? TransactionRef { get; set; }
        public string? Reason { get; set; }

        /// <summary>Tiền đã chuyển từ available sang processing. Chưa thì chưa hiện ở đâu.</summary>
        public bool Funded { get; set; }
        /// <summary>Kết quả duyệt/từ chối đã ghi sổ.</summary>
        public bool Posted { get; set; }
        /// <summary>Chặn bấm đúp: cùng người, cùng số tiền trong một khoảng ngắn.</summary>
        [BsonIgnoreIfNull]
        public string? DedupeKey { get; set; }
    }
}
