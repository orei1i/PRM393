// lib/features/profile/data/profile_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/utils/mock_delay.dart';
import '../domain/entities/user_profile.dart';
import 'models/user_profile_model.dart';

abstract interface class ProfileApiService {
  Future<UserProfileDto> getMe();

  /// BE: `PUT /api/v1/users/{id}` with `UpdateUserRequest { fullName, phone }`.
  Future<UserProfileDto> updateMe(String userId, UpdateUserRequestDto request);

  /// Goes to the admin "Duyệt chuyên gia" queue on the web console.
  Future<void> submitChefApplication(ChefApplicationRequest request);
}

class RemoteProfileApiService implements ProfileApiService {
  RemoteProfileApiService(this._dio);

  final Dio _dio;

  @override
  Future<UserProfileDto> getMe() => guardApi(() async {
        final res = await _dio.get<Map<String, dynamic>>(ApiEndpoints.me);
        return UserProfileDto.fromJson(res.data!);
      });

  @override
  Future<UserProfileDto> updateMe(
          String userId, UpdateUserRequestDto request) =>
      guardApi(() async {
        final res = await _dio.put<Map<String, dynamic>>(
            ApiEndpoints.user(userId),
            data: request.toJson());
        return UserProfileDto.fromJson(res.data!);
      });

  @override
  Future<void> submitChefApplication(ChefApplicationRequest request) =>
      guardApi(() async {
        await _dio.post<void>(ApiEndpoints.chefApplications,
            data: request.toJson());
      });
}

class MockProfileRepository implements ProfileApiService {
  MockProfileRepository({required this.displayName});

  final String displayName;

  static Map<String, dynamic>? _me;

  Map<String, dynamic> get _store => _me ??= {
        'id': 'u_me',
        'email': 'minhanh.nguyen@gmail.com',
        'fullName': displayName,
        'phone': '0912345678',
        'role': 'Member',
        'status': 0,
        'authType': 1,
        'createdAt': '2026-07-02T08:15:00Z',
        'stats': {'posts': 2, 'likesReceived': 20, 'saved': 2},
        'chefApplication': {'status': 'none'},
      };

  @override
  Future<UserProfileDto> getMe() async {
    await mockDelay(500);
    return UserProfileDto.fromJson(_store);
  }

  @override
  Future<UserProfileDto> updateMe(
      String userId, UpdateUserRequestDto request) async {
    await mockDelay(700);
    if (request.fullName.toLowerCase().contains('#fail')) {
      throw const ApiException(
          message: 'Máy chủ đang bận, chưa lưu được thay đổi.',
          statusCode: 503);
    }
    _store
      ..['fullName'] = request.fullName
      ..['phone'] = request.phone ?? '';
    return UserProfileDto.fromJson(_store);
  }

  @override
  Future<void> submitChefApplication(ChefApplicationRequest request) async {
    await mockDelay(900);
    _store['chefApplication'] = {'status': 'pending'};
  }
}

final profileApiProvider = Provider<ProfileApiService>((ref) {
  if (Env.useMockData) {
    return MockProfileRepository(
        displayName:
            ref.read(sessionControllerProvider).displayName ?? 'Minh Anh');
  }
  return RemoteProfileApiService(ref.watch(dioProvider));
});
