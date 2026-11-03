// integration_test_be/chat_be_test.dart
//
// The chatbot against a real BE (RemoteChatApiService, SSE over HTTP). Needs a BE
// with an AI service, so it only runs when asked:
//
//   flutter test chat_be_test.dart --no-pub --dart-define=RAG_QA=true \
//     --dart-define=USE_MOCK_DATA=false \
//     --dart-define=API_BASE_URL=http://localhost:5003/api/v1
//
// This checks the app's contract with the server, not the quality of an answer:
// on QA the BE may be pointed at a fake Gemini.
import 'dart:math';

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

const _ragQa = bool.fromEnvironment('RAG_QA');

String _session() =>
    'session_${Random.secure().nextInt(1 << 32)}_${randomHex(8)}';

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

  group('chat (real BE)', skip: _ragQa ? be.skipReason : 'RAG_QA is not true',
      () {
    late String admin;
    late String marker;
    late String docId;

    tearDownAll(() async {
      await rawRequest('DELETE', '/admin/knowledge-docs/$docId', token: admin);
    });

    setUpAll(() async {
      admin = await be.adminToken();
      // What a run that stopped halfway left behind.
      final left = await rawRequest('GET', '/admin/knowledge-docs',
          token: admin, query: {'search': 'Tài liệu kiểm thử chatbot'});
      for (final doc in left.dataList) {
        await rawRequest('DELETE', '/admin/knowledge-docs/${doc['id']}',
            token: admin);
      }
      marker = randomHex(20);
      final created = await rawRequest(
        'POST',
        '/admin/knowledge-docs',
        token: admin,
        data: {
          'title': 'Tài liệu kiểm thử chatbot $marker',
          'content': '$marker $marker $marker Đậu lăng là nguồn đạm thực vật '
              'tốt cho người ăn chay. Một phần đậu lăng nấu chín có nhiều chất xơ.',
          'fileUrl': 'https://example.org/qa/$marker',
          'publisher': 'QA',
        },
      );
      expect(created.status, 200);
      expect(created.dataMap['status'], 'Approved');
      docId = created.dataMap['id'] as String;
    });

    beTest('streams citation, tokens and done, and the [n] has its source',
        () async {
      final chat = _guestChat(randomHex(24));
      final events = await chat
          .streamReply(
              sessionId: _session(),
              request: ChatRequestDto(message: '$marker $marker đậu lăng'))
          .toList();

      final text = events.whereType<ChatTokenEvent>().map((e) => e.text).join();
      expect(text, contains('[1]'));
      final citation = events.whereType<ChatCitationEvent>().single.citation;
      expect(citation.index, 1);
      expect(citation.passage, contains(marker));
      expect(citation.verified, isTrue);
      expect(citation.url, 'https://example.org/qa/$marker');
      expect(events.last, isA<ChatDoneEvent>());
      expect((events.last as ChatDoneEvent).trialRemaining, 2);
    });

    beTest('no source: says so, cites nothing', () async {
      // The fake Gemini hashes words into a vector, so a made-up word can land on
      // some chunk of the corpus by chance. Ten words that all do is a real bug.
      List<ChatStreamEvent>? events;
      for (var i = 0; i < 10 && events == null; i++) {
        final tried = await _guestChat(randomHex(24))
            .streamReply(
                sessionId: _session(),
                request: ChatRequestDto(message: 'qqqxxx${randomHex(12)}'))
            .toList();
        if (tried.whereType<ChatCitationEvent>().isEmpty) events = tried;
      }
      expect(events, isNotNull, reason: 'every made-up word found a source');
      expect(events!.last, isA<ChatDoneEvent>());
      expect(events.whereType<ChatTokenEvent>().map((e) => e.text).join(),
          contains('chưa tìm thấy'));
    });

    beTest('the fourth guest question is TrialExhaustedException', () async {
      final token = randomHex(24);
      final chat = _guestChat(token);
      for (var i = 0; i < 3; i++) {
        await chat
            .streamReply(
                sessionId: _session(),
                request: ChatRequestDto(message: 'câu số $i qqqxxx zzzyyy'))
            .toList();
      }
      expect((await chat.getGuestTrialStatus()).remaining, 0);

      await expectLater(
          chat
              .streamReply(
                  sessionId: _session(),
                  request: const ChatRequestDto(message: 'câu thứ tư qqqxxx'))
              .toList(),
          throwsA(isA<TrialExhaustedException>()));
    });

    beTest('a member is not on the trial; a bad session id says why', () async {
      final user = await be.newUser();
      final chat = RemoteChatApiService(user.dio);
      final events = await chat
          .streamReply(
              sessionId: _session(),
              request: const ChatRequestDto(message: 'qqqxxx thành viên'))
          .toList();
      expect((events.last as ChatDoneEvent).trialRemaining, isNull);

      await expectLater(
          chat
              .streamReply(
                  sessionId: 'x',
                  request: const ChatRequestDto(message: 'qqqxxx'))
              .toList(),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', 'invalid_session')));
    });

    beTest('model cut mid-answer: error event, then resume without a charge',
        () async {
      final token = randomHex(24);
      final session = _session();
      final chat = _guestChat(token);
      final question = '$marker $marker $marker đậu lăng là nguồn đạm ngatgiua';

      final first = await chat
          .streamReply(
              sessionId: session, request: ChatRequestDto(message: question))
          .toList();
      final partial =
          first.whereType<ChatTokenEvent>().map((e) => e.text).join();
      expect(first.last, isA<ChatErrorEvent>());
      expect(partial, isNotEmpty);
      expect((await chat.getGuestTrialStatus()).used, 1);

      final resumed = await chat
          .streamReply(
              sessionId: session,
              request:
                  ChatRequestDto(message: question, resumeFrom: partial.length))
          .toList();
      expect((await chat.getGuestTrialStatus()).used, 1,
          reason: 'resuming must not charge a second question');
      expect(resumed.last, anyOf(isA<ChatDoneEvent>(), isA<ChatErrorEvent>()));
    });

    beTest('a guest of the real app: its own token, three free questions',
        () async {
      final c = await guestContainer();
      addTearDown(c.dispose);
      final chat = c.read(chatApiProvider);
      expect(chat, isA<RemoteChatApiService>());
      final status = await chat.getGuestTrialStatus();
      expect(status.limit, 3);
      final events = await chat
          .streamReply(
              sessionId: 'session_${randomHex(12)}',
              request: ChatRequestDto(message: '$marker $marker đậu lăng'))
          .toList();
      expect(events.last, isA<ChatDoneEvent>());
      expect((await chat.getGuestTrialStatus()).used, status.used + 1);
    });

    beTest('through the app controller: answer, sources, done', () async {
      final user = await be.newUser();
      final c = await user.container();
      addTearDown(c.dispose);
      expect(c.read(chatApiProvider), isA<RemoteChatApiService>());
      final sub = c.listen(chatControllerProvider, (_, __) {});
      addTearDown(sub.close);
      await c
          .read(chatControllerProvider.notifier)
          .send('$marker $marker đậu lăng');
      while (c.read(chatControllerProvider).isStreaming) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      final answer = c.read(chatControllerProvider).messages.last;
      expect(answer.isUser, isFalse);
      expect(answer.status, MessageStatus.complete);
      expect(answer.content, contains('[1]'));
      expect(answer.citations.single.url, 'https://example.org/qa/$marker');
    });

    beTest('switched off at /ai-models: 503 ai_disabled and no answer',
        () async {
      final models = await rawRequest('GET', '/admin/ai/models', token: admin);
      final chatbot = models.dataList.firstWhere((m) => m['task'] == 'chatbot');
      final id = chatbot['id'] as String;
      Future<void> setEnabled(bool on) async {
        final res = await rawRequest('PATCH', '/admin/ai/models/$id',
            token: admin,
            data: {'enabled': on, 'note': 'Kiểm thử công tắc chatbot.'});
        expect(res.status, 200);
      }

      await setEnabled(false);
      addTearDown(() => setEnabled(true));

      final token = randomHex(24);
      await expectLater(
          _guestChat(token)
              .streamReply(
                  sessionId: _session(),
                  request: const ChatRequestDto(message: 'đậu lăng'))
              .toList(),
          throwsA(isA<ApiException>()
              .having((e) => e.statusCode, 'status', 503)
              .having((e) => e.code, 'code', 'ai_disabled')
              .having((e) => e.message, 'message', isVietnamese)));
      expect((await _guestChat(token).getGuestTrialStatus()).used, 0,
          reason: 'a refused question costs no free turn');

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
      final answer = c.read(chatControllerProvider).messages.last;
      expect(answer.status, MessageStatus.failed);
      expect(answer.content, isEmpty, reason: 'no fake answer');
      expect(answer.errorMessage, isVietnamese);
    });

    beTest('a chef-only route refuses a member', () async {
      final user = await be.newUser();
      final res = await rawRequest('POST', '/chefs/me/knowledge-docs',
          token: user.token,
          data: {
            'title': 'Không phải chuyên gia',
            'content': 'x' * 60,
          });
      expect(res.status, 403);
    });
  });
}
