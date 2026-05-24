import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/secure_storage.dart';
import 'base_url.dart';

/// Dio instance with:
///   1. Bearer token attached on every request
///   2. On 401: single-flight refresh that any concurrent caller can await
///   3. After refresh, the original request retries once with the new token
///   4. If refresh itself fails (or returns null), force-signs the user out
///   5. Cold-start transient retry on GETs: connection / timeout errors are
///      retried twice with 600ms + 1500ms backoff. Fixes the "API error"
///      flash on first launch when the TCP/TLS connection hasn't warmed up
///      yet (especially over `adb reverse` tunnels). POST/PATCH/DELETE are
///      NEVER retried — they aren't idempotent and a duplicate submit would
///      create dupes.
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
    // Order matters. dio fires onResponse in REVERSE order of insertion
    // (last-added runs first), so we add:
    //
    //   1. _TransientRetryInterceptor — retries connection/timeout errors
    //      (only fires for `onError`, not `onResponse`).
    //   2. _Non2xxResponseInterceptor — catches non-401 4xx/5xx responses
    //      and converts them into DioException(badResponse), so every API
    //      method's `on DioException catch (e)` block routes through
    //      ApiException.fromDio. Without this, validateStatus (s < 500)
    //      lets 4xx through to callers that do `r.data!['data']['x']` on a
    //      `{error:{...}}` payload, crashing on null deref. Added before
    //      _AuthInterceptor so auth's onResponse 401-handling fires FIRST
    //      on the response chain (reverse insertion order).
    //   3. _AuthInterceptor — attaches the bearer token on request, and on
    //      response detects 401s, runs single-flight refresh, and re-issues
    //      the original request with the new token.
    //
    // The retry interceptor reuses `dio` itself for the retried call so
    // the retried request goes through every other interceptor and
    // inherits the project's validateStatus / contentType / responseType
    // — otherwise the response shape arrives as a raw JSON string and
    // callers like `cars_api.list()` get an empty list out of
    // `r.data?['data']?['cars']`.
    dio.interceptors.add(_TransientRetryInterceptor(this));
    dio.interceptors.add(_Non2xxResponseInterceptor());
    dio.interceptors.add(_AuthInterceptor(this));
  }

  late final Dio dio;
  final TokenStorage _tokens;
  TokenStorage get tokens => _tokens;

  /// Hook the auth notifier sets on sign-in success / sign-out.
  /// Used so the interceptor can force a logout on a hard 401.
  void Function()? onAuthFailure;
}

/// Retries idempotent GET requests on transient network errors. Caps at
/// two retries (so three attempts total) with exponential backoff so the
/// user never sees the cold-start TCP race translate into a red banner.
///
/// What we retry:
///   - DioExceptionType.connectionTimeout  — TCP handshake didn't complete
///   - DioExceptionType.sendTimeout         — request body upload stalled
///   - DioExceptionType.receiveTimeout      — server stopped sending bytes
///   - DioExceptionType.connectionError     — host unreachable / no route
///
/// What we DO NOT retry:
///   - Any non-GET request (writes aren't idempotent — POST twice = dupes)
///   - DioExceptionType.badResponse with a 4xx/5xx — that's a real error
///   - DioExceptionType.cancel               — caller explicitly bailed
///   - DioExceptionType.badCertificate       — pointless to retry
class _TransientRetryInterceptor extends Interceptor {
  _TransientRetryInterceptor(this._client);

  /// We re-issue the retried request through the parent DioClient's own dio
  /// instance so it picks up auth interceptors, validateStatus, content-type
  /// negotiation, and JSON response parsing. Creating a bare `Dio()` here
  /// returned `Response<dynamic>` whose `data` was a raw string — callers
  /// got empty lists out of `r.data?['data']?['cars']` and the home screen
  /// fell to its empty state on cold-start. That bug was real and observed
  /// during QA on 2026-05-04.
  final DioClient _client;

  static const int _maxRetries = 2;
  static const List<Duration> _backoff = [
    Duration(milliseconds: 600),
    Duration(milliseconds: 1500),
  ];

  static const _retryKey = '_retryAttempt';

  bool _isTransient(DioExceptionType type) {
    return type == DioExceptionType.connectionTimeout ||
        type == DioExceptionType.sendTimeout ||
        type == DioExceptionType.receiveTimeout ||
        type == DioExceptionType.connectionError;
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final req = err.requestOptions;
    final method = req.method.toUpperCase();
    final attempt = (req.extra[_retryKey] as int?) ?? 0;

    if (method != 'GET' ||
        !_isTransient(err.type) ||
        attempt >= _maxRetries) {
      handler.next(err);
      return;
    }

    // Wait the backoff window, then re-issue via the same dio instance so
    // every interceptor (auth in particular) gets to do its job, AND the
    // BaseOptions-level validateStatus / contentType / responseType are
    // inherited so the response data is parsed as JSON.
    //
    // To avoid infinite recursion, we copy req.extra so the bumped attempt
    // counter rides along and this interceptor bails on the next loop once
    // _maxRetries is hit.
    await Future<void>.delayed(_backoff[attempt]);

    try {
      final retried = await _client.dio.request<dynamic>(
        req.path,
        data: req.data,
        queryParameters: req.queryParameters,
        options: Options(
          method: req.method,
          headers: Map<String, dynamic>.from(req.headers),
          contentType: req.contentType,
          responseType: req.responseType,
          extra: {...req.extra, _retryKey: attempt + 1},
        ),
      );
      handler.resolve(retried);
    } on DioException catch (e) {
      // Hand the latest failure back so onError chains correctly.
      handler.next(e);
    }
  }
}

/// Converts non-401 4xx/5xx responses into `DioException(badResponse)` so
/// every API method's existing `on DioException catch (e) => throw
/// ApiException.fromDio(e)` block converts cleanly to a user-facing
/// error. Without this, [DioClient]'s `validateStatus: s < 500` lets 4xx
/// pass through and callers force-unwrap `r.data!['data']['x']` against a
/// `{error:{...}}` payload, hitting a null deref at runtime — a real bug
/// surfaced by the 2026-05-24 backend audit.
///
/// 401 is intentionally pass-through here: the next interceptor
/// (_AuthInterceptor) catches it in onResponse, runs single-flight refresh,
/// and resolves the response. If refresh fails, _AuthInterceptor propagates
/// the 401 down the chain and this interceptor (which runs AFTER auth on
/// the response path, per reverse-insertion order) then rejects it like
/// any other 4xx.
class _Non2xxResponseInterceptor extends Interceptor {
  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final status = response.statusCode;
    if (status != null && status >= 400 && status != 401) {
      handler.reject(DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'HTTP $status',
      ));
      return;
    }
    handler.next(response);
  }
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._client);
  final DioClient _client;

  /// Single-flight refresh: when one request triggers a refresh, every other
  /// concurrent 401 awaits this same future and reuses the resulting access
  /// token. Without this, parallel home-screen requests race and all but the
  /// first see `_refreshing=true`, return null, and force a sign-out.
  Future<String?>? _refreshInFlight;

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
      final newAccess = await _refreshOnce();
      if (newAccess != null) {
        final retried = await _retryWithToken(response.requestOptions, newAccess);
        if (retried != null) {
          handler.resolve(retried);
          return;
        }
      }
      _client.onAuthFailure?.call();
    }
    handler.next(response);
  }

  /// Returns a fresh access token (caller is expected to retry with it),
  /// or null if refresh failed (caller should treat as hard auth failure).
  /// Concurrent callers share the same in-flight request.
  Future<String?> _refreshOnce() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<String?> _doRefresh() async {
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
      return access;
    } catch (_) {
      return null;
    }
  }

  Future<Response?> _retryWithToken(RequestOptions original, String accessToken) async {
    try {
      final retryOptions = Options(
        method: original.method,
        headers: {...original.headers, 'Authorization': 'Bearer $accessToken'},
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
    }
  }
}

final dioClientProvider = Provider<DioClient>((ref) {
  return DioClient(ref.watch(tokenStorageProvider));
});
