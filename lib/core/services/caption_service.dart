import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../models/caption_resolution.dart';
import '../models/media_type.dart';

abstract interface class CaptionService {
  Future<CaptionResolution> resolveCaptions({
    required int? tmdbId,
    required MediaType mediaType,
    required String languageCode,
    int? seasonNumber,
    int? episodeNumber,
    String? imdbId,
    String? title,
  });
}

class NoOpCaptionService implements CaptionService {
  const NoOpCaptionService();

  @override
  Future<CaptionResolution> resolveCaptions({
    required int? tmdbId,
    required MediaType mediaType,
    required String languageCode,
    int? seasonNumber,
    int? episodeNumber,
    String? imdbId,
    String? title,
  }) async {
    return CaptionResolution.empty;
  }
}

class HttpCaptionService implements CaptionService {
  HttpCaptionService({
    required this.baseUri,
    HttpClient? client,
    Duration timeout = const Duration(seconds: 6),
    int maxAttempts = 3,
    Duration retryBaseDelay = const Duration(milliseconds: 200),
    Duration maxRetryDelay = const Duration(milliseconds: 1200),
    Duration circuitBreakerCooldown = const Duration(seconds: 15),
    int circuitBreakerFailureThreshold = 5,
    math.Random? random,
  })  : _client = client ?? HttpClient(),
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

  @override
  Future<CaptionResolution> resolveCaptions({
    required int? tmdbId,
    required MediaType mediaType,
    required String languageCode,
    int? seasonNumber,
    int? episodeNumber,
    String? imdbId,
    String? title,
  }) async {
    final uri = baseUri.replace(
      path: '${baseUri.path.replaceFirst(RegExp(r'/$'), '')}/v1/captions',
      queryParameters: <String, String>{
        if (tmdbId != null) 'tmdbId': '$tmdbId',
        'mediaType': mediaType.name,
        'languageCode': languageCode,
        if (seasonNumber != null) 'seasonNumber': '$seasonNumber',
        if (episodeNumber != null) 'episodeNumber': '$episodeNumber',
        if (imdbId != null && imdbId.trim().isNotEmpty) 'imdbId': imdbId.trim(),
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      },
    );

    final payload = await _getJsonPayload(uri);
    if (payload == null) {
      return CaptionResolution.empty;
    }
    if (payload is! Map<String, dynamic>) {
      return CaptionResolution.empty;
    }
    return CaptionResolution.fromJson(payload);
  }

  Future<dynamic> _getJsonPayload(Uri uri) async {
    if (!_isCircuitAvailable()) {
      return null;
    }

    for (var attempt = 1; attempt <= _maxAttempts; attempt += 1) {
      try {
        final request = await _client.getUrl(uri).timeout(_timeout);
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close().timeout(_timeout);
        final body =
            await response.transform(utf8.decoder).join().timeout(_timeout);

        if (response.statusCode < 200 || response.statusCode >= 300) {
          if (_isRetryableStatus(response.statusCode)) {
            _recordFailure();
            if (attempt >= _maxAttempts) {
              return null;
            }
            final retryDelay = _retryAfterFromHeaders(response.headers) ??
                _retryDelayFor(attempt);
            await Future<void>.delayed(retryDelay);
            continue;
          }
          return null;
        }

        dynamic decoded;
        try {
          decoded = jsonDecode(body);
        } on FormatException {
          _recordFailure();
          return null;
        }
        _recordSuccess();
        return decoded;
      } on TimeoutException {
        _recordFailure();
      } on SocketException {
        _recordFailure();
      } on HandshakeException {
        _recordFailure();
      } on HttpException {
        _recordFailure();
      }

      if (attempt >= _maxAttempts) {
        return null;
      }
      await Future<void>.delayed(_retryDelayFor(attempt));
    }

    return null;
  }

  bool _isCircuitAvailable() {
    final openUntil = _circuitOpenUntilUtc;
    if (openUntil == null) {
      return true;
    }
    final now = DateTime.now().toUtc();
    if (!now.isBefore(openUntil)) {
      _circuitOpenUntilUtc = null;
      return true;
    }
    return false;
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

  bool _isRetryableStatus(int statusCode) {
    return statusCode == HttpStatus.requestTimeout ||
        statusCode == HttpStatus.tooManyRequests ||
        statusCode == HttpStatus.badGateway ||
        statusCode == HttpStatus.serviceUnavailable ||
        statusCode == HttpStatus.gatewayTimeout;
  }

  Duration _retryDelayFor(int attempt) {
    final multiplier = math.min(1 << (attempt - 1), 8);
    final baseDelayMs = _retryBaseDelay.inMilliseconds * multiplier;
    final jitterMs = _random.nextInt(150);
    final delayMs =
        math.min(baseDelayMs + jitterMs, _maxRetryDelay.inMilliseconds);
    return Duration(milliseconds: delayMs);
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
      final retryAt = HttpDate.parse(raw);
      final remaining = retryAt.difference(DateTime.now().toUtc());
      return remaining.isNegative ? Duration.zero : remaining;
    } catch (_) {
      return null;
    }
  }
}
