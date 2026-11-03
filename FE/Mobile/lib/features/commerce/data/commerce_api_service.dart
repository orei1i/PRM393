// lib/features/commerce/data/commerce_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/backend_modules.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/session/mock_persona.dart';
import '../../../core/session/session_controller.dart';
import 'mock_commerce_repository.dart';
import 'models/order_model.dart';
import 'models/payment_model.dart';

/// Buyer side of a booking payment: the order (created when an offer is
/// accepted) → the gateway's QR (`POST /orders/{id}/payments`, 503
/// `payment_unavailable` without a gateway) or the wallet → status → escrow.
/// Course / VIP Menu purchases and consultations are gone;
/// an unpaid booking is cancelled from the booking itself ("Huỷ yêu cầu").
abstract interface class CommerceApiService {
  Future<OrderDto> getOrder(String id);

  /// The open QR, or a new one when there is none, or the last expired or failed.
  Future<PaymentDto> renewPayment(String orderId);

  /// Polled every 3 s by the payment screen.
  Future<PaymentDto> getPayment(String id);

  /// Pays the order from the member's wallet, in one go (no partial balance).
  /// 409 `insufficient_balance`, 409 `not_awaiting_payment`.
  Future<OrderDto> payWithWallet(String orderId);

  /// The demo's stand-in for the gateway: mock, or `POST
  /// /payments/{id}/sandbox-confirm` on the sandbox gateway (no real money).
  Future<PaymentDto> mockConfirmPayment(String paymentId,
      {required bool success});
}

class RemoteCommerceApiService implements CommerceApiService {
  RemoteCommerceApiService(this._dio);

  final Dio _dio;

  @override
  Future<OrderDto> getOrder(String id) => guardApi(() async {
        final res =
            await _dio.get<Map<String, dynamic>>(ApiEndpoints.order(id));
        return OrderDto.fromJson(res.data!);
      });

  @override
  Future<PaymentDto> renewPayment(String orderId) => guardApi(() async {
        final res = await _dio
            .post<Map<String, dynamic>>(ApiEndpoints.orderPayments(orderId));
        return PaymentDto.fromJson(res.data!);
      });

  @override
  Future<PaymentDto> getPayment(String id) => guardApi(() async {
        final res =
            await _dio.get<Map<String, dynamic>>(ApiEndpoints.payment(id));
        return PaymentDto.fromJson(res.data!);
      });

  @override
  Future<OrderDto> payWithWallet(String orderId) => guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
            ApiEndpoints.orderWalletPayment(orderId));
        return OrderDto.fromJson(res.data!);
      });

  @override
  Future<PaymentDto> mockConfirmPayment(String paymentId,
      {required bool success}) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
            ApiEndpoints.paymentSandboxConfirm(paymentId),
            data: {'success': success});
        return PaymentDto.fromJson(res.data!);
      });
}

final commerceApiProvider = Provider<CommerceApiService>((ref) {
  if (BackendModules.isMock(BackendModule.commerce)) {
    return MockCommerceRepository(
      currentUserId: () => mockPersonaId(ref.read(sessionControllerProvider)),
    );
  }
  return RemoteCommerceApiService(ref.watch(dioProvider));
});
