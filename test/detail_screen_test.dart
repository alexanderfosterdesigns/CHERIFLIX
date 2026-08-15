import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/media_summary.dart';
import 'package:cheriflix/core/models/media_type.dart';
import 'package:cheriflix/core/models/maturity_tier.dart';
import 'package:cheriflix/core/models/playback_progress_entry.dart';
import 'package:cheriflix/core/models/playback_progress_snapshot.dart';
import 'package:cheriflix/core/models/profile.dart';
import 'package:cheriflix/core/models/title_metadata.dart';
import 'package:cheriflix/core/models/tmdb_title_logo.dart';
import 'package:cheriflix/core/services/json_cache_store.dart';
import 'package:cheriflix/core/services/tmdb_client.dart';
import 'package:cheriflix/core/services/tmdb_media_catalog_service.dart';
import 'package:cheriflix/core/theme/tv_layout.dart';
import 'package:cheriflix/core/widgets/tv_shortcuts.dart';
import 'package:cheriflix/features/details/detail_screen.dart';

void main() {
  test('title-logo limiter preserves aspect ratio within both bounds', () {
    expect(
      calculateTitleLogoSize(
        intrinsicWidth: 2968,
        intrinsicHeight: 1300,
        maxWidth: 560,
        maxHeight: 150,
      ),
      const Size(342.46153846153845, 150),
    );
    expect(
      calculateTitleLogoSize(
        intrinsicWidth: 3000,
        intrinsicHeight: 300,
        maxWidth: 560,
        maxHeight: 150,
      ),
      const Size(560, 56),
    );
  });

  testWidgets('tall title logo cannot auto-scroll above the detail viewport',
      (tester) async {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final summary = MediaSummary(
      tmdbId: 44242,
      mediaType: MediaType.tv,
      title: 'Devious Maids',
      overview: 'Test overview.',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DetailScreen(
          activeProfile: Profile(
            id: 'p1',
            name: 'Cherif',
            avatarLabel: 'C',
            languageCode: 'en',
            maturityTier: MaturityTier.mature,
            createdAt: DateTime.utc(2026, 3, 8),
          ),
          summary: summary,
          languageCode: 'en',
          mediaCatalogService: _FakeTmdbCatalogService(
            detail: summary,
            metadata: TitleMetadata(summary: summary),
            recommendations: const <MediaSummary>[],
            logo: const TmdbTitleLogo(
              filePath: '/devious.png',
              width: 2968,
              height: 1300,
              languageCode: 'en',
            ),
          ),
          playbackProgress: PlaybackProgressSnapshot.empty(),
          isSaved: false,
          onBack: () {},
          onPlay: () {},
          onToggleSaved: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_detailBodyScrollOffset(tester), 0);
    final heroTop = tester.getTopLeft(
      find.byKey(const ValueKey<String>('detail_hero_section')),
    );
    expect(heroTop.dy, greaterThanOrEqualTo(0));
  });

  testWidgets('DetailScreen uses a long backdrop fade with no abrupt cutoff',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final summary = MediaSummary(
      tmdbId: 90210,
      mediaType: MediaType.movie,
      title: 'Backdrop Fade',
      overview: 'A synthetic title used to verify the detail scrim.',
      releaseDate: DateTime.utc(2025, 9, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DetailScreen(
          activeProfile: Profile(
            id: 'p1',
            name: 'Cherif',
            avatarLabel: 'C',
            languageCode: 'en',
            maturityTier: MaturityTier.mature,
            createdAt: DateTime.utc(2026, 3, 8),
          ),
          summary: summary,
          languageCode: 'en',
          mediaCatalogService: _FakeTmdbCatalogService(
            detail: summary,
            metadata: TitleMetadata(summary: summary),
            recommendations: const <MediaSummary>[],
          ),
          playbackProgress: PlaybackProgressSnapshot.empty(),
          isSaved: false,
          onBack: () {},
          onPlay: () {},
          onToggleSaved: () {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    final horizontalScrim = tester.widget<DecoratedBox>(
      find.byWidgetPredicate((widget) {
        if (widget is! DecoratedBox) {
          return false;
        }
        final decoration = widget.decoration;
        if (decoration is! BoxDecoration) {
          return false;
        }
        final gradient = decoration.gradient;
        return gradient is LinearGradient &&
            gradient.begin == Alignment.centerLeft &&
            gradient.end == Alignment.centerRight &&
            gradient.colors.length == 8 &&
            gradient.colors.first == const Color(0xFC141414) &&
            gradient.colors.last == const Color(0x00141414);
      }).first,
    );
    final horizontalGradient = horizontalScrim.decoration as BoxDecoration;
    expect(
      horizontalGradient.gradient,
      isA<LinearGradient>().having(
        (gradient) => gradient.stops,
        'stops',
        const <double>[0, 0.08, 0.18, 0.32, 0.5, 0.68, 0.84, 1],
      ),
    );

    final verticalScrim = tester.widget<DecoratedBox>(
      find.byWidgetPredicate((widget) {
        if (widget is! DecoratedBox) {
          return false;
        }
        final decoration = widget.decoration;
        if (decoration is! BoxDecoration) {
          return false;
        }
        final gradient = decoration.gradient;
        return gradient is LinearGradient &&
            gradient.begin == Alignment.bottomCenter &&
            gradient.end == Alignment.topCenter &&
            gradient.colors.length == 9 &&
            gradient.colors.first == const Color(0xFF141414) &&
            gradient.colors.last == const Color(0x00141414);
      }).first,
    );
    final verticalGradient = verticalScrim.decoration as BoxDecoration;
    expect(
      verticalGradient.gradient,
      isA<LinearGradient>().having(
        (gradient) => gradient.stops,
        'stops',
        const <double>[0, 0.06, 0.14, 0.24, 0.38, 0.54, 0.72, 0.9, 1],
      ),
    );
  });

  testWidgets('DetailScreen renders TV-show hero actions and recommendations',
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
      seasonCount: 8,
    );
    final recommendation = MediaSummary(
      tmdbId: 125988,
      mediaType: MediaType.tv,
      title: 'Silo',
      overview: 'A mystery deep underground.',
      rating: 8.1,
      releaseDate: DateTime.utc(2023, 5, 5),
    );

    MediaSummary? openedEpisodesSummary;
    var openedDetails = false;
    MediaSummary? openedTitle;
    final metadata = TitleMetadata(
      summary: summary,
      certification: 'TV-14',
      genres: const <String>['Drama', 'Crime'],
      creators: const <String>['Alexi Hawley'],
      writers: const <String>['Alexi Hawley'],
      cast: const <TitleCredit>[
        TitleCredit(
          name: 'Nathan Fillion',
          role: 'John Nolan',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DetailScreen(
          activeProfile: Profile(
            id: 'p1',
            name: 'Cherif',
            avatarLabel: 'C',
            languageCode: 'en',
            maturityTier: MaturityTier.mature,
            createdAt: DateTime.utc(2026, 3, 8),
          ),
          summary: summary,
          languageCode: 'en',
          mediaCatalogService: _FakeTmdbCatalogService(
            detail: summary,
            metadata: metadata,
            recommendations: <MediaSummary>[recommendation],
          ),
          playbackProgress: PlaybackProgressSnapshot(
            <PlaybackProgressEntry>[
              PlaybackProgressEntry(
                summary: summary,
                seasonNumber: 1,
                episodeNumber: 2,
                position: const Duration(minutes: 5),
                totalDuration: const Duration(minutes: 43),
                updatedAt: DateTime.utc(2026, 3, 8),
              ),
            ],
          ),
          isSaved: false,
          onBack: () {},
          onPlay: () {},
          onToggleSaved: () {},
          onOpenEpisodes: (value) => openedEpisodesSummary = value,
          onOpenTitleInfo: () => openedDetails = true,
          onOpenTitle: (value) => openedTitle = value,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('The Rookie'), findsOneWidget);
    expect(find.text('RESUME'), findsOneWidget);
    expect(find.text('8.5'), findsOneWidget);
    expect(find.text('TV-14'), findsOneWidget);
    expect(find.text('EPISODES'), findsOneWidget);
    expect(find.text('DETAILS'), findsOneWidget);
    expect(find.text('TRAILERS & MORE'), findsNothing);
    expect(find.text('Others Also Watched'), findsOneWidget);
    expect(find.text('Silo'), findsOneWidget);
    final overviewTabSurface = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey<String>('detail_tab_surface_OVERVIEW')),
    );
    final overviewTabDecoration =
        overviewTabSurface.decoration! as BoxDecoration;
    expect(overviewTabDecoration.color, const Color(0xFF2B2B2B));
    expect(overviewTabDecoration.color, isNot(const Color(0x241E90FF)));
    final recommendationCard =
        tester.widget<TvPosterButton>(find.byType(TvPosterButton).first);
    final shellWidth = tester.getSize(find.byType(Scaffold).first).width;
    final layout = CheriflixTvLayout.fromWidth(shellWidth);
    final expectedExpandedPosterHeight = layout.homeRailExpandedPosterHeight;
    expect(recommendationCard.width, layout.homeRailCardWidth);
    expect(recommendationCard.posterHeight, layout.homeRailCardPosterHeight);
    expect(
      recommendationCard.expandedWidth,
      expectedExpandedPosterHeight * (16 / 9),
    );
    expect(
      recommendationCard.expandedPosterHeight,
      expectedExpandedPosterHeight,
    );
    expect(recommendationCard.expandOnFocus, isTrue);
    expect(recommendationCard.overlayExpandedDetails, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'DetailOverviewTab',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'DetailEpisodesTab',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(openedEpisodesSummary?.tmdbId, summary.tmdbId);
    expect(openedEpisodesSummary?.seasonCount, 8);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'DetailDetailsTab',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(openedDetails, isTrue);

    final recommendationFinder = find.byKey(
      ValueKey<String>('detail_recommendation_${recommendation.saveKey}_0'),
    );
    await tester.ensureVisible(recommendationFinder);
    await tester.pumpAndSettle();
    await tester.tap(recommendationFinder);
    await tester.pump();
    expect(openedTitle?.tmdbId, 125988);
  });

  testWidgets(
      'DetailScreen keeps the hero shelf stable while moving between hero actions',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final summary = MediaSummary(
      tmdbId: 79800,
      mediaType: MediaType.tv,
      title: 'Focus Drift',
      overview:
          'This overview is long enough to keep the hero section prominent while the action buttons are focused.',
      rating: 8.1,
      releaseDate: DateTime.utc(2024, 8, 14),
      runtimeMinutes: 45,
      seasonCount: 3,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DetailScreen(
          activeProfile: Profile(
            id: 'p1',
            name: 'Cherif',
            avatarLabel: 'C',
            languageCode: 'en',
            maturityTier: MaturityTier.mature,
            createdAt: DateTime.utc(2026, 3, 8),
          ),
          summary: summary,
          languageCode: 'en',
          mediaCatalogService: _FakeTmdbCatalogService(
            detail: summary,
            metadata: TitleMetadata(
              summary: summary,
              certification: 'TV-14',
              genres: const <String>['Drama'],
            ),
            recommendations: <MediaSummary>[
              MediaSummary(
                tmdbId: 79801,
                mediaType: MediaType.movie,
                title: 'Backstop',
                releaseDate: DateTime.utc(2025, 2, 2),
              ),
            ],
          ),
          playbackProgress: PlaybackProgressSnapshot.empty(),
          isSaved: false,
          onBack: () {},
          onPlay: () {},
          onToggleSaved: () {},
          onOpenTitle: (_) {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    final lowerShelf = find.byKey(
      const ValueKey<String>('detail_lower_shelf'),
    );
    final initialShelfTop = tester.getTopLeft(lowerShelf);
    final initialFocus = FocusManager.instance.primaryFocus;

    FocusManager.instance.primaryFocus?.nextFocus();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, isNot(same(initialFocus)));
    expect(tester.getTopLeft(lowerShelf).dy, equals(initialShelfTop.dy));

    final secondFocus = FocusManager.instance.primaryFocus;
    FocusManager.instance.primaryFocus?.nextFocus();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, isNot(same(secondFocus)));
    expect(tester.getTopLeft(lowerShelf).dy, equals(initialShelfTop.dy));

    final thirdFocus = FocusManager.instance.primaryFocus;
    FocusManager.instance.primaryFocus?.nextFocus();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, isNot(same(thirdFocus)));
    expect(tester.getTopLeft(lowerShelf).dy, equals(initialShelfTop.dy));
  });

  testWidgets('DetailScreen keeps the hero and lower shelf from overlapping',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final summary = MediaSummary(
      tmdbId: 550,
      mediaType: MediaType.movie,
      title: 'War Machine',
      overview: 'A long overview to keep the hero content tall and readable.',
      rating: 7.2,
      releaseDate: DateTime.utc(2026, 2, 12),
      runtimeMinutes: 110,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DetailScreen(
          activeProfile: Profile(
            id: 'p1',
            name: 'Cherif',
            avatarLabel: 'C',
            languageCode: 'en',
            maturityTier: MaturityTier.mature,
            createdAt: DateTime.utc(2026, 3, 8),
          ),
          summary: summary,
          languageCode: 'en',
          mediaCatalogService: _FakeTmdbCatalogService(
            detail: summary,
            metadata: TitleMetadata(
              summary: summary,
              certification: 'MA 15+',
              genres: const <String>['Action'],
            ),
            recommendations: <MediaSummary>[
              MediaSummary(
                tmdbId: 551,
                mediaType: MediaType.movie,
                title: 'Valiant One',
                releaseDate: DateTime.utc(2025, 1, 1),
              ),
            ],
          ),
          playbackProgress: PlaybackProgressSnapshot.empty(),
          isSaved: false,
          onBack: () {},
          onPlay: () {},
          onToggleSaved: () {},
          onOpenTitle: (_) {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    final heroBottom = tester.getBottomLeft(
      find.byKey(const ValueKey<String>('detail_hero_section')),
    );
    final shelfTop = tester.getTopLeft(
      find.byKey(const ValueKey<String>('detail_lower_shelf')),
    );

    expect(heroBottom.dy, lessThan(shelfTop.dy));
  });

  testWidgets(
      'DetailScreen scrolls recommendations into view and snaps back up',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final summary = MediaSummary(
      tmdbId: 552,
      mediaType: MediaType.movie,
      title: 'Beauty',
      overview:
          'A long overview that keeps the hero stack tall enough to require scrolling on shorter layouts.',
      rating: 4.8,
      releaseDate: DateTime.utc(2022, 6, 29),
      runtimeMinutes: 95,
    );
    final recommendations = List<MediaSummary>.generate(
      5,
      (index) => MediaSummary(
        tmdbId: 560 + index,
        mediaType: MediaType.movie,
        title: 'Recommendation ${index + 1}',
        releaseDate: DateTime.utc(2025, 1, index + 1),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DetailScreen(
          activeProfile: Profile(
            id: 'p1',
            name: 'Cherif',
            avatarLabel: 'C',
            languageCode: 'en',
            maturityTier: MaturityTier.mature,
            createdAt: DateTime.utc(2026, 3, 8),
          ),
          summary: summary,
          languageCode: 'en',
          mediaCatalogService: _FakeTmdbCatalogService(
            detail: summary,
            metadata: TitleMetadata(
              summary: summary,
              certification: 'R',
              genres: const <String>['Romance'],
            ),
            recommendations: recommendations,
          ),
          playbackProgress: PlaybackProgressSnapshot.empty(),
          isSaved: false,
          onBack: () {},
          onPlay: () {},
          onToggleSaved: () {},
          onOpenTitle: (_) {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    final firstRecommendationKey = ValueKey<String>(
      'detail_recommendation_${recommendations.first.saveKey}_0',
    );
    await tester.ensureVisible(find.byKey(firstRecommendationKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(firstRecommendationKey));
    await tester.pumpAndSettle();

    expect(_primaryFocusLabel(), 'DetailFirstRecommendation');
    final bodyRect = tester.getRect(
      find.byKey(const ValueKey<String>('detail_body_list')),
    );
    final recommendationRect = tester.getRect(
      find.byKey(firstRecommendationKey),
    );
    expect(recommendationRect.bottom, lessThanOrEqualTo(bodyRect.bottom));

    await tester.drag(
      find.byKey(const ValueKey<String>('detail_body_list')),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();

    expect(_detailBodyScrollOffset(tester), greaterThan(0));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(_primaryFocusLabel(), 'DetailOverviewTab');
    expect(_detailBodyScrollOffset(tester), closeTo(0, 1.0));
  });

  testWidgets(
      'DetailScreen reloads the backdrop preview when auto mute trailers changes',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final summary = MediaSummary(
      tmdbId: 90300,
      mediaType: MediaType.movie,
      title: 'Backdrop Preview Audio',
      overview: 'Verifies the detail backdrop preview reads mute settings.',
      releaseDate: DateTime.utc(2026, 3, 1),
    );
    final service = _FakeTmdbCatalogService(
      detail: summary,
      metadata: TitleMetadata(summary: summary),
      recommendations: const <MediaSummary>[],
    );

    Widget buildScreen({required bool muteAutoplayTrailers}) {
      return MaterialApp(
        home: DetailScreen(
          activeProfile: Profile(
            id: 'p1',
            name: 'Cherif',
            avatarLabel: 'C',
            languageCode: 'en',
            maturityTier: MaturityTier.mature,
            createdAt: DateTime.utc(2026, 3, 8),
          ),
          summary: summary,
          languageCode: 'en',
          mediaCatalogService: service,
          playbackProgress: PlaybackProgressSnapshot.empty(),
          isSaved: false,
          muteAutoplayTrailers: muteAutoplayTrailers,
          onBack: () {},
          onPlay: () {},
          onToggleSaved: () {},
        ),
      );
    }

    await tester.pumpWidget(buildScreen(muteAutoplayTrailers: true));
    await tester.pumpAndSettle();

    expect(service.previewRequests, contains(_previewKey(summary)));
    expect(
      service.previewRequests,
      isNot(contains(_previewKey(summary, muted: false))),
    );

    await tester.pumpWidget(buildScreen(muteAutoplayTrailers: false));
    await tester.pumpAndSettle();

    expect(
      service.previewRequests,
      contains(_previewKey(summary, muted: false)),
    );
  });
}

String _primaryFocusLabel() {
  return FocusManager.instance.primaryFocus?.debugLabel ?? '';
}

String _previewKey(MediaSummary item, {bool muted = true}) {
  return '${item.mediaType.name}:${item.tmdbId}:${muted ? 'muted' : 'audio'}';
}

double _detailBodyScrollOffset(WidgetTester tester) {
  final listView = tester.widget<ListView>(
    find.byKey(const ValueKey<String>('detail_body_list')),
  );
  return listView.controller?.offset ?? 0;
}

class _FakeTmdbCatalogService extends TmdbMediaCatalogService {
  _FakeTmdbCatalogService({
    required this.detail,
    required this.metadata,
    required this.recommendations,
    this.logo,
  }) : super(
          tmdbClient: TmdbClient(apiKey: 'test'),
          cacheStore: const _NoopJsonCacheStore(),
        );

  final MediaSummary detail;
  final TitleMetadata metadata;
  final List<MediaSummary> recommendations;
  final TmdbTitleLogo? logo;
  final List<String> previewRequests = <String>[];

  @override
  Future<MediaSummary> fetchTitleDetails({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) async {
    return detail;
  }

  @override
  Future<TitleMetadata> fetchTitleMetadata({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) async {
    return metadata;
  }

  @override
  Future<List<MediaSummary>> fetchRecommendations({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) async {
    return recommendations;
  }

  @override
  Future<TmdbTitleLogo?> fetchPreferredTitleLogo({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) async {
    return logo;
  }

  @override
  Future<Uri?> fetchTrailerPreviewUri({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
    bool muted = true,
  }) async {
    previewRequests.add(
      '${mediaType.name}:$tmdbId:${muted ? 'muted' : 'audio'}',
    );
    return Uri.parse(
      'https://example.com/trailers/$tmdbId/${muted ? 'muted' : 'audio'}',
    );
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
