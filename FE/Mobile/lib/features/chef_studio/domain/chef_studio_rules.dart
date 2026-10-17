// lib/features/chef_studio/domain/chef_studio_rules.dart
//
// Form rules for chef studio ("Hồ sơ & bảng giá", knowledge docs). The forms
// show these messages inline and the mock server enforces the same ones
// (400), like the real BE should.
import '../../../core/utils/formatters.dart';

bool isHttpsUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null && uri.scheme == 'https' && uri.host.contains('.');
}

abstract final class ChefProfileRules {
  static const minBio = 50;
  static const maxBio = 1000;

  /// Listed price per day ("Giá mỗi ngày", "Giá có phản hồi mỗi ngày").
  static const minDayPrice = 30000;
  static const maxDayPrice = 5000000;

  /// Same bounds as a booking's plan (`BookingRules`).
  static const minPlanDays = 3;
  static const maxPlanDays = 30;

  static String? dayPrice(int? value) => value == null ||
          value < minDayPrice ||
          value > maxDayPrice
      ? 'Giá mỗi ngày từ ${formatVnd(minDayPrice)} đến ${formatVnd(maxDayPrice)}.'
      : null;

  static String? planDays(int? min, int? max) {
    if (min == null || max == null) return 'Nhập số ngày tối thiểu và tối đa.';
    if (min < minPlanDays || max > maxPlanDays) {
      return 'Số ngày từ $minPlanDays đến $maxPlanDays.';
    }
    return min > max ? 'Số ngày tối thiểu không được lớn hơn tối đa.' : null;
  }

  static String? specialty(String? value) =>
      value == null || value.isEmpty ? 'Chọn chuyên môn chính.' : null;

  static String? bio(String value) {
    final n = value.trim().length;
    return n < minBio || n > maxBio
        ? 'Giới thiệu từ $minBio đến $maxBio ký tự.'
        : null;
  }
}

abstract final class KnowledgeDocRules {
  static const minTitle = 10;
  static const maxTitle = 200;

  static String? title(String value) {
    final n = value.trim().length;
    return n < minTitle || n > maxTitle
        ? 'Tiêu đề từ $minTitle đến $maxTitle ký tự.'
        : null;
  }

  static String? fileUrl(String value) =>
      isHttpsUrl(value) ? null : 'Nhập đường dẫn https:// tới tệp tài liệu.';
}
