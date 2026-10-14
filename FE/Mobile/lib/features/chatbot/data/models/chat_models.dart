// lib/features/chatbot/data/models/chat_models.dart
//
// POST /chat/sessions/{id}/messages   (Accept: text/event-stream)
// request:  { "message": "…", "resume_from": 0,
//             "context": { "include_meal_plan": true, "include_health_profile": true } }
// response (SSE):
//   event: token     data: {"text":"Thực đơn "}
//   event: citation  data: {"index":1,"title":"…","publisher":"NIH ODS","source_type":"scientific",
//                           "passage":"…","url":"https://…","published_at":"2025-03-01","verified":true}
//   event: done      data: {"message_id":"msg_91","trial_remaining":1}
//   event: error     data: {"code":"model_unavailable","message":"…"}
//
// GET /chat/guest-trial  → { "limit": 3, "used": 1, "remaining": 2 }

import '../../../../core/utils/json_helpers.dart';
import '../../domain/entities/chat_message.dart';

class CitationDto {
  const CitationDto({
    required this.index,
    required this.title,
    required this.publisher,
    required this.sourceType,
    required this.passage,
    this.url,
    this.publishedAt,
    this.verified = false,
  });

  factory CitationDto.fromJson(Map<String, dynamic> json) => CitationDto(
        index: readInt(json['index']),
        title: json['title'] as String? ?? '',
        publisher: json['publisher'] as String? ?? '',
        sourceType: json['source_type'] as String? ?? 'scientific',
        passage: json['passage'] as String? ?? '',
        url: json['url'] as String?,
        publishedAt: readDateTime(json['published_at']),
        verified: json['verified'] as bool? ?? false,
      );

  final int index;
  final String title;
  final String publisher;
  final String sourceType;
  final String passage;
  final String? url;
  final DateTime? publishedAt;
  final bool verified;

  Map<String, dynamic> toJson() => {
        'index': index,
        'title': title,
        'publisher': publisher,
        'source_type': sourceType,
        'passage': passage,
        if (url != null) 'url': url,
        if (publishedAt != null) 'published_at': publishedAt!.toIso8601String(),
        'verified': verified,
      };

  Citation toEntity() => Citation(
        index: index,
        title: title,
        publisher: publisher,
        sourceType: CitationSourceType.fromApi(sourceType),
        passage: passage,
        url: url,
        publishedAt: publishedAt,
        verified: verified,
      );
}

class TrialStatusDto {
  const TrialStatusDto({required this.limit, required this.used});

  factory TrialStatusDto.fromJson(Map<String, dynamic> json) => TrialStatusDto(
        limit: readInt(json['limit']),
        used: readInt(json['used']),
      );

  final int limit;
  final int used;

  int get remaining => (limit - used).clamp(0, limit).toInt();

  Map<String, dynamic> toJson() => {'limit': limit, 'used': used, 'remaining': remaining};
}

class ChatRequestDto {
  const ChatRequestDto({
    required this.message,
    this.resumeFrom = 0,
    this.includeMealPlan = true,
    this.includeHealthProfile = true,
  });

  final String message;

  /// > 0 → continue an interrupted answer after this many characters.
  final int resumeFrom;
  final bool includeMealPlan;
  final bool includeHealthProfile;

  Map<String, dynamic> toJson() => {
        'message': message,
        if (resumeFrom > 0) 'resume_from': resumeFrom,
        'context': {
          'include_meal_plan': includeMealPlan,
          'include_health_profile': includeHealthProfile,
        },
      };
}

/// One Server-Sent Event from the answer stream.
sealed class ChatStreamEvent {
  const ChatStreamEvent();

  static ChatStreamEvent? fromSse(String? event, Map<String, dynamic> data) => switch (event) {
        'token' => ChatTokenEvent(data['text'] as String? ?? ''),
        'citation' => ChatCitationEvent(CitationDto.fromJson(data)),
        'done' => ChatDoneEvent(
            messageId: data['message_id'] as String?,
            trialRemaining: data['trial_remaining'] == null ? null : readInt(data['trial_remaining']),
          ),
        'error' => ChatErrorEvent(
            code: data['code'] as String? ?? 'unknown',
            message: data['message'] as String? ?? 'Đã có lỗi xảy ra.',
          ),
        _ => null,
      };
}

class ChatTokenEvent extends ChatStreamEvent {
  const ChatTokenEvent(this.text);
  final String text;
}

class ChatCitationEvent extends ChatStreamEvent {
  const ChatCitationEvent(this.citation);
  final CitationDto citation;
}

class ChatDoneEvent extends ChatStreamEvent {
  const ChatDoneEvent({this.messageId, this.trialRemaining});
  final String? messageId;

  /// Present for guests only.
  final int? trialRemaining;
}

class ChatErrorEvent extends ChatStreamEvent {
  const ChatErrorEvent({required this.code, required this.message});
  final String code;
  final String message;
}
