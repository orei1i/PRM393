// lib/features/meal_planner/data/mock/body_measurement_mock_data.dart
//
// Seed weigh-ins (`health_metric_logs`) for the demo accounts, in the
// GET /health-profile/me/metrics wire format, dated relative to [now] (the
// planner clock when the account's mock store is created).
import '../../../../core/session/mock_accounts.dart';

/// `(days ago, kg, waist cm, body fat %, source)`, oldest first.
typedef _Seed = (int, double, double?, double?, String);

/// Minh Anh (172 cm): eight weeks of check-ins after her first profile save;
/// the last one 8 days ago, so "Cập nhật cân nặng" is due on a weekly
/// reminder.
const List<_Seed> _minhAnhSeeds = [
  (56, 65.0, 71, 27.8, 'profile'),
  (42, 65.2, null, null, 'check_in'),
  (28, 65.3, 70.5, null, 'check_in'),
  (21, 65.6, null, null, 'check_in'),
  (14, 65.8, null, 27.0, 'check_in'),
  (8, 66.0, 70, null, 'check_in'),
];

/// Lê Quang Tâm (168 cm): only the row of his profile save.
const List<_Seed> _tamSeeds = [(20, 63.0, null, null, 'profile')];

/// Seed rows for [userId], newest first; none for other accounts (a new
/// account gets its first row from its first profile save).
List<Map<String, Object?>> mockBodyMeasurementsFor(
    String? userId, DateTime now) {
  final (List<_Seed> seeds, double heightCm, String prefix) = switch (userId) {
    _ when userId == minhAnhAccount.userId => (_minhAnhSeeds, 172.0, 'ma'),
    _ when userId == tamChefAccount.userId => (_tamSeeds, 168.0, 'tam'),
    _ => (const <_Seed>[], 0.0, ''),
  };
  final meters = heightCm / 100;
  return [
    for (final (i, (daysAgo, kg, waist, fat, source)) in seeds.indexed)
      {
        'id': 'm_${prefix}_${i + 1}',
        'weightKg': kg,
        'heightCm': heightCm,
        'bmi': (kg / (meters * meters) * 10).roundToDouble() / 10,
        if (waist != null) 'waistCm': waist,
        if (fat != null) 'bodyFatPct': fat,
        'source': source,
        'loggedAt':
            now.subtract(Duration(days: daysAgo)).toUtc().toIso8601String(),
      },
  ].reversed.toList();
}
