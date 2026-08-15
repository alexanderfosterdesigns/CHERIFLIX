import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/media_summary.dart';
import '../models/media_type.dart';
import '../models/playback_progress_entry.dart';
import '../models/trakt_account.dart';
import '../models/trakt_recommended_title.dart';

enum TraktScrobbleAction {
  start,
  pause,
  stop;

  String get pathSegment => switch (this) {
        TraktScrobbleAction.start => 'start',
        TraktScrobbleAction.pause => 'pause',
        TraktScrobbleAction.stop => 'stop',
      };
}

class TraktApiException implements Exception {
  const TraktApiException(
    this.message, {
    this.statusCode,
    this.uri,
  });

  final String message;
  final int? statusCode;
  final Uri? uri;

  @override
  String toString() {
    final statusLabel = statusCode == null ? '' : ' (HTTP $statusCode)';
    final uriLabel = uri == null ? '' : ' [$uri]';
    return 'TraktApiException$statusLabel: $message$uriLabel';
  }
}

class TraktClient {
  TraktClient({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  final String clientId;
  final String clientSecret;
  final String redirectUri;
  final HttpClient _client;

  static final Uri _apiBaseUri = Uri.parse('https://api.trakt.tv');
  static final Uri _oauthBaseUri = Uri.parse('https://trakt.tv');
  static const Duration _requestTimeout = Duration(seconds: 10);
  static const int _maxGetAttempts = 3;

  final Map<int, _TraktMovieLookup> _movieLookupByTmdbId =
      <int, _TraktMovieLookup>{};
  final Map<int, _TraktShowLookup> _showLookupByTmdbId =
      <int, _TraktShowLookup>{};
  final Map<String, _TraktEpisodeLookup> _episodeLookupByKey =
      <String, _TraktEpisodeLookup>{};

  bool get isConfigured =>
      clientId.trim().isNotEmpty &&
      clientSecret.trim().isNotEmpty &&
      redirectUri.trim().isNotEmpty;

  Uri buildAuthorizationUri() {
    return _oauthBaseUri.replace(
      path: '/oauth/authorize',
      queryParameters: <String, String>{
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
      },
    );
  }

  Future<TraktAccount> exchangeAuthorizationCode(String code) async {
    final payload = await _requestJson(
      'POST',
      '/oauth/token',
      body: <String, Object?>{
        'code': code.trim(),
        'client_id': clientId,
        'client_secret': clientSecret,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
      },
      includeApiHeaders: false,
      expectedStatusCodes: const <int>{200},
    );
    final tokenJson = _expectJsonMap(payload);
    final username = await fetchCurrentUsername(
      accessToken: tokenJson['access_token'] as String,
    );
    return _accountFromTokenJson(tokenJson, username: username);
  }

  Future<TraktAccount> refreshAccount(TraktAccount account) async {
    final payload = await _requestJson(
      'POST',
      '/oauth/token',
      body: <String, Object?>{
        'refresh_token': account.refreshToken,
        'client_id': clientId,
        'client_secret': clientSecret,
        'redirect_uri': redirectUri,
        'grant_type': 'refresh_token',
      },
      includeApiHeaders: false,
      expectedStatusCodes: const <int>{200},
    );
    final tokenJson = _expectJsonMap(payload);
    return _accountFromTokenJson(tokenJson, username: account.username);
  }

  Future<String> fetchCurrentUsername({
    required String accessToken,
  }) async {
    final payload = await _requestJson(
      'GET',
      '/users/settings',
      accessToken: accessToken,
      expectedStatusCodes: const <int>{200},
    );
    final json = _expectJsonMap(payload);
    final userJson =
        json['user'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final username =
        '${userJson['username'] ?? (userJson['ids'] as Map?)?['slug'] ?? ''}'
            .trim();
    if (username.isEmpty) {
      throw const TraktApiException(
        'Trakt did not return a username for the authorized account.',
      );
    }
    return username;
  }

  Future<List<TraktRecommendedTitle>> fetchPersonalizedRecommendations({
    required String accessToken,
    int limit = 12,
  }) async {
    final responses = await Future.wait<List<TraktRecommendedTitle>>(
      <Future<List<TraktRecommendedTitle>>>[
        _fetchRecommendationsForType(
          path: '/recommendations/movies',
          mediaType: MediaType.movie,
          accessToken: accessToken,
          limit: limit,
        ),
        _fetchRecommendationsForType(
          path: '/recommendations/shows',
          mediaType: MediaType.tv,
          accessToken: accessToken,
          limit: limit,
        ),
      ],
    );

    final merged = <TraktRecommendedTitle>[];
    final seenTmdbIds = <String>{};
    final movies = responses[0];
    final shows = responses[1];
    final maxCount =
        movies.length > shows.length ? movies.length : shows.length;
    for (var index = 0; index < maxCount; index += 1) {
      if (index < movies.length) {
        final item = movies[index];
        if (seenTmdbIds.add('${item.mediaType.name}:${item.tmdbId}')) {
          merged.add(item);
        }
      }
      if (index < shows.length) {
        final item = shows[index];
        if (seenTmdbIds.add('${item.mediaType.name}:${item.tmdbId}')) {
          merged.add(item);
        }
      }
      if (merged.length >= limit) {
        break;
      }
    }
    return merged.take(limit).toList(growable: false);
  }

  Future<void> scrobbleMovie({
    required String accessToken,
    required MediaSummary summary,
    required int progress,
    required TraktScrobbleAction action,
  }) async {
    final lookup = await _resolveMovieLookup(summary.tmdbId);
    final year = lookup.year ?? summary.releaseDate?.year;
    if (year == null) {
      throw TraktApiException(
        'Unable to resolve a release year for "${summary.title}".',
      );
    }

    await _requestJson(
      'POST',
      '/scrobble/movie/${action.pathSegment}',
      accessToken: accessToken,
      body: <String, Object?>{
        'progress': progress,
        'movie': <String, Object?>{
          'title': lookup.title.isEmpty ? summary.title : lookup.title,
          'year': year,
          'ids': <String, Object?>{
            if (lookup.traktId != null) 'trakt': lookup.traktId!,
            'tmdb': lookup.tmdbId,
          },
        },
      },
      expectedStatusCodes: const <int>{201},
    );
  }

  Future<void> scrobbleEpisode({
    required String accessToken,
    required int showTmdbId,
    required int seasonNumber,
    required int episodeNumber,
    required int progress,
    required TraktScrobbleAction action,
  }) async {
    final lookup = await _resolveEpisodeLookup(
      showTmdbId: showTmdbId,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
    final ids = <String, Object?>{
      if (lookup.traktId != null) 'trakt': lookup.traktId!,
      if (lookup.tvdbId != null) 'tvdb': lookup.tvdbId!,
    };
    if (ids.isEmpty) {
      throw const TraktApiException(
        'Unable to resolve Trakt or TVDB episode identifiers.',
      );
    }

    await _requestJson(
      'POST',
      '/scrobble/episode/${action.pathSegment}',
      accessToken: accessToken,
      body: <String, Object?>{
        'progress': progress,
        'episode': <String, Object?>{
          'ids': ids,
        },
      },
      expectedStatusCodes: const <int>{201},
    );
  }

  Future<void> addPlaybackToHistory({
    required String accessToken,
    required PlaybackProgressEntry entry,
  }) async {
    final watchedAt = entry.updatedAt.toUtc().toIso8601String();
    final body = switch (entry.summary.mediaType) {
      MediaType.movie => <String, Object?>{
          'movies': <Object?>[
            <String, Object?>{
              'ids': <String, Object?>{'tmdb': entry.summary.tmdbId},
              'watched_at': watchedAt,
            },
          ],
        },
      MediaType.tv
          when entry.seasonNumber != null && entry.episodeNumber != null =>
        <String, Object?>{
          'shows': <Object?>[
            <String, Object?>{
              'ids': <String, Object?>{'tmdb': entry.summary.tmdbId},
              'seasons': <Object?>[
                <String, Object?>{
                  'number': entry.seasonNumber,
                  'episodes': <Object?>[
                    <String, Object?>{
                      'number': entry.episodeNumber,
                      'watched_at': watchedAt,
                    },
                  ],
                },
              ],
            },
          ],
        },
      MediaType.tv => <String, Object?>{
          'shows': <Object?>[
            <String, Object?>{
              'ids': <String, Object?>{'tmdb': entry.summary.tmdbId},
              'watched_at': watchedAt,
            },
          ],
        },
    };

    await _requestJson(
      'POST',
      '/sync/history',
      accessToken: accessToken,
      body: body,
      expectedStatusCodes: const <int>{200},
    );
  }

  Future<List<TraktRecommendedTitle>> _fetchRecommendationsForType({
    required String path,
    required MediaType mediaType,
    required String accessToken,
    required int limit,
  }) async {
    final payload = await _requestJson(
      'GET',
      path,
      accessToken: accessToken,
      queryParameters: <String, String>{
        'limit': '$limit',
        'ignore_collected': 'true',
        'ignore_watchlisted': 'true',
        'extended': 'full',
      },
      expectedStatusCodes: const <int>{200},
    );
    final rows = _expectJsonList(payload);
    final items = <TraktRecommendedTitle>[];
    for (final row in rows) {
      final ids =
          row['ids'] as Map<String, dynamic>? ?? const <String, dynamic>{};
      final tmdbId = (ids['tmdb'] as num?)?.toInt();
      if (tmdbId == null) {
        continue;
      }
      final title = '${row['title'] ?? ''}'.trim();
      if (title.isEmpty) {
        continue;
      }
      final genreNames = (row['genres'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false);
      items.add(
        TraktRecommendedTitle(
          tmdbId: tmdbId,
          mediaType: mediaType,
          title: title,
          overview: row['overview'] as String?,
          rating: (row['rating'] as num?)?.toDouble(),
          releaseDate: _parseDateTime(
            mediaType == MediaType.movie
                ? row['released'] as String?
                : row['first_aired'] as String?,
          ),
          genreNames: genreNames,
          runtimeMinutes: (row['runtime'] as num?)?.toInt(),
        ),
      );
    }
    return items;
  }

  Future<_TraktMovieLookup> _resolveMovieLookup(int tmdbId) async {
    final cached = _movieLookupByTmdbId[tmdbId];
    if (cached != null) {
      return cached;
    }

    final payload = await _requestJson(
      'GET',
      '/search/tmdb/$tmdbId',
      queryParameters: const <String, String>{
        'id_type': 'movie',
      },
      expectedStatusCodes: const <int>{200},
    );
    final rows = _extractSearchRows(payload);
    for (final row in rows) {
      if ('${row['type'] ?? ''}' != 'movie') {
        continue;
      }
      final movie =
          row['movie'] as Map<String, dynamic>? ?? const <String, dynamic>{};
      final ids =
          movie['ids'] as Map<String, dynamic>? ?? const <String, dynamic>{};
      if ((ids['tmdb'] as num?)?.toInt() != tmdbId) {
        continue;
      }
      final lookup = _TraktMovieLookup(
        traktId: (ids['trakt'] as num?)?.toInt(),
        tmdbId: tmdbId,
        title: '${movie['title'] ?? ''}'.trim(),
        year: (movie['year'] as num?)?.toInt(),
      );
      _movieLookupByTmdbId[tmdbId] = lookup;
      return lookup;
    }

    throw TraktApiException(
        'Unable to resolve Trakt movie for TMDB id $tmdbId.');
  }

  Future<_TraktShowLookup> _resolveShowLookup(int tmdbId) async {
    final cached = _showLookupByTmdbId[tmdbId];
    if (cached != null) {
      return cached;
    }

    final payload = await _requestJson(
      'GET',
      '/search/tmdb/$tmdbId',
      queryParameters: const <String, String>{
        'id_type': 'show',
      },
      expectedStatusCodes: const <int>{200},
    );
    final rows = _extractSearchRows(payload);
    for (final row in rows) {
      if ('${row['type'] ?? ''}' != 'show') {
        continue;
      }
      final show =
          row['show'] as Map<String, dynamic>? ?? const <String, dynamic>{};
      final ids =
          show['ids'] as Map<String, dynamic>? ?? const <String, dynamic>{};
      if ((ids['tmdb'] as num?)?.toInt() != tmdbId) {
        continue;
      }
      final lookup = _TraktShowLookup(
        traktId: (ids['trakt'] as num?)?.toInt(),
        tmdbId: tmdbId,
        slug: ids['slug'] as String?,
      );
      _showLookupByTmdbId[tmdbId] = lookup;
      return lookup;
    }

    throw TraktApiException(
        'Unable to resolve Trakt show for TMDB id $tmdbId.');
  }

  Future<_TraktEpisodeLookup> _resolveEpisodeLookup({
    required int showTmdbId,
    required int seasonNumber,
    required int episodeNumber,
  }) async {
    final cacheKey = '$showTmdbId:$seasonNumber:$episodeNumber';
    final cached = _episodeLookupByKey[cacheKey];
    if (cached != null) {
      return cached;
    }

    final showLookup = await _resolveShowLookup(showTmdbId);
    final showId = showLookup.traktId?.toString() ?? showLookup.slug;
    if (showId == null || showId.trim().isEmpty) {
      throw TraktApiException(
        'Unable to resolve a Trakt show identifier for TMDB id $showTmdbId.',
      );
    }

    final payload = await _requestJson(
      'GET',
      '/shows/$showId/seasons/$seasonNumber/episodes/$episodeNumber',
      queryParameters: const <String, String>{'extended': 'full'},
      expectedStatusCodes: const <int>{200},
    );
    final json = _expectJsonMap(payload);
    final ids =
        json['ids'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final lookup = _TraktEpisodeLookup(
      traktId: (ids['trakt'] as num?)?.toInt(),
      tvdbId: (ids['tvdb'] as num?)?.toInt(),
    );
    _episodeLookupByKey[cacheKey] = lookup;
    return lookup;
  }

  TraktAccount _accountFromTokenJson(
    Map<String, dynamic> json, {
    required String username,
  }) {
    final tokenCreatedAtSeconds = (json['created_at'] as num?)?.toInt();
    final expiresInSeconds = (json['expires_in'] as num?)?.toInt();
    final accessToken = json['access_token'] as String?;
    final refreshToken = json['refresh_token'] as String?;
    final tokenType = json['token_type'] as String?;
    final scope = (json['scope'] as String?) ?? '';
    if (tokenCreatedAtSeconds == null ||
        expiresInSeconds == null ||
        accessToken == null ||
        refreshToken == null ||
        tokenType == null) {
      throw const TraktApiException(
        'Trakt returned an incomplete OAuth token response.',
      );
    }

    return TraktAccount(
      username: username,
      accessToken: accessToken,
      refreshToken: refreshToken,
      tokenType: tokenType,
      scope: scope,
      tokenCreatedAt: DateTime.fromMillisecondsSinceEpoch(
        tokenCreatedAtSeconds * 1000,
        isUtc: true,
      ),
      expiresInSeconds: expiresInSeconds,
    );
  }

  Future<dynamic> _requestJson(
    String method,
    String path, {
    Map<String, String> queryParameters = const <String, String>{},
    String? accessToken,
    Object? body,
    Set<int> expectedStatusCodes = const <int>{200},
    bool includeApiHeaders = true,
  }) async {
    final uri = _apiBaseUri.replace(
      path: '${_apiBaseUri.path}$path',
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    final isRetriableMethod = method.toUpperCase() == 'GET';
    final maxAttempts = isRetriableMethod ? _maxGetAttempts : 1;
    for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
      try {
        final request =
            await _client.openUrl(method, uri).timeout(_requestTimeout);
        if (includeApiHeaders) {
          request.headers.set('trakt-api-key', clientId);
          request.headers.set('trakt-api-version', '2');
        }
        request.headers.set('Accept', 'application/json');
        if (accessToken != null && accessToken.trim().isNotEmpty) {
          request.headers.set('Authorization', 'Bearer ${accessToken.trim()}');
        }
        if (body != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(body));
        }

        final response = await request.close().timeout(_requestTimeout);
        final payload = await response
            .transform(utf8.decoder)
            .join()
            .timeout(_requestTimeout);
        if (!expectedStatusCodes.contains(response.statusCode)) {
          if (!isRetriableMethod ||
              !_isRetriableStatus(response.statusCode) ||
              attempt >= maxAttempts) {
            throw TraktApiException(
              _errorMessageFromPayload(payload),
              statusCode: response.statusCode,
              uri: uri,
            );
          }
        } else {
          final trimmedPayload = payload.trim();
          if (trimmedPayload.isEmpty) {
            return null;
          }
          return jsonDecode(trimmedPayload);
        }
      } on TimeoutException {
        if (!isRetriableMethod || attempt >= maxAttempts) {
          rethrow;
        }
      } on SocketException {
        if (!isRetriableMethod || attempt >= maxAttempts) {
          rethrow;
        }
      }
      await _retryDelay(attempt);
    }
    throw TraktApiException('The Trakt request failed.', uri: uri);
  }

  bool _isRetriableStatus(int statusCode) {
    return statusCode == 429 || statusCode >= 500;
  }

  Future<void> _retryDelay(int attempt) {
    return Future<void>.delayed(Duration(milliseconds: 240 * attempt));
  }

  List<Map<String, dynamic>> _extractSearchRows(dynamic payload) {
    if (payload is List) {
      return payload.whereType<Map<String, dynamic>>().toList(growable: false);
    }
    if (payload is Map<String, dynamic>) {
      return <Map<String, dynamic>>[payload];
    }
    return const <Map<String, dynamic>>[];
  }

  Map<String, dynamic> _expectJsonMap(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      return payload;
    }
    throw const TraktApiException(
        'Trakt returned an unexpected response type.');
  }

  List<Map<String, dynamic>> _expectJsonList(dynamic payload) {
    if (payload is List) {
      return payload.whereType<Map<String, dynamic>>().toList(growable: false);
    }
    throw const TraktApiException(
        'Trakt returned an unexpected response type.');
  }

  DateTime? _parseDateTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }

  String _errorMessageFromPayload(String payload) {
    final trimmed = payload.trim();
    if (trimmed.isEmpty) {
      return 'The Trakt request failed.';
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        final description =
            '${decoded['error_description'] ?? decoded['error'] ?? decoded['message'] ?? ''}'
                .trim();
        if (description.isNotEmpty) {
          return description;
        }
      }
    } catch (_) {
      // Fall back to the raw payload when the response is not JSON.
    }
    return trimmed;
  }
}

class _TraktMovieLookup {
  const _TraktMovieLookup({
    required this.traktId,
    required this.tmdbId,
    required this.title,
    required this.year,
  });

  final int? traktId;
  final int tmdbId;
  final String title;
  final int? year;
}

class _TraktShowLookup {
  const _TraktShowLookup({
    required this.traktId,
    required this.tmdbId,
    required this.slug,
  });

  final int? traktId;
  final int tmdbId;
  final String? slug;
}

class _TraktEpisodeLookup {
  const _TraktEpisodeLookup({
    required this.traktId,
    required this.tvdbId,
  });

  final int? traktId;
  final int? tvdbId;
}
