import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persisted map of `schedulingKey -> notificationId`.
///
/// We need this so [NotificationsService] can cancel a previously-scheduled
/// notification by its scheduling key (e.g. `reminder:abc:30d`) when the
/// underlying due-date shifts and we need to reschedule.
///
/// Backed by [FlutterSecureStorage] (already in pubspec — `shared_preferences`
/// is not). Stored as a single JSON blob under a single key for simplicity:
/// the map is tiny (≤ 4 entries per car * ≤ 5 cars = 20 keys typical).
class NotificationIdsStore {
  NotificationIdsStore(this._storage);
  final FlutterSecureStorage _storage;

  static const _kBlob = 'garage_notification_ids';

  Future<Map<String, int>> _readAll() async {
    final raw = await _storage.read(key: _kBlob);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
      }
    } catch (_) {
      // corrupt blob — start fresh.
    }
    return {};
  }

  Future<void> _writeAll(Map<String, int> map) async {
    await _storage.write(key: _kBlob, value: jsonEncode(map));
  }

  Future<int?> read(String key) async {
    final all = await _readAll();
    return all[key];
  }

  Future<void> write(String key, int id) async {
    final all = await _readAll();
    all[key] = id;
    await _writeAll(all);
  }

  Future<void> remove(String key) async {
    final all = await _readAll();
    if (all.remove(key) != null) await _writeAll(all);
  }

  /// Returns and clears every stored mapping. Used by [cancelAll] paths.
  Future<List<int>> drainAll() async {
    final all = await _readAll();
    final ids = all.values.toList(growable: false);
    await _storage.delete(key: _kBlob);
    return ids;
  }

  Future<Map<String, int>> snapshot() => _readAll();
}
