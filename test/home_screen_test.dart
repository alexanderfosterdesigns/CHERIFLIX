import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/home_catalog_data.dart';
import 'package:cheriflix/core/models/just_released_catalog.dart';
import 'package:cheriflix/core/models/maturity_tier.dart';
import 'package:cheriflix/core/models/media_summary.dart';
import 'package:cheriflix/core/models/media_type.dart';
import 'package:cheriflix/core/models/playback_progress_entry.dart';
import 'package:cheriflix/core/models/playback_progress_snapshot.dart';
import 'package:cheriflix/core/models/profile.dart';
import 'package:cheriflix/core/models/profile_playback_settings.dart';
import 'package:cheriflix/core/models/tmdb_title_logo.dart';
import 'package:cheriflix/core/services/json_cache_store.dart';
import 'package:cheriflix/core/services/media_catalog_service.dart';
import 'package:cheriflix/core/services/tmdb_client.dart';
import 'package:cheriflix/core/services/tmdb_media_catalog_service.dart';
import 'package:cheriflix/core/widgets/playback_progress_bar.dart';
import 'package:cheriflix/core/widgets/poster_preview_overlay.dart';
import 'package:cheriflix/core/widgets/cheriflix_title_mark.dart';
import 'package:cheriflix/core/widgets/tv_shortcuts.dart';
import 'package:cheriflix/features/home/home_screen.dart';

void main() {
  testWidgets('HomeScreen renders the static mockup hero and opens the feature',
      (tester) async {
    final featured = _media(
      tmdbId: 1399,
      mediaType: MediaType.movie,
      title: 'Game of Thrones',
      overview: 'Winter is coming.',
      rating: 9.2,
      releaseDate: DateTime.utc(2011, 4, 17),
    );
    final dune = _media(
      tmdbId: 438631,
      mediaType: MediaType.movie,
      title: 'Dune',
      rating: 8.3,
      releaseDate: DateTime.utc(2021, 10, 22),
    );

    MediaSummary? opened;
    await _pumpHome(
      tester,
      service: _FakeCatalogService(
        _catalog(
          featured: featured,
          newOnStreaming: <MediaSummary>[dune],
          trending: <MediaSummary>[featured],
          popularMovies: <MediaSummary>[dune],
          popularSeries: <MediaSummary>[featured],
          newAndPopular: <MediaSummary>[dune],
        ),
      ),
      onOpenTitle: (value) => opened = value,
      onToggleSaved: (_) {},
    );

    expect(find.text('GAME OF THRONES'), findsOneWidget);
    expect(find.text('New On Streaming', skipOffstage: false), findsOneWidget);
    expect(find.text('Add to My List'), findsOneWidget);
    expect(find.byType(PlaybackProgressBar), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('hero_play_button')));
    await tester.pump();

    expect(opened?.tmdbId, 1399);
  });

  testWidgets('HomeScreen puts a bounded TMDB logo over the looping hero',
      (tester) async {
    final featured = _media(
      tmdbId: 44242,
      mediaType: MediaType.tv,
      title: 'Devious Maids',
    );
    final service = _FakeTmdbHomeCatalogService(
      _catalog(
        featured: featured,
        newOnStreaming: <MediaSummary>[featured],
        trending: <MediaSummary>[featured],
        popularMovies: const <MediaSummary>[],
        popularSeries: <MediaSummary>[featured],
        newAndPopular: <MediaSummary>[featured],
      ),
      titleLogo: const TmdbTitleLogo(
        filePath: '',
        width: 2968,
        height: 1300,
        languageCode: 'en',
      ),
    );

    await _pumpHome(tester, service: service, settle: false);
    await tester.pump();
    await tester.pump();

    final mark = tester.widget<CheriflixTitleMark>(
      find.byType(CheriflixTitleMark),
    );
    expect(mark.logo?.width, 2968);
    expect(mark.maxHeight, lessThanOrEqualTo(138));
    expect(find.byKey(const ValueKey<String>('home_hero_banner')), findsOne);
  });

  testWidgets(
      'HomeScreen new and popular browse mode uses the renamed nav label and release rails',
      (tester) async {
    final featured = _media(
      tmdbId: 111,
      mediaType: MediaType.movie,
      title: 'Launch Feature',
    );
    final freshArrival = _media(
      tmdbId: 112,
      mediaType: MediaType.movie,
      title: 'Fresh Arrival',
    );
    final topRatedRecent = _media(
      tmdbId: 113,
      mediaType: MediaType.tv,
      title: 'Critics Choice',
      rating: 9.1,
    );
    final thriller = _media(
      tmdbId: 114,
      mediaType: MediaType.movie,
      title: 'Night Run',
    );
    final romance = _media(
      tmdbId: 115,
      mediaType: MediaType.movie,
      title: 'Love Signal',
    );
    final drama = _media(
      tmdbId: 116,
      mediaType: MediaType.movie,
      title: 'Heavy Weather',
    );
    final streaming = _media(
      tmdbId: 117,
      mediaType: MediaType.tv,
      title: 'Now Streaming',
    );

    await _pumpHome(
      tester,
      service: _FakeCatalogService(
        _catalog(
          featured: featured,
          newOnStreaming: <MediaSummary>[streaming],
          trending: <MediaSummary>[topRatedRecent],
          popularMovies: <MediaSummary>[thriller],
          popularSeries: <MediaSummary>[featured],
          newAndPopular: <MediaSummary>[freshArrival],
        ),
        justReleasedCatalog: JustReleasedCatalog(
          recentReleases: <MediaSummary>[freshArrival, featured],
          topRatedRecent: <MediaSummary>[topRatedRecent],
          newThrillers: <MediaSummary>[thriller],
          newRomance: <MediaSummary>[romance],
          newDrama: <MediaSummary>[drama],
          justHitStreaming: <MediaSummary>[streaming],
        ),
      ),
      browseMode: BrowseMode.newPopular,
    );

    expect(find.text('New & Popular', skipOffstage: false), findsWidgets);
    expect(find.text('Top Rated Recent', skipOffstage: false), findsOneWidget);
    expect(find.text('New Thrillers', skipOffstage: false), findsOneWidget);
    expect(find.text('New Romance', skipOffstage: false), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('New Drama'),
      find.byKey(const ValueKey<String>('home_body_list')),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    expect(find.text('New Drama'), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('Just Hit Streaming'),
      find.byKey(const ValueKey<String>('home_body_list')),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();

    expect(find.text('Just Hit Streaming'), findsOneWidget);
  });

  testWidgets(
      'HomeScreen replaces the default New and Popular rail with personalized picks',
      (tester) async {
    final featured = _media(
      tmdbId: 211,
      mediaType: MediaType.movie,
      title: 'Profile Feature',
    );
    final personalized = _media(
      tmdbId: 212,
      mediaType: MediaType.tv,
      title: 'Personal Pick',
    );

    await _pumpHome(
      tester,
      service: _FakeCatalogService(
        _catalog(
          featured: featured,
          newOnStreaming: <MediaSummary>[featured],
          trending: <MediaSummary>[featured],
          popularMovies: <MediaSummary>[featured],
          popularSeries: <MediaSummary>[featured],
          newAndPopular: <MediaSummary>[featured],
        ),
      ),
      loadHomeRecommendations: () async => <MediaSummary>[personalized],
    );

    await tester.dragUntilVisible(
      find.text('Recommended For Cherif'),
      find.byKey(const ValueKey<String>('home_body_list')),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    expect(find.text('Recommended For Cherif'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('home_rail_list_New & Popular')),
      findsNothing,
    );
  });

  testWidgets('HomeScreen continue watching rail keeps progress bars visible',
      (tester) async {
    final featured = _media(
      tmdbId: 120,
      mediaType: MediaType.movie,
      title: 'Hero Feature',
    );
    final resumeShow = _media(
      tmdbId: 121,
      mediaType: MediaType.tv,
      title: 'The Rookie',
    );

    await _pumpHome(
      tester,
      service: _FakeCatalogService(
        _catalog(
          featured: featured,
          newOnStreaming: <MediaSummary>[resumeShow],
          trending: <MediaSummary>[featured],
          popularMovies: <MediaSummary>[featured],
          popularSeries: <MediaSummary>[resumeShow],
          newAndPopular: <MediaSummary>[featured],
        ),
      ),
      playbackProgressByKey: <String, PlaybackProgressEntry>{
        resumeShow.saveKey: PlaybackProgressEntry(
          summary: resumeShow,
          seasonNumber: 1,
          episodeNumber: 2,
          episodeTitle: 'Crash Course',
          position: const Duration(minutes: 9),
          totalDuration: const Duration(minutes: 42),
          updatedAt: DateTime.utc(2026, 3, 12),
        ),
      },
    );

    expect(find.text('Continue Watching', skipOffstage: false), findsOneWidget);
    expect(
      find.byType(PlaybackProgressBar, skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('HomeScreen plays continue watching cards directly',
      (tester) async {
    final featured = _media(
      tmdbId: 220,
      mediaType: MediaType.movie,
      title: 'Hero Feature',
    );
    final resumeShow = _media(
      tmdbId: 221,
      mediaType: MediaType.tv,
      title: 'The Rookie',
    );
    final normalMovie = _media(
      tmdbId: 222,
      mediaType: MediaType.movie,
      title: 'Normal Movie',
    );
    MediaSummary? openedTitle;
    MediaSummary? playedTitle;

    await _pumpHome(
      tester,
      service: _FakeCatalogService(
        _catalog(
          featured: featured,
          newOnStreaming: <MediaSummary>[normalMovie],
          trending: <MediaSummary>[featured],
          popularMovies: <MediaSummary>[normalMovie],
          popularSeries: <MediaSummary>[resumeShow],
          newAndPopular: <MediaSummary>[featured],
        ),
      ),
      onOpenTitle: (value) => openedTitle = value,
      onPlayTitle: (value) => playedTitle = value,
      playbackProgressByKey: <String, PlaybackProgressEntry>{
        resumeShow.saveKey: PlaybackProgressEntry(
          summary: resumeShow,
          seasonNumber: 1,
          episodeNumber: 2,
          episodeTitle: 'Crash Course',
          position: const Duration(minutes: 9),
          totalDuration: const Duration(minutes: 42),
          updatedAt: DateTime.utc(2026, 3, 12),
        ),
      },
    );

    tester
        .widget<TvPosterButton>(
          find.byKey(
            const ValueKey<String>('home_rail_Continue Watching_tv:221_0'),
            skipOffstage: false,
          ),
        )
        .onPressed();
    await tester.pump();

    expect(playedTitle?.tmdbId, 221);
    expect(openedTitle, isNull);

    playedTitle = null;
    tester
        .widget<TvPosterButton>(
          find.byKey(
            const ValueKey<String>('home_rail_New On Streaming_movie:222_0'),
            skipOffstage: false,
          ),
        )
        .onPressed();
    await tester.pump();

    expect(openedTitle?.tmdbId, 222);
    expect(playedTitle, isNull);
  });

  testWidgets(
      'HomeScreen top bar can move down from the far right into the hero actions',
      (tester) async {
    final featured = _media(
      tmdbId: 300,
      mediaType: MediaType.movie,
      title: 'Focus Feature',
    );
    final railItem = _media(
      tmdbId: 301,
      mediaType: MediaType.movie,
      title: 'Rail Item',
    );

    await _pumpHome(
      tester,
      service: _FakeCatalogService(
        _catalog(
          featured: featured,
          newOnStreaming: <MediaSummary>[railItem],
          trending: <MediaSummary>[railItem],
          popularMovies: <MediaSummary>[featured],
          popularSeries: <MediaSummary>[featured],
          newAndPopular: <MediaSummary>[railItem],
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(_primaryFocusLabel(), 'HomeTopBarHome');

    for (var step = 0; step < 7; step += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    expect(_primaryFocusLabel(), 'HomeTopBarProfiles');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(_primaryFocusLabel(), 'HomeHeroPlay');
  });

  testWidgets(
      'HomeScreen uses inline preview rails with save badges and expanded actions',
      (tester) async {
    final featured = _media(
      tmdbId: 401,
      mediaType: MediaType.movie,
      title: 'Hero Feature',
    );
    final alpha = _media(
      tmdbId: 402,
      mediaType: MediaType.movie,
      title: 'Alpha',
    );
    final beta = _media(
      tmdbId: 403,
      mediaType: MediaType.movie,
      title: 'Beta',
    );

    await _pumpHome(
      tester,
      service: _FakeCatalogService(
        _catalog(
          featured: featured,
          newOnStreaming: <MediaSummary>[alpha, beta],
          trending: <MediaSummary>[featured],
          popularMovies: <MediaSummary>[featured],
          popularSeries: <MediaSummary>[featured],
          newAndPopular: <MediaSummary>[featured],
        ),
      ),
      savedTitleKeys: <String>{beta.saveKey},
    );

    final alphaCard = find.byKey(
      ValueKey<String>('home_rail_New On Streaming_${alpha.saveKey}_0'),
    );
    final betaCard = find.byKey(
      ValueKey<String>('home_rail_New On Streaming_${beta.saveKey}_1'),
    );

    expect(
      find.descendant(of: alphaCard, matching: find.text('SAVE')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: betaCard, matching: find.text('SAVED')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_primaryFocusLabel(), 'HomeFirstRail');

    final alphaSurface = find.byKey(
      ValueKey<String>('home_rail_surface_New On Streaming_${alpha.saveKey}_0'),
    );
    expect(find.byType(PosterPreviewOverlay), findsNothing);
    expect(
      find.descendant(of: alphaSurface, matching: find.text('Play')),
      findsOneWidget,
    );
  });

  testWidgets(
      'HomeScreen loads the hero trailer only after the focused delay elapses',
      (tester) async {
    final featured = _media(
      tmdbId: 610,
      mediaType: MediaType.movie,
      title: 'Focus Hero',
    );
    final railItem = _media(
      tmdbId: 611,
      mediaType: MediaType.tv,
      title: 'Rail Preview',
    );
    final service = _FakeTmdbHomeCatalogService(
      _catalog(
        featured: featured,
        newOnStreaming: <MediaSummary>[railItem],
        trending: <MediaSummary>[featured],
        popularMovies: <MediaSummary>[featured],
        popularSeries: <MediaSummary>[railItem],
        newAndPopular: <MediaSummary>[featured],
      ),
    );

    await _pumpHome(
      tester,
      service: service,
      settle: false,
    );

    expect(_primaryFocusLabel(), 'HomeHeroPlay');
    expect(service.previewRequests, isEmpty);

    await tester.pump(const Duration(milliseconds: 1799));
    expect(service.previewRequests, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(service.previewRequests, contains(_previewKey(featured)));
  });

  testWidgets(
      'HomeScreen cancels the hero trailer when focus moves into the first rail and loads the card preview instead',
      (tester) async {
    final featured = _media(
      tmdbId: 620,
      mediaType: MediaType.movie,
      title: 'Leaving Hero',
    );
    final railItem = _media(
      tmdbId: 621,
      mediaType: MediaType.tv,
      title: 'Focused Card',
    );
    final service = _FakeTmdbHomeCatalogService(
      _catalog(
        featured: featured,
        newOnStreaming: <MediaSummary>[railItem],
        trending: <MediaSummary>[featured],
        popularMovies: <MediaSummary>[featured],
        popularSeries: <MediaSummary>[railItem],
        newAndPopular: <MediaSummary>[featured],
      ),
    );

    await _pumpHome(
      tester,
      service: service,
      settle: false,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(_primaryFocusLabel(), 'HomeFirstRail');
    expect(service.previewRequests, isEmpty);

    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump();

    expect(service.previewRequests, isNot(contains(_previewKey(featured))));
    expect(service.previewRequests, contains(_previewKey(railItem)));
  });

  testWidgets(
      'HomeScreen reloads hero and rail trailer requests when autoplay mute changes',
      (tester) async {
    final featured = _media(
      tmdbId: 630,
      mediaType: MediaType.movie,
      title: 'Audio Toggle Hero',
    );
    final railItem = _media(
      tmdbId: 631,
      mediaType: MediaType.movie,
      title: 'Audio Toggle Card',
    );
    final service = _FakeTmdbHomeCatalogService(
      _catalog(
        featured: featured,
        newOnStreaming: <MediaSummary>[railItem],
        trending: <MediaSummary>[featured],
        popularMovies: <MediaSummary>[featured],
        popularSeries: <MediaSummary>[railItem],
        newAndPopular: <MediaSummary>[featured],
      ),
    );

    await _pumpHome(
      tester,
      service: service,
      playbackSettings: const ProfilePlaybackSettings(languageCode: 'en'),
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump();

    expect(service.previewRequests, contains(_previewKey(featured)));
    expect(service.previewRequests, contains(_previewKey(railItem)));

    await _pumpHome(
      tester,
      service: service,
      playbackSettings: const ProfilePlaybackSettings(
        languageCode: 'en',
        muteAutoplayTrailers: false,
      ),
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump();

    expect(
      service.previewRequests,
      contains(_previewKey(featured, muted: false)),
    );
    expect(
      service.previewRequests,
      contains(_previewKey(railItem, muted: false)),
    );
  });

  testWidgets('HomeScreen hero remains stable while preview loading settles',
      (tester) async {
    final featured = _media(
      tmdbId: 501,
      mediaType: MediaType.movie,
      title: 'Static Hero',
    );

    await _pumpHome(
      tester,
      service: _FakeCatalogService(
        _catalog(
          featured: featured,
          newOnStreaming: <MediaSummary>[featured],
          trending: <MediaSummary>[featured],
          popularMovies: <MediaSummary>[featured],
          popularSeries: <MediaSummary>[featured],
          newAndPopular: <MediaSummary>[featured],
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(find.text('STATIC HERO'), findsOneWidget);
    expect(_bodyScrollOffset(tester), closeTo(0, 0.1));
  });

  testWidgets(
      'HomeScreen keeps the same hero banner height for the same logical size across DPRs',
      (tester) async {
    final featured = _media(
      tmdbId: 710,
      mediaType: MediaType.movie,
      title: 'Logical Size Hero',
    );
    final railItem = _media(
      tmdbId: 711,
      mediaType: MediaType.movie,
      title: 'Logical Size Rail',
    );
    final service = _FakeCatalogService(
      _catalog(
        featured: featured,
        newOnStreaming: <MediaSummary>[railItem],
        trending: <MediaSummary>[railItem],
        popularMovies: <MediaSummary>[railItem],
        popularSeries: <MediaSummary>[railItem],
        newAndPopular: <MediaSummary>[railItem],
      ),
    );

    await _pumpHome(
      tester,
      service: service,
      physicalSize: const Size(1280, 720),
      devicePixelRatio: 1.0,
    );
    final standardDprHeight = tester
        .getSize(find.byKey(const ValueKey<String>('home_hero_banner')))
        .height;

    await _pumpHome(
      tester,
      service: service,
      physicalSize: const Size(2560, 1440),
      devicePixelRatio: 2.0,
    );
    final highDprHeight = tester
        .getSize(find.byKey(const ValueKey<String>('home_hero_banner')))
        .height;

    expect(highDprHeight, standardDprHeight);
  });

  testWidgets(
      'HomeScreen does not vertically jump while moving left and right inside a rail',
      (tester) async {
    final featured = _media(
      tmdbId: 720,
      mediaType: MediaType.movie,
      title: 'Stable Hero',
    );
    final railItems = List<MediaSummary>.generate(
      6,
      (index) => _media(
        tmdbId: 730 + index,
        mediaType: MediaType.movie,
        title: 'Rail $index',
      ),
    );

    await _pumpHome(
      tester,
      service: _FakeCatalogService(
        _catalog(
          featured: featured,
          newOnStreaming: railItems,
          trending: railItems,
          popularMovies: railItems,
          popularSeries: railItems,
          newAndPopular: railItems,
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    final beforeHorizontalMove = _bodyScrollOffset(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final afterRightMove = _bodyScrollOffset(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    final afterLeftMove = _bodyScrollOffset(tester);

    expect(afterRightMove, closeTo(beforeHorizontalMove, 0.5));
    expect(afterLeftMove, closeTo(beforeHorizontalMove, 0.5));
  });

  testWidgets(
      'HomeScreen moves rail focus immediately during rapid D-pad input',
      (tester) async {
    final featured = _media(
      tmdbId: 820,
      mediaType: MediaType.movie,
      title: 'Fast Hero',
    );
    final railItems = List<MediaSummary>.generate(
      8,
      (index) => _media(
        tmdbId: 830 + index,
        mediaType: MediaType.movie,
        title: 'Fast Rail $index',
      ),
    );

    await _pumpHome(
      tester,
      service: _FakeCatalogService(
        _catalog(
          featured: featured,
          newOnStreaming: railItems,
          trending: railItems,
          popularMovies: railItems,
          popularSeries: railItems,
          newAndPopular: railItems,
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(_primaryFocusLabel(), isNotEmpty);
    final beforeHorizontalMove = _bodyScrollOffset(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(_primaryFocusLabel(), endsWith('[1]'));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(_primaryFocusLabel(), endsWith('[2]'));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(_primaryFocusLabel(), endsWith('[3]'));

    await tester.pumpAndSettle();
    expect(_bodyScrollOffset(tester), closeTo(beforeHorizontalMove, 0.5));
  });
  testWidgets(
      'HomeScreen keeps rail slot geometry fixed while a card expands in the overlay',
      (tester) async {
    final featured = _media(
      tmdbId: 780,
      mediaType: MediaType.movie,
      title: 'Stable Hero',
    );
    final railItems = List<MediaSummary>.generate(
      6,
      (index) => _media(
        tmdbId: 781 + index,
        mediaType: MediaType.movie,
        title: 'Stable Card $index',
      ),
    );
    await _pumpHome(
      tester,
      service: _FakeCatalogService(
        _catalog(
          featured: featured,
          newOnStreaming: railItems,
          trending: railItems,
          popularMovies: railItems,
          popularSeries: const <MediaSummary>[],
          newAndPopular: railItems,
        ),
      ),
    );

    final card = find.byKey(
      ValueKey<String>(
        'home_rail_New On Streaming_${railItems.first.saveKey}_0',
      ),
    );
    final widthBeforeFocus = tester.getSize(card).width;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 220));

    expect(_primaryFocusLabel(), 'HomeFirstRail');
    expect(tester.getSize(card).width, closeTo(widthBeforeFocus, 0.1));
  });

  testWidgets('HomeScreen reuses its loaded catalog when browse tabs change',
      (tester) async {
    final featured = _media(
      tmdbId: 810,
      mediaType: MediaType.movie,
      title: 'Cached Feature',
    );
    final service = _FakeCatalogService(
      _catalog(
        featured: featured,
        newOnStreaming: <MediaSummary>[featured],
        trending: <MediaSummary>[featured],
        popularMovies: <MediaSummary>[featured],
        popularSeries: <MediaSummary>[featured],
        newAndPopular: <MediaSummary>[featured],
      ),
    );

    await _pumpHome(tester, service: service);
    expect(service.homeFetchCount, 1);

    await _pumpHome(
      tester,
      service: service,
      browseMode: BrowseMode.movies,
    );

    expect(service.homeFetchCount, 1);
    expect(find.text('Movies', skipOffstage: false), findsWidgets);
  });

  testWidgets('HomeScreen never launches a focused title automatically',
      (tester) async {
    final featured = _media(
      tmdbId: 820,
      mediaType: MediaType.movie,
      title: 'Manual Play Only',
    );
    var playCount = 0;

    await _pumpHome(
      tester,
      service: _FakeCatalogService(
        _catalog(
          featured: featured,
          newOnStreaming: <MediaSummary>[featured],
          trending: <MediaSummary>[featured],
          popularMovies: <MediaSummary>[featured],
          popularSeries: <MediaSummary>[featured],
          newAndPopular: <MediaSummary>[featured],
        ),
      ),
      playbackSettings: const ProfilePlaybackSettings(
        languageCode: 'en',
        autoplayPreviews: false,
      ),
      onPlayTitle: (_) => playCount += 1,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_primaryFocusLabel(), 'HomeFirstRail');

    await tester.pump(const Duration(seconds: 30));
    expect(playCount, 0);
  });
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required MediaCatalogService service,
  BrowseMode browseMode = BrowseMode.home,
  Future<List<MediaSummary>> Function()? loadHomeRecommendations,
  ValueChanged<MediaSummary>? onOpenTitle,
  ValueChanged<MediaSummary>? onPlayTitle,
  ValueChanged<MediaSummary>? onToggleSaved,
  Set<String> savedTitleKeys = const <String>{},
  Map<String, PlaybackProgressEntry> playbackProgressByKey =
      const <String, PlaybackProgressEntry>{},
  ProfilePlaybackSettings playbackSettings =
      const ProfilePlaybackSettings(languageCode: 'en'),
  bool settle = true,
  Size physicalSize = const Size(1600, 1200),
  double devicePixelRatio = 1.0,
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: HomeScreen(
        activeProfile: _profile(),
        playbackSettings: playbackSettings,
        mediaCatalogService: service,
        languageCode: 'en',
        savedTitleKeys: savedTitleKeys,
        playbackProgress: PlaybackProgressSnapshot(
          playbackProgressByKey.values,
        ),
        loadHomeRecommendations: loadHomeRecommendations,
        onOpenSearch: () {},
        onOpenSettings: () {},
        onSwitchProfile: () {},
        onOpenTitle: onOpenTitle ?? (_) {},
        onPlayTitle: onPlayTitle,
        onToggleSaved: onToggleSaved,
        browseMode: browseMode,
        onBrowseHome: () {},
        onBrowseTvShows: () {},
        onBrowseMovies: () {},
        onBrowseNewPopular: () {},
        onBrowseMyList: () {},
      ),
    ),
  );

  await tester.pump();
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

HomeCatalogData _catalog({
  required MediaSummary featured,
  required List<MediaSummary> newOnStreaming,
  required List<MediaSummary> trending,
  required List<MediaSummary> popularMovies,
  required List<MediaSummary> popularSeries,
  required List<MediaSummary> newAndPopular,
}) {
  return HomeCatalogData(
    featured: featured,
    newOnStreaming: newOnStreaming,
    trending: trending,
    popularMovies: popularMovies,
    popularSeries: popularSeries,
    newAndPopular: newAndPopular,
  );
}

MediaSummary _media({
  required int tmdbId,
  required MediaType mediaType,
  required String title,
  String? overview,
  double rating = 7.0,
  DateTime? releaseDate,
}) {
  return MediaSummary(
    tmdbId: tmdbId,
    mediaType: mediaType,
    title: title,
    overview: overview,
    rating: rating,
    releaseDate: releaseDate ?? DateTime.utc(2026, 1, 1),
  );
}

Profile _profile() {
  return Profile(
    id: 'p1',
    name: 'Cherif',
    avatarLabel: 'C',
    languageCode: 'en',
    maturityTier: MaturityTier.mature,
    createdAt: DateTime.utc(2026, 3, 7),
  );
}

String _primaryFocusLabel() {
  return FocusManager.instance.primaryFocus?.debugLabel ?? '';
}

double _bodyScrollOffset(WidgetTester tester) {
  final listView = tester.widget<ListView>(
    find.byKey(const ValueKey<String>('home_body_list')),
  );
  return listView.controller?.offset ?? 0;
}

String _previewKey(MediaSummary item, {bool muted = true}) {
  return '${item.mediaType.name}:${item.tmdbId}:${muted ? 'muted' : 'audio'}';
}

class _FakeCatalogService implements MediaCatalogService {
  _FakeCatalogService(
    this._catalog, {
    JustReleasedCatalog? justReleasedCatalog,
  }) : _justReleasedCatalog = justReleasedCatalog;

  final HomeCatalogData _catalog;
  final JustReleasedCatalog? _justReleasedCatalog;
  int homeFetchCount = 0;

  @override
  Future<HomeCatalogData> fetchHomeCatalog({
    required String languageCode,
  }) async {
    homeFetchCount += 1;
    return _catalog;
  }

  @override
  Future<JustReleasedCatalog> fetchJustReleasedCatalog({
    required String languageCode,
    required DateTime releasedAfter,
  }) async {
    return _justReleasedCatalog ?? _justReleasedFromHomeCatalog(_catalog);
  }

  @override
  Future<MediaSummary> fetchTitleDetails({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) async {
    return _catalog.featured;
  }

  @override
  Future<List<MediaSummary>> searchTitles({
    required String query,
    required String languageCode,
  }) async {
    return _catalog.trending;
  }
}

class _FakeTmdbHomeCatalogService extends TmdbMediaCatalogService {
  _FakeTmdbHomeCatalogService(
    this._catalog, {
    this.titleLogo,
  }) : super(
          tmdbClient: TmdbClient(apiKey: 'test'),
          cacheStore: const _NoopJsonCacheStore(),
        );

  final HomeCatalogData _catalog;
  final TmdbTitleLogo? titleLogo;
  final List<String> previewRequests = <String>[];

  @override
  TmdbTitleLogo? peekPreferredTitleLogo({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) {
    return titleLogo;
  }

  @override
  Future<TmdbTitleLogo?> fetchPreferredTitleLogo({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) async {
    return titleLogo;
  }

  @override
  Future<HomeCatalogData> fetchHomeCatalog({
    required String languageCode,
  }) async {
    return _catalog;
  }

  @override
  Future<JustReleasedCatalog> fetchJustReleasedCatalog({
    required String languageCode,
    required DateTime releasedAfter,
  }) async {
    return _justReleasedFromHomeCatalog(_catalog);
  }

  @override
  Future<MediaSummary> fetchTitleDetails({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) async {
    return _catalog.featured;
  }

  @override
  Future<List<MediaSummary>> searchTitles({
    required String query,
    required String languageCode,
  }) async {
    return _catalog.trending;
  }

  @override
  Future<Uri?> fetchTrailerPreviewUri({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
    bool muted = true,
  }) async {
    previewRequests.add(_previewKey(
        _media(
          tmdbId: tmdbId,
          mediaType: mediaType,
          title: 'preview',
        ),
        muted: muted));
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

JustReleasedCatalog _justReleasedFromHomeCatalog(HomeCatalogData catalog) {
  return JustReleasedCatalog(
    recentReleases: catalog.newAndPopular,
    topRatedRecent: catalog.trending,
    newThrillers: catalog.popularMovies,
    newRomance: catalog.newOnStreaming,
    newDrama: catalog.popularSeries,
    justHitStreaming: catalog.newOnStreaming,
  );
}
