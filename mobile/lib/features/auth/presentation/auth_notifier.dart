import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../data/auth_api.dart';
import '../data/auth_models.dart';

/// AuthState lifecycle:
///   - loading: initial bootstrap (reading tokens, optionally calling /auth/me)
///   - data(null): signed out
///   - data(user): signed in
///   - error: failed bootstrap (rare; also surfaces login/register errors)
class AuthNotifier extends StateNotifier<AsyncValue<AppUser?>> {
  AuthNotifier(this._ref) : super(const AsyncValue.loading()) {
    _bootstrap();
  }
  final Ref _ref;

  TokenStorage get _tokens => _ref.read(tokenStorageProvider);
  AuthApi get _api => _ref.read(authApiProvider);
  DioClient get _client => _ref.read(dioClientProvider);

  Future<void> _bootstrap() async {
    await _tokens.ensureFreshOnFirstLaunch();
    _client.onAuthFailure = _onAuthFailure;

    final access = await _tokens.readAccess();
    if (access == null) {
      state = const AsyncValue.data(null);
      return;
    }
    try {
      final user = await _api.me();
      state = AsyncValue.data(user);
    } catch (_) {
      // Either token expired or backend down — treat as signed-out for now
      // (the dio interceptor will have already attempted refresh).
      await _tokens.clear();
      state = const AsyncValue.data(null);
    }
  }

  Future<void> login({required String email, required String password}) async {
    state = const AsyncValue.loading();
    try {
      final result = await _api.login(email: email, password: password);
      await _tokens.saveTokens(access: result.accessToken, refresh: result.refreshToken);
      state = AsyncValue.data(result.user);
    } on ApiException catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String name,
    String? phone,
  }) async {
    state = const AsyncValue.loading();
    try {
      final result = await _api.register(
        email: email,
        password: password,
        name: name,
        phone: phone,
      );
      await _tokens.saveTokens(access: result.accessToken, refresh: result.refreshToken);
      state = AsyncValue.data(result.user);
    } on ApiException catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> logout() async {
    final refresh = await _tokens.readRefresh();
    if (refresh != null) {
      try {
        await _api.logout(refresh);
      } catch (_) {/* best-effort */}
    }
    await _tokens.clear();
    state = const AsyncValue.data(null);
  }

  void _onAuthFailure() {
    _tokens.clear();
    state = const AsyncValue.data(null);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AsyncValue<AppUser?>>((ref) {
  return AuthNotifier(ref);
});

/// Convenience: true once bootstrap is done AND a user is present.
final isSignedInProvider = Provider<bool>((ref) {
  final auth = ref.watch(authProvider);
  return auth.maybeWhen(data: (u) => u != null, orElse: () => false);
});
