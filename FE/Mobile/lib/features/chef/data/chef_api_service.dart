// lib/features/chef/data/chef_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import 'mock_chef_repository.dart';
import 'models/chef_model.dart';

/// Public chef directory (guests too). Booking a chef goes through
/// `BookingApiService` (`POST /bookings`).
abstract interface class ChefApiService {
  Future<List<ChefDto>> listChefs({String? query, String? specialty});

  /// With bio, certificates and the booking prices.
  Future<ChefDto> getChef(String id);
}

class RemoteChefApiService implements ChefApiService {
  RemoteChefApiService(this._dio);

  final Dio _dio;

  @override
  Future<List<ChefDto>> listChefs({String? query, String? specialty}) =>
      guardApi(() async {
        final res = await _dio.get<List<dynamic>>(
          ApiEndpoints.chefs,
          queryParameters: {
            if (query != null && query.isNotEmpty) 'q': query,
            if (specialty != null) 'specialty': specialty,
          },
        );
        return (res.data ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ChefDto.fromJson)
            .toList();
      });

  @override
  Future<ChefDto> getChef(String id) => guardApi(() async {
        final res = await _dio.get<Map<String, dynamic>>(ApiEndpoints.chef(id));
        return ChefDto.fromJson(res.data!);
      });
}

final chefApiProvider = Provider<ChefApiService>((ref) {
  if (Env.useMockData) return MockChefRepository();
  return RemoteChefApiService(ref.watch(dioProvider));
});
