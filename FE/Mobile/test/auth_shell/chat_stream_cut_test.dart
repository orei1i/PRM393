// test/auth_shell/chat_stream_cut_test.dart
// How the chat treats the end of an answer: only `done` means finished.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/chatbot/data/chat_api_service.dart';
import 'package:veganlife_mobile/features/chatbot/data/models/chat_models.dart';
import 'package:veganlife_mobile/features/chatbot/domain/entities/chat_message.dart';
import 'package:veganlife_mobile/features/chatbot/presentation/controllers/chat_controller.dart';

class _FakeChat implements ChatApiService {
  _FakeChat(this.replies);

  final List<List<ChatStreamEvent>> replies;
  final requests = <ChatRequestDto>[];

  @override
  Future<TrialStatusDto> getGuestTrialStatus() async =>
      const TrialStatusDto(limit: 3, used: 0);

  @override
  Stream<ChatStreamEvent> streamReply({
    required String sessionId,
    required ChatRequestDto request,
    CancelToken? cancelToken,
  }) {
    requests.add(request);
    return Stream.fromIterable(replies.removeAt(0));
  }
}

Future<(ProviderContainer, _FakeChat)> _start(
    List<List<ChatStreamEvent>> replies) async {
  SharedPreferences.setMockInitialValues({
    'vl.access_token': 'mock.jwt',
    'vl.display_name': 'Minh Anh',
    'vl.user_id': 'u_me',
    'vl.role': 'User',
  });
  final prefs = await SharedPreferences.getInstance();
  final fake = _FakeChat(replies);
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    chatApiProvider.overrideWithValue(fake),
  ]);
  addTearDown(container.dispose);
  return (container, fake);
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  test('done: the answer is complete', () async {
    final (c, _) = await _start([
      [const ChatTokenEvent('Xong rồi.'), const ChatDoneEvent(messageId: 'm1')]
    ]);
    final chat = c.read(chatControllerProvider.notifier);
    await chat.send('Hỏi');
    await _settle();

    final last = c.read(chatControllerProvider).messages.last;
    expect(last.status, MessageStatus.complete);
    expect(c.read(chatControllerProvider).isStreaming, isFalse);
  });

  test('closed without done, with text: interrupted and can resume', () async {
    final (c, fake) = await _start([
      [const ChatTokenEvent('Một phần')],
      [const ChatTokenEvent(' còn lại'), const ChatDoneEvent(messageId: 'm1')],
    ]);
    final chat = c.read(chatControllerProvider.notifier);
    await chat.send('Hỏi');
    await _settle();

    final cut = c.read(chatControllerProvider).messages.last;
    expect(cut.status, MessageStatus.interrupted,
        reason: 'a cut answer must not look finished');
    expect(cut.errorMessage, isNotNull);
    expect(c.read(chatControllerProvider).isStreaming, isFalse);

    chat.retry(cut.id);
    await _settle();

    expect(fake.requests.last.resumeFrom, 'Một phần'.length);
    final done = c.read(chatControllerProvider).messages.last;
    expect(done.content, 'Một phần còn lại');
    expect(done.status, MessageStatus.complete);
    expect(c.read(chatControllerProvider).messages.where((m) => m.isUser),
        hasLength(1),
        reason: 'resuming adds no second question');
  });

  test('closed without done or text: failed, retry asks again', () async {
    final (c, fake) = await _start([
      const [],
      [const ChatTokenEvent('Có rồi.'), const ChatDoneEvent(messageId: 'm1')],
    ]);
    final chat = c.read(chatControllerProvider.notifier);
    await chat.send('Hỏi');
    await _settle();

    final failed = c.read(chatControllerProvider).messages.last;
    expect(failed.status, MessageStatus.failed);

    chat.retry(failed.id);
    await _settle();

    expect(fake.requests.last.resumeFrom, 0);
    expect(c.read(chatControllerProvider).messages.last.content, 'Có rồi.');
  });

  test('an error event keeps the text and offers resume', () async {
    final (c, _) = await _start([
      [
        const ChatTokenEvent('Một phần'),
        const ChatErrorEvent(code: 'model_unavailable', message: 'Gián đoạn.'),
      ]
    ]);
    await c.read(chatControllerProvider.notifier).send('Hỏi');
    await _settle();

    final last = c.read(chatControllerProvider).messages.last;
    expect(last.content, 'Một phần');
    expect(last.status, MessageStatus.interrupted);
    expect(last.errorMessage, 'Gián đoạn.');
  });

  test('a citation is kept once, and an unknown event is ignored', () {
    final json = <String, dynamic>{
      'index': 1,
      'title': 'T',
      'publisher': 'P',
      'sourceType': 'chef_document',
      'passage': 'Đoạn',
      'verified': true,
    };
    final event =
        ChatStreamEvent.fromSse('citation', json)! as ChatCitationEvent;
    expect(
        event.citation.toEntity().sourceType, CitationSourceType.chefDocument);
    expect(ChatStreamEvent.fromSse('khac', json), isNull);
  });
}
