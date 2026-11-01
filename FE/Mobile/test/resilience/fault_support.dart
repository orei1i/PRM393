// test/resilience/fault_support.dart
// Bad server responses for the real modules, through the real Dio pipeline: a
// recorded healthy body per route, then one fault applied to every response.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// What the server does wrong.
enum Fault {
  missingFields,
  nullsEverywhere,
  numbersAsStrings,
  textAsNumbers,
  objectWhereList,
  listWhereObject,
  zeroes,
  dataNull,
  emptyBody,
  htmlBody,
  htmlAsJson,
  truncatedJson,
  envelopeFailure,
  garbledMessage,
  http400,
  http401,
  http403,
  http404,
  http409,
  http429,
  http500,
  http502,
  timeout,
  connectionError,
  droppedMidResponse,
}

/// Answers every request with the healthy body of its route, damaged by [fault].
class FaultBackend implements HttpClientAdapter {
  FaultBackend(this.fault, {this.only, this.damage});

  final Fault? fault;

  /// When set, only matching `METHOD /path` requests are faulted.
  final bool Function(String route)? only;

  /// A targeted change to the healthy body of a route.
  final Object? Function(String route, Object? body)? damage;
  final calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    await requestStream?.drain<void>();
    final route = '${options.method} ${options.path}';
    calls.add(route);
    final healthy = healthyBody(route);
    final body = damage?.call(route, healthy) ?? healthy;
    final fault = this.fault;
    if (fault == null || !(only?.call(route) ?? true)) return _json(200, body);
    return switch (fault) {
      Fault.missingFields => _json(200, _onData(body, _noFields)),
      Fault.nullsEverywhere => _json(200, _onData(body, _nulls)),
      Fault.numbersAsStrings => _json(200, _onData(body, _numbersAsStrings)),
      Fault.textAsNumbers => _json(200, _onData(body, _textAsNumbers)),
      Fault.objectWhereList => _json(200, _onData(body, _objectForList)),
      Fault.listWhereObject => _json(200, _onData(body, _listForObject)),
      Fault.zeroes => _json(200, _onData(body, _zeroes)),
      Fault.dataNull => _json(200, _envelope(null)),
      Fault.emptyBody => _text(200, '', Headers.jsonContentType),
      Fault.htmlBody => _text(200, _html, 'text/html; charset=utf-8'),
      Fault.htmlAsJson => _text(200, _html, Headers.jsonContentType),
      Fault.truncatedJson => _text(
          200, '{"success":true,"data":{"id":"1","na', Headers.jsonContentType),
      Fault.envelopeFailure => _json(200, _failure(200, _message)),
      Fault.garbledMessage => _json(400, _failure(400, _garbled)),
      Fault.http400 => _json(400, _failure(400, _message)),
      Fault.http401 => _json(401, _failure(401, _message)),
      Fault.http403 => _json(403, _failure(403, _message)),
      Fault.http404 => _json(404, _failure(404, _message)),
      Fault.http409 => _json(409, _failure(409, _message)),
      Fault.http429 => _json(429, _failure(429, _message)),
      Fault.http500 => _text(500, 'Internal Server Error', 'text/plain'),
      Fault.http502 => _text(502, _html, 'text/html'),
      Fault.timeout => throw DioException.receiveTimeout(
          timeout: const Duration(seconds: 30), requestOptions: options),
      Fault.connectionError => throw DioException.connectionError(
          requestOptions: options, reason: 'Connection refused'),
      Fault.droppedMidResponse => ResponseBody(
          Stream.fromIterable([utf8.encode('{"success":true,"data":{"id"')])
              .map(Uint8List.fromList)
              .followedByError(
                  const SocketException('Connection reset by peer')),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
    };
  }

  @override
  void close({bool force = false}) {}
}

extension on Stream<Uint8List> {
  Stream<Uint8List> followedByError(Object error) async* {
    yield* this;
    throw error;
  }
}

const _message = 'Không xử lý được yêu cầu.';
const _garbled = 'KhÃ´ng tÃ¬m tháº¥y dá»¯ liá»‡u';
const _html =
    '<!DOCTYPE html><html><body><h1>502 Bad Gateway</h1></body></html>';

Map<String, dynamic> _envelope(Object? data) =>
    {'success': true, 'message': null, 'data': data, 'statusCode': 200};

Map<String, dynamic> _failure(int status, String message) =>
    {'success': false, 'message': message, 'data': null, 'statusCode': status};

ResponseBody _json(int status, Object? body) =>
    _text(status, jsonEncode(body), Headers.jsonContentType);

ResponseBody _text(int status, String body, String type) =>
    ResponseBody.fromString(body, status, headers: {
      Headers.contentTypeHeader: [type],
    });

/// Damages `data`, leaving the envelope as it is.
Object? _onData(Object? body, Object? Function(Object?) change) {
  if (body is Map<String, dynamic> && body.containsKey('success')) {
    return {...body, 'data': change(body['data'])};
  }
  return change(body);
}

/// `{}`, and a list of `{}`.
Object? _noFields(Object? v) => switch (v) {
      final Map<String, dynamic> _ => <String, dynamic>{},
      final List<Object?> l => [for (final _ in l) <String, dynamic>{}],
      _ => null,
    };

Object? _nulls(Object? v) => switch (v) {
      final Map<String, dynamic> m => {for (final k in m.keys) k: null},
      final List<Object?> l => [for (final e in l) _nulls(e)],
      _ => null,
    };

Object? _walk(Object? v, Object? Function(Object?) leaf,
        {Object? Function(Map<String, dynamic>)? map,
        Object? Function(List<Object?>)? list}) =>
    switch (v) {
      final Map<String, dynamic> m => map != null && m.isNotEmpty
          ? map(m)
          : {
              for (final e in m.entries)
                e.key: _walk(e.value, leaf, map: map, list: list)
            },
      final List<Object?> l => list != null
          ? list(l)
          : [for (final e in l) _walk(e, leaf, map: map, list: list)],
      _ => leaf(v),
    };

Object? _numbersAsStrings(Object? v) =>
    _walk(v, (x) => x is num ? 'mười hai' : x);

Object? _textAsNumbers(Object? v) => _walk(v, (x) => x is String ? 12345 : x);

Object? _zeroes(Object? v) => _walk(v, (x) => x is num ? 0 : x);

/// Inside the top-level object: every list becomes an object.
Object? _objectForList(Object? v) => v is List<Object?>
    ? {'items': v.length}
    : _walk(v, (x) => x, list: (l) => {'items': l.length});

/// Inside the top-level list or object: every nested object becomes a list.
Object? _listForObject(Object? v) => switch (v) {
      final Map<String, dynamic> m => {
          for (final e in m.entries)
            e.key: e.value is Map ? [1, 2] : _listForObject(e.value)
        },
      final List<Object?> l => [for (final _ in l) 1],
      _ => v,
    };

// ------------------------------------------------------------ healthy bodies

Object? _fixture(String name) =>
    jsonDecode(File('test/hybrid/$name').readAsStringSync());

Map<String, dynamic> _ok(Object? data) => _envelope(data);

final _recipeRow = {
  'id': '6ae595c796695f5c139fa99b',
  'name': 'Cơm gạo lứt đậu hũ kho nấm đông cô',
  'imageUrl': null,
  'calories': 520,
  'proteinG': 26,
  'carbsG': 75,
  'fatG': 14,
  'fiberG': 10,
  'allergens': ['soy'],
  'dietTags': ['balanced'],
  'prepMinutes': 25,
  'ingredients': ['Gạo lứt', 'Đậu hũ'],
  'instructions': ['Sơ chế nguyên liệu.', 'Thưởng thức khi còn ấm.'],
  'seasonalSwap': null,
};

/// The recorded (or, without a recording, hand-copied) healthy body of a route.
Object? healthyBody(String route) {
  final path = route.split(' ').last;
  final get = route.startsWith('GET');
  final me = path == '/users/me';
  if (me) return _fixture('profile_fixture_me.json');
  if (path.startsWith('/auth/')) {
    return _ok({
      'accessToken': 'new-token',
      'refreshToken': 'new-refresh',
      'expiresAt': '2030-01-01T00:00:00Z',
      'user': {
        'id': '6ae5962396695f5c139fa9b0',
        'fullName': 'FE Test',
        'email': 'a@example.com',
        'role': 'User',
      },
    });
  }
  if (path == '/health-profile/me/metrics') {
    return get
        ? _fixture('planner_fixture_metrics.json')
        : _ok({
            'id': 'm1',
            'weightKg': 66,
            'heightCm': 172,
            'bmi': 22.3,
            'loggedAt': '2026-10-31T07:19:11.062Z',
          });
  }
  if (path == '/health-profile/me') {
    return _fixture('planner_fixture_profile.json');
  }
  if (path == '/catalog/allergens') {
    return _fixture('planner_fixture_allergens.json');
  }
  if (path == '/meal-plans/current/meals') {
    return _fixture('planner_fixture_add_meal.json');
  }
  if (path.endsWith('/swap-suggestions') ||
      path == '/meal-plans/from-ingredients') {
    return _fixture('recipe_fixture_swap.json');
  }
  if (path.startsWith('/meal-plans') && path.endsWith('/meals')) {
    return _fixture('planner_fixture_patch.json');
  }
  if (path.startsWith('/meal-plans') || path == '/meal-plans') {
    return _fixture('planner_fixture_plan.json');
  }
  if (path.startsWith('/recipes/')) return _ok(_recipeRow);
  if (path == '/recipes' || path == '/users/me/recipes') {
    return _ok(get ? [_recipeRow] : _recipeRow);
  }
  if (path == '/users/me/ingredients') {
    return get
        ? _fixture('pantry_fixture_list.json')
        : _fixture('pantry_fixture_add.json');
  }
  if (path.startsWith('/users/me/ingredients/')) {
    return _fixture('pantry_fixture_put.json');
  }
  if (path.startsWith('/ingredients/')) {
    return _fixture('pantry_fixture_ingredient.json');
  }
  if (path == '/ingredients') {
    return _ok([(_fixture('pantry_fixture_ingredient.json')! as Map)['data']]);
  }
  if (path == '/posts') {
    return get
        ? _fixture('community_fixture_feed_page1.json')
        : _fixture('community_fixture_post_discussion.json');
  }
  if (path.endsWith('/replies') || path.endsWith('/comments')) {
    return get
        ? _fixture('community_fixture_comments_page1.json')
        : _fixture('community_fixture_comment_reply.json');
  }
  if (path.endsWith('/like')) return _fixture('community_fixture_like_on.json');
  if (path.endsWith('/reports')) {
    return _fixture('community_fixture_report_ok.json');
  }
  if (path.startsWith('/posts/')) {
    return _fixture('community_fixture_post_get.json');
  }
  if (path == '/media/images') {
    return _fixture('community_fixture_media_image.json');
  }
  if (path == '/media/videos') {
    return _fixture('community_fixture_media_video.json');
  }
  if (path == '/vision/scan') return _fixture('scanner_fixture_scan.json');
  return _ok(null);
}
