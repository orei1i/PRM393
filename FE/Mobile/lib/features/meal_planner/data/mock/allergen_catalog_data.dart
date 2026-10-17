// lib/features/meal_planner/data/mock/allergen_catalog_data.dart
//
// Mock GET /catalog/allergens: common allergens and foods people avoid in a
// Vietnamese vegan kitchen. The first 7 ids are the ones dishes are tagged
// with (`recipes.allergens`); the rest are matched by name.

const List<Map<String, Object?>> mockAllergenCatalog = [
  {
    'id': 'peanut',
    'name': 'Đậu phộng',
    'aliases': ['lạc']
  },
  {
    'id': 'tree_nut',
    'name': 'Hạt cây',
    'aliases': ['hạt điều', 'hạnh nhân', 'óc chó', 'hạt dẻ']
  },
  {
    'id': 'soy',
    'name': 'Đậu nành',
    'aliases': ['đậu hũ', 'đậu phụ', 'tàu hũ', 'nước tương']
  },
  {
    'id': 'gluten',
    'name': 'Gluten',
    'aliases': ['lúa mì', 'bột mì', 'mì căn']
  },
  {
    'id': 'sesame',
    'name': 'Mè',
    'aliases': ['vừng']
  },
  {'id': 'mustard', 'name': 'Mù tạt', 'aliases': []},
  {'id': 'celery', 'name': 'Cần tây', 'aliases': []},
  {'id': 'mushroom', 'name': 'Nấm', 'aliases': []},
  {
    'id': 'corn',
    'name': 'Bắp',
    'aliases': ['ngô']
  },
  {'id': 'tomato', 'name': 'Cà chua', 'aliases': []},
  {'id': 'eggplant', 'name': 'Cà tím', 'aliases': []},
  {'id': 'bell_pepper', 'name': 'Ớt chuông', 'aliases': []},
  {
    'id': 'chili',
    'name': 'Ớt',
    'aliases': ['ớt cay']
  },
  {'id': 'potato', 'name': 'Khoai tây', 'aliases': []},
  {'id': 'taro', 'name': 'Khoai môn', 'aliases': []},
  {
    'id': 'coconut',
    'name': 'Dừa',
    'aliases': ['nước cốt dừa']
  },
  {
    'id': 'avocado',
    'name': 'Bơ',
    'aliases': ['quả bơ']
  },
  {'id': 'banana', 'name': 'Chuối', 'aliases': []},
  {'id': 'mango', 'name': 'Xoài', 'aliases': []},
  {
    'id': 'pineapple',
    'name': 'Thơm',
    'aliases': ['dứa', 'khóm']
  },
  {'id': 'kiwi', 'name': 'Kiwi', 'aliases': []},
  {'id': 'strawberry', 'name': 'Dâu tây', 'aliases': []},
  {
    'id': 'citrus',
    'name': 'Cam quýt',
    'aliases': ['cam', 'quýt', 'bưởi']
  },
  {'id': 'lemon', 'name': 'Chanh', 'aliases': []},
  {
    'id': 'buckwheat',
    'name': 'Kiều mạch',
    'aliases': ['soba']
  },
  {'id': 'oat', 'name': 'Yến mạch', 'aliases': []},
  {'id': 'rice', 'name': 'Gạo', 'aliases': []},
  {'id': 'chickpea', 'name': 'Đậu gà', 'aliases': []},
  {'id': 'lentil', 'name': 'Đậu lăng', 'aliases': []},
  {'id': 'green_bean', 'name': 'Đậu xanh', 'aliases': []},
  {'id': 'pea', 'name': 'Đậu Hà Lan', 'aliases': []},
  {'id': 'lupin', 'name': 'Đậu lupin', 'aliases': []},
  {'id': 'sunflower', 'name': 'Hạt hướng dương', 'aliases': []},
  {'id': 'chia', 'name': 'Hạt chia', 'aliases': []},
  {'id': 'flax', 'name': 'Hạt lanh', 'aliases': []},
  {
    'id': 'quinoa',
    'name': 'Diêm mạch',
    'aliases': ['quinoa']
  },
  {'id': 'cinnamon', 'name': 'Quế', 'aliases': []},
  {'id': 'garlic', 'name': 'Tỏi', 'aliases': []},
  {'id': 'onion', 'name': 'Hành tây', 'aliases': []},
  {
    'id': 'sulfite',
    'name': 'Sulfite',
    'aliases': ['chất bảo quản sulfite']
  },
  {
    'id': 'msg',
    'name': 'Bột ngọt',
    'aliases': ['mì chính', 'MSG']
  },
  {'id': 'betel_leaf', 'name': 'Lá lốt', 'aliases': []},
  {'id': 'seaweed', 'name': 'Rong biển', 'aliases': []},
];
