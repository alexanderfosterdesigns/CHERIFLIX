import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/home_catalog_data.dart';
import 'package:cheriflix/core/models/just_released_catalog.dart';
import 'package:cheriflix/core/models/maturity_tier.dart';
import 'package:cheriflix/core/models/media_summary.dart';
import 'package:cheriflix/core/models/media_type.dart';
import 'package:cheriflix/core/models/profile.dart';
import 'package:cheriflix/core/services/media_catalog_service.dart';
import 'package:cheriflix/core/widgets/tv_shortcuts.dart';
import 'package:cheriflix/features/search/search_screen.dart';

void main() {
  testWidgets('SearchScreen performs live search from the on-screen keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dune = MediaSummary(
      tmdbId: 438631,
      mediaType: MediaType.movie,
      title: 'Dune',
      rating: 8.3,
      releaseDate: DateTime.utc(2021, 10, 22),
    );

    MediaSummary? opened;

    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(
          mediaCatalogService: _SearchCatalogService(
            responses: <String, List<MediaSummary>>{
              'DU': <MediaSummary>[dune],
            },
          ),
          languageCode: 'en',
          onBack: () {},
          onOpenTitle: (value) => opened = value,
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('D').first);
    await tester.pump();
    await tester.tap(find.text('U').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('Results for "DU"'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);

    await tester.tap(find.text('Dune'));
    await tester.pump();

    expect(opened?.tmdbId, 438631);
  });

  testWidgets('SearchScreen result cards keep compact non-autoplay behavior',
      (tester) async {
    final dune = MediaSummary(
      tmdbId: 438631,
      mediaType: MediaType.movie,
      title: 'Dune',
      rating: 8.3,
      releaseDate: DateTime.utc(2021, 10, 22),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(
          mediaCatalogService: _SearchCatalogService(
            responses: <String, List<MediaSummary>>{
              'DU': <MediaSummary>[dune],
            },
          ),
          languageCode: 'en',
          onBack: () {},
          onOpenTitle: (_) {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('D').first);
    await tester.pump();
    await tester.tap(find.text('U').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    final posterButton = tester.widget<TvPosterButton>(
      find.byType(TvPosterButton),
    );
    expect(posterButton.expandOnFocus, isFalse);
    expect(posterButton.overlayExpandedDetails, isFalse);
    expect(posterButton.autoplayPreviewEnabled, isFalse);
    expect(posterButton.autoplayPreviewMuted, isTrue);
    expect(
      posterButton.previewLoadDelay,
      const Duration(milliseconds: 1800),
    );
  });

  testWidgets('SearchScreen cursor keys insert text at the cursor',
      (tester) async {
    final craft = MediaSummary(
      tmdbId: 9001,
      mediaType: MediaType.movie,
      title: 'Craft',
      releaseDate: DateTime.utc(2024, 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(
          mediaCatalogService: _SearchCatalogService(
            responses: <String, List<MediaSummary>>{
              'CRAT': <MediaSummary>[craft],
            },
          ),
          languageCode: 'en',
          onBack: () {},
          onOpenTitle: (_) {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    void pressKey(String label) {
      tester
          .widget<TvActionButton>(
            find.widgetWithText(TvActionButton, label).first,
          )
          .onPressed!
          .call();
    }

    pressKey('C');
    await tester.pump();
    pressKey('A');
    await tester.pump();
    pressKey('T');
    await tester.pump();
    pressKey('←');
    await tester.pump();
    pressKey('←');
    await tester.pump();
    pressKey('R');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('Results for "CRAT"'), findsOneWidget);
    expect(find.text('Craft'), findsOneWidget);
  });

  testWidgets('SearchScreen routes backspace through the TV shortcut layer',
      (tester) async {
    var backInvoked = false;

    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(
          mediaCatalogService: _SearchCatalogService(
              responses: const <String, List<MediaSummary>>{}),
          languageCode: 'en',
          onBack: () => backInvoked = true,
          onOpenTitle: (_) {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(backInvoked, isTrue);
  });

  testWidgets(
      'SearchScreen can navigate down from the top bar into keyboard UI',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(
          mediaCatalogService: _SearchCatalogService(
            responses: const <String, List<MediaSummary>>{},
          ),
          languageCode: 'en',
          activeProfile: Profile(
            id: 'p1',
            name: 'Cherif',
            avatarLabel: 'C',
            languageCode: 'en',
            maturityTier: MaturityTier.mature,
            createdAt: DateTime.utc(2026, 3, 8),
          ),
          onBack: () {},
          onOpenTitle: (_) {},
          onBrowseHome: () {},
          onBrowseTvShows: () {},
          onBrowseMovies: () {},
          onBrowseNewPopular: () {},
          onBrowseMyList: () {},
          onOpenSettings: () {},
          onSwitchProfile: () {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('TvActionButton'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      anyOf(contains('SearchFirstKey'), contains('SearchKey')),
    );
  });

  testWidgets(
      'SearchScreen keeps top-bar down navigation working from far-right actions when results are empty',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(
          mediaCatalogService: _SearchCatalogService(
            responses: const <String, List<MediaSummary>>{},
          ),
          languageCode: 'en',
          activeProfile: Profile(
            id: 'p1',
            name: 'Cherif',
            avatarLabel: 'C',
            languageCode: 'en',
            maturityTier: MaturityTier.mature,
            createdAt: DateTime.utc(2026, 3, 8),
          ),
          onBack: () {},
          onOpenTitle: (_) {},
          onBrowseHome: () {},
          onBrowseTvShows: () {},
          onBrowseMovies: () {},
          onBrowseNewPopular: () {},
          onBrowseMyList: () {},
          onOpenSettings: () {},
          onSwitchProfile: () {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    for (var index = 0; index < 6; index += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      anyOf(contains('SearchFirstKey'), contains('SearchKey')),
    );
  });

  testWidgets('SearchScreen keyboard matrix navigates through the utility row',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(
          mediaCatalogService: _SearchCatalogService(
            responses: const <String, List<MediaSummary>>{},
          ),
          languageCode: 'en',
          onBack: () {},
          onOpenTitle: (_) {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('\u2191'), findsNothing);
    expect(find.text('\u2193'), findsNothing);

    for (var step = 0; step < 5; step += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    for (var step = 0; step < 4; step += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('SP'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('DEL'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('CLR'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('\u2190'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('\u2192'),
    );
  });

  testWidgets(
      'SearchScreen jumps from a keypad row boundary into results and back to the same key',
      (tester) async {
    final dune = MediaSummary(
      tmdbId: 438631,
      mediaType: MediaType.movie,
      title: 'Dune',
      rating: 8.3,
      releaseDate: DateTime.utc(2021, 10, 22),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(
          mediaCatalogService: _SearchCatalogService(
            responses: <String, List<MediaSummary>>{
              'DU': <MediaSummary>[dune],
            },
          ),
          languageCode: 'en',
          onBack: () {},
          onOpenTitle: (_) {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('D').first);
    await tester.pump();
    await tester.tap(find.text('U').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    for (var step = 0; step < 4; step += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'SearchResult[0]',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'SearchKey(2,7,X)',
    );
  });

  testWidgets(
      'SearchScreen keeps the bottom utility-row handoff into results working',
      (tester) async {
    final dune = MediaSummary(
      tmdbId: 438631,
      mediaType: MediaType.movie,
      title: 'Dune',
      rating: 8.3,
      releaseDate: DateTime.utc(2021, 10, 22),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(
          mediaCatalogService: _SearchCatalogService(
            responses: <String, List<MediaSummary>>{
              'DU': <MediaSummary>[dune],
            },
          ),
          languageCode: 'en',
          onBack: () {},
          onOpenTitle: (_) {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('D').first);
    await tester.pump();
    await tester.tap(find.text('U').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    tester
        .widget<TvActionButton>(find.widgetWithText(TvActionButton, 'CLR'))
        .focusNode!
        .requestFocus();
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'SearchKey(4,6,CLR)',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'SearchResult[0]',
    );
  });

  testWidgets(
      'SearchScreen can traverse across the full results grid beyond the first two cards',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final results = List<MediaSummary>.generate(
      8,
      (index) => MediaSummary(
        tmdbId: 2000 + index,
        mediaType: MediaType.movie,
        title: 'Bag ${index + 1}',
        releaseDate: DateTime.utc(2025, 1, index + 1),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(
          mediaCatalogService: _SearchCatalogService(
            responses: <String, List<MediaSummary>>{
              'BA': results,
            },
          ),
          languageCode: 'en',
          onBack: () {},
          onOpenTitle: (_) {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('B').first);
    await tester.pump();
    await tester.tap(find.text('A').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    for (var step = 0; step < 9; step += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'SearchResult[1]',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'SearchResult[2]',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'SearchResult[6]',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'SearchResult[5]',
    );
  });

  testWidgets(
      'SearchScreen keeps keypad boundary focus stable when no results are available',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(
          mediaCatalogService: _SearchCatalogService(
            responses: const <String, List<MediaSummary>>{},
          ),
          languageCode: 'en',
          onBack: () {},
          onOpenTitle: (_) {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('D').first);
    await tester.pump();
    await tester.tap(find.text('U').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    for (var step = 0; step < 4; step += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'SearchKey(2,7,X)',
    );
  });

  testWidgets('SearchScreen uses a denser results grid on wide layouts',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final results = List<MediaSummary>.generate(
      8,
      (index) => MediaSummary(
        tmdbId: 1000 + index,
        mediaType: MediaType.movie,
        title: 'Alpha ${index + 1}',
        rating: 7.0 + index / 10,
        releaseDate: DateTime.utc(2025, 1, index + 1),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(
          mediaCatalogService: _SearchCatalogService(
            responses: <String, List<MediaSummary>>{
              'DU': results,
            },
          ),
          languageCode: 'en',
          onBack: () {},
          onOpenTitle: (_) {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('D').first);
    await tester.pump();
    await tester.tap(find.text('U').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Results for "DU"'), findsOneWidget);
    expect(find.byType(TvPosterButton), findsNWidgets(8));

    final firstRowY = tester.getTopLeft(find.byType(TvPosterButton).at(0)).dy;
    final fifthRowY = tester.getTopLeft(find.byType(TvPosterButton).at(4)).dy;

    expect((firstRowY - fifthRowY).abs(), lessThan(1));
  });

  testWidgets('SearchScreen keeps three results per row at TV scale',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final results = List<MediaSummary>.generate(
      6,
      (index) => MediaSummary(
        tmdbId: 3000 + index,
        mediaType: MediaType.movie,
        title: 'Delta ${index + 1}',
        releaseDate: DateTime.utc(2025, 2, index + 1),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(
          mediaCatalogService: _SearchCatalogService(
            responses: <String, List<MediaSummary>>{
              'DU': results,
            },
          ),
          languageCode: 'en',
          onBack: () {},
          onOpenTitle: (_) {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('D').first);
    await tester.pump();
    await tester.tap(find.text('U').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final firstRowY = tester.getTopLeft(find.byType(TvPosterButton).at(0)).dy;
    final thirdRowY = tester.getTopLeft(find.byType(TvPosterButton).at(2)).dy;
    final fourthRowY = tester.getTopLeft(find.byType(TvPosterButton).at(3)).dy;

    expect((firstRowY - thirdRowY).abs(), lessThan(1));
    expect(fourthRowY, greaterThan(firstRowY + 1));
  });

  testWidgets('SearchScreen keeps every inset keyboard row visible at 803x360',
      (tester) async {
    tester.view.physicalSize = const Size(803, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(
          mediaCatalogService: null,
          languageCode: 'en',
          onBack: () {},
          onOpenTitle: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in <String>['A', 'I', 'Q', 'Y', '7', '\u2192']) {
      final key = find.widgetWithText(TvActionButton, label);
      expect(key, findsOneWidget);
      final rect = tester.getRect(key);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(360));
    }

    final firstKeyRect =
        tester.getRect(find.widgetWithText(TvActionButton, 'A'));
    final lastKeyRect =
        tester.getRect(find.widgetWithText(TvActionButton, '\u2192'));
    expect(lastKeyRect.top, greaterThan(firstKeyRect.top));
  });
}

class _SearchCatalogService implements MediaCatalogService {
  _SearchCatalogService({required this.responses});

  final Map<String, List<MediaSummary>> responses;

  @override
  Future<HomeCatalogData> fetchHomeCatalog(
      {required String languageCode}) async {
    throw UnimplementedError();
  }

  @override
  Future<JustReleasedCatalog> fetchJustReleasedCatalog({
    required String languageCode,
    required DateTime releasedAfter,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<MediaSummary> fetchTitleDetails({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<MediaSummary>> searchTitles({
    required String query,
    required String languageCode,
  }) async {
    return responses[query] ?? const <MediaSummary>[];
  }
}
