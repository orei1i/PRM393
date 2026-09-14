import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vegan_life/src/features/ai_nutrition/domain/entities/nutrition_entities.dart';
import 'package:vegan_life/src/features/ai_nutrition/domain/repositories/nutrition_repository.dart';
import 'package:vegan_life/src/features/ai_nutrition/presentation/view_models/ai_nutrition_view_model.dart';
import 'package:vegan_life/src/features/ai_nutrition/presentation/widgets/nutrition_chat_panel.dart';
import 'package:vegan_life/src/features/auth/data/repositories/mock_auth_repository.dart';
import 'package:vegan_life/src/features/auth/presentation/view_models/auth_view_model.dart';
import 'package:vegan_life/src/features/trial_chat/data/repositories/mock_trial_quota_repository.dart';
import 'package:vegan_life/src/features/trial_chat/presentation/view_models/trial_chat_view_model.dart';
import 'package:vegan_life/src/features/trial_chat/presentation/views/trial_chat_view.dart';

const _welcome = 'Good food.\nA little guidance.';
const _streamError = 'A demo connection error occurred. Try another question.';
const _failedAnswer =
    'The demo response could not be completed. You can send another question.';

// No token delays or scheduled repository work: each test owns chunk, error,
// and completion delivery independently of Flutter's animation clock.
class _ControlledResponse {
  _ControlledResponse(this.prompt) {
    _controller = StreamController<String>(
      sync: true,
      onCancel: () {
        cancelCount++;
      },
    );
  }

  final String prompt;
  late final StreamController<String> _controller;
  int cancelCount = 0;

  Stream<String> get stream => _controller.stream;
  void add(String chunk) => _controller.add(chunk);
  void fail() => _controller.addError(StateError('Controlled stream failure'));
  Future<void> close() => _controller.close();
}

class _ControlledNutritionRepository implements NutritionRepository {
  final requests = <_ControlledResponse>[];

  @override
  List<NutritionTip> get quickActions => const [
    NutritionTip('Protein ideas', 'How can I add plant protein?'),
  ];

  @override
  List<FoodSubstitution> get substitutions => const [];

  @override
  Stream<String> streamResponse(String prompt) {
    final response = _ControlledResponse(prompt);
    requests.add(response);
    return response.stream;
  }

  Future<void> dispose() async {
    for (final response in requests) {
      await response.close();
    }
  }
}

class _ChatFixture {
  _ChatFixture({bool trial = false}) {
    if (!trial) auth.signInAsMember();
    vm = trial
        ? TrialChatViewModel(repository, auth, MockTrialQuotaRepository())
        : AiNutritionViewModel(repository, auth);
  }

  final repository = _ControlledNutritionRepository();
  final auth = AuthViewModel(MockAuthRepository());
  late final AiNutritionViewModel vm;

  Future<void> dispose() async {
    vm.dispose();
    auth.dispose();
    await repository.dispose();
  }
}

_ChatFixture _fixture({bool trial = false}) {
  final fixture = _ChatFixture(trial: trial);
  addTearDown(fixture.dispose);
  return fixture;
}

Widget _app(_ChatFixture fixture, {VoidCallback? onSubmitted}) => MultiProvider(
  providers: [
    ChangeNotifierProvider<AuthViewModel>.value(value: fixture.auth),
    if (fixture.vm is TrialChatViewModel)
      ChangeNotifierProvider<TrialChatViewModel>.value(
        value: fixture.vm as TrialChatViewModel,
      ),
  ],
  child: MaterialApp(
    home: Scaffold(
      body: fixture.vm is TrialChatViewModel
          ? const TrialChatView()
          : NutritionChatPanel(
              key: const ValueKey('regression-chat-panel'),
              vm: fixture.vm,
              onSubmitted: onSubmitted,
            ),
    ),
  ),
);

Future<void> _mount(
  WidgetTester tester,
  _ChatFixture fixture, {
  VoidCallback? onSubmitted,
}) async {
  // Keep transcript tests in the normal-height layout, not the compact shell.
  tester.view.physicalSize = const Size(800, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // Registered after fixtures so listeners detach before their VMs dispose.
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pumpWidget(_app(fixture, onSubmitted: onSubmitted));
  await tester.pump();
}

Future<void> _seedHistory(
  WidgetTester tester,
  _ChatFixture fixture, {
  int turns = 2,
}) async {
  for (var index = 0; index < turns; index++) {
    final pending = fixture.vm.submit('History question $index');
    final response = fixture.repository.requests.last;
    response.add('History answer $index');
    final closing = response.close();
    await tester.pump();
    await closing;
    expect(await pending, isTrue);
  }
}

Finder _bubble(ChatMessage message) =>
    find.byKey(ValueKey('chat-message-${message.id}'));

Finder _bubbles() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith('chat-message-');
}, skipOffstage: false);

ListView _transcript(WidgetTester tester) =>
    tester.widget<ListView>(find.byKey(const ValueKey('chat-transcript')));

TextField _composer(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField));

String? _bubbleText(WidgetTester tester, ChatMessage message) => tester
    .widget<SelectableText>(
      find.descendant(
        of: _bubble(message),
        matching: find.byType(SelectableText),
      ),
    )
    .data;

Future<void> _sendPrompt(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byTooltip('Send question'));
  // Never settle while the indeterminate streaming indicator is active.
  await tester.pump();
}

void main() {
  group('Chat message snapshots', () {
    test(
      'streaming, appending, stop, and clear preserve earlier snapshots',
      () async {
        final fixture = _fixture();
        final vm = fixture.vm;
        final empty = vm.messages;
        final firstPending = vm.submit('First question');
        final firstResponse = fixture.repository.requests.single;
        final preparing = vm.messages;

        expect(empty, isEmpty);
        expect(preparing, hasLength(2));
        expect(preparing.last.text, isEmpty);
        expect(preparing.last.streaming, isTrue);
        firstResponse.add('First');
        final partial = vm.messages;
        expect(partial, isNot(same(preparing)));
        expect(partial.first, same(preparing.first));
        expect(partial.last.id, preparing.last.id);
        expect(partial.last.text, 'First');
        expect(preparing.last.text, isEmpty);

        firstResponse.add(' answer');
        final streamed = vm.messages;
        expect(partial.last.text, 'First');
        expect(streamed.last.text, 'First answer');
        await firstResponse.close();
        expect(await firstPending, isTrue);
        final completed = vm.messages;
        expect(completed, isNot(same(streamed)));
        expect(completed.last.streaming, isFalse);
        expect(streamed.last.streaming, isTrue);
        expect(completed.last.text, 'First answer');

        for (final snapshot in [preparing, partial, streamed, completed]) {
          expect(() => snapshot.add(completed.first), throwsUnsupportedError);
          expect(() => snapshot[0] = completed.last, throwsUnsupportedError);
          expect(snapshot.clear, throwsUnsupportedError);
        }

        final secondPending = vm.submit('Second question');
        final secondResponse = fixture.repository.requests.last;
        secondResponse.add('Second partial');
        final beforeStop = vm.messages;
        expect(beforeStop, hasLength(4));
        expect(completed, hasLength(2));
        expect(beforeStop.first, same(completed.first));
        expect(beforeStop[1], same(completed.last));
        vm.cancel();
        expect(await secondPending, isFalse);
        final stopped = vm.messages;
        expect(stopped.last.text, 'Second partial\n[Response stopped]');
        expect(stopped.last.streaming, isFalse);
        expect(beforeStop.last.text, 'Second partial');
        expect(beforeStop.last.streaming, isTrue);
        expect(secondResponse.cancelCount, 1);

        vm.clearConversation();
        secondResponse.add(' late data');
        await secondResponse.close();
        expect(vm.messages, isEmpty);
        expect(stopped, hasLength(4));
        expect(completed.last.text, 'First answer');
        expect(stopped.last.text, 'Second partial\n[Response stopped]');
      },
    );

    test(
      'draft notifications retain empty, streaming, and finished list identity',
      () async {
        final fixture = _fixture();
        final vm = fixture.vm;
        var notifications = 0;
        vm.addListener(() => notifications++);

        void checkDrafts() {
          final messages = vm.messages;
          for (final draft in ['P', 'Plant protein?', ' ', '']) {
            final before = notifications;
            vm.setDraft(draft);
            expect(notifications, greaterThan(before));
            expect(vm.messages, same(messages));
            expect(vm.draft, draft);
            expect(vm.canSend, !vm.busy && draft.trim().isNotEmpty);
          }
        }

        checkDrafts();
        final pending = vm.submit('A question');
        final response = fixture.repository.requests.single;
        response.add('An answer');
        checkDrafts();
        await response.close();
        expect(await pending, isTrue);
        checkDrafts();
      },
    );
  });

  testWidgets('long history builds only a lazy viewport of message bubbles', (
    tester,
  ) async {
    final fixture = _fixture();
    await _seedHistory(tester, fixture, turns: 120);
    await _mount(tester, fixture);
    final messages = fixture.vm.messages;
    final list = _transcript(tester);

    expect(messages, hasLength(240));
    expect(list.reverse, isTrue);
    expect(list.childrenDelegate, isA<SliverChildBuilderDelegate>());
    expect(_bubbles().evaluate().length, greaterThan(0));
    expect(_bubbles().evaluate().length, lessThan(messages.length ~/ 4));
    expect(_bubble(messages.last), findsOneWidget);
    expect(_bubble(messages.first), findsNothing);
    expect(_bubbleText(tester, messages.last), 'History answer 119');

    list.controller!.jumpTo(600);
    await tester.pump();
    expect(_bubbles().evaluate().length, lessThan(messages.length ~/ 4));
    expect(list.controller!.offset, closeTo(600, .01));
    expect(tester.takeException(), isNull);
  });

  for (final streaming in [false, true]) {
    testWidgets(
      'typing preserves transcript widget instances while ${streaming ? 'streaming' : 'idle'}',
      (tester) async {
        final fixture = _fixture();
        await _seedHistory(tester, fixture);
        Future<bool>? pending;
        if (streaming) {
          pending = fixture.vm.submit('Active question');
          fixture.repository.requests.last.add('Active partial answer');
        }
        await _mount(tester, fixture);
        final messages = fixture.vm.messages;
        final list = _transcript(tester);
        final bubbles = <Key, Widget>{
          for (final element in _bubbles().evaluate())
            element.widget.key!: element.widget,
        };
        expect(bubbles, isNotEmpty);

        for (final draft in ['P', 'Plant', 'Plant protein?', '']) {
          await tester.enterText(find.byType(TextField), draft);
          await tester.pump();
          expect(fixture.vm.messages, same(messages));
          expect(_transcript(tester), same(list));
          expect(_composer(tester).controller!.text, draft);
          for (final entry in bubbles.entries) {
            expect(tester.widget(find.byKey(entry.key)), same(entry.value));
          }
          final button = tester.widget<IconButton>(
            find.byTooltip(streaming ? 'Stop response' : 'Send question'),
          );
          expect(button.onPressed != null, streaming || draft.isNotEmpty);
        }

        if (pending != null) {
          fixture.vm.cancel();
          expect(await pending, isFalse);
          await tester.pump();
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'stream chunks update the bubble while the composer keeps the next draft',
    (tester) async {
      final fixture = _fixture();
      var submitted = 0;
      await _mount(tester, fixture, onSubmitted: () => submitted++);
      expect(
        tester.widget<IconButton>(find.byTooltip('Send question')).onPressed,
        isNull,
      );

      await tester.enterText(find.byType(TextField), ' ');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(
        find.text('Write a question of 1–2,000 characters.'),
        findsOneWidget,
      );
      expect(find.text(_welcome), findsOneWidget);
      expect(fixture.repository.requests, isEmpty);

      await _sendPrompt(tester, '  A balanced lunch?  ');
      final response = fixture.repository.requests.single;
      final assistant = fixture.vm.messages.last;
      expect(response.prompt, 'A balanced lunch?');
      expect(fixture.vm.busy, isTrue);
      expect(fixture.vm.error, isNull);
      expect(_composer(tester).controller!.text, isEmpty);
      expect(_bubbleText(tester, assistant), 'Preparing a little inspiration…');
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byTooltip('Stop response'), findsOneWidget);

      response.add('Lentils');
      await tester.pump();
      expect(_bubbleText(tester, assistant), 'Lentils');
      expect(submitted, 0);
      await tester.enterText(find.byType(TextField), 'My next question');
      await tester.pump();
      expect(_composer(tester).enabled, isNot(false));
      expect(_composer(tester).readOnly, isFalse);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(fixture.repository.requests, hasLength(1));
      expect(fixture.vm.draft, 'My next question');

      response.add(' and tofu.');
      await tester.pump();
      expect(_bubbleText(tester, assistant), 'Lentils and tofu.');
      expect(_composer(tester).controller!.text, 'My next question');
      expect(submitted, 0);
      await response.close();
      await tester.pumpAndSettle();
      expect(fixture.vm.busy, isFalse);
      expect(fixture.vm.messages.last.streaming, isFalse);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byTooltip('Stop response'), findsNothing);
      expect(
        tester.widget<IconButton>(find.byTooltip('Send question')).onPressed,
        isNotNull,
      );
      expect(_composer(tester).controller!.text, 'My next question');
      expect(submitted, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'quick action stop preserves partial text and ignores its late stream after retry',
    (tester) async {
      final fixture = _fixture();
      var submitted = 0;
      await _mount(tester, fixture, onSubmitted: () => submitted++);
      await tester.tap(find.widgetWithText(ActionChip, 'Protein ideas'));
      await tester.pump();
      final stoppedResponse = fixture.repository.requests.single;
      expect(stoppedResponse.prompt, 'How can I add plant protein?');
      stoppedResponse.add('A partial answer');
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Keep this draft');
      await tester.tap(find.byTooltip('Stop response'));
      await tester.pumpAndSettle();

      final stopped = fixture.vm.messages.last;
      expect(stoppedResponse.cancelCount, 1);
      expect(fixture.vm.busy, isFalse);
      expect(stopped.streaming, isFalse);
      expect(
        _bubbleText(tester, stopped),
        'A partial answer\n[Response stopped]',
      );
      expect(_composer(tester).controller!.text, 'Keep this draft');
      expect(submitted, 0);

      await tester.tap(find.byTooltip('Send question'));
      await tester.pump();
      final fresh = fixture.repository.requests.last;
      expect(fresh.prompt, 'Keep this draft');
      fresh.add('Fresh answer');
      final freshSnapshot = fixture.vm.messages;
      stoppedResponse.add(' late old data');
      await stoppedResponse.close();
      await tester.pump();
      expect(fixture.vm.messages, same(freshSnapshot));
      expect(fixture.vm.busy, isTrue);
      expect(_bubbleText(tester, fixture.vm.messages.last), 'Fresh answer');
      expect(submitted, 0);
      await fresh.close();
      await tester.pumpAndSettle();
      expect(submitted, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stream errors show one notice and a recoverable nonstreaming bubble',
    (tester) async {
      final fixture = _fixture();
      var submitted = 0;
      await _mount(tester, fixture, onSubmitted: () => submitted++);
      await _sendPrompt(tester, 'Fail this response');
      final response = fixture.repository.requests.single;
      response.add('Incomplete answer');
      await tester.pump();
      final partial = fixture.vm.messages;
      await tester.enterText(find.byType(TextField), 'Try another question');
      response.fail();
      await tester.pumpAndSettle();

      expect(response.cancelCount, 1);
      expect(fixture.vm.busy, isFalse);
      expect(fixture.vm.error, _streamError);
      expect(find.text(_streamError), findsOneWidget);
      expect(_bubbleText(tester, fixture.vm.messages.last), _failedAnswer);
      expect(fixture.vm.messages.last.streaming, isFalse);
      expect(partial.last.text, 'Incomplete answer');
      expect(partial.last.streaming, isTrue);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(_composer(tester).controller!.text, 'Try another question');
      expect(submitted, 0);

      await tester.tap(find.byTooltip('Send question'));
      await tester.pump();
      expect(fixture.repository.requests, hasLength(2));
      expect(fixture.vm.error, isNull);
      expect(find.text(_streamError), findsNothing);
      final retry = fixture.repository.requests.last;
      expect(retry.prompt, 'Try another question');
      retry.add('Recovered answer');
      await retry.close();
      await tester.pumpAndSettle();
      expect(_bubbleText(tester, fixture.vm.messages.last), 'Recovered answer');
      expect(submitted, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clear cancels an active response and resets transcript and composer',
    (tester) async {
      final fixture = _fixture();
      await _seedHistory(tester, fixture, turns: 1);
      var submitted = 0;
      await _mount(tester, fixture, onSubmitted: () => submitted++);
      await _sendPrompt(tester, 'Clear this response');
      final response = fixture.repository.requests.last;
      response.add('Partial response');
      await tester.enterText(find.byType(TextField), 'Also clear this draft');
      await tester.tap(find.byTooltip('Clear conversation'));
      await tester.pumpAndSettle();

      expect(response.cancelCount, 1);
      expect(fixture.vm.messages, isEmpty);
      expect(fixture.vm.draft, isEmpty);
      expect(fixture.vm.busy, isFalse);
      expect(fixture.vm.error, isNull);
      expect(_composer(tester).controller!.text, isEmpty);
      expect(find.byKey(const ValueKey('chat-transcript')), findsNothing);
      expect(_bubbles(), findsNothing);
      expect(find.text(_welcome), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'Protein ideas'), findsOneWidget);
      expect(submitted, 0);

      response.add(' late data');
      await response.close();
      await tester.pump();
      expect(fixture.vm.messages, isEmpty);
      expect(find.text(_welcome), findsOneWidget);
      expect(submitted, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final outcome in ['success', 'stop', 'error']) {
    testWidgets(
      'third trial $outcome ${outcome == 'success' ? 'opens' : 'does not open'} auth',
      (tester) async {
        final fixture = _fixture(trial: true);
        final vm = fixture.vm as TrialChatViewModel;
        await _mount(tester, fixture);
        final authButton = find.text('Continue as demo member');

        for (var turn = 1; turn <= 2; turn++) {
          await _sendPrompt(tester, 'Trial question $turn');
          expect(vm.limit.remaining, 3 - turn);
          expect(vm.busy, isTrue);
          expect(authButton, findsNothing);
          final response = fixture.repository.requests.last;
          response.add('Trial answer $turn');
          await response.close();
          await tester.pumpAndSettle();
          expect(authButton, findsNothing);
          expect(
            find.text('${3 - turn} of 3 trial turns remaining'),
            findsOneWidget,
          );
        }

        await _sendPrompt(tester, 'Third trial question');
        final third = fixture.repository.requests.last;
        third.add('Third partial answer');
        await tester.pump();
        expect(vm.limit.remaining, 0);
        expect(vm.busy, isTrue);
        expect(vm.shouldPromptForAuth, isFalse);
        expect(find.text('0 of 3 trial turns remaining'), findsOneWidget);
        expect(authButton, findsNothing);

        if (outcome == 'success') {
          await third.close();
        } else if (outcome == 'stop') {
          await tester.tap(find.byTooltip('Stop response'));
        } else {
          third.fail();
        }
        await tester.pumpAndSettle();
        expect(vm.busy, isFalse);
        // This becomes true even after cancellation/error; only a successful
        // submit completion may cause TrialChatView to present the sheet.
        expect(vm.shouldPromptForAuth, isTrue);
        expect(vm.limit.remaining, 0);
        expect(
          authButton,
          outcome == 'success' ? findsOneWidget : findsNothing,
        );

        if (outcome == 'success') {
          expect(find.byType(BottomSheet), findsOneWidget);
          Navigator.of(tester.element(authButton)).pop();
          await tester.pumpAndSettle();
        } else {
          expect(third.cancelCount, 1);
          third.add(' ignored late data');
          await third.close();
          await tester.pump();
        }
        expect(authButton, findsNothing);
        await _sendPrompt(tester, 'A rejected fourth question');
        await tester.pumpAndSettle();
        expect(fixture.repository.requests, hasLength(3));
        expect(
          vm.error,
          'Your three trial turns are used. Join to keep exploring.',
        );
        expect(vm.limit.remaining, 0);
        expect(authButton, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a successful completion after panel removal cannot call onSubmitted',
    (tester) async {
      final fixture = _fixture();
      var submitted = 0;
      await _mount(tester, fixture, onSubmitted: () => submitted++);
      await _sendPrompt(tester, 'Finish after removal');
      final response = fixture.repository.requests.single;
      response.add('Before removal');
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());

      fixture.vm.setDraft('No disposed controller should receive this');
      response.add(' and after removal');
      await response.close();
      await tester.pump();
      expect(fixture.vm.messages.last.text, 'Before removal and after removal');
      expect(fixture.vm.messages.last.streaming, isFalse);
      expect(fixture.vm.busy, isFalse);
      expect(submitted, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'VM replacement detaches the old draft listener and ignores its completion',
    (tester) async {
      final original = _fixture();
      final replacement = _fixture();
      var originalSubmitted = 0;
      var replacementSubmitted = 0;
      await _mount(tester, original, onSubmitted: () => originalSubmitted++);
      await _sendPrompt(tester, 'Original pending question');
      final oldResponse = original.repository.requests.single;
      oldResponse.add('Original answer');
      await tester.pump();
      final state = tester.state(find.byType(NutritionChatPanel));

      replacement.vm.setDraft('Replacement draft');
      await tester.pumpWidget(
        _app(replacement, onSubmitted: () => replacementSubmitted++),
      );
      await tester.pump();
      expect(tester.state(find.byType(NutritionChatPanel)), same(state));
      expect(_composer(tester).controller!.text, 'Replacement draft');
      expect(find.text(_welcome), findsOneWidget);
      original.vm.setDraft('Stale original draft');
      oldResponse.add(' finished late');
      await oldResponse.close();
      await tester.pump();

      expect(original.vm.messages.last.text, 'Original answer finished late');
      expect(original.vm.busy, isFalse);
      expect(_composer(tester).controller!.text, 'Replacement draft');
      expect(replacement.vm.messages, isEmpty);
      expect(originalSubmitted, 0);
      expect(replacementSubmitted, 0);
      await tester.tap(find.byTooltip('Send question'));
      await tester.pump();
      final fresh = replacement.repository.requests.single;
      expect(fresh.prompt, 'Replacement draft');
      fresh.add('Replacement answer');
      await fresh.close();
      await tester.pumpAndSettle();
      expect(
        _bubbleText(tester, replacement.vm.messages.last),
        'Replacement answer',
      );
      expect(originalSubmitted, 0);
      expect(replacementSubmitted, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'streaming follows near the bottom without moving a reader in history',
    (tester) async {
      final fixture = _fixture();
      await _seedHistory(tester, fixture, turns: 30);
      await _mount(tester, fixture);
      final controller = _transcript(tester).controller!;
      expect(controller.position.maxScrollExtent, greaterThan(600));
      expect(controller.offset, closeTo(0, .01));
      final pending = fixture.vm.submit('A scrolling response');
      final response = fixture.repository.requests.last;
      response.add('First line');
      await tester.pump();
      expect(controller.offset, closeTo(0, .01));

      controller.jumpTo(80);
      await tester.pump();
      response.add('\nFollow this line');
      await tester.pump();
      await tester.pump();
      expect(controller.offset, closeTo(0, .01));

      controller.jumpTo(400);
      await tester.pump();
      final readingOffset = controller.offset;
      response.add('\nDo not interrupt the reader');
      await tester.pump();
      await tester.pump();
      expect(controller.offset, closeTo(readingOffset, .01));
      fixture.vm.setDraft('Draft changes should not move history either');
      await tester.pump();
      expect(controller.offset, closeTo(readingOffset, .01));
      await response.close();
      expect(await pending, isTrue);
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(readingOffset, .01));

      await tester.tap(find.byTooltip('Clear conversation'));
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(0, .01));
      expect(find.text(_welcome), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
