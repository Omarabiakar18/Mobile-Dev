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
  /// or network errors. Network/timeout failures (no server response at all)
  /// get a user-friendly message — never the raw Dio "Connection error" text.
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

    // No (usable) response. This is the transient-network-error path — by
    // the time we get here the dio interceptor has already retried two
    // times so it's not a cold-start flash. Surface friendly copy keyed
    // off the dio error type so the user sees what's actually wrong.
    final friendlyMessage = _friendlyNetworkMessage(e.type);
    return ApiException(r?.statusCode ?? 0, 'NETWORK_ERROR', friendlyMessage);
  }

  /// Maps a Dio error type to a one-line message a non-engineer can read.
  /// Intentionally short — the screen-level UI adds its own headline (e.g.
  /// "Couldn't load") so we only need the *reason*.
  static String _friendlyNetworkMessage(DioExceptionType type) {
    switch (type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return "The server's taking too long to respond. Check your connection.";
      case DioExceptionType.connectionError:
        return "Can't reach the server. Make sure you're online.";
      case DioExceptionType.badCertificate:
        return 'The server certificate is invalid. Cannot continue.';
      case DioExceptionType.cancel:
        return 'Request was cancelled.';
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        return 'Something went wrong. Please try again.';
    }
  }
}
