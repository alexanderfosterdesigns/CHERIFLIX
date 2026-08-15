import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/media_summary.dart';
import 'package:cheriflix/core/models/media_type.dart';
import 'package:cheriflix/core/models/playback_progress_entry.dart';
import 'package:cheriflix/core/models/playback_progress_snapshot.dart';

void main() {
  test('snapshot prefers in-progress episodes over newer completed entries',
      () {
    final show = MediaSummary(
      tmdbId: 101,
      mediaType: MediaType.tv,
      title: 'The Rookie',
    );
    final movie = MediaSummary(
      tmdbId: 202,
      mediaType: MediaType.movie,
      title: 'Dune',
    );

    final snapshot = PlaybackProgressSnapshot(
      <PlaybackProgressEntry>[
        PlaybackProgressEntry(
          summary: show,
          seasonNumber: 1,
          episodeNumber: 1,
          episodeTitle: 'Pilot',
          position: const Duration(minutes: 43),
          totalDuration: const Duration(minutes: 43),
          updatedAt: DateTime.utc(2026, 3, 12),
        ),
        PlaybackProgressEntry(
          summary: movie,
          position: const Duration(minutes: 155),
          totalDuration: const Duration(minutes: 155),
          updatedAt: DateTime.utc(2026, 3, 11),
        ),
        PlaybackProgressEntry(
          summary: show,
          seasonNumber: 1,
          episodeNumber: 3,
          episodeTitle: 'The Good, the Bad and the Ugly',
          position: const Duration(minutes: 14),
          totalDuration: const Duration(minutes: 43),
          updatedAt: DateTime.utc(2026, 3, 10),
        ),
      ],
    );

    expect(
      snapshot.preferredForTitle(show)?.episodeNumber,
      3,
    );
    expect(
      snapshot.continueWatchingEntries.map((entry) => entry.saveKey),
      <String>[show.saveKey],
    );
    expect(
      snapshot.alreadyWatchedEntries.map((entry) => entry.saveKey),
      <String>[movie.saveKey],
    );
  });

  test('snapshot can resolve specific episode targets', () {
    final show = MediaSummary(
      tmdbId: 101,
      mediaType: MediaType.tv,
      title: 'The Rookie',
    );
    final entry = PlaybackProgressEntry(
      summary: show,
      seasonNumber: 2,
      episodeNumber: 4,
      position: const Duration(minutes: 20),
      totalDuration: const Duration(minutes: 43),
      updatedAt: DateTime.utc(2026, 3, 13),
    );

    final snapshot = PlaybackProgressSnapshot(<PlaybackProgressEntry>[entry]);

    expect(
      snapshot.entryForTarget(
        summary: show,
        seasonNumber: 2,
        episodeNumber: 4,
      ),
      same(entry),
    );
  });

  test('snapshot keeps last played episode target for completed shows', () {
    final show = MediaSummary(
      tmdbId: 303,
      mediaType: MediaType.tv,
      title: 'Severance',
    );
    final completedEpisode = PlaybackProgressEntry(
      summary: show,
      seasonNumber: 2,
      episodeNumber: 7,
      episodeTitle: 'Chikhai Bardo',
      position: const Duration(minutes: 52),
      totalDuration: const Duration(minutes: 52),
      updatedAt: DateTime.utc(2026, 3, 14),
    );

    final snapshot = PlaybackProgressSnapshot(
      <PlaybackProgressEntry>[completedEpisode],
    );

    expect(snapshot.preferredForTitle(show)?.episodeNumber, 7);
    expect(snapshot.latestResumeForTitle(show), isNull);
  });

  test('snapshot does not expose resume for tiny or nearly finished positions',
      () {
    final movie = MediaSummary(
      tmdbId: 404,
      mediaType: MediaType.movie,
      title: 'Heat',
    );
    final tinyPosition = PlaybackProgressEntry(
      summary: movie,
      position: const Duration(seconds: 12),
      totalDuration: const Duration(minutes: 170),
      updatedAt: DateTime.utc(2026, 3, 15),
    );
    final nearlyFinished = PlaybackProgressEntry(
      summary: movie,
      position: const Duration(minutes: 169),
      totalDuration: const Duration(minutes: 170),
      updatedAt: DateTime.utc(2026, 3, 16),
    );

    expect(tinyPosition.resumePosition, Duration.zero);
    expect(nearlyFinished.resumePosition, Duration.zero);

    final snapshot = PlaybackProgressSnapshot(
      <PlaybackProgressEntry>[nearlyFinished, tinyPosition],
    );

    expect(snapshot.latestResumeForTitle(movie), isNull);
    expect(snapshot.continueWatchingEntries, isEmpty);
  });
}
