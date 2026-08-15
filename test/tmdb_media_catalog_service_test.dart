import 'package:cheriflix/core/models/media_type.dart';
import 'package:cheriflix/core/services/json_cache_store.dart';
import 'package:cheriflix/core/services/tmdb_client.dart';
import 'package:cheriflix/core/services/tmdb_media_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TmdbMediaCatalogService trailer preview packaging', () {
    test('returns the original preview uri when only one candidate exists',
        () async {
      final previewUri = Uri.parse(
        'https://www.youtube-nocookie.com/embed/solo?autoplay=1&mute=1',
      );
      final service = _PreviewListCatalogService(<Uri>[previewUri]);

      final result = await service.fetchTrailerPreviewUri(
        tmdbId: 101,
        mediaType: MediaType.movie,
        languageCode: 'en',
      );

      expect(result, previewUri);
    });

    test('packages multiple candidates into a silent-fallback preview uri',
        () async {
      final first = Uri.parse(
        'https://www.youtube-nocookie.com/embed/first?autoplay=1&mute=1',
      );
      final second = Uri.parse(
        'https://player.vimeo.com/video/second?autoplay=1&muted=1',
      );
      final service = _PreviewListCatalogService(<Uri>[first, second]);

      final result = await service.fetchTrailerPreviewUri(
        tmdbId: 202,
        mediaType: MediaType.movie,
        languageCode: 'en',
      );

      expect(result, isNotNull);
      expect(result!.scheme, 'cheriflix-preview');
      expect(result.host, 'trailers');
      expect(result.queryParameters['src'], first.toString());
      expect(result.queryParameters['src1'], second.toString());
    });

    test('returns null when no preview candidates exist', () async {
      final service = _PreviewListCatalogService(const <Uri>[]);

      final result = await service.fetchTrailerPreviewUri(
        tmdbId: 303,
        mediaType: MediaType.movie,
        languageCode: 'en',
      );

      expect(result, isNull);
    });

    test('coalesces identical requests while the cache fill is in flight',
        () async {
      final previewUri = Uri.parse(
        'https://www.youtube-nocookie.com/embed/shared?autoplay=1&mute=1',
      );
      final service = _PreviewListCatalogService(
        <Uri>[previewUri],
        delay: const Duration(milliseconds: 20),
      );

      final results = await Future.wait(<Future<Uri?>>[
        service.fetchTrailerPreviewUri(
          tmdbId: 404,
          mediaType: MediaType.movie,
          languageCode: 'en',
        ),
        service.fetchTrailerPreviewUri(
          tmdbId: 404,
          mediaType: MediaType.movie,
          languageCode: 'en',
        ),
      ]);

      expect(results, <Uri?>[previewUri, previewUri]);
      expect(service.fetchCount, 1);
    });
  });
}

class _PreviewListCatalogService extends TmdbMediaCatalogService {
  _PreviewListCatalogService(
    this.previewUris, {
    this.delay = Duration.zero,
  }) : super(
          tmdbClient: TmdbClient(apiKey: 'test'),
          cacheStore: const _NoopJsonCacheStore(),
        );

  final List<Uri> previewUris;
  final Duration delay;
  int fetchCount = 0;

  @override
  Future<List<Uri>> fetchTrailerPreviewUris({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
    bool muted = true,
  }) async {
    fetchCount += 1;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return previewUris;
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
