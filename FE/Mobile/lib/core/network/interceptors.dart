// lib/core/network/interceptors.dart
import 'package:dio/dio.dart';

import 'api_exception.dart';

typedef AuthHeadersReader = Map<String, String> Function();

/// Adds `Authorization: Bearer …` for members or `X-Guest-Token` for guests.
/// The reader is evaluated per request, so sign-in/out applies immediately.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._readHeaders);

  final AuthHeadersReader _readHeaders;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers.addAll(_readHeaders());
    handler.next(options);
  }
}

/// Attaches a typed [ApiException] to every DioException (`err.error`).
class ErrorMappingInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.next(err.copyWith(error: mapDioException(err)));
  }
}

/// Adds a correlation id so a failed request can be found in the admin `ai_logs`.
class CorrelationIdInterceptor extends Interceptor {
  int _counter = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _counter++;
    final id = '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-$_counter';
    options.headers['X-Correlation-Id'] = id;
    handler.next(options);
  }
}
