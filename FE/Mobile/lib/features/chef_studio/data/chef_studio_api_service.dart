// lib/features/chef_studio/data/chef_studio_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/session/session_controller.dart';
import '../../chef/data/models/service_model.dart';
import '../../commerce/data/models/consultation_model.dart';
import '../../commerce/data/models/order_model.dart';
import '../../commerce/domain/commerce_status.dart';
import 'mock_chef_studio_repository.dart';
import 'models/chef_studio_models.dart';

/// Role Chef only (403 otherwise): own profile, services, bookings and
/// knowledge docs. "Me" is the chef profile of the signed-in user.
abstract interface class ChefStudioApiService {
  /// 404 `chef_profile_missing` when the chef has no profile yet.
  Future<ChefProfileDto> getMyProfile();

  /// Upsert.
  Future<ChefProfileDto> updateMyProfile(ChefProfileRequestDto request);

  Future<List<ServiceDto>> myServices();

  Future<ServiceDto> createService(ServiceRequestDto request);

  Future<ServiceDto> updateService(String id, ServiceRequestDto request);

  /// 409 `service_has_orders` once someone ordered it.
  Future<void> deleteService(String id);

  /// Orders for my services, with `buyer`.
  Future<List<OrderDto>> myOrders({OrderStatus? status});

  /// Paid consultations only (unpaid holds stay with the buyer).
  Future<List<ConsultationDto>> myConsultations({ConsultationStatus? status});

  Future<ConsultationDto> confirmConsultation(String id);

  /// Refunds the order (stub).
  Future<ConsultationDto> declineConsultation(String id, String reason);

  /// 409 `too_early` before `startAt − 15 min`.
  Future<ConsultationDto> startConsultation(String id);

  Future<ConsultationDto> completeConsultation(String id, String notes);

  Future<List<KnowledgeDocDto>> myKnowledgeDocs();

  /// Starts `Pending`; the AI cites it only after an admin approves it.
  Future<KnowledgeDocDto> submitKnowledgeDoc(KnowledgeDocRequestDto request);
}

class RemoteChefStudioApiService implements ChefStudioApiService {
  RemoteChefStudioApiService(this._dio);

  final Dio _dio;

  List<T> _list<T>(List<dynamic>? data, T Function(Map<String, dynamic>) f) =>
      (data ?? const []).whereType<Map<String, dynamic>>().map(f).toList();

  Future<ConsultationDto> _action(String id, String action,
          [Map<String, dynamic>? body]) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
            ApiEndpoints.chefConsultationAction(id, action),
            data: body);
        return ConsultationDto.fromJson(res.data!);
      });

  @override
  Future<ChefProfileDto> getMyProfile() => guardApi(() async {
        final res =
            await _dio.get<Map<String, dynamic>>(ApiEndpoints.myChefProfile);
        return ChefProfileDto.fromJson(res.data!);
      });

  @override
  Future<ChefProfileDto> updateMyProfile(ChefProfileRequestDto request) =>
      guardApi(() async {
        final res = await _dio.put<Map<String, dynamic>>(
            ApiEndpoints.myChefProfile,
            data: request.toJson());
        return ChefProfileDto.fromJson(res.data!);
      });

  @override
  Future<List<ServiceDto>> myServices() => guardApi(() async {
        final res = await _dio.get<List<dynamic>>(ApiEndpoints.myChefServices);
        return _list(res.data, ServiceDto.fromJson);
      });

  @override
  Future<ServiceDto> createService(ServiceRequestDto request) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
            ApiEndpoints.myChefServices,
            data: request.toJson());
        return ServiceDto.fromJson(res.data!);
      });

  @override
  Future<ServiceDto> updateService(String id, ServiceRequestDto request) =>
      guardApi(() async {
        final res = await _dio.put<Map<String, dynamic>>(
            ApiEndpoints.myChefService(id),
            data: request.toJson());
        return ServiceDto.fromJson(res.data!);
      });

  @override
  Future<void> deleteService(String id) => guardApi(() async {
        await _dio.delete<void>(ApiEndpoints.myChefService(id));
      });

  @override
  Future<List<OrderDto>> myOrders({OrderStatus? status}) => guardApi(() async {
        final res = await _dio.get<List<dynamic>>(ApiEndpoints.myChefOrders,
            queryParameters: {if (status != null) 'status': status.apiValue});
        return _list(res.data, OrderDto.fromJson);
      });

  @override
  Future<List<ConsultationDto>> myConsultations({ConsultationStatus? status}) =>
      guardApi(() async {
        final res = await _dio.get<List<dynamic>>(
            ApiEndpoints.myChefConsultations,
            queryParameters: {if (status != null) 'status': status.apiValue});
        return _list(res.data, ConsultationDto.fromJson);
      });

  @override
  Future<ConsultationDto> confirmConsultation(String id) =>
      _action(id, 'confirm');

  @override
  Future<ConsultationDto> declineConsultation(String id, String reason) =>
      _action(id, 'decline', {'reason': reason});

  @override
  Future<ConsultationDto> startConsultation(String id) => _action(id, 'start');

  @override
  Future<ConsultationDto> completeConsultation(String id, String notes) =>
      _action(id, 'complete', {'notes': notes});

  @override
  Future<List<KnowledgeDocDto>> myKnowledgeDocs() => guardApi(() async {
        final res = await _dio.get<List<dynamic>>(ApiEndpoints.myKnowledgeDocs);
        return _list(res.data, KnowledgeDocDto.fromJson);
      });

  @override
  Future<KnowledgeDocDto> submitKnowledgeDoc(KnowledgeDocRequestDto request) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
            ApiEndpoints.myKnowledgeDocs,
            data: request.toJson());
        return KnowledgeDocDto.fromJson(res.data!);
      });
}

final chefStudioApiProvider = Provider<ChefStudioApiService>((ref) {
  if (Env.useMockData) {
    return MockChefStudioRepository(
      currentUserId: () => ref.read(sessionControllerProvider).userId,
      currentUserName: () =>
          ref.read(sessionControllerProvider).displayName ?? 'Chuyên gia',
      currentRole: () => ref.read(sessionControllerProvider).role,
    );
  }
  return RemoteChefStudioApiService(ref.watch(dioProvider));
});
