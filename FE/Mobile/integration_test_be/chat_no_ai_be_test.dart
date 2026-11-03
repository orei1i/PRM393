// integration_test_be/chat_no_ai_be_test.dart
//
// A BE with no Gemini configured: the chatbot and the knowledge documents must
// say so, never answer with something made up. Only on such a server:
//
//   flutter test chat_no_ai_be_test.dart --no-pub --dart-define=NO_AI_QA=true \
//     --dart-define=USE_MOCK_DATA=false \
//     --dart-define=API_BASE_URL=http://localhost:5002/api/v1
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/config/env.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/network/interceptors.dart';
import 'package:veganlife_mobile/features/chatbot/data/chat_api_service.dart';
import 'package:veganlife_mobile/features/chatbot/data/models/chat_models.dart';
import 'package:veganlife_mobile/features/chatbot/domain/entities/chat_message.dart';
import 'package:veganlife_mobile/features/chatbot/presentation/controllers/chat_controller.dart';

import 'be_harness.dart';

const _noAiQa = bool.fromEnvironment('NO_AI_QA');

ChatApiService _guestChat(String guestToken) {
  final dio = Dio(BaseOptions(
    baseUrl: Env.apiBaseUrl,
    headers: {'Accept': 'application/json', 'X-Guest-Token': guestToken},
  ));
  dio.interceptors.addAll([EnvelopeInterceptor(), ErrorMappingInterceptor()]);
  return RemoteChatApiService(dio);
}

void main() async {
  final be = await BeHarness.start();

  group('no AI on the server',
      skip: _noAiQa ? be.skipReason : 'NO_AI_QA is not true', () {
    beTest('a guest: 503 ai_unavailable, the free turn is kept', () async {
      final token = randomHex(24);
      final chat = _guestChat(token);
      await expectLater(
          chat
              .streamReply(
                  sessionId: 'session_${randomHex(12)}',
                  request:
                      const ChatRequestDto(message: 'đậu lăng có đạm không'))
              .toList(),
          throwsA(isA<ApiException>()
              .having((e) => e.statusCode, 'status', 503)
              .having((e) => e.code, 'code', 'ai_unavailable')
              .having((e) => e.message, 'message', isVietnamese)));
      expect((await chat.getGuestTrialStatus()).used, 0);
    });

    beTest('in the app: a failed bubble with the reason, no answer', () async {
      final user = await be.newUser();
      final c = await user.container();
      addTearDown(c.dispose);
      final sub = c.listen(chatControllerProvider, (_, __) {});
      addTearDown(sub.close);
      await c
          .read(chatControllerProvider.notifier)
          .send('đậu lăng có đạm không');
      while (c.read(chatControllerProvider).isStreaming) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      final messages = c.read(chatControllerProvider).messages;
      expect(messages.first.isUser, isTrue, reason: 'the question stays');
      final answer = messages.last;
      expect(answer.status, MessageStatus.failed);
      expect(answer.content, isEmpty);
      expect(answer.citations, isEmpty);
      expect(answer.errorMessage, isVietnamese);
    });

    beTest('a WHO document stays waiting with ingestStatus Failed', () async {
      final admin = await be.adminToken();
      final marker = randomHex(10);
      final res = await rawRequest('POST', '/admin/knowledge-docs',
          token: admin,
          data: {
            'title': 'Tài liệu không có AI $marker',
            'content': '$marker Đậu lăng là nguồn đạm thực vật. ' * 6,
          });
      expect(res.status, 200);
      expect(res.dataMap['status'], 'Pending');
      expect(res.dataMap['ingestStatus'], 'Failed');
      expect(res.dataMap['ingestError'], isVietnamese);
      await rawRequest('DELETE', '/admin/knowledge-docs/${res.dataMap['id']}',
          token: admin);
    });
  });
}
