import 'package:sqflite/sqflite.dart';

import '../services/json_cache_store.dart';

class SqliteJsonCacheStore implements JsonCacheStore {
  const SqliteJsonCacheStore(this._database);

  final Database _database;

  @override
  Future<CachedJsonEntry?> read({
    required String key,
  }) async {
    final rows = await _database.query(
      'json_cache',
      columns: <String>['payload', 'fetched_at'],
      where: 'cache_key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return CachedJsonEntry(
      payload: rows.first['payload']! as String,
      fetchedAt: DateTime.parse(rows.first['fetched_at']! as String).toUtc(),
    );
  }

  @override
  Future<String?> readFresh({
    required String key,
    required Duration maxAge,
  }) async {
    final entry = await read(key: key);
    if (entry == null) {
      return null;
    }
    if (!entry.isFresh(maxAge)) {
      return null;
    }
    return entry.payload;
  }

  @override
  Future<void> write({
    required String key,
    required String payload,
  }) {
    return _database.insert(
      'json_cache',
      <String, Object?>{
        'cache_key': key,
        'payload': payload,
        'fetched_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
