import 'package:sqflite/sqflite.dart';

import '../models/media_type.dart';
import '../services/provider_preference_store.dart';

class SqliteProviderPreferenceStore implements ProviderPreferenceStore {
  const SqliteProviderPreferenceStore(this._database);

  final Database _database;

  @override
  Future<int?> getLastGoodProviderIndex({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
  }) async {
    final rows = await _database.query(
      'provider_preferences',
      columns: <String>['provider_index'],
      where: 'profile_id = ? AND tmdb_id = ? AND media_type = ?',
      whereArgs: <Object?>[profileId, tmdbId, mediaType.name],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first['provider_index']! as int;
  }

  @override
  Future<void> saveLastGoodProviderIndex({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
  }) {
    return _database.insert(
      'provider_preferences',
      <String, Object?>{
        'profile_id': profileId,
        'tmdb_id': tmdbId,
        'media_type': mediaType.name,
        'provider_index': providerIndex,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
