// lib/features/scanner/data/mock_scanner_repository.dart
import 'dart:typed_data';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/mock_delay.dart';
import 'models/scan_result_model.dart';
import 'scanner_api_service.dart';

/// Fake vision backend. Boxes line up with the built-in mock fridge preview,
/// so the overlay looks right on emulators without a camera. Like the real
/// server it says, per item, whether the food is vegan (`isVegan`), and why
/// not: the eggs and the milk show the "Không thuần chay" path by default.
///
/// `--dart-define=MOCK_SCAN_SCENARIO=empty|error` exercises the edge states.
class MockScannerRepository implements ScannerApiService {
  MockScannerRepository({this.scenario = 'normal'});

  final String scenario;

  static const _items = <Map<String, Object?>>[
    {
      'id': 'det_broccoli',
      'label': 'Bông cải xanh',
      'confidence': 0.96,
      'isVegan': true,
      'bbox': {'x': 0.05, 'y': 0.17, 'w': 0.30, 'h': 0.20},
    },
    {
      'id': 'det_tofu',
      'label': 'Đậu hũ',
      'confidence': 0.93,
      'isVegan': true,
      'bbox': {'x': 0.40, 'y': 0.19, 'w': 0.27, 'h': 0.18},
    },
    {
      'id': 'det_tomato',
      'label': 'Cà chua',
      'confidence': 0.89,
      'isVegan': true,
      'bbox': {'x': 0.71, 'y': 0.21, 'w': 0.25, 'h': 0.15},
    },
    {
      'id': 'det_egg',
      'label': 'Trứng gà',
      'confidence': 0.94,
      'isVegan': false,
      'nonVeganReason': 'Có nguồn gốc động vật: trứng',
      'veganAlternatives': ['Đậu hũ non'],
      'bbox': {'x': 0.05, 'y': 0.43, 'w': 0.36, 'h': 0.12},
    },
    {
      'id': 'det_milk',
      'label': 'Sữa bò',
      'confidence': 0.88,
      'isVegan': false,
      'nonVeganReason': 'Chứa sữa bò',
      'veganAlternatives': ['Sữa hạt', 'Sữa đậu nành'],
      'bbox': {'x': 0.45, 'y': 0.40, 'w': 0.17, 'h': 0.15},
    },
    {
      'id': 'det_carrot',
      'label': 'Cà rốt',
      'confidence': 0.91,
      'isVegan': true,
      'bbox': {'x': 0.05, 'y': 0.58, 'w': 0.42, 'h': 0.13},
    },
    {
      'id': 'det_leafy',
      'label': 'Rau chân vịt',
      'confidence': 0.58,
      'isVegan': true,
      'bbox': {'x': 0.52, 'y': 0.585, 'w': 0.43, 'h': 0.12},
      'alternatives': [
        {'label': 'Rau muống', 'confidence': 0.21, 'isVegan': true},
        {'label': 'Cải thìa', 'confidence': 0.12, 'isVegan': true},
      ],
    },
  ];

  @override
  Future<ScanResultDto> scanImage(Uint8List jpegBytes) async {
    await mockDelay(1400);
    switch (scenario) {
      case 'empty':
        return const ScanResultDto(scanId: 'scn_empty', items: []);
      case 'error':
        throw const ApiException(
          message: 'Không nhận diện được ảnh lúc này. Vui lòng thử lại.',
          statusCode: 503,
          code: 'vision_unavailable',
        );
      default:
        return ScanResultDto.fromJson({
          'scanId': 'scn_${DateTime.now().millisecondsSinceEpoch}',
          'items': _items,
        });
    }
  }

  @override
  Future<List<MenuSuggestionDto>> generateMenu(
      GenerateMenuRequestDto request) async {
    await mockDelay(2000);
    // Dishes are built from vegan items only.
    final names = [
      for (final i in request.ingredients)
        if (i.isVegan) i.name,
    ];
    bool has(String n) => names.any((x) => x.toLowerCase() == n.toLowerCase());

    final ideas = <Map<String, Object?>>[
      {
        'id': 'menu_1',
        'name': 'Đậu hũ xào bông cải cà rốt',
        'calories': 420,
        'prepMinutes': 20,
        'usedIngredients': [
          if (has('Đậu hũ')) 'Đậu hũ',
          if (has('Bông cải xanh')) 'Bông cải xanh',
          if (has('Cà rốt')) 'Cà rốt'
        ],
        'missingIngredients': ['Tỏi', 'Nước tương'],
        'allergens': ['soy'],
      },
      {
        'id': 'menu_2',
        'name': 'Canh cà chua đậu hũ rau thơm',
        'calories': 260,
        'prepMinutes': 15,
        'usedIngredients': [
          if (has('Cà chua')) 'Cà chua',
          if (has('Đậu hũ')) 'Đậu hũ'
        ],
        'missingIngredients': ['Hành lá'],
        'allergens': ['soy'],
      },
      {
        'id': 'menu_3',
        'name': 'Cơm chiên rau củ kiểu Việt',
        'calories': 540,
        'prepMinutes': 25,
        'usedIngredients': [
          if (has('Cà rốt')) 'Cà rốt',
          if (has('Bông cải xanh')) 'Bông cải xanh',
          if (has('Rau chân vịt')) 'Rau chân vịt'
        ],
        'missingIngredients': ['Cơm nguội'],
      },
    ];

    // Like the server: never suggest a dish with an excluded allergen.
    final excluded = request.excludeAllergens.toSet();
    return ideas
        .map(MenuSuggestionDto.fromJson)
        .where((m) => m.usedIngredients.isNotEmpty)
        .where((m) => !m.allergens.any(excluded.contains))
        .toList();
  }
}
