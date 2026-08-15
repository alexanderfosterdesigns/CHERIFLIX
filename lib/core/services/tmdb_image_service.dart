import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

enum TmdbImagePreset {
  smallPoster(sourceWidth: 342, outputWidth: 300, quality: 72),
  largePoster(sourceWidth: 500, outputWidth: 500, quality: 78),
  cardBackdrop(sourceWidth: 780, outputWidth: 700, quality: 76),
  episodeStill(sourceWidth: 780, outputWidth: 700, quality: 76),
  heroBackdrop(sourceWidth: 1280, outputWidth: 1280, quality: 82),
  castProfile(sourceWidth: 185, outputWidth: 220, quality: 76),
  studioLogo(sourceWidth: 300, outputWidth: 300, quality: 84),
  titleLogo(sourceWidth: 500, outputWidth: 700, quality: 90);

  const TmdbImagePreset({
    required this.sourceWidth,
    required this.outputWidth,
    required this.quality,
  });

  final int sourceWidth;
  final int outputWidth;
  final int quality;

  String get tmdbSize => 'w$sourceWidth';
}

class TmdbImageRequest {
  const TmdbImageRequest({
    required this.primaryUrl,
    required this.fallbackUrl,
    required this.cacheKey,
  });

  final String primaryUrl;
  final String fallbackUrl;
  final String cacheKey;
}

/// The single static-artwork pipeline used by Cheriflix.
///
/// TMDB path -> smallest sufficient TMDB source -> wsrv WebP -> bounded local
/// cache. If wsrv is unavailable, callers immediately retry the direct TMDB
/// source. Video, subtitle and provider URLs never enter this service.
class TmdbImageService {
  TmdbImageService._();

  static final CacheManager cacheManager = _CheriflixArtworkCacheManager(
    Config(
      'cheriflix-static-artwork-v2',
      stalePeriod: const Duration(days: 21),
      maxNrOfCacheObjects: 1400,
      repo: JsonCacheInfoRepository(databaseName: 'cheriflixArtworkCacheV2'),
      fileService: HttpFileService(),
    ),
  );

  static final Map<String, Future<void>> _inFlightPreloads =
      <String, Future<void>>{};

  static String? directUrlForPath(
    String? path,
    TmdbImagePreset preset,
  ) {
    final normalized = path?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      return normalized;
    }
    final slashPath = normalized.startsWith('/') ? normalized : '/$normalized';
    return 'https://image.tmdb.org/t/p/${preset.tmdbSize}$slashPath';
  }

  static TmdbImageRequest? request(
    String? sourceUrl, {
    required TmdbImagePreset preset,
  }) {
    final raw = sourceUrl?.trim();
    if (raw == null || raw.isEmpty) return null;
    final parsed = Uri.tryParse(raw);
    if (parsed == null || !parsed.hasScheme) return null;

    final direct = _rightSizeTmdbUrl(parsed, preset) ?? raw;
    if (!_isTmdbImage(Uri.tryParse(direct))) {
      return TmdbImageRequest(
        primaryUrl: direct,
        fallbackUrl: direct,
        cacheKey: direct,
      );
    }
    final optimized = Uri.https('wsrv.nl', '/', <String, String>{
      'url': direct,
      'w': '${preset.outputWidth}',
      'output': 'webp',
      'q': '${preset.quality}',
    }).toString();
    return TmdbImageRequest(
      primaryUrl: optimized,
      fallbackUrl: direct,
      cacheKey: '${preset.name}:${parsed.path}',
    );
  }

  static Future<void> preload(
    BuildContext context,
    String? sourceUrl, {
    required TmdbImagePreset preset,
    int? decodeWidth,
    int? decodeHeight,
  }) {
    final imageRequest = request(sourceUrl, preset: preset);
    if (imageRequest == null) return Future<void>.value();
    final key =
        '${imageRequest.cacheKey}:${decodeWidth ?? 0}x${decodeHeight ?? 0}';
    return _inFlightPreloads.putIfAbsent(key, () async {
      try {
        await precacheImage(
          CachedNetworkImageProvider(
            imageRequest.primaryUrl,
            cacheManager: cacheManager,
            maxWidth: decodeWidth,
            maxHeight: decodeHeight,
          ),
          context,
        );
      } catch (_) {
        if (imageRequest.fallbackUrl != imageRequest.primaryUrl &&
            context.mounted) {
          await precacheImage(
            CachedNetworkImageProvider(
              imageRequest.fallbackUrl,
              cacheManager: cacheManager,
              maxWidth: decodeWidth,
              maxHeight: decodeHeight,
            ),
            context,
            onError: (_, __) {},
          );
        }
      } finally {
        _inFlightPreloads.remove(key);
      }
    });
  }

  static String? _rightSizeTmdbUrl(Uri? uri, TmdbImagePreset preset) {
    if (!_isTmdbImage(uri)) return null;
    final segments = uri!.pathSegments;
    final pIndex = segments.indexOf('p');
    if (pIndex < 0 || pIndex + 2 >= segments.length) return uri.toString();
    final resized = <String>[...segments]..[pIndex + 1] = preset.tmdbSize;
    return uri.replace(pathSegments: resized).toString();
  }

  static bool _isTmdbImage(Uri? uri) {
    return uri != null &&
        uri.host.toLowerCase() == 'image.tmdb.org' &&
        uri.path.contains('/t/p/');
  }
}

class _CheriflixArtworkCacheManager extends CacheManager
    with ImageCacheManager {
  _CheriflixArtworkCacheManager(super.config);
}
