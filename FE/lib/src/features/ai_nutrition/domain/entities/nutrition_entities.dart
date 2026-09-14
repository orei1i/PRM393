enum MessageRole { user, assistant }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.streaming = false,
  });
  final String id, text;
  final MessageRole role;
  final bool streaming;
  ChatMessage copyWith({String? text, bool? streaming}) => ChatMessage(
    id: id,
    role: role,
    text: text ?? this.text,
    streaming: streaming ?? this.streaming,
  );
}

class NutritionTip {
  const NutritionTip(this.title, this.prompt);
  final String title, prompt;
}

class FoodSubstitution {
  const FoodSubstitution(this.original, this.alternative, this.note);
  final String original, alternative, note;
}
