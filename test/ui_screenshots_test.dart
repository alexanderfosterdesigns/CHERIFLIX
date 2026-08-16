import 'package:cheriflix/core/models/home_catalog_data.dart';
import 'package:cheriflix/core/models/just_released_catalog.dart';
import 'package:cheriflix/core/models/maturity_tier.dart';
import 'package:cheriflix/core/models/media_summary.dart';
import 'package:cheriflix/core/models/media_type.dart';
import 'package:cheriflix/core/models/playback_progress_entry.dart';
import 'package:cheriflix/core/models/playback_progress_snapshot.dart';
import 'package:cheriflix/core/models/profile.dart';
import 'package:cheriflix/core/models/profile_playback_settings.dart';
import 'package:cheriflix/core/services/media_catalog_service.dart';
import 'package:cheriflix/core/theme/cheriflix_theme.dart';
import 'package:cheriflix/features/details/detail_screen.dart';
import 'package:cheriflix/features/home/home_screen.dart';
import 'package:cheriflix/features/my_list/my_list_screen.dart';
import 'package:cheriflix/features/profile/profile_selection_screen.dart';
import 'package:cheriflix/features/search/search_screen.dart';
import 'package:cheriflix/features/settings/settings_screen.dart';
import 'package:cheriflix/features/splash/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _captureKey = ValueKey<String>('ui-capture');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture splash', (tester) async {
    await _pump(tester, const SplashScreen(loadingOnly: true));
    await tester.pump(const Duration(milliseconds: 900));
    await _capture(tester, '01_splash.png');
  });

  testWidgets('capture profile selection', (tester) async {
    await _pump(
      tester,
      ProfileSelectionScreen(
        profiles: <Profile>[_profile, _kidsProfile],
        onSelectProfile: (_) {},
        onCreateProfile: () {},
      ),
    );
    await tester.pumpAndSettle();
    await _capture(tester, '02_profiles.png');
  });

  testWidgets('capture home', (tester) async {
    final catalog = HomeCatalogData(
      featured: _titles.first,
      newOnStreaming: _titles.sublist(1),
      trending: _titles,
      popularMovies: _titles.where((item) => item.mediaType == MediaType.movie).toList(),
      popularSeries: _titles.where((item) => item.mediaType == MediaType.tv).toList(),
      newAndPopular: _titles.reversed.toList(),
    );
    await _pump(
      tester,
      HomeScreen(
        activeProfile: _profile,
        playbackSettings: const ProfilePlaybackSettings(
          languageCode: 'en',
          autoplayPreviews: false,
        ),
        mediaCatalogService: _CatalogService(catalog),
        languageCode: 'en',
        onOpenSearch: () {},
        onOpenSettings: () {},
        onSwitchProfile: () {},
        onOpenTitle: (_) {},
        onPlayTitle: (_) {},
        onToggleSaved: (_) {},
        playbackProgress: PlaybackProgressSnapshot.empty(),
        onBrowseHome: () {},
        onBrowseTvShows: () {},
        onBrowseMovies: () {},
        onBrowseNewPopular: () {},
        onBrowseMyList: () {},
      ),
    );
    await tester.pumpAndSettle();
    await _capture(tester, '03_home.png');
  });

  testWidgets('capture search', (tester) async {
    await _pump(
      tester,
      SearchScreen(
        mediaCatalogService: _CatalogService(
          HomeCatalogData(
            featured: _titles.first,
            newOnStreaming: _titles,
            trending: _titles,
            popularMovies: _titles,
            popularSeries: _titles,
            newAndPopular: _titles,
          ),
        ),
        languageCode: 'en',
        activeProfile: _profile,
        onBack: () {},
        onOpenTitle: (_) {},
        onPlayTitle: (_) {},
        onToggleSaved: (_) {},
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('D').first);
    await tester.pump();
    await tester.tap(find.text('U').first);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    await _capture(tester, '04_search.png');
  });

  testWidgets('capture my list', (tester) async {
    final started = PlaybackProgressEntry(
      summary: _titles[2],
      seasonNumber: 1,
      episodeNumber: 3,
      episodeTitle: 'The Bet',
      position: const Duration(minutes: 18),
      totalDuration: const Duration(minutes: 43),
      updatedAt: DateTime.utc(2026, 8, 15),
    );
    final watched = PlaybackProgressEntry(
      summary: _titles[1],
      position: const Duration(minutes: 155),
      totalDuration: const Duration(minutes: 155),
      updatedAt: DateTime.utc(2026, 8, 14),
    );
    await _pump(
      tester,
      MyListScreen(
        activeProfile: _profile,
        savedTitles: _titles,
        playbackProgress: PlaybackProgressSnapshot(<PlaybackProgressEntry>[started, watched]),
        mediaCatalogService: null,
        languageCode: 'en',
        autoplayPreviews: false,
        muteAutoplayTrailers: true,
        onOpenTitle: (_) {},
        onPlayTitle: (_) {},
        onToggleSaved: (_) {},
      ),
    );
    await tester.pumpAndSettle();
    await _capture(tester, '05_my_list.png');
  });

  testWidgets('capture details', (tester) async {
    await _pump(
      tester,
      DetailScreen(
        activeProfile: _profile,
        summary: _titles.first,
        languageCode: 'en',
        onBack: () {},
        onPlay: () {},
        isSaved: false,
        onToggleSaved: () {},
        playbackProgress: PlaybackProgressSnapshot.empty(),
        autoplayPreviews: false,
      ),
    );
    await tester.pumpAndSettle();
    await _capture(tester, '06_details.png');
  });

  testWidgets('capture settings', (tester) async {
    await _pump(
      tester,
      SettingsScreen(
        activeProfile: _profile,
        playbackSettings: const ProfilePlaybackSettings(languageCode: 'en'),
        hideSpoilers: false,
        onHideSpoilersChanged: (_) {},
        onBack: () {},
        onSaveProfile: (_) {},
        onSavePlaybackSettings: (_) {},
        onCheckForUpdates: () async {},
      ),
    );
    await tester.pumpAndSettle();
    await _capture(tester, '07_settings.png');
  });
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      title: 'CHERIFLIX',
      theme: buildCheriflixTheme(),
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(key: _captureKey, child: screen),
    ),
  );
  await tester.pump();
}

Future<void> _capture(WidgetTester tester, String name) {
  return expectLater(
    find.byKey(_captureKey),
    matchesGoldenFile('ui_screenshots/$name'),
  );
}

final Profile _profile = Profile(
  id: 'p1',
  name: 'Cherif',
  avatarLabel: 'C',
  languageCode: 'en',
  maturityTier: MaturityTier.mature,
  createdAt: DateTime.utc(2026, 3, 8),
);

final Profile _kidsProfile = Profile(
  id: 'p2',
  name: 'Kids',
  avatarLabel: 'K',
  languageCode: 'en',
  maturityTier: MaturityTier.kids,
  createdAt: DateTime.utc(2026, 3, 8),
);

final List<MediaSummary> _titles = <MediaSummary>[
  MediaSummary(
    tmdbId: 1399,
    mediaType: MediaType.tv,
    title: 'Game of Thrones',
    overview: 'Nine noble families fight for control over the lands of Westeros, while an ancient enemy returns after being dormant for millennia.',
    rating: 9.2,
    releaseDate: DateTime.utc(2011, 4, 17),
    genreNames: <String>['Drama', 'Fantasy'],
    runtimeMinutes: 58,
    seasonCount: 8,
  ),
  MediaSummary(
    tmdbId: 438631,
    mediaType: MediaType.movie,
    title: 'Dune',
    overview: 'A gifted young man must travel to the most dangerous planet in the universe to ensure the future of his family and his people.',
    rating: 8.3,
    releaseDate: DateTime.utc(2021, 10, 22),
    genreNames: <String>['Science Fiction'],
    runtimeMinutes: 155,
  ),
  MediaSummary(
    tmdbId: 79744,
    mediaType: MediaType.tv,
    title: 'The Rookie',
    overview: 'John Nolan starts over and joins the LAPD.',
    rating: 8.5,
    releaseDate: DateTime.utc(2018, 10, 16),
    genreNames: <String>['Crime', 'Drama'],
    runtimeMinutes: 43,
    seasonCount: 7,
  ),
  MediaSummary(
    tmdbId: 845781,
    mediaType: MediaType.movie,
    title: 'Carry-On',
    overview: 'A traveler is blackmailed into letting a dangerous package slip onto a Christmas Eve flight.',
    rating: 7.0,
    releaseDate: DateTime.utc(2024, 12, 13),
    genreNames: <String>['Thriller'],
    runtimeMinutes: 119,
  ),
  MediaSummary(
    tmdbId: 66732,
    mediaType: MediaType.tv,
    title: 'Stranger Things',
    rating: 8.7,
    releaseDate: DateTime.utc(2016, 7, 15),
    genreNames: <String>['Drama', 'Mystery'],
    seasonCount: 5,
  ),
];

class _CatalogService implements MediaCatalogService {
  const _CatalogService(this.catalog);
  final HomeCatalogData catalog;

  @override
  Future<HomeCatalogData> fetchHomeCatalog({required String languageCode}) async => catalog;

  @override
  Future<JustReleasedCatalog> fetchJustReleasedCatalog({
    required String languageCode,
    required DateTime releasedAfter,
  }) async => JustReleasedCatalog(
    recentReleases: catalog.newAndPopular,
    topRatedRecent: catalog.trending,
    newThrillers: catalog.popularMovies,
    newRomance: const <MediaSummary>[],
    newDrama: catalog.popularSeries,
    justHitStreaming: catalog.newOnStreaming,
  );

  @override
  Future<MediaSummary> fetchTitleDetails({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) async => catalog.featured;

  @override
  Future<List<MediaSummary>> searchTitles({
    required String query,
    required String languageCode,
  }) async => query.isEmpty ? const <MediaSummary>[] : catalog.trending;
}
