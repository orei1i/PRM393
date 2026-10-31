// lib/core/network/dio_client.dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../session/session_controller.dart';
import 'interceptors.dart';

/// Single configured Dio instance for every remote API service.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: Env.connectTimeout,
      receiveTimeout: Env.receiveTimeout,
      headers: const {
        'Accept': 'application/json',
        'Accept-Language': 'vi-VN',
      },
    ),
  );

  dio.interceptors.addAll([
    CorrelationIdInterceptor(),
    EnvelopeInterceptor(),
    AuthInterceptor(() => ref.read(sessionControllerProvider).authHeaders),
    ErrorMappingInterceptor(),
    UnauthorizedInterceptor((token) =>
        ref.read(sessionControllerProvider.notifier).expire(token: token)),
    if (kDebugMode)
      // No request headers or bodies: they carry the bearer and passwords.
      LogInterceptor(
        requestHeader: false,
        requestBody: false,
        responseBody: false,
        logPrint: (line) => debugPrint(line.toString()),
      ),
  ]);

  ref.onDispose(dio.close);
  return dio;
});
