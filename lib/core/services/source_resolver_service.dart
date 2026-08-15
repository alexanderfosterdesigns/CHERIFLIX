import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../models/media_type.dart';
import '../models/playback_target.dart';
import '../models/profile_playback_settings.dart';
import '../models/provider_config.dart';
import 'source_health_store.dart';

class SourceResolverUnavailableException implements Exception {
  const SourceResolverUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class SourceResolverService {
  Future<PlaybackTarget?> resolveTitle({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    int? seasonNumber,
    int? episodeNumber,
  });

  Future<PlaybackTarget?> resolveNextSource({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    required int currentProviderIndex,
    int? seasonNumber,
    int? episodeNumber,
    bool probeCandidates = true,
  });

  Future<PlaybackTarget?> resolveSpecificSource({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    required int providerIndex,
    int? seasonNumber,
    int? episodeNumber,
    bool probeCandidate = false,
  });

  Future<void> reportSourceSuccess({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
    int? seasonNumber,
    int? episodeNumber,
  });

  Future<void> reportSourceFailure({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
    required SourceFailureKind kind,
    int? seasonNumber,
    int? episodeNumber,
  });

  Future<Duration?> estimateNextSourceRetryDelay({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    int? seasonNumber,
    int? episodeNumber,
  });
}

class NoOpSourceResolverService implements SourceResolverService {
  const NoOpSourceResolverService();

  @override
  Future<PlaybackTarget?> resolveTitle({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    return null;
  }

  @override
  Future<PlaybackTarget?> resolveNextSource({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    required int currentProviderIndex,
    int? seasonNumber,
    int? episodeNumber,
    bool probeCandidates = true,
  }) async {
    return null;
  }

  @override
  Future<PlaybackTarget?> resolveSpecificSource({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    required int providerIndex,
    int? seasonNumber,
    int? episodeNumber,
    bool probeCandidate = false,
  }) async {
    return null;
  }

  @override
  Future<void> reportSourceFailure({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
    required SourceFailureKind kind,
    int? seasonNumber,
    int? episodeNumber,
  }) async {}

  @override
  Future<void> reportSourceSuccess({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
    int? seasonNumber,
    int? episodeNumber,
  }) async {}

  @override
  Future<Duration?> estimateNextSourceRetryDelay({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    return null;
  }
}

class MissingSourceResolverService implements SourceResolverService {
  const MissingSourceResolverService();

  static const String _message =
      'Playback requires CHERIFLIX_SOURCE_RESOLVER_URL to be configured.';

  Never _throw() {
    throw const SourceResolverUnavailableException(_message);
  }

  @override
  Future<PlaybackTarget?> resolveTitle({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    _throw();
  }

  @override
  Future<PlaybackTarget?> resolveNextSource({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    required int currentProviderIndex,
    int? seasonNumber,
    int? episodeNumber,
    bool probeCandidates = true,
  }) async {
    _throw();
  }

  @override
  Future<PlaybackTarget?> resolveSpecificSource({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    required int providerIndex,
    int? seasonNumber,
    int? episodeNumber,
    bool probeCandidate = false,
  }) async {
    _throw();
  }

  @override
  Future<void> reportSourceFailure({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
    required SourceFailureKind kind,
    int? seasonNumber,
    int? episodeNumber,
  }) async {}

  @override
  Future<void> reportSourceSuccess({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
    int? seasonNumber,
    int? episodeNumber,
  }) async {}

  @override
  Future<Duration?> estimateNextSourceRetryDelay({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    _throw();
  }
}

class HttpSourceResolverService implements SourceResolverService {
  HttpSourceResolverService({
    required this.baseUri,
    HttpClient? client,
    Duration timeout = const Duration(seconds: 8),
    int maxAttempts = 3,
    Duration retryBaseDelay = const Duration(milliseconds: 220),
    Duration maxRetryDelay = const Duration(seconds: 2),
    Duration circuitBreakerCooldown = const Duration(seconds: 18),
    int circuitBreakerFailureThreshold = 5,
    math.Random? random,
  })  : _client = client ?? _createResolverHttpClient(timeout),
        _timeout = timeout,
        _maxAttempts = maxAttempts < 1 ? 1 : maxAttempts,
        _retryBaseDelay = retryBaseDelay,
        _maxRetryDelay = maxRetryDelay,
        _circuitBreakerCooldown = circuitBreakerCooldown,
        _circuitBreakerFailureThreshold = circuitBreakerFailureThreshold < 1
            ? 1
            : circuitBreakerFailureThreshold,
        _random = random ?? math.Random();

  final Uri baseUri;
  final HttpClient _client;
  final Duration _timeout;
  final int _maxAttempts;
  final Duration _retryBaseDelay;
  final Duration _maxRetryDelay;
  final Duration _circuitBreakerCooldown;
  final int _circuitBreakerFailureThreshold;
  final math.Random _random;
  int _consecutiveFailures = 0;
  DateTime? _circuitOpenUntilUtc;

  static const String _resolvePath = '/v1/sources/resolve';
  static const String _resolveNextPath = '/v1/sources/resolve-next';
  static const String _resolveSpecificPath = '/v1/sources/resolve-specific';
  static const String _successPath = '/v1/sources/success';
  static const String _failurePath = '/v1/sources/failure';
  static const String _retryDelayPath = '/v1/sources/retry-delay';

  @override
  Future<PlaybackTarget?> resolveTitle({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    final payload = await _postJson(
      _endpoint(_resolvePath),
      _buildBasePayload(
        profileId: profileId,
        tmdbId: tmdbId,
        mediaType: mediaType,
        providerConfig: providerConfig,
        settings: settings,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      ),
    );
    return _decodeTarget(payload);
  }

  @override
  Future<PlaybackTarget?> resolveNextSource({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    required int currentProviderIndex,
    int? seasonNumber,
    int? episodeNumber,
    bool probeCandidates = true,
  }) async {
    final payload = await _postJson(
      _endpoint(_resolveNextPath),
      <String, dynamic>{
        ..._buildBasePayload(
          profileId: profileId,
          tmdbId: tmdbId,
          mediaType: mediaType,
          providerConfig: providerConfig,
          settings: settings,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
        ),
        'currentProviderIndex': currentProviderIndex,
        'probeCandidates': probeCandidates,
      },
    );
    return _decodeTarget(payload);
  }

  @override
  Future<PlaybackTarget?> resolveSpecificSource({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    required int providerIndex,
    int? seasonNumber,
    int? episodeNumber,
    bool probeCandidate = false,
  }) async {
    final payload = await _postJson(
      _endpoint(_resolveSpecificPath),
      <String, dynamic>{
        ..._buildBasePayload(
          profileId: profileId,
          tmdbId: tmdbId,
          mediaType: mediaType,
          providerConfig: providerConfig,
          settings: settings,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
        ),
        'providerIndex': providerIndex,
        'probeCandidate': probeCandidate,
      },
    );
    return _decodeTarget(payload);
  }

  @override
  Future<void> reportSourceSuccess({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    await _postJson(
      _endpoint(_successPath),
      <String, dynamic>{
        'profileId': profileId,
        'tmdbId': tmdbId,
        'mediaType': mediaType.name,
        'providerIndex': providerIndex,
        if (seasonNumber != null) 'seasonNumber': seasonNumber,
        if (episodeNumber != null) 'episodeNumber': episodeNumber,
      },
    );
  }

  @override
  Future<void> reportSourceFailure({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
    required SourceFailureKind kind,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    await _postJson(
      _endpoint(_failurePath),
      <String, dynamic>{
        'profileId': profileId,
        'tmdbId': tmdbId,
        'mediaType': mediaType.name,
        'providerIndex': providerIndex,
        'kind': kind.name,
        if (seasonNumber != null) 'seasonNumber': seasonNumber,
        if (episodeNumber != null) 'episodeNumber': episodeNumber,
      },
    );
  }

  @override
  Future<Duration?> estimateNextSourceRetryDelay({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    final payload = await _postJson(
      _endpoint(_retryDelayPath),
      _buildBasePayload(
        profileId: profileId,
        tmdbId: tmdbId,
        mediaType: mediaType,
        providerConfig: providerConfig,
        settings: settings,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      ),
    );
    final rawValue = payload?['retryAfterMilliseconds'] ??
        payload?['retry_after_milliseconds'];
    final milliseconds = _readInt(rawValue);
    if (milliseconds == null || milliseconds <= 0) {
      return null;
    }
    return Duration(milliseconds: milliseconds);
  }

  Map<String, dynamic> _buildBasePayload({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    int? seasonNumber,
    int? episodeNumber,
  }) {
    return <String, dynamic>{
      'profileId': profileId,
      'tmdbId': tmdbId,
      'mediaType': mediaType.name,
      if (seasonNumber != null) 'seasonNumber': seasonNumber,
      if (episodeNumber != null) 'episodeNumber': episodeNumber,
      'providerConfig': providerConfig.toJson(),
      'settings': settings.toJson(),
    };
  }

  Future<Map<String, dynamic>?> _postJson(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    _throwIfCircuitOpen();
    _RetryableSourceResolverException? lastRetryableFailure;
    for (var attempt = 1; attempt <= _maxAttempts; attempt += 1) {
      try {
        final payload = await _postJsonOnce(uri, body);
        _recordSuccess();
        return payload;
      } on _RetryableSourceResolverException catch (error) {
        lastRetryableFailure = error;
        _recordFailure();
        if (attempt >= _maxAttempts) {
          break;
        }
        final retryDelay = error.retryAfter ?? _retryDelayFor(attempt);
        await Future<void>.delayed(retryDelay);
      } on SourceResolverUnavailableException catch (error) {
        _recordFailure();
        rethrow;
      }
    }

    if (lastRetryableFailure != null) {
      throw SourceResolverUnavailableException(lastRetryableFailure.message);
    }
    throw const SourceResolverUnavailableException(
      'The source resolver service is temporarily unavailable.',
    );
  }

  Future<Map<String, dynamic>?> _postJsonOnce(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    try {
      final request = await _client.postUrl(uri).timeout(_timeout);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(_timeout);
      final responseBody =
          await response.transform(utf8.decoder).join().timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message =
            'The source resolver service returned HTTP ${response.statusCode}.';
        if (_isRetryableStatus(response.statusCode)) {
          throw _RetryableSourceResolverException(
            message,
            retryAfter: _retryAfterFromHeaders(response.headers),
          );
        }
        throw SourceResolverUnavailableException(message);
      }
      if (responseBody.trim().isEmpty) {
        return <String, dynamic>{};
      }
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
      return null;
    } on TimeoutException {
      throw const _RetryableSourceResolverException(
        'The source resolver service timed out.',
      );
    } on SocketException {
      throw const _RetryableSourceResolverException(
        'The source resolver service is unreachable.',
      );
    } on HandshakeException {
      throw const _RetryableSourceResolverException(
        'The source resolver service rejected the connection.',
      );
    } on HttpException {
      throw const _RetryableSourceResolverException(
        'The source resolver service returned an invalid response.',
      );
    } on FormatException {
      throw const SourceResolverUnavailableException(
        'The source resolver service returned malformed JSON.',
      );
    }
  }

  void _throwIfCircuitOpen() {
    final openUntil = _circuitOpenUntilUtc;
    if (openUntil == null) {
      return;
    }
    final now = DateTime.now().toUtc();
    if (!now.isBefore(openUntil)) {
      _circuitOpenUntilUtc = null;
      return;
    }
    throw const SourceResolverUnavailableException(
      'The source resolver service is temporarily paused after repeated failures.',
    );
  }

  void _recordSuccess() {
    _consecutiveFailures = 0;
    _circuitOpenUntilUtc = null;
  }

  void _recordFailure() {
    _consecutiveFailures += 1;
    if (_consecutiveFailures < _circuitBreakerFailureThreshold) {
      return;
    }
    _circuitOpenUntilUtc = DateTime.now().toUtc().add(_circuitBreakerCooldown);
  }

  Duration _retryDelayFor(int attempt) {
    final multiplier = math.min(1 << (attempt - 1), 8);
    final baseDelayMs = _retryBaseDelay.inMilliseconds * multiplier;
    final jitterMs = _random.nextInt(180);
    final delayMs =
        math.min(baseDelayMs + jitterMs, _maxRetryDelay.inMilliseconds);
    return Duration(milliseconds: delayMs);
  }

  bool _isRetryableStatus(int statusCode) {
    return statusCode == HttpStatus.tooManyRequests ||
        statusCode == HttpStatus.requestTimeout ||
        statusCode == HttpStatus.badGateway ||
        statusCode == HttpStatus.serviceUnavailable ||
        statusCode == HttpStatus.gatewayTimeout;
  }

  Duration? _retryAfterFromHeaders(HttpHeaders headers) {
    final raw = headers.value(HttpHeaders.retryAfterHeader)?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final seconds = int.tryParse(raw);
    if (seconds != null && seconds > 0) {
      return Duration(seconds: seconds);
    }
    try {
      final retryAfterAt = HttpDate.parse(raw);
      final remaining = retryAfterAt.difference(DateTime.now().toUtc());
      return remaining.isNegative ? Duration.zero : remaining;
    } catch (_) {
      return null;
    }
  }

  PlaybackTarget? _decodeTarget(Map<String, dynamic>? payload) {
    if (payload == null) {
      return null;
    }

    final rawTarget = payload['target'] ?? payload['playbackTarget'];
    if (rawTarget is Map<String, dynamic>) {
      return PlaybackTarget.fromJson(rawTarget);
    }

    if (payload.containsKey('uri') || payload.containsKey('url')) {
      return PlaybackTarget.fromJson(payload);
    }

    return null;
  }

  Uri _endpoint(String path) {
    final normalizedPath = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    return baseUri.replace(
      path: '$normalizedPath$path',
    );
  }

  int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }
}

HttpClient _createResolverHttpClient(Duration timeout) {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..idleTimeout = timeout;
  return client;
}

class _RetryableSourceResolverException implements Exception {
  const _RetryableSourceResolverException(
    this.message, {
    this.retryAfter,
  });

  final String message;
  final Duration? retryAfter;
}
