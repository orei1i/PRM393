// lib/features/chef_studio/data/mock_chef_wallet_repository.dart
import '../../../core/session/user_role.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/mock_delay.dart';
import '../../booking/data/mock/mock_booking_db.dart';
import '../../booking/domain/booking_enums.dart';
import '../../commerce/data/mock/mock_commerce_db.dart';
import '../domain/wallet_rules.dart';
import 'chef_wallet_api_service.dart';
import 'models/wallet_models.dart';

/// One paid booking as the wallet sees it (same derivation as the web
/// `earningOf`): what the chef earns on and where that money is.
class _Earning {
  const _Earning({
    required this.entry,
    required this.gross,
    required this.fee,
    required this.status,
    required this.at,
    this.note,
  });

  final EscrowLedgerEntry entry;

  /// Contract price, or price − refund after a Split decision.
  final int gross;
  final int fee;
  final LedgerStatus status;

  /// When the money was held (payment) or became available (release).
  final DateTime at;
  final String? note;

  int get net => gross - fee;
}

/// Checks of "Tài khoản nhận tiền", for every wallet. `#fail` in the account
/// holder name → 503. Returns the row to store.
MockBankAccountRow validatedBankAccount(BankAccountDto account, DateTime at) {
  if (account.accountHolder.toLowerCase().contains('#fail')) {
    throw mockError(
        503, 'Ngân hàng chưa xác minh được tài khoản. Thử lại sau.');
  }
  final number = account.accountNumber.replaceAll(' ', '');
  if (account.bankName.trim().isEmpty) {
    throw mockError(400, 'Chọn ngân hàng.', 'validation');
  }
  if (!RegExp(r'^\d{6,19}$').hasMatch(number)) {
    throw mockError(400, 'Số tài khoản gồm 6–19 chữ số.', 'validation');
  }
  if (account.accountHolder.trim().length < 3) {
    throw mockError(400, 'Nhập tên chủ tài khoản.', 'validation');
  }
  return MockBankAccountRow(
    bankName: account.bankName.trim(),
    accountNumber: number,
    accountHolder: account.accountHolder.trim().toUpperCase(),
    updatedAt: at,
  );
}

/// Checks of a withdrawal against the bank account and the balance.
void checkWithdrawal(
    {required int amount,
    required int available,
    required MockBankAccountRow? account}) {
  if (account == null) {
    throw mockError(
        409, 'Thêm tài khoản ngân hàng trước khi rút tiền.', 'no_bank_account');
  }
  if (amount < kMinWithdrawal) {
    throw mockError(400, 'Số tiền rút tối thiểu ${formatVnd(kMinWithdrawal)}.',
        'amount_too_small');
  }
  if (amount > available) {
    throw mockError(
        409, 'Số tiền vượt quá số dư có thể rút.', 'insufficient_balance');
  }
}

/// What the wire shows of a withdrawal (the number is masked by the server).
Map<String, dynamic> withdrawalJson(MockWithdrawalRow w) => {
      'id': w.id,
      'amount': w.amount,
      'status': w.status,
      'bankName': w.bankName,
      'accountNumber': maskAccount(w.accountNumber),
      'createdAt': w.createdAt.toUtc().toIso8601String(),
      'processedAt': w.processedAt?.toUtc().toIso8601String(),
      'reason': w.reason,
    };

String maskAccount(String number) =>
    number.length <= 4 ? number : '•••• ${number.substring(number.length - 4)}';

/// Wallet on top of the booking escrow holds ([MockBookingDb]): a paid
/// booking is "Đang giữ" until [kEscrowHoldDays] days after the contract is
/// completed, "Tạm giữ do khiếu nại" while a complaint is open, then "Có thể
/// rút" at net 90 % — or "Đã hoàn" when an admin refunds it in full. Every
/// withdrawal waits for an admin; "Mô phỏng duyệt" stands in for one.
/// `#fail` in the account holder name → 503.
class MockChefWalletRepository implements ChefWalletApiService {
  MockChefWalletRepository(
      {required this.currentUserId, required this.currentRole});

  final String? Function() currentUserId;
  final UserRole Function() currentRole;

  MockCommerceDb get _db => MockCommerceDb.instance;

  MockChefRow _chef() {
    final id = currentUserId();
    if (id == null) throw mockError(401, 'Vui lòng đăng nhập để tiếp tục.');
    if (currentRole() != UserRole.chef) {
      throw mockError(403, 'Chỉ dành cho chuyên gia.', 'not_chef');
    }
    return _db.chefOfUser(id) ??
        (throw mockError(
            404, 'Bạn chưa có hồ sơ chuyên gia.', 'chef_profile_missing'));
  }

  static _Earning _earningOf(EscrowLedgerEntry e) => switch (e.status) {
        EscrowStatus.held || EscrowStatus.frozen => _Earning(
            entry: e,
            gross: e.amount,
            fee: platformFee(e.amount),
            status: e.status == EscrowStatus.held
                ? LedgerStatus.held
                : LedgerStatus.frozen,
            at: e.heldAt,
          ),
        EscrowStatus.released => _Earning(
            entry: e,
            gross: e.releasedAmount,
            fee: e.feeAmount,
            status: LedgerStatus.available,
            at: e.releasedAt ?? e.releaseAt ?? e.heldAt,
            note: e.complaintId != null
                ? 'Giải ngân theo quyết định khiếu nại'
                : e.adminResolved
                    ? 'Giải ngân theo quyết định của Ban quản trị'
                    : null,
          ),
        EscrowStatus.partiallyRefunded => _Earning(
            entry: e,
            gross: e.releasedAmount,
            fee: e.feeAmount,
            status: LedgerStatus.available,
            at: e.releasedAt ?? e.decidedAt ?? e.heldAt,
            note:
                'Hoàn ${formatVnd(e.refundedAmount)} cho thành viên theo quyết định ${e.adminResolved ? 'của Ban quản trị' : 'khiếu nại'}',
          ),
        EscrowStatus.refunded => _Earning(
            entry: e,
            gross: e.amount,
            fee: platformFee(e.amount),
            status: LedgerStatus.reversed,
            at: e.decidedAt ?? e.heldAt,
            note:
                'Đã hoàn toàn bộ ${formatVnd(e.refundedAmount)} cho thành viên',
          ),
      };

  List<_Earning> _earnings(String chefId) => [
        for (final e in _db.bookingDb.escrowLedger())
          if (e.chefId == chefId) _earningOf(e),
      ];

  List<MockWithdrawalRow> _withdrawals(String userId) =>
      _db.withdrawals.where((w) => w.userId == userId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  int _sum(Iterable<int> values) => values.fold(0, (a, b) => a + b);

  WalletDto _wallet(MockChefRow chef) {
    final earnings = _earnings(chef.id);
    final withdrawals = _withdrawals(chef.userId);
    int netOf(LedgerStatus status) =>
        _sum(earnings.where((e) => e.status == status).map((e) => e.net));
    final withdrawn = _sum(
        withdrawals.where((w) => w.status == 'Completed').map((w) => w.amount));
    final processing = _sum(withdrawals
        .where((w) => w.status == 'Processing')
        .map((w) => w.amount));
    final account = _db.bankAccounts[chef.userId];
    return WalletDto.fromJson({
      'available': _db.availableOf(chef.userId),
      'pending': netOf(LedgerStatus.held),
      'frozen': netOf(LedgerStatus.frozen),
      'withdrawn': withdrawn,
      'processing': processing,
      'feeRate': kPlatformFeeRate,
      'holdDays': kEscrowHoldDays,
      'bankAccount': account == null ? null : _accountJson(account),
    });
  }

  static Map<String, dynamic> _accountJson(MockBankAccountRow a) => {
        'bankName': a.bankName,
        'accountNumber': a.accountNumber,
        'accountHolder': a.accountHolder,
      };

  static String _iso(DateTime d) => d.toUtc().toIso8601String();

  @override
  Future<WalletDto> getWallet() async {
    await mockDelay(500);
    final chef = _chef();
    if (MockCommerceDb.emptyScenario()) {
      return const WalletDto(available: 0, pending: 0, withdrawn: 0);
    }
    return _wallet(chef);
  }

  @override
  Future<List<WalletTransactionDto>> transactions({String? month}) async {
    await mockDelay(500);
    final chef = _chef();
    if (MockCommerceDb.emptyScenario()) return const [];
    final rows = <Map<String, dynamic>>[
      for (final e in _earnings(chef.id))
        {
          'id': 'tx_in_${e.entry.bookingId}',
          'type': 'Income',
          'status': e.status.apiValue,
          'createdAt': _iso(e.at),
          'gross': e.gross,
          'fee': e.fee,
          'net': e.net,
          'bookingId': e.entry.bookingId,
          'orderId': e.entry.orderId,
          'transactionRef': e.entry.transactionRef,
          'planTitle': e.entry.planTitle,
          'memberName': e.entry.memberName,
          'releaseAt': e.status == LedgerStatus.held
              ? e.entry.releaseAt?.toUtc().toIso8601String()
              : null,
          'complaintId': e.entry.complaintId,
          'note': e.note,
        },
      // One wallet per user: what they booked themselves shows here too.
      for (final e in _db.walletEntries)
        if (e.userId == chef.userId)
          {
            'id': e.id,
            'type': e.type,
            'status': e.type == 'Refund' ? 'Available' : 'Completed',
            'createdAt': _iso(e.createdAt),
            'net': e.amount,
            'bookingId': e.bookingId,
            'orderId': e.orderId,
            'transactionRef': e.transactionRef,
            'planTitle': e.planTitle,
            'note': e.note,
          },
      for (final w in _withdrawals(chef.userId))
        {
          'id': 'tx_wd_${w.id}',
          'type': 'Withdrawal',
          'status': w.status,
          'createdAt': _iso(w.createdAt),
          'net': -w.amount,
          'bankName': '${w.bankName} ${maskAccount(w.accountNumber)}',
          'note': w.reason,
        },
    ];
    final list = rows.map(WalletTransactionDto.fromJson).where((t) {
      if (month == null) return true;
      final d = t.createdAt;
      return '${d.year}-${d.month.toString().padLeft(2, '0')}' == month;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Future<BankAccountDto> saveBankAccount(BankAccountDto account) async {
    await mockDelay(700);
    final chef = _chef();
    final row = validatedBankAccount(account, _db.now);
    _db.bankAccounts[chef.userId] = row;
    return BankAccountDto.fromJson(_accountJson(row));
  }

  @override
  Future<WithdrawalDto> requestWithdrawal(WithdrawalRequestDto request) async {
    await mockDelay(800);
    final chef = _chef();
    final account = _db.bankAccounts[chef.userId];
    checkWithdrawal(
        amount: request.amount,
        available: _wallet(chef).available,
        account: account);
    final row = MockWithdrawalRow(
      id: _db.newId('wd'),
      userId: chef.userId,
      amount: request.amount,
      bankName: account!.bankName,
      accountNumber: account.accountNumber,
      createdAt: _db.now,
      reason: 'Chờ Ban quản trị duyệt (1–2 ngày làm việc).',
    );
    _db.withdrawals.add(row);
    return WithdrawalDto.fromJson(withdrawalJson(row));
  }

  @override
  Future<WithdrawalDto> mockDecideWithdrawal(String id,
      {required bool approve}) async {
    await mockDelay(400);
    final chef = _chef();
    if (!_withdrawals(chef.userId).any((w) => w.id == id)) {
      throw mockError(404, 'Không tìm thấy yêu cầu rút tiền.');
    }
    final row = _db.decideWithdrawal(id,
        approve: approve,
        reason: approve ? null : 'Từ chối mô phỏng: thông tin chưa khớp.');
    return WithdrawalDto.fromJson(withdrawalJson(row));
  }

  @override
  Future<List<WithdrawalDto>> withdrawals() async {
    await mockDelay(400);
    final chef = _chef();
    if (MockCommerceDb.emptyScenario()) return const [];
    return _withdrawals(chef.userId)
        .map((w) => WithdrawalDto.fromJson(withdrawalJson(w)))
        .toList();
  }
}
