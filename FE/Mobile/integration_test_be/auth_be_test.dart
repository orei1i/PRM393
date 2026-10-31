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

    beTest('forgot password, then a wrong code', () async {
      expect(await auth.requestPasswordReset(me.email), isNull);
      await expectApiError(
        auth.verifyResetCode(email: me.email, code: '000000'),
        status: 400,
        code: 'invalid_code',
        message: AuthErrors.invalidCode,
      );
    });

    beTest(
      'forgot password, right code, new password works',
      () async {},
      skip: 'B23: the code is only in the BE stdout, so this is the device QA '
          'step 4 of the plan.',
    );

    beTest('a bad token gets a 401 and ends the session', () async {
      final stale = await be.newUser(name: 'FE IT Stale');
      final c =
          await stale.container(realDio: true, tokenOverride: 'bad.token');
      addTearDown(c.dispose);
      expect(c.read(sessionControllerProvider).isGuest, isFalse);

      await expectLater(
        c.read(dioProvider).get<Object?>(ApiEndpoints.me),
        throwsA(isA<DioException>()
            .having((e) => mapDioException(e).statusCode, 'status', 401)),
      );
      await pumpEventQueue();

      final session = c.read(sessionControllerProvider);
      expect(session.isGuest, isTrue);
      expect(session.userId, isNull);
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
