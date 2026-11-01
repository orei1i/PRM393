// lib/features/commerce/data/member_wallet_api_service.dart
//
// A member's wallet: refunds go in, bookings can be paid from it, and the
// balance can be withdrawn to a bank account once an admin approves. One wallet
// per user, in the same shapes as the chef's routes
// (chef_studio/data/models/wallet_models.dart); it switches with them
// (`BackendModule.chefWallet`).
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/backend_modules.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/session/mock_persona.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/utils/mock_delay.dart';
import '../../chef_studio/data/chef_wallet_api_service.dart';
import '../../chef_studio/data/mock_chef_wallet_repository.dart';
import '../../chef_studio/data/models/wallet_models.dart';
import '../../chef_studio/domain/wallet_rules.dart';
import 'mock/mock_commerce_db.dart';

/// "Ví của tôi" of a member.
abstract interface class MemberWalletApiService implements WalletWithdrawalApi {
  Future<WalletDto> getWallet();

  /// Refunds, payments and withdrawals, newest first.
  Future<List<WalletTransactionDto>> transactions();

  Future<List<WithdrawalDto>> withdrawals();
}

class RemoteMemberWalletApiService implements MemberWalletApiService {
  RemoteMemberWalletApiService(this._dio);

  final Dio _dio;

  @override
  Future<WalletDto> getWallet() => guardApi(() async {
        final res = await _dio.get<Map<String, dynamic>>(ApiEndpoints.myWallet);
        return WalletDto.fromJson(res.data!);
      });

  @override
  Future<List<WalletTransactionDto>> transactions() => guardApi(() async {
        final res =
            await _dio.get<List<dynamic>>(ApiEndpoints.myWalletTransactions);
        return (res.data ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(WalletTransactionDto.fromJson)
            .toList();
      });

  @override
  Future<BankAccountDto> saveBankAccount(BankAccountDto account) =>
      guardApi(() async {
        final res = await _dio.put<Map<String, dynamic>>(
            ApiEndpoints.myBankAccount,
            data: account.toJson());
        return BankAccountDto.fromJson(res.data!);
      });

  @override
  Future<WithdrawalDto> requestWithdrawal(WithdrawalRequestDto request) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
            ApiEndpoints.myWithdrawals,
            data: request.toJson());
        return WithdrawalDto.fromJson(res.data!);
      });

  @override
  Future<WithdrawalDto> mockDecideWithdrawal(String id,
      {required bool approve}) async {
    throw const ApiException(
      message: 'Chỉ dùng được ở chế độ mô phỏng.',
      code: 'not_supported',
    );
  }

  @override
  Future<List<WithdrawalDto>> withdrawals() => guardApi(() async {
        final res = await _dio.get<List<dynamic>>(ApiEndpoints.myWithdrawals);
        return (res.data ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(WithdrawalDto.fromJson)
            .toList();
      });
}

/// Member wallet on [MockCommerceDb]. Every withdrawal waits for an admin;
/// "Mô phỏng duyệt" stands in for one. `#fail` in the account holder name →
/// 503; `MOCK_COMMERCE_SCENARIO` empties or fails the lists.
class MockMemberWalletRepository implements MemberWalletApiService {
  MockMemberWalletRepository({required this.currentUserId});

  final String? Function() currentUserId;

  MockCommerceDb get _db => MockCommerceDb.instance;

  String _me() =>
      currentUserId() ??
      (throw mockError(401, 'Vui lòng đăng nhập để tiếp tục.'));

  List<MockWithdrawalRow> _mine(String me) =>
      _db.withdrawals.where((w) => w.userId == me).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  int _sum(Iterable<int> values) => values.fold(0, (a, b) => a + b);

  @override
  Future<WalletDto> getWallet() async {
    await mockDelay(400);
    final me = _me();
    if (MockCommerceDb.emptyScenario()) {
      return const WalletDto(available: 0, pending: 0, withdrawn: 0);
    }
    _db.bookingDb.settle();
    final mine = _mine(me);
    final account = _db.bankAccounts[me];
    return WalletDto.fromJson({
      'available': _db.availableOf(me),
      'pending': 0,
      'frozen': 0,
      'withdrawn':
          _sum(mine.where((w) => w.status == 'Completed').map((w) => w.amount)),
      'processing': _sum(
          mine.where((w) => w.status == 'Processing').map((w) => w.amount)),
      'feeRate': kPlatformFeeRate,
      'holdDays': kEscrowHoldDays,
      'bankAccount': account == null
          ? null
          : {
              'bankName': account.bankName,
              'accountNumber': account.accountNumber,
              'accountHolder': account.accountHolder,
            },
    });
  }

  @override
  Future<List<WalletTransactionDto>> transactions() async {
    await mockDelay(400);
    final me = _me();
    if (MockCommerceDb.emptyScenario()) return const [];
    _db.bookingDb.settle();
    final rows = <Map<String, dynamic>>[
      for (final e in _db.walletEntries)
        if (e.userId == me)
          {
            'id': e.id,
            'type': e.type,
            'status': e.type == 'Refund' ? 'Available' : 'Completed',
            'createdAt': e.createdAt.toUtc().toIso8601String(),
            'net': e.amount,
            'bookingId': e.bookingId,
            'orderId': e.orderId,
            'transactionRef': e.transactionRef,
            'planTitle': e.planTitle,
            'note': e.note,
          },
      for (final w in _mine(me))
        {
          'id': 'tx_wd_${w.id}',
          'type': 'Withdrawal',
          'status': w.status,
          'createdAt': w.createdAt.toUtc().toIso8601String(),
          'net': -w.amount,
          'bankName': '${w.bankName} ${maskAccount(w.accountNumber)}',
          'note': w.reason,
        },
    ];
    return rows.map(WalletTransactionDto.fromJson).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<BankAccountDto> saveBankAccount(BankAccountDto account) async {
    await mockDelay(600);
    final me = _me();
    final row = validatedBankAccount(account, _db.now);
    _db.bankAccounts[me] = row;
    return BankAccountDto(
      bankName: row.bankName,
      accountNumber: row.accountNumber,
      accountHolder: row.accountHolder,
    );
  }

  @override
  Future<WithdrawalDto> requestWithdrawal(WithdrawalRequestDto request) async {
    await mockDelay(700);
    final me = _me();
    _db.bookingDb.settle();
    final account = _db.bankAccounts[me];
    checkWithdrawal(
        amount: request.amount,
        available: _db.availableOf(me),
        account: account);
    final row = MockWithdrawalRow(
      id: _db.newId('wd'),
      userId: me,
      role: MockWithdrawalRow.kMemberRole,
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
    final me = _me();
    if (!_mine(me).any((w) => w.id == id)) {
      throw mockError(404, 'Không tìm thấy yêu cầu rút tiền.');
    }
    final row = _db.decideWithdrawal(id,
        approve: approve,
        reason: approve ? null : 'Từ chối mô phỏng: thông tin chưa khớp.');
    return WithdrawalDto.fromJson(withdrawalJson(row));
  }

  @override
  Future<List<WithdrawalDto>> withdrawals() async {
    await mockDelay(350);
    final me = _me();
    if (MockCommerceDb.emptyScenario()) return const [];
    return _mine(me)
        .map((w) => WithdrawalDto.fromJson(withdrawalJson(w)))
        .toList();
  }
}

final memberWalletApiProvider = Provider<MemberWalletApiService>((ref) {
  if (BackendModules.isMock(BackendModule.chefWallet)) {
    return MockMemberWalletRepository(
      currentUserId: () => mockPersonaId(ref.read(sessionControllerProvider)),
    );
  }
  return RemoteMemberWalletApiService(ref.watch(dioProvider));
});
