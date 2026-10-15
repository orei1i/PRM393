// lib/features/chef_studio/data/mock_chef_wallet_repository.dart
import '../../../core/session/user_role.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/mock_delay.dart';
import '../../chef/domain/entities/chef.dart';
import '../../commerce/data/mock/mock_commerce_db.dart';
import '../../commerce/domain/commerce_status.dart';
import '../domain/wallet_rules.dart';
import 'chef_wallet_api_service.dart';
import 'models/wallet_models.dart';

/// One sale as the wallet sees it, derived from the orders in
/// [MockCommerceDb] so the ledger always matches the chef's real orders.
class _Earning {
  _Earning(this.order, this.paidAt, this.ref, this.status, this.refundedAt);

  final MockOrderRow order;
  final DateTime paidAt;
  final String ref;
  final LedgerStatus status;
  final DateTime? refundedAt;

  int get gross => order.amount;
  int get fee => platformFee(gross);
  int get net => gross - fee;
}

/// Wallet on top of [MockCommerceDb]. Money becomes "Có thể rút" when a
/// consult is completed, or [kPackageHoldDays] after a package is paid;
/// refunds reverse it. Withdrawals up to [kAutoApproveLimit] are paid out
/// 10 s after the request; bigger ones wait for an admin. `#fail` in the
/// account holder name → 503.
class MockChefWalletRepository implements ChefWalletApiService {
  MockChefWalletRepository(
      {required this.currentUserId, required this.currentRole});

  final String? Function() currentUserId;
  final UserRole Function() currentRole;

  static const autoApproveAfter = Duration(seconds: 10);

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

  List<_Earning> _earnings(String chefId) {
    final now = _db.now;
    final list = <_Earning>[];
    for (final o in _db.orders.where((o) => o.chefId == chefId)) {
      if (o.status != OrderStatus.paid && o.status != OrderStatus.refunded) {
        continue;
      }
      final paid = _db.payments
          .where((p) => p.orderId == o.id && p.paidAt != null)
          .firstOrNull;
      if (paid == null) continue;
      final paidAt = paid.paidAt!;
      final DateTime? releasedAt = o.type == ServiceType.consult
          ? (_db.consultationOf(o.id)?.status == ConsultationStatus.completed
              ? _db.consultationOf(o.id)!.completedAt
              : null)
          : paidAt.add(const Duration(days: kPackageHoldDays));
      final status = o.status == OrderStatus.refunded
          ? LedgerStatus.reversed
          : releasedAt != null && !releasedAt.isAfter(now)
              ? LedgerStatus.available
              : LedgerStatus.pending;
      list.add(_Earning(o, paidAt, paid.transactionRef, status,
          o.status == OrderStatus.refunded ? (o.refundedAt ?? paidAt) : null));
    }
    return list;
  }

  List<MockWithdrawalRow> _withdrawals(String chefId) {
    final list = _db.withdrawals.where((w) => w.chefId == chefId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    list.forEach(_db.settleWithdrawal);
    return list;
  }

  int _sum(Iterable<int> values) => values.fold(0, (a, b) => a + b);

  WalletDto _wallet(MockChefRow chef) {
    final earnings = _earnings(chef.id);
    final withdrawals = _withdrawals(chef.id);
    final released = _sum(earnings
        .where((e) => e.status == LedgerStatus.available)
        .map((e) => e.net));
    final withdrawn = _sum(
        withdrawals.where((w) => w.status == 'Completed').map((w) => w.amount));
    final processing = _sum(withdrawals
        .where((w) => w.status == 'Processing')
        .map((w) => w.amount));
    final account = _db.bankAccounts[chef.id];
    return WalletDto.fromJson({
      'available': released - withdrawn - processing,
      'pending': _sum(earnings
          .where((e) => e.status == LedgerStatus.pending)
          .map((e) => e.net)),
      'withdrawn': withdrawn,
      'processing': processing,
      'feeRate': kPlatformFeeRate,
      'holdDays': kPackageHoldDays,
      'bankAccount': account == null ? null : _accountJson(account),
    });
  }

  static Map<String, dynamic> _accountJson(MockBankAccountRow a) => {
        'bankName': a.bankName,
        'accountNumber': a.accountNumber,
        'accountHolder': a.accountHolder,
      };

  static String _iso(DateTime d) => d.toUtc().toIso8601String();

  static String _mask(String number) => number.length <= 4
      ? number
      : '•••• ${number.substring(number.length - 4)}';

  Map<String, dynamic> _withdrawalJson(MockWithdrawalRow w) => {
        'id': w.id,
        'amount': w.amount,
        'status': w.status,
        'bankName': w.bankName,
        'accountNumber': _mask(w.accountNumber),
        'createdAt': _iso(w.createdAt),
        'processedAt': w.processedAt == null ? null : _iso(w.processedAt!),
        'reason': w.reason,
      };

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
    final rows = <Map<String, dynamic>>[];
    for (final e in _earnings(chef.id)) {
      final common = {
        'orderId': e.order.id,
        'transactionRef': e.ref,
        'serviceTitle': e.order.serviceTitle,
        'buyerName': e.order.buyerName,
      };
      rows.add({
        'id': 'tx_in_${e.order.id}',
        'type': 'Income',
        'createdAt': _iso(e.paidAt),
        'status': e.status.apiValue,
        'gross': e.gross,
        'fee': e.fee,
        'net': e.net,
        ...common,
      });
      if (e.refundedAt != null) {
        rows.add({
          'id': 'tx_rf_${e.order.id}',
          'type': 'Refund',
          'createdAt': _iso(e.refundedAt!),
          'status': LedgerStatus.reversed.apiValue,
          'gross': -e.gross,
          'fee': -e.fee,
          'net': -e.net,
          ...common,
        });
      }
    }
    for (final w in _withdrawals(chef.id)) {
      rows.add({
        'id': 'tx_wd_${w.id}',
        'type': 'Withdrawal',
        'createdAt': _iso(w.createdAt),
        'status': w.status,
        'net': -w.amount,
        'bankName': '${w.bankName} ${_mask(w.accountNumber)}',
        'note': w.reason,
      });
    }
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
    final row = MockBankAccountRow(
      bankName: account.bankName.trim(),
      accountNumber: number,
      accountHolder: account.accountHolder.trim().toUpperCase(),
      updatedAt: _db.now,
    );
    _db.bankAccounts[chef.id] = row;
    return BankAccountDto.fromJson(_accountJson(row));
  }

  @override
  Future<WithdrawalDto> requestWithdrawal(WithdrawalRequestDto request) async {
    await mockDelay(800);
    final chef = _chef();
    final account = _db.bankAccounts[chef.id];
    if (account == null) {
      throw mockError(409, 'Thêm tài khoản ngân hàng trước khi rút tiền.',
          'no_bank_account');
    }
    if (request.amount < kMinWithdrawal) {
      throw mockError(400,
          'Số tiền rút tối thiểu ${formatVnd(kMinWithdrawal)}.', 'validation');
    }
    if (request.amount > _wallet(chef).available) {
      throw mockError(
          409, 'Số tiền vượt quá số dư có thể rút.', 'insufficient_balance');
    }
    final now = _db.now;
    final auto = request.amount <= kAutoApproveLimit;
    final row = MockWithdrawalRow(
      id: _db.newId('wd'),
      chefId: chef.id,
      amount: request.amount,
      bankName: account.bankName,
      accountNumber: account.accountNumber,
      createdAt: now,
      autoApproveAt: auto ? now.add(autoApproveAfter) : null,
      reason: auto
          ? null
          : 'Trên ${formatVnd(kAutoApproveLimit)}: chờ Ban quản trị duyệt (1–2 ngày làm việc).',
    );
    _db.withdrawals.add(row);
    return WithdrawalDto.fromJson(_withdrawalJson(row));
  }

  @override
  Future<List<WithdrawalDto>> withdrawals() async {
    await mockDelay(400);
    final chef = _chef();
    if (MockCommerceDb.emptyScenario()) return const [];
    return _withdrawals(chef.id)
        .map((w) => WithdrawalDto.fromJson(_withdrawalJson(w)))
        .toList();
  }
}
