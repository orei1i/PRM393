// lib/features/chef_studio/data/chef_wallet_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/backend_modules.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/session/mock_persona.dart';
import '../../../core/session/session_controller.dart';
import 'mock_chef_wallet_repository.dart';
import 'models/wallet_models.dart';

/// What every wallet (chef or member) can do with a bank account: the shared
/// "Tài khoản nhận tiền" and "Rút tiền" screens work on this.
abstract interface class WalletWithdrawalApi {
  Future<BankAccountDto> saveBankAccount(BankAccountDto account);

  /// Starts `Processing` and waits for an admin (web `/payouts`). 400 below
  /// the minimum, 409 `insufficient_balance` above the balance, 409
  /// `no_bank_account` without a bank account.
  Future<WithdrawalDto> requestWithdrawal(WithdrawalRequestDto request);

  /// Mock/dev only; the real approval is an admin on web `/payouts`.
  Future<WithdrawalDto> mockDecideWithdrawal(String id,
      {required bool approve});
}

/// "Ví của tôi" (role Chef): booking escrow holds (Đang giữ / Tạm giữ do
/// khiếu nại / Có thể rút after the 10 % fee) and withdrawals to the chef's
/// bank account.
abstract interface class ChefWalletApiService implements WalletWithdrawalApi {
  Future<WalletDto> getWallet();

  /// [month] is `yyyy-MM`; null = every month.
  Future<List<WalletTransactionDto>> transactions({String? month});

  Future<List<WithdrawalDto>> withdrawals();
}

class RemoteChefWalletApiService implements ChefWalletApiService {
  RemoteChefWalletApiService(this._dio);

  final Dio _dio;

  @override
  Future<WalletDto> getWallet() => guardApi(() async {
        final res =
            await _dio.get<Map<String, dynamic>>(ApiEndpoints.myChefWallet);
        return WalletDto.fromJson(res.data!);
      });

  @override
  Future<List<WalletTransactionDto>> transactions({String? month}) =>
      guardApi(() async {
        final res = await _dio.get<List<dynamic>>(
            ApiEndpoints.myChefWalletTransactions,
            queryParameters: {if (month != null) 'month': month});
        return (res.data ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(WalletTransactionDto.fromJson)
            .toList();
      });

  @override
  Future<BankAccountDto> saveBankAccount(BankAccountDto account) =>
      guardApi(() async {
        final res = await _dio.put<Map<String, dynamic>>(
            ApiEndpoints.myChefBankAccount,
            data: account.toJson());
        return BankAccountDto.fromJson(res.data!);
      });

  @override
  Future<WithdrawalDto> requestWithdrawal(WithdrawalRequestDto request) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
            ApiEndpoints.myChefWithdrawals,
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
        final res =
            await _dio.get<List<dynamic>>(ApiEndpoints.myChefWithdrawals);
        return (res.data ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(WithdrawalDto.fromJson)
            .toList();
      });
}

final chefWalletApiProvider = Provider<ChefWalletApiService>((ref) {
  if (BackendModules.isMock(BackendModule.chefWallet)) {
    return MockChefWalletRepository(
      currentUserId: () => mockPersonaId(ref.read(sessionControllerProvider)),
      currentRole: () => ref.read(sessionControllerProvider).role,
    );
  }
  return RemoteChefWalletApiService(ref.watch(dioProvider));
});
