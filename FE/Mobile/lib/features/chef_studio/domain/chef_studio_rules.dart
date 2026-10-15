// lib/features/chef_studio/domain/chef_studio_rules.dart
//
// Form rules for chef studio. The forms show these messages inline and the
// mock server enforces the same ones (400), like the real BE should.
import '../../../core/utils/formatters.dart';
import '../../chef/domain/entities/chef.dart';

bool isHttpsUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null && uri.scheme == 'https' && uri.host.contains('.');
}

abstract final class ServiceRules {
  static const minTitle = 8;
  static const maxTitle = 120;
  static const minPrice = 50000;
  static const maxPrice = 50000000;
  static const minMinutes = 15;
  static const maxMinutes = 240;
  static const maxDescription = 500;

  static String? title(String value) {
    final n = value.trim().length;
    return n < minTitle || n > maxTitle
        ? 'Tên dịch vụ từ $minTitle đến $maxTitle ký tự.'
        : null;
  }

  static String? price(int? value) =>
      value == null || value < minPrice || value > maxPrice
          ? 'Giá từ ${formatVnd(minPrice)} đến ${formatVnd(maxPrice)}.'
          : null;

  static String? minutes(ServiceType type, int? value) =>
      type == ServiceType.consult &&
              (value == null || value < minMinutes || value > maxMinutes)
          ? 'Thời lượng từ $minMinutes đến $maxMinutes phút.'
          : null;

  static String? description(String value) =>
      value.trim().length > maxDescription
          ? 'Mô tả tối đa $maxDescription ký tự.'
          : null;

  static String? contentUrl(ServiceType type, String value) =>
      type.isPackage && !isHttpsUrl(value)
          ? 'Nhập đường dẫn https:// tới nội dung khoá học / thực đơn.'
          : null;
}

abstract final class ChefProfileRules {
  static const minBio = 50;
  static const maxBio = 1000;

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

abstract final class ConsultationRules {
  static const minDeclineReason = 10;
  static const minNotes = 20;

  /// "Bắt đầu buổi tư vấn" opens this long before the appointment.
  static const startWindow = Duration(minutes: 15);

  static String? declineReason(String value) =>
      value.trim().length < minDeclineReason
          ? 'Lý do cần ít nhất $minDeclineReason ký tự.'
          : null;

  static String? notes(String value) => value.trim().length < minNotes
      ? 'Ghi chú cần ít nhất $minNotes ký tự.'
      : null;

  static bool canStart(DateTime startAt, DateTime now) =>
      !now.isBefore(startAt.subtract(startWindow));
}
