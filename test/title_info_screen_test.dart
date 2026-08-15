import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/media_summary.dart';
import 'package:cheriflix/core/models/media_type.dart';
import 'package:cheriflix/core/models/title_metadata.dart';
import 'package:cheriflix/core/services/json_cache_store.dart';
import 'package:cheriflix/core/services/tmdb_client.dart';
import 'package:cheriflix/core/services/tmdb_media_catalog_service.dart';
import 'package:cheriflix/features/details/title_info_screen.dart';

void main() {
  testWidgets('TitleInfoScreen renders cast and production details',
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
      genreNames: const <String>['Drama', 'Crime'],
    );
    final metadata = TitleMetadata(
      summary: summary,
      certification: 'TV-14',
      tagline: 'Never too late for a second chance.',
      status: 'Returning Series',
      originalTitle: 'The Rookie',
      originalLanguage: 'en',
      homepage: 'https://example.com/the-rookie',
      genres: const <String>['Drama', 'Crime'],
      studios: const <String>['Entertainment One'],
      networks: const <String>['ABC'],
      spokenLanguages: const <String>['English'],
      originCountries: const <String>['US'],
      creators: const <String>['Alexi Hawley'],
      writers: const <String>['Alexi Hawley'],
      cast: const <TitleCredit>[
        TitleCredit(
          name: 'Nathan Fillion',
          role: 'John Nolan',
        ),
        TitleCredit(
          name: 'Melissa O\'Neil',
          role: 'Lucy Chen',
        ),
      ],
      crew: const <TitleCredit>[
        TitleCredit(
          name: 'Bill Roe',
          role: 'Executive Producer',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TitleInfoScreen(
          summary: summary,
          languageCode: 'en',
          mediaCatalogService: _FakeMetadataCatalogService(
            metadata: metadata,
          ),
          onBack: () {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('DETAILS'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Creative Team'), findsOneWidget);
    expect(find.text('Quick Facts'), findsOneWidget);
    expect(find.text('Featured Cast'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('title_info_cast_grid')),
      findsOneWidget,
    );
    expect(find.text('Cast & Crew'), findsNothing);
    expect(find.text('Nathan Fillion'), findsOneWidget);
    expect(find.text('Alexi Hawley'), findsWidgets);
    expect(find.text('TV-14'), findsWidgets);
  });

  testWidgets(
      'TitleInfoScreen keeps long details readable at 960x540 without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final summary = MediaSummary(
      tmdbId: 99111,
      mediaType: MediaType.movie,
      title: 'The Impossible Story of Extremely Long Metadata',
      overview:
          'A deliberately long synopsis used to verify that detail copy remains readable when the viewport is compact.',
      rating: 7.3,
      releaseDate: DateTime.utc(2025, 11, 2),
      runtimeMinutes: 142,
      genreNames: const <String>['Drama', 'Thriller', 'Mystery'],
    );
    final metadata = TitleMetadata(
      summary: summary,
      certification: 'PG-13',
      tagline: 'One headline, many moving parts.',
      status: 'Released',
      originalTitle: 'La Historia Imposible del Metadata Extendido',
      originalLanguage: 'es',
      homepage: 'https://example.com/impossible-story',
      genres: const <String>['Drama', 'Thriller', 'Mystery'],
      studios: const <String>[
        'An Incredibly Verbose Studio Name That Keeps Going',
      ],
      networks: const <String>['A Very Long Premium Network Brand Name'],
      spokenLanguages: const <String>[
        'English',
        'Spanish',
        'French',
        'Portuguese',
      ],
      originCountries: const <String>['US', 'GB', 'ES'],
      creators: const <String>[
        'A Creator With A Name Long Enough To Force Wrapping',
      ],
      writers: const <String>[
        'A Writer With Another Long Name For Wrapping Validation',
      ],
      cast: const <TitleCredit>[
        TitleCredit(
          name: 'Alexandria Montgomery-Winters',
          role: 'Commander of the Continental Investigative Taskforce',
        ),
        TitleCredit(
          name: 'Jonathan Theodore Kensington III',
          role: 'Lead Biographer and Cultural Archivist',
        ),
        TitleCredit(
          name: 'Marisol Fernanda Rodriguez',
          role: 'International Correspondent',
        ),
        TitleCredit(
          name: 'Christopher Damian Holloway',
          role: 'Systems Analyst',
        ),
        TitleCredit(
          name: 'Priya Nandini Chakraborty',
          role: 'Chief Strategist',
        ),
        TitleCredit(
          name: 'Hugo Alejandro Martinez',
          role: 'Field Operations Director',
        ),
      ],
      crew: const <TitleCredit>[
        TitleCredit(
          name: 'Samantha Lee',
          role: 'Executive Producer',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TitleInfoScreen(
          summary: summary,
          languageCode: 'en',
          mediaCatalogService: _FakeMetadataCatalogService(metadata: metadata),
          onBack: () {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('DETAILS'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Featured Cast'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('title_info_cast_grid')),
        findsOneWidget);
    expect(find.text('La Historia Imposible del Metadata Extendido'),
        findsOneWidget);
  });

  testWidgets('TitleInfoScreen wraps cast cards at 1366x768 without clipping',
      (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final summary = MediaSummary(
      tmdbId: 55123,
      mediaType: MediaType.tv,
      title: 'Cast Layout Validation',
      overview: 'A synthetic summary for responsive cast-grid verification.',
      rating: 8.0,
      releaseDate: DateTime.utc(2024, 7, 15),
      seasonCount: 4,
    );
    final metadata = TitleMetadata(
      summary: summary,
      certification: 'TV-14',
      genres: const <String>['Drama'],
      creators: const <String>['Jordan Pierce'],
      writers: const <String>['Jamie Holt'],
      cast: const <TitleCredit>[
        TitleCredit(name: 'Actor 1', role: 'Role 1'),
        TitleCredit(name: 'Actor 2', role: 'Role 2'),
        TitleCredit(name: 'Actor 3', role: 'Role 3'),
        TitleCredit(name: 'Actor 4', role: 'Role 4'),
        TitleCredit(name: 'Actor 5', role: 'Role 5'),
        TitleCredit(name: 'Actor 6', role: 'Role 6'),
        TitleCredit(name: 'Actor 7', role: 'Role 7'),
        TitleCredit(name: 'Actor 8', role: 'Role 8'),
        TitleCredit(name: 'Actor 9', role: 'Role 9'),
        TitleCredit(name: 'Actor 10', role: 'Role 10'),
      ],
      crew: const <TitleCredit>[
        TitleCredit(name: 'Crew 1', role: 'Director'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TitleInfoScreen(
          summary: summary,
          languageCode: 'en',
          mediaCatalogService: _FakeMetadataCatalogService(metadata: metadata),
          onBack: () {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    final castGridFinder =
        find.byKey(const ValueKey<String>('title_info_cast_grid'));
    expect(castGridFinder, findsOneWidget);

    final castGridRect = tester.getRect(castGridFinder);
    for (var index = 0; index < 10; index += 1) {
      final cardRect = tester.getRect(
        find.byKey(ValueKey<String>('title_info_cast_card_$index')),
      );
      expect(cardRect.right, lessThanOrEqualTo(castGridRect.right + 0.1));
    }

    final firstRect = tester.getRect(
      find.byKey(const ValueKey<String>('title_info_cast_card_0')),
    );
    final sixthRect = tester.getRect(
      find.byKey(const ValueKey<String>('title_info_cast_card_5')),
    );
    expect(sixthRect.top, greaterThan(firstRect.top));
    expect(tester.takeException(), isNull);
  });
}

class _FakeMetadataCatalogService extends TmdbMediaCatalogService {
  _FakeMetadataCatalogService({
    required this.metadata,
  }) : super(
          tmdbClient: TmdbClient(apiKey: 'test'),
          cacheStore: const _NoopJsonCacheStore(),
        );

  final TitleMetadata metadata;

  @override
  Future<TitleMetadata> fetchTitleMetadata({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) async {
    return metadata;
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
