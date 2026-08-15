import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/media_type.dart';
import '../models/playback_target.dart';
import '../models/profile_playback_settings.dart';
import '../models/provider_config.dart';
import 'playback_provider.dart';
import 'direct_source_validator.dart';
import 'media_catalog_service.dart';
import 'offline_media_library.dart';
import 'playback_diagnostics.dart';
import 'profile_repository.dart';
import 'provider_catalog.dart';
import 'provider_preference_store.dart';
import 'source_health_store.dart';
import 'source_resolver_service.dart';
import '../utils/safe_logging.dart';

class EmbedPlaybackProvider implements PlaybackProvider {
  static Duration get _sourceResolutionTimeout => Platform.isAndroid
      ? const Duration(seconds: 20)
      : const Duration(seconds: 12);
  static Duration get _vidKingSourceResolutionTimeout => Platform.isAndroid
      ? const Duration(seconds: 12)
      : const Duration(seconds: 6);

  EmbedPlaybackProvider({
    required this.providerCatalog,
    required this.preferenceStore,
    required this.profileSettingsStore,
    required this.providerConfig,
    required this.probe,
    this.mediaCatalogService,
    this.sourceResolverService = const NoOpSourceResolverService(),
    this.allowEmbedFallback = true,
    this.offlineMediaLibrary,
    DirectSourceValidator? directSourceValidator,
    SourceHealthStore? sourceHealthStore,
    DateTime Function()? clock,
    bool? raceInitialSources,
  })  : directSourceValidator =
            directSourceValidator ?? HttpDirectSourceValidator(),
        raceInitialSources = raceInitialSources ?? Platform.isAndroid,
        sourceHealthStore = sourceHealthStore ??
            SourceHealthStore(clock: clock ?? DateTime.now);

  final ProviderCatalog providerCatalog;
  final ProviderPreferenceStore preferenceStore;
  final ProfileSettingsStore profileSettingsStore;
  final ProviderConfig providerConfig;
  final EmbedProbe probe;
  final MediaCatalogService? mediaCatalogService;
  final SourceResolverService sourceResolverService;
  final bool allowEmbedFallback;
  final OfflineMediaLibrary? offlineMediaLibrary;
  final DirectSourceValidator directSourceValidator;
  final SourceHealthStore sourceHealthStore;
  final bool raceInitialSources;
  _ConcurrentResolutionSession? _activeResolutionSession;
  int _resolutionGeneration = 0;
  final Map<String, String> _pendingDiagnosticSessions = <String, String>{};

  void beginPlaybackAttempt({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    int? seasonNumber,
    int? episodeNumber,
  }) {
    final key = _resolutionContentKey(
      profileId: profileId,
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
    _pendingDiagnosticSessions[key] = PlaybackDiagnostics.instance.startSession(
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
    if (_pendingDiagnosticSessions.length > 4) {
      _pendingDiagnosticSessions.remove(_pendingDiagnosticSessions.keys.first);
    }
  }

  List<ProviderDescriptor> listEnabledProviders() {
    return providerCatalog.orderedProviders(providerConfig);
  }

  @override
  Future<PlaybackTarget?> resolveTitle({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    return resolveTitleWithLanguage(
      profileId: profileId,
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
  }

  Future<PlaybackTarget?> resolveTitleWithLanguage({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    int? seasonNumber,
    int? episodeNumber,
    String? preferredAudioLanguage,
  }) async {
    final contentKey = _resolutionContentKey(
      profileId: profileId,
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
    final offlineTarget = await offlineMediaLibrary?.findCompletedTarget(
      OfflineMediaKey(
        tmdbId: tmdbId,
        mediaType: mediaType,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      ),
    );
    if (offlineTarget != null) {
      final diagnosticSessionId =
          _pendingDiagnosticSessions.remove(contentKey) ??
              PlaybackDiagnostics.instance.startSession(
                tmdbId: tmdbId,
                mediaType: mediaType,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
              );
      PlaybackDiagnostics.instance.record(
        sessionId: diagnosticSessionId,
        stage: PlaybackDiagnosticStage.resolutionStarted,
        outcome: 'offline-local-first',
      );
      PlaybackDiagnostics.instance.record(
        sessionId: diagnosticSessionId,
        stage: PlaybackDiagnosticStage.firstValidSource,
        providerKey: offlineTarget.providerKey,
        outcome: 'offline-local',
      );
      PlaybackDiagnostics.instance.record(
        sessionId: diagnosticSessionId,
        stage: PlaybackDiagnosticStage.manifestReady,
        providerKey: offlineTarget.providerKey,
        outcome: 'offline-verified',
      );
      return PlaybackTarget(
        uri: offlineTarget.uri,
        providerKey: offlineTarget.providerKey,
        providerLabel: offlineTarget.providerLabel,
        providerIndex: offlineTarget.providerIndex,
        sourceKind: offlineTarget.sourceKind,
        httpHeaders: offlineTarget.httpHeaders,
        pageUri: offlineTarget.pageUri,
        expiresAtEpochMs: offlineTarget.expiresAtEpochMs,
        fallbackUris: offlineTarget.fallbackUris,
        diagnosticSessionId: diagnosticSessionId,
        offlineStorageAllowed: offlineTarget.offlineStorageAllowed,
        qualityLabel: offlineTarget.qualityLabel,
        bitrateBitsPerSecond: offlineTarget.bitrateBitsPerSecond,
      );
    }
    return _resolve(
      profileId: profileId,
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      startAfterCanonicalIndex: null,
      preferredAudioLanguage: preferredAudioLanguage,
    );
  }

  /// Resolves through the same validated provider race as playback, but keeps
  /// advancing past controlled embed candidates because offline packaging
  /// requires an actual media stream.
  Future<PlaybackTarget?> resolveDownloadTarget({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    int? seasonNumber,
    int? episodeNumber,
    String? preferredAudioLanguage,
  }) async {
    var target = await resolveTitleWithLanguage(
      profileId: profileId,
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      preferredAudioLanguage: preferredAudioLanguage,
    );
    final visited = <int>{};
    final providerCount = listEnabledProviders().length;
    while (target != null &&
        !target.isDirectPlayable &&
        visited.length < providerCount) {
      if (!visited.add(target.providerIndex)) break;
      target = await resolveNextSource(
        profileId: profileId,
        tmdbId: tmdbId,
        mediaType: mediaType,
        currentProviderIndex: target.providerIndex,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        preferredAudioLanguage: preferredAudioLanguage,
        probeCandidates: true,
      );
    }
    return target?.isDirectPlayable == true ? target : null;
  }

  Future<PlaybackTarget?> resolveNextSource({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int currentProviderIndex,
    int? seasonNumber,
    int? episodeNumber,
    bool probeCandidates = true,
    String? preferredAudioLanguage,
  }) async {
    return _resolve(
      profileId: profileId,
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      startAfterCanonicalIndex: currentProviderIndex,
      probeCandidates: probeCandidates,
      preferredAudioLanguage: preferredAudioLanguage,
    );
  }

  Future<PlaybackTarget?> resolveSpecificSource({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
    int? seasonNumber,
    int? episodeNumber,
    bool probeCandidate = false,
    String? preferredAudioLanguage,
  }) async {
    var profileSettings =
        await profileSettingsStore.loadPlaybackSettings(profileId);
    final normalizedAudioLanguage = preferredAudioLanguage?.trim();
    if (normalizedAudioLanguage?.isNotEmpty == true) {
      profileSettings = profileSettings.copyWith(
        preferredAudioLanguageCode: normalizedAudioLanguage,
      );
    }
    final provider = listEnabledProviders().firstWhere(
      (candidate) => candidate.canonicalIndex == providerIndex,
      orElse: () => throw StateError('Unknown provider index: $providerIndex'),
    );
    return _buildTargetForProvider(
      provider: provider,
      profileId: profileId,
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      settings: profileSettings,
      probeCandidate: probeCandidate,
      validateDirectCandidate: raceInitialSources,
    );
  }

  Future<PlaybackTarget?> _resolve({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int? seasonNumber,
    required int? episodeNumber,
    required int? startAfterCanonicalIndex,
    ProfilePlaybackSettings? settings,
    bool probeCandidates = true,
    String? preferredAudioLanguage,
  }) async {
    final providers = providerCatalog.orderedProviders(providerConfig);
    if (providers.isEmpty) {
      return null;
    }

    var profileSettings =
        settings ?? await profileSettingsStore.loadPlaybackSettings(profileId);
    final normalizedAudioLanguage = preferredAudioLanguage?.trim();
    if (normalizedAudioLanguage?.isNotEmpty == true) {
      profileSettings = profileSettings.copyWith(
        preferredAudioLanguageCode: normalizedAudioLanguage,
      );
    }
    final savedCanonicalIndex = startAfterCanonicalIndex ??
        await preferenceStore.getLastGoodProviderIndex(
          profileId: profileId,
          tmdbId: tmdbId,
          mediaType: mediaType,
        );

    final orderedAttempts = _prioritizeProvidersForAudioLanguage(
      _rotateProviders(
        providers,
        savedCanonicalIndex,
        skipMatchingCanonicalIndex: startAfterCanonicalIndex,
      ),
      profileSettings.preferredAudioLanguageCode,
    );

    final eligibleAttempts = orderedAttempts.where((provider) {
      return sourceHealthStore.cooldownRemaining(
            profileId: profileId,
            tmdbId: tmdbId,
            mediaType: mediaType,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            providerIndex: provider.canonicalIndex,
          ) ==
          null;
    }).toList(growable: false);

    final attempts = _rankProviders(
      eligibleAttempts.isNotEmpty ? eligibleAttempts : orderedAttempts,
      mediaType: mediaType,
      preferredCanonicalIndex:
          profileSettings.preferredAudioLanguageCode.toLowerCase() == 'en'
              ? savedCanonicalIndex
              : null,
    );
    if (attempts.isEmpty) {
      return null;
    }

    if (raceInitialSources && allowEmbedFallback) {
      final contentKey = _resolutionContentKey(
        profileId: profileId,
        tmdbId: tmdbId,
        mediaType: mediaType,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      );
      var session = _activeResolutionSession;
      if (startAfterCanonicalIndex == null ||
          session == null ||
          session.contentKey != contentKey ||
          session.isCancelled) {
        session?.cancel();
        final diagnosticSessionId =
            _pendingDiagnosticSessions.remove(contentKey) ??
                PlaybackDiagnostics.instance.startSession(
                  tmdbId: tmdbId,
                  mediaType: mediaType,
                  seasonNumber: seasonNumber,
                  episodeNumber: episodeNumber,
                );
        PlaybackDiagnostics.instance.record(
          sessionId: diagnosticSessionId,
          stage: PlaybackDiagnosticStage.resolutionStarted,
          details: <String, Object?>{'providerCount': attempts.length},
        );
        session = _ConcurrentResolutionSession(
          contentKey: contentKey,
          mediaType: mediaType,
          generation: ++_resolutionGeneration,
          diagnosticSessionId: diagnosticSessionId,
          attempts: attempts,
          // Keep both fast direct providers in the first wave without letting
          // several unrelated embed probes compete with HLS startup for the
          // Android TV network connection pool.
          maxConcurrent: Platform.isAndroid ? 4 : 8,
          resolveCandidate: (provider) => _buildTargetForProvider(
            provider: provider,
            profileId: profileId,
            tmdbId: tmdbId,
            mediaType: mediaType,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            settings: profileSettings,
            probeCandidate: true,
            requireSuccessfulEmbedProbe: true,
            validateDirectCandidate: true,
          ),
          sourceHealthStore: sourceHealthStore,
        )..start();
        _activeResolutionSession = session;
      }
      if (startAfterCanonicalIndex != null) {
        session.excludeProvider(startAfterCanonicalIndex);
      }
      final target = await session.nextTarget(
        preferDirectGrace: startAfterCanonicalIndex == null,
      );
      if (identical(_activeResolutionSession, session) && target != null) {
        return _withDiagnosticSession(target, session.diagnosticSessionId);
      }
      if (identical(_activeResolutionSession, session) && session.isExhausted) {
        PlaybackDiagnostics.instance.record(
          sessionId: session.diagnosticSessionId,
          stage: PlaybackDiagnosticStage.exhausted,
          outcome: 'all-providers-exhausted',
          details: <String, Object?>{
            'providerStates': session.providerStateSummary,
          },
        );
        PlaybackDiagnostics.instance.finishSession(session.diagnosticSessionId);
        return null;
      }
      // A newer title/episode invalidated this request while providers were
      // still resolving. Never let its stale result fall through into a new
      // sequential resolution pass.
      if (!identical(_activeResolutionSession, session) ||
          session.isCancelled) {
        return null;
      }
    }

    for (final provider in attempts) {
      final target = await _buildTargetForProvider(
        provider: provider,
        profileId: profileId,
        tmdbId: tmdbId,
        mediaType: mediaType,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        settings: profileSettings,
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
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int? seasonNumber,
    required int? episodeNumber,
    required ProfilePlaybackSettings settings,
    required bool probeCandidate,
    bool requireSuccessfulEmbedProbe = false,
    bool validateDirectCandidate = false,
  }) async {
    final providerWatch = Stopwatch()..start();
    void trace(String outcome, [Map<String, Object?> details = const {}]) {
      cheriflixLog(
        'playback-provider',
        jsonEncode(<String, Object?>{
          'provider': provider.key,
          'outcome': outcome,
          'elapsedMs': providerWatch.elapsedMilliseconds,
          ...details,
        }),
      );
    }

    trace('resolver-started');
    try {
      final target = await sourceResolverService
          .resolveSpecificSource(
            profileId: profileId,
            tmdbId: tmdbId,
            mediaType: mediaType,
            providerConfig: providerConfig,
            settings: settings,
            providerIndex: provider.canonicalIndex,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            probeCandidate: probeCandidate,
          )
          .timeout(
            provider.key == 'vidking'
                ? _vidKingSourceResolutionTimeout
                : _sourceResolutionTimeout,
          );
      if (target != null && target.isDirectPlayable) {
        trace('resolver-direct', <String, Object?>{
          'host': target.uri.host,
          'kind': target.sourceKind.name,
          'headerNames': target.httpHeaders.keys.toList(growable: false),
          if (target.pageUri != null) 'pageHost': target.pageUri!.host,
        });
        if (validateDirectCandidate) {
          final validation = await directSourceValidator.validate(target);
          trace('direct-validation', <String, Object?>{
            'playable': validation.playable,
            'stage': validation.stage,
            if (validation.statusCode != null) 'status': validation.statusCode,
            if (validation.reason != null) 'reason': validation.reason,
          });
          if (!validation.playable) {
            sourceHealthStore.recordFailure(
              profileId: profileId,
              tmdbId: tmdbId,
              mediaType: mediaType,
              seasonNumber: seasonNumber,
              episodeNumber: episodeNumber,
              providerIndex: provider.canonicalIndex,
              kind: SourceFailureKind.validation,
            );
            return null;
          }
        }
        return _withOfflineDownloadCapability(target);
      }
      if (target != null && allowEmbedFallback) {
        trace('resolver-embed', <String, Object?>{
          'host': target.uri.host,
        });
        if (!requireSuccessfulEmbedProbe) {
          return target;
        }
        final embedUri = target.pageUri ?? target.uri;
        if (await _probeCandidate(provider: provider, uri: embedUri)) {
          trace('embed-probe-accepted', <String, Object?>{
            'host': embedUri.host,
          });
          return target;
        }
        trace('embed-probe-rejected', <String, Object?>{
          'host': embedUri.host,
        });
        sourceHealthStore.recordFailure(
          profileId: profileId,
          tmdbId: tmdbId,
          mediaType: mediaType,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
          providerIndex: provider.canonicalIndex,
          kind: SourceFailureKind.probe,
        );
        return null;
      }
    } catch (error) {
      trace('resolver-error', <String, Object?>{
        'errorType': error.runtimeType.toString(),
      });
      if (!allowEmbedFallback) {
        return null;
      }
      // Fall back to the provider page target when explicitly allowed.
    }

    if (!allowEmbedFallback) {
      return null;
    }

    // VidKing is resolved natively. Its encrypted source flow is not a reliable
    // hidden-WebView fallback on Android TV, so continue to the next provider.
    if (provider.key == 'vidking') {
      trace('native-only-unavailable');
      return null;
    }

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

    if (probeCandidate) {
      if (requireSuccessfulEmbedProbe) {
        final success = await _probeCandidate(provider: provider, uri: pageUri);
        if (!success) {
          trace('fallback-embed-probe-rejected', <String, Object?>{
            'host': pageUri.host,
          });
          sourceHealthStore.recordFailure(
            profileId: profileId,
            tmdbId: tmdbId,
            mediaType: mediaType,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            providerIndex: provider.canonicalIndex,
            kind: SourceFailureKind.probe,
          );
          return null;
        }
        trace('fallback-embed-probe-accepted', <String, Object?>{
          'host': pageUri.host,
        });
      } else {
        // A probe failure never prevented this page target from being returned,
        // so do it in the background instead of blocking first playback.
        unawaited(
          _ignoreSourceResolverErrors(() async {
            final success = await _probeCandidate(
              provider: provider,
              uri: pageUri,
            );
            if (!success) {
              sourceHealthStore.recordFailure(
                profileId: profileId,
                tmdbId: tmdbId,
                mediaType: mediaType,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                providerIndex: provider.canonicalIndex,
                kind: SourceFailureKind.probe,
              );
            }
          }),
        );
      }
    }

    return PlaybackTarget(
      uri: pageUri,
      providerKey: provider.key,
      providerLabel: provider.label,
      providerIndex: provider.canonicalIndex,
      sourceKind: PlaybackSourceKind.embed,
      pageUri: pageUri,
    );
  }

  Future<bool> _probeCandidate({
    required ProviderDescriptor provider,
    required Uri uri,
  }) async {
    final attempts = provider.probeAttempts <= 0 ? 1 : provider.probeAttempts;
    final timeoutSeconds =
        provider.probeTimeoutSeconds ?? providerConfig.providerTimeoutSeconds;
    final timeout = Duration(seconds: timeoutSeconds);

    for (var attempt = 0; attempt < attempts; attempt += 1) {
      final success = await probe.canLoad(uri, timeout);
      if (success) {
        return true;
      }
      if (attempt + 1 < attempts) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }

    return false;
  }

  Future<void> recordSourceSuccess({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
    int? seasonNumber,
    int? episodeNumber,
    Duration? startupDuration,
  }) async {
    final contentKey = _resolutionContentKey(
      profileId: profileId,
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
    final session = _activeResolutionSession;
    if (session?.contentKey == contentKey) {
      session!.markPlaying(providerIndex);
    }
    sourceHealthStore.recordSuccess(
      profileId: profileId,
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      providerIndex: providerIndex,
      startupDuration: startupDuration,
    );

    await preferenceStore.saveLastGoodProviderIndex(
      profileId: profileId,
      tmdbId: tmdbId,
      mediaType: mediaType,
      providerIndex: providerIndex,
    );

    unawaited(
      _ignoreSourceResolverErrors(
        () => sourceResolverService.reportSourceSuccess(
          profileId: profileId,
          tmdbId: tmdbId,
          mediaType: mediaType,
          providerIndex: providerIndex,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
        ),
      ),
    );
  }

  void recordSourceFailure({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
    required SourceFailureKind kind,
    int? seasonNumber,
    int? episodeNumber,
  }) {
    final contentKey = _resolutionContentKey(
      profileId: profileId,
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
    final session = _activeResolutionSession;
    if (session?.contentKey == contentKey) {
      session!.markFailed(providerIndex, kind);
    }
    sourceHealthStore.recordFailure(
      profileId: profileId,
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      providerIndex: providerIndex,
      kind: kind,
    );

    unawaited(
      _ignoreSourceResolverErrors(
        () => sourceResolverService.reportSourceFailure(
          profileId: profileId,
          tmdbId: tmdbId,
          mediaType: mediaType,
          providerIndex: providerIndex,
          kind: kind,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
        ),
      ),
    );
  }

  Future<Duration?> estimateNextSourceRetryDelay({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    final providers = providerCatalog.orderedProviders(providerConfig);
    if (providers.isEmpty) {
      return null;
    }

    Duration? shortestCooldown;
    var hasEligibleProvider = false;

    for (final provider in providers) {
      final remaining = sourceHealthStore.cooldownRemaining(
        profileId: profileId,
        tmdbId: tmdbId,
        mediaType: mediaType,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
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
            (provider) => provider.canonicalIndex == preferredCanonicalIndex);

    final startIndex = preferredIndex < 0 ? 0 : preferredIndex;
    final rotated = <ProviderDescriptor>[
      ...providers.sublist(startIndex),
      ...providers.sublist(0, startIndex),
    ];
    final preferredProvider =
        preferredIndex < 0 ? null : providers[preferredIndex];
    final keepDirectFallbackAdjacent = preferredProvider?.key == 'vidking' ||
        preferredProvider?.key == 'vixsrc';
    final ordered = keepDirectFallbackAdjacent
        ? <ProviderDescriptor>[
            preferredProvider!,
            ...providers.where(
              (provider) =>
                  provider.canonicalIndex != preferredProvider.canonicalIndex &&
                  (provider.key == 'vidking' || provider.key == 'vixsrc'),
            ),
            ...rotated.where(
              (provider) =>
                  provider.key != 'vidking' && provider.key != 'vixsrc',
            ),
          ]
        : rotated;

    if (skipMatchingCanonicalIndex == null) {
      return ordered;
    }

    return ordered
        .where(
            (provider) => provider.canonicalIndex != skipMatchingCanonicalIndex)
        .toList();
  }

  List<ProviderDescriptor> _rankProviders(
    List<ProviderDescriptor> providers, {
    required MediaType mediaType,
    required int? preferredCanonicalIndex,
  }) {
    final ranked = List<ProviderDescriptor>.of(providers);
    final originalPositions = <int, int>{
      for (var index = 0; index < providers.length; index += 1)
        providers[index].canonicalIndex: index,
    };
    ranked.sort((left, right) {
      if (left.canonicalIndex == preferredCanonicalIndex) {
        return -1;
      }
      if (right.canonicalIndex == preferredCanonicalIndex) {
        return 1;
      }
      final scoreCompare = sourceHealthStore
          .priorityScore(left.canonicalIndex, mediaType)
          .compareTo(
            sourceHealthStore.priorityScore(right.canonicalIndex, mediaType),
          );
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return originalPositions[left.canonicalIndex]!
          .compareTo(originalPositions[right.canonicalIndex]!);
    });
    return ranked;
  }

  PlaybackTarget _withOfflineDownloadCapability(PlaybackTarget target) {
    if (!target.isDirectPlayable || target.offlineStorageAllowed) {
      return target;
    }
    // Direct sources use the same validated media path for streaming and
    // downloads. Embed pages remain ineligible because they are not media.
    return PlaybackTarget(
      uri: target.uri,
      providerKey: target.providerKey,
      providerLabel: target.providerLabel,
      providerIndex: target.providerIndex,
      sourceKind: target.sourceKind,
      httpHeaders: target.httpHeaders,
      pageUri: target.pageUri,
      expiresAtEpochMs: target.expiresAtEpochMs,
      fallbackUris: target.fallbackUris,
      diagnosticSessionId: target.diagnosticSessionId,
      offlineStorageAllowed: true,
      qualityLabel: target.qualityLabel,
      bitrateBitsPerSecond: target.bitrateBitsPerSecond,
    );
  }

  List<ProviderDescriptor> _prioritizeProvidersForAudioLanguage(
    List<ProviderDescriptor> providers,
    String languageCode,
  ) {
    final normalized = languageCode.trim().toLowerCase().split('-').first;
    if (normalized.isEmpty || normalized == 'en') return providers;
    const languageAwareProviders = <String>{'vixsrc', 'videasy', 'vidapi'};
    return <ProviderDescriptor>[
      ...providers.where(
        (provider) => languageAwareProviders.contains(provider.key),
      ),
      ...providers.where(
        (provider) => !languageAwareProviders.contains(provider.key),
      ),
    ];
  }

  String _resolutionContentKey({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int? seasonNumber,
    required int? episodeNumber,
  }) =>
      '$profileId:${mediaType.name}:$tmdbId:${seasonNumber ?? 0}:${episodeNumber ?? 0}';

  PlaybackTarget _withDiagnosticSession(
    PlaybackTarget target,
    String sessionId,
  ) {
    return PlaybackTarget(
      uri: target.uri,
      providerKey: target.providerKey,
      providerLabel: target.providerLabel,
      providerIndex: target.providerIndex,
      sourceKind: target.sourceKind,
      httpHeaders: target.httpHeaders,
      pageUri: target.pageUri,
      expiresAtEpochMs: target.expiresAtEpochMs,
      fallbackUris: target.fallbackUris,
      diagnosticSessionId: sessionId,
      offlineStorageAllowed: target.offlineStorageAllowed,
      qualityLabel: target.qualityLabel,
      bitrateBitsPerSecond: target.bitrateBitsPerSecond,
    );
  }

  Future<void> _ignoreSourceResolverErrors(
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {}
  }
}

class _ConcurrentResolutionSession {
  _ConcurrentResolutionSession({
    required this.contentKey,
    required this.mediaType,
    required this.generation,
    required this.diagnosticSessionId,
    required this.attempts,
    required this.maxConcurrent,
    required this.resolveCandidate,
    required this.sourceHealthStore,
  });

  final String contentKey;
  final MediaType mediaType;
  final int generation;
  final String diagnosticSessionId;
  final List<ProviderDescriptor> attempts;
  final int maxConcurrent;
  final Future<PlaybackTarget?> Function(ProviderDescriptor provider)
      resolveCandidate;
  final SourceHealthStore sourceHealthStore;

  final StreamController<void> _changes = StreamController<void>.broadcast();
  final List<PlaybackTarget> _ready = <PlaybackTarget>[];
  final Set<int> _excludedProviders = <int>{};
  final Set<int> _deliveredProviders = <int>{};
  final Set<int> _finishedProviders = <int>{};
  final Map<int, _ProviderSourceState> _providerStates =
      <int, _ProviderSourceState>{};
  var _nextAttempt = 0;
  var _inFlight = 0;
  var _completed = 0;
  var _started = false;
  var _cancelled = false;
  var _reportedFirstSource = false;
  var _pauseNewAttemptsForStartupSource = false;

  bool get isCancelled => _cancelled;
  Map<String, String> get providerStateSummary => <String, String>{
        for (final provider in attempts)
          provider.key: (_providerStates[provider.canonicalIndex] ??
                  _ProviderSourceState.queued)
              .name,
      };
  bool get isExhausted =>
      _completed >= attempts.length &&
      !_ready.any(
        (target) =>
            !_excludedProviders.contains(target.providerIndex) &&
            !_deliveredProviders.contains(target.providerIndex),
      );

  void start() {
    if (_started || _cancelled) {
      return;
    }
    _started = true;
    _pump();
  }

  void cancel() {
    _cancelled = true;
    PlaybackDiagnostics.instance.finishSession(diagnosticSessionId);
    _notify();
  }

  void excludeProvider(int providerIndex) {
    _excludedProviders.add(providerIndex);
    _notify();
  }

  void markPlaying(int providerIndex) {
    _providerStates[providerIndex] = _ProviderSourceState.playing;
    _notify();
  }

  void markFailed(int providerIndex, SourceFailureKind kind) {
    _providerStates[providerIndex] = switch (kind) {
      SourceFailureKind.startupStall => _ProviderSourceState.stalled,
      SourceFailureKind.playbackStall => _ProviderSourceState.stalled,
      _ => _ProviderSourceState.failed,
    };
    _notify();
  }

  Future<PlaybackTarget?> nextTarget({
    bool preferDirectGrace = false,
  }) async {
    start();
    // A second call means the previously delivered source failed in the real
    // player. Resume the queued providers immediately for fallback.
    if (_pauseNewAttemptsForStartupSource && _deliveredProviders.isNotEmpty) {
      _pauseNewAttemptsForStartupSource = false;
      _pump();
    }
    DateTime? directGraceDeadline;
    DateTime? vidKingGraceDeadline;
    while (!_cancelled) {
      final direct = _peekReady(directOnly: true);
      if (direct != null) {
        if (preferDirectGrace &&
            direct.providerKey != 'vidking' &&
            _isProviderPendingAheadOf('vidking', direct.providerIndex)) {
          vidKingGraceDeadline ??=
              DateTime.now().add(const Duration(milliseconds: 750));
          final remaining = vidKingGraceDeadline.difference(DateTime.now());
          if (remaining > Duration.zero) {
            await _waitForChange(remaining);
            continue;
          }
        }
        return _takeReady(directOnly: true);
      }
      final embed = _peekReady();
      if (embed != null) {
        if (preferDirectGrace && _hasPendingPreferredDirectProvider) {
          directGraceDeadline ??=
              DateTime.now().add(const Duration(seconds: 12));
          final remaining = directGraceDeadline.difference(DateTime.now());
          if (remaining > Duration.zero) {
            // A provider webpage can become "ready" before a native HLS source
            // has finished its manifest + first-segment validation. Giving the
            // native path a bounded head start prevents a quick embed result
            // from occupying the player while a genuinely playable stream is
            // already being proved in parallel. Provider completions may wake
            // this wait, but cannot consume the absolute deadline.
            await _waitForChange(remaining);
            continue;
          }
        }
        return _takeReady(directOnly: false);
      }
      if (isExhausted) {
        return null;
      }
      await _waitForChange(const Duration(seconds: 13));
    }
    return null;
  }

  bool get _hasPendingPreferredDirectProvider => attempts.any(
        (provider) =>
            (provider.key == 'vixsrc' || provider.key == 'vidking') &&
            !_finishedProviders.contains(provider.canonicalIndex),
      );

  bool _isProviderPending(String providerKey) => attempts.any(
        (provider) =>
            provider.key == providerKey &&
            !_excludedProviders.contains(provider.canonicalIndex) &&
            !_deliveredProviders.contains(provider.canonicalIndex) &&
            !_finishedProviders.contains(provider.canonicalIndex),
      );

  bool _isProviderPendingAheadOf(String providerKey, int readyProviderIndex) {
    final pendingPosition = attempts.indexWhere(
      (provider) =>
          provider.key == providerKey && _isProviderPending(providerKey),
    );
    final readyPosition = attempts.indexWhere(
      (provider) => provider.canonicalIndex == readyProviderIndex,
    );
    return pendingPosition >= 0 &&
        readyPosition >= 0 &&
        pendingPosition < readyPosition;
  }

  PlaybackTarget? _peekReady({bool directOnly = false}) {
    // Completion order alone is noisy: a historically unreliable provider can
    // win a race by a few milliseconds. Select among sources that are already
    // ready using the contextual attempt ranking. A source that is not ready
    // never blocks a lower-ranked validated fallback beyond the bounded grace.
    for (final provider in attempts) {
      for (final target in _ready) {
        if (target.providerIndex == provider.canonicalIndex &&
            _isEligibleReadyTarget(target, directOnly: directOnly)) {
          return target;
        }
      }
    }
    return null;
  }

  PlaybackTarget? _takeReady({required bool directOnly}) {
    final preferred = _peekReady(directOnly: directOnly);
    if (preferred != null) {
      _deliveredProviders.add(preferred.providerIndex);
      _providerStates[preferred.providerIndex] = _ProviderSourceState.starting;
      for (final retained in _ready) {
        if (retained.providerIndex != preferred.providerIndex &&
            !_deliveredProviders.contains(retained.providerIndex) &&
            !_excludedProviders.contains(retained.providerIndex)) {
          _providerStates[retained.providerIndex] =
              _ProviderSourceState.retainedFallback;
        }
      }
      return preferred;
    }
    return null;
  }

  bool _isEligibleReadyTarget(
    PlaybackTarget target, {
    required bool directOnly,
  }) {
    return !_excludedProviders.contains(target.providerIndex) &&
        !_deliveredProviders.contains(target.providerIndex) &&
        !_isExpired(target) &&
        (!directOnly || target.isDirectPlayable);
  }

  bool _isExpired(PlaybackTarget target) {
    final expiresAt = target.expiresAtEpochMs;
    return expiresAt != null &&
        expiresAt <= DateTime.now().millisecondsSinceEpoch + 5000;
  }

  Future<void> _waitForChange(Duration timeout) async {
    if (_cancelled || isExhausted) {
      return;
    }
    try {
      await _changes.stream.first.timeout(timeout);
    } on TimeoutException {
      // Every provider has its own timeout. This short wait merely rechecks
      // session state so a missed stream notification cannot hang playback.
    }
  }

  void _pump() {
    while (!_cancelled &&
        !_pauseNewAttemptsForStartupSource &&
        _inFlight < maxConcurrent &&
        _nextAttempt < attempts.length) {
      final provider = attempts[_nextAttempt++];
      _inFlight += 1;
      unawaited(_runCandidate(provider));
    }
  }

  Future<void> _runCandidate(ProviderDescriptor provider) async {
    final stopwatch = Stopwatch()..start();
    PlaybackDiagnostics.instance.record(
      sessionId: diagnosticSessionId,
      stage: PlaybackDiagnosticStage.providerStarted,
      providerKey: provider.key,
    );
    PlaybackTarget? target;
    Object? failure;
    _providerStates[provider.canonicalIndex] = _ProviderSourceState.resolving;
    try {
      target = await resolveCandidate(provider).timeout(
        provider.key == 'vidking' || provider.key == 'vixsrc'
            ? const Duration(seconds: 12)
            : const Duration(seconds: 7),
      );
    } catch (error) {
      failure = error;
    } finally {
      stopwatch.stop();
      _finishedProviders.add(provider.canonicalIndex);
    }

    if (_cancelled) {
      _inFlight -= 1;
      _completed += 1;
      return;
    }

    sourceHealthStore.recordResolution(
      providerIndex: provider.canonicalIndex,
      mediaType: mediaType,
      duration: stopwatch.elapsed,
      success: target != null,
      failureKind: failure is TimeoutException
          ? SourceFailureKind.timeout
          : target == null
              ? SourceFailureKind.sourceRejected
              : null,
    );
    PlaybackDiagnostics.instance.record(
      sessionId: diagnosticSessionId,
      stage: PlaybackDiagnosticStage.providerFinished,
      providerKey: provider.key,
      outcome: target != null
          ? target.isDirectPlayable
              ? 'direct'
              : 'embed-validated'
          : failure is TimeoutException
              ? 'timeout'
              : 'unavailable',
      details: <String, Object?>{
        'durationMs': stopwatch.elapsedMilliseconds,
        if (target != null) 'host': target.uri.host,
        if (target != null) 'kind': target.sourceKind.name,
        if (failure != null) 'errorType': failure.runtimeType.toString(),
      },
    );
    if (target?.isDirectPlayable == true) {
      PlaybackDiagnostics.instance.record(
        sessionId: diagnosticSessionId,
        stage: PlaybackDiagnosticStage.manifestReady,
        providerKey: provider.key,
        outcome: 'validated',
        details: <String, Object?>{'durationMs': stopwatch.elapsedMilliseconds},
      );
    }

    _inFlight -= 1;
    _completed += 1;
    if (!_cancelled && target != null) {
      _ready.add(target);
      _providerStates[provider.canonicalIndex] = _ProviderSourceState.validated;
      if (target.isDirectPlayable || _hasPendingPreferredDirectProvider) {
        // Keep already-running fallbacks, but do not launch more provider
        // webpages after a usable startup candidate exists. VidKing and
        // VixSrc are already in flight and retain their bounded head start.
        _pauseNewAttemptsForStartupSource = true;
      }
      if (!_reportedFirstSource) {
        _reportedFirstSource = true;
        PlaybackDiagnostics.instance.record(
          sessionId: diagnosticSessionId,
          stage: PlaybackDiagnosticStage.firstValidSource,
          providerKey: provider.key,
          outcome: target.isDirectPlayable ? 'direct' : 'embed-validated',
        );
      }
    } else if (!_cancelled) {
      _providerStates[provider.canonicalIndex] = failure is TimeoutException
          ? _ProviderSourceState.timedOut
          : _ProviderSourceState.rejected;
    }
    _pump();
    _notify();
  }

  void _notify() {
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }
}

enum _ProviderSourceState {
  queued,
  resolving,
  rejected,
  timedOut,
  validated,
  starting,
  playing,
  stalled,
  failed,
  retainedFallback,
}

abstract interface class EmbedProbe {
  Future<bool> canLoad(Uri uri, Duration timeout);
}

bool isLikelyWorkingEmbedResponse({
  required int statusCode,
  required String body,
}) {
  final isOkStatus = statusCode >= 200 && statusCode < 400;
  if (!isOkStatus) {
    return false;
  }

  final trimmedBody = body.trim();
  if (trimmedBody.isEmpty) {
    return false;
  }

  final normalizedBody =
      trimmedBody.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  const fatalSnippets = <String>[
    '404 page not found',
    'page not found',
    'return to the home page',
    'go to home',
    'application error',
    'client-side exception has occurred',
    'video not found',
    'media not found',
    'media is unavailable at the moment',
    'file not found',
    'content not found',
    'could not be found',
  ];

  if (fatalSnippets.any(normalizedBody.contains)) {
    return false;
  }

  if (RegExp(r'<title[^>]*>\s*404\b', caseSensitive: false).hasMatch(body)) {
    return false;
  }

  if (RegExp(
    'titletext\\s*=\\s*["\\\']404\\b',
    caseSensitive: false,
  ).hasMatch(body)) {
    return false;
  }

  return true;
}

class HttpEmbedProbe implements EmbedProbe {
  HttpEmbedProbe({HttpClient? client})
      : _client = client ?? _createBoundedHttpClient();

  final HttpClient _client;
  static const String _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36 Edg/133.0.0.0';

  @override
  Future<bool> canLoad(Uri uri, Duration timeout) async {
    try {
      final request = await _client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, _browserUserAgent);
      final response = await request.close().timeout(timeout);
      final body =
          await response.transform(utf8.decoder).join().timeout(timeout);
      return isLikelyWorkingEmbedResponse(
        statusCode: response.statusCode,
        body: body,
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

HttpClient _createBoundedHttpClient() {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..idleTimeout = const Duration(seconds: 6);
  return client;
}
