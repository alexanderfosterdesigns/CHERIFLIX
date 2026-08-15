import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/data/sqlite_audio_language_preference_store.dart';
import 'package:cheriflix/core/data/sqlite_database.dart';
import 'package:cheriflix/core/models/media_type.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('persists show and movie language preferences by stable TMDB key',
      () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'cheriflix_audio_preferences_',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    final databasePath =
        '${tempDirectory.path}${Platform.pathSeparator}cheriflix.db';
    var database = await CheriflixDatabase.open(databasePath: databasePath);
    await database.insert('profiles', <String, Object?>{
      'id': 'profile-1',
      'name': 'Tester',
      'avatar_label': 'T',
      'language_code': 'en',
      'maturity_tier': 'mature',
      'created_at': DateTime.utc(2026).toIso8601String(),
    });
    var store = SqliteAudioLanguagePreferenceStore(database);

    await store.setPreferredLanguage(
      profileId: 'profile-1',
      tmdbId: 44242,
      mediaType: MediaType.tv,
      languageCode: 'spa',
    );
    await store.setPreferredLanguage(
      profileId: 'profile-1',
      tmdbId: 385687,
      mediaType: MediaType.movie,
      languageCode: 'ja-JP',
    );
    await database.close();

    database = await CheriflixDatabase.open(databasePath: databasePath);
    addTearDown(database.close);
    store = SqliteAudioLanguagePreferenceStore(database);

    expect(
      await store.getPreferredLanguage(
        profileId: 'profile-1',
        tmdbId: 44242,
        mediaType: MediaType.tv,
      ),
      'es',
    );
    expect(
      await store.getPreferredLanguage(
        profileId: 'profile-1',
        tmdbId: 385687,
        mediaType: MediaType.movie,
      ),
      'ja',
    );
    expect(
      await store.getPreferredLanguage(
        profileId: 'profile-1',
        tmdbId: 44242,
        mediaType: MediaType.movie,
      ),
      isNull,
    );
  });
}
