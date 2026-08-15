import 'dart:convert';

import '../models/media_summary.dart';
import '../models/profile.dart';
import '../models/trakt_recommended_title.dart';
import 'json_cache_store.dart';
import 'tmdb_media_catalog_service.dart';
import 'trakt_client.dart';

class TraktHomeRecommendationService {
  const TraktHomeRecommendationService({
    required this.traktClient,
    required this.cacheStore,
    required this.tmdbMediaCatalogService,
  });

  static const Duration _cacheTtl = Duration(hours: 24);
  static const int _maxItems = 12;

  final TraktClient traktClient;
  final JsonCacheStore cacheStore;
  final TmdbMediaCatalogService? tmdbMediaCatalogService;

  Future<List<MediaSummary>> fetchRecommendations({
    required Profile profile,
    required String languageCode,
    required List<MediaSummary> fallbackSeeds,
  }) async {
    final account = profile.traktAccount;
    if (account == null) {
      return const <MediaSummary>[];
    }

    final cacheKey = 'trakt_home_recommendations:${profile.id}:$languageCode';
    final cached = await cacheStore.read(
      key: cacheKey,
    );
    if (cached != null && cached.isFresh(_cacheTtl)) {
      return _decodeCachedRecommendations(cached.payload);
    }

    var shouldCache = true;
    List<MediaSummary> resolved;
    try {
      final recommendations =
          await traktClient.fetchPersonalizedRecommendations(
        accessToken: account.accessToken,
        limit: _maxItems,
      );
      resolved = await _hydrateRecommendations(
        recommendations,
        languageCode: languageCode,
      );
      if (resolved.isEmpty) {
        resolved = await _fetchTmdbFallback(
          languageCode: languageCode,
          fallbackSeeds: fallbackSeeds,
        );
      }
    } on TraktApiException {
      shouldCache = false;
      if (cached != null) {
        return _decodeCachedRecommendations(cached.payload);
      }
      resolved = await _fetchTmdbFallback(
        languageCode: languageCode,
        fallbackSeeds: fallbackSeeds,
      );
    }

    if (shouldCache && resolved.isNotEmpty) {
      await cacheStore.write(
        key: cacheKey,
        payload: jsonEncode(
          resolved.map((item) => item.toJson()).toList(growable: false),
        ),
      );
    }
    return resolved;
  }

  List<MediaSummary> _decodeCachedRecommendations(String payload) {
    final decoded = jsonDecode(payload) as List<dynamic>;
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(MediaSummary.fromJson)
        .toList(growable: false);
  }

  Future<List<MediaSummary>> _hydrateRecommendations(
    List<TraktRecommendedTitle> recommendations, {
    required String languageCode,
  }) async {
    if (recommendations.isEmpty) {
      return const <MediaSummary>[];
    }

    final tmdbService = tmdbMediaCatalogService;
    if (tmdbService == null) {
      return _dedupeAndLimit(
        recommendations.map((item) => item.toMediaSummary()),
      );
    }

    final hydrated = await Future.wait<MediaSummary>(
      recommendations.map((item) async {
        try {
          return await tmdbService.fetchTitleDetails(
            tmdbId: item.tmdbId,
            mediaType: item.mediaType,
            languageCode: languageCode,
          );
        } catch (_) {
          return item.toMediaSummary();
        }
      }),
    );
    return _dedupeAndLimit(hydrated);
  }

  Future<List<MediaSummary>> _fetchTmdbFallback({
    required String languageCode,
    required List<MediaSummary> fallbackSeeds,
  }) async {
    final tmdbService = tmdbMediaCatalogService;
    if (tmdbService == null) {
      return const <MediaSummary>[];
    }

    final merged = <MediaSummary>[];
    final seenKeys = <String>{};
    final seeds = _dedupeAndLimit(fallbackSeeds);
    for (final seed in seeds.take(3)) {
      try {
        final recommendations = await tmdbService.fetchRecommendations(
          tmdbId: seed.tmdbId,
          mediaType: seed.mediaType,
          languageCode: languageCode,
        );
        for (final item in recommendations) {
          if (item.saveKey == seed.saveKey || !seenKeys.add(item.saveKey)) {
            continue;
          }
          merged.add(item);
          if (merged.length >= _maxItems) {
            return merged;
          }
        }
      } catch (_) {
        // Ignore individual fallback seed failures and keep going.
      }
    }

    if (merged.isNotEmpty) {
      return merged.take(_maxItems).toList(growable: false);
    }

    final fallbackGroups = await Future.wait<List<MediaSummary>>(
      <Future<List<MediaSummary>>>[
        tmdbService.tmdbClient.fetchPopularMovies(languageCode: languageCode),
        tmdbService.tmdbClient.fetchPopularTv(languageCode: languageCode),
      ],
    );
    final popular = <MediaSummary>[];
    final movies = fallbackGroups[0];
    final shows = fallbackGroups[1];
    final maxCount =
        movies.length > shows.length ? movies.length : shows.length;
    for (var index = 0; index < maxCount; index += 1) {
      if (index < movies.length) {
        popular.add(movies[index]);
      }
      if (index < shows.length) {
        popular.add(shows[index]);
      }
      if (popular.length >= _maxItems) {
        break;
      }
    }
    return _dedupeAndLimit(popular);
  }

  List<MediaSummary> _dedupeAndLimit(Iterable<MediaSummary> items) {
    final deduped = <MediaSummary>[];
    final seenKeys = <String>{};
    for (final item in items) {
      if (!seenKeys.add(item.saveKey)) {
        continue;
      }
      deduped.add(item);
      if (deduped.length >= _maxItems) {
        break;
      }
    }
    return deduped;
  }
}
