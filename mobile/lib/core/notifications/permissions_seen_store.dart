import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tracks whether the user has seen the one-time permissions explainer
/// screen. Stored in the secure store under `garage_permissions_seen`
/// (string '1' = seen, missing = unseen).
class PermissionsSeenStore {
  PermissionsSeenStore(this._storage);
  final FlutterSecureStorage _storage;

  static const _key = 'garage_permissions_seen';

  Future<bool> isSeen() async {
    final v = await _storage.read(key: _key);
    return v != null && v.isNotEmpty;
  }

  Future<void> markSeen() async {
    await _storage.write(key: _key, value: '1');
  }

  Future<void> reset() => _storage.delete(key: _key);
}

final permissionsSeenStoreProvider = Provider<PermissionsSeenStore>((ref) {
  const storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  return PermissionsSeenStore(storage);
});

/// Resolves whether the explainer should still be shown. The router redirect
/// reads this once during bootstrap; once the user dismisses or completes
/// the explainer it's flipped and the router redirect stops sending users
/// to `/permissions`.
final permissionsSeenProvider = StateProvider<bool>((ref) => false);
