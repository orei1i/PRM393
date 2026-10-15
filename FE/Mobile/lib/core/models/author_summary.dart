// lib/core/models/author_summary.dart
import '../utils/json_helpers.dart';

/// Minimal public profile attached to posts, videos and comments.
class AuthorSummary {
  const AuthorSummary(
      {required this.id, required this.name, this.isVerifiedChef = false});

  factory AuthorSummary.fromJson(Map<String, dynamic> json) => AuthorSummary(
        id: json['id']?.toString() ?? '',
        name: json['fullName'] as String? ??
            json['name'] as String? ??
            'Thành viên',
        isVerifiedChef: json['isVerifiedChef'] == true,
      );

  factory AuthorSummary.fromJsonValue(Object? value) =>
      AuthorSummary.fromJson(readMap(value));

  final String id;
  final String name;
  final bool isVerifiedChef;

  Map<String, dynamic> toJson() =>
      {'id': id, 'fullName': name, 'isVerifiedChef': isVerifiedChef};
}
