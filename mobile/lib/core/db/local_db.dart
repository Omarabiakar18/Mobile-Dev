import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// On-device SQLite cache. Tables mirror API response shapes.
/// We never write user-edited data here directly — only mirror successful
/// API responses so the app can open to last-known data offline.
///
/// Bump [_dbVersion] and add an upgrade branch when adding/altering tables.
class LocalDb {
  LocalDb._(this._db);
  final Database _db;
  Database get db => _db;

  static const _dbName = 'garage.db';
  static const _dbVersion = 1;

  static Future<LocalDb> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _dbName);
    final db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
    );
    return LocalDb._(db);
  }

  static Future<void> _onCreate(Database db, int _) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cars_cache (
        id            TEXT PRIMARY KEY,
        json          TEXT NOT NULL,
        cached_at     INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_cache (
        id            TEXT PRIMARY KEY,
        json          TEXT NOT NULL,
        cached_at     INTEGER NOT NULL
      )
    ''');

    // Phase 2+ tables (created upfront — empty until those features land):
    await db.execute('''
      CREATE TABLE IF NOT EXISTS fuel_entries_cache (
        id            TEXT PRIMARY KEY,
        car_id        TEXT NOT NULL,
        json          TEXT NOT NULL,
        cached_at     INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_fuel_car ON fuel_entries_cache(car_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS maintenance_cache (
        id            TEXT PRIMARY KEY,
        car_id        TEXT NOT NULL,
        json          TEXT NOT NULL,
        cached_at     INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_maint_car ON maintenance_cache(car_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS reminders_cache (
        id            TEXT PRIMARY KEY,
        car_id        TEXT NOT NULL,
        json          TEXT NOT NULL,
        cached_at     INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS documents_cache (
        id            TEXT PRIMARY KEY,
        car_id        TEXT NOT NULL,
        json          TEXT NOT NULL,
        cached_at     INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS gas_stations_cache (
        id            TEXT PRIMARY KEY,
        json          TEXT NOT NULL,
        cached_at     INTEGER NOT NULL
      )
    ''');
  }

  Future<void> close() => _db.close();
}

/// Opens the DB once on first read and reuses it.
final localDbProvider = FutureProvider<LocalDb>((ref) async {
  final db = await LocalDb.open();
  ref.onDispose(() => db.close());
  return db;
});
