// tool/brand/render_brand_assets_test.dart
//
// (Re)writes every launcher-icon and splash PNG from the painted VeganLife
// mark (`lib/core/widgets/app_logo.dart`). Lives outside `test/`, so the
// normal suite never runs it. From FE/Mobile:
//
//   flutter test tool/brand/render_brand_assets_test.dart
//
// then commit the PNGs `git status` lists. No dependency: the PNG encoder
// below uses dart:io's zlib.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/widgets/app_logo.dart';

const _res = 'android/app/src/main/res';
const _ios = 'ios/Runner/Assets.xcassets';

/// Android density buckets → scale of 1 dp.
const _densities = {
  'mdpi': 1.0,
  'hdpi': 1.5,
  'xhdpi': 2.0,
  'xxhdpi': 3.0,
  'xxxhdpi': 4.0,
};

typedef _Draw = void Function(Canvas canvas, Rect rect);

/// Legacy launcher icon (API < 26): rounded square, transparent corners.
void _legacyIcon(Canvas canvas, Rect rect) =>
    VeganLifeLeafPainter.paintBadge(canvas, rect.deflate(rect.width * 2 / 48),
        circle: false, cornerRadius: 0.22);

/// Adaptive-icon foreground: white leaf inside the 66 dp safe zone of the
/// 108 dp canvas (the background is `@color/ic_launcher_background`).
void _adaptiveForeground(Canvas canvas, Rect rect) =>
    VeganLifeLeafPainter.paintBadge(canvas, rect,
        background: false, leafScale: 0.56);

/// Splash logo: the round badge, edge to edge.
void _roundBadge(Canvas canvas, Rect rect) =>
    VeganLifeLeafPainter.paintBadge(canvas, rect);

/// Android 12 splash icon: 288 dp canvas, badge within the central 192 dp
/// circle the system keeps.
void _android12Splash(Canvas canvas, Rect rect) =>
    VeganLifeLeafPainter.paintBadge(
        canvas,
        Rect.fromCenter(
            center: rect.center,
            width: rect.width * 190 / 288,
            height: rect.height * 190 / 288));

/// iOS app icon: full-bleed square (iOS rounds it), opaque.
void _iosIcon(Canvas canvas, Rect rect) =>
    VeganLifeLeafPainter.paintBadge(canvas, rect,
        circle: false, cornerRadius: 0, leafScale: 0.6);

Future<void> _write(String path, int px, _Draw draw,
    {bool alpha = true}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final rect = Rect.fromLTWH(0, 0, px.toDouble(), px.toDouble());
  draw(canvas, rect);
  final image = await recorder.endRecording().toImage(px, px);
  final data =
      await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  image.dispose();
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(
      _encodePng(px, px, data!.buffer.asUint8List(), alpha: alpha));
}

// ------------------------------------------------------------- PNG encoder --

List<int> _encodePng(int width, int height, Uint8List rgba,
    {required bool alpha}) {
  final channels = alpha ? 4 : 3;
  final raw = Uint8List(height * (1 + width * channels));
  var o = 0;
  for (var y = 0; y < height; y++) {
    raw[o++] = 0; // filter: none
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      raw[o++] = rgba[i];
      raw[o++] = rgba[i + 1];
      raw[o++] = rgba[i + 2];
      if (alpha) raw[o++] = rgba[i + 3];
    }
  }
  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, alpha ? 6 : 2) // RGBA : RGB
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  return [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    ..._chunk('IHDR', header.buffer.asUint8List()),
    ..._chunk('IDAT', ZLibCodec(level: 9).encode(raw)),
    ..._chunk('IEND', const []),
  ];
}

List<int> _chunk(String type, List<int> data) {
  final typeBytes = type.codeUnits;
  final length = ByteData(4)..setUint32(0, data.length);
  final crc = ByteData(4)..setUint32(0, _crc32([...typeBytes, ...data]));
  return [
    ...length.buffer.asUint8List(),
    ...typeBytes,
    ...data,
    ...crc.buffer.asUint8List(),
  ];
}

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >>> 8);
  }
  return c ^ 0xFFFFFFFF;
}

// ------------------------------------------------------------------ assets --

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('render launcher icons and splash logos', () async {
    for (final MapEntry(key: bucket, value: scale) in _densities.entries) {
      await _write('$_res/mipmap-$bucket/ic_launcher.png', (48 * scale).round(),
          _legacyIcon);
      await _write('$_res/drawable-$bucket/ic_launcher_foreground.png',
          (108 * scale).round(), _adaptiveForeground);
      await _write('$_res/drawable-$bucket/splash_logo.png',
          (96 * scale).round(), _roundBadge);
      await _write('$_res/drawable-$bucket/android12splash.png',
          (288 * scale).round(), _android12Splash);
    }

    for (final (name, px) in [
      ('LaunchImage.png', 120),
      ('LaunchImage@2x.png', 240),
      ('LaunchImage@3x.png', 360),
    ]) {
      await _write('$_ios/LaunchImage.imageset/$name', px, _roundBadge);
    }

    for (final (points, scale) in [
      (20.0, 1),
      (20.0, 2),
      (20.0, 3),
      (29.0, 1),
      (29.0, 2),
      (29.0, 3),
      (40.0, 1),
      (40.0, 2),
      (40.0, 3),
      (60.0, 2),
      (60.0, 3),
      (76.0, 1),
      (76.0, 2),
      (83.5, 2),
      (1024.0, 1),
    ]) {
      final label = points == points.roundToDouble()
          ? points.toInt().toString()
          : points.toString();
      // App Store icons must not have an alpha channel.
      await _write(
          '$_ios/AppIcon.appiconset/Icon-App-${label}x$label@${scale}x.png',
          (points * scale).round(),
          _iosIcon,
          alpha: false);
    }
  });
}
