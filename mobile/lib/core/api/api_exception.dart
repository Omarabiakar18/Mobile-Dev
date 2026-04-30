import 'package:dio/dio.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.code, this.message, [this.details]);

  final int statusCode;
  final String code;
  final String message;
  final Object? details;

  @override
  String toString() => 'ApiException($statusCode $code): $message';

  /// Pulls the uniform `{ error: { code, message, details? } }` shape from a
  /// failed Dio response. Falls back to a generic message on shape mismatch
  /// or network errors.
  static ApiException fromDio(DioException e) {
    final r = e.response;
    if (r != null && r.data is Map) {
      final err = (r.data as Map)['error'];
      if (err is Map) {
        return ApiException(
          r.statusCode ?? 0,
          err['code']?.toString() ?? 'UNKNOWN',
          err['message']?.toString() ?? 'Something went wrong',
          err['details'],
        );
      }
    }
    return ApiException(
      r?.statusCode ?? 0,
      'NETWORK_ERROR',
      e.message ?? 'Network error',
    );
  }
}
