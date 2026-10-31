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

    beTest('B3: updateMe reads as the "not allowed yet" message', () async {
      await expectApiError(
        profile.updateMe(
            me.id, const UpdateUserRequestDto(fullName: 'Tên mới')),
        status: 403,
        message: profileUpdateForbiddenMessage,
      );
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
