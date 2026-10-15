// lib/core/utils/json_helpers.dart
// Lenient readers: the API may send ints where doubles are expected, or omit lists.

double readDouble(Object? value) => switch (value) {
      final num n => n.toDouble(),
      final String s => double.tryParse(s) ?? 0,
      _ => 0,
    };

int readInt(Object? value) => switch (value) {
      final num n => n.round(),
      final String s => int.tryParse(s) ?? 0,
      _ => 0,
    };

List<String> readStringList(Object? value) => value is List<Object?>
    ? value.map((e) => e.toString()).toList(growable: false)
    : const [];

DateTime? readDateTime(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

/// "2026-10-14" → local midnight.
DateTime readDate(Object? value) {
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return DateTime(parsed.year, parsed.month, parsed.day);
  }
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

Map<String, dynamic> readMap(Object? value) =>
    value is Map<String, dynamic> ? value : const <String, dynamic>{};
