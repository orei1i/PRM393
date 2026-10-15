// lib/features/chatbot/domain/entities/chat_message.dart

enum ChatRole { user, assistant }

enum MessageStatus {
  /// Assistant placeholder before the first token.
  waiting,
  streaming,
  complete,

  /// Stream cut (network/stop). Partial text is kept; can resume.
  interrupted,

  /// Nothing arrived.
  failed,
}

enum CitationSourceType {
  scientific('scientific', 'Tổ chức khoa học'),
  chefDocument('chef_document', 'Tài liệu đầu bếp'),
  userData('user_data', 'Dữ liệu của bạn');

  const CitationSourceType(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static CitationSourceType fromApi(String? value) =>
      values.firstWhere((t) => t.apiValue == value,
          orElse: () => CitationSourceType.scientific);
}

class Citation {
  const Citation({
    required this.index,
    required this.title,
    required this.publisher,
    required this.sourceType,
    required this.passage,
    this.url,
    this.publishedAt,
    this.verified = false,
  });

  /// Number used in the answer text: [1], [2]…
  final int index;
  final String title;
  final String publisher;
  final CitationSourceType sourceType;

  /// Retrieved chunk the answer relied on.
  final String passage;
  final String? url;
  final DateTime? publishedAt;

  /// Admin-approved chef document / vetted source.
  final bool verified;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.citations = const [],
    this.status = MessageStatus.complete,
    this.errorMessage,
  });

  factory ChatMessage.user(String text) => ChatMessage(
        id: 'u_${DateTime.now().microsecondsSinceEpoch}',
        role: ChatRole.user,
        content: text,
        createdAt: DateTime.now(),
      );

  factory ChatMessage.assistantPlaceholder() => ChatMessage(
        id: 'a_${DateTime.now().microsecondsSinceEpoch}',
        role: ChatRole.assistant,
        content: '',
        createdAt: DateTime.now(),
        status: MessageStatus.waiting,
      );

  final String id;
  final ChatRole role;
  final String content;
  final DateTime createdAt;
  final List<Citation> citations;
  final MessageStatus status;
  final String? errorMessage;

  bool get isUser => role == ChatRole.user;
  bool get isInProgress =>
      status == MessageStatus.waiting || status == MessageStatus.streaming;

  ChatMessage copyWith({
    String? content,
    List<Citation>? citations,
    MessageStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      createdAt: createdAt,
      citations: citations ?? this.citations,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
