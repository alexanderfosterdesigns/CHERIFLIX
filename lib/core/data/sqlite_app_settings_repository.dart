import 'package:sqflite/sqflite.dart';

class SqliteAppSettingsRepository {
  const SqliteAppSettingsRepository(this._database);

  final Database _database;

  Future<DateTime?> readSessionUnlockedAt() async {
    final rows = await _database.query(
      'app_settings',
      columns: <String>['setting_value'],
      where: 'setting_key = ?',
      whereArgs: <Object?>['session_unlocked_at'],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return DateTime.parse(rows.first['setting_value']! as String).toUtc();
  }

  Future<void> writeSessionUnlockedAt(DateTime value) {
    return _database.insert(
      'app_settings',
      <String, Object?>{
        'setting_key': 'session_unlocked_at',
        'setting_value': value.toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> readLastActiveProfileId() async {
    final rows = await _database.query(
      'app_settings',
      columns: <String>['setting_value'],
      where: 'setting_key = ?',
      whereArgs: <Object?>['last_active_profile_id'],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first['setting_value'] as String;
  }

  Future<void> writeLastActiveProfileId(String profileId) {
    return _database.insert(
      'app_settings',
      <String, Object?>{
        'setting_key': 'last_active_profile_id',
        'setting_value': profileId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> readDownloadLocation() {
    return _readString('download_location');
  }

  Future<void> writeDownloadLocation(String path) {
    return _writeString('download_location', path);
  }

  Future<String?> _readString(String key) async {
    final rows = await _database.query(
      'app_settings',
      columns: <String>['setting_value'],
      where: 'setting_key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['setting_value'] as String;
  }

  Future<void> _writeString(String key, String value) {
    return _database.insert(
      'app_settings',
      <String, Object?>{
        'setting_key': key,
        'setting_value': value,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
