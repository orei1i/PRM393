// lib/features/chef_studio/data/models/wallet_models.dart
//
// Wallets of chefs and members. Needs SQL tables the 26-table design doesn't
// have yet: `wallets`, `wallet_transactions`, `withdrawal_requests`,
// `bank_accounts`.
//
// Same shapes as the web console (FE/Web src/types/payouts.ts). A chef's
// earnings come from booking escrow holds: one Income row per paid booking
// whose status follows the hold — Held ("Đang giữ", until releaseAt = the
// contract's completion + 7 days, no date before that) → Frozen ("Tạm giữ do
// khiếu nại") → Available ("Có thể rút", net of the 10 % fee; a Split decision
// releases price − refund) or Reversed ("Đã hoàn", refunded to the member).
// A member's wallet holds refunds, minus bookings paid from it and withdrawals.
// A user has one wallet, whatever their role.
//
// GET /chefs/me/wallet, GET /users/me/wallet      WalletDto
// { "available": 110000, "pending": 2214000, "frozen": 945000, "withdrawn": 1000000,
//   "processing": 5100000, "feeRate": 0.1, "holdDays": 7, "bankAccount": BankAccountDto | null }
//   Member: pending and frozen are 0.
// GET /chefs/me/wallet/transactions?month=2026-10   [WalletTransactionDto]
// GET /users/me/wallet/transactions                [WalletTransactionDto]
// { "id": "tx_in_b_vy_tam_active", "type": "Income" | "Refund" | "Payment" | "Withdrawal", "createdAt": "…",
//   "status": "Held" | "Frozen" | "Available" | "Reversed" | "Processing" | "Completed" | "Rejected",
//   "bookingId": "b_vy_tam_active", "orderId": "ord_603", "transactionRef": "VL2610120001",
//   "planTitle": "Thực đơn 7 ngày · Có phản hồi mỗi ngày", "memberName": "Thảo Vy",
//   "gross": 1260000, "fee": 126000, "net": 1134000,   // net is signed: withdrawals < 0
//   "releaseAt": "…" | null,        // Held rows: when the escrow is released; null until completed
//   "complaintId": "cp_…" | null,   // Frozen rows: the complaint holding the money
//   "bankName": null, "note": null }
// Legacy: status "Pending" reads as Held; serviceTitle / buyerName as
// planTitle / memberName.
// PUT /chefs/me/bank-account, PUT /users/me/bank-account
//                                     { "bankName", "accountNumber", "accountHolder" } → BankAccountDto
// POST /chefs/me/withdrawals, POST /users/me/withdrawals
//                                     { "amount": 1500000 } → WithdrawalDto (Processing: waits for an admin)
// GET /chefs/me/withdrawals, GET /users/me/withdrawals   [WithdrawalDto]
// { "id": 1, "amount": 1500000, "status": "Processing", "bankName": "Vietcombank",
//   "accountNumber": "•••• 6789", "createdAt": "…", "processedAt": null, "reason": null }
import '../../../../core/utils/json_helpers.dart';

T _fromApi<T extends Enum>(
    List<T> values, String Function(T) wire, Object? value) {
  final raw = value?.toString().trim().toLowerCase();
  return values.firstWhere((e) => wire(e).toLowerCase() == raw,
      orElse: () => values.first);
}

/// Whose wallet a shared screen works on (bank account, withdrawal).
enum WalletOwner { chef, member }

enum WalletEntryType {
  income('Income', 'Thu nhập'),
  refund('Refund', 'Hoàn tiền'),
  payment('Payment', 'Thanh toán'),
  withdrawal('Withdrawal', 'Rút tiền');

  const WalletEntryType(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static WalletEntryType fromApi(Object? v) =>
      _fromApi(values, (e) => e.apiValue, v);
}

/// Earnings: Held → Available after the hold (Frozen while a complaint is
/// open; Reversed when fully refunded). Withdrawals: Processing → Completed /
/// Rejected.
enum LedgerStatus {
  held('Held', 'Đang giữ'),
  frozen('Frozen', 'Tạm giữ do khiếu nại'),
  available('Available', 'Có thể rút'),
  reversed('Reversed', 'Đã hoàn'),
  processing('Processing', 'Chờ duyệt'),
  completed('Completed', 'Đã chuyển'),
  rejected('Rejected', 'Bị từ chối');

  const LedgerStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;

  /// Legacy `Pending` reads as [held].
  static LedgerStatus fromApi(Object? v) =>
      v?.toString().trim().toLowerCase() == 'pending'
          ? held
          : _fromApi(values, (e) => e.apiValue, v);
}

class BankAccountDto {
  const BankAccountDto({
    required this.bankName,
    required this.accountNumber,
    required this.accountHolder,
  });

  factory BankAccountDto.fromJson(Map<String, dynamic> json) => BankAccountDto(
        bankName: json['bankName'] as String? ?? '',
        accountNumber: json['accountNumber']?.toString() ?? '',
        accountHolder: json['accountHolder'] as String? ?? '',
      );

  static BankAccountDto? fromJsonValue(Object? value) =>
      value is Map<String, dynamic> ? BankAccountDto.fromJson(value) : null;

  final String bankName;
  final String accountNumber;
  final String accountHolder;

  /// "•••• 6789"
  String get masked => accountNumber.length <= 4
      ? accountNumber
      : '•••• ${accountNumber.substring(accountNumber.length - 4)}';

  Map<String, dynamic> toJson() => {
        'bankName': bankName,
        'accountNumber': accountNumber,
        'accountHolder': accountHolder,
      };
}

class WalletDto {
  const WalletDto({
    required this.available,
    required this.pending,
    required this.withdrawn,
    this.frozen = 0,
    this.processing = 0,
    this.feeRate = 0.1,
    this.holdDays = 7,
    this.bankAccount,
  });

  factory WalletDto.fromJson(Map<String, dynamic> json) => WalletDto(
        available: readInt(json['available']),
        pending: readInt(json['pending']),
        frozen: readInt(json['frozen']),
        withdrawn: readInt(json['withdrawn']),
        processing: readInt(json['processing']),
        feeRate: json['feeRate'] == null ? 0.1 : readDouble(json['feeRate']),
        holdDays: json['holdDays'] == null ? 7 : readInt(json['holdDays']),
        bankAccount: BankAccountDto.fromJsonValue(json['bankAccount']),
      );

  /// "Có thể rút": released earnings minus fees, withdrawals and requests
  /// still being processed.
  final int available;

  /// "Đang giữ": net of bookings still in escrow (until [holdDays] days after
  /// the contract is completed).
  final int pending;

  /// "Tạm giữ do khiếu nại": net of holds frozen by an open complaint.
  final int frozen;

  /// "Đã rút": completed withdrawals.
  final int withdrawn;

  /// Withdrawals waiting for an admin (already out of [available]).
  final int processing;
  final double feeRate;
  final int holdDays;
  final BankAccountDto? bankAccount;
}

class WalletTransactionDto {
  const WalletTransactionDto({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.status,
    required this.net,
    this.bookingId,
    this.orderId,
    this.transactionRef,
    this.planTitle,
    this.memberName,
    this.gross,
    this.fee,
    this.releaseAt,
    this.complaintId,
    this.bankName,
    this.note,
  });

  factory WalletTransactionDto.fromJson(Map<String, dynamic> json) =>
      WalletTransactionDto(
        id: json['id']?.toString() ?? '',
        type: WalletEntryType.fromApi(json['type']),
        createdAt: readDateTime(json['createdAt']) ?? DateTime.now(),
        status: LedgerStatus.fromApi(json['status']),
        net: readInt(json['net']),
        bookingId: json['bookingId']?.toString(),
        orderId: json['orderId']?.toString(),
        transactionRef: json['transactionRef'] as String?,
        planTitle: (json['planTitle'] ?? json['serviceTitle']) as String?,
        memberName: (json['memberName'] ?? json['buyerName']) as String?,
        gross: json['gross'] == null ? null : readInt(json['gross']),
        fee: json['fee'] == null ? null : readInt(json['fee']),
        releaseAt: readDateTime(json['releaseAt']),
        complaintId: json['complaintId']?.toString(),
        bankName: json['bankName'] as String?,
        note: json['note'] as String?,
      );

  final String id;
  final WalletEntryType type;
  final DateTime createdAt;
  final LedgerStatus status;

  /// Signed: refunds and withdrawals are negative.
  final int net;
  final String? bookingId;
  final String? orderId;
  final String? transactionRef;

  /// "Thực đơn 10 ngày · Có phản hồi mỗi ngày" (computed by BE).
  final String? planTitle;
  final String? memberName;
  final int? gross;
  final int? fee;

  /// Held rows: when the escrow is released if nobody complains.
  final DateTime? releaseAt;

  /// Frozen rows: the complaint holding the money.
  final String? complaintId;
  final String? bankName;

  /// Rejection reason / admin or refund note.
  final String? note;
}

class WithdrawalDto {
  const WithdrawalDto({
    required this.id,
    required this.amount,
    required this.status,
    required this.bankName,
    required this.accountNumber,
    required this.createdAt,
    this.processedAt,
    this.reason,
  });

  factory WithdrawalDto.fromJson(Map<String, dynamic> json) => WithdrawalDto(
        id: json['id']?.toString() ?? '',
        amount: readInt(json['amount']),
        status: LedgerStatus.fromApi(json['status']),
        bankName: json['bankName'] as String? ?? '',
        accountNumber: json['accountNumber']?.toString() ?? '',
        createdAt: readDateTime(json['createdAt']) ?? DateTime.now(),
        processedAt: readDateTime(json['processedAt']),
        reason: json['reason'] as String?,
      );

  final String id;
  final int amount;

  /// processing / completed / rejected.
  final LedgerStatus status;
  final String bankName;

  /// Masked by the server.
  final String accountNumber;
  final DateTime createdAt;
  final DateTime? processedAt;
  final String? reason;
}

class WithdrawalRequestDto {
  const WithdrawalRequestDto({required this.amount});

  final int amount;

  Map<String, dynamic> toJson() => {'amount': amount};
}
