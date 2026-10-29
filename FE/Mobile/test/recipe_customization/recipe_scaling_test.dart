// test/recipe_customization/recipe_scaling_test.dart
// "Nấu cho N người": the §4.1 rounding table, unit classes, minimums and
// kg / lít normalisation.
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/features/recipe/domain/recipe_scaling.dart';

String scaled(double? q, String unit, int from, int to) =>
    scaleAmount(q, unit, to / from).text;

void main() {
  group('worked examples (§4.1)', () {
    final cases = <(String, double?, String, int, int, String)>[
      ('Bún tươi 400 g', 400, 'g', 2, 3, '600 g'),
      ('250 g', 250, 'g', 2, 3, '375 g'),
      ('Cà chua 4 quả', 4, 'quả', 2, 3, '6 quả'),
      ('Củ cải trắng 1 củ', 1, 'củ', 2, 3, '1,5 củ'),
      ('Hành tím 3 củ', 3, 'củ', 2, 3, '4,5 củ'),
      ('Tỏi 3 tép', 3, 'tép', 2, 3, '5 tép'),
      ('Mắm ruốc 1 muỗng canh', 1, 'muỗng canh', 2, 3, '1,5 muỗng canh'),
      ('Bún tươi 400 g ×2,5', 400, 'g', 2, 5, '1 kg'),
      ('Đậu hũ 300 g ×3,5', 300, 'g', 2, 7, '1,05 kg'),
      ('Đậu hũ 200 g 3→2', 200, 'g', 3, 2, '135 g'),
      ('Bông cải 0,5 bông 2→1', 0.5, 'bông', 2, 1, '0,5 bông'),
      ('Sữa đậu nành 250 ml 1→5', 250, 'ml', 1, 5, '1,25 lít'),
      ('Hạt nêm vừa ăn', null, 'vừa ăn', 2, 5, 'vừa ăn'),
    ];
    for (final (label, q, unit, from, to, expected) in cases) {
      test(label, () => expect(scaled(q, unit, from, to), expected));
    }

    test('7 g × 1,5 → 11 g', () {
      expect(scaleAmount(7, 'g', 1.5).text, '11 g');
    });
  });

  group('unit classes', () {
    test('mass steps by size; kg below 1 kg shows grams', () {
      expect(scaleAmount(3, 'g', 1.5).text, '4,5 g'); // < 10 → 0,5
      expect(scaleAmount(30, 'g', 1.5).text, '45 g'); // < 100 → 1
      expect(scaleAmount(33, 'g', 1.5).text, '50 g'); // 49,5 → 50
      expect(scaleAmount(0.5, 'kg', 1).text, '0,5 kg', reason: 'as written');
      expect(scaleAmount(0.5, 'kg', 1.5).text, '750 g');
      expect(scaleAmount(0.4, 'KG', 3).text, '1,2 kg',
          reason: 'case-insensitive');
      expect(scaleAmount(998, 'g', 1.001).text, '1 kg',
          reason: 'rounded up to 1000 g');
    });

    test('volume: ml, l and lít', () {
      expect(scaleAmount(100, 'ml', 1.5).text, '150 ml');
      expect(scaleAmount(1, 'lít', 2).text, '2 lít');
      expect(scaleAmount(1, 'l', 0.5).text, '500 ml');
    });

    test('whole-only units round half up, at least 1', () {
      expect(scaleAmount(1, 'tép', 0.5).text, '1 tép');
      expect(scaleAmount(8, 'lá', 1.5).text, '12 lá');
      expect(scaleAmount(1, 'ổ', 2.5).text, '3 ổ');
    });

    test('halvable and spoon units: nearest 0,5, at least 0,5', () {
      expect(scaleAmount(1, 'chén', 0.2).text, '0,5 chén');
      expect(scaleAmount(1, 'muỗng cà phê', 1.3).text, '1,5 muỗng cà phê');
      expect(scaleAmount(2, 'thìa', 1 / 3).text, '0,5 thìa');
    });

    test('other units: < 10 → 0,5 step, else integer', () {
      expect(scaleAmount(3, 'nhúm', 1.5).text, '4,5 nhúm');
      expect(scaleAmount(8, 'nhúm', 1.5).text, '12 nhúm');
      expect(scaleAmount(2, '', 0.1).text, '0,5');
    });

    test('factor 1 keeps the amount exactly as written', () {
      expect(scaleAmount(1050, 'g', 1).text, '1.050 g');
      expect(scaleAmount(0.25, 'quả', 1).text, '0,25 quả');
    });
  });
}
