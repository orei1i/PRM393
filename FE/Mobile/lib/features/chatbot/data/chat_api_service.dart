// lib/features/chatbot/data/chat_api_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/backend_modules.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/session/session_controller.dart';
import 'mock_chat_repository.dart';
import 'models/chat_models.dart';

abstract interface class ChatApiService {
  /// Free questions left for the current guest token.
  Future<TrialStatusDto> getGuestTrialStatus();

  /// Streams the answer as SSE events. Throws [TrialExhaustedException] when a
  /// guest has no free questions left.
  Stream<ChatStreamEvent> streamReply({
    required String sessionId,
    required ChatRequestDto request,
    CancelToken? cancelToken,
  });
}

class RemoteChatApiService implements ChatApiService {
  RemoteChatApiService(this._dio);

  final Dio _dio;

  @override
  Future<TrialStatusDto> getGuestTrialStatus() => guardApi(() async {
        final res =
            await _dio.get<Map<String, dynamic>>(ApiEndpoints.guestTrial);
        return TrialStatusDto.fromJson(res.data!);
      });

  @override
  Stream<ChatStreamEvent> streamReply({
    required String sessionId,
    required ChatRequestDto request,
    CancelToken? cancelToken,
  }) async* {
    final Response<ResponseBody> res;
    try {
      res = await _dio.post<ResponseBody>(
        ApiEndpoints.chatMessages(sessionId),
        data: request.toJson(),
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
    } on DioException catch (e) {
      throw await _streamRequestError(e);
    }

    final lines = res.data!.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    String? eventName;
    final data = StringBuffer();
    try {
      await for (final line in lines) {
        if (line.isEmpty) {
          if (data.isNotEmpty) {
            final decoded = jsonDecode(data.toString());
            if (decoded is Map<String, dynamic>) {
              final event = ChatStreamEvent.fromSse(eventName, decoded);
              if (event != null) yield event;
            }
          }
          eventName = null;
          data.clear();
        } else if (line.startsWith('event:')) {
          eventName = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          if (data.isNotEmpty) data.write('\n');
          data.write(line.substring(5).trimLeft());
        }
      }
    } on DioException catch (e) {
      throw mapDioException(e);
    } on FormatException {
      throw const ApiException(
          message: 'Phản hồi từ máy chủ không hợp lệ.', code: 'bad_stream');
    }
  }
}

/// With `ResponseType.stream` an error body is a stream too, so the interceptor
/// couldn't read `code` and `message`: read them here, or a 503 says nothing.
Future<ApiException> _streamRequestError(DioException e) async {
  final response = e.response;
  final body = response?.data;
  if (response == null || body is! ResponseBody) return mapDioException(e);
  try {
    final bytes = await body.stream
        .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk))
        .timeout(const Duration(seconds: 5));
    final decoded = jsonDecode(utf8.decode(bytes));
    return mapDioException(DioException(
      requestOptions: e.requestOptions,
      type: e.type,
      response: Response<dynamic>(
        requestOptions: e.requestOptions,
        statusCode: response.statusCode,
        data: decoded,
      ),
    ));
  } on Exception {
    return mapDioException(e);
  }
}

final chatApiProvider = Provider<ChatApiService>((ref) {
  if (BackendModules.isMock(BackendModule.chatbot)) {
    return MockChatRepository(
      prefs: ref.watch(sharedPreferencesProvider),
      readSession: () => ref.read(sessionControllerProvider),
    );
  }
  return RemoteChatApiService(ref.watch(dioProvider));
});
