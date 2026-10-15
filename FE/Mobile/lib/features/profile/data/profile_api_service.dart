// lib/features/profile/data/profile_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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

/// One stored profile per mock account (`u_me`, `u_chef_tam`), so edits
/// and chef applications don't leak from one account to the other.
class MockProfileRepository implements ProfileApiService {
  MockProfileRepository(
      {required this.currentUserId, required this.currentUserName});

  final String? Function() currentUserId;
  final String Function() currentUserName;

  static final Map<String, Map<String, dynamic>> _users = {};

  @visibleForTesting
  static void reset() => _users.clear();

  static Map<String, dynamic> _seed(String id, String name) => switch (id) {
        'u_chef_tam' => {
            'id': id,
            'email': 'tam.chefchay@gmail.com',
            'fullName': name,
            'phone': '0903456789',
            'role': 'Chef',
            'status': 0,
            'authType': 1,
            'createdAt': '2025-11-20T03:00:00Z',
            'stats': {'posts': 0, 'likesReceived': 0, 'saved': 0},
            'chefApplication': {'status': 'approved'},
          },
        _ => {
            'id': id,
            'email': 'minhanh.nguyen@gmail.com',
            'fullName': name,
            'phone': '0912345678',
            'role': 'User',
            'status': 0,
            'authType': 1,
            'createdAt': '2026-07-02T08:15:00Z',
            'stats': {'posts': 2, 'likesReceived': 20, 'saved': 2},
            'chefApplication': {'status': 'none'},
          },
      };

  Map<String, dynamic> get _store {
    final id = currentUserId();
    if (id == null) {
      throw const ApiException(
          message: 'Vui lòng đăng nhập để tiếp tục.', statusCode: 401);
    }
    return _users.putIfAbsent(id, () => _seed(id, currentUserName()));
  }

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
      currentUserId: () => ref.read(sessionControllerProvider).userId,
      currentUserName: () =>
          ref.read(sessionControllerProvider).displayName ?? 'Minh Anh',
    );
  }
  return RemoteProfileApiService(ref.watch(dioProvider));
});
