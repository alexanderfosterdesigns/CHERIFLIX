import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

class CheriflixDatabase {
  CheriflixDatabase._();

  static const int schemaVersion = 12;

  static Future<Database> open({String? databasePath}) async {
    if (_shouldUseFfiDatabaseFactory) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final resolvedPath = databasePath ?? await _defaultDatabasePath();

    return databaseFactory.openDatabase(
      resolvedPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (database, version) async {
          await _createSchema(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createJsonCacheTable(database);
          }
          if (oldVersion < 3) {
            await _ensureColumn(
              database,
              tableName: 'profile_playback_settings',
              columnName: 'autoplay_next_episode',
              columnDefinition: 'INTEGER NOT NULL DEFAULT 1',
            );
            await _ensureColumn(
              database,
              tableName: 'profile_playback_settings',
              columnName: 'autoplay_previews',
              columnDefinition: 'INTEGER NOT NULL DEFAULT 1',
            );
          }
          if (oldVersion < 4) {
            await _createSavedTitlesTable(database);
          }
          if (oldVersion < 5) {
            await _createPlaybackProgressTable(database);
          }
          if (oldVersion < 6) {
            await _ensureColumn(
              database,
              tableName: 'profile_playback_settings',
              columnName: 'mute_autoplay_trailers',
              columnDefinition: 'INTEGER NOT NULL DEFAULT 1',
            );
          }
          if (oldVersion < 7) {
            await database.execute('''
              UPDATE profile_playback_settings
              SET autoplay_previews = 1
              WHERE autoplay_previews = 0
            ''');
          }
          if (oldVersion < 8) {
            await _migratePlaybackProgressTableToEpisodeScoped(database);
          }
          if (oldVersion < 9) {
            await _ensureColumn(
              database,
              tableName: 'profiles',
              columnName: 'trakt_username',
              columnDefinition: 'TEXT',
            );
            await _ensureColumn(
              database,
              tableName: 'profiles',
              columnName: 'trakt_access_token',
              columnDefinition: 'TEXT',
            );
            await _ensureColumn(
              database,
              tableName: 'profiles',
              columnName: 'trakt_refresh_token',
              columnDefinition: 'TEXT',
            );
            await _ensureColumn(
              database,
              tableName: 'profiles',
              columnName: 'trakt_token_type',
              columnDefinition: 'TEXT',
            );
            await _ensureColumn(
              database,
              tableName: 'profiles',
              columnName: 'trakt_scope',
              columnDefinition: 'TEXT',
            );
            await _ensureColumn(
              database,
              tableName: 'profiles',
              columnName: 'trakt_token_created_at',
              columnDefinition: 'TEXT',
            );
            await _ensureColumn(
              database,
              tableName: 'profiles',
              columnName: 'trakt_expires_in',
              columnDefinition: 'INTEGER',
            );
          }
          if (oldVersion < 10) {
            await _ensureColumn(
              database,
              tableName: 'profile_playback_settings',
              columnName: 'preferred_android_renderer_profile',
              columnDefinition: 'TEXT',
            );
          }
          if (oldVersion < 11) {
            await _ensureColumn(
              database,
              tableName: 'profiles',
              columnName: 'pin_hash',
              columnDefinition: 'TEXT',
            );
          }
          if (oldVersion < 12) {
            await _createAudioLanguagePreferencesTable(database);
            await _ensureColumn(
              database,
              tableName: 'profile_playback_settings',
              columnName: 'preferred_audio_language_code',
              columnDefinition: 'TEXT',
            );
          }
        },
      ),
    );
  }

  static Future<void> _createSchema(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS profiles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        avatar_label TEXT NOT NULL,
        language_code TEXT NOT NULL,
        maturity_tier TEXT NOT NULL,
        created_at TEXT NOT NULL,
        pin_hash TEXT,
        trakt_username TEXT,
        trakt_access_token TEXT,
        trakt_refresh_token TEXT,
        trakt_token_type TEXT,
        trakt_scope TEXT,
        trakt_token_created_at TEXT,
        trakt_expires_in INTEGER
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS profile_playback_settings (
        profile_id TEXT PRIMARY KEY,
        language_code TEXT NOT NULL,
        preferred_audio_language_code TEXT NOT NULL DEFAULT 'en',
        subtitle_url TEXT,
        autoplay_next_episode INTEGER NOT NULL DEFAULT 1,
        autoplay_previews INTEGER NOT NULL DEFAULT 1,
        mute_autoplay_trailers INTEGER NOT NULL DEFAULT 1,
        preferred_android_renderer_profile TEXT,
        FOREIGN KEY(profile_id) REFERENCES profiles(id) ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS provider_preferences (
        profile_id TEXT NOT NULL,
        tmdb_id INTEGER NOT NULL,
        media_type TEXT NOT NULL,
        provider_index INTEGER NOT NULL,
        PRIMARY KEY(profile_id, tmdb_id, media_type)
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL
      )
    ''');

    await _createJsonCacheTable(database);
    await _createSavedTitlesTable(database);
    await _createPlaybackProgressTable(database);
    await _createAudioLanguagePreferencesTable(database);
  }

  static Future<String> _defaultDatabasePath() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return _joinPath(supportDirectory.path, 'cheriflix.db');
  }

  static Future<void> _createJsonCacheTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS json_cache (
        cache_key TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        fetched_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createSavedTitlesTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS saved_titles (
        profile_id TEXT NOT NULL,
        tmdb_id INTEGER NOT NULL,
        media_type TEXT NOT NULL,
        title TEXT NOT NULL,
        overview TEXT,
        poster_path TEXT,
        backdrop_path TEXT,
        rating REAL,
        release_date TEXT,
        saved_at TEXT NOT NULL,
        PRIMARY KEY(profile_id, tmdb_id, media_type)
      )
    ''');
  }

  static Future<void> _createPlaybackProgressTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS playback_progress (
        profile_id TEXT NOT NULL,
        tmdb_id INTEGER NOT NULL,
        media_type TEXT NOT NULL,
        season_number INTEGER NOT NULL DEFAULT 0,
        episode_number INTEGER NOT NULL DEFAULT 0,
        title TEXT NOT NULL,
        overview TEXT,
        poster_path TEXT,
        backdrop_path TEXT,
        rating REAL,
        release_date TEXT,
        episode_title TEXT,
        episode_still_path TEXT,
        position_ms INTEGER NOT NULL,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(
          profile_id,
          tmdb_id,
          media_type,
          season_number,
          episode_number
        )
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_playback_progress_profile_updated
      ON playback_progress(profile_id, updated_at DESC)
    ''');
  }

  static Future<void> _createAudioLanguagePreferencesTable(
    Database database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS audio_language_preferences (
        profile_id TEXT NOT NULL,
        tmdb_id INTEGER NOT NULL,
        media_type TEXT NOT NULL,
        language_code TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(profile_id, tmdb_id, media_type),
        FOREIGN KEY(profile_id) REFERENCES profiles(id) ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> _migratePlaybackProgressTableToEpisodeScoped(
    Database database,
  ) async {
    final tableInfo =
        await database.rawQuery('PRAGMA table_info(playback_progress)');
    if (tableInfo.isEmpty) {
      await _createPlaybackProgressTable(database);
      return;
    }

    final columns = tableInfo
        .map((row) => '${row['name'] ?? ''}')
        .where((name) => name.isNotEmpty)
        .toSet();
    final isAlreadyEpisodeScoped = columns.contains('episode_title') &&
        columns.contains('episode_still_path') &&
        columns.contains('season_number') &&
        columns.contains('episode_number');
    if (isAlreadyEpisodeScoped) {
      await database.execute('''
        CREATE INDEX IF NOT EXISTS idx_playback_progress_profile_updated
        ON playback_progress(profile_id, updated_at DESC)
      ''');
      return;
    }

    await database.execute('''
      CREATE TABLE playback_progress_next (
        profile_id TEXT NOT NULL,
        tmdb_id INTEGER NOT NULL,
        media_type TEXT NOT NULL,
        season_number INTEGER NOT NULL DEFAULT 0,
        episode_number INTEGER NOT NULL DEFAULT 0,
        title TEXT NOT NULL,
        overview TEXT,
        poster_path TEXT,
        backdrop_path TEXT,
        rating REAL,
        release_date TEXT,
        episode_title TEXT,
        episode_still_path TEXT,
        position_ms INTEGER NOT NULL,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(
          profile_id,
          tmdb_id,
          media_type,
          season_number,
          episode_number
        )
      )
    ''');

    await database.execute('''
      INSERT OR REPLACE INTO playback_progress_next (
        profile_id,
        tmdb_id,
        media_type,
        season_number,
        episode_number,
        title,
        overview,
        poster_path,
        backdrop_path,
        rating,
        release_date,
        episode_title,
        episode_still_path,
        position_ms,
        duration_ms,
        updated_at
      )
      SELECT
        profile_id,
        tmdb_id,
        media_type,
        COALESCE(season_number, 0),
        COALESCE(episode_number, 0),
        title,
        overview,
        poster_path,
        backdrop_path,
        rating,
        release_date,
        NULL,
        NULL,
        position_ms,
        duration_ms,
        updated_at
      FROM playback_progress
    ''');

    await database.execute('DROP TABLE playback_progress');
    await database.execute(
      'ALTER TABLE playback_progress_next RENAME TO playback_progress',
    );
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_playback_progress_profile_updated
      ON playback_progress(profile_id, updated_at DESC)
    ''');
  }

  static Future<void> _ensureColumn(
    Database database, {
    required String tableName,
    required String columnName,
    required String columnDefinition,
  }) async {
    final rows = await database.rawQuery('PRAGMA table_info($tableName)');
    final hasColumn = rows.any((row) => row['name'] == columnName);
    if (hasColumn) {
      return;
    }

    await database.execute(
      'ALTER TABLE $tableName ADD COLUMN $columnName $columnDefinition',
    );
  }

  static bool get _shouldUseFfiDatabaseFactory =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}

String _joinPath(String left, String right) {
  final separator = Platform.pathSeparator;
  if (left.endsWith(separator)) {
    return '$left$right';
  }
  return '$left$separator$right';
}
