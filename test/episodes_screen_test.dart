import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/episode_summary.dart';
import 'package:cheriflix/core/models/media_summary.dart';
import 'package:cheriflix/core/models/media_type.dart';
import 'package:cheriflix/core/models/maturity_tier.dart';
import 'package:cheriflix/core/models/playback_progress_entry.dart';
import 'package:cheriflix/core/models/playback_progress_snapshot.dart';
import 'package:cheriflix/core/models/profile.dart';
import 'package:cheriflix/core/services/json_cache_store.dart';
import 'package:cheriflix/core/services/tmdb_client.dart';
import 'package:cheriflix/core/services/tmdb_media_catalog_service.dart';
import 'package:cheriflix/core/widgets/playback_progress_bar.dart';
import 'package:cheriflix/features/episodes/episodes_screen.dart';

void main() {
  testWidgets('EpisodesScreen renders episodes and plays the selected one',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final summary = MediaSummary(
      tmdbId: 79744,
      mediaType: MediaType.tv,
      title: 'The Rookie',
      overview: 'John Nolan starts over and joins the LAPD.',
      rating: 8.5,
      releaseDate: DateTime.utc(2018, 10, 16),
      runtimeMinutes: 43,
      seasonCount: 2,
    );
    final episodes = <EpisodeSummary>[
      EpisodeSummary(
        seasonNumber: 1,
        episodeNumber: 1,
        title: 'Pilot',
        overview: 'Nolan begins training with the LAPD.',
        runtimeMinutes: 43,
      ),
      EpisodeSummary(
        seasonNumber: 1,
        episodeNumber: 2,
        title: 'Crash Course',
        overview: 'Training intensifies.',
        runtimeMinutes: 43,
      ),
    ];

    int? playedSeason;
    int? playedEpisode;

    await tester.pumpWidget(
      MaterialApp(
        home: EpisodesScreen(
          activeProfile: Profile(
            id: 'p1',
            name: 'Cherif',
            avatarLabel: 'C',
            languageCode: 'en',
            maturityTier: MaturityTier.mature,
            createdAt: DateTime.utc(2026, 3, 8),
          ),
          summary: summary,
          playbackProgress: PlaybackProgressSnapshot.empty(),
          languageCode: 'en',
          mediaCatalogService: _FakeEpisodesTmdbCatalogService(
            episodesBySeason: <int, List<EpisodeSummary>>{
              1: episodes,
            },
          ),
          onBack: () {},
          onPlayEpisode: (seasonNumber, episode) {
            playedSeason = seasonNumber;
            playedEpisode = episode.episodeNumber;
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('The Rookie'), findsOneWidget);
    expect(find.text('Season 1'), findsOneWidget);
    expect(find.text('Episode 1 - Pilot'), findsOneWidget);
    expect(find.text('Episode 2 - Crash Course'), findsOneWidget);

    await tester.tap(find.text('Episode 1 - Pilot'));
    await tester.pump();

    expect(playedSeason, 1);
    expect(playedEpisode, 1);
  });

  testWidgets('EpisodesScreen shows progress bars for started episodes',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final summary = MediaSummary(
      tmdbId: 79744,
      mediaType: MediaType.tv,
      title: 'The Rookie',
      releaseDate: DateTime.utc(2018, 10, 16),
      runtimeMinutes: 43,
      seasonCount: 1,
    );
    final episodes = <EpisodeSummary>[
      EpisodeSummary(
        seasonNumber: 1,
        episodeNumber: 1,
        title: 'Pilot',
        runtimeMinutes: 43,
      ),
      EpisodeSummary(
        seasonNumber: 1,
        episodeNumber: 2,
        title: 'Crash Course',
        runtimeMinutes: 43,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: EpisodesScreen(
          activeProfile: Profile(
            id: 'p1',
            name: 'Cherif',
            avatarLabel: 'C',
            languageCode: 'en',
            maturityTier: MaturityTier.mature,
            createdAt: DateTime.utc(2026, 3, 8),
          ),
          summary: summary,
          playbackProgress: PlaybackProgressSnapshot(
            <PlaybackProgressEntry>[
              PlaybackProgressEntry(
                summary: summary,
                seasonNumber: 1,
                episodeNumber: 1,
                position: const Duration(minutes: 10),
                totalDuration: const Duration(minutes: 43),
                updatedAt: DateTime.utc(2026, 3, 10),
              ),
              PlaybackProgressEntry(
                summary: summary,
                seasonNumber: 1,
                episodeNumber: 2,
                position: const Duration(minutes: 43),
                totalDuration: const Duration(minutes: 43),
                updatedAt: DateTime.utc(2026, 3, 11),
              ),
            ],
          ),
          languageCode: 'en',
          mediaCatalogService: _FakeEpisodesTmdbCatalogService(
            episodesBySeason: <int, List<EpisodeSummary>>{
              1: episodes,
            },
          ),
          onBack: () {},
          onPlayEpisode: (_, __) {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(PlaybackProgressBar), findsNWidgets(2));
  });

  testWidgets('EpisodesScreen hides spoilers only for unstarted episodes',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final summary = MediaSummary(
      tmdbId: 79744,
      mediaType: MediaType.tv,
      title: 'The Rookie',
      releaseDate: DateTime.utc(2018, 10, 16),
      runtimeMinutes: 43,
      seasonCount: 1,
    );
    final episodes = <EpisodeSummary>[
      EpisodeSummary(
        seasonNumber: 1,
        episodeNumber: 1,
        title: 'Pilot',
        overview: 'Nolan begins training with the LAPD.',
        runtimeMinutes: 43,
      ),
      EpisodeSummary(
        seasonNumber: 1,
        episodeNumber: 2,
        title: 'Crash Course',
        overview: 'Training intensifies.',
        runtimeMinutes: 43,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: EpisodesScreen(
          activeProfile: Profile(
            id: 'p1',
            name: 'Cherif',
            avatarLabel: 'C',
            languageCode: 'en',
            maturityTier: MaturityTier.mature,
            createdAt: DateTime.utc(2026, 3, 8),
          ),
          summary: summary,
          playbackProgress: PlaybackProgressSnapshot(
            <PlaybackProgressEntry>[
              PlaybackProgressEntry(
                summary: summary,
                seasonNumber: 1,
                episodeNumber: 1,
                position: const Duration(minutes: 2, seconds: 9),
                totalDuration: const Duration(minutes: 43),
                updatedAt: DateTime.utc(2026, 3, 10),
              ),
            ],
          ),
          languageCode: 'en',
          hideSpoilers: true,
          mediaCatalogService: _FakeEpisodesTmdbCatalogService(
            episodesBySeason: <int, List<EpisodeSummary>>{
              1: episodes,
            },
          ),
          onBack: () {},
          onPlayEpisode: (_, __) {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Nolan begins training with the LAPD.'), findsOneWidget);
    expect(find.text('Training intensifies.'), findsNothing);
    expect(find.byIcon(Icons.hide_image_rounded), findsOneWidget);
  });

  testWidgets(
      'EpisodesScreen renders the compact TV layout without overflow at high DPR',
      (tester) async {
    tester.view.physicalSize = const Size(2560, 1440);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final summary = MediaSummary(
      tmdbId: 9001,
      mediaType: MediaType.tv,
      title: 'Compact Episodes',
      releaseDate: DateTime.utc(2020, 1, 1),
      runtimeMinutes: 42,
      seasonCount: 1,
    );
    final episodes = <EpisodeSummary>[
      EpisodeSummary(
        seasonNumber: 1,
        episodeNumber: 1,
        title: 'Pilot',
        runtimeMinutes: 42,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: EpisodesScreen(
          activeProfile: Profile(
            id: 'p1',
            name: 'Cherif',
            avatarLabel: 'C',
            languageCode: 'en',
            maturityTier: MaturityTier.mature,
            createdAt: DateTime.utc(2026, 3, 8),
          ),
          summary: summary,
          playbackProgress: PlaybackProgressSnapshot.empty(),
          languageCode: 'en',
          mediaCatalogService: _FakeEpisodesTmdbCatalogService(
            episodesBySeason: <int, List<EpisodeSummary>>{
              1: episodes,
            },
          ),
          onBack: () {},
          onPlayEpisode: (_, __) {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Compact Episodes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeEpisodesTmdbCatalogService extends TmdbMediaCatalogService {
  _FakeEpisodesTmdbCatalogService({
    required this.episodesBySeason,
  }) : super(
          tmdbClient: TmdbClient(apiKey: 'test'),
          cacheStore: const _NoopJsonCacheStore(),
        );

  final Map<int, List<EpisodeSummary>> episodesBySeason;

  @override
  Future<List<EpisodeSummary>> fetchSeasonEpisodes({
    required int tmdbId,
    required int seasonNumber,
    required String languageCode,
    int? fallbackRuntimeMinutes,
  }) async {
    return episodesBySeason[seasonNumber] ?? const <EpisodeSummary>[];
  }
}

class _NoopJsonCacheStore implements JsonCacheStore {
  const _NoopJsonCacheStore();

  @override
  Future<CachedJsonEntry?> read({
    required String key,
  }) async {
    return null;
  }

  @override
  Future<String?> readFresh({
    required String key,
    required Duration maxAge,
  }) async {
    return null;
  }

  @override
  Future<void> write({
    required String key,
    required String payload,
  }) async {}
}
