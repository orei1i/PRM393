// lib/core/utils/text_search.dart

const _from =
    'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
const _to =
    'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';

/// "Ẩm thực Huế" → "am thuc hue" — so users can search without diacritics.
String foldVietnamese(String input) {
  final lower = input.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    final i = _from.indexOf(ch);
    buffer.write(i >= 0 ? _to[i] : ch);
  }
  return buffer.toString();
}

/// True when every word of [query] appears in [text], ignoring case and accents.
bool matchesQuery(String text, String query) {
  final haystack = foldVietnamese(text);
  return foldVietnamese(query)
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .every(haystack.contains);
}
