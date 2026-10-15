// lib/features/commerce/data/commerce_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/session/session_controller.dart';
import '../domain/commerce_status.dart';
import 'mock_commerce_repository.dart';
import 'models/consultation_model.dart';
import 'models/order_model.dart';
import 'models/payment_model.dart';

/// Buyer side: order → PaymentOS QR → status → access grant.
abstract interface class CommerceApiService {
  /// A consult order also creates its consultation (AwaitingPayment), which
  /// holds the slot while the 15-minute QR is payable.
  Future<OrderDto> createOrder(CreateOrderRequestDto request);

  Future<List<OrderDto>> myOrders({OrderStatus? status});

  Future<OrderDto> getOrder(String id);

  /// Pending orders only.
  Future<OrderDto> cancelOrder(String id);

  /// A new QR after the last one expired or failed.
  Future<PaymentDto> renewPayment(String orderId);

  /// Polled every 3 s by the payment screen.
  Future<PaymentDto> getPayment(String id);

  /// Mock/dev only; the real confirmation is the PaymentOS webhook (BE).
  Future<PaymentDto> mockConfirmPayment(String paymentId,
      {required bool success});

  Future<List<ConsultationDto>> myConsultations();

  /// Refund stub: consultation Cancelled, order/payment Refunded, grant Revoked.
  Future<ConsultationDto> cancelConsultation(String id);

  /// 403 `no_access` without an Active grant.
  Future<ServiceContentDto> getServiceContent(String serviceId);
}

class RemoteCommerceApiService implements CommerceApiService {
  RemoteCommerceApiService(this._dio);

  final Dio _dio;

  List<T> _list<T>(List<dynamic>? data, T Function(Map<String, dynamic>) f) =>
      (data ?? const []).whereType<Map<String, dynamic>>().map(f).toList();

  @override
  Future<OrderDto> createOrder(CreateOrderRequestDto request) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(ApiEndpoints.orders,
            data: request.toJson());
        return OrderDto.fromJson(res.data!);
      });

  @override
  Future<List<OrderDto>> myOrders({OrderStatus? status}) => guardApi(() async {
        final res = await _dio.get<List<dynamic>>(ApiEndpoints.myOrders,
            queryParameters: {if (status != null) 'status': status.apiValue});
        return _list(res.data, OrderDto.fromJson);
      });

  @override
  Future<OrderDto> getOrder(String id) => guardApi(() async {
        final res =
            await _dio.get<Map<String, dynamic>>(ApiEndpoints.order(id));
        return OrderDto.fromJson(res.data!);
      });

  @override
  Future<OrderDto> cancelOrder(String id) => guardApi(() async {
        final res =
            await _dio.post<Map<String, dynamic>>(ApiEndpoints.cancelOrder(id));
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

  @override
  Future<List<ConsultationDto>> myConsultations() => guardApi(() async {
        final res = await _dio.get<List<dynamic>>(ApiEndpoints.myConsultations);
        return _list(res.data, ConsultationDto.fromJson);
      });

  @override
  Future<ConsultationDto> cancelConsultation(String id) => guardApi(() async {
        final res = await _dio
            .post<Map<String, dynamic>>(ApiEndpoints.cancelConsultation(id));
        return ConsultationDto.fromJson(res.data!);
      });

  @override
  Future<ServiceContentDto> getServiceContent(String serviceId) =>
      guardApi(() async {
        final res = await _dio
            .get<Map<String, dynamic>>(ApiEndpoints.serviceContent(serviceId));
        return ServiceContentDto.fromJson(res.data!);
      });
}

final commerceApiProvider = Provider<CommerceApiService>((ref) {
  if (Env.useMockData) {
    return MockCommerceRepository(
      currentUserId: () => ref.read(sessionControllerProvider).userId,
      currentUserName: () =>
          ref.read(sessionControllerProvider).displayName ?? 'Bạn',
    );
  }
  return RemoteCommerceApiService(ref.watch(dioProvider));
});
