// lib/core/network/api_envelope.dart
import 'api_exception.dart';
import '../utils/json_helpers.dart';

/// The ASP.NET Core API wraps every payload in `ApiResponse<T>`:
///
/// ```json
/// { "success": true, "message": null, "data": { … }, "statusCode": 200 }
/// ```
///
/// Returns `data` for successful envelopes, throws [ApiException] for
/// `success: false`, and passes any other body through unchanged (SSE
/// streams, files, endpoints that are not wrapped).
Object? unwrapEnvelope(Object? body) {
  if (body is! Map<String, dynamic>) return body;
  final looksLikeEnvelope = body.containsKey('success') &&
      (body.containsKey('data') || body.containsKey('statusCode'));
  if (!looksLikeEnvelope) return body;

  if (body['success'] == false) {
    final status =
        body['statusCode'] == null ? null : readInt(body['statusCode']);
    throw ApiException(
      message:
          body['message']?.toString() ?? 'Đã có lỗi xảy ra. Vui lòng thử lại.',
      statusCode: status,
      code: body['code']?.toString(),
    );
  }
  return body['data'];
}
