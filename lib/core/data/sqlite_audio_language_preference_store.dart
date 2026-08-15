import 'package:sqflite/sqflite.dart';

import '../models/media_type.dart';
import '../services/audio_language_preference_store.dart';

class SqliteAudioLanguagePreferenceStore
    implements AudioLanguagePreferenceStore {
  const SqliteAudioLanguagePreferenceStore(this._database);

  final Database _database;

  @override
  Future<String?> getPreferredLanguage(
      {required String profileId,
      required int tmdbId,
      required MediaType mediaType}) async {
    final rows = await _database.query('audio_language_preferences',
        columns: const <String>['language_code'],
        where: 'profile_id = ? AND tmdb_id = ? AND media_type = ?',
        whereArgs: <Object?>[profileId, tmdbId, mediaType.name],
        limit: 1);
    if (rows.isEmpty) return null;
    final value = normalizeAudioLanguageCode(
        rows.first['language_code']?.toString() ?? '');
    return value.isEmpty ? null : value;
  }

  @override
  Future<void> setPreferredLanguage(
      {required String profileId,
      required int tmdbId,
      required MediaType mediaType,
      required String languageCode}) async {
    final normalized = normalizeAudioLanguageCode(languageCode);
    if (normalized.isEmpty) return;
    await _database.insert(
        'audio_language_preferences',
        <String, Object?>{
          'profile_id': profileId,
          'tmdb_id': tmdbId,
          'media_type': mediaType.name,
          'language_code': normalized,
          'updated_at': DateTime.now().toUtc().toIso8601String()
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> clearPreferredLanguage(
          {required String profileId,
          required int tmdbId,
          required MediaType mediaType}) =>
      _database.delete('audio_language_preferences',
          where: 'profile_id = ? AND tmdb_id = ? AND media_type = ?',
          whereArgs: <Object?>[profileId, tmdbId, mediaType.name]);

  @override
  Future<void> clearAllForProfile(String profileId) =>
      _database.delete('audio_language_preferences',
          where: 'profile_id = ?', whereArgs: <Object?>[profileId]);
}
