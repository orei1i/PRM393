// integration_test_be/auth_be_test.dart
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/network/api_endpoints.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/network/dio_client.dart';
import 'package:veganlife_mobile/core/session/auth_api_service.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/session/user_role.dart';
import 'package:veganlife_mobile/core/utils/backend_ids.dart';

import 'be_harness.dart';

Future<void> main() async {
  final be = await BeHarness.start();

  group('auth', skip: be.skipReason, () {
    late BeUser me;
    late AuthApiService auth;

    setUpAll(() async {
      // Only for `rootScaffoldMessengerKey` in SessionController.expire; its
      // HttpOverrides would answer 400 to everything, so it comes off again.
      TestWidgetsFlutterBinding.ensureInitialized();
      HttpOverrides.global = null;
      me = await be.newUser(name: 'FE IT Auth');
      auth = RemoteAuthApiService(be.guestDio());
    });

    beTest('register returns a member with a real id', () async {
      expect(isBackendId(me.id), isTrue);
      final result = await auth.register(RegisterRequest(
        fullName: 'FE IT Auth 2',
        email: randomEmail(),
        password: randomPassword(),
      ));
      expect(result.role, UserRole.user);
      expect(result.displayName, 'FE IT Auth 2');
      expect(result.expiresAt!.isAfter(DateTime.now()), isTrue);
    });

    beTest('login with the right password', () async {
      final result = await auth.login(email: me.email, password: me.password);
      expect(result.userId, me.id);
      expect(result.accessToken, isNotEmpty);
    });

    beTest('wrong password and unknown email read the same, in Vietnamese',
        () async {
      await expectApiError(
        auth.login(email: me.email, password: randomPassword()),
        status: 401,
        message: AuthErrors.invalidCredentials,
      );
      await expectApiError(
        auth.login(email: randomEmail(), password: randomPassword()),
        status: 401,
        message: AuthErrors.invalidCredentials,
      );
    });

    beTest('email taken', () async {
      await expectApiError(
        auth.register(RegisterRequest(
          fullName: 'FE IT Auth',
          email: me.email,
          password: randomPassword(),
        )),
        status: 409,
        message: AuthErrors.emailTaken,
      );
    });

    beTest('validation errors are Vietnamese, never English', () async {
      await expectApiError(
        auth.register(RegisterRequest(
          fullName: 'FE IT Auth',
          email: 'not-an-email',
          password: randomPassword(),
        )),
        status: 400,
      );
      await expectApiError(
        auth.register(RegisterRequest(
          fullName: 'FE IT Auth',
          email: randomEmail(),
          password: 'abc',
        )),
        status: 400,
      );
    });

    beTest('B23: a wrong code is Vietnamese; 5 of them use the code up',
        () async {
      expect(await auth.requestPasswordReset(me.email), isNull);
      for (var i = 0; i < 4; i++) {
        await expectApiError(
          auth.verifyResetCode(email: me.email, code: '000000'),
          status: 400,
          code: 'invalid_code',
          message: AuthErrors.invalidCode,
        );
      }
      await expectApiError(
        auth.verifyResetCode(email: me.email, code: '000000'),
        status: 400,
        code: 'code_expired',
      );
      await expectApiError(
        auth.verifyResetCode(email: me.email, code: '000000'),
        status: 400,
        code: 'code_expired',
      );
    });

    beTest(
        'B23, B42: forgot password, right code, new password; the old one '
        'and the old sessions end', () async {
      final user = await be.newUser(name: 'FE IT Reset');
      final api = RemoteAuthApiService(be.guestDio());
      expect(await api.requestPasswordReset(user.email), isNull);
      final code = await devResetCode(user.email);
      final resetToken =
          await api.verifyResetCode(email: user.email, code: code);
      expect(resetToken, isNotEmpty);
      final newPassword = randomPassword();
      await api.resetPassword(resetToken: resetToken, newPassword: newPassword);

      final back = await api.login(email: user.email, password: newPassword);
      expect(back.userId, user.id);
      await expectApiError(
        api.login(email: user.email, password: user.password),
        status: 401,
        message: AuthErrors.invalidCredentials,
      );
      await expectApiError(api.refresh(user.refreshToken), status: 401);
      await expectApiError(
        api.resetPassword(
            resetToken: resetToken, newPassword: randomPassword()),
        status: 400,
      );
    });

    group('B2, B5: the seed accounts', () {
      beTest('a member and a chef sign in here', () async {
        final member = await be.seedLogin(seedMemberEmail);
        expect(member.status, 200);
        expect((member.dataMap['user'] as Map)['role'], 'User');
        final chef = await be.seedLogin(seedChefEmail);
        expect(chef.status, 200);
        final role = (chef.dataMap['user'] as Map)['role'];
        expect(UserRole.fromApi(role), UserRole.chef);
        final profile = await rawRequest('GET', '/users/me',
            token: chef.dataMap['accessToken'] as String);
        expect(
            (profile.dataMap['chefApplication'] as Map)['status'], 'approved');
      });

      beTest('an admin only signs in on its own route', () async {
        final admin = await be.seedLogin(seedAdminEmail);
        expect(admin.status, 403);
        expect(
            AuthErrors.localize(ApiException(
                    message: admin.json['message'] as String,
                    statusCode: admin.status))
                .message,
            AuthErrors.adminWebOnly);
        final route =
            await be.seedLogin(seedAdminEmail, path: '/auth/admin/login');
        expect(route.status, 200);
        expect((route.dataMap['user'] as Map)['role'], 'Admin');
        expect(
            (await be.seedLogin(seedMemberEmail, path: '/auth/admin/login'))
                .status,
            403);
      });
    });

    group('B18: refresh', () {
      beTest('a refresh rotates: the old token is dead, the new one works',
          () async {
        final user = await be.newUser(name: 'FE IT Refresh');
        final api = RemoteAuthApiService(be.guestDio());
        final fresh = await api.refresh(user.refreshToken);
        expect(fresh.refreshToken, isNot(user.refreshToken));
        expect(fresh.userId, user.id);
        await expectApiError(api.refresh(user.refreshToken), status: 401);
        expect(
            (await rawRequest('GET', '/users/me', token: fresh.accessToken))
                .status,
            200);
        await api.refresh(fresh.refreshToken!);
      });

      beTest('a garbage JWT refreshes silently; the request goes through',
          () async {
        final user = await be.newUser(name: 'FE IT Refresh');
        final c = await user.container(
          realDio: true,
          tokenOverride: 'bad.token',
          refreshTokenOverride: user.refreshToken,
        );
        addTearDown(c.dispose);

        final res = await c.read(dioProvider).get<Object?>(ApiEndpoints.me);

        expect(res.statusCode, 200);
        final session = c.read(sessionControllerProvider);
        expect(session.isGuest, isFalse);
        expect(session.accessToken, isNot('bad.token'));
        final prefs = c.read(sharedPreferencesProvider);
        expect(prefs.getString(SessionController.refreshTokenKey),
            isNot(user.refreshToken));
      });

      beTest('a dead refresh token ends the session', () async {
        final user = await be.newUser(name: 'FE IT Refresh');
        final c = await user.container(
          realDio: true,
          tokenOverride: 'bad.token',
          refreshTokenOverride: 'dead',
        );
        addTearDown(c.dispose);
        await expectLater(
          c.read(dioProvider).get<Object?>(ApiEndpoints.me),
          throwsA(isA<DioException>()
              .having((e) => mapDioException(e).statusCode, 'status', 401)),
        );
        final session = c.read(sessionControllerProvider);
        expect(session.isGuest, isTrue);
        expect(session.userId, isNull);
      });

      beTest('signing out revokes the refresh token', () async {
        final user = await be.newUser(name: 'FE IT Refresh');
        final c = await user.container(
            realDio: true, refreshTokenOverride: user.refreshToken);
        addTearDown(c.dispose);
        await c.read(sessionControllerProvider.notifier).signOut();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(c.read(sessionControllerProvider).isGuest, isTrue);
        await expectApiError(
          RemoteAuthApiService(be.guestDio()).refresh(user.refreshToken),
          status: 401,
        );
      });

      beTest(
          'B55: each device keeps its session: a second login leaves the first '
          'refresh alive, and a refresh there rotates only that one', () async {
        final user = await be.newUser(name: 'FE IT Refresh');
        final second =
            await auth.login(email: user.email, password: user.password);
        final api = RemoteAuthApiService(be.guestDio());
        final first = await api.refresh(user.refreshToken);
        expect(first.userId, user.id);
        await expectApiError(api.refresh(user.refreshToken), status: 401);
        final rotated = await api.refresh(second.refreshToken!);
        expect(rotated.refreshToken, isNot(second.refreshToken));
        expect(rotated.userId, user.id);
        await api.refresh(first.refreshToken!);
      });

      beTest('B55: signing out on one device leaves the other signed in',
          () async {
        final user = await be.newUser(name: 'FE IT Refresh');
        final other =
            await auth.login(email: user.email, password: user.password);
        final c = await user.container(
            realDio: true, refreshTokenOverride: user.refreshToken);
        addTearDown(c.dispose);
        await c.read(sessionControllerProvider.notifier).signOut();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final api = RemoteAuthApiService(be.guestDio());
        await expectApiError(api.refresh(user.refreshToken), status: 401);
        expect((await api.refresh(other.refreshToken!)).userId, user.id);
      });
    });

    beTest('B25: the errors envelope reaches the member by field', () async {
      final raw = await rawRequest('POST', '/auth/register', data: {
        'fullName': '',
        'email': 'not-an-email',
        'password': 'abc',
      });
      expect(raw.status, 400);
      expect(raw.json['success'], isFalse);
      expect(raw.json['errors'], isA<Map<String, dynamic>>());
      await expectApiError(
        auth.register(const RegisterRequest(
            fullName: '', email: 'not-an-email', password: 'abc')),
        status: 400,
        message: 'Email không đúng định dạng. Họ tên là bắt buộc. '
            'Mật khẩu phải có ít nhất 8 ký tự.',
      );
    });

    beTest('a 401 on /auth/* does not end the session', () async {
      final c = await me.container(realDio: true);
      addTearDown(c.dispose);
      await expectLater(
        RemoteAuthApiService(c.read(dioProvider))
            .login(email: me.email, password: randomPassword()),
        throwsA(isA<ApiException>()),
      );
      await pumpEventQueue();
      expect(c.read(sessionControllerProvider).isGuest, isFalse);
    });

    beTest('signIn, then revalidate refreshes the name and keeps the session',
        () async {
      final c = await guestContainer();
      addTearDown(c.dispose);
      final session = c.read(sessionControllerProvider.notifier);
      await session.signIn(email: me.email, password: me.password);
      expect(c.read(sessionControllerProvider).userId, me.id);
      expect(c.read(sessionControllerProvider).displayName, me.name);

      final stale = await me.container(realDio: true, displayName: 'Tên cũ');
      addTearDown(stale.dispose);
      expect(stale.read(sessionControllerProvider).displayName, 'Tên cũ');
      await stale.read(sessionControllerProvider.notifier).revalidate();
      expect(stale.read(sessionControllerProvider).displayName, me.name);
      expect(stale.read(sessionControllerProvider).isGuest, isFalse);
    });
  });
}
