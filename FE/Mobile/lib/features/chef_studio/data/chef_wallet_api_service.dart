// lib/features/chef_studio/data/chef_wallet_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/session/session_controller.dart';
import 'mock_chef_wallet_repository.dart';
import 'models/wallet_models.dart';

/// "Ví của tôi" (role Chef): booking escrow holds (Đang giữ / Tạm giữ do
/// khiếu nại / Có thể rút after the 10 % fee) and withdrawals to the chef's
/// bank account.
abstract interface class ChefWalletApiService {
  Future<WalletDto> getWallet();

  /// [month] is `yyyy-MM`; null = every month.
  Future<List<WalletTransactionDto>> transactions({String? month});

  Future<BankAccountDto> saveBankAccount(BankAccountDto account);

  /// Starts `Processing`. 400 below the minimum, 409 `insufficient_balance`
  /// above "Có thể rút", 409 `no_bank_account` without a bank account.
  Future<WithdrawalDto> requestWithdrawal(WithdrawalRequestDto request);

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
  if (Env.useMockData) {
    return MockChefWalletRepository(
      currentUserId: () => ref.read(sessionControllerProvider).userId,
      currentRole: () => ref.read(sessionControllerProvider).role,
    );
  }
  return RemoteChefWalletApiService(ref.watch(dioProvider));
});
