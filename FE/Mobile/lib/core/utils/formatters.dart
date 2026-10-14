// lib/core/utils/formatters.dart
// Vietnamese number/date formatting without pulling in `intl`.

/// 1670 → "1.670"
String formatInt(num value) {
  final digits = value.round().abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return value < 0 ? '-$buffer' : buffer.toString();
}

/// 22.31 → "22,3"
String formatDecimal(double value, {int digits = 1}) =>
    value.toStringAsFixed(digits).replaceAll('.', ',');

/// 0.934 → "93%"
String formatPercent(double ratio) => '${(ratio * 100).round()}%';

const _weekdayShort = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
const _weekdayLong = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];

String weekdayShort(DateTime d) => _weekdayShort[d.weekday - 1];
String weekdayLong(DateTime d) => _weekdayLong[d.weekday - 1];

String _two(int n) => n.toString().padLeft(2, '0');

/// "14/10"
String formatDayMonth(DateTime d) => '${_two(d.day)}/${_two(d.month)}';

/// "Thứ Tư, 14/10"
String formatLongDate(DateTime d) => '${weekdayLong(d)}, ${formatDayMonth(d)}';

/// "2026-10-14" (API date-only format)
String toApiDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Monday of the week containing [d].
DateTime startOfWeek(DateTime d) => dateOnly(d).subtract(Duration(days: d.weekday - 1));

/// "vừa xong", "4 phút trước", "2 giờ trước", "3 ngày trước"
String relativeTime(DateTime time, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(time);
  if (diff.inMinutes < 1) return 'vừa xong';
  if (diff.inHours < 1) return '${diff.inMinutes} phút trước';
  if (diff.inDays < 1) return '${diff.inHours} giờ trước';
  return '${diff.inDays} ngày trước';
}
