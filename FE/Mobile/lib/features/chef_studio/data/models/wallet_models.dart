// lib/features/chef_studio/data/models/wallet_models.dart
//
// Chef wallet. Needs SQL tables the 26-table design doesn't have yet:
// `wallets`, `wallet_transactions`, `withdrawal_requests`, `bank_accounts`.
//
// GET /chefs/me/wallet                WalletDto
// { "available": 5462000, "pending": 1521000, "withdrawn": 1000000, "processing": 0,
//   "feeRate": 0.1, "holdDays": 7, "bankAccount": BankAccountDto | null }
// GET /chefs/me/wallet/transactions?month=2026-10   [WalletTransactionDto]
// { "id": "tx_1", "type": "Income" | "Refund" | "Withdrawal", "createdAt": "…",
//   "status": "Pending" | "Available" | "Reversed" | "Processing" | "Completed" | "Rejected",
//   "orderId": 501, "transactionRef": "VL2610150001", "serviceTitle": "…", "buyerName": "…",
//   "gross": 350000, "fee": 35000, "net": 315000,      // net is signed: refunds/withdrawals < 0
//   "bankName": null, "note": null }
// PUT /chefs/me/bank-account          { "bankName", "accountNumber", "accountHolder" } → BankAccountDto
// POST /chefs/me/withdrawals          { "amount": 1500000 } → WithdrawalDto
// GET /chefs/me/withdrawals           [WithdrawalDto]
// { "id": 1, "amount": 1500000, "status": "Processing", "bankName": "Vietcombank",
//   "accountNumber": "•••• 6789", "createdAt": "…", "processedAt": null, "reason": null }
import '../../../../core/utils/json_helpers.dart';

T _fromApi<T extends Enum>(
    List<T> values, String Function(T) wire, Object? value) {
  final raw = value?.toString().trim().toLowerCase();
  return values.firstWhere((e) => wire(e).toLowerCase() == raw,
      orElse: () => values.first);
}

enum WalletEntryType {
  income('Income', 'Thu nhập'),
  refund('Refund', 'Hoàn tiền'),
  withdrawal('Withdrawal', 'Rút tiền');

  const WalletEntryType(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static WalletEntryType fromApi(Object? v) =>
      _fromApi(values, (e) => e.apiValue, v);
}

/// Earnings: Pending → Available (or Reversed by a refund).
/// Withdrawals: Processing → Completed / Rejected.
enum LedgerStatus {
  pending('Pending', 'Đang chờ'),
  available('Available', 'Có thể rút'),
  reversed('Reversed', 'Đã hoàn'),
  processing('Processing', 'Đang xử lý'),
  completed('Completed', 'Đã chuyển'),
  rejected('Rejected', 'Bị từ chối');

  const LedgerStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static LedgerStatus fromApi(Object? v) =>
      _fromApi(values, (e) => e.apiValue, v);
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
    this.processing = 0,
    this.feeRate = 0.1,
    this.holdDays = 7,
    this.bankAccount,
  });

  factory WalletDto.fromJson(Map<String, dynamic> json) => WalletDto(
        available: readInt(json['available']),
        pending: readInt(json['pending']),
        withdrawn: readInt(json['withdrawn']),
        processing: readInt(json['processing']),
        feeRate: json['feeRate'] == null ? 0.1 : readDouble(json['feeRate']),
        holdDays: json['holdDays'] == null ? 7 : readInt(json['holdDays']),
        bankAccount: BankAccountDto.fromJsonValue(json['bankAccount']),
      );

  /// "Có thể rút": released earnings minus fees, withdrawals and requests
  /// still being processed.
  final int available;

  /// "Đang chờ": paid but not released yet.
  final int pending;

  /// "Đã rút": completed withdrawals.
  final int withdrawn;

  /// Withdrawals in "Đang xử lý" (already out of [available]).
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
    this.orderId,
    this.transactionRef,
    this.serviceTitle,
    this.buyerName,
    this.gross,
    this.fee,
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
        orderId: json['orderId']?.toString(),
        transactionRef: json['transactionRef'] as String?,
        serviceTitle: json['serviceTitle'] as String?,
        buyerName: json['buyerName'] as String?,
        gross: json['gross'] == null ? null : readInt(json['gross']),
        fee: json['fee'] == null ? null : readInt(json['fee']),
        bankName: json['bankName'] as String?,
        note: json['note'] as String?,
      );

  final String id;
  final WalletEntryType type;
  final DateTime createdAt;
  final LedgerStatus status;

  /// Signed: refunds and withdrawals are negative.
  final int net;
  final String? orderId;
  final String? transactionRef;
  final String? serviceTitle;
  final String? buyerName;
  final int? gross;
  final int? fee;
  final String? bankName;

  /// Rejection reason / admin note.
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
