// lib/features/restaurant/domain/food_match.dart
import '../../../core/utils/text_search.dart';

/// Words that say nothing about the dish ("Bún riêu **chay**", "**Quán**
/// Chay An Lạc"), so they never decide a match on their own. Compared
/// without accents.
final _stopWords =
    'chay thuan va voi kieu mon quan nha hang bep an ngon cac cho tu lam'
        .split(' ')
        .toSet();

final _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

List<String> _split(String text) =>
    text.toLowerCase().split(_separators).where((w) => w.isNotEmpty).toList();

/// The dish words of a food name, in order, lower-cased with their accents:
/// "Bún riêu chay" → [bún, riêu].
List<String> foodTokens(String food) {
  final seen = <String>{};
  return _split(food)
      .where((w) => !_stopWords.contains(foldVietnamese(w)) && seen.add(w))
      .toList();
}

/// The words of one text, as written and without accents.
class _Words {
  _Words(String text)
      : exact = _split(text).toSet(),
        folded = _split(foldVietnamese(text)).toSet();

  final Set<String> exact;
  final Set<String> folded;

  /// A word typed with accents must match them ("lẩu" ≠ "lâu"); one typed
  /// without accents matches any ("lau" = "lẩu" = "lâu").
  bool has(String token) => foldVietnamese(token) == token
      ? folded.contains(token)
      : exact.contains(token);
}

/// How well each item mentions [food]: the number of leading dish words
/// found together in one of its texts (a restaurant's name or a review, a
/// post's title or body). Items scoring 0 are left out.
///
/// Vietnamese dish names lead with the dish ("Phở chay nấm đông cô"), so
/// "phở … nấm" in a review scores 2 and "phở" alone scores 1.
Map<K, int> foodMatchScores<K>(Map<K, List<String>> textsByKey, String food) {
  final tokens = foodTokens(food);
  final scores = <K, int>{};
  if (tokens.isEmpty) return scores;
  for (final MapEntry(key: key, value: texts) in textsByKey.entries) {
    var best = 0;
    for (final text in texts) {
      final words = _Words(text);
      var n = 0;
      while (n < tokens.length && words.has(tokens[n])) {
        n++;
      }
      if (n > best) best = n;
    }
    if (best > 0) scores[key] = best;
  }
  return scores;
}

/// Items that mention [food]: those holding its first two dish words, or
/// just the first one when nothing holds two ("bún riêu" doesn't pull in
/// every "bún" place, but "phở Hà Nội" still finds the phở places).
Set<K> matchFood<K>(Map<K, List<String>> textsByKey, String food) {
  final scores = foodMatchScores(textsByKey, food);
  if (scores.isEmpty) return <K>{};
  final best = scores.values.reduce((a, b) => a > b ? a : b);
  final threshold = best >= 2 ? 2 : 1;
  return {
    for (final e in scores.entries)
      if (e.value >= threshold) e.key,
  };
}
