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
    AuthInterceptor(() => ref.read(sessionControllerProvider).authHeaders),
    ErrorMappingInterceptor(),
    if (kDebugMode)
      LogInterceptor(
        requestBody: true,
        responseBody: false,
        logPrint: (line) => debugPrint(line.toString()),
      ),
  ]);

  ref.onDispose(dio.close);
  return dio;
});
