// lib/core/network/api_exception.dart
import 'package:dio/dio.dart';

/// The only error type features need to understand. Messages are user-facing (vi).
class ApiException implements Exception {
  const ApiException({required this.message, this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  bool get isNetwork => code == 'network' || code == 'timeout';
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() =>
      'ApiException(status: $statusCode, code: $code): $message';
}

/// Guest has used every free AI question (HTTP 402 / code `trial_exhausted`).
class TrialExhaustedException extends ApiException {
  const TrialExhaustedException()
      : super(
          message: 'Bạn đã dùng hết lượt hỏi miễn phí.',
          statusCode: 402,
          code: 'trial_exhausted',
        );
}

/// Maps any Dio failure to an [ApiException] with a Vietnamese message.
ApiException mapDioException(DioException err) {
  final existing = err.error;
  if (existing is ApiException) return existing;

  switch (err.type) {
    case DioExceptionType.connectionError:
      return const ApiException(
        message: 'Không có kết nối mạng. Kiểm tra Wi-Fi hoặc dữ liệu di động.',
        code: 'network',
      );
    case DioExceptionType.cancel:
      return const ApiException(
          message: 'Yêu cầu đã bị huỷ.', code: 'cancelled');
    case DioExceptionType.badCertificate:
      return const ApiException(
          message: 'Kết nối không an toàn.', code: 'bad_certificate');
    case DioExceptionType.badResponse:
    case DioExceptionType.unknown:
      return _fromResponse(err);
    default:
      // connection/send/receive timeouts (+ transformTimeout on newer dio).
      if (err.type.name.endsWith('Timeout')) {
        return const ApiException(
          message: 'Máy chủ phản hồi chậm. Vui lòng thử lại.',
          code: 'timeout',
        );
      }
      return _fromResponse(err);
  }
}

ApiException _fromResponse(DioException err) {
  final status = err.response?.statusCode;
  final data = err.response?.data;
  String? code;
  String? message;
  if (data is Map<String, dynamic>) {
    code = data['code']?.toString();
    message = (data['message'] ?? data['title'])?.toString();
  }
  if (status == 402 || code == 'trial_exhausted') {
    return const TrialExhaustedException();
  }
  return ApiException(
    message: message ?? _fallbackMessage(status),
    statusCode: status,
    code: code,
  );
}

String _fallbackMessage(int? status) => switch (status) {
      400 => 'Dữ liệu gửi lên chưa hợp lệ.',
      401 => 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
      403 => 'Bạn không có quyền thực hiện thao tác này.',
      404 => 'Không tìm thấy dữ liệu.',
      429 => 'Bạn thao tác quá nhanh. Thử lại sau ít phút.',
      final int s when s >= 500 =>
        'Máy chủ đang gặp sự cố. Vui lòng thử lại sau.',
      _ => 'Đã có lỗi xảy ra. Vui lòng thử lại.',
    };

/// Runs an API call and rethrows failures as [ApiException].
Future<T> guardApi<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on DioException catch (e) {
    throw mapDioException(e);
  }
}

/// User-facing text for any error object.
String describeError(Object error) {
  if (error is ApiException) return error.message;
  if (error is DioException) return mapDioException(error).message;
  return 'Đã có lỗi xảy ra. Vui lòng thử lại.';
}
