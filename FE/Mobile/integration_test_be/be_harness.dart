// integration_test_be/be_harness.dart
//
// What the real-BE suite shares. It lives outside `test/`, so a plain
// `flutter test` never runs it:
//
//   flutter test integration_test_be --concurrency=1 \
//     --dart-define=USE_MOCK_DATA=false \
//     --dart-define=API_BASE_URL=http://localhost:5001/api/v1
//
// `--concurrency=1` because the files share one feed: posts created by another
// file while a feed is being paged would shift it.
//
// Rules for the test files:
// - Plain `test()`, never `testWidgets`: the widget binding installs an
//   HttpOverrides that answers 400 to all HTTP.
// - Accounts are throwaway ones from [BeHarness.newUser]; their password and
//   token are never printed.
// - Never print or `expect` on a whole raw body from a failed request: the BE's
//   developer exception page echoes the request headers, bearer included.
//
// `setMockInitialValues` is for tests, and this helper counts as one:
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/config/env.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/network/dio_client.dart';
import 'package:veganlife_mobile/core/network/interceptors.dart';
import 'package:veganlife_mobile/core/session/auth_api_service.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';

/// Tag of the tests in `be_bug_pins_test.dart`.
const beBugPinTag = 'be-bug-pin';

const _testTimeout = Timeout(Duration(minutes: 2));
const _probeTimeout = Duration(seconds: 2);

/// A `test()` with room for slow BE calls (plan generation).
void beTest(String description, Future<void> Function() body, {Object? skip}) =>
    test(description, body, timeout: _testTimeout, skip: skip);

/// Whether the BE can be reached, and the throwaway accounts.
class BeHarness {
  BeHarness._(this.skipReason);

  /// Why the suite can't run (for `group(skip:)`), or null when it can.
  final String? skipReason;

  static Future<BeHarness> start() async =>
      BeHarness._(await _whyNotRunnable());

  static Future<String?> _whyNotRunnable() async {
    const hint =
        'Start the BE, then from integration_test_be run: flutter test '
        '. --concurrency=1 --dart-define=USE_MOCK_DATA=false '
        '--dart-define=API_BASE_URL=http://localhost:5001/api/v1';
    if (Env.useMockData) return 'USE_MOCK_DATA is not false. $hint';
    final client = HttpClient()..connectionTimeout = _probeTimeout;
    try {
      final request = await client
          .getUrl(Uri.parse('${Env.apiBaseUrl}/catalog/allergens'))
          .timeout(_probeTimeout);
      final response = await request.close().timeout(_probeTimeout);
      await response.drain<void>();
      return response.statusCode == 200
          ? null
          : 'BE down at ${Env.apiBaseUrl} '
              '(HTTP ${response.statusCode}). $hint';
    } on Exception {
      return 'BE down at ${Env.apiBaseUrl}. $hint';
    } finally {
      client.close(force: true);
    }
  }

  /// A new account on the BE, signed in.
  Future<BeUser> newUser({String name = 'FE IT'}) async {
    final email = randomEmail();
    final password = randomPassword();
    final auth = RemoteAuthApiService(guestDio());
    final result = await auth.register(RegisterRequest(
      fullName: name,
      email: email,
      password: password,
    ));
    return BeUser._(
      id: result.userId!,
      name: result.displayName,
      email: email,
      password: password,
      token: result.accessToken,
    );
  }

  /// The same pipeline as `dioProvider` for someone who isn't signed in.
  Dio guestDio() => _pipeline(() => {'X-Guest-Token': 'guest_feit'});
}

String randomHex(int length) {
  final random = Random.secure();
  return List.generate(length, (_) => random.nextInt(16).toRadixString(16))
      .join();
}

String randomEmail() => 'feit.${randomHex(16)}@example.com';

String randomPassword() => 'Fe${randomHex(16)}9!';

/// `dioProvider` without the session (no expiry on a 401) and the debug log.
Dio _pipeline(AuthHeadersReader headers) {
  final dio = Dio(BaseOptions(
    baseUrl: Env.apiBaseUrl,
    connectTimeout: Env.connectTimeout,
    receiveTimeout: Env.receiveTimeout,
    headers: const {'Accept': 'application/json', 'Accept-Language': 'vi-VN'},
  ));
  dio.interceptors.addAll([
    CorrelationIdInterceptor(),
    EnvelopeInterceptor(),
    AuthInterceptor(headers),
    ErrorMappingInterceptor(),
  ]);
  return dio;
}

/// A throwaway account with its Dio.
class BeUser {
  BeUser._({
    required this.id,
    required this.name,
    required this.email,
    required this.password,
    required this.token,
  }) {
    dio = _pipeline(() => {'Authorization': 'Bearer $token'});
  }

  final String id;
  final String name;
  final String email;
  final String password;
  final String token;

  late final Dio dio;

  /// A plain request that only reads the status and the envelope, for what the
  /// services hide on purpose.
  Future<RawResponse> raw(String method, String path,
          {Object? data, Map<String, dynamic>? query}) =>
      rawRequest(method, path, token: token, data: data, query: query);

  /// A container signed in as this account. By default its Remote services use
  /// [dio]; [realDio] keeps the real `dioProvider`, reading the session.
  Future<ProviderContainer> container({
    bool realDio = false,
    String? tokenOverride,
    String? displayName,
  }) async {
    SharedPreferences.setMockInitialValues({
      SessionController.accessTokenKey: tokenOverride ?? token,
      'vl.user_id': id,
      'vl.display_name': displayName ?? name,
      'vl.role': 'User',
    });
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      if (!realDio) dioProvider.overrideWithValue(dio),
    ]);
  }
}

/// A container with nobody signed in, on the real `dioProvider`.
Future<ProviderContainer> guestContainer() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
}

class RawResponse {
  const RawResponse(this.status, this.body);

  final int status;

  /// The JSON body, or the text of a non-JSON one.
  final Object? body;

  Map<String, dynamic> get json =>
      body is Map<String, dynamic> ? body! as Map<String, dynamic> : const {};

  /// The envelope's `data`.
  Object? get data => json['data'];

  Map<String, dynamic> get dataMap =>
      data is Map<String, dynamic> ? data! as Map<String, dynamic> : const {};

  List<Map<String, dynamic>> get dataList => data is List<Object?>
      ? (data! as List<Object?>).whereType<Map<String, dynamic>>().toList()
      : const [];
}

/// [path] is relative to `API_BASE_URL`, or absolute.
Future<RawResponse> rawRequest(
  String method,
  String path, {
  String? token,
  Object? data,
  Map<String, dynamic>? query,
}) async {
  final dio = Dio(BaseOptions(
    baseUrl: Env.apiBaseUrl,
    connectTimeout: Env.connectTimeout,
    receiveTimeout: const Duration(seconds: 60),
    validateStatus: (_) => true,
    headers: {
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    },
  ));
  try {
    final res = await dio.request<Object?>(path,
        data: data, queryParameters: query, options: Options(method: method));
    return RawResponse(res.statusCode ?? 0, res.data);
  } finally {
    dio.close();
  }
}

/// A multipart body with one file in [field].
FormData oneFile(String field, String filename, Uint8List bytes) =>
    FormData.fromMap(
        {field: MultipartFile.fromBytes(bytes, filename: filename)});

/// A 1×1 PNG.
Uint8List pngBytes() => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

/// A file the BE takes for an mp4 (an `ftyp` box and padding).
Uint8List mp4Bytes() => Uint8List.fromList([
      0, 0, 0, 24, //
      ...ascii.encode('ftypisom'),
      0, 0, 2, 0, //
      ...ascii.encode('isommp42'),
      ...List.filled(2048, 0),
    ]);

/// Writes [bytes] to a temporary file, removed with the test.
Future<String> tempFile(String name, List<int> bytes) async {
  final dir = await Directory.systemTemp.createTemp('veganlife_feit_');
  addTearDown(() => dir.delete(recursive: true));
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes);
  return file.path;
}

/// A message a member can read: Vietnamese, not the framework's English.
final isVietnamese = predicate<String>(
    (s) => RegExp(r'[^\x00-\x7F]').hasMatch(s) && !s.startsWith('The '),
    'a Vietnamese message');

/// The call fails with this [ApiException]; its message is Vietnamese unless
/// [message] says exactly what it must be.
Future<void> expectApiError(
  Future<Object?> call, {
  int? status,
  String? code,
  String? message,
}) =>
    expectLater(
      call,
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', status ?? anything)
          .having((e) => e.code, 'code', code ?? anything)
          .having((e) => e.message, 'message', message ?? isVietnamese)),
    );
