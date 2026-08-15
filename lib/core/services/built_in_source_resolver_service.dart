import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/media_summary.dart';
import '../models/media_type.dart';
import '../models/playback_target.dart';
import '../models/profile_playback_settings.dart';
import '../models/provider_config.dart';
import 'media_catalog_service.dart';
import 'hls_unwrap_proxy.dart';
import 'provider_catalog.dart';
import 'source_health_store.dart';
import 'source_resolver_service.dart';
import '../utils/safe_logging.dart';

bool isDirectManifestUri(Uri uri) {
  final path = uri.path.toLowerCase();
  return path.endsWith('.m3u8') || path.endsWith('.mpd');
}

bool isLikelyPlayableDirectManifestResponse({
  required Uri uri,
  required int statusCode,
  required String body,
}) {
  if (statusCode < 200 || statusCode >= 300) {
    return false;
  }

  final trimmedBody = body.trimLeft();
  if (trimmedBody.isEmpty) {
    return false;
  }

  final path = uri.path.toLowerCase();
  if (path.endsWith('.m3u8')) {
    return trimmedBody.startsWith('#EXTM3U');
  }
  if (path.endsWith('.mpd')) {
    return RegExp(r'<(?:[a-zA-Z0-9_-]+:)?MPD(?:\s|>)', caseSensitive: false)
        .hasMatch(trimmedBody);
  }
  return true;
}

class FallbackSourceResolverService implements SourceResolverService {
  const FallbackSourceResolverService({
    required this.primary,
    required this.fallback,
  });

  final SourceResolverService primary;
  final SourceResolverService fallback;

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
    return _raceDirectResolvers(
      primaryAction: () => primary.resolveTitle(
        profileId: profileId,
        tmdbId: tmdbId,
        mediaType: mediaType,
        providerConfig: providerConfig,
        settings: settings,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      ),
      fallbackAction: () => fallback.resolveTitle(
        profileId: profileId,
        tmdbId: tmdbId,
        mediaType: mediaType,
        providerConfig: providerConfig,
        settings: settings,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      ),
    );
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
    return _raceDirectResolvers(
      primaryAction: () => primary.resolveNextSource(
        profileId: profileId,
        tmdbId: tmdbId,
        mediaType: mediaType,
        providerConfig: providerConfig,
        settings: settings,
        currentProviderIndex: currentProviderIndex,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        probeCandidates: probeCandidates,
      ),
      fallbackAction: () => fallback.resolveNextSource(
        profileId: profileId,
        tmdbId: tmdbId,
        mediaType: mediaType,
        providerConfig: providerConfig,
        settings: settings,
        currentProviderIndex: currentProviderIndex,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        probeCandidates: probeCandidates,
      ),
    );
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
    return _raceDirectResolvers(
      primaryAction: () => primary.resolveSpecificSource(
        profileId: profileId,
        tmdbId: tmdbId,
        mediaType: mediaType,
        providerConfig: providerConfig,
        settings: settings,
        providerIndex: providerIndex,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        probeCandidate: probeCandidate,
      ),
      fallbackAction: () => fallback.resolveSpecificSource(
        profileId: profileId,
        tmdbId: tmdbId,
        mediaType: mediaType,
        providerConfig: providerConfig,
        settings: settings,
        providerIndex: providerIndex,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        probeCandidate: probeCandidate,
      ),
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
    await _ignoreErrors(
      () => primary.reportSourceFailure(
        profileId: profileId,
        tmdbId: tmdbId,
        mediaType: mediaType,
        providerIndex: providerIndex,
        kind: kind,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      ),
    );
    await _ignoreErrors(
      () => fallback.reportSourceFailure(
        profileId: profileId,
        tmdbId: tmdbId,
        mediaType: mediaType,
        providerIndex: providerIndex,
        kind: kind,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      ),
    );
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
    await _ignoreErrors(
      () => primary.reportSourceSuccess(
        profileId: profileId,
        tmdbId: tmdbId,
        mediaType: mediaType,
        providerIndex: providerIndex,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      ),
    );
    await _ignoreErrors(
      () => fallback.reportSourceSuccess(
        profileId: profileId,
        tmdbId: tmdbId,
        mediaType: mediaType,
        providerIndex: providerIndex,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      ),
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
    final primaryDelay = await _tryDelay(
      () => primary.estimateNextSourceRetryDelay(
        profileId: profileId,
        tmdbId: tmdbId,
        mediaType: mediaType,
        providerConfig: providerConfig,
        settings: settings,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      ),
    );
    if (primaryDelay != null) {
      return primaryDelay;
    }
    return fallback.estimateNextSourceRetryDelay(
      profileId: profileId,
      tmdbId: tmdbId,
      mediaType: mediaType,
      providerConfig: providerConfig,
      settings: settings,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
  }

  Future<PlaybackTarget?> _tryResolve(
    Future<PlaybackTarget?> Function() action,
  ) async {
    try {
      final target = await action();
      if (target != null && target.isDirectPlayable) {
        return target;
      }
    } catch (_) {}
    return null;
  }

  /// Remote resolution and the built-in extractor are independent. Running
  /// them together prevents an unavailable backend from delaying a working
  /// built-in source. A null/failed result never wins the race: exhaustion is
  /// reported only after both paths have completed.
  Future<PlaybackTarget?> _raceDirectResolvers({
    required Future<PlaybackTarget?> Function() primaryAction,
    required Future<PlaybackTarget?> Function() fallbackAction,
  }) async {
    final winner = Completer<PlaybackTarget?>();
    var completed = 0;

    Future<void> run(Future<PlaybackTarget?> Function() action) async {
      final target = await _tryResolve(action);
      if (target != null && !winner.isCompleted) {
        winner.complete(target);
        return;
      }
      completed += 1;
      if (completed == 2 && !winner.isCompleted) {
        winner.complete(null);
      }
    }

    unawaited(run(primaryAction));
    unawaited(run(fallbackAction));
    return winner.future;
  }

  Future<Duration?> _tryDelay(Future<Duration?> Function() action) async {
    try {
      return await action();
    } catch (_) {
      return null;
    }
  }

  Future<void> _ignoreErrors(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }
}

class BuiltInSourceResolverService implements SourceResolverService {
  BuiltInSourceResolverService({
    ProviderCatalog? providerCatalog,
    this.mediaCatalogService,
    BuiltInResolverHttpClient? httpClient,
  })  : providerCatalog = providerCatalog ?? const ProviderCatalog(),
        _httpClient = httpClient ?? IoBuiltInResolverHttpClient();

  final ProviderCatalog providerCatalog;
  final MediaCatalogService? mediaCatalogService;
  final BuiltInResolverHttpClient _httpClient;

  static const String _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36';
  static const Duration _vidKingServerResolveTimeout = Duration(seconds: 12);
  static const Duration _vidKingManifestProbeTimeout = Duration(seconds: 5);

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
    for (final provider in providerCatalog.orderedProviders(providerConfig)) {
      final target = await resolveSpecificSource(
        profileId: profileId,
        tmdbId: tmdbId,
        mediaType: mediaType,
        providerConfig: providerConfig,
        settings: settings,
        providerIndex: provider.canonicalIndex,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      );
      if (target != null) {
        return target;
      }
    }
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
    final orderedProviders = providerCatalog.orderedProviders(providerConfig);
    if (orderedProviders.isEmpty) {
      return null;
    }

    final currentPosition = orderedProviders.indexWhere(
      (provider) => provider.canonicalIndex == currentProviderIndex,
    );
    final candidates = currentPosition < 0
        ? orderedProviders
        : <ProviderDescriptor>[
            ...orderedProviders.skip(currentPosition + 1),
            ...orderedProviders.take(currentPosition),
          ];

    for (final provider in candidates) {
      final target = await resolveSpecificSource(
        profileId: profileId,
        tmdbId: tmdbId,
        mediaType: mediaType,
        providerConfig: providerConfig,
        settings: settings,
        providerIndex: provider.canonicalIndex,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      );
      if (target != null) {
        return target;
      }
    }

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
    final provider = providerCatalog.defaultProviders.firstWhere(
      (candidate) => candidate.canonicalIndex == providerIndex,
      orElse: () => throw StateError('Unknown provider index: $providerIndex'),
    );

    final pageUri = ProviderCatalog.buildUri(
      provider: provider,
      tmdbId: tmdbId,
      mediaType: mediaType,
      settings: settings,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
    if (pageUri == null) {
      return null;
    }

    try {
      switch (provider.key) {
        case 'vidking':
          return await _resolveVidKing(
            provider: provider,
            pageUri: pageUri,
            tmdbId: tmdbId,
            mediaType: mediaType,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
          );
        case 'vidsrc':
        case 'vidsrc_embed':
        case 'vsembed':
        case 'vsrcsu':
        case 'vidsrcme':
        case 'embedsu':
          return await _resolveVidsrcNetFamily(
            provider: provider,
            pageUri: pageUri,
            tmdbId: tmdbId,
            mediaType: mediaType,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
          );
        case 'videasy':
          return await _resolveVideasy(
            provider: provider,
            tmdbId: tmdbId,
            mediaType: mediaType,
            languageCode: settings.preferredAudioLanguageCode,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
          );
        case 'vixsrc':
          return await _resolveVixSrc(
            provider: provider,
            pageUri: pageUri,
            tmdbId: tmdbId,
            mediaType: mediaType,
            languageCode: settings.preferredAudioLanguageCode,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
          );
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
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

  Future<PlaybackTarget?> _resolveVidKing({
    required ProviderDescriptor provider,
    required Uri pageUri,
    required int tmdbId,
    required MediaType mediaType,
    required int? seasonNumber,
    required int? episodeNumber,
  }) async {
    if (mediaType == MediaType.tv &&
        (seasonNumber == null || episodeNumber == null)) {
      return null;
    }

    final mediaTypeName = mediaType == MediaType.movie ? 'movie' : 'tv';
    final metadataUri = Uri.https(
      'db.speedracelight.com',
      '/3/$mediaTypeName/$tmdbId',
      const <String, String>{'append_to_response': 'external_ids'},
    );
    final requestHeaders = _navigationHeaders(pageUri);
    final metadataResponse = await _safeGet(
      metadataUri,
      headers: requestHeaders,
    );
    final metadata = _decodeJsonObject(metadataResponse?.body);
    if (metadata == null) {
      return null;
    }

    final title =
        '${metadata[mediaType == MediaType.movie ? 'title' : 'name'] ?? ''}'
            .trim();
    final releaseDate = DateTime.tryParse(
      '${metadata[mediaType == MediaType.movie ? 'release_date' : 'first_air_date'] ?? ''}',
    );
    final externalIds = _decodeJsonObject(metadata['external_ids']);
    final imdbId = '${externalIds?['imdb_id'] ?? ''}'.trim();
    if (title.isEmpty) {
      return null;
    }

    final seed = await _loadVidKingSeed(
      tmdbId,
      pageUri: pageUri,
    );
    if (seed == null) {
      return null;
    }
    final playbackHeaders = _playbackHeaders(pageUri);
    final playableSourceUrls = <String>[];
    for (final server in _vidKingServers) {
      final sourceUrl = await _resolveVidKingServerSourceUrl(
        server: server,
        title: title,
        mediaTypeName: mediaTypeName,
        releaseYear: releaseDate?.year.toString() ?? '',
        episodeNumber: episodeNumber ?? 1,
        seasonNumber: seasonNumber ?? 1,
        tmdbId: tmdbId,
        imdbId: imdbId,
        initialSeed: seed,
        pageUri: pageUri,
        requestHeaders: requestHeaders,
      ).timeout(
        _vidKingServerResolveTimeout,
        onTimeout: () => null,
      );
      if (sourceUrl == null || playableSourceUrls.contains(sourceUrl)) {
        continue;
      }
      final isPlayable = await _isPlayableVidKingSourceUrl(
        sourceUrl,
        headers: playbackHeaders,
      ).timeout(
        _vidKingManifestProbeTimeout,
        onTimeout: () => false,
      );
      if (!isPlayable) {
        continue;
      }
      playableSourceUrls.add(sourceUrl);
      if (playableSourceUrls.length >= _vidKingDesiredSourceCount) {
        break;
      }
    }
    if (playableSourceUrls.isNotEmpty) {
      final sourceUrl = playableSourceUrls.first;
      final sourceUri = Uri.parse(sourceUrl);
      Uri playerUri = sourceUri;
      if (Platform.isAndroid &&
          _inferSourceKind(sourceUrl) == PlaybackSourceKind.hls) {
        try {
          // libmpv's Android TLS/segment path can wedge its synchronous
          // property bridge after a CDN read failure. Route the complete HLS
          // chain through the same bounded loopback adapter used by VixSrc so
          // manifests, keys, Range requests and segments retain their headers
          // and use Android's HttpClient. A proxy setup failure rejects this
          // candidate instead of handing the known-unsafe raw URL to the TV
          // player and potentially making the whole app unresponsive.
          playerUri = await HlsUnwrapProxy.instance.sanitizeMaster(
            sourceUri,
            headers: playbackHeaders,
            stripSubtitleTracks: true,
            proxyChildren: true,
          );
        } catch (error) {
          cheriflixLog(
            'playback-provider',
            jsonEncode(<String, Object?>{
              'provider': provider.key,
              'outcome': 'android-hls-proxy-rejected',
              'host': sourceUri.host,
              'errorType': error.runtimeType.toString(),
            }),
          );
          return null;
        }
      }
      return PlaybackTarget(
        uri: playerUri,
        providerKey: provider.key,
        providerLabel: provider.label,
        providerIndex: provider.canonicalIndex,
        sourceKind: _inferSourceKind(sourceUrl),
        httpHeaders: playbackHeaders,
        pageUri: pageUri,
        fallbackUris: Platform.isAndroid
            ? const <Uri>[]
            : playableSourceUrls.skip(1).map(Uri.parse).toList(growable: false),
      );
    }

    return null;
  }

  Future<String?> _resolveVidKingServerSourceUrl({
    required _VidKingServer server,
    required String title,
    required String mediaTypeName,
    required String releaseYear,
    required int episodeNumber,
    required int seasonNumber,
    required int tmdbId,
    required String imdbId,
    required String initialSeed,
    required Uri pageUri,
    required Map<String, String> requestHeaders,
  }) async {
    var activeSeed = initialSeed;
    for (var attempt = 0; attempt < 2; attempt += 1) {
      final sourceUri = Uri.https(
        'api.speedracelight.com',
        '/${server.endpoint}',
        <String, String>{
          'title': title,
          'mediaType': mediaTypeName,
          'year': releaseYear,
          'episodeId': '$episodeNumber',
          'seasonId': '$seasonNumber',
          'tmdbId': '$tmdbId',
          'imdbId': imdbId,
          'enc': '2',
          'seed': activeSeed,
          '_t': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );
      final encryptedResponse = await _safeGet(
        sourceUri,
        headers: <String, String>{
          ...requestHeaders,
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0',
        },
      );
      final encryptedBody = encryptedResponse?.body.trim() ?? '';
      if (encryptedBody.isEmpty) {
        return null;
      }

      try {
        final decodedPayload = _decodeVidKingPayload(
          encryptedBody,
          activeSeed,
          tmdbId,
        );
        final payload = _decodeJsonObject(decodedPayload);
        return _selectVidKingSourceUrl(
          payload?['sources'],
          qualityFilter: server.qualityFilter,
        );
      } catch (_) {
        if (attempt > 0) {
          return null;
        }
        final refreshedSeed = await _loadVidKingSeed(
          tmdbId,
          pageUri: pageUri,
        );
        if (refreshedSeed == null || refreshedSeed == activeSeed) {
          return null;
        }
        activeSeed = refreshedSeed;
      }
    }
    return null;
  }

  Future<bool> _isPlayableVidKingSourceUrl(
    String sourceUrl, {
    required Map<String, String> headers,
  }) async {
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null || uri.host.isEmpty) {
      return false;
    }
    if (!isDirectManifestUri(uri)) {
      return true;
    }
    final response = await _safeGet(uri, headers: headers);
    if (response == null) {
      return false;
    }
    final manifestIsPlayable = isLikelyPlayableDirectManifestResponse(
      uri: uri,
      statusCode: response.statusCode,
      body: response.body,
    );
    if (!manifestIsPlayable || !uri.path.toLowerCase().endsWith('.m3u8')) {
      return manifestIsPlayable;
    }

    // Some providers return a syntactically valid playlist while every media
    // segment is forbidden. Probe one real segment so the player is never
    // handed a source that can only spin until its startup timeout.
    final firstSegmentPath = response.body
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .firstOrNull;
    if (firstSegmentPath == null) {
      return false;
    }
    final firstSegmentUri = uri.resolve(firstSegmentPath);
    final segmentResponse = await _safeGet(
      firstSegmentUri,
      headers: <String, String>{
        ...headers,
        'Range': 'bytes=0-2047',
      },
    );
    if (segmentResponse == null) {
      return false;
    }
    final prefix = segmentResponse.body.trimLeft().toLowerCase();
    return !prefix.startsWith('<!doctype html') && !prefix.startsWith('<html');
  }

  Future<String?> _loadVidKingSeed(
    int tmdbId, {
    required Uri pageUri,
  }) async {
    final response = await _safeGet(
      Uri.https(
        'api.speedracelight.com',
        '/seed',
        <String, String>{'mediaId': '$tmdbId'},
      ),
      headers: _navigationHeaders(pageUri),
    );
    final payload = _decodeJsonObject(response?.body);
    final seed = '${payload?['seed'] ?? ''}'.trim();
    return seed.isEmpty ? null : seed;
  }

  String? _selectVidKingSourceUrl(
    Object? value, {
    String? qualityFilter,
  }) {
    if (value is! List) {
      return null;
    }
    final candidates = <String>[];
    for (final source in value) {
      if (source is! Map) {
        continue;
      }
      final quality = '${source['quality'] ?? ''}'.trim();
      if (qualityFilter != null &&
          quality.toLowerCase() != qualityFilter.toLowerCase()) {
        continue;
      }
      final sourceUrl = '${source['url'] ?? ''}'.trim();
      final uri = Uri.tryParse(sourceUrl);
      if (uri != null &&
          (uri.scheme == 'https' || uri.scheme == 'http') &&
          uri.host.isNotEmpty) {
        candidates.add(sourceUrl);
      }
    }
    if (candidates.isEmpty) {
      return null;
    }
    return candidates.firstWhere(
      (url) => url.toLowerCase().contains('.m3u8'),
      orElse: () => candidates.firstWhere(
        (url) => url.toLowerCase().contains('.mpd'),
        orElse: () => candidates.first,
      ),
    );
  }

  Future<PlaybackTarget?> _resolveVideasy({
    required ProviderDescriptor provider,
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
    required int? seasonNumber,
    required int? episodeNumber,
  }) async {
    final summary = await _loadSummary(
      tmdbId: tmdbId,
      mediaType: mediaType,
      languageCode: languageCode,
    );
    if (summary == null) {
      return null;
    }

    for (final requestUri in _videasyCandidateUris(
      tmdbId: tmdbId,
      mediaType: mediaType,
      summary: summary,
      languageCode: languageCode,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    )) {
      final encryptedResponse = await _safeGet(requestUri);
      final encryptedBody = encryptedResponse?.body.trim() ?? '';
      if (encryptedBody.isEmpty) {
        continue;
      }

      final decodedResponse = await _safePostJson(
        Uri.parse('https://enc-dec.app/api/dec-videasy'),
        <String, Object?>{
          'text': encryptedBody,
          'id': '$tmdbId',
        },
      );
      final payload = _decodeJsonObject(decodedResponse?.body);
      final resultMap = _decodeJsonObject(payload?['result']);
      final sources = resultMap?['sources'];
      if (sources is! List) {
        continue;
      }

      final sourceUrl = _firstVideasySourceUrl(sources);
      if (sourceUrl == null) {
        continue;
      }

      return PlaybackTarget(
        uri: Uri.parse(sourceUrl),
        providerKey: provider.key,
        providerLabel: provider.label,
        providerIndex: provider.canonicalIndex,
        sourceKind: _inferSourceKind(sourceUrl),
        httpHeaders: const <String, String>{
          'Referer': 'https://player.videasy.net/',
          'Origin': 'https://player.videasy.net',
          'User-Agent': _browserUserAgent,
        },
        pageUri: requestUri,
      );
    }

    return null;
  }

  /// Resolves the public VixSrc player flow to the HLS master playlist that
  /// its own HTML player consumes. No provider page or ad frame is mounted in
  /// Cheriflix; the resulting manifest is still validated before handoff.
  Future<PlaybackTarget?> _resolveVixSrc({
    required ProviderDescriptor provider,
    required Uri pageUri,
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
    required int? seasonNumber,
    required int? episodeNumber,
  }) async {
    final watch = Stopwatch()..start();
    void trace(String stage, BuiltInResolverResponse? response) {
      cheriflixLog(
        'playback-provider',
        jsonEncode(<String, Object?>{
          'provider': 'vixsrc',
          'outcome': 'resolver-stage',
          'stage': stage,
          'elapsedMs': watch.elapsedMilliseconds,
          if (response != null) 'status': response.statusCode,
          if (response != null) 'bodyBytes': response.body.length,
          if (response == null) 'reason': 'request-failed',
        }),
      );
    }

    if (mediaType == MediaType.tv &&
        (seasonNumber == null || episodeNumber == null)) {
      return null;
    }

    final apiPath = mediaType == MediaType.movie
        ? '/api/movie/$tmdbId'
        : '/api/tv/$tmdbId/$seasonNumber/$episodeNumber';
    final apiUri = Uri.https('vixsrc.to', apiPath);
    final apiResponse = await _safeGet(
      apiUri,
      headers: _navigationHeaders(pageUri),
    );
    trace('episode-api', apiResponse);
    final apiPayload = _decodeJsonObject(apiResponse?.body);
    final rawEmbedPath = '${apiPayload?['src'] ?? ''}'.trim();
    final embedUri = _absoluteUri(pageUri, rawEmbedPath);
    if (embedUri == null || embedUri.host != 'vixsrc.to') {
      return null;
    }

    final embedResponse = await _safeGet(
      embedUri,
      headers: _navigationHeaders(pageUri),
    );
    trace('embed-page', embedResponse);
    final embedHtml = embedResponse?.body ?? '';
    if (embedHtml.isEmpty) {
      return null;
    }
    final markerIndex = embedHtml.indexOf('window.masterPlaylist');
    if (markerIndex < 0) {
      return null;
    }
    final markerEnd = markerIndex + 2200 < embedHtml.length
        ? markerIndex + 2200
        : embedHtml.length;
    final playlistBlock = embedHtml.substring(markerIndex, markerEnd);
    final token = _firstMatch(playlistBlock, <RegExp>[
      RegExp(r'''['"]token['"]\s*:\s*['"]([^'"]+)'''),
    ]);
    final expires = _firstMatch(playlistBlock, <RegExp>[
      RegExp(r'''['"]expires['"]\s*:\s*['"]([^'"]+)'''),
    ]);
    final asn = _firstMatch(playlistBlock, <RegExp>[
      RegExp(r'''['"]asn['"]\s*:\s*['"]([^'"]*)'''),
    ]);
    final rawPlaylistUrl = _firstMatch(playlistBlock, <RegExp>[
      RegExp(r'''url\s*:\s*['"]([^'"]+/playlist/[^'"]+)'''),
    ]);
    final playlistUri =
        rawPlaylistUrl == null ? null : _absoluteUri(embedUri, rawPlaylistUrl);
    if (playlistUri == null || token == null || expires == null) {
      return null;
    }

    final normalizedLanguage = languageCode.trim().toLowerCase();
    final sourceUri = playlistUri.replace(
      queryParameters: <String, String>{
        ...playlistUri.queryParameters,
        'token': token,
        'expires': expires,
        if (asn != null && asn.isNotEmpty) 'asn': asn,
        'h': '1',
        'lang': normalizedLanguage.isEmpty ? 'en' : normalizedLanguage,
      },
    );
    final expiresAtEpochMs = int.tryParse(expires);
    final playbackHeaders = _playbackHeaders(embedUri);
    final masterResponse = await _safeGet(
      sourceUri,
      headers: playbackHeaders,
    );
    trace('master-manifest', masterResponse);
    final masterManifest = masterResponse?.body ?? '';
    if (masterResponse == null ||
        masterResponse.statusCode < 200 ||
        masterResponse.statusCode >= 300 ||
        !masterManifest.trimLeft().startsWith('#EXTM3U')) {
      return null;
    }
    final sanitizedSourceUri = await HlsUnwrapProxy.instance.sanitizeMaster(
      sourceUri,
      headers: playbackHeaders,
      stripSubtitleTracks: true,
      selectSingleVariant: Platform.isAndroid,
      preferredAudioLanguage:
          normalizedLanguage.isEmpty ? 'en' : normalizedLanguage,
      prefetchedManifest: masterManifest,
      // Android libmpv/mbedTLS intermittently fails against this CDN even
      // when Android's HttpClient validates the same segment. Keep one player
      // and bridge the complete HLS request chain through loopback so child
      // playlists, keys, Range requests and segments use Android networking.
      proxyChildren: Platform.isAndroid,
    );
    return PlaybackTarget(
      uri: sanitizedSourceUri,
      providerKey: provider.key,
      providerLabel: provider.label,
      providerIndex: provider.canonicalIndex,
      sourceKind: PlaybackSourceKind.hls,
      httpHeaders: playbackHeaders,
      pageUri: embedUri,
      expiresAtEpochMs:
          expiresAtEpochMs == null ? null : expiresAtEpochMs * 1000,
    );
  }

  Future<PlaybackTarget?> _resolveVidsrcNetFamily({
    required ProviderDescriptor provider,
    required Uri pageUri,
    required int tmdbId,
    required MediaType mediaType,
    required int? seasonNumber,
    required int? episodeNumber,
  }) async {
    final effectivePageUri = _normalizedVidsrcFamilyPageUri(
      provider: provider,
      originalPageUri: pageUri,
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );

    final pageResponse = await _safeGet(effectivePageUri);
    final pageBody = pageResponse?.body ?? '';
    if (pageBody.isEmpty) {
      return null;
    }

    final iframeSrc = _firstMatch(
      pageBody,
      <RegExp>[
        RegExp(
          r"""<iframe[^>]+id=["']player_iframe["'][^>]+src=["']([^"']+)""",
          caseSensitive: false,
        ),
        RegExp(
          r"""<iframe[^>]+src=["']([^"']+)""",
          caseSensitive: false,
        ),
      ],
    );
    if (iframeSrc == null) {
      return null;
    }

    final iframeUri = _absoluteUri(effectivePageUri, iframeSrc);
    if (iframeUri == null) {
      return null;
    }

    final iframeResponse = await _safeGet(
      iframeUri,
      headers: _navigationHeaders(effectivePageUri),
    );
    final iframeBody = iframeResponse?.body ?? '';
    if (iframeBody.isEmpty) {
      return null;
    }

    final prorcpPath = _firstMatch(
      iframeBody,
      <RegExp>[
        RegExp(r"""src:\s*['"](/prorcp/.*?)['"]"""),
      ],
    );
    if (prorcpPath == null) {
      return null;
    }

    final prorcpUri = _absoluteUri(iframeUri, prorcpPath);
    if (prorcpUri == null) {
      return null;
    }

    final scriptResponse = await _safeGet(
      prorcpUri,
      headers: _navigationHeaders(iframeUri),
    );
    final script = scriptResponse?.body ?? '';
    if (script.isEmpty) {
      return null;
    }

    String? rawFile = _firstMatch(
      script,
      <RegExp>[
        RegExp(
          r'''Playerjs.*file:\s*"([^"]*?)"\s*,''',
          dotAll: true,
        ),
      ],
    );

    if (rawFile == null) {
      final playerId = _firstMatch(
        script,
        <RegExp>[
          RegExp(
            r'Playerjs.*file:\s*([a-zA-Z0-9]*?)\s*,',
            dotAll: true,
          ),
        ],
      );
      if (playerId == null) {
        return null;
      }

      final encryptedSource = _firstMatch(
        script,
        <RegExp>[
          RegExp(
            '<div id="$playerId" style="display:none;">\\s*(.*?)\\s*</div>',
            dotAll: true,
          ),
        ],
      );
      if (encryptedSource == null) {
        return null;
      }

      rawFile = _decryptVidsrcNetSource(playerId, encryptedSource);
    }

    if (rawFile == null || rawFile.isEmpty) {
      return null;
    }

    final streamUrl = _selectVidsrcFamilyStreamUrl(rawFile);
    if (streamUrl == null) {
      return null;
    }

    return PlaybackTarget(
      uri: Uri.parse(streamUrl),
      providerKey: provider.key,
      providerLabel: provider.label,
      providerIndex: provider.canonicalIndex,
      sourceKind: _inferSourceKind(streamUrl),
      httpHeaders: _playbackHeaders(iframeUri),
      pageUri: effectivePageUri,
    );
  }

  Future<MediaSummary?> _loadSummary({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) async {
    final service = mediaCatalogService;
    if (service == null) {
      return null;
    }

    try {
      return await service.fetchTitleDetails(
        tmdbId: tmdbId,
        mediaType: mediaType,
        languageCode: languageCode,
      );
    } catch (_) {
      return null;
    }
  }

  Iterable<Uri> _videasyCandidateUris({
    required int tmdbId,
    required MediaType mediaType,
    required MediaSummary summary,
    required String languageCode,
    required int? seasonNumber,
    required int? episodeNumber,
  }) sync* {
    final normalizedLanguage = languageCode.trim().toLowerCase();
    final releaseYear = summary.releaseDate?.year.toString() ?? '';

    if (normalizedLanguage.isEmpty || normalizedLanguage == 'en') {
      const configs = <Map<String, Object?>>[
        <String, Object?>{'endpoint': 'myflixerzupcloud'},
        <String, Object?>{'endpoint': 'cdn', 'movieOnly': true},
        <String, Object?>{'endpoint': 'moviebox'},
        <String, Object?>{'endpoint': '1movies'},
        <String, Object?>{'endpoint': 'primesrcme'},
        <String, Object?>{'endpoint': 'primewire'},
        <String, Object?>{'endpoint': 'm4uhd'},
        <String, Object?>{'endpoint': 'hdmovie'},
      ];
      for (final config in configs) {
        if (config['movieOnly'] == true && mediaType != MediaType.movie) {
          continue;
        }
        yield _buildVideasyApiUri(
          endpoint: config['endpoint']! as String,
          title: summary.title,
          mediaType: mediaType,
          tmdbId: tmdbId,
          releaseYear: releaseYear,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
        );
      }
      return;
    }

    final endpoint = switch (normalizedLanguage) {
      'de' => 'meine',
      'it' => 'meine',
      'fr' when mediaType == MediaType.movie => 'meine',
      'es' => 'cuevana-spanish',
      _ => null,
    };
    final remoteLanguage = switch (normalizedLanguage) {
      'de' => 'german',
      'it' => 'italian',
      'fr' => 'french',
      'es' => 'spanish',
      _ => null,
    };
    if (endpoint == null || remoteLanguage == null) {
      return;
    }

    yield _buildVideasyApiUri(
      endpoint: endpoint,
      title: summary.title,
      mediaType: mediaType,
      tmdbId: tmdbId,
      releaseYear: releaseYear,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      language: remoteLanguage,
    );
  }

  Uri _buildVideasyApiUri({
    required String endpoint,
    required String title,
    required MediaType mediaType,
    required int tmdbId,
    required String releaseYear,
    required int? seasonNumber,
    required int? episodeNumber,
    String? language,
  }) {
    return Uri.https(
      'api.videasy.net',
      '/$endpoint/sources-with-title',
      <String, String>{
        'title': title,
        'mediaType': mediaType.name,
        'year': releaseYear,
        'tmdbId': '$tmdbId',
        'imdbId': '',
        if (language != null && language.isNotEmpty) 'language': language,
        if (mediaType == MediaType.tv && seasonNumber != null)
          'seasonId': '$seasonNumber',
        if (mediaType == MediaType.tv && episodeNumber != null)
          'episodeId': '$episodeNumber',
      },
    );
  }

  Uri _normalizedVidsrcFamilyPageUri({
    required ProviderDescriptor provider,
    required Uri originalPageUri,
    required int tmdbId,
    required MediaType mediaType,
    required int? seasonNumber,
    required int? episodeNumber,
  }) {
    if (provider.key == 'vidsrc') {
      switch (mediaType) {
        case MediaType.movie:
          return Uri.https(
            'vsembed.ru',
            '/embed/movie/$tmdbId',
            const <String, String>{
              'autoplay': '1',
              'mute': '1',
            },
          );
        case MediaType.tv:
          if (seasonNumber == null || episodeNumber == null) {
            return originalPageUri;
          }
          return Uri.https(
            'vsembed.ru',
            '/embed/tv/$tmdbId/$seasonNumber/$episodeNumber',
            const <String, String>{
              'autoplay': '1',
              'autonext': '1',
              'mute': '1',
            },
          );
      }
    }

    if (provider.key == 'embedsu') {
      return originalPageUri.replace(host: 'vsembed.ru');
    }

    return originalPageUri;
  }

  Future<BuiltInResolverResponse?> _safeGet(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    try {
      final response = await _httpClient.get(
        uri,
        headers: <String, String>{
          'User-Agent': _browserUserAgent,
          ...headers,
        },
      );
      return response.isSuccessful ? response : null;
    } catch (_) {
      return null;
    }
  }

  Future<BuiltInResolverResponse?> _safePostJson(
    Uri uri,
    Map<String, Object?> body, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    try {
      final response = await _httpClient.postJson(
        uri,
        body,
        headers: <String, String>{
          'User-Agent': _browserUserAgent,
          ...headers,
        },
      );
      return response.isSuccessful ? response : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _decodeJsonObject(Object? value) {
    if (value == null) {
      return null;
    }

    final decoded = switch (value) {
      Map<Object?, Object?>() => <String, dynamic>{
          for (final entry in value.entries) entry.key.toString(): entry.value,
        },
      String() => jsonDecode(value),
      _ => null,
    };
    if (decoded is Map) {
      return <String, dynamic>{
        for (final entry in decoded.entries) entry.key.toString(): entry.value,
      };
    }
    return null;
  }

  String? _firstVideasySourceUrl(List<dynamic> sources) {
    for (final source in sources) {
      if (source is! Map) {
        continue;
      }
      final sourceUrl = '${source['url'] ?? ''}'.trim();
      if (sourceUrl.isNotEmpty) {
        return sourceUrl;
      }
    }
    return null;
  }

  String? _firstMatch(String input, List<RegExp> patterns) {
    for (final pattern in patterns) {
      final match = pattern.firstMatch(input);
      if (match == null || match.groupCount < 1) {
        continue;
      }
      final value = match.group(1)?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  Uri? _absoluteUri(Uri baseUri, String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.startsWith('//')) {
      return Uri.tryParse('${baseUri.scheme}:$trimmed');
    }
    final absoluteUri = Uri.tryParse(trimmed);
    if (absoluteUri?.hasScheme == true) {
      return absoluteUri;
    }
    return baseUri.resolve(trimmed);
  }

  Map<String, String> _navigationHeaders(Uri refererUri) {
    return <String, String>{
      'Referer': refererUri.toString(),
      'Origin': '${refererUri.scheme}://${refererUri.host}',
    };
  }

  Map<String, String> _playbackHeaders(Uri refererUri) {
    return <String, String>{
      ..._navigationHeaders(refererUri),
      'User-Agent': _browserUserAgent,
    };
  }

  PlaybackSourceKind _inferSourceKind(String sourceUrl) {
    return sourceUrl.toLowerCase().contains('.m3u8')
        ? PlaybackSourceKind.hls
        : PlaybackSourceKind.file;
  }

  String? _selectVidsrcFamilyStreamUrl(String rawFile) {
    for (final candidate
        in rawFile.split(RegExp(r'\s+or\s+', caseSensitive: false))) {
      final normalized = _normalizeVidsrcFamilyStreamUrl(candidate);
      if (normalized != null) {
        return normalized;
      }
    }
    return null;
  }

  String? _normalizeVidsrcFamilyStreamUrl(String value) {
    final normalized = value.trim().replaceAll(
          RegExp(r'\{[a-z]\d+\}', caseSensitive: false),
          'quibblezoomfable.com',
        );
    return normalized.startsWith('http') ? normalized : null;
  }

  String? _decryptVidsrcNetSource(String id, String encrypted) {
    try {
      switch (id) {
        case 'NdonQLf1Tzyx7bMG':
          return _decryptNdonQLf1Tzyx7bMG(encrypted);
        case 'sXnL9MQIry':
          return _decryptSXnL9MQIry(encrypted);
        case 'IhWrImMIGL':
          return _decryptIhWrImMIGL(encrypted);
        case 'xTyBxQyGTA':
          return _decryptXTyBxQyGTA(encrypted);
        case 'ux8qjPHC66':
          return _decryptUx8qjPHC66(encrypted);
        case 'eSfH1IRMyL':
          return _decryptESfH1IRMyL(encrypted);
        case 'KJHidj7det':
          return _decryptKJHidj7det(encrypted);
        case 'o2VSUnjnZl':
          return _decryptO2VSUnjnZl(encrypted);
        case 'Oi3v1dAlaM':
          return _decryptOi3v1dAlaM(encrypted);
        case 'TsA2KGDGux':
          return _decryptTsA2KGDGux(encrypted);
        case 'JoAHUMCLXV':
          return _decryptJoAHUMCLXV(encrypted);
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  String _decryptNdonQLf1Tzyx7bMG(String value) {
    const chunkSize = 3;
    final chunks = <String>[];
    for (var index = 0; index < value.length; index += chunkSize) {
      final end =
          index + chunkSize > value.length ? value.length : index + chunkSize;
      chunks.add(value.substring(index, end));
    }
    return chunks.reversed.join();
  }

  String _decryptSXnL9MQIry(String value) {
    const key = 'pWB9V)[*4I`nJpp?ozyB~dbr9yt!_n4u';
    final hexBytes = <int>[];
    for (var index = 0; index < value.length; index += 2) {
      hexBytes.add(int.parse(value.substring(index, index + 2), radix: 16));
    }
    final decoded = String.fromCharCodes(hexBytes);
    final xored = String.fromCharCodes(
      decoded.codeUnits.asMap().entries.map(
            (entry) => entry.value ^ key.codeUnitAt(entry.key % key.length),
          ),
    );
    final shifted = String.fromCharCodes(
      xored.codeUnits.map((code) => code - 3),
    );
    return utf8.decode(base64Decode(shifted));
  }

  String _decryptIhWrImMIGL(String value) {
    final reversed = value.split('').reversed.join();
    final rotated = String.fromCharCodes(
      reversed.codeUnits.map((code) {
        if ((code >= 97 && code <= 109) || (code >= 65 && code <= 77)) {
          return code + 13;
        }
        if ((code >= 110 && code <= 122) || (code >= 78 && code <= 90)) {
          return code - 13;
        }
        return code;
      }),
    );
    final base64Value = rotated.split('').reversed.join();
    return utf8.decode(base64Decode(base64Value));
  }

  String _decryptXTyBxQyGTA(String value) {
    final filtered = value
        .split('')
        .reversed
        .toList()
        .asMap()
        .entries
        .where((entry) => entry.key.isEven)
        .map((entry) => entry.value)
        .join();
    return utf8.decode(base64Decode(filtered));
  }

  String _decryptUx8qjPHC66(String value) {
    const key = 'X9a(O;FMV2-7VO5x;Ao\u0005:dN1NoFs?j,';
    final reversed = value.split('').reversed.join();
    final bytes = <int>[];
    for (var index = 0; index < reversed.length; index += 2) {
      bytes.add(int.parse(reversed.substring(index, index + 2), radix: 16));
    }
    return String.fromCharCodes(
      bytes.asMap().entries.map(
            (entry) => entry.value ^ key.codeUnitAt(entry.key % key.length),
          ),
    );
  }

  String _decryptESfH1IRMyL(String value) {
    final shiftedBack = String.fromCharCodes(
      value.split('').reversed.join().codeUnits.map((code) => code - 1),
    );
    final bytes = <int>[];
    for (var index = 0; index < shiftedBack.length; index += 2) {
      bytes.add(int.parse(shiftedBack.substring(index, index + 2), radix: 16));
    }
    return String.fromCharCodes(bytes);
  }

  String _decryptKJHidj7det(String value) {
    const key = r'3SAY~#%Y(V%>5d/Yg"$G[Lh1rK4a;7ok';
    final sliced = value.substring(10, value.length - 16);
    final decoded = utf8.decode(base64Decode(sliced));
    final repeatedKey = StringBuffer();
    while (repeatedKey.length < decoded.length) {
      repeatedKey.write(key);
    }
    return String.fromCharCodes(
      decoded.codeUnits.asMap().entries.map(
            (entry) =>
                entry.value ^ repeatedKey.toString().codeUnitAt(entry.key),
          ),
    );
  }

  String _decryptO2VSUnjnZl(String value) {
    return String.fromCharCodes(
      value.codeUnits.map((code) {
        if (code >= 97 && code <= 122) {
          final shifted = code - 3;
          return shifted < 97 ? shifted + 26 : shifted;
        }
        if (code >= 65 && code <= 90) {
          final shifted = code - 3;
          return shifted < 65 ? shifted + 26 : shifted;
        }
        return code;
      }),
    );
  }

  String _decryptOi3v1dAlaM(String value) {
    final reversed = value.split('').reversed.join();
    final normalized = reversed.replaceAll('-', '+').replaceAll('_', '/');
    final decoded = utf8.decode(base64Decode(normalized));
    return String.fromCharCodes(decoded.codeUnits.map((code) => code - 5));
  }

  String _decryptTsA2KGDGux(String value) {
    final reversed = value.split('').reversed.join();
    final normalized = reversed.replaceAll('-', '+').replaceAll('_', '/');
    final decoded = utf8.decode(base64Decode(normalized));
    return String.fromCharCodes(decoded.codeUnits.map((code) => code - 7));
  }

  String _decryptJoAHUMCLXV(String value) {
    final reversed = value.split('').reversed.join();
    final normalized = reversed.replaceAll('-', '+').replaceAll('_', '/');
    final decoded = utf8.decode(base64Decode(normalized));
    return String.fromCharCodes(decoded.codeUnits.map((code) => code - 3));
  }
}

const List<_VidKingServer> _vidKingServers = <_VidKingServer>[
  _VidKingServer(name: 'Yoru', endpoint: 'cdn/sources-with-title'),
  _VidKingServer(name: 'Omen', endpoint: 'lamovie/sources-with-title'),
  _VidKingServer(name: 'Breach', endpoint: 'm4uhd/sources-with-title'),
  _VidKingServer(name: 'Neon', endpoint: 'neon2/sources-with-title'),
  _VidKingServer(
    name: 'Vyse',
    endpoint: 'hdmovie/sources-with-title',
    qualityFilter: 'English',
  ),
  _VidKingServer(name: 'Raze', endpoint: 'superflix/sources-with-title'),
];
const int _vidKingDesiredSourceCount = 1;

class _VidKingServer {
  const _VidKingServer({
    required this.name,
    required this.endpoint,
    this.qualityFilter,
  });
  final String name;
  final String endpoint;
  final String? qualityFilter;
}

const List<int> _vidKingRoundConstants = <int>[
  1116352408,
  1899447441,
  3049323471,
  3921009573,
  961987163,
  1508970993,
  2453635748,
  2870763221,
  3624381080,
  310598401,
  607225278,
  1426881987,
  1925078388,
  2162078206,
  2614888103,
  3248222580,
];
const List<int> _vidKingInitialWords = <int>[
  1732584193,
  4023233417,
  2562383102,
  271733878,
];
const int _vidKingStateSize = 61;
const int _vidKingInitRounds = 8;
const int _vidKingGoldenRatio = 2654435769;
const List<int> _vidKingPayloadPrefix = <int>[109, 118, 109, 49];

String _decodeVidKingPayload(String encoded, String seed, int mediaId) {
  final normalized = encoded
      .replaceAll('-', '+')
      .replaceAll('_', '/')
      .padRight(((encoded.length + 3) ~/ 4) * 4, '=');
  final bytes = base64Decode(normalized);
  final keyStream = _vidKingKeyStream(seed, mediaId, bytes.length);
  final decoded = List<int>.generate(
    bytes.length,
    (index) => bytes[index] ^ keyStream[index],
    growable: false,
  );
  if (decoded.length < _vidKingPayloadPrefix.length) {
    throw const FormatException('VidKing payload is too short.');
  }
  for (var index = 0; index < _vidKingPayloadPrefix.length; index++) {
    if (decoded[index] != _vidKingPayloadPrefix[index]) {
      throw const FormatException('VidKing payload seed was rejected.');
    }
  }
  return utf8.decode(decoded.sublist(_vidKingPayloadPrefix.length));
}

List<int> _vidKingKeyStream(String seed, int mediaId, int length) {
  final state = _vidKingCreateCipherState(seed, mediaId);
  final output = List<int>.filled(length, 0);
  var wordIndex = 0;
  for (var offset = 0; offset < length;) {
    final word = _vidKingNextWord(state, wordIndex++);
    output[offset++] = word & 0xff;
    if (offset < length) output[offset++] = (word >>> 8) & 0xff;
    if (offset < length) output[offset++] = (word >>> 16) & 0xff;
    if (offset < length) output[offset++] = (word >>> 24) & 0xff;
  }
  return output;
}

_VidKingCipherState _vidKingCreateCipherState(String seed, int mediaId) {
  if (_vidKingTriangularIsOdd(seed.length)) {
    return _VidKingCipherState(
      values: _vidKingPermutation(seed).map<int?>((value) => value).toList(),
      accumulator: _vidKingSeedAccumulator(seed),
    );
  }

  final values = List<int?>.filled(_vidKingStateSize, null);
  var accumulator = _vidKingMix(
    _vidKingHash(seed) ^
        _vidKingMix(_vidKingU32(mediaId ^ _vidKingGoldenRatio)),
  );
  for (var round = 0; round < _vidKingInitRounds; round++) {
    if (_vidKingTriangularIsEven(round)) {
      final index = accumulator % _vidKingStateSize;
      accumulator = _vidKingRotateLeft(
        _vidKingU32(accumulator + _vidKingGoldenRatio),
        7 + (round & 7),
      );
      values[index] = _vidKingU32(accumulator ^ _vidKingMix(accumulator));
      accumulator = _vidKingMix(accumulator + index);
    } else {
      values[round] = _vidKingRoundConstants[round & 15];
    }
  }
  return _VidKingCipherState(
    values: values,
    accumulator: _vidKingMix(accumulator ^ 2779096485),
  );
}

int _vidKingNextWord(_VidKingCipherState state, int wordIndex) {
  final index = state.accumulator % _vidKingStateSize;
  final hasValue = index < state.values.length && state.values[index] != null;
  final value = hasValue ? state.values[index]! : 0;
  final roundValue = _vidKingImul(_vidKingGoldenRatio, wordIndex + 1);
  var mixed = _vidKingNf(
    state.accumulator,
    _vidKingU32(value ^ roundValue),
    hasValue ? -1 : 0,
  );
  mixed = _vidKingU32(
    _vidKingRotateLeft(
          _vidKingU32(mixed + state.accumulator),
          index & 31,
        ) ^
        _vidKingRotateLeft(
          state.accumulator,
          _vidKingImul(index, 7) & 31,
        ),
  );
  state.accumulator = _vidKingMix(mixed + _vidKingGoldenRatio);
  state.values[index] = state.accumulator;
  return state.accumulator;
}

int _vidKingSeedAccumulator(String seed) {
  var accumulator = _vidKingInitialWords.first;
  for (var index = 0; index < seed.length; index++) {
    accumulator = _vidKingRotateLeft(
      _vidKingU32(
        accumulator ^
            _vidKingImul(
              seed.codeUnitAt(index),
              _vidKingRoundConstants[index & 15],
            ),
      ),
      5,
    );
  }
  return _vidKingMix(accumulator);
}

List<int> _vidKingPermutation(String seed) {
  final values = List<int>.generate(256, (index) => index);
  var cursor = 0;
  for (var index = 0; index < values.length; index++) {
    cursor =
        (cursor + values[index] + seed.codeUnitAt(index % seed.length)) & 0xff;
    final current = values[index];
    values[index] = values[cursor];
    values[cursor] = current;
  }
  return values;
}

int _vidKingHash(String seed) {
  var value = 2166136261;
  for (var index = 0; index < seed.length; index++) {
    value = _vidKingImul(value ^ seed.codeUnitAt(index), 16777619);
  }
  return _vidKingMix(value);
}

int _vidKingNf(int left, int right, int mask) =>
    _vidKingU32((left ^ right) | (left & right & mask));

int _vidKingMix(int value) {
  var mixed = _vidKingU32(value);
  mixed = _vidKingU32(mixed ^ (mixed >>> 16));
  mixed = _vidKingImul(mixed, 2246822507);
  mixed = _vidKingU32(mixed ^ (mixed >>> 13));
  mixed = _vidKingImul(mixed, 3266489909);
  mixed = _vidKingU32(mixed ^ (mixed >>> 16));
  return mixed;
}

int _vidKingRotateLeft(int value, int count) {
  final normalized = count & 31;
  final unsigned = _vidKingU32(value);
  if (normalized == 0) {
    return unsigned;
  }
  return _vidKingU32(
    (unsigned << normalized) | (unsigned >>> (32 - normalized)),
  );
}

int _vidKingImul(int left, int right) => _vidKingU32(left * right);
int _vidKingU32(int value) => value & 0xffffffff;
bool _vidKingTriangularIsEven(int value) => ((value * (value + 1)) & 1) == 0;
bool _vidKingTriangularIsOdd(int value) => ((value * (value + 1)) & 1) == 1;

class _VidKingCipherState {
  _VidKingCipherState({required this.values, required this.accumulator});

  final List<int?> values;
  int accumulator;
}

abstract class BuiltInResolverHttpClient {
  Future<BuiltInResolverResponse> get(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
  });

  Future<BuiltInResolverResponse> postJson(
    Uri uri,
    Map<String, Object?> body, {
    Map<String, String> headers = const <String, String>{},
  });
}

class BuiltInResolverResponse {
  const BuiltInResolverResponse({
    required this.statusCode,
    required this.body,
    this.headers = const <String, String>{},
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;

  bool get isSuccessful => statusCode >= 200 && statusCode < 300;
}

class IoBuiltInResolverHttpClient implements BuiltInResolverHttpClient {
  IoBuiltInResolverHttpClient({
    this.timeout = const Duration(seconds: 20),
    HttpClient? client,
  }) : _client = client ?? _createClient(timeout);

  final Duration timeout;
  final HttpClient _client;

  static HttpClient _createClient(Duration timeout) => HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..idleTimeout = timeout
    ..maxConnectionsPerHost = 12;

  @override
  Future<BuiltInResolverResponse> get(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    final request = await _client.getUrl(uri).timeout(timeout);
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(timeout);
    final bytes = await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    ).timeout(timeout);
    final body = utf8.decode(bytes, allowMalformed: true);
    return BuiltInResolverResponse(
      statusCode: response.statusCode,
      body: body,
      headers: _headersFromResponse(response),
    );
  }

  @override
  Future<BuiltInResolverResponse> postJson(
    Uri uri,
    Map<String, Object?> body, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    final request = await _client.postUrl(uri).timeout(timeout);
    request.headers.contentType = ContentType.json;
    headers.forEach(request.headers.set);
    request.write(jsonEncode(body));
    final response = await request.close().timeout(timeout);
    final text = await response.transform(utf8.decoder).join().timeout(timeout);
    return BuiltInResolverResponse(
      statusCode: response.statusCode,
      body: text,
      headers: _headersFromResponse(response),
    );
  }

  Map<String, String> _headersFromResponse(HttpClientResponse response) {
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      if (values.isNotEmpty) {
        headers[name] = values.join(', ');
      }
    });
    return headers;
  }
}
