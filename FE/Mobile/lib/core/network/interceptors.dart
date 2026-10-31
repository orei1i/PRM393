// lib/core/network/interceptors.dart
import 'package:dio/dio.dart';

import 'api_envelope.dart';
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

/// Reports a 401 on a request that carried a Bearer (the JWT expired or was
/// revoked; the BE has no refresh). Auth endpoints are skipped: a 401 there is
/// a wrong password. A guest request is never reported.
class UnauthorizedInterceptor extends Interceptor {
  UnauthorizedInterceptor(this._onUnauthorized);

  /// Gets the token that was refused, so a late answer to a request of an
  /// earlier session cannot end the current one.
  final void Function(String token) _onUnauthorized;

  static const _bearerPrefix = 'Bearer ';

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final options = err.requestOptions;
    final mapped = err.error;
    final status = err.response?.statusCode ??
        (mapped is ApiException ? mapped.statusCode : null);
    final authorization = options.headers['Authorization'];
    if (status == 401 &&
        authorization is String &&
        authorization.startsWith(_bearerPrefix) &&
        !options.path.startsWith('/auth/')) {
      _onUnauthorized(authorization.substring(_bearerPrefix.length));
    }
    handler.next(err);
  }
}

/// Adds a correlation id so a failed request can be found in the admin `ai_logs`.
class CorrelationIdInterceptor extends Interceptor {
  int _counter = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _counter++;
    final id =
        '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-$_counter';
    options.headers['X-Correlation-Id'] = id;
    handler.next(options);
  }
}

/// Unwraps the backend `ApiResponse<T>` envelope so services read `data` directly
/// (see [unwrapEnvelope]). `success: false` with HTTP 200 becomes an error.
class EnvelopeInterceptor extends Interceptor {
  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    if (response.requestOptions.responseType == ResponseType.stream) {
      handler.next(response);
      return;
    }
    try {
      response.data = unwrapEnvelope(response.data);
      handler.next(response);
    } on ApiException catch (e) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          error: e,
        ),
        true,
      );
    }
  }
}
