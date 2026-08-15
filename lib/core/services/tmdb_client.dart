import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/episode_summary.dart';
import '../models/media_summary.dart';
import '../models/media_type.dart';
import '../models/title_metadata.dart';
import '../models/tmdb_title_logo.dart';
import '../models/upcoming_catalog.dart';

class TmdbClient {
  TmdbClient({
    required this.apiKey,
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  final String apiKey;
  final HttpClient _client;

  static final Uri _baseUri = Uri.parse('https://api.themoviedb.org/3');
  static const Duration _requestTimeout = Duration(seconds: 10);
  static const int _maxAttempts = 3;

  Future<List<MediaSummary>> fetchTrending({
    required String languageCode,
  }) {
    return _fetchList(
      '/trending/all/week',
      queryParameters: <String, String>{
        'language': _normalizeLanguage(languageCode),
      },
    );
  }

  Future<List<MediaSummary>> fetchPopularMovies({
    required String languageCode,
  }) {
    return _fetchList(
      '/movie/popular',
      queryParameters: <String, String>{
        'language': _normalizeLanguage(languageCode),
      },
    );
  }

  Future<List<MediaSummary>> fetchPopularTv({
    required String languageCode,
  }) {
    return _fetchList(
      '/tv/popular',
      queryParameters: <String, String>{
        'language': _normalizeLanguage(languageCode),
      },
    );
  }

  Future<List<MediaSummary>> fetchAiringTodayTv({
    required String languageCode,
  }) {
    return _fetchList(
      '/tv/airing_today',
      queryParameters: <String, String>{
        'language': _normalizeLanguage(languageCode),
      },
    );
  }

  Future<List<MediaSummary>> fetchNowPlayingMovies({
    required String languageCode,
  }) {
    return _fetchList(
      '/movie/now_playing',
      queryParameters: <String, String>{
        'language': _normalizeLanguage(languageCode),
      },
    );
  }

  Future<List<MediaSummary>> fetchTopRatedMovies({
    required String languageCode,
  }) {
    return _fetchList(
      '/movie/top_rated',
      queryParameters: <String, String>{
        'language': _normalizeLanguage(languageCode),
      },
    );
  }

  Future<List<MediaSummary>> search({
    required String query,
    required String languageCode,
  }) async {
    return _fetchList(
      '/search/multi',
      queryParameters: <String, String>{
        'query': query,
        'include_adult': 'false',
        'language': _normalizeLanguage(languageCode),
      },
    );
  }

  Future<List<MediaSummary>> fetchRecommendations({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) {
    final segment = mediaType == MediaType.movie ? 'movie' : 'tv';
    return _fetchList(
      '/$segment/$tmdbId/recommendations',
      queryParameters: <String, String>{
        'language': _normalizeLanguage(languageCode),
      },
    );
  }

  Future<List<MediaSummary>> fetchSimilar({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) {
    final segment = mediaType == MediaType.movie ? 'movie' : 'tv';
    return _fetchList(
      '/$segment/$tmdbId/similar',
      queryParameters: <String, String>{
        'language': _normalizeLanguage(languageCode),
      },
    );
  }

  Future<MediaSummary> fetchDetails({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) async {
    final segment = mediaType == MediaType.movie ? 'movie' : 'tv';
    final json = await _getJson(
      '/$segment/$tmdbId',
      queryParameters: <String, String>{
        'language': _normalizeLanguage(languageCode),
      },
    );
    return MediaSummary.fromTmdbJson(
      <String, dynamic>{
        ...json,
        'media_type': segment,
      },
    );
  }

  Future<TitleMetadata> fetchTitleMetadata({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) async {
    final segment = mediaType == MediaType.movie ? 'movie' : 'tv';
    final appendToResponse = mediaType == MediaType.movie
        ? 'credits,release_dates'
        : 'credits,content_ratings';
    final json = await _getJson(
      '/$segment/$tmdbId',
      queryParameters: <String, String>{
        'language': _normalizeLanguage(languageCode),
        'append_to_response': appendToResponse,
      },
    );
    return _titleMetadataFromJson(json, mediaType);
  }

  Future<List<TmdbTitleLogo>> fetchTitleLogos({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) async {
    final segment = mediaType == MediaType.movie ? 'movie' : 'tv';
    final primaryLanguage = _normalizeLanguage(languageCode).split('-').first;
    final json = await _getJson(
      '/$segment/$tmdbId/images',
      queryParameters: <String, String>{
        'include_image_language': '$primaryLanguage,en,null',
      },
    );
    return (json['logos'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(TmdbTitleLogo.fromJson)
        .where((logo) =>
            logo.filePath.isNotEmpty && logo.width > 0 && logo.height > 0)
        .toList(growable: false);
  }

  Future<List<MediaSummary>> fetchCollectionMovies({
    required int collectionId,
    required String languageCode,
  }) async {
    final json = await _getJson(
      '/collection/$collectionId',
      queryParameters: <String, String>{
        'language': _normalizeLanguage(languageCode),
      },
    );
    final parts = json['parts'] as List<dynamic>? ?? const <dynamic>[];
    return parts
        .whereType<Map<String, dynamic>>()
        .map(
          (item) => MediaSummary.fromTmdbJson(
            <String, dynamic>{...item, 'media_type': 'movie'},
          ),
        )
        .toList(growable: false);
  }

  Future<List<MediaSummary>> discoverByGenres({
    required MediaType mediaType,
    required List<int> genreIds,
    required String languageCode,
  }) {
    if (genreIds.isEmpty) {
      return Future<List<MediaSummary>>.value(const <MediaSummary>[]);
    }

    final segment = mediaType == MediaType.movie ? 'movie' : 'tv';
    return _fetchList(
      '/discover/$segment',
      queryParameters: <String, String>{
        'language': _normalizeLanguage(languageCode),
        'sort_by': 'popularity.desc',
        'with_genres': genreIds.join('|'),
        'include_adult': 'false',
      },
    );
  }

  Future<List<MediaSummary>> discoverRecentTitles({
    required MediaType mediaType,
    required String languageCode,
    required DateTime releasedAfter,
    DateTime? releasedBefore,
  }) {
    return _discoverRecent(
      mediaType: mediaType,
      languageCode: languageCode,
      releasedAfter: releasedAfter,
      releasedBefore: releasedBefore,
      sortBy: 'popularity.desc',
    );
  }

  Future<List<MediaSummary>> discoverUpcomingTitles({
    required MediaType mediaType,
    required String languageCode,
    required DateTime releasedAfter,
    required DateTime releasedBefore,
  }) {
    final segment = mediaType == MediaType.movie ? 'movie' : 'tv';
    final dateField = mediaType == MediaType.movie
        ? 'primary_release_date'
        : 'first_air_date';
    return _fetchList(
      '/discover/$segment',
      queryParameters: <String, String>{
        'language': _normalizeLanguage(languageCode),
        'sort_by': '$dateField.asc',
        '$dateField.gte': _formatDate(releasedAfter),
        '$dateField.lte': _formatDate(releasedBefore),
        'include_adult': 'false',
        'include_null_first_air_dates': 'false',
        'vote_count.gte': '0',
      },
    );
  }

  Future<UpcomingSeasonEntry?> fetchConfirmedSeasonEntry({
    required MediaSummary summary,
    required String languageCode,
    required DateTime now,
  }) async {
    if (summary.mediaType != MediaType.tv) return null;
    final json = await _getJson(
      '/tv/${summary.tmdbId}',
      queryParameters: <String, String>{
        'language': _normalizeLanguage(languageCode),
      },
    );
    final today = DateTime(now.year, now.month, now.day);
    final lowerBound = today.subtract(const Duration(days: 45));
    final upperBound = today.add(const Duration(days: 240));
    final seasons = (json['seasons'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map((season) {
          final number = (season['season_number'] as num?)?.toInt() ?? 0;
          final date = DateTime.tryParse(season['air_date'] as String? ?? '');
          return (number: number, date: date);
        })
        .where((season) =>
            season.number > 1 &&
            season.date != null &&
            !season.date!.isBefore(lowerBound) &&
            !season.date!.isAfter(upperBound))
        .toList(growable: false)
      ..sort((left, right) => right.date!.compareTo(left.date!));
    if (seasons.isEmpty) return null;

    final season = seasons.first;
    final nextEpisode = json['next_episode_to_air'] as Map<String, dynamic>?;
    final lastEpisode = json['last_episode_to_air'] as Map<String, dynamic>?;
    final nextSeason = (nextEpisode?['season_number'] as num?)?.toInt();
    final lastSeason = (lastEpisode?['season_number'] as num?)?.toInt();
    final nextDate =
        DateTime.tryParse(nextEpisode?['air_date'] as String? ?? '');
    final hasFutureEpisode = nextSeason == season.number &&
        nextDate != null &&
        nextDate.isAfter(today);
    final currentlyAiring = hasFutureEpisode &&
        (lastSeason == season.number || !season.date!.isAfter(today));
    final state = season.date!.isAfter(today)
        ? SeasonReleaseState.upcoming
        : currentlyAiring
            ? SeasonReleaseState.currentlyAiring
            : SeasonReleaseState.recentlyStarted;
    return UpcomingSeasonEntry(
      summary: MediaSummary.fromTmdbJson(<String, dynamic>{
        ...json,
        'media_type': 'tv',
      }),
      seasonNumber: season.number,
      premiereDate: season.date!,
      state: state,
    );
  }

  Future<List<MediaSummary>> discoverRecentTopRatedTitles({
    required MediaType mediaType,
    required String languageCode,
    required DateTime releasedAfter,
    DateTime? releasedBefore,
  }) {
    return _discoverRecent(
      mediaType: mediaType,
      languageCode: languageCode,
      releasedAfter: releasedAfter,
      releasedBefore: releasedBefore,
      sortBy: 'vote_average.desc',
      voteCountAtLeast: 120,
    );
  }

  Future<List<MediaSummary>> discoverRecentMoviesByGenre({
    required List<int> genreIds,
    required String languageCode,
    required DateTime releasedAfter,
    DateTime? releasedBefore,
  }) {
    return _discoverRecent(
      mediaType: MediaType.movie,
      languageCode: languageCode,
      releasedAfter: releasedAfter,
      releasedBefore: releasedBefore,
      sortBy: 'popularity.desc',
      genreIds: genreIds,
    );
  }

  Future<Uri?> fetchTrailerPreviewUri({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
    bool muted = true,
  }) async {
    final previewUris = await fetchTrailerPreviewUris(
      tmdbId: tmdbId,
      mediaType: mediaType,
      languageCode: languageCode,
      muted: muted,
    );
    if (previewUris.isEmpty) {
      return null;
    }
    return previewUris.first;
  }

  Future<List<Uri>> fetchTrailerPreviewUris({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
    bool muted = true,
  }) async {
    final segment = mediaType == MediaType.movie ? 'movie' : 'tv';
    final json = await _getJson(
      '/$segment/$tmdbId/videos',
      queryParameters: <String, String>{
        'language': _normalizeLanguage(languageCode),
      },
    );
    final results = json['results'] as List<dynamic>? ?? const <dynamic>[];
    final trailers = results
        .whereType<Map<String, dynamic>>()
        .map(_PreviewVideoCandidate.fromJson)
        .where(
            (candidate) => candidate.key.isNotEmpty && candidate.supportsEmbed)
        .toList(growable: false);
    if (trailers.isEmpty) {
      return const <Uri>[];
    }

    trailers.sort(_comparePreviewCandidates);
    return trailers
        .map((trailer) => trailer.embedUri(muted: muted))
        .whereType<Uri>()
        .toList(growable: false);
  }

  Future<List<EpisodeSummary>> fetchSeasonEpisodes({
    required int tmdbId,
    required int seasonNumber,
    required String languageCode,
    int? fallbackRuntimeMinutes,
  }) async {
    final json = await _getJson(
      '/tv/$tmdbId/season/$seasonNumber',
      queryParameters: <String, String>{
        'language': _normalizeLanguage(languageCode),
      },
    );
    final episodes = json['episodes'] as List<dynamic>? ?? const <dynamic>[];
    return episodes
        .whereType<Map<String, dynamic>>()
        .map(
          (episode) => EpisodeSummary.fromTmdbJson(
            episode,
            seasonNumber: seasonNumber,
            fallbackRuntimeMinutes: fallbackRuntimeMinutes,
          ),
        )
        .toList(growable: false);
  }

  Future<List<MediaSummary>> _fetchList(
    String path, {
    required Map<String, String> queryParameters,
  }) async {
    final json = await _getJson(path, queryParameters: queryParameters);
    final results = json['results'] as List<dynamic>? ?? const <dynamic>[];
    return results
        .whereType<Map<String, dynamic>>()
        .where((item) =>
            item['media_type'] == null ||
            item['media_type'] == 'movie' ||
            item['media_type'] == 'tv')
        .map(MediaSummary.fromTmdbJson)
        .toList();
  }

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, String> queryParameters = const <String, String>{},
  }) async {
    final uri = _baseUri.replace(
      path: '${_baseUri.path}$path',
      queryParameters: <String, String>{
        'api_key': apiKey,
        ...queryParameters,
      },
    );

    for (var attempt = 1; attempt <= _maxAttempts; attempt += 1) {
      try {
        final request = await _client.getUrl(uri).timeout(_requestTimeout);
        final response = await request.close().timeout(_requestTimeout);
        final payload = await response
            .transform(utf8.decoder)
            .join()
            .timeout(_requestTimeout);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return jsonDecode(payload) as Map<String, dynamic>;
        }
        if (!_isRetriableStatus(response.statusCode) ||
            attempt >= _maxAttempts) {
          throw HttpException(
            'TMDb request failed: ${response.statusCode}',
            uri: uri,
          );
        }
      } on TimeoutException {
        if (attempt >= _maxAttempts) {
          rethrow;
        }
      } on SocketException {
        if (attempt >= _maxAttempts) {
          rethrow;
        }
      }
      await _retryDelay(attempt);
    }
    throw HttpException('TMDb request failed.', uri: uri);
  }

  bool _isRetriableStatus(int statusCode) {
    return statusCode == 429 || statusCode >= 500;
  }

  Future<void> _retryDelay(int attempt) {
    return Future<void>.delayed(Duration(milliseconds: 240 * attempt));
  }

  String _normalizeLanguage(String languageCode) {
    final trimmed = languageCode.trim();
    if (trimmed.isEmpty) {
      return 'en-US';
    }
    if (trimmed.contains('-')) {
      return trimmed;
    }
    return '${trimmed.toLowerCase()}-${trimmed.toUpperCase()}';
  }

  Future<List<MediaSummary>> _discoverRecent({
    required MediaType mediaType,
    required String languageCode,
    required DateTime releasedAfter,
    required String sortBy,
    DateTime? releasedBefore,
    List<int> genreIds = const <int>[],
    int? voteCountAtLeast,
  }) {
    final segment = mediaType == MediaType.movie ? 'movie' : 'tv';
    final dateParamPrefix = mediaType == MediaType.movie
        ? 'primary_release_date'
        : 'first_air_date';
    return _fetchList(
      '/discover/$segment',
      queryParameters: <String, String>{
        'language': _normalizeLanguage(languageCode),
        'sort_by': sortBy,
        'include_adult': 'false',
        '$dateParamPrefix.gte': _formatDate(releasedAfter),
        if (releasedBefore != null)
          '$dateParamPrefix.lte': _formatDate(releasedBefore),
        if (genreIds.isNotEmpty) 'with_genres': genreIds.join('|'),
        if (voteCountAtLeast != null) 'vote_count.gte': '$voteCountAtLeast',
      },
    );
  }

  String _formatDate(DateTime value) {
    // TMDB date filters are calendar dates, not instants. Converting a local
    // midnight to UTC can move Australia and other positive-offset regions
    // back one day and incorrectly include/exclude release-day content.
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}

TitleMetadata _titleMetadataFromJson(
  Map<String, dynamic> json,
  MediaType mediaType,
) {
  final segment = mediaType == MediaType.movie ? 'movie' : 'tv';
  final summary = MediaSummary.fromTmdbJson(
    <String, dynamic>{...json, 'media_type': segment},
  );
  final credits =
      json['credits'] as Map<String, dynamic>? ?? const <String, dynamic>{};
  final cast = (credits['cast'] as List<dynamic>? ?? const <dynamic>[])
      .whereType<Map<String, dynamic>>()
      .map(
        (item) => TitleCredit(
          name: item['name'] as String? ?? 'Unknown',
          role: item['character'] as String? ?? '',
          profilePath: item['profile_path'] as String?,
          department: 'Cast',
        ),
      )
      .take(16)
      .toList(growable: false);

  final crewRows = (credits['crew'] as List<dynamic>? ?? const <dynamic>[])
      .whereType<Map<String, dynamic>>()
      .toList(growable: false);
  final crew = crewRows
      .where(
        (item) => _importantCrewJobs.contains(
          '${item['job'] ?? item['known_for_department'] ?? ''}'.trim(),
        ),
      )
      .map(
        (item) => TitleCredit(
          name: item['name'] as String? ?? 'Unknown',
          role: item['job'] as String? ?? '',
          profilePath: item['profile_path'] as String?,
          department: item['department'] as String?,
        ),
      )
      .fold<List<TitleCredit>>(<TitleCredit>[], (list, credit) {
    final duplicate = list.any(
      (existing) =>
          existing.name == credit.name && existing.role == credit.role,
    );
    if (!duplicate && list.length < 12) {
      list.add(credit);
    }
    return list;
  });

  final creators = mediaType == MediaType.tv
      ? (json['created_by'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map((item) => item['name'] as String?)
          .whereType<String>()
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false)
      : crewRows
          .where((item) => (item['job'] as String?) == 'Director')
          .map((item) => item['name'] as String?)
          .whereType<String>()
          .toSet()
          .toList(growable: false);

  final writers = crewRows
      .where(
        (item) => const <String>{
          'Writer',
          'Screenplay',
          'Story',
          'Teleplay',
        }.contains(item['job'] as String?),
      )
      .map((item) => item['name'] as String?)
      .whereType<String>()
      .toSet()
      .toList(growable: false);

  return TitleMetadata(
    summary: summary,
    certification: _extractCertification(json, mediaType),
    tagline: json['tagline'] as String?,
    status: json['status'] as String?,
    originalTitle: (json['original_title'] ?? json['original_name']) as String?,
    originalLanguage: json['original_language'] as String?,
    homepage: json['homepage'] as String?,
    genres: summary.genreNames,
    studios:
        (json['production_companies'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map((item) => item['name'] as String?)
            .whereType<String>()
            .where((item) => item.trim().isNotEmpty)
            .toList(growable: false),
    networks: (json['networks'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map((item) => item['name'] as String?)
        .whereType<String>()
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false),
    spokenLanguages:
        (json['spoken_languages'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map((item) =>
                item['english_name'] as String? ?? item['name'] as String?)
            .whereType<String>()
            .where((item) => item.trim().isNotEmpty)
            .toList(growable: false),
    originCountries:
        (json['origin_country'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>()
            .where((item) => item.trim().isNotEmpty)
            .toList(growable: false),
    creators: creators,
    writers: writers,
    cast: cast,
    crew: crew,
  );
}

String? _extractCertification(Map<String, dynamic> json, MediaType mediaType) {
  if (mediaType == MediaType.movie) {
    final releaseDates = (json['release_dates']
            as Map<String, dynamic>?)?['results'] as List<dynamic>? ??
        const <dynamic>[];
    for (final countryCode in _preferredCertificationRegions) {
      for (final entry in releaseDates.whereType<Map<String, dynamic>>()) {
        if (entry['iso_3166_1'] != countryCode) {
          continue;
        }
        final releases =
            entry['release_dates'] as List<dynamic>? ?? const <dynamic>[];
        for (final release in releases.whereType<Map<String, dynamic>>()) {
          final certification = '${release['certification'] ?? ''}'.trim();
          if (certification.isNotEmpty) {
            return certification;
          }
        }
      }
    }
    return null;
  }

  final contentRatings = (json['content_ratings']
          as Map<String, dynamic>?)?['results'] as List<dynamic>? ??
      const <dynamic>[];
  for (final countryCode in _preferredCertificationRegions) {
    for (final entry in contentRatings.whereType<Map<String, dynamic>>()) {
      if (entry['iso_3166_1'] != countryCode) {
        continue;
      }
      final rating = '${entry['rating'] ?? ''}'.trim();
      if (rating.isNotEmpty) {
        return rating;
      }
    }
  }
  return null;
}

const List<String> _preferredCertificationRegions = <String>[
  'AU',
  'US',
  'GB',
  'CA',
];

const Set<String> _importantCrewJobs = <String>{
  'Director',
  'Writer',
  'Screenplay',
  'Story',
  'Producer',
  'Executive Producer',
  'Original Music Composer',
  'Characters',
  'Teleplay',
  'Creator',
};

int _comparePreviewCandidates(
  _PreviewVideoCandidate left,
  _PreviewVideoCandidate right,
) {
  final leftPriority = left.priority;
  final rightPriority = right.priority;
  if (leftPriority != rightPriority) {
    return leftPriority.compareTo(rightPriority);
  }
  return right.size.compareTo(left.size);
}

class _PreviewVideoCandidate {
  const _PreviewVideoCandidate({
    required this.site,
    required this.key,
    required this.type,
    required this.official,
    required this.size,
  });

  factory _PreviewVideoCandidate.fromJson(Map<String, dynamic> json) {
    return _PreviewVideoCandidate(
      site: '${json['site'] ?? ''}'.trim(),
      key: '${json['key'] ?? ''}'.trim(),
      type: '${json['type'] ?? ''}'.trim(),
      official: json['official'] == true,
      size: (json['size'] as num?)?.toInt() ?? 0,
    );
  }

  final String site;
  final String key;
  final String type;
  final bool official;
  final int size;

  bool get supportsEmbed {
    final normalizedSite = site.toLowerCase();
    return normalizedSite == 'youtube' || normalizedSite == 'vimeo';
  }

  int get priority {
    final normalizedSite = site.toLowerCase();
    final normalizedType = type.toLowerCase();
    final sitePriority = switch (normalizedSite) {
      'youtube' => 0,
      'vimeo' => 1,
      _ => 2,
    };
    final typePriority = switch (normalizedType) {
      'trailer' => 0,
      'teaser' => 1,
      'clip' => 2,
      _ => 3,
    };
    final officialPriority = official ? 0 : 1;
    return sitePriority * 100 + typePriority * 10 + officialPriority;
  }

  Uri? embedUri({
    required bool muted,
  }) {
    final normalizedSite = site.toLowerCase();
    if (normalizedSite == 'youtube') {
      return Uri.parse(
        'https://www.youtube-nocookie.com/embed/$key'
        '?autoplay=1&mute=${muted ? 1 : 0}&controls=0&modestbranding=1'
        '&playsinline=1&rel=0&loop=1&playlist=$key&iv_load_policy=3'
        '&enablejsapi=1&fs=0&disablekb=1&cc_load_policy=0&autohide=1',
      );
    }
    if (normalizedSite == 'vimeo') {
      return Uri.parse(
        'https://player.vimeo.com/video/$key'
        '?autoplay=1&muted=${muted ? 1 : 0}'
        '&title=0&byline=0&portrait=0&loop=1&autopause=0',
      );
    }
    return null;
  }
}
