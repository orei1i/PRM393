// lib/features/commerce/presentation/widgets/mock_qr_view.dart
import 'package:flutter/material.dart';

/// A QR-looking grid drawn from [data] (same input → same picture). Not
/// scannable: it stands in for the PaymentOS QR in mock builds.
class MockQrView extends StatelessWidget {
  const MockQrView({super.key, required this.data, this.size = 200});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Mã QR mô phỏng',
      image: true,
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(10),
        // QR codes need a light quiet zone, dark theme included.
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: CustomPaint(painter: _QrPainter(data)),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.data);

  final String data;

  static const _n = 25;

  bool _inFinder(int x, int y) {
    bool box(int ox, int oy) => x >= ox && x < ox + 7 && y >= oy && y < oy + 7;
    return box(0, 0) || box(_n - 7, 0) || box(0, _n - 7);
  }

  bool _finderDark(int x, int y) {
    int local(int v) => v >= _n - 7 ? v - (_n - 7) : v;
    final lx = local(x), ly = local(y);
    final ring = lx == 0 || lx == 6 || ly == 0 || ly == 6;
    final core = lx >= 2 && lx <= 4 && ly >= 2 && ly <= 4;
    return ring || core;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / _n;
    final paint = Paint()..color = const Color(0xFF111111);
    // xorshift seeded from the text: deterministic, no dart:math Random
    // (its sequence isn't guaranteed across platforms).
    var seed = data.codeUnits
        .fold<int>(0x2545F491, (a, b) => (a * 31 + b) & 0x7fffffff);
    if (seed == 0) seed = 1;
    bool next() {
      seed ^= (seed << 13) & 0x7fffffff;
      seed ^= seed >> 17;
      seed ^= (seed << 5) & 0x7fffffff;
      return seed % 100 < 47;
    }

    for (var y = 0; y < _n; y++) {
      for (var x = 0; x < _n; x++) {
        final dark = _inFinder(x, y) ? _finderDark(x, y) : next();
        if (dark) {
          canvas.drawRect(
              Rect.fromLTWH(x * cell, y * cell, cell + 0.4, cell + 0.4), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data;
}
