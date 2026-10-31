// test/hybrid/planner_test_support.dart
// The real Dio pipeline with a recorded BE behind it (no network): what the
// planner, pantry, recipe and scanner contract tests share. Fixtures are real
// response bodies, envelope included.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/network/dio_client.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';

const testUserId = '6ae5962396695f5c139fa9b0';

/// In the week of the recorded plan (Monday 2026-10-26).
final testNow = DateTime(2026, 10, 31, 9);

/// A recorded response body.
Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/hybrid/$name').readAsStringSync())
        as Map<String, dynamic>;

/// The `data` of a recorded response.
T fixtureData<T>(String name) => fixture(name)['data'] as T;

Map<String, dynamic> envelope(Object? data) =>
    {'success': true, 'message': null, 'data': data, 'statusCode': 200};

Map<String, dynamic> notFound(String message) =>
    {'success': false, 'message': message, 'statusCode': 404};

/// One answer: `(status, body)`, or a function of the request.
typedef Answer = (int, Object?) Function(RequestOptions request);

/// Answers by `METHOD /path`. A missing route fails the request and the test
/// can see it in [seen], so a call nobody expected never goes unnoticed.
class FakeBackend implements HttpClientAdapter {
  FakeBackend([Map<String, Answer>? routes]) : routes = routes ?? {};

  final Map<String, Answer> routes;
  final seen = <RequestOptions>[];

  void on(String route, int status, Object? body) =>
      routes[route] = (_) => (status, body);

  /// `METHOD /path` of everything requested, in order.
  List<String> get calls =>
      [for (final r in seen) '${r.method} ${r.path}'].toList();

  List<RequestOptions> requests(String route) => [
        for (final r in seen)
          if ('${r.method} ${r.path}' == route) r
      ];

  /// The JSON body of the only [route] request.
  Map<String, dynamic> bodyOf(String route) =>
      requests(route).single.data as Map<String, dynamic>;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    seen.add(options);
    final answer = routes['${options.method} ${options.path}'];
    if (answer == null) {
      throw DioException.connectionError(
          requestOptions: options, reason: 'no route in test');
    }
    final (status, body) = answer(options);
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A signed-in container on the real [dioProvider], [backend] as its transport.
Future<ProviderContainer> backendContainer(FakeBackend backend,
    {bool signedIn = true}) async {
  SharedPreferences.setMockInitialValues({
    if (signedIn) ...{
      SessionController.accessTokenKey: 'test-token',
      'vl.user_id': testUserId,
      'vl.display_name': 'FE Test',
      'vl.role': 'User',
    },
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    plannerClockProvider.overrideWithValue(() => testNow),
  ]);
  addTearDown(container.dispose);
  container.read(dioProvider).httpClientAdapter = backend;
  return container;
}
