// test/fix_chat_pending_test.dart
//
// B01: a guest out of free questions who asks again before signing in must
// not end up with the same question twice and a single answer.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/config/env.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/chatbot/presentation/controllers/chat_controller.dart';

void main() {
  Future<ProviderContainer> exhaustedGuest() async {
    SharedPreferences.setMockInitialValues({'vl.guest_token': 'guest_b01'});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('vl.mock.trial_used.guest_b01', Env.guestTrialLimit);
    final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    container.listen(chatControllerProvider, (_, __) {});
    // Let the controller fetch the (exhausted) trial status.
    for (var i = 0;
        i < 40 && !container.read(chatControllerProvider).isTrialExhausted;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(container.read(chatControllerProvider).isTrialExhausted, isTrue);
    return container;
  }

  List<String> userQuestions(ProviderContainer c) => [
        for (final m in c.read(chatControllerProvider).messages)
          if (m.isUser) m.content,
      ];

  test('asking the same question again keeps a single held bubble', () async {
    final c = await exhaustedGuest();
    final chat = c.read(chatControllerProvider.notifier);

    await chat.send('Gợi ý món thay thế đậu hũ');
    chat.consumeTrialExhaustedEvent();
    await chat.send('Gợi ý món thay thế đậu hũ');

    expect(userQuestions(c), ['Gợi ý món thay thế đậu hũ']);
    expect(c.read(chatControllerProvider).pendingPrompt,
        'Gợi ý món thay thế đậu hũ');
    expect(c.read(chatControllerProvider).showTrialExhausted, isTrue);
  });

  test('a different question replaces the held one', () async {
    final c = await exhaustedGuest();
    final chat = c.read(chatControllerProvider.notifier);

    await chat.send('Câu hỏi thứ nhất');
    await chat.send('Câu hỏi thứ hai');

    expect(userQuestions(c), ['Câu hỏi thứ hai']);
    expect(c.read(chatControllerProvider).pendingPrompt, 'Câu hỏi thứ hai');
  });

  test('after sign-in the held question is asked once and answered once',
      () async {
    final c = await exhaustedGuest();
    final chat = c.read(chatControllerProvider.notifier);

    await chat.send('Gợi ý món thay thế đậu hũ');
    await chat.send('Gợi ý món thay thế đậu hũ');
    await c.read(sessionControllerProvider.notifier).signInWithGoogle();

    // Wait for the mock answer to finish streaming.
    for (var i = 0; i < 200 && !_answered(c); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final messages = c.read(chatControllerProvider).messages;
    expect(messages.where((m) => m.isUser).map((m) => m.content),
        ['Gợi ý món thay thế đậu hũ']);
    expect(messages.where((m) => !m.isUser), hasLength(1));
    expect(c.read(chatControllerProvider).pendingPrompt, isNull);
  });
}

bool _answered(ProviderContainer c) {
  final s = c.read(chatControllerProvider);
  return !s.isStreaming && s.messages.any((m) => !m.isUser);
}
