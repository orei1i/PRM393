// test/hybrid/profile_contract_test.dart
// `/users/me`, the local chef application and the "Tôi" stats on recorded BE
// bodies, through the real Dio pipeline. No network.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/session/user_role.dart';
import 'package:veganlife_mobile/features/profile/data/models/user_profile_model.dart';
import 'package:veganlife_mobile/features/profile/data/profile_api_service.dart';
import 'package:veganlife_mobile/features/profile/domain/entities/user_profile.dart';
import 'package:veganlife_mobile/features/profile/presentation/controllers/profile_controller.dart';

import 'planner_test_support.dart';

const _request = ChefApplicationRequest(
  specialties: ['Dinh dưỡng thực vật'],
  yearsExperience: 3,
  city: 'TP.HCM',
  bio: 'Giới thiệu',
  certificates: ['Chứng chỉ'],
);

Map<String, dynamic> _me({String? status, String? id}) {
  final body = fixture('profile_fixture_me.json');
  final data = body['data'] as Map<String, dynamic>;
  data['id'] = id ?? testUserId;
  if (status != null) data['chefApplication'] = {'status': status};
  return body;
}

void main() {
  setUp(() => BackendModules.debugOverride(BackendModules.supportedByBackend));
  tearDown(() => BackendModules.debugOverride(null));

  ProfileApiService api(ProviderContainer c) => c.read(profileApiProvider);

  group('GET /users/me', () {
    test('a recorded body reads whole', () async {
      final backend = FakeBackend()..on('GET /users/me', 200, _me());
      final c = await backendContainer(backend);

      final me = (await api(c).getMe()).toEntity();
      expect(me.id, testUserId);
      expect(me.fullName, 'FE M1');
      expect(me.role, UserRole.user);
      expect(me.status, UserStatus.active);
      expect(me.signedInWithGoogle, isFalse);
      expect(me.postCount, 0);
      expect(me.chefApplication, ChefApplicationStatus.none);
      expect(me.isVerifiedChef, isFalse);
    });

    test('approved reads as verified', () async {
      final backend = FakeBackend()
        ..on('GET /users/me', 200, _me(status: 'approved'));
      final c = await backendContainer(backend);
      expect((await api(c).getMe()).toEntity().isVerifiedChef, isTrue);
    });
  });

  group('chef application stays on this device (D8)', () {
    test('submitting asks nothing, and the profile then reads pending',
        () async {
      final backend = FakeBackend()..on('GET /users/me', 200, _me());
      final c = await backendContainer(backend);

      await api(c).submitChefApplication(_request);
      expect(backend.seen, isEmpty);
      expect(
          c
              .read(sharedPreferencesProvider)
              .getString('vl.chef_application.$testUserId'),
          'pending');

      final me = (await api(c).getMe()).toEntity();
      expect(me.chefApplication, ChefApplicationStatus.pending);
    });

    test('through the controller', () async {
      final backend = FakeBackend()..on('GET /users/me', 200, _me());
      final c = await backendContainer(backend);
      addTearDown(c.listen(profileControllerProvider, (_, __) {}).close);
      await c.read(profileControllerProvider.future);

      await c
          .read(profileControllerProvider.notifier)
          .submitChefApplication(_request);
      expect(c.read(profileControllerProvider).requireValue.chefApplication,
          ChefApplicationStatus.pending);
    });

    test('whatever the BE says other than none wins', () async {
      final backend = FakeBackend()
        ..on('GET /users/me', 200, _me(status: 'approved'));
      final c = await backendContainer(backend);
      await api(c).submitChefApplication(_request);
      expect((await api(c).getMe()).toEntity().chefApplication,
          ChefApplicationStatus.approved);
    });

    test('another account on this device is not affected', () async {
      final backend = FakeBackend()
        ..on('GET /users/me', 200, _me(id: 'someone_else'));
      final c = await backendContainer(backend);
      await api(c).submitChefApplication(_request);
      expect((await api(c).getMe()).toEntity().chefApplication,
          ChefApplicationStatus.none);
    });

    test('a guest cannot', () async {
      final c = await backendContainer(FakeBackend(), signedIn: false);
      await expectLater(api(c).submitChefApplication(_request),
          throwsA(isA<ApiException>().having((e) => e.statusCode, '', 401)));
    });
  });

  group('saving "Thông tin cá nhân"', () {
    test('403 (B3) says so in Vietnamese and keeps the profile', () async {
      final backend = FakeBackend()
        ..on('GET /users/me', 200, _me())
        ..on('PUT /users/$testUserId', 403, null);
      final c = await backendContainer(backend);
      addTearDown(c.listen(profileControllerProvider, (_, __) {}).close);
      await c.read(profileControllerProvider.future);

      await expectLater(
        c
            .read(profileControllerProvider.notifier)
            .updateInfo(fullName: 'Tên Mới'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message',
            'Máy chủ chưa cho phép đổi thông tin cá nhân. Thử lại sau nhé.')),
      );
      expect(c.read(profileControllerProvider).requireValue.fullName, 'FE M1');
    });

    test('once B3 is fixed it saves, then reloads the whole profile', () async {
      var name = 'FE M1';
      final backend = FakeBackend();
      backend.routes['GET /users/me'] = (_) {
        final body = _me();
        (body['data'] as Map)['fullName'] = name;
        (body['data'] as Map)['stats'] = {'posts': 4};
        return (200, body);
      };
      backend.routes['PUT /users/$testUserId'] = (request) {
        name = (request.data as Map)['fullName'] as String;
        // UserResponse: no stats.
        return (200, envelope({'id': testUserId, 'fullName': name}));
      };
      final c = await backendContainer(backend);
      addTearDown(c.listen(profileControllerProvider, (_, __) {}).close);
      await c.read(profileControllerProvider.future);

      await c
          .read(profileControllerProvider.notifier)
          .updateInfo(fullName: 'Tên Mới', phone: '0912345678');

      final me = c.read(profileControllerProvider).requireValue;
      expect(me.fullName, 'Tên Mới');
      expect(me.postCount, 4);
      expect(backend.bodyOf('PUT /users/$testUserId'),
          {'fullName': 'Tên Mới', 'phone': '0912345678'});
    });

    test('other failures keep the BE message', () async {
      final backend = FakeBackend()
        ..on('PUT /users/$testUserId', 400,
            {'success': false, 'message': 'Tên không hợp lệ.'});
      final c = await backendContainer(backend);
      await expectLater(
        api(c).updateMe(testUserId, const UpdateUserRequestDto(fullName: 'x')),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', 'Tên không hợp lệ.')),
      );
    });
  });

  group('stats on "Tôi"', () {
    test('follow the feed and the saved list, not the zeros of /users/me',
        () async {
      final backend = FakeBackend()
        ..on('GET /users/me', 200, _me())
        ..on(
            'GET /posts',
            200,
            envelope({
              'items': [
                for (final (id, author, likes) in [
                  ('a', testUserId, 2),
                  ('b', 'someone_else', 9),
                  ('c', testUserId, 3),
                ])
                  {
                    'id': id,
                    'type': 'recipe',
                    'author': {'id': author, 'fullName': 'Ai đó'},
                    'title': 'Bài',
                    'likeCount': likes,
                  },
              ],
              'page': 1,
              'totalPages': 1,
            }))
        ..on('GET /posts/b', 200, envelope({'id': 'b', 'title': 'Đã lưu'}));
      final c = await backendContainer(backend);
      await c
          .read(sharedPreferencesProvider)
          .setStringList('vl.saved_posts.$testUserId', const ['b']);

      addTearDown(c.listen(profileStatsProvider, (_, __) {}).close);
      await c.read(myPostsProvider.future);
      await c.read(savedPostsProvider.future);

      expect(
          c.read(profileStatsProvider), (posts: 2, likesReceived: 5, saved: 1));
      expect(c.read(myPostsTruncatedProvider), isFalse);
    });
  });
}
