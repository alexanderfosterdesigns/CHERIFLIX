import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/maturity_tier.dart';
import 'package:cheriflix/core/models/media_summary.dart';
import 'package:cheriflix/core/models/media_type.dart';
import 'package:cheriflix/core/models/profile.dart';
import 'package:cheriflix/core/models/trakt_account.dart';
import 'package:cheriflix/core/models/trakt_recommended_title.dart';
import 'package:cheriflix/core/services/json_cache_store.dart';
import 'package:cheriflix/core/services/tmdb_client.dart';
import 'package:cheriflix/core/services/tmdb_media_catalog_service.dart';
import 'package:cheriflix/core/services/trakt_client.dart';
import 'package:cheriflix/core/services/trakt_home_recommendation_service.dart';

void main() {
  test('returns hydrated Trakt recommendations and reuses the 24-hour cache',
      () async {
    final traktClient = _FakeTraktClient(
      recommendations: <TraktRecommendedTitle>[
        const TraktRecommendedTitle(
          tmdbId: 700,
          mediaType: MediaType.movie,
          title: 'Trakt Pick',
        ),
      ],
    );
    final tmdbService = _FakeTmdbCatalogService(
      titleDetailsByKey: <String, MediaSummary>{
        'movie:700': _media(
          tmdbId: 700,
          mediaType: MediaType.movie,
          title: 'Hydrated Pick',
        ),
      },
    );
    final cacheStore = _MemoryCacheStore();
    final service = TraktHomeRecommendationService(
      traktClient: traktClient,
      cacheStore: cacheStore,
      tmdbMediaCatalogService: tmdbService,
    );

    final first = await service.fetchRecommendations(
      profile: _profileWithTrakt(),
      languageCode: 'en',
      fallbackSeeds: const <MediaSummary>[],
    );

    expect(first.single.title, 'Hydrated Pick');
    expect(traktClient.fetchRecommendationsCalls, 1);

    traktClient.recommendations = const <TraktRecommendedTitle>[];
    final second = await service.fetchRecommendations(
      profile: _profileWithTrakt(),
      languageCode: 'en',
      fallbackSeeds: const <MediaSummary>[],
    );

    expect(second.single.title, 'Hydrated Pick');
    expect(traktClient.fetchRecommendationsCalls, 1);
  });

  test('falls back to TMDB recommendations when Trakt has no results',
      () async {
    final traktClient = _FakeTraktClient(
      recommendations: const <TraktRecommendedTitle>[],
    );
    final seed = _media(
      tmdbId: 800,
      mediaType: MediaType.tv,
      title: 'Seed Show',
    );
    final fallback = _media(
      tmdbId: 801,
      mediaType: MediaType.movie,
      title: 'Fallback Movie',
    );
    final tmdbService = _FakeTmdbCatalogService(
      recommendationsByKey: <String, List<MediaSummary>>{
        seed.saveKey: <MediaSummary>[fallback],
      },
    );
    final service = TraktHomeRecommendationService(
      traktClient: traktClient,
      cacheStore: _MemoryCacheStore(),
      tmdbMediaCatalogService: tmdbService,
    );

    final recommendations = await service.fetchRecommendations(
      profile: _profileWithTrakt(),
      languageCode: 'en',
      fallbackSeeds: <MediaSummary>[seed],
    );

    expect(recommendations.single.title, 'Fallback Movie');
  });
}

Profile _profileWithTrakt() {
  return Profile(
    id: 'profile-1',
    name: 'Cherif',
    avatarLabel: 'C',
    languageCode: 'en',
    maturityTier: MaturityTier.mature,
    createdAt: DateTime.utc(2026, 3, 28),
    traktAccount: TraktAccount(
      username: 'cherif',
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      tokenType: 'bearer',
      scope: 'public',
      tokenCreatedAt: DateTime.utc(2026, 3, 28, 10),
      expiresInSeconds: 86400,
    ),
  );
}

MediaSummary _media({
  required int tmdbId,
  required MediaType mediaType,
  required String title,
}) {
  return MediaSummary(
    tmdbId: tmdbId,
    mediaType: mediaType,
    title: title,
    releaseDate: DateTime.utc(2026, 1, 1),
  );
}

class _FakeTraktClient extends TraktClient {
  _FakeTraktClient({
    required this.recommendations,
  }) : super(
          clientId: 'client-id',
          clientSecret: 'client-secret',
          redirectUri: 'urn:ietf:wg:oauth:2.0:oob',
        );

  List<TraktRecommendedTitle> recommendations;
  int fetchRecommendationsCalls = 0;

  @override
  Future<List<TraktRecommendedTitle>> fetchPersonalizedRecommendations({
    required String accessToken,
    int limit = 12,
  }) async {
    fetchRecommendationsCalls += 1;
    return recommendations;
  }
}

class _FakeTmdbCatalogService extends TmdbMediaCatalogService {
  _FakeTmdbCatalogService({
    this.titleDetailsByKey = const <String, MediaSummary>{},
    this.recommendationsByKey = const <String, List<MediaSummary>>{},
  }) : super(
          tmdbClient: TmdbClient(apiKey: 'test'),
          cacheStore: const _NoopCacheStore(),
        );

  final Map<String, MediaSummary> titleDetailsByKey;
  final Map<String, List<MediaSummary>> recommendationsByKey;

  @override
  Future<MediaSummary> fetchTitleDetails({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) async {
    final key = '${mediaType.name}:$tmdbId';
    final summary = titleDetailsByKey[key];
    if (summary == null) {
      throw StateError('Missing TMDB detail for $key');
    }
    return summary;
  }

  @override
  Future<List<MediaSummary>> fetchRecommendations({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) async {
    return recommendationsByKey['${mediaType.name}:$tmdbId'] ??
        const <MediaSummary>[];
  }
}

class _MemoryCacheStore implements JsonCacheStore {
  final Map<String, String> _payloadByKey = <String, String>{};
  final Map<String, DateTime> _fetchedAtByKey = <String, DateTime>{};

  @override
  Future<CachedJsonEntry?> read({
    required String key,
  }) async {
    final fetchedAt = _fetchedAtByKey[key];
    final payload = _payloadByKey[key];
    if (fetchedAt == null || payload == null) {
      return null;
    }
    return CachedJsonEntry(payload: payload, fetchedAt: fetchedAt);
  }

  @override
  Future<String?> readFresh({
    required String key,
    required Duration maxAge,
  }) async {
    final entry = await read(key: key);
    if (entry == null || !entry.isFresh(maxAge)) {
      return null;
    }
    return entry.payload;
  }

  @override
  Future<void> write({
    required String key,
    required String payload,
  }) async {
    _payloadByKey[key] = payload;
    _fetchedAtByKey[key] = DateTime.now().toUtc();
  }
}

class _NoopCacheStore implements JsonCacheStore {
  const _NoopCacheStore();

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
