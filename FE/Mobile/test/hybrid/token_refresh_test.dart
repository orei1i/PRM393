// test/hybrid/token_refresh_test.dart
// A refused JWT through the real Dio pipeline: one refresh for everybody, the
// request sent again once, and when the session really ends. No network.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/network/dio_client.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';

const _oldAccess = 'access-old';
const _oldRefresh = 'refresh-old';
const _newAccess = 'access-new';
const _newRefresh = 'refresh-new';

Map<String, dynamic> _envelope(Object? data) =>
    {'success': true, 'message': null, 'data': data, 'statusCode': 200};

Map<String, dynamic> get _tokens => _envelope({
      'accessToken': _newAccess,
      'refreshToken': _newRefresh,
      'expiresAt': '2030-01-01T00:00:00Z',
      'user': {'id': 'u1', 'fullName': 'Tên Trên Máy Chủ', 'role': 'User'},
    });

/// A BE that takes only the tokens it should: [refreshAnswer] for a refresh,
/// a 401 for a Bearer other than [validBearer], a 200 otherwise.
class _Backend implements HttpClientAdapter {
  _Backend({this.validBearer = _newAccess, this.refreshAnswer});

  String validBearer;

  /// `(status, body)`; `null` drops the connection.
  (int, Object?)? refreshAnswer;

  final seen = <RequestOptions>[];
  int get refreshes => seen.where((r) => r.path == '/auth/refresh').length;
  Iterable<RequestOptions> requestsTo(String path) =>
      seen.where((r) => r.path == path);

  /// While set, a refresh waits on it.
  Completer<void>? refreshGate;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    seen.add(options);
    if (options.path == '/auth/refresh') {
      await refreshGate?.future;
      final answer = refreshAnswer;
      if (answer == null) {
        throw DioException.connectionError(
            requestOptions: options, reason: 'offline');
      }
      return _body(answer.$1, answer.$2);
    }
    if (options.path == '/auth/logout') return _body(204, null);
    await requestStream?.drain<void>();
    final bearer = options.headers['Authorization'];
    return bearer == 'Bearer $validBearer'
        ? _body(200, _envelope({'ok': true}))
        : _body(401, null);
  }

  static ResponseBody _body(int status, Object? body) =>
      ResponseBody.fromString(
        body == null ? '' : jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

Future<ProviderContainer> _signedIn(_Backend backend,
    {bool withRefreshToken = true, String? expiresAt}) async {
  SharedPreferences.setMockInitialValues({
    SessionController.accessTokenKey: _oldAccess,
    if (withRefreshToken) SessionController.refreshTokenKey: _oldRefresh,
    if (expiresAt != null) SessionController.expiresAtKey: expiresAt,
    'vl.user_id': 'u1',
    'vl.display_name': 'FE Test',
    'vl.role': 'User',
  });
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
  addTearDown(c.dispose);
  c.read(dioProvider).httpClientAdapter = backend;
  return c;
}

void main() {
  // SessionController.expire looks at the app's navigator and messenger.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => BackendModules.debugOverride(BackendModules.supportedByBackend));
  tearDown(() => BackendModules.debugOverride(null));

  group('a refused JWT', () {
    test('a token refused right after a refresh does not refresh again',
        () async {
      // Refresh works, but no Bearer is ever accepted.
      final backend =
          _Backend(validBearer: 'never', refreshAnswer: (200, _tokens));
      final c = await _signedIn(backend);
      final dio = c.read(dioProvider);

      await expectLater(dio.get<dynamic>('/a'), throwsA(isA<DioException>()));
      expect(backend.refreshes, 1);
      expect(c.read(sessionControllerProvider).accessToken, _newAccess);

      for (var i = 0; i < 3; i++) {
        await expectLater(dio.get<dynamic>('/a'), throwsA(isA<DioException>()));
      }
      expect(backend.refreshes, 1, reason: 'no refresh loop');
      expect(c.read(sessionControllerProvider).accessToken, _newAccess,
          reason: 'still signed in, the request just fails');
    });

    test('is refreshed, and the request goes through with the new one',
        () async {
      final backend = _Backend(refreshAnswer: (200, _tokens));
      final c = await _signedIn(backend);

      final res = await c.read(dioProvider).get<Object?>('/x');

      expect((res.data! as Map)['ok'], isTrue);
      expect(backend.refreshes, 1);
      expect(backend.requestsTo('/auth/refresh').single.data,
          {'refreshToken': _oldRefresh});
      expect(backend.requestsTo('/x').map((r) => r.headers['Authorization']),
          ['Bearer $_oldAccess', 'Bearer $_newAccess']);
    });

    test('the rotated tokens are saved, the session stays the same', () async {
      final c = await _signedIn(_Backend(refreshAnswer: (200, _tokens)));
      await c.read(dioProvider).get<Object?>('/x');

      final prefs = c.read(sharedPreferencesProvider);
      expect(prefs.getString(SessionController.accessTokenKey), _newAccess);
      expect(prefs.getString(SessionController.refreshTokenKey), _newRefresh);
      expect(prefs.getString(SessionController.expiresAtKey),
          startsWith('2030-01-01'));
      final session = c.read(sessionControllerProvider);
      expect(session.accessToken, _newAccess);
      expect(session.userId, 'u1');
      expect(session.displayName, 'FE Test');
    });

    test('several requests share one refresh, and each goes through', () async {
      final backend = _Backend(refreshAnswer: (200, _tokens))
        ..refreshGate = Completer<void>();
      final c = await _signedIn(backend);
      final dio = c.read(dioProvider);

      final requests = [
        dio.get<Object?>('/a'),
        dio.get<Object?>('/b'),
        dio.post<Object?>('/c'),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(backend.refreshes, 1);
      backend.refreshGate!.complete();

      final results = await Future.wait(requests);
      expect(results.map((r) => r.statusCode), [200, 200, 200]);
      expect(backend.refreshes, 1);
    });

    test('a late 401 for a token already replaced only goes again', () async {
      final backend = _Backend(refreshAnswer: (200, _tokens));
      final c = await _signedIn(backend);
      final dio = c.read(dioProvider);
      await dio.get<Object?>('/a');
      expect(backend.refreshes, 1);

      final res = await dio.get<Object?>('/b',
          options: Options(headers: {'Authorization': 'Bearer $_oldAccess'}));
      expect(res.statusCode, 200);
      expect(backend.refreshes, 1);
    });

    test('retried only once: a second 401 is an error, with no second refresh',
        () async {
      final backend = _Backend(
          validBearer: 'nothing-is-valid', refreshAnswer: (200, _tokens));
      final c = await _signedIn(backend);

      await expectLater(
          c.read(dioProvider).get<Object?>('/x'), throwsA(isA<DioException>()));

      expect(backend.requestsTo('/x'), hasLength(2));
      expect(backend.refreshes, 1);
      expect(c.read(sessionControllerProvider).isGuest, isFalse);
    });

    test('an upload is sent again in full', () async {
      final backend = _Backend(refreshAnswer: (200, _tokens));
      final c = await _signedIn(backend);
      final res = await c.read(dioProvider).post<Object?>(
            '/media/images',
            data: FormData.fromMap({
              'file': MultipartFile.fromBytes([1, 2, 3], filename: 'a.png'),
            }),
          );
      expect(res.statusCode, 200);
      expect(backend.requestsTo('/media/images'), hasLength(2));
    });
  });

  group('the refresh itself', () {
    test('a dead refresh token ends the session, and the error gets through',
        () async {
      final backend = _Backend(refreshAnswer: (
        401,
        {
          'success': false,
          'message': 'Refresh token không hợp lệ hoặc đã bị thu hồi.',
          'statusCode': 401,
        }
      ));
      final c = await _signedIn(backend);

      await expectLater(
        c.read(dioProvider).get<Object?>('/x'),
        throwsA(isA<DioException>()
            .having((e) => mapDioException(e).statusCode, 'status', 401)),
      );

      expect(c.read(sessionControllerProvider).isGuest, isTrue);
      expect(backend.requestsTo('/x'), hasLength(1));
      final prefs = c.read(sharedPreferencesProvider);
      expect(prefs.getString(SessionController.accessTokenKey), isNull);
      expect(prefs.getString(SessionController.refreshTokenKey), isNull);
      expect(backend.requestsTo('/auth/logout'), isEmpty,
          reason: 'the server ended it: nothing to revoke');
    });

    test('offline: the session stays and the tokens are kept', () async {
      final backend = _Backend();
      final c = await _signedIn(backend);

      await expectLater(
          c.read(dioProvider).get<Object?>('/x'), throwsA(isA<DioException>()));

      expect(c.read(sessionControllerProvider).isGuest, isFalse);
      expect(c.read(sessionControllerProvider).accessToken, _oldAccess);
      expect(
          c
              .read(sharedPreferencesProvider)
              .getString(SessionController.refreshTokenKey),
          _oldRefresh);
    });

    test('a server error: the same', () async {
      final backend = _Backend(refreshAnswer: (500, {'statusCode': 500}));
      final c = await _signedIn(backend);
      await expectLater(
          c.read(dioProvider).get<Object?>('/x'), throwsA(isA<DioException>()));
      expect(c.read(sessionControllerProvider).isGuest, isFalse);
    });

    test('after a failure the next 401 tries again', () async {
      final backend = _Backend();
      final c = await _signedIn(backend);
      final dio = c.read(dioProvider);
      await expectLater(dio.get<Object?>('/x'), throwsA(isA<DioException>()));

      backend.refreshAnswer = (200, _tokens);
      expect((await dio.get<Object?>('/x')).statusCode, 200);
      expect(backend.refreshes, 2);
    });

    test('a session without a refresh token ends at once', () async {
      final backend = _Backend();
      final c = await _signedIn(backend, withRefreshToken: false);
      await expectLater(
          c.read(dioProvider).get<Object?>('/x'), throwsA(isA<DioException>()));
      expect(c.read(sessionControllerProvider).isGuest, isTrue);
      expect(backend.refreshes, 0);
    });

    test('an answer after signing out starts nothing', () async {
      final backend = _Backend(refreshAnswer: (200, _tokens))
        ..refreshGate = Completer<void>();
      final c = await _signedIn(backend);
      final request = c
          .read(dioProvider)
          .get<Object?>('/x')
          .then<Object?>((r) => r, onError: (Object e) => e);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await c.read(sessionControllerProvider.notifier).signOut();
      backend.refreshGate!.complete();
      await request;

      expect(c.read(sessionControllerProvider).isGuest, isTrue);
      expect(
          c
              .read(sharedPreferencesProvider)
              .getString(SessionController.accessTokenKey),
          isNull);
    });

    test('never for an auth endpoint', () async {
      final backend = _Backend(refreshAnswer: (200, _tokens));
      final c = await _signedIn(backend);
      await expectLater(
        c.read(dioProvider).post<Object?>('/auth/login'),
        throwsA(isA<DioException>()),
      );
      expect(backend.refreshes, 0);
      expect(c.read(sessionControllerProvider).isGuest, isFalse);
    });

    test('never for a guest', () async {
      final backend = _Backend(refreshAnswer: (200, _tokens));
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);
      c.read(dioProvider).httpClientAdapter = backend;

      await expectLater(
          c.read(dioProvider).get<Object?>('/x'), throwsA(isA<DioException>()));
      expect(backend.refreshes, 0);
    });

    test('the 401 of an earlier session changes nothing', () async {
      final c = await _signedIn(_Backend());
      expect(
          await c
              .read(sessionControllerProvider.notifier)
              .refreshAfterRefusal('an-older-token'),
          isFalse);
      expect(c.read(sessionControllerProvider).isGuest, isFalse);
    });
  });

  group('signing out', () {
    test('revokes in the background, with the session\'s own Bearer', () async {
      final backend = _Backend();
      final c = await _signedIn(backend);
      await c.read(sessionControllerProvider.notifier).signOut();
      await pumpEventQueue();

      expect(c.read(sessionControllerProvider).isGuest, isTrue);
      expect(backend.requestsTo('/auth/logout').single.headers['Authorization'],
          'Bearer $_oldAccess');
    });

    test('still works with the BE unreachable', () async {
      final c = await _signedIn(_Backend());
      c.read(dioProvider).httpClientAdapter = _Unreachable();
      await c.read(sessionControllerProvider.notifier).signOut();
      await pumpEventQueue();
      expect(c.read(sessionControllerProvider).isGuest, isTrue);
      expect(
          c
              .read(sharedPreferencesProvider)
              .getString(SessionController.refreshTokenKey),
          isNull);
    });

    test('does not wait for the server', () async {
      final c = await _signedIn(_Backend());
      c.read(dioProvider).httpClientAdapter = _Hanging();
      await c.read(sessionControllerProvider.notifier).signOut();
      expect(c.read(sessionControllerProvider).isGuest, isTrue);
    });

    test('mock auth: no request', () async {
      BackendModules.debugOverride(const {});
      final backend = _Backend();
      final c = await _signedIn(backend);
      await c.read(sessionControllerProvider.notifier).signOut();
      await pumpEventQueue();
      expect(backend.seen, isEmpty);
    });
  });

  group('at app start', () {
    final past =
        DateTime.now().subtract(const Duration(hours: 1)).toIso8601String();

    test('a JWT past its time is refreshed instead of ending the session',
        () async {
      final backend = _Backend(refreshAnswer: (200, _tokens));
      final c = await _signedIn(backend, expiresAt: past);
      await c.read(sessionControllerProvider.notifier).revalidate();
      expect(c.read(sessionControllerProvider).accessToken, _newAccess);
      expect(backend.refreshes, 1);
    });

    test('offline it stays signed in', () async {
      final backend = _Backend();
      final c = await _signedIn(backend, expiresAt: past);
      await c.read(sessionControllerProvider.notifier).revalidate();
      expect(c.read(sessionControllerProvider).isGuest, isFalse);
    });

    test('without a refresh token (an older session) it ends', () async {
      final backend = _Backend();
      final c =
          await _signedIn(backend, withRefreshToken: false, expiresAt: past);
      await c.read(sessionControllerProvider.notifier).revalidate();
      expect(c.read(sessionControllerProvider).isGuest, isTrue);
      expect(backend.seen, isEmpty);
    });
  });
}

class _Unreachable implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) =>
      Future.error(DioException.connectionError(
          requestOptions: options, reason: 'offline'));

  @override
  void close({bool force = false}) {}
}

/// Never answers.
class _Hanging implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) =>
      Completer<ResponseBody>().future;

  @override
  void close({bool force = false}) {}
}
