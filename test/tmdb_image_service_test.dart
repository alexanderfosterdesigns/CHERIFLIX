import 'package:cheriflix/core/models/tmdb_title_logo.dart';
import 'package:cheriflix/core/services/tmdb_image_service.dart';
import 'package:cheriflix/core/services/tmdb_media_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TmdbImageService', () {
    test('uses a right-sized TMDB source and deterministic wsrv WebP URL', () {
      final request = TmdbImageService.request(
        'https://image.tmdb.org/t/p/original/poster.jpg',
        preset: TmdbImagePreset.smallPoster,
      );

      expect(request, isNotNull);
      expect(request!.fallbackUrl, contains('/t/p/w342/poster.jpg'));
      final optimized = Uri.parse(request.primaryUrl);
      expect(optimized.host, 'wsrv.nl');
      expect(optimized.queryParameters['url'], request.fallbackUrl);
      expect(optimized.queryParameters['w'], '300');
      expect(optimized.queryParameters['output'], 'webp');
      expect(optimized.queryParameters['q'], '72');
    });

    test('never proxies non-TMDB URLs through wsrv', () {
      final request = TmdbImageService.request(
        'https://example.com/artwork.jpg',
        preset: TmdbImagePreset.heroBackdrop,
      );
      expect(request!.primaryUrl, 'https://example.com/artwork.jpg');
      expect(request.fallbackUrl, request.primaryUrl);
    });

    test('gives each visual role a stable distinct cache key', () {
      final poster = TmdbImageService.request(
        'https://image.tmdb.org/t/p/w342/shared.jpg',
        preset: TmdbImagePreset.smallPoster,
      );
      final backdrop = TmdbImageService.request(
        'https://image.tmdb.org/t/p/w1280/shared.jpg',
        preset: TmdbImagePreset.heroBackdrop,
      );
      expect(poster!.cacheKey, isNot(backdrop!.cacheKey));
    });
  });

  group('TMDB title-logo selection', () {
    test('prefers the current language, then English and neutral', () {
      final logos = <TmdbTitleLogo>[
        const TmdbTitleLogo(
          filePath: '/neutral.png',
          width: 1000,
          height: 300,
        ),
        const TmdbTitleLogo(
          filePath: '/english.png',
          width: 700,
          height: 220,
          languageCode: 'en',
        ),
        const TmdbTitleLogo(
          filePath: '/french.png',
          width: 600,
          height: 200,
          languageCode: 'fr',
        ),
      ];

      expect(
        TmdbMediaCatalogService.selectPreferredTitleLogo(logos, 'fr-FR')
            ?.filePath,
        '/french.png',
      );
      expect(
        TmdbMediaCatalogService.selectPreferredTitleLogo(logos, 'de')?.filePath,
        '/english.png',
      );
      expect(
        TmdbMediaCatalogService.selectPreferredTitleLogo(
          <TmdbTitleLogo>[logos.first],
          'de',
        )?.filePath,
        '/neutral.png',
      );
    });
  });
}
