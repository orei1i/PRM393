// lib/features/scanner/domain/vegan_check.dart
//
// Is this food vegan (thuần chay)? The vision server answers per detection
// (`isVegan`, mirroring `ingredients.is_vegan`); this local keyword check
// covers names typed by hand ("Nhập tay", "Loại khác…", the fridge on the
// Thực đơn tab) and servers that don't send the flag, so the app behaves the
// same offline. When the server sends `isVegan`, it wins ([resolveVegan]).

import '../../../core/utils/text_search.dart';

/// Whether a food is vegan, why not, and what to use instead.
class VeganVerdict {
  const VeganVerdict.vegan()
      : isVegan = true,
        nonVeganReason = null,
        veganAlternatives = const [];

  const VeganVerdict.nonVegan(
      {required String reason, this.veganAlternatives = const []})
      : isVegan = false,
        nonVeganReason = reason;

  final bool isVegan;

  /// "Có nguồn gốc động vật: trứng", "Chứa sữa bò"… `null` when vegan.
  final String? nonVeganReason;

  /// Vegan swaps ("Đậu hũ non" for eggs). Empty when vegan.
  final List<String> veganAlternatives;

  /// "Thuần chay" / "Không thuần chay".
  String get label => isVegan ? 'Thuần chay' : 'Không thuần chay';
}

class _Rule {
  const _Rule(this.keywords, this.alternatives, {this.reason});

  /// Whole words (or phrases), lower case with diacritics.
  final List<String> keywords;

  /// Fixed reason; `null` → "Có nguồn gốc động vật: `keyword`".
  final String? reason;
  final List<String> alternatives;
}

/// First matching rule wins, so specific phrases come before broad words
/// ("sữa bò" before "sữa", "trứng" before "gà").
const _rules = <_Rule>[
  _Rule(['mật ong'], ['Siro phong', 'Mật hoa dừa'], reason: 'Mật ong (từ ong)'),
  _Rule(['kim chi'], ['Kim chi chay'], reason: 'Có thể chứa nước mắm'),
  _Rule([
    'nước mắm',
    'mắm tôm',
    'mắm nêm',
    'mắm ruốc',
    'mắm'
  ], [
    'Nước tương',
    'Nước mắm chay'
  ], reason: 'Làm từ cá hoặc tôm lên men'),
  _Rule(['dầu hào'], ['Dầu hào chay'], reason: 'Làm từ hàu'),
  _Rule(['hạt nêm'], ['Hạt nêm chay'], reason: 'Thường có chiết xuất thịt'),
  _Rule(
      ['sữa bò', 'sữa tươi', 'sữa đặc', 'sữa bột'], ['Sữa hạt', 'Sữa đậu nành'],
      reason: 'Chứa sữa bò'),
  _Rule(['sữa chua'], ['Sữa chua dừa'], reason: 'Làm từ sữa động vật'),
  _Rule(['phô mai', 'pho mát', 'phomai', 'cheese'], ['Phô mai chay'],
      reason: 'Làm từ sữa động vật'),
  _Rule(
      ['bơ động vật', 'bơ sữa', 'bơ lạt', 'bơ mặn', 'bơ nhạt'], ['Bơ thực vật'],
      reason: 'Làm từ sữa động vật'),
  _Rule([
    'sữa dê',
    'kem tươi',
    'váng sữa',
    'whey',
    'sữa'
  ], [
    'Sữa hạt',
    'Sữa đậu nành'
  ], reason: 'Chứa sữa động vật'),
  _Rule(['trứng', 'lòng đỏ', 'lòng trắng'], ['Đậu hũ non']),
  _Rule(['gelatin', 'gelatine', 'collagen'], ['Bột rau câu'],
      reason: 'Làm từ da, xương động vật'),
  _Rule(['tổ yến', 'yến sào', 'yến'], ['Nấm tuyết'],
      reason: 'Làm từ tổ chim yến'),
  _Rule(['tóp mỡ', 'mỡ heo', 'mỡ lợn', 'mỡ gà', 'mỡ'], ['Dầu thực vật']),
  _Rule([
    'cá hồi', 'cá ngừ', 'cá thu', 'cá basa', 'hải sản', 'bạch tuộc', //
    'bào ngư', 'nghêu', 'ghẹ', 'cua', 'sò', 'hàu', 'hến', 'ốc', 'ruốc',
    'tôm', 'mực', 'cá',
  ], [
    'Nấm bào ngư',
    'Đậu hũ'
  ]),
  _Rule([
    'thịt bò', 'thịt heo', 'thịt lợn', 'thịt gà', 'thịt vịt', //
    'xúc xích', 'lạp xưởng', 'giăm bông', 'jambon', 'thịt xông khói',
    'ba chỉ', 'chả lụa', 'giò lụa', 'pate', 'sườn', 'huyết',
    'bò', 'heo', 'lợn', 'gà', 'vịt', 'ngan', 'ngỗng', 'cừu', 'dê', 'bê',
    'thỏ', 'ếch', 'thịt',
  ], [
    'Đậu hũ',
    'Nấm đùi gà',
    'Mì căn'
  ]),
];

/// Plant foods whose names contain an animal word ("rau chân vịt", "nấm mỡ",
/// "đậu gà", "sữa đậu nành"…). Removed before matching.
const _plantPhrases = [
  'rau chân vịt', 'nấm mỡ', 'nấm đùi gà', 'nấm bào ngư', 'đậu gà', //
  'diếp cá', 'bò khai', 'cỏ mực', 'bánh da lợn', 'yến mạch',
  'sữa đậu nành', 'sữa đậu', 'sữa hạt', 'sữa dừa', 'sữa yến mạch',
  'sữa hạnh nhân', 'sữa gạo', 'sữa óc chó', 'sữa điều', 'sữa bắp', 'sữa mè',
  'sữa chua dừa', 'sữa chua hạt', 'sữa chua đậu nành', 'bơ đậu phộng',
  'bơ hạt', 'bơ thực vật',
];

/// Words that make any name vegan ("gà chay", "nước mắm chay").
const _veganMarkers = [
  'chay', 'thuần chay', 'thực vật', 'vegan', 'plant based', //
];

/// Without diacritics these mean too many things ("bo" = bò / bó / bơ, "ca"
/// = cá / cà), so names typed without accents skip them.
const _ambiguousUnaccented = {
  'bo', 'ga', 'ca', 'mo', 'cua', 'oc', 'so', 'de', 'be', 'hau', 'hen', //
  'mam', 'yen', 'lon', 'tho',
};

final _separators = RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true);

/// Longest phrases first, so "sữa yến mạch" goes before "yến mạch".
final _plantPhrasesByLength = [..._plantPhrases]
  ..sort((a, b) => b.length.compareTo(a.length));

/// Local, offline vegan check for a food name. Matches whole words, with or
/// without diacritics ("thit bo" is "thịt bò").
VeganVerdict classifyVegan(String name) {
  final lower = name.toLowerCase().trim();
  if (lower.isEmpty) return const VeganVerdict.vegan();
  // Typed without accents: compare against folded keywords.
  final unaccented = foldVietnamese(lower) == lower;
  String form(String s) => unaccented ? foldVietnamese(s) : s;

  var text =
      ' ${lower.split(_separators).where((w) => w.isNotEmpty).join(' ')} ';
  for (final phrase in _plantPhrasesByLength) {
    final p = ' ${form(phrase)} ';
    while (text.contains(p)) {
      text = text.replaceFirst(p, ' ');
    }
  }
  for (final marker in _veganMarkers) {
    if (text.contains(' ${form(marker)} ')) return const VeganVerdict.vegan();
  }
  for (final rule in _rules) {
    for (final keyword in rule.keywords) {
      final k = form(keyword);
      if (unaccented && _ambiguousUnaccented.contains(k)) continue;
      if (text.contains(' $k ')) {
        return VeganVerdict.nonVegan(
          reason: rule.reason ?? 'Có nguồn gốc động vật: $keyword',
          veganAlternatives: rule.alternatives,
        );
      }
    }
  }
  return const VeganVerdict.vegan();
}

/// The server's `isVegan` wins; its reason/alternatives are filled in from
/// [classifyVegan] when missing. No server flag → [classifyVegan].
VeganVerdict resolveVegan(
  String name, {
  bool? serverIsVegan,
  String? serverReason,
  List<String> serverAlternatives = const [],
}) {
  if (serverIsVegan == null) return classifyVegan(name);
  if (serverIsVegan) return const VeganVerdict.vegan();
  final local = classifyVegan(name);
  final reason = serverReason?.trim();
  return VeganVerdict.nonVegan(
    reason: reason != null && reason.isNotEmpty
        ? reason
        : local.nonVeganReason ?? 'Có nguồn gốc động vật',
    veganAlternatives: serverAlternatives.isNotEmpty
        ? serverAlternatives
        : local.veganAlternatives,
  );
}
