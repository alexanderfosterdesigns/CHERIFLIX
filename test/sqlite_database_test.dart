import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cheriflix/core/data/sqlite_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('repairs stale schema versions when tables already exist', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'cheriflix_sqlite_test_',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    final databasePath = '${tempDirectory.path}${Platform.pathSeparator}app.db';
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final seedDatabase = await databaseFactory.openDatabase(databasePath);
    await seedDatabase.execute('''
      CREATE TABLE profiles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        avatar_label TEXT NOT NULL,
        language_code TEXT NOT NULL,
        maturity_tier TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await seedDatabase.execute('''
      CREATE TABLE profile_playback_settings (
        profile_id TEXT PRIMARY KEY,
        language_code TEXT NOT NULL,
        subtitle_url TEXT,
        autoplay_next_episode INTEGER NOT NULL DEFAULT 1,
        autoplay_previews INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await seedDatabase.execute('''
      CREATE TABLE provider_preferences (
        profile_id TEXT NOT NULL,
        tmdb_id INTEGER NOT NULL,
        media_type TEXT NOT NULL,
        provider_index INTEGER NOT NULL,
        PRIMARY KEY(profile_id, tmdb_id, media_type)
      )
    ''');
    await seedDatabase.execute('''
      CREATE TABLE app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL
      )
    ''');
    await seedDatabase.execute('''
      CREATE TABLE json_cache (
        cache_key TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        fetched_at TEXT NOT NULL
      )
    ''');
    await seedDatabase.execute('''
      CREATE TABLE saved_titles (
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
    await seedDatabase.execute('''
      CREATE TABLE playback_progress (
        profile_id TEXT NOT NULL,
        tmdb_id INTEGER NOT NULL,
        media_type TEXT NOT NULL,
        title TEXT NOT NULL,
        overview TEXT,
        poster_path TEXT,
        backdrop_path TEXT,
        rating REAL,
        release_date TEXT,
        season_number INTEGER,
        episode_number INTEGER,
        position_ms INTEGER NOT NULL,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(profile_id, tmdb_id, media_type)
      )
    ''');
    await seedDatabase.execute('PRAGMA user_version = 2');
    await seedDatabase.close();

    final repairedDatabase = await CheriflixDatabase.open(
      databasePath: databasePath,
    );
    addTearDown(repairedDatabase.close);

    final versionRows = await repairedDatabase.rawQuery('PRAGMA user_version');
    expect(versionRows.single.values.single, CheriflixDatabase.schemaVersion);

    final playbackSettingsColumns = await repairedDatabase.rawQuery(
      'PRAGMA table_info(profile_playback_settings)',
    );
    final columnNames =
        playbackSettingsColumns.map((row) => row['name']).toSet();
    expect(columnNames, contains('autoplay_next_episode'));
    expect(columnNames, contains('autoplay_previews'));
    expect(columnNames, contains('mute_autoplay_trailers'));
    expect(columnNames, contains('preferred_android_renderer_profile'));
  });
}
