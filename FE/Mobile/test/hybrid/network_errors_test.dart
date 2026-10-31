// test/hybrid/network_errors_test.dart
// Real BE error bodies (recorded samples) through the real Dio pipeline, the
// auth messages, session expiry and the start-up revalidation. No network.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/network/dio_client.dart';
import 'package:veganlife_mobile/core/session/auth_api_service.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/session/user_role.dart';

const _token = 'test-token';
const _userId = '6ae5962396695f5c139fa9b0';

/// Answers by path. A missing path is a connection failure.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.answers);

  final Map<String, (int, Object?)> answers;
  final seen = <RequestOptions>[];

  /// While set, every request waits on it (to overlap requests).
  Completer<void>? gate;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    seen.add(options);
    await gate?.future;
    final answer = answers[options.path];
    if (answer == null) {
      throw DioException.connectionError(
          requestOptions: options, reason: 'no route in test');
    }
    final (status, body) = answer;
    return ResponseBody.fromString(
      body == null ? '' : (body is String ? body : jsonEncode(body)),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A container on the real [dioProvider] with [adapter] as its transport.
Future<ProviderContainer> _container(
  _FakeAdapter adapter, {
  bool signedIn = true,
  String role = 'User',
  String? expiresAt,
}) async {
  SharedPreferences.setMockInitialValues({
    if (signedIn) ...{
      SessionController.accessTokenKey: _token,
      'vl.user_id': _userId,
      'vl.display_name': 'Tên Cũ',
      'vl.role': role,
    },
    if (expiresAt != null) SessionController.expiresAtKey: expiresAt,
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  container.read(dioProvider).httpClientAdapter = adapter;
  return container;
}

/// The [ApiException] of one failing GET.
Future<ApiException> _errorOf(Object? body, {int status = 400}) async {
  final container =
      await _container(_FakeAdapter({'/x': (status, body)}), signedIn: false);
  try {
    await container.read(dioProvider).get<Object?>('/x');
  } on DioException catch (e) {
    return mapDioException(e);
  }
  fail('expected the request to fail');
}

void main() {
  tearDown(() => BackendModules.debugOverride(null));

  group('error messages', () {
    test('ProblemDetails: the first message of each field, joined', () async {
      final error = await _errorOf({
        'type': 'https://tools.ietf.org/html/rfc9110#section-15.5.1',
        'title': 'One or more validation errors occurred.',
        'status': 400,
        'errors': {
          'Email': ['Email không đúng định dạng.', 'Thứ hai.'],
          'FullName': ['Họ tên là bắt buộc.'],
          'Password': ['Mật khẩu phải có ít nhất 8 ký tự.'],
        },
        'traceId': '00-1',
      });
      expect(
          error.message,
          'Email không đúng định dạng. Họ tên là bắt buộc. '
          'Mật khẩu phải có ít nhất 8 ký tự.');
      expect(error.statusCode, 400);
    });

    test('framework errors in English are skipped', () async {
      final error = await _errorOf({
        'title': 'One or more validation errors occurred.',
        'errors': {
          r'$.birthYear': ['The JSON value could not be converted to Int32.'],
          'Name': ['The Name field is required.', 'Tên là bắt buộc.'],
        },
      });
      expect(error.message, 'Tên là bắt buộc.');
    });

    test('ProblemDetails with no usable message: the generic Vietnamese one',
        () async {
      final error = await _errorOf({
        'title': 'One or more validation errors occurred.',
        'errors': {
          'request': ['The request field is required.'],
          r'$.allergies[0]': ['The JSON value could not be converted.'],
        },
      }, status: 422);
      expect(error.message, 'Dữ liệu gửi lên chưa hợp lệ.');
    });

    test('a title alone is never shown', () async {
      final error = await _errorOf(
          {'title': 'Not Found', 'status': 404, 'type': 'about:blank'},
          status: 404);
      expect(error.message, 'Không tìm thấy dữ liệu.');
    });

    test('envelope: its message, never the stack trace in detail', () async {
      final error = await _errorOf({
        'success': false,
        'message': 'Bạn đã báo cáo bài viết này rồi.',
        'statusCode': 409,
        'detail': 'DomainLayer.Exceptions.ConflictException: at …',
      }, status: 409);
      expect(error.message, 'Bạn đã báo cáo bài viết này rồi.');
      expect(error.statusCode, 409);
    });

    test('an empty 403 falls back by status', () async {
      final error = await _errorOf('', status: 403);
      expect(error.message, 'Bạn không có quyền thực hiện thao tác này.');
    });
  });

  group('AuthErrors.localize', () {
    ApiException localize(String message, int status, {String? code}) =>
        AuthErrors.localize(
            ApiException(message: message, statusCode: status, code: code));

    test('a code sent as message maps to Vietnamese and becomes the code', () {
      final invalid = localize('invalid_code', 400);
      expect(invalid.message, AuthErrors.invalidCode);
      expect(invalid.code, 'invalid_code');

      // The screen allows "Gửi lại mã" right away on this code.
      final expired = localize('code_expired', 400);
      expect(expired.message, AuthErrors.codeExpired);
      expect(expired.code, 'code_expired');
    });

    test('still maps by code', () {
      expect(localize('x', 400, code: 'code_expired').message,
          AuthErrors.codeExpired);
      expect(localize('x', 401, code: 'invalid_credentials').message,
          AuthErrors.invalidCredentials);
      expect(localize('x', 403, code: 'admin_web_only').message,
          AuthErrors.adminWebOnly);
    });

    test('with no code it still maps by status, whatever the message', () {
      expect(localize('Sai rồi', 401).message, AuthErrors.invalidCredentials);
      expect(localize('Sai rồi', 401).code, isNull);
      expect(localize('Sai rồi', 403).message, AuthErrors.adminWebOnly);
      expect(localize('Sai rồi', 423).message, AuthErrors.accountLocked);
      expect(localize('Sai rồi', 429).message, AuthErrors.tooManyAttempts);
      expect(localize('Sai rồi', 409).message, AuthErrors.emailTaken);
    });

    test('other errors stay as they are', () {
      const plain = ApiException(message: 'Email sai.', statusCode: 400);
      expect(AuthErrors.localize(plain), same(plain));
      const coded = ApiException(message: 'm', statusCode: 401, code: 'other');
      expect(AuthErrors.localize(coded), same(coded));
    });

    test('verify-reset-code through the real pipeline', () async {
      final container = await _container(
        _FakeAdapter({
          '/auth/verify-reset-code': (
            400,
            {
              'success': false,
              'message': 'invalid_code',
              'statusCode': 400,
              'detail': 'System.ArgumentException: invalid_code',
            }
          ),
        }),
        signedIn: false,
      );
      final api = RemoteAuthApiService(container.read(dioProvider));
      await expectLater(
        api.verifyResetCode(email: 'a@example.com', code: '000000'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', AuthErrors.invalidCode)
            .having((e) => e.code, 'code', 'invalid_code')),
      );
    });
  });

  group('401 handling', () {
    setUp(() => BackendModules.debugOverride({BackendModule.auth}));

    Future<void> failing(ProviderContainer c, String path) async {
      await expectLater(
          c.read(dioProvider).get<Object?>(path), throwsA(isA<DioException>()));
      await pumpEventQueue();
    }

    test('a 401 with a Bearer ends the session and clears the stored one',
        () async {
      final adapter = _FakeAdapter({'/meal-plans/current': (401, '')});
      final c = await _container(adapter);
      expect(c.read(sessionControllerProvider).isGuest, isFalse);

      await failing(c, '/meal-plans/current');

      expect(adapter.seen.single.headers['Authorization'], 'Bearer $_token');
      expect(c.read(sessionControllerProvider).isGuest, isTrue);
      final prefs = c.read(sharedPreferencesProvider);
      expect(prefs.getString(SessionController.accessTokenKey), isNull);
      expect(prefs.getString('vl.user_id'), isNull);
    });

    test('the mapped error still reaches the caller', () async {
      final c = await _container(_FakeAdapter({'/x': (401, '')}));
      try {
        await c.read(dioProvider).get<Object?>('/x');
        fail('expected a failure');
      } on DioException catch (e) {
        expect(mapDioException(e).isUnauthorized, isTrue);
        expect(mapDioException(e).message, AuthErrors.sessionExpired);
      }
    });

    test('several 401s at once expire once', () async {
      final adapter = _FakeAdapter({'/a': (401, ''), '/b': (401, '')})
        ..gate = Completer<void>();
      final c = await _container(adapter);
      final dio = c.read(dioProvider);
      final results = [
        dio
            .get<Object?>('/a')
            .then<Object?>((_) => null, onError: (Object e) => e),
        dio
            .get<Object?>('/b')
            .then<Object?>((_) => null, onError: (Object e) => e),
      ];
      var changes = 0;
      c.listen(sessionControllerProvider, (_, __) => changes++);
      adapter.gate!.complete();
      await Future.wait(results);
      await pumpEventQueue();
      expect(changes, 1);
      expect(c.read(sessionControllerProvider).isGuest, isTrue);
    });

    test('a 401 from an auth endpoint is a wrong password, not an expiry',
        () async {
      final c = await _container(_FakeAdapter({'/auth/login': (401, '')}));
      await expectLater(
          c.read(dioProvider).post<Object?>('/auth/login'), throwsA(anything));
      await pumpEventQueue();
      expect(c.read(sessionControllerProvider).isGuest, isFalse);
    });

    test('other statuses keep the session', () async {
      final c = await _container(_FakeAdapter({'/x': (403, '')}));
      await failing(c, '/x');
      expect(c.read(sessionControllerProvider).isGuest, isFalse);
    });

    test('a guest request is never treated as an expiry', () async {
      final adapter = _FakeAdapter({'/x': (401, '')});
      final c = await _container(adapter, signedIn: false);
      await failing(c, '/x');
      expect(adapter.seen.single.headers['Authorization'], isNull);
      expect(adapter.seen.single.headers['X-Guest-Token'], isNotNull);
    });

    test('the late 401 of an earlier session keeps the new one', () async {
      final c = await _container(_FakeAdapter(const {}));
      await c
          .read(sessionControllerProvider.notifier)
          .expire(token: 'an-older-token');
      expect(c.read(sessionControllerProvider).isGuest, isFalse);
    });
  });

  testWidgets('expire shows the snackbar on the root messenger',
      (tester) async {
    BackendModules.debugOverride({BackendModule.auth});
    SharedPreferences.setMockInitialValues({
      SessionController.accessTokenKey: _token,
      'vl.user_id': _userId,
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        home: const Scaffold(body: SizedBox()),
      ),
    ));

    await tester.runAsync(
        () => container.read(sessionControllerProvider.notifier).expire());
    await tester.pump();

    expect(find.text('Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.'),
        findsOneWidget);
    expect(container.read(sessionControllerProvider).isGuest, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  group('revalidate at start', () {
    setUp(() => BackendModules.debugOverride({BackendModule.auth}));

    Map<String, dynamic> me(
            {String fullName = 'Tên Mới', String role = 'Chef'}) =>
        {
          'success': true,
          'message': null,
          'data': {
            'stats': {'posts': 0, 'likesReceived': 0, 'saved': 0},
            'chefApplication': {'status': 'none', 'rejectReason': null},
            'id': _userId,
            'email': 'feit@example.com',
            'fullName': fullName,
            'phone': '',
            'role': role,
            'status': 0,
            'authType': 0,
            'createdAt': '2026-10-31T07:17:55.648Z',
          },
          'statusCode': 200,
        };

    test('a JWT past its time ends the session without a request', () async {
      final adapter = _FakeAdapter({'/users/me': (200, me())});
      final c = await _container(adapter,
          expiresAt: DateTime.now()
              .subtract(const Duration(minutes: 1))
              .toUtc()
              .toIso8601String());
      await c.read(sessionControllerProvider.notifier).revalidate();
      expect(c.read(sessionControllerProvider).isGuest, isTrue);
      expect(adapter.seen, isEmpty);
    });

    test('refreshes the name and role, and stores them', () async {
      final c = await _container(
        _FakeAdapter({'/users/me': (200, me())}),
        expiresAt: DateTime.now()
            .add(const Duration(minutes: 30))
            .toUtc()
            .toIso8601String(),
      );
      await c.read(sessionControllerProvider.notifier).revalidate();
      final session = c.read(sessionControllerProvider);
      expect(session.displayName, 'Tên Mới');
      expect(session.role, UserRole.chef);
      expect(session.accessToken, _token);
      expect(session.userId, _userId);
      final prefs = c.read(sharedPreferencesProvider);
      expect(prefs.getString('vl.display_name'), 'Tên Mới');
      expect(prefs.getString('vl.role'), 'Chef');
    });

    test('no change: the session object stays the same', () async {
      final c = await _container(_FakeAdapter(
          {'/users/me': (200, me(fullName: 'Tên Cũ', role: 'User'))}));
      final before = c.read(sessionControllerProvider);
      await c.read(sessionControllerProvider.notifier).revalidate();
      expect(c.read(sessionControllerProvider), same(before));
    });

    test('401 signs out through the interceptor', () async {
      final c = await _container(_FakeAdapter({'/users/me': (401, '')}));
      await c.read(sessionControllerProvider.notifier).revalidate();
      await pumpEventQueue();
      expect(c.read(sessionControllerProvider).isGuest, isTrue);
    });

    test('423 signs out', () async {
      final c = await _container(_FakeAdapter({
        '/users/me': (
          423,
          {'success': false, 'message': 'Khoá', 'statusCode': 423}
        ),
      }));
      await c.read(sessionControllerProvider.notifier).revalidate();
      expect(c.read(sessionControllerProvider).isGuest, isTrue);
    });

    test('network errors, 500s and odd bodies change nothing', () async {
      for (final answers in <Map<String, (int, Object?)>>[
        const {},
        const {'/users/me': (500, '')},
        const {'/users/me': (200, 'not json')},
        const {'/users/me': (200, '[1,2]')},
      ]) {
        final c = await _container(_FakeAdapter(answers));
        final before = c.read(sessionControllerProvider);
        await c.read(sessionControllerProvider.notifier).revalidate();
        expect(c.read(sessionControllerProvider), same(before));
      }
    });

    test('mock auth: never a request, even with an old expiry', () async {
      BackendModules.debugOverride(const {});
      final adapter = _FakeAdapter({'/users/me': (200, me())});
      final c = await _container(adapter, expiresAt: '2020-01-01T00:00:00Z');
      final before = c.read(sessionControllerProvider);
      await c.read(sessionControllerProvider.notifier).revalidate();
      expect(c.read(sessionControllerProvider), same(before));
      expect(adapter.seen, isEmpty);
    });

    test('a guest has nothing to revalidate', () async {
      final adapter = _FakeAdapter({'/users/me': (200, me())});
      final c = await _container(adapter, signedIn: false);
      await c.read(sessionControllerProvider.notifier).revalidate();
      expect(adapter.seen, isEmpty);
    });
  });
}
