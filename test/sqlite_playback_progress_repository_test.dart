import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/data/sqlite_database.dart';
import 'package:cheriflix/core/data/sqlite_playback_progress_repository.dart';
import 'package:cheriflix/core/models/media_summary.dart';
import 'package:cheriflix/core/models/media_type.dart';
import 'package:cheriflix/core/models/playback_progress_entry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('repository stores multiple episode entries for the same show',
      () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'cheriflix_progress_repo_',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    final database = await CheriflixDatabase.open(
      databasePath: '${tempDirectory.path}${Platform.pathSeparator}app.db',
    );
    addTearDown(database.close);

    final repository = SqlitePlaybackProgressRepository(database);
    final summary = MediaSummary(
      tmdbId: 79744,
      mediaType: MediaType.tv,
      title: 'The Rookie',
    );

    await repository.saveProgress(
      profileId: 'profile-1',
      entry: PlaybackProgressEntry(
        summary: summary,
        seasonNumber: 1,
        episodeNumber: 1,
        episodeTitle: 'Pilot',
        position: const Duration(minutes: 12),
        totalDuration: const Duration(minutes: 43),
        updatedAt: DateTime.utc(2026, 3, 10),
      ),
    );
    await repository.saveProgress(
      profileId: 'profile-1',
      entry: PlaybackProgressEntry(
        summary: summary,
        seasonNumber: 1,
        episodeNumber: 2,
        episodeTitle: 'Crash Course',
        position: const Duration(minutes: 43),
        totalDuration: const Duration(minutes: 43),
        updatedAt: DateTime.utc(2026, 3, 11),
      ),
    );

    final entries = await repository.fetchProgressEntries('profile-1');

    expect(entries, hasLength(2));
    expect(entries.first.episodeNumber, 2);
    expect(entries.last.episodeNumber, 1);

    await repository.removeProgress(
      profileId: 'profile-1',
      tmdbId: summary.tmdbId,
      mediaType: summary.mediaType,
      seasonNumber: 1,
      episodeNumber: 1,
    );

    final remaining = await repository.fetchProgressEntries('profile-1');

    expect(remaining, hasLength(1));
    expect(remaining.single.episodeNumber, 2);
  });

  test('repository keeps movie progress isolated per profile', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'cheriflix_progress_repo_',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    final database = await CheriflixDatabase.open(
      databasePath: '${tempDirectory.path}${Platform.pathSeparator}app.db',
    );
    addTearDown(database.close);

    final repository = SqlitePlaybackProgressRepository(database);
    final movie = MediaSummary(
      tmdbId: 438631,
      mediaType: MediaType.movie,
      title: 'Dune',
    );

    await repository.saveProgress(
      profileId: 'profile-1',
      entry: PlaybackProgressEntry(
        summary: movie,
        position: const Duration(minutes: 20),
        totalDuration: const Duration(minutes: 155),
        updatedAt: DateTime.utc(2026, 3, 10),
      ),
    );
    await repository.saveProgress(
      profileId: 'profile-2',
      entry: PlaybackProgressEntry(
        summary: movie,
        position: const Duration(minutes: 80),
        totalDuration: const Duration(minutes: 155),
        updatedAt: DateTime.utc(2026, 3, 11),
      ),
    );

    final firstProfileEntries = await repository.fetchProgressEntries(
      'profile-1',
    );
    final secondProfileEntries = await repository.fetchProgressEntries(
      'profile-2',
    );

    expect(firstProfileEntries.single.position, const Duration(minutes: 20));
    expect(secondProfileEntries.single.position, const Duration(minutes: 80));
  });
}
