// lib/features/meal_planner/domain/allergy_match.dart
//
// A member's allergies are kept as keys: the allergen ids dishes are tagged
// with (`peanut`, `soy`…) or, for anything else, the name they typed or
// picked ("Nấm", "lá lốt"). Tagged ids match a dish's `allergens`; names are
// looked for, as whole words and ignoring accents, in the dish name and its
// ingredients.
import '../../../core/utils/text_search.dart';

/// Allergen ids recipes are tagged with (`recipes.allergens`), labelled by
/// `allergenLabel`.
const dishAllergenIds = {
  'peanut',
  'tree_nut',
  'soy',
  'gluten',
  'sesame',
  'mustard',
  'celery',
};

bool isDishAllergenId(String key) => dishAllergenIds.contains(key);

/// "Lá lốt (tươi)" → " la lot tuoi ": folded, punctuation as spaces, padded
/// so whole words can be found with `contains(' word ')`.
String allergyText(String text) {
  final folded = foldVietnamese(text).replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  return ' ${folded.trim()} ';
}

/// " bơ " — lower case, accents kept, punctuation as spaces.
String _accentedWords(String text) {
  final words = text
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((w) => w.isNotEmpty);
  return ' ${words.join(' ')} ';
}

/// Whether the free-text allergy [name] appears as whole words in any of
/// [texts] ("la lot" matches "Đậu hũ cuốn lá lốt nướng"). Accents are
/// ignored, except for names of three letters or fewer, where they carry
/// the meaning ("bơ" is not "bò", "lạc" is not "lắc").
bool mentionsAllergy(String name, Iterable<String> texts) {
  final needle = allergyText(name);
  if (needle.trim().isEmpty) return false;
  if (needle.trim().length <= 3) {
    final exact = _accentedWords(name);
    return texts.any((t) => _accentedWords(t).contains(exact));
  }
  return texts.any((t) => allergyText(t).contains(needle));
}

/// The member's allergy keys a dish conflicts with: tagged ids found in
/// [tags], plus free-text names found in [texts] (dish name, ingredients).
List<String> allergyConflicts({
  required Iterable<String> tags,
  required Iterable<String> texts,
  required Iterable<String> userAllergies,
}) {
  final mine = userAllergies.toSet();
  final tagged = tags.toSet();
  return [
    // In the dish's own order, like the tags.
    for (final tag in tagged)
      if (mine.contains(tag)) tag,
    for (final key in mine)
      if (!isDishAllergenId(key) &&
          !tagged.contains(key) &&
          mentionsAllergy(key, texts))
        key,
  ];
}
