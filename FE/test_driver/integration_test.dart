import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final screenshots = Directory(
    '${Directory.current.path}${Platform.pathSeparator}build${Platform.pathSeparator}screenshots',
  );
  await screenshots.create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      await File(
        '${screenshots.path}${Platform.pathSeparator}$name.png',
      ).writeAsBytes(bytes);
      return true;
    },
  );
}
