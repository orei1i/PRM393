// integration_test_be/profile_be_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/features/profile/data/models/user_profile_model.dart';
import 'package:veganlife_mobile/features/profile/data/profile_api_service.dart';
import 'package:veganlife_mobile/features/profile/domain/entities/user_profile.dart';

import 'be_harness.dart';

Future<void> main() async {
  final be = await BeHarness.start();

  group('profile', skip: be.skipReason, () {
    late BeUser me;
    late ProfileApiService profile;

    setUpAll(() async {
      me = await be.newUser(name: 'FE IT Profile');
      profile = RemoteProfileApiService(me.dio, currentUserId: () => me.id);
    });

    beTest('getMe returns the account', () async {
      final user = (await profile.getMe()).toEntity();
      expect(user.id, me.id);
      expect(user.email, me.email);
      expect(user.fullName, 'FE IT Profile');
    });

    beTest('B3: a member renames themselves, and only themselves', () async {
      final saved = (await profile.updateMe(
              me.id,
              const UpdateUserRequestDto(
                  fullName: 'Tên mới', phone: '0912345678')))
          .toEntity();
      expect(saved.fullName, 'Tên mới');
      final read = (await profile.getMe()).toEntity();
      expect(read.fullName, 'Tên mới');
      expect(read.phone, '0912345678');

      // No phone: the saved one stays (the form sends null for an empty field).
      await profile.updateMe(
          me.id, const UpdateUserRequestDto(fullName: 'Tên mới 2'));
      expect((await profile.getMe()).toEntity().phone, '0912345678');

      final other = await be.newUser(name: 'FE IT Profile Other');
      await expectApiError(
        profile.updateMe(other.id,
            const UpdateUserRequestDto(fullName: 'Tên của người khác')),
        status: 403,
      );
      expect((await other.raw('GET', '/users/me')).dataMap['fullName'],
          'FE IT Profile Other');
      expect((await me.raw('GET', '/users/${other.id}')).status, 403);
    });

    beTest('B3: an empty name is refused, with the reason of the field',
        () async {
      await expectApiError(
        profile.updateMe(me.id, const UpdateUserRequestDto(fullName: '')),
        status: 400,
        message: 'Họ tên là bắt buộc.',
      );
    });

    beTest('B3: a role cannot be changed through it', () async {
      final res = await me.raw('PUT', '/users/${me.id}',
          data: {'fullName': 'Tên mới', 'role': 'Admin'});
      expect(res.status, 200);
      expect((await me.raw('GET', '/users/me')).dataMap['role'], 'User');
    });

    beTest('B22: the counts are real', () async {
      final author = await be.newUser(name: 'FE IT Profile Stats');
      final liker = await be.newUser(name: 'FE IT Profile Liker');
      Future<Map<String, dynamic>> stats() async =>
          (await author.raw('GET', '/users/me')).dataMap['stats']
              as Map<String, dynamic>;
      expect((await stats())['posts'], 0);

      final post = await author.raw('POST', '/posts', data: {
        'type': 'discussion',
        'title': 'Bài đếm số liệu',
        'body': 'Bài dùng để thử số liệu trên trang Tôi.',
        'tags': <String>[],
        'mediaType': 'Text',
        'mediaUrl': null,
      });
      final id = post.dataMap['id'];
      await liker.raw('POST', '/posts/$id/like');
      expect(await stats(), containsPair('posts', 1));
      expect(await stats(), containsPair('likesReceived', 1));
      await liker.raw('POST', '/posts/$id/like');
      expect(await stats(), containsPair('likesReceived', 0));
      await author.raw('DELETE', '/posts/$id');
      expect(await stats(), containsPair('posts', 0));
    });

    beTest('a chef application stays on the device, per account', () async {
      await profile.submitChefApplication(const ChefApplicationRequest(
        specialties: ['Món chay'],
        yearsExperience: 3,
        city: 'TP.HCM',
        bio: 'Đầu bếp chay nhiều năm kinh nghiệm.',
        certificates: [],
      ));
      expect((await profile.getMe()).toEntity().chefApplication,
          ChefApplicationStatus.pending);

      final other = await be.newUser(name: 'FE IT Profile 2');
      final otherProfile =
          RemoteProfileApiService(other.dio, currentUserId: () => other.id);
      expect((await otherProfile.getMe()).toEntity().chefApplication,
          ChefApplicationStatus.none);
    });

    beTest('a guest has no profile', () async {
      await expectApiError(
        RemoteProfileApiService(be.guestDio()).getMe(),
        status: 401,
      );
    });
  });
}
