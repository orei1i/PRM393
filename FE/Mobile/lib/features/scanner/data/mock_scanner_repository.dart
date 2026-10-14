// lib/features/scanner/data/mock_scanner_repository.dart
import 'dart:typed_data';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/mock_delay.dart';
import 'models/scan_result_model.dart';
import 'scanner_api_service.dart';

/// Fake vision backend. Boxes line up with the built-in mock fridge preview,
/// so the overlay looks right on emulators without a camera.
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
      'freshness': 'fresh',
      'bbox': {'x': 0.05, 'y': 0.17, 'w': 0.30, 'h': 0.20},
      'quantity': 1,
      'unit': 'bông',
    },
    {
      'id': 'det_tofu',
      'label': 'Đậu hũ',
      'confidence': 0.93,
      'freshness': 'use_soon',
      'bbox': {'x': 0.40, 'y': 0.19, 'w': 0.27, 'h': 0.18},
      'quantity': 300,
      'unit': 'g',
    },
    {
      'id': 'det_tomato',
      'label': 'Cà chua',
      'confidence': 0.89,
      'freshness': 'fresh',
      'bbox': {'x': 0.71, 'y': 0.21, 'w': 0.25, 'h': 0.15},
      'quantity': 2,
      'unit': 'quả',
    },
    {
      'id': 'det_carrot',
      'label': 'Cà rốt',
      'confidence': 0.91,
      'freshness': 'fresh',
      'bbox': {'x': 0.05, 'y': 0.50, 'w': 0.42, 'h': 0.20},
      'quantity': 3,
      'unit': 'củ',
    },
    {
      'id': 'det_leafy',
      'label': 'Rau chân vịt',
      'confidence': 0.58,
      'freshness': 'fresh',
      'bbox': {'x': 0.52, 'y': 0.52, 'w': 0.43, 'h': 0.18},
      'quantity': 1,
      'unit': 'bó',
      'alternatives': [
        {'label': 'Rau muống', 'confidence': 0.21},
        {'label': 'Cải thìa', 'confidence': 0.12},
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
          'scan_id': 'scn_${DateTime.now().millisecondsSinceEpoch}',
          'items': _items,
        });
    }
  }

  @override
  Future<List<MenuSuggestionDto>> generateMenu(GenerateMenuRequestDto request) async {
    await mockDelay(2000);
    final names = request.ingredients.map((i) => i.name).toList();
    bool has(String n) => names.any((x) => x.toLowerCase() == n.toLowerCase());

    final ideas = <Map<String, Object?>>[
      {
        'id': 'menu_1',
        'name': 'Đậu hũ xào bông cải cà rốt',
        'calories': 420,
        'prep_minutes': 20,
        'used_ingredients': [if (has('Đậu hũ')) 'Đậu hũ', if (has('Bông cải xanh')) 'Bông cải xanh', if (has('Cà rốt')) 'Cà rốt'],
        'missing_ingredients': ['Tỏi', 'Nước tương'],
      },
      {
        'id': 'menu_2',
        'name': 'Canh cà chua đậu hũ rau thơm',
        'calories': 260,
        'prep_minutes': 15,
        'used_ingredients': [if (has('Cà chua')) 'Cà chua', if (has('Đậu hũ')) 'Đậu hũ'],
        'missing_ingredients': ['Hành lá'],
      },
      {
        'id': 'menu_3',
        'name': 'Cơm chiên rau củ kiểu Việt',
        'calories': 540,
        'prep_minutes': 25,
        'used_ingredients': [if (has('Cà rốt')) 'Cà rốt', if (has('Bông cải xanh')) 'Bông cải xanh', if (has('Rau chân vịt')) 'Rau chân vịt'],
        'missing_ingredients': ['Cơm nguội'],
      },
    ];

    return ideas
        .map(MenuSuggestionDto.fromJson)
        .where((m) => m.usedIngredients.isNotEmpty)
        .toList();
  }
}
