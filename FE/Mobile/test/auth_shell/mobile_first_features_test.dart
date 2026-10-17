// test/auth_shell/mobile_first_features_test.dart
// Split from test/mobile_first_features_test.dart: the ApiResponse envelope,
// UserProfileDto and formatting & search.
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/network/api_envelope.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/user_role.dart';
import 'package:veganlife_mobile/core/utils/formatters.dart';
import 'package:veganlife_mobile/core/utils/text_search.dart';
import 'package:veganlife_mobile/features/profile/data/models/user_profile_model.dart';
import 'package:veganlife_mobile/features/profile/domain/entities/user_profile.dart';

void main() {
  group('ApiResponse envelope', () {
    test('unwraps data on success', () {
      final body = {
        'success': true,
        'message': null,
        'data': {'id': 'u_1'},
        'statusCode': 200
      };
      expect(unwrapEnvelope(body), {'id': 'u_1'});
    });

    test('throws ApiException with the server message on success:false', () {
      final body = {
        'success': false,
        'message': 'Email đã tồn tại.',
        'data': null,
        'statusCode': 409
      };
      expect(
        () => unwrapEnvelope(body),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', 'Email đã tồn tại.')
            .having((e) => e.statusCode, 'statusCode', 409)),
      );
    });

    test('passes through bodies that are not envelopes', () {
      expect(unwrapEnvelope({'items': <Object>[]}), {'items': <Object>[]});
      expect(unwrapEnvelope([1, 2]), [1, 2]);
    });
  });

  test('UserProfileDto accepts numeric enums from ASP.NET', () {
    final profile = UserProfileDto.fromJson({
      'id': 'u_me',
      'email': 'a@b.vn',
      'fullName': 'Minh Anh',
      'phone': '0912345678',
      'role': 'Member',
      'status': 2,
      'authType': 1,
      'createdAt': '2026-07-02T08:15:00Z',
      'chefApplication': {'status': 'pending'},
    }).toEntity();
    expect(profile.status, UserStatus.locked);
    expect(profile.signedInWithGoogle, isTrue);
    expect(profile.chefApplication, ChefApplicationStatus.pending);
    expect(profile.role, UserRole.user, reason: 'legacy Member');
    expect(profile.isVerifiedChef, isFalse);

    final chef = UserProfileDto.fromJson({
      'id': 12,
      'email': 'tam@x.vn',
      'name': 'Lê Quang Tâm',
      'role': 'Chef',
    }).toEntity();
    expect(chef.fullName, 'Lê Quang Tâm');
    expect(chef.role, UserRole.chef);
    expect(chef.isVerifiedChef, isTrue);
  });

  group('formatting & search', () {
    test('durations and VND', () {
      expect(formatDuration(724), '12:04');
      expect(formatDuration(3725), '1:02:05');
      expect(formatVnd(350000), '350.000đ');
    });

    test('accent-insensitive Vietnamese search', () {
      expect(foldVietnamese('Ẩm thực chay Huế'), 'am thuc chay hue');
      expect(matchesQuery('Tôn Nữ Minh Châu · Ẩm thực chay Huế', 'chay hue'),
          isTrue);
      expect(matchesQuery('Lê Quang Tâm', 'thu ha'), isFalse);
    });
  });
}
