import 'dart:async';
import '../../../../core/state/view_model.dart';
import '../../../auth/presentation/view_models/auth_view_model.dart';
import '../../domain/entities/nutrition_entities.dart';
import '../../domain/repositories/nutrition_repository.dart';

class AiNutritionViewModel extends ViewModel {
  AiNutritionViewModel(this.repository, this.auth) {
    auth.addListener(_roleChanged);
  }
  final NutritionRepository repository;
  final AuthViewModel auth;
  List<ChatMessage> _messages = const [];
  StreamSubscription<String>? _subscription;
  Completer<bool>? _completion;
  int _sequence = 0;
  int _generation = 0;
  String _draft = '';
  List<ChatMessage> get messages => _messages;

  void _replaceMessage(int index, ChatMessage message) {
    final updated = List<ChatMessage>.of(_messages);
    updated[index] = message;
    _messages = List.unmodifiable(updated);
  }

  List<NutritionTip> get quickActions => repository.quickActions;
  String get draft => _draft;
  bool get authorized => auth.canParticipate;
  bool get canSend => !busy && _draft.trim().isNotEmpty;
  void setDraft(String value) {
    _draft = value;
    emit();
  }

  bool reserveTurn() => true;

  Future<bool> submit([String? prompt]) {
    final text = (prompt ?? _draft).trim();
    if (busy || disposed) return Future.value(false);
    if (!authorized) {
      fail('Sign in to use this assistant.');
      return Future.value(false);
    }
    if (text.isEmpty || text.length > 2000) {
      fail('Write a question of 1–2,000 characters.');
      return Future.value(false);
    }
    if (!reserveTurn()) return Future.value(false);
    _draft = '';
    final request = ++_generation;
    final index = _messages.length + 1;
    _messages = List.unmodifiable([
      ..._messages,
      ChatMessage(id: 'u${_sequence++}', role: MessageRole.user, text: text),
      ChatMessage(
        id: 'a${_sequence++}',
        role: MessageRole.assistant,
        text: '',
        streaming: true,
      ),
    ]);
    final completion = Completer<bool>();
    _completion = completion;
    setBusy(true);
    _subscription = repository
        .streamResponse(text)
        .listen(
          (chunk) {
            if (disposed || request != _generation) return;
            _replaceMessage(
              index,
              _messages[index].copyWith(text: _messages[index].text + chunk),
            );
            emit();
          },
          onError: (Object exception) {
            if (disposed || request != _generation) return;
            _replaceMessage(
              index,
              _messages[index].copyWith(
                text:
                    'The demo response could not be completed. You can send another question.',
                streaming: false,
              ),
            );
            fail('A demo connection error occurred. Try another question.');
            if (!completion.isCompleted) completion.complete(false);
          },
          onDone: () {
            if (disposed || request != _generation) return;
            _replaceMessage(index, _messages[index].copyWith(streaming: false));
            setBusy(false);
            if (!completion.isCompleted) completion.complete(true);
          },
          cancelOnError: true,
        );
    return completion.future;
  }

  void cancel() {
    _generation++;
    _subscription?.cancel();
    _subscription = null;
    if (_completion?.isCompleted == false) _completion!.complete(false);
    if (_messages.any((message) => message.streaming)) {
      _messages = List.unmodifiable([
        for (final message in _messages)
          message.streaming
              ? message.copyWith(
                  text: '${message.text}\n[Response stopped]',
                  streaming: false,
                )
              : message,
      ]);
    }
    setBusy(false);
  }

  void clearConversation() {
    cancel();
    _messages = const [];
    _draft = '';
    clearError();
  }

  void _roleChanged() => clearConversation();
  @override
  void dispose() {
    cancel();
    auth.removeListener(_roleChanged);
    super.dispose();
  }
}
