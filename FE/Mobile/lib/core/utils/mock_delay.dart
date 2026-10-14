// lib/core/utils/mock_delay.dart
import 'dart:math';

final _random = Random();

/// Simulated network latency for Mock repositories: [baseMs] + 0–300 ms jitter.
Future<void> mockDelay([int baseMs = 700]) =>
    Future<void>.delayed(Duration(milliseconds: baseMs + _random.nextInt(300)));
