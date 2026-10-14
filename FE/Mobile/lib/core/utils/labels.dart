// lib/core/utils/labels.dart
// Vietnamese display labels for ids that come from the API.

const Map<String, String> _allergenLabels = {
  'peanut': 'Đậu phộng',
  'tree_nut': 'Hạt cây',
  'soy': 'Đậu nành',
  'gluten': 'Gluten',
  'sesame': 'Mè',
  'mustard': 'Mù tạt',
  'celery': 'Cần tây',
};

const Map<String, String> _dietTagLabels = {
  'gluten_free': 'Không gluten',
  'high_protein': 'Giàu đạm',
  'high_fiber': 'Giàu chất xơ',
  'low_sodium': 'Ít muối',
  'whole_food': 'Thực phẩm nguyên chất',
  'quick': 'Nhanh gọn',
  'seasonal': 'Đang mùa',
};

String allergenLabel(String id) => _allergenLabels[id] ?? id;

String dietTagLabel(String id) => _dietTagLabels[id] ?? id;
