import 'dart:convert';

import '../models/episode_summary.dart';
import '../models/home_catalog_data.dart';
import '../models/just_released_catalog.dart';
import '../models/media_summary.dart';
import '../models/media_type.dart';
import '../models/maturity_tier.dart';
import '../models/title_metadata.dart';
import '../models/tmdb_title_logo.dart';
import '../models/upcoming_catalog.dart';
import '../utils/release_date_utils.dart';
import '../utils/maturity_policy.dart';
import 'json_cache_store.dart';
import 'media_catalog_service.dart';
import 'tmdb_client.dart';

class TmdbMediaCatalogService implements MediaCatalogService {
  TmdbMediaCatalogService({
    required this.tmdbClient,
    required this.cacheStore,
  });

  final TmdbClient tmdbClient;
  final JsonCacheStore cacheStore;
  final Map<String, TmdbTitleLogo?> _logoMemoryCache =
      <String, TmdbTitleLogo?>{};
  final Map<String, Future<TmdbTitleLogo?>> _logoRequests =
      <String, Future<TmdbTitleLogo?>>{};

  static const Duration _homeTtl = Duration(hours: 1);
  static const Duration _justReleasedTtl = Duration(hours: 1);
  static const Duration _detailTtl = Duration(hours: 6);
  static const Duration _upcomingTtl = Duration(hours: 6);
  static const int _justReleasedWindowDays = 105;
  static const int _tabRailLimit = 20;

  static const List<int> _thrillerGenreIds = <int>[53];
  static const List<int> _romanceGenreIds = <int>[10749];
  static const List<int> _dramaGenreIds = <int>[18];

  @override
  Future<HomeCatalogData> fetchHomeCatalog({
    required String languageCode,
  }) async {
    final cacheKey = 'home_catalog:$languageCode';
    return _readThroughCache<HomeCatalogData>(
      key: cacheKey,
      maxAge: _homeTtl,
      decode: (payload) => HomeCatalogData.fromJson(
        jsonDecode(payload) as Map<String, dynamic>,
      ),
      fetch: () async {
        final results =
            await Future.wait<List<MediaSummary>>(<Future<List<MediaSummary>>>[
          tmdbClient.fetchTrending(languageCode: languageCode),
          tmdbClient.fetchNowPlayingMovies(languageCode: languageCode),
          tmdbClient.fetchPopularMovies(languageCode: languageCode),
          tmdbClient.fetchPopularTv(languageCode: languageCode),
          tmdbClient.fetchTopRatedMovies(languageCode: languageCode),
        ]);

        final trending = results[0];
        final newOnStreaming = results[1];
        final popularMovies = results[2];
        final popularSeries = results[3];
        final newAndPopular = results[4];

        final featured = trending.firstWhere(
          (item) => item.backdropUrl != null,
          orElse: () => popularMovies.firstWhere(
            (item) => item.backdropUrl != null,
            orElse: () => (trending.isNotEmpty
                ? trending.first
                : (popularMovies.isNotEmpty
                    ? popularMovies.first
                    : popularSeries.first)),
          ),
        );

        return HomeCatalogData(
          featured: featured,
          newOnStreaming: newOnStreaming,
          trending: trending,
          popularMovies: popularMovies,
          popularSeries: popularSeries,
          newAndPopular: newAndPopular,
        );
      },
      encode: (payload) => jsonEncode(payload.toJson()),
    );
  }

  Future<UpcomingCatalog> fetchUpcomingCatalog({
    required String languageCode,
  }) async {
    final now = DateTime.now();
    final today = calendarDate(now);
    final tomorrow = today.add(const Duration(days: 1));
    final horizon = today.add(const Duration(days: 365));
    // v3 deliberately bypasses older empty snapshots produced when a
    // supplemental TV request caused the whole combined fetch to fail.
    final cacheKey =
        'upcoming_catalog:v3:$languageCode:${_cacheDateKey(today)}';
    return _readThroughCache<UpcomingCatalog>(
      key: cacheKey,
      maxAge: _upcomingTtl,
      decode: (payload) => UpcomingCatalog.fromJson(
        jsonDecode(payload) as Map<String, dynamic>,
      ),
      fetch: () async {
        final essentialDiscovery = await Future.wait<List<MediaSummary>>(
          <Future<List<MediaSummary>>>[
            tmdbClient.discoverUpcomingTitles(
              mediaType: MediaType.movie,
              languageCode: languageCode,
              releasedAfter: tomorrow,
              releasedBefore: horizon,
            ),
            tmdbClient.discoverUpcomingTitles(
              mediaType: MediaType.tv,
              languageCode: languageCode,
              releasedAfter: tomorrow,
              releasedBefore: horizon,
            ),
          ],
        );
        // Popular/airing data improves season discovery but is not required
        // for the actual Coming Soon rows. Isolate those failures so a 429 or
        // transient error cannot erase otherwise valid future movies/series.
        final supplementalDiscovery = await Future.wait<List<MediaSummary>>(
          <Future<List<MediaSummary>>>[
            tmdbClient
                .fetchPopularTv(languageCode: languageCode)
                .catchError((_) => const <MediaSummary>[]),
            tmdbClient
                .fetchAiringTodayTv(languageCode: languageCode)
                .catchError((_) => const <MediaSummary>[]),
          ],
        );
        final movies = _curateUpcoming(essentialDiscovery[0], today: today);
        final series = _curateUpcoming(essentialDiscovery[1], today: today);
        final candidateMap = <String, MediaSummary>{
          for (final item in <MediaSummary>[
            ...supplementalDiscovery[0],
            ...supplementalDiscovery[1],
            ...series,
          ])
            item.saveKey: item,
        };
        // Season discovery is supplemental and must never hold the whole
        // browse screen behind one slow TMDB detail request. A curated sample
        // is ample for this discovery rail; every request has a short ceiling.
        final seasonResults = await Future.wait<UpcomingSeasonEntry?>(
          candidateMap.values.take(16).map(
                (summary) => tmdbClient
                    .fetchConfirmedSeasonEntry(
                      summary: summary,
                      languageCode: languageCode,
                      now: today,
                    )
                    .timeout(
                      const Duration(seconds: 6),
                      onTimeout: () => null,
                    )
                    .catchError((_) => null),
              ),
        );
        final seasons = seasonResults.whereType<UpcomingSeasonEntry>().toList()
          ..sort((a, b) => a.premiereDate.compareTo(b.premiereDate));
        return UpcomingCatalog(
          movies: movies,
          series: series,
          seasons: seasons.take(_tabRailLimit).toList(growable: false),
        );
      },
      encode: (payload) => jsonEncode(payload.toJson()),
    );
  }

  List<MediaSummary> _curateUpcoming(
    List<MediaSummary> items, {
    required DateTime today,
  }) {
    final candidates = items
        .where((item) =>
            item.releaseDate != null && item.releaseDate!.isAfter(today))
        .where((item) => item.posterPath != null || item.backdropPath != null)
        .toList(growable: false)
      ..sort((a, b) {
        final date = a.releaseDate!.compareTo(b.releaseDate!);
        if (date != 0) return date;
        return (b.rating ?? 0).compareTo(a.rating ?? 0);
      });
    return _dedupeAndLimit(candidates);
  }

  @override
  Future<JustReleasedCatalog> fetchJustReleasedCatalog({
    required String languageCode,
    required DateTime releasedAfter,
  }) async {
    final now = DateTime.now().toUtc();
    final effectiveReleasedAfter = releasedAfter.toUtc();
    final cacheKey =
        'just_released_catalog:$languageCode:${_cacheDateKey(effectiveReleasedAfter)}:${_cacheDateKey(now)}';
    return _readThroughCache<JustReleasedCatalog>(
      key: cacheKey,
      maxAge: _justReleasedTtl,
      decode: (payload) => JustReleasedCatalog.fromJson(
        jsonDecode(payload) as Map<String, dynamic>,
      ),
      fetch: () async {
        final recentWindowStart = now.subtract(
          const Duration(days: _justReleasedWindowDays),
        );
        final windowStart = effectiveReleasedAfter.isAfter(recentWindowStart)
            ? effectiveReleasedAfter
            : recentWindowStart;

        final results =
            await Future.wait<List<MediaSummary>>(<Future<List<MediaSummary>>>[
          tmdbClient.discoverRecentTitles(
            mediaType: MediaType.movie,
            languageCode: languageCode,
            releasedAfter: windowStart,
            releasedBefore: now,
          ),
          tmdbClient.discoverRecentTitles(
            mediaType: MediaType.tv,
            languageCode: languageCode,
            releasedAfter: windowStart,
            releasedBefore: now,
          ),
          tmdbClient.discoverRecentTopRatedTitles(
            mediaType: MediaType.movie,
            languageCode: languageCode,
            releasedAfter: windowStart,
            releasedBefore: now,
          ),
          tmdbClient.discoverRecentTopRatedTitles(
            mediaType: MediaType.tv,
            languageCode: languageCode,
            releasedAfter: windowStart,
            releasedBefore: now,
          ),
          tmdbClient.discoverRecentMoviesByGenre(
            genreIds: _thrillerGenreIds,
            languageCode: languageCode,
            releasedAfter: windowStart,
            releasedBefore: now,
          ),
          tmdbClient.discoverRecentMoviesByGenre(
            genreIds: _romanceGenreIds,
            languageCode: languageCode,
            releasedAfter: windowStart,
            releasedBefore: now,
          ),
          tmdbClient.discoverRecentMoviesByGenre(
            genreIds: _dramaGenreIds,
            languageCode: languageCode,
            releasedAfter: windowStart,
            releasedBefore: now,
          ),
          tmdbClient.fetchNowPlayingMovies(languageCode: languageCode),
          tmdbClient.fetchAiringTodayTv(languageCode: languageCode),
        ]);

        return JustReleasedCatalog(
          recentReleases: _mergeAndSortByReleaseDate(
            <List<MediaSummary>>[results[0], results[1]],
            releasedAfter: windowStart,
          ),
          topRatedRecent: _mergeAndSortTopRated(
            <List<MediaSummary>>[results[2], results[3]],
            releasedAfter: windowStart,
          ),
          newThrillers: _filterRecent(results[4], releasedAfter: windowStart),
          newRomance: _filterRecent(results[5], releasedAfter: windowStart),
          newDrama: _filterRecent(results[6], releasedAfter: windowStart),
          justHitStreaming: _mergeAndSortByReleaseDate(
            <List<MediaSummary>>[results[7], results[8]],
            releasedAfter: windowStart,
          ),
        );
      },
      encode: (payload) => jsonEncode(payload.toJson()),
    );
  }

  @override
  Future<MediaSummary> fetchTitleDetails({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) async {
    final segment = mediaType == MediaType.movie ? 'movie' : 'tv';
    final cacheKey = 'title_detail:$languageCode:$segment:$tmdbId';
    return _readThroughCache<MediaSummary>(
      key: cacheKey,
      maxAge: _detailTtl,
      decode: (payload) => MediaSummary.fromJson(
        jsonDecode(payload) as Map<String, dynamic>,
      ),
      fetch: () => tmdbClient.fetchDetails(
        tmdbId: tmdbId,
        mediaType: mediaType,
        languageCode: languageCode,
      ),
      encode: (summary) => jsonEncode(summary.toJson()),
    );
  }

  Future<TitleMetadata> fetchTitleMetadata({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) async {
    final segment = mediaType == MediaType.movie ? 'movie' : 'tv';
    final cacheKey = 'title_metadata:v1:$languageCode:$segment:$tmdbId';
    return _readThroughCache<TitleMetadata>(
      key: cacheKey,
      maxAge: _detailTtl,
      decode: (payload) => TitleMetadata.fromJson(
        jsonDecode(payload) as Map<String, dynamic>,
      ),
      fetch: () => tmdbClient.fetchTitleMetadata(
        tmdbId: tmdbId,
        mediaType: mediaType,
        languageCode: languageCode,
      ),
      encode: (metadata) => jsonEncode(metadata.toJson()),
    );
  }

  Future<List<MediaSummary>> filterForMaturity(
    Iterable<MediaSummary> items, {
    required MaturityTier tier,
    required String languageCode,
  }) async {
    final unique = <String, MediaSummary>{
      for (final item in items) item.saveKey: item,
    }.values.toList(growable: false);
    if (tier == MaturityTier.mature) return unique;
    final allowed = <MediaSummary>[];
    // Bounded batches avoid flooding TMDB while cached metadata makes later
    // screens and launches effectively immediate.
    for (var start = 0; start < unique.length; start += 8) {
      final batch = unique.skip(start).take(8).toList(growable: false);
      final decisions = await Future.wait<bool>(batch.map((item) async {
        try {
          final metadata = await fetchTitleMetadata(
            tmdbId: item.tmdbId,
            mediaType: item.mediaType,
            languageCode: languageCode,
          );
          return MaturityPolicy.allows(metadata.certification, tier);
        } catch (_) {
          return false;
        }
      }));
      for (var index = 0; index < batch.length; index += 1) {
        if (decisions[index]) allowed.add(batch[index]);
      }
    }
    return allowed;
  }

  Future<HomeCatalogData> filterHomeCatalogForMaturity(
    HomeCatalogData catalog, {
    required MaturityTier tier,
    required String languageCode,
  }) async {
    if (tier == MaturityTier.mature) return catalog;
    final all = <MediaSummary>[
      catalog.featured,
      ...catalog.newOnStreaming,
      ...catalog.trending,
      ...catalog.popularMovies,
      ...catalog.popularSeries,
      ...catalog.newAndPopular,
    ];
    final allowed = await filterForMaturity(
      all,
      tier: tier,
      languageCode: languageCode,
    );
    final keys = allowed.map((item) => item.saveKey).toSet();
    List<MediaSummary> keep(List<MediaSummary> items) => items
        .where((item) => keys.contains(item.saveKey))
        .toList(growable: false);
    final fallback = allowed.isEmpty ? null : allowed.first;
    if (fallback == null) {
      throw StateError('No titles match this profile maturity level.');
    }
    return HomeCatalogData(
      featured:
          keys.contains(catalog.featured.saveKey) ? catalog.featured : fallback,
      newOnStreaming: keep(catalog.newOnStreaming),
      trending: keep(catalog.trending),
      popularMovies: keep(catalog.popularMovies),
      popularSeries: keep(catalog.popularSeries),
      newAndPopular: keep(catalog.newAndPopular),
    );
  }

  Future<UpcomingCatalog> filterUpcomingCatalogForMaturity(
    UpcomingCatalog catalog, {
    required MaturityTier tier,
    required String languageCode,
  }) async {
    if (tier == MaturityTier.mature) return catalog;
    final allowed = await filterForMaturity(
      <MediaSummary>[
        ...catalog.movies,
        ...catalog.series,
        ...catalog.seasons.map((entry) => entry.summary),
      ],
      tier: tier,
      languageCode: languageCode,
    );
    final keys = allowed.map((item) => item.saveKey).toSet();
    return UpcomingCatalog(
      movies:
          catalog.movies.where((item) => keys.contains(item.saveKey)).toList(),
      series:
          catalog.series.where((item) => keys.contains(item.saveKey)).toList(),
      seasons: catalog.seasons
          .where((item) => keys.contains(item.summary.saveKey))
          .toList(),
    );
  }

  Future<JustReleasedCatalog> filterJustReleasedCatalogForMaturity(
    JustReleasedCatalog catalog, {
    required MaturityTier tier,
    required String languageCode,
  }) async {
    if (tier == MaturityTier.mature) return catalog;
    final allowed = await filterForMaturity(
      <MediaSummary>[
        ...catalog.recentReleases,
        ...catalog.topRatedRecent,
        ...catalog.newThrillers,
        ...catalog.newRomance,
        ...catalog.newDrama,
        ...catalog.justHitStreaming,
      ],
      tier: tier,
      languageCode: languageCode,
    );
    final keys = allowed.map((item) => item.saveKey).toSet();
    List<MediaSummary> keep(List<MediaSummary> items) => items
        .where((item) => keys.contains(item.saveKey))
        .toList(growable: false);
    return JustReleasedCatalog(
      recentReleases: keep(catalog.recentReleases),
      topRatedRecent: keep(catalog.topRatedRecent),
      newThrillers: keep(catalog.newThrillers),
      newRomance: keep(catalog.newRomance),
      newDrama: keep(catalog.newDrama),
      justHitStreaming: keep(catalog.justHitStreaming),
    );
  }

  Future<TmdbTitleLogo?> fetchPreferredTitleLogo({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) async {
    final cacheKey = _titleLogoCacheKey(
      tmdbId: tmdbId,
      mediaType: mediaType,
      languageCode: languageCode,
    );
    if (_logoMemoryCache.containsKey(cacheKey)) {
      return Future<TmdbTitleLogo?>.value(_logoMemoryCache[cacheKey]);
    }
    return _logoRequests.putIfAbsent(cacheKey, () async {
      final normalizedLanguage = languageCode.toLowerCase().split('-').first;
      try {
        final logo = await _readThroughCache<TmdbTitleLogo?>(
          key: cacheKey,
          maxAge: const Duration(days: 14),
          decode: (payload) {
            if (payload.trim().isEmpty) return null;
            return TmdbTitleLogo.fromJson(
              jsonDecode(payload) as Map<String, dynamic>,
            );
          },
          fetch: () async {
            final logos = await tmdbClient.fetchTitleLogos(
              tmdbId: tmdbId,
              mediaType: mediaType,
              languageCode: normalizedLanguage,
            );
            if (logos.isEmpty) return null;
            return selectPreferredTitleLogo(logos, normalizedLanguage);
          },
          encode: (logo) => logo == null ? '' : jsonEncode(logo.toJson()),
        );
        _logoMemoryCache[cacheKey] = logo;
        return logo;
      } finally {
        _logoRequests.remove(cacheKey);
      }
    });
  }

  /// Returns a logo already resolved during this app session without any I/O.
  TmdbTitleLogo? peekPreferredTitleLogo({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) {
    return _logoMemoryCache[_titleLogoCacheKey(
      tmdbId: tmdbId,
      mediaType: mediaType,
      languageCode: languageCode,
    )];
  }

  String _titleLogoCacheKey({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) {
    final segment = mediaType == MediaType.movie ? 'movie' : 'tv';
    final normalizedLanguage = languageCode.toLowerCase().split('-').first;
    return 'title_logo:v2:$normalizedLanguage:$segment:$tmdbId';
  }

  static TmdbTitleLogo? selectPreferredTitleLogo(
    List<TmdbTitleLogo> logos,
    String preferredLanguage,
  ) {
    if (logos.isEmpty) return null;
    final normalizedLanguage = preferredLanguage.toLowerCase().split('-').first;
    final ranked = List<TmdbTitleLogo>.of(logos)
      ..sort((left, right) => _logoScore(
            right,
            normalizedLanguage,
          ).compareTo(_logoScore(left, normalizedLanguage)));
    return ranked.first;
  }

  static double _logoScore(TmdbTitleLogo logo, String preferredLanguage) {
    final language = logo.languageCode?.toLowerCase();
    final languageScore = language == preferredLanguage
        ? 4000.0
        : language == 'en'
            ? 3000.0
            : language == null || language.isEmpty
                ? 2000.0
                : 1000.0;
    final aspectRatio = logo.width / logo.height;
    final shapeScore = aspectRatio >= 1.2 && aspectRatio <= 8 ? 200.0 : 0.0;
    final resolutionScore = logo.width.clamp(0, 2000) / 20;
    return languageScore +
        shapeScore +
        resolutionScore +
        logo.voteAverage * 4 +
        logo.voteCount.clamp(0, 100) / 10;
  }

  @override
  Future<List<MediaSummary>> searchTitles({
    required String query,
    required String languageCode,
  }) {
    return tmdbClient.search(
      query: query,
      languageCode: languageCode,
    );
  }

  Future<List<MediaSummary>> fetchRecommendations({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) async {
    final segment = mediaType == MediaType.movie ? 'movie' : 'tv';
    final cacheKey = 'title_recommendations:$languageCode:$segment:$tmdbId';
    return _readThroughCache<List<MediaSummary>>(
      key: cacheKey,
      maxAge: _detailTtl,
      decode: (payload) {
        final decoded = jsonDecode(payload) as List<dynamic>;
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(MediaSummary.fromJson)
            .where((item) => item.tmdbId != tmdbId)
            .toList(growable: false);
      },
      fetch: () async {
        final detail = await fetchTitleDetails(
          tmdbId: tmdbId,
          mediaType: mediaType,
          languageCode: languageCode,
        );
        final seenKeys = <String>{detail.saveKey};
        final merged = <MediaSummary>[];

        void addAll(Iterable<MediaSummary> items) {
          for (final item in items) {
            if (seenKeys.add(item.saveKey)) {
              merged.add(item);
            }
            if (merged.length >= 12) {
              return;
            }
          }
        }

        if (mediaType == MediaType.movie && detail.collectionId != null) {
          addAll(
            (await tmdbClient.fetchCollectionMovies(
              collectionId: detail.collectionId!,
              languageCode: languageCode,
            ))
                .where((item) => item.tmdbId != tmdbId),
          );
        }

        if (merged.length < 12) {
          addAll(
            await tmdbClient.fetchRecommendations(
              tmdbId: tmdbId,
              mediaType: mediaType,
              languageCode: languageCode,
            ),
          );
        }

        if (merged.length < 12) {
          addAll(
            await tmdbClient.fetchSimilar(
              tmdbId: tmdbId,
              mediaType: mediaType,
              languageCode: languageCode,
            ),
          );
        }

        if (merged.length < 12 && detail.genreIds.isNotEmpty) {
          addAll(
            await tmdbClient.discoverByGenres(
              mediaType: mediaType,
              genreIds: detail.genreIds.take(3).toList(growable: false),
              languageCode: languageCode,
            ),
          );
        }

        if (merged.isEmpty) {
          addAll(
            mediaType == MediaType.movie
                ? await tmdbClient.fetchPopularMovies(
                    languageCode: languageCode)
                : await tmdbClient.fetchPopularTv(languageCode: languageCode),
          );
        }

        return merged.take(12).toList(growable: false);
      },
      encode: (items) => jsonEncode(
        items.map((item) => item.toJson()).toList(growable: false),
      ),
    );
  }

  Future<List<EpisodeSummary>> fetchSeasonEpisodes({
    required int tmdbId,
    required int seasonNumber,
    required String languageCode,
    int? fallbackRuntimeMinutes,
  }) async {
    final cacheKey = 'season_episodes:$languageCode:$tmdbId:$seasonNumber';
    return _readThroughCache<List<EpisodeSummary>>(
      key: cacheKey,
      maxAge: _detailTtl,
      decode: (payload) {
        final decoded = jsonDecode(payload) as List<dynamic>;
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(
              (json) => EpisodeSummary.fromTmdbJson(
                json,
                seasonNumber: seasonNumber,
                fallbackRuntimeMinutes: fallbackRuntimeMinutes,
              ),
            )
            .toList(growable: false);
      },
      fetch: () => tmdbClient.fetchSeasonEpisodes(
        tmdbId: tmdbId,
        seasonNumber: seasonNumber,
        languageCode: languageCode,
        fallbackRuntimeMinutes: fallbackRuntimeMinutes,
      ),
      encode: (episodes) => jsonEncode(
        episodes
            .map(
              (episode) => <String, Object?>{
                'episode_number': episode.episodeNumber,
                'name': episode.title,
                'overview': episode.overview,
                'still_path': episode.stillPath,
                'runtime': episode.runtimeMinutes,
                'air_date': episode.airDate?.toIso8601String(),
              },
            )
            .toList(growable: false),
      ),
    );
  }

  Future<Uri?> fetchTrailerPreviewUri({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
    bool muted = true,
  }) async {
    final segment = mediaType == MediaType.movie ? 'movie' : 'tv';
    final cacheKey =
        'title_preview:$languageCode:$segment:$tmdbId:${muted ? 'muted' : 'audio'}';
    return _readThroughCache<Uri?>(
      key: cacheKey,
      maxAge: _detailTtl,
      decode: (payload) {
        final raw = payload.trim();
        if (raw.isEmpty) {
          return null;
        }
        return Uri.tryParse(raw);
      },
      fetch: () async {
        final previewUris = await fetchTrailerPreviewUris(
          tmdbId: tmdbId,
          mediaType: mediaType,
          languageCode: languageCode,
          muted: muted,
        );
        return switch (previewUris.length) {
          0 => null,
          1 => previewUris.first,
          _ => _buildPreviewPlaylistUri(previewUris),
        };
      },
      encode: (uri) => uri?.toString() ?? '',
    );
  }

  Future<List<Uri>> fetchTrailerPreviewUris({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
    bool muted = true,
  }) {
    return tmdbClient.fetchTrailerPreviewUris(
      tmdbId: tmdbId,
      mediaType: mediaType,
      languageCode: languageCode,
      muted: muted,
    );
  }

  String _cacheDateKey(DateTime value) {
    final utcValue = value.toUtc();
    final month = utcValue.month.toString().padLeft(2, '0');
    final day = utcValue.day.toString().padLeft(2, '0');
    return '${utcValue.year}-$month-$day';
  }

  List<MediaSummary> _filterRecent(
    List<MediaSummary> items, {
    required DateTime releasedAfter,
  }) {
    final filtered = items
        .where(
          (item) =>
              item.releaseDate != null &&
              !item.releaseDate!.toUtc().isBefore(releasedAfter),
        )
        .toList(growable: false);
    return _dedupeAndLimit(
      filtered..sort(_compareByReleaseDateDesc),
    );
  }

  Uri _buildPreviewPlaylistUri(List<Uri> previewUris) {
    final queryParameters = <String, String>{
      'src': previewUris.first.toString(),
    };
    for (var index = 1; index < previewUris.length; index += 1) {
      queryParameters['src$index'] = previewUris[index].toString();
    }
    return Uri(
      scheme: 'cheriflix-preview',
      host: 'trailers',
      queryParameters: queryParameters,
    );
  }

  List<MediaSummary> _mergeAndSortByReleaseDate(
    List<List<MediaSummary>> groups, {
    required DateTime releasedAfter,
  }) {
    final merged = <MediaSummary>[
      for (final group in groups)
        for (final item in group)
          if (item.releaseDate != null &&
              !item.releaseDate!.toUtc().isBefore(releasedAfter))
            item,
    ]..sort(_compareByReleaseDateDesc);
    return _dedupeAndLimit(merged);
  }

  List<MediaSummary> _mergeAndSortTopRated(
    List<List<MediaSummary>> groups, {
    required DateTime releasedAfter,
  }) {
    final merged = <MediaSummary>[
      for (final group in groups)
        for (final item in group)
          if (item.releaseDate != null &&
              !item.releaseDate!.toUtc().isBefore(releasedAfter))
            item,
    ]..sort(_compareTopRatedRecent);
    return _dedupeAndLimit(merged);
  }

  List<MediaSummary> _dedupeAndLimit(List<MediaSummary> items) {
    final seenKeys = <String>{};
    final deduped = <MediaSummary>[];
    for (final item in items) {
      if (!seenKeys.add(item.saveKey)) {
        continue;
      }
      deduped.add(item);
      if (deduped.length >= _tabRailLimit) {
        break;
      }
    }
    return deduped;
  }

  Future<T> _readThroughCache<T>({
    required String key,
    required Duration maxAge,
    required T Function(String payload) decode,
    required Future<T> Function() fetch,
    required String Function(T value) encode,
  }) async {
    final cached = await cacheStore.read(key: key);
    if (cached != null && cached.isFresh(maxAge)) {
      return decode(cached.payload);
    }

    try {
      final value = await fetch();
      await cacheStore.write(key: key, payload: encode(value));
      return value;
    } catch (_) {
      if (cached != null) {
        return decode(cached.payload);
      }
      rethrow;
    }
  }
}

int _compareByReleaseDateDesc(MediaSummary left, MediaSummary right) {
  final leftDate = left.releaseDate?.millisecondsSinceEpoch ?? 0;
  final rightDate = right.releaseDate?.millisecondsSinceEpoch ?? 0;
  if (leftDate != rightDate) {
    return rightDate.compareTo(leftDate);
  }
  return left.title.compareTo(right.title);
}

int _compareTopRatedRecent(MediaSummary left, MediaSummary right) {
  final leftRating = left.rating ?? 0;
  final rightRating = right.rating ?? 0;
  final ratingComparison = rightRating.compareTo(leftRating);
  if (ratingComparison != 0) {
    return ratingComparison;
  }
  return _compareByReleaseDateDesc(left, right);
}
