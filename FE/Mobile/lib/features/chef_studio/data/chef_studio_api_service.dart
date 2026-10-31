// lib/features/chef_studio/data/chef_studio_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/backend_modules.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/session/mock_persona.dart';
import '../../../core/session/session_controller.dart';
import 'mock_chef_studio_repository.dart';
import 'models/chef_studio_models.dart';

/// Role Chef only (403 otherwise): own profile & prices ("Hồ sơ & bảng
/// giá") and knowledge docs. "Me" is the chef profile of the signed-in user.
/// Booking requests live in `BookingApiService`; the wallet in
/// `ChefWalletApiService`.
abstract interface class ChefStudioApiService {
  /// 404 `chef_profile_missing` when the chef has no profile yet.
  Future<ChefProfileDto> getMyProfile();

  /// Upsert.
  Future<ChefProfileDto> updateMyProfile(ChefProfileRequestDto request);

  Future<List<KnowledgeDocDto>> myKnowledgeDocs();

  /// Starts `Pending`; the AI cites it only after an admin approves it.
  Future<KnowledgeDocDto> submitKnowledgeDoc(KnowledgeDocRequestDto request);
}

class RemoteChefStudioApiService implements ChefStudioApiService {
  RemoteChefStudioApiService(this._dio);

  final Dio _dio;

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
  Future<List<KnowledgeDocDto>> myKnowledgeDocs() => guardApi(() async {
        final res = await _dio.get<List<dynamic>>(ApiEndpoints.myKnowledgeDocs);
        return (res.data ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(KnowledgeDocDto.fromJson)
            .toList();
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
  if (BackendModules.isMock(BackendModule.chefStudio)) {
    return MockChefStudioRepository(
      currentUserId: () => mockPersonaId(ref.read(sessionControllerProvider)),
      currentUserName: () =>
          ref.read(sessionControllerProvider).displayName ?? 'Chuyên gia',
      currentRole: () => ref.read(sessionControllerProvider).role,
    );
  }
  return RemoteChefStudioApiService(ref.watch(dioProvider));
});
