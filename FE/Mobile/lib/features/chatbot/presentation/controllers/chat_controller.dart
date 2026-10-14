// lib/features/chatbot/presentation/controllers/chat_controller.dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/env.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/session/session_controller.dart';
import '../../data/chat_api_service.dart';
import '../../data/models/chat_models.dart';
import '../../domain/entities/chat_message.dart';

class ChatState {
  const ChatState({
    required this.sessionId,
    this.messages = const [],
    this.isStreaming = false,
    this.trialRemaining,
    this.trialLimit = Env.guestTrialLimit,
    this.showTrialExhausted = false,
    this.pendingPrompt,
  });

  final String sessionId;
  final List<ChatMessage> messages;
  final bool isStreaming;

  /// Free questions left; `null` for members (unlimited).
  final int? trialRemaining;
  final int trialLimit;

  /// One-shot UI event: present the sign-in sheet.
  final bool showTrialExhausted;

  /// Question held while the guest signs in; sent automatically afterwards.
  final String? pendingPrompt;

  bool get isGuestTrial => trialRemaining != null;
  bool get isTrialExhausted => trialRemaining != null && trialRemaining! <= 0;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isStreaming,
    int? trialRemaining,
    bool clearTrial = false,
    bool? showTrialExhausted,
    String? pendingPrompt,
    bool clearPending = false,
  }) {
    return ChatState(
      sessionId: sessionId,
      messages: messages ?? this.messages,
      isStreaming: isStreaming ?? this.isStreaming,
      trialRemaining: clearTrial ? null : (trialRemaining ?? this.trialRemaining),
      trialLimit: trialLimit,
      showTrialExhausted: showTrialExhausted ?? this.showTrialExhausted,
      pendingPrompt: clearPending ? null : (pendingPrompt ?? this.pendingPrompt),
    );
  }
}

final chatControllerProvider = NotifierProvider<ChatController, ChatState>(ChatController.new);

class ChatController extends Notifier<ChatState> {
  StreamSubscription<ChatStreamEvent>? _subscription;
  CancelToken? _cancelToken;

  ChatApiService get _api => ref.read(chatApiProvider);

  @override
  ChatState build() {
    ref.onDispose(_cancelStream);

    // Sign-in keeps the conversation: drop the trial counter and send the held question.
    ref.listen<AuthSession>(sessionControllerProvider, (previous, next) {
      if (previous == null || previous.isGuest == next.isGuest) return;
      if (!next.isGuest) {
        _onSignedIn();
      } else {
        state = state.copyWith(trialRemaining: Env.guestTrialLimit);
        _refreshTrialStatus();
      }
    });

    final isGuest = ref.read(sessionControllerProvider).isGuest;
    if (isGuest) Future.microtask(_refreshTrialStatus);

    return ChatState(
      sessionId: 'session_${DateTime.now().millisecondsSinceEpoch}',
      trialRemaining: isGuest ? Env.guestTrialLimit : null,
    );
  }

  // ------------------------------------------------------------- commands --

  Future<void> send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || state.isStreaming) return;

    state = state.copyWith(messages: [...state.messages, ChatMessage.user(text)]);

    // Known to be out of free questions: don't even call the API.
    if (ref.read(sessionControllerProvider).isGuest && state.isTrialExhausted) {
      state = state.copyWith(showTrialExhausted: true, pendingPrompt: text);
      return;
    }
    _respondTo(text);
  }

  /// Stops generation and keeps whatever text already arrived.
  void stop() {
    _cancelStream();
    final last = _lastAssistant;
    if (last == null || !last.isInProgress) return;
    _replace(
      last.id,
      last.copyWith(
        status: last.content.isEmpty ? MessageStatus.failed : MessageStatus.interrupted,
        errorMessage: 'Đã dừng.',
      ),
    );
    state = state.copyWith(isStreaming: false);
  }

  /// Continues an interrupted answer from where it stopped (or re-asks if empty).
  void retry(String assistantMessageId) {
    if (state.isStreaming) return;
    final index = state.messages.indexWhere((m) => m.id == assistantMessageId);
    if (index <= 0) return;
    final question = state.messages.take(index).lastWhere((m) => m.isUser, orElse: () => state.messages[index - 1]);
    final partial = state.messages[index];

    if (partial.content.isEmpty) {
      state = state.copyWith(messages: [...state.messages]..removeAt(index));
      _respondTo(question.content);
      return;
    }
    _replace(partial.id, partial.copyWith(status: MessageStatus.streaming, clearError: true));
    state = state.copyWith(isStreaming: true);
    _listen(
      assistantId: partial.id,
      question: question.content,
      request: ChatRequestDto(message: question.content, resumeFrom: partial.content.length),
    );
  }

  void consumeTrialExhaustedEvent() => state = state.copyWith(showTrialExhausted: false);

  void newConversation() {
    _cancelStream();
    state = ChatState(
      sessionId: 'session_${DateTime.now().millisecondsSinceEpoch}',
      trialRemaining: state.trialRemaining,
    );
  }

  // -------------------------------------------------------------- internals --

  void _respondTo(String question) {
    final placeholder = ChatMessage.assistantPlaceholder();
    state = state.copyWith(messages: [...state.messages, placeholder], isStreaming: true);
    _listen(
      assistantId: placeholder.id,
      question: question,
      request: ChatRequestDto(message: question),
    );
  }

  void _listen({required String assistantId, required String question, required ChatRequestDto request}) {
    _cancelStream();
    final token = CancelToken();
    _cancelToken = token;
    _subscription = _api
        .streamReply(sessionId: state.sessionId, request: request, cancelToken: token)
        .listen(
          (event) => _onEvent(assistantId, event),
          onError: (Object error, StackTrace _) => _onError(assistantId, question, error),
          onDone: () => _onDone(assistantId),
          cancelOnError: true,
        );
  }

  void _onEvent(String id, ChatStreamEvent event) {
    final message = _byId(id);
    if (message == null) return;
    switch (event) {
      case ChatTokenEvent(:final text):
        _replace(id, message.copyWith(content: message.content + text, status: MessageStatus.streaming));
      case ChatCitationEvent(:final citation):
        final entity = citation.toEntity();
        if (message.citations.any((c) => c.index == entity.index)) return;
        _replace(id, message.copyWith(citations: [...message.citations, entity]));
      case ChatDoneEvent(:final trialRemaining):
        if (trialRemaining != null) state = state.copyWith(trialRemaining: trialRemaining);
        _replace(id, message.copyWith(status: MessageStatus.complete));
      case ChatErrorEvent(message: final errorText):
        _onError(id, '', ApiException(message: errorText));
    }
  }

  void _onDone(String id) {
    final message = _byId(id);
    if (message != null && message.isInProgress) {
      _replace(id, message.copyWith(status: MessageStatus.complete));
    }
    state = state.copyWith(isStreaming: false);
  }

  void _onError(String id, String question, Object error) {
    final message = _byId(id);
    if (error is TrialExhaustedException) {
      // Remove the empty bubble, keep the user's question for after sign-in.
      state = state.copyWith(
        messages: state.messages.where((m) => m.id != id).toList(),
        trialRemaining: 0,
        showTrialExhausted: true,
        pendingPrompt: question.isEmpty ? null : question,
        isStreaming: false,
      );
      return;
    }
    if (message != null) {
      _replace(
        id,
        message.copyWith(
          status: message.content.isEmpty ? MessageStatus.failed : MessageStatus.interrupted,
          errorMessage: describeError(error),
        ),
      );
    }
    state = state.copyWith(isStreaming: false);
  }

  void _onSignedIn() {
    final pending = state.pendingPrompt;
    state = state.copyWith(clearTrial: true, showTrialExhausted: false, clearPending: true);
    if (pending != null && !state.isStreaming) _respondTo(pending);
  }

  Future<void> _refreshTrialStatus() async {
    try {
      final status = await _api.getGuestTrialStatus();
      if (!ref.read(sessionControllerProvider).isGuest) return;
      state = state.copyWith(trialRemaining: status.remaining);
    } catch (_) {
      // Keep the optimistic default; the server enforces the limit anyway.
    }
  }

  void _cancelStream() {
    _cancelToken?.cancel();
    _cancelToken = null;
    _subscription?.cancel();
    _subscription = null;
  }

  ChatMessage? get _lastAssistant {
    for (final m in state.messages.reversed) {
      if (!m.isUser) return m;
    }
    return null;
  }

  ChatMessage? _byId(String id) {
    for (final m in state.messages) {
      if (m.id == id) return m;
    }
    return null;
  }

  void _replace(String id, ChatMessage updated) {
    state = state.copyWith(messages: [for (final m in state.messages) m.id == id ? updated : m]);
  }
}
