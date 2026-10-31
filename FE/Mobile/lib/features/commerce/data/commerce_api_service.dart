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
/// accepted, `POST /bookings/{id}/payments` opens its QR) → PaymentOS QR →
/// status → escrow. Course / VIP Menu purchases and consultations are gone;
/// an unpaid booking is cancelled from the booking itself ("Huỷ yêu cầu").
abstract interface class CommerceApiService {
  Future<OrderDto> getOrder(String id);

  /// A new QR after the last one expired or failed.
  Future<PaymentDto> renewPayment(String orderId);

  /// Polled every 3 s by the payment screen.
  Future<PaymentDto> getPayment(String id);

  /// Mock/dev only; the real confirmation is the PaymentOS webhook (BE).
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
  Future<PaymentDto> mockConfirmPayment(String paymentId,
      {required bool success}) async {
    throw const ApiException(
      message: 'Chỉ dùng được ở chế độ mô phỏng.',
      code: 'not_supported',
    );
  }
}

final commerceApiProvider = Provider<CommerceApiService>((ref) {
  if (BackendModules.isMock(BackendModule.commerce)) {
    return MockCommerceRepository(
      currentUserId: () => mockPersonaId(ref.read(sessionControllerProvider)),
    );
  }
  return RemoteCommerceApiService(ref.watch(dioProvider));
});
