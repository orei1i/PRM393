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
  // What the BE's recipe catalogue is tagged with.
  'baked': 'Món nướng',
  'balanced': 'Cân bằng',
  'calm': 'Thanh tịnh',
  'classic': 'Món quen',
  'colorful': 'Nhiều màu sắc',
  'comfort': 'Dễ ăn',
  'creamy': 'Béo mịn',
  'crispy': 'Giòn',
  'crunchy': 'Giòn rụm',
  'delicate': 'Thanh nhẹ',
  'detox': 'Thanh lọc',
  'drink': 'Đồ uống',
  'easy_digest': 'Dễ tiêu',
  'fresh': 'Tươi mát',
  'light': 'Nhẹ bụng',
  'no_cook': 'Không cần nấu',
  'refreshing': 'Giải nhiệt',
  'rich': 'Đậm đà',
  'savory': 'Mặn mà',
  'spicy': 'Cay',
  'sweet': 'Vị ngọt',
  'traditional': 'Truyền thống',
  'warm': 'Món nóng',
};

String allergenLabel(String id) => _allergenLabels[id] ?? id;

/// A tag this app has no word for yet at least doesn't read as a raw id
/// ("low_fat" → "low fat").
String dietTagLabel(String id) => _dietTagLabels[id] ?? id.replaceAll('_', ' ');
