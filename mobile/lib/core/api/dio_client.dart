import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/secure_storage.dart';
import 'base_url.dart';

/// Dio instance with:
///   1. Bearer token attached on every request
///   2. On 401: try the refresh endpoint once, retry the failed request
///   3. On second 401: bubble up — caller (auth notifier) should sign the user out
class DioClient {
  DioClient(this._tokens) {
    dio = Dio(
      BaseOptions(
        baseUrl: apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        contentType: 'application/json',
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    dio.interceptors.add(_AuthInterceptor(this));
  }

  late final Dio dio;
  final TokenStorage _tokens;
  TokenStorage get tokens => _tokens;

  /// Hook the auth notifier sets on sign-in success / sign-out.
  /// Used so the interceptor can force a logout on a hard 401.
  void Function()? onAuthFailure;
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._client);
  final DioClient _client;
  bool _refreshing = false;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _client.tokens.readAccess();
    if (token != null && options.headers['Authorization'] == null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onResponse(Response response, ResponseInterceptorHandler handler) async {
    if (response.statusCode == 401 && response.requestOptions.path != '/auth/refresh') {
      final retried = await _tryRefreshAndRetry(response.requestOptions);
      if (retried != null) {
        handler.resolve(retried);
        return;
      }
      _client.onAuthFailure?.call();
    }
    handler.next(response);
  }

  Future<Response?> _tryRefreshAndRetry(RequestOptions original) async {
    if (_refreshing) return null;
    _refreshing = true;
    try {
      final refresh = await _client.tokens.readRefresh();
      if (refresh == null) return null;

      final r = await _client.dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refresh},
        options: Options(headers: {'Authorization': null}),
      );
      if (r.statusCode != 200) return null;

      final data = r.data?['data'] as Map<String, dynamic>?;
      final access = data?['accessToken'] as String?;
      final newRefresh = data?['refreshToken'] as String?;
      if (access == null || newRefresh == null) return null;

      await _client.tokens.saveTokens(access: access, refresh: newRefresh);

      // Retry the original request with the new token
      final retryOptions = Options(
        method: original.method,
        headers: {...original.headers, 'Authorization': 'Bearer $access'},
        contentType: original.contentType,
        responseType: original.responseType,
      );
      return await _client.dio.request(
        original.path,
        data: original.data,
        queryParameters: original.queryParameters,
        options: retryOptions,
      );
    } catch (_) {
      return null;
    } finally {
      _refreshing = false;
    }
  }
}

final dioClientProvider = Provider<DioClient>((ref) {
  return DioClient(ref.watch(tokenStorageProvider));
});
