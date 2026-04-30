import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Backed by iOS Keychain. Survives app uninstall by default — we clear
/// on first launch in main() to avoid stale-token surprises after reinstall.
class TokenStorage {
  TokenStorage(this._storage);
  final FlutterSecureStorage _storage;

  static const _kAccess = 'garage_access_token';
  static const _kRefresh = 'garage_refresh_token';
  static const _kFirstLaunch = 'garage_first_launch_done';

  Future<void> saveTokens({required String access, required String refresh}) async {
    await _storage.write(key: _kAccess, value: access);
    await _storage.write(key: _kRefresh, value: refresh);
  }

  Future<String?> readAccess() => _storage.read(key: _kAccess);
  Future<String?> readRefresh() => _storage.read(key: _kRefresh);

  Future<void> clear() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
  }

  /// On first launch ever, wipe any keychain leftovers from a prior install.
  Future<void> ensureFreshOnFirstLaunch() async {
    final done = await _storage.read(key: _kFirstLaunch);
    if (done == null) {
      await clear();
      await _storage.write(key: _kFirstLaunch, value: '1');
    }
  }
}

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  const storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  return TokenStorage(storage);
});
