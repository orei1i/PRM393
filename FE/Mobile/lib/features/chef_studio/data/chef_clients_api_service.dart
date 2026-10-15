// lib/features/chef_studio/data/chef_clients_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/session/session_controller.dart';
import '../domain/chef_client_rules.dart';
import 'mock_chef_clients_repository.dart';
import 'models/chef_client_models.dart';

/// "Khách hàng" (role Chef only, 403 otherwise): members using the signed-in
/// chef's packages, computed from orders, access grants and consultations.
abstract interface class ChefClientsApiService {
  /// All clients, or one tab's with [status].
  Future<List<ChefClientDto>> myClients({ClientBucket? status});

  /// 404 when [userId] never bought from this chef.
  Future<ChefClientDto> client(String userId);
}

class RemoteChefClientsApiService implements ChefClientsApiService {
  RemoteChefClientsApiService(this._dio);

  final Dio _dio;

  @override
  Future<List<ChefClientDto>> myClients({ClientBucket? status}) =>
      guardApi(() async {
        final res = await _dio.get<List<dynamic>>(ApiEndpoints.myChefClients,
            queryParameters: {if (status != null) 'status': status.apiValue});
        return (res.data ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ChefClientDto.fromJson)
            .toList();
      });

  @override
  Future<ChefClientDto> client(String userId) => guardApi(() async {
        final res = await _dio
            .get<Map<String, dynamic>>(ApiEndpoints.myChefClient(userId));
        return ChefClientDto.fromJson(res.data!);
      });
}

final chefClientsApiProvider = Provider<ChefClientsApiService>((ref) {
  if (Env.useMockData) {
    return MockChefClientsRepository(
      currentUserId: () => ref.read(sessionControllerProvider).userId,
      currentRole: () => ref.read(sessionControllerProvider).role,
    );
  }
  return RemoteChefClientsApiService(ref.watch(dioProvider));
});
