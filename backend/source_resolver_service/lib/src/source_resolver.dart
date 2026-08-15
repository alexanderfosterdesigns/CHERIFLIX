import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'source_health_store.dart';
import 'source_resolver_models.dart';
import 'source_resolver_provider_catalog.dart';

typedef ProviderPlaybackTargetExtractor = Future<PlaybackTarget?> Function({
  required ProviderDescriptor provider,
  required Uri pageUri,
  required SourceResolverRequest request,
});

class ProviderPlaybackTargetExtractorRegistry {
  ProviderPlaybackTargetExtractorRegistry({
    Map<String, ProviderPlaybackTargetExtractor>? extractors,
  }) : _extractors =
            extractors ?? const <String, ProviderPlaybackTargetExtractor>{};

  final Map<String, ProviderPlaybackTargetExtractor> _extractors;

  Future<PlaybackTarget?> resolve({
    required ProviderDescriptor provider,
    required Uri pageUri,
    required SourceResolverRequest request,
  }) async {
    final extractor = _extractors[provider.key];
    if (extractor == null) {
      return null;
    }
    return extractor(
      provider: provider,
      pageUri: pageUri,
      request: request,
    );
  }
}

abstract interface class PlaybackTargetProbe {
  Future<bool> canLoad(PlaybackTarget target, Duration timeout);
}

class SourceResolver {
  SourceResolver({
    ProviderCatalog? providerCatalog,
    SourcePreferenceStore? preferenceStore,
    SourceHealthStore? sourceHealthStore,
    SourceTargetCache? targetCache,
    ProviderPlaybackTargetExtractorRegistry? targetExtractorRegistry,
    PlaybackTargetProbe? probe,
    DateTime Function()? clock,
  })  : providerCatalog = providerCatalog ?? const ProviderCatalog(),
        preferenceStore = preferenceStore ?? SourcePreferenceStore(),
        sourceHealthStore = sourceHealthStore ??
            SourceHealthStore(clock: clock ?? DateTime.now),
        targetCache =
            targetCache ?? SourceTargetCache(clock: clock ?? DateTime.now),
        targetExtractorRegistry = targetExtractorRegistry ??
            ProviderPlaybackTargetExtractorRegistry(),
        probe = probe ?? HttpPlaybackTargetProbe();

  final ProviderCatalog providerCatalog;
  final SourcePreferenceStore preferenceStore;
  final SourceHealthStore sourceHealthStore;
  final SourceTargetCache targetCache;
  final ProviderPlaybackTargetExtractorRegistry targetExtractorRegistry;
  final PlaybackTargetProbe probe;

  Future<PlaybackTarget?> resolveTitle(SourceResolverRequest request) async {
    if (!_isValidRequest(request)) {
      return null;
    }

    final cachedTarget = targetCache.read(
      key: request.key,
      providerConfig: request.providerConfig,
      settings: request.settings,
    );
    if (cachedTarget != null && _isCachedTargetHealthy(request, cachedTarget)) {
      return cachedTarget;
    }

    return _resolve(
      request,
      startAfterCanonicalIndex: null,
      probeCandidates: true,
    );
  }

  Future<PlaybackTarget?> resolveNextSource(
      SourceResolverRequest request) async {
    if (!_isValidRequest(request) || request.currentProviderIndex == null) {
      return null;
    }

    return _resolve(
      request,
      startAfterCanonicalIndex: request.currentProviderIndex,
      probeCandidates: request.probeCandidates,
    );
  }

  Future<PlaybackTarget?> resolveSpecificSource(
    SourceResolverRequest request,
  ) async {
    if (!_isValidRequest(request) || request.providerIndex == null) {
      return null;
    }

    final providers = providerCatalog.orderedProviders(request.providerConfig);
    final provider = _findProviderByIndex(
      providers,
      request.providerIndex!,
    );
    if (provider == null) {
      return null;
    }

    return _buildTargetForProvider(
      provider: provider,
      request: request,
      probeCandidate: request.probeCandidate,
    );
  }

  Future<void> reportSourceSuccess(SourceResolverRequest request) async {
    if (!_isValidRequest(request) || request.providerIndex == null) {
      return;
    }

    sourceHealthStore.recordSuccess(
      key: request.key,
      providerIndex: request.providerIndex!,
    );
    preferenceStore.saveLastGoodProviderIndex(
      key: request.key,
      providerIndex: request.providerIndex!,
    );
  }

  Future<void> reportSourceFailure(SourceResolverRequest request) async {
    if (!_isValidRequest(request) || request.providerIndex == null) {
      return;
    }

    sourceHealthStore.recordFailure(
      key: request.key,
      providerIndex: request.providerIndex!,
      kind: request.kind,
    );
    targetCache.invalidate(
      key: request.key,
      providerConfig: request.providerConfig,
      settings: request.settings,
      providerIndex: request.providerIndex!,
    );
  }

  Future<Duration?> estimateNextSourceRetryDelay(
    SourceResolverRequest request,
  ) async {
    if (!_isValidRequest(request)) {
      return null;
    }

    final providers = providerCatalog.orderedProviders(request.providerConfig);
    if (providers.isEmpty) {
      return null;
    }

    Duration? shortestCooldown;
    var hasEligibleProvider = false;

    for (final provider in providers) {
      final remaining = sourceHealthStore.cooldownRemaining(
        key: request.key,
        providerIndex: provider.canonicalIndex,
      );
      if (remaining == null) {
        hasEligibleProvider = true;
        break;
      }

      if (shortestCooldown == null || remaining < shortestCooldown) {
        shortestCooldown = remaining;
      }
    }

    return hasEligibleProvider ? null : shortestCooldown;
  }

  Future<PlaybackTarget?> _resolve(
    SourceResolverRequest request, {
    required int? startAfterCanonicalIndex,
    required bool probeCandidates,
  }) async {
    final providers = providerCatalog.orderedProviders(request.providerConfig);
    if (providers.isEmpty) {
      return null;
    }

    final savedCanonicalIndex = startAfterCanonicalIndex ??
        preferenceStore.getLastGoodProviderIndex(request.key);
    final orderedAttempts = _rotateProviders(
      providers,
      savedCanonicalIndex,
      skipMatchingCanonicalIndex: startAfterCanonicalIndex,
    );

    final eligibleAttempts = orderedAttempts.where((provider) {
      return sourceHealthStore.cooldownRemaining(
            key: request.key,
            providerIndex: provider.canonicalIndex,
          ) ==
          null;
    }).toList(growable: false);

    if (eligibleAttempts.isEmpty) {
      return null;
    }

    for (final provider in eligibleAttempts) {
      final target = await _buildTargetForProvider(
        provider: provider,
        request: request,
        probeCandidate: probeCandidates,
      );
      if (target == null) {
        continue;
      }
      return target;
    }

    return null;
  }

  Future<PlaybackTarget?> _buildTargetForProvider({
    required ProviderDescriptor provider,
    required SourceResolverRequest request,
    required bool probeCandidate,
  }) async {
    final pageUri = ProviderCatalog.buildUri(
      provider: provider,
      tmdbId: request.tmdbId,
      mediaType: request.mediaType,
      settings: request.settings,
      seasonNumber: request.seasonNumber,
      episodeNumber: request.episodeNumber,
    );
    if (pageUri == null) {
      return null;
    }

    final extractedTarget = await targetExtractorRegistry.resolve(
      provider: provider,
      pageUri: pageUri,
      request: request,
    );
    if (extractedTarget == null || !extractedTarget.isDirectPlayable) {
      return null;
    }

    final target = PlaybackTarget(
      uri: extractedTarget.uri,
      providerKey: provider.key,
      providerLabel: provider.label,
      providerIndex: provider.canonicalIndex,
      sourceKind: extractedTarget.sourceKind,
      httpHeaders: extractedTarget.httpHeaders,
      pageUri: extractedTarget.pageUri ?? pageUri,
      expiresAtEpochMs: extractedTarget.expiresAtEpochMs,
    );

    if (probeCandidate) {
      final success = await _probeCandidate(
        provider: provider,
        target: target,
        providerTimeoutSeconds: request.providerConfig.providerTimeoutSeconds,
      );
      if (!success) {
        sourceHealthStore.recordFailure(
          key: request.key,
          providerIndex: provider.canonicalIndex,
          kind: SourceFailureKind.probe,
        );
        targetCache.invalidate(
          key: request.key,
          providerConfig: request.providerConfig,
          settings: request.settings,
          providerIndex: provider.canonicalIndex,
        );
        return null;
      }
    }

    targetCache.remember(
      key: request.key,
      providerConfig: request.providerConfig,
      settings: request.settings,
      target: target,
    );
    return target;
  }

  Future<bool> _probeCandidate({
    required ProviderDescriptor provider,
    required PlaybackTarget target,
    required int providerTimeoutSeconds,
  }) async {
    final attempts = provider.probeAttempts <= 0 ? 1 : provider.probeAttempts;
    final timeoutSeconds =
        provider.probeTimeoutSeconds ?? providerTimeoutSeconds;
    final timeout = Duration(seconds: timeoutSeconds);

    for (var attempt = 0; attempt < attempts; attempt++) {
      final success = await probe.canLoad(target, timeout);
      if (success) {
        return true;
      }

      if (attempt + 1 < attempts) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }

    return false;
  }

  bool _isCachedTargetHealthy(
    SourceResolverRequest request,
    PlaybackTarget target,
  ) {
    if (!target.isDirectPlayable) {
      return false;
    }

    final provider = _findProviderByIndex(
      providerCatalog.orderedProviders(request.providerConfig),
      target.providerIndex,
    );
    if (provider == null) {
      return false;
    }

    return sourceHealthStore.cooldownRemaining(
          key: request.key,
          providerIndex: target.providerIndex,
        ) ==
        null;
  }

  bool _isValidRequest(SourceResolverRequest request) {
    return request.profileId.trim().isNotEmpty &&
        request.tmdbId > 0 &&
        (request.mediaType == 'movie' || request.mediaType == 'tv');
  }

  ProviderDescriptor? _findProviderByIndex(
    List<ProviderDescriptor> providers,
    int providerIndex,
  ) {
    for (final provider in providers) {
      if (provider.canonicalIndex == providerIndex) {
        return provider;
      }
    }
    return null;
  }

  List<ProviderDescriptor> _rotateProviders(
    List<ProviderDescriptor> providers,
    int? preferredCanonicalIndex, {
    int? skipMatchingCanonicalIndex,
  }) {
    if (providers.isEmpty) {
      return providers;
    }

    final preferredIndex = preferredCanonicalIndex == null
        ? 0
        : providers.indexWhere(
            (provider) => provider.canonicalIndex == preferredCanonicalIndex,
          );

    final startIndex = preferredIndex < 0 ? 0 : preferredIndex;
    final rotated = <ProviderDescriptor>[
      ...providers.sublist(startIndex),
      ...providers.sublist(0, startIndex),
    ];

    if (skipMatchingCanonicalIndex == null) {
      return rotated;
    }

    return rotated
        .where(
          (provider) => provider.canonicalIndex != skipMatchingCanonicalIndex,
        )
        .toList(growable: false);
  }
}

class HttpPlaybackTargetProbe implements PlaybackTargetProbe {
  HttpPlaybackTargetProbe({HttpClient? client})
      : _client = client ?? HttpClient();

  final HttpClient _client;
  static const String _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36 Edg/133.0.0.0';

  @override
  Future<bool> canLoad(PlaybackTarget target, Duration timeout) async {
    try {
      final request = await _client.getUrl(target.uri).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, _browserUserAgent);
      request.headers.set(
        HttpHeaders.acceptHeader,
        target.sourceKind == PlaybackSourceKind.hls
            ? 'application/vnd.apple.mpegurl, application/x-mpegURL, */*'
            : '*/*',
      );
      for (final entry in target.httpHeaders.entries) {
        request.headers.set(entry.key, entry.value);
      }
      final response = await request.close().timeout(timeout);
      final contentType = (response.headers.contentType?.mimeType ??
              response.headers.value(HttpHeaders.contentTypeHeader) ??
              '')
          .toLowerCase();
      if (target.sourceKind == PlaybackSourceKind.file) {
        final accepted = isLikelyWorkingPlaybackResponse(
          statusCode: response.statusCode,
          sourceKind: target.sourceKind,
          contentType: contentType,
          body: '',
          contentLength: response.contentLength,
        );
        await response.drain<void>().timeout(timeout);
        return accepted;
      }

      final body =
          await response.transform(utf8.decoder).join().timeout(timeout);
      return isLikelyWorkingPlaybackResponse(
        statusCode: response.statusCode,
        sourceKind: target.sourceKind,
        contentType: contentType,
        body: body,
        contentLength: response.contentLength,
      );
    } on TimeoutException {
      return false;
    } on SocketException {
      return false;
    } on HandshakeException {
      return false;
    } on HttpException {
      return false;
    }
  }
}

bool isLikelyWorkingPlaybackResponse({
  required int statusCode,
  required PlaybackSourceKind sourceKind,
  required String contentType,
  required String body,
  required int contentLength,
}) {
  final isOkStatus = statusCode >= 200 && statusCode < 400;
  if (!isOkStatus) {
    return false;
  }

  return switch (sourceKind) {
    PlaybackSourceKind.hls =>
      contentType.contains('mpegurl') || body.trimLeft().startsWith('#EXTM3U'),
    PlaybackSourceKind.file => contentType.startsWith('video/') ||
        contentType.startsWith('audio/') ||
        contentType.contains('octet-stream') ||
        contentLength > 0,
  };
}
