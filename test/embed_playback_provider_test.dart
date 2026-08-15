import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/media_type.dart';
import 'package:cheriflix/core/models/playback_target.dart';
import 'package:cheriflix/core/models/profile_playback_settings.dart';
import 'package:cheriflix/core/models/provider_config.dart';
import 'package:cheriflix/core/services/embed_playback_provider.dart';
import 'package:cheriflix/core/services/direct_source_validator.dart';
import 'package:cheriflix/core/services/profile_repository.dart';
import 'package:cheriflix/core/services/provider_catalog.dart';
import 'package:cheriflix/core/services/provider_preference_store.dart';
import 'package:cheriflix/core/services/source_health_store.dart';
import 'package:cheriflix/core/services/source_resolver_service.dart';

void main() {
  group('ProviderCatalog', () {
    const settings = ProfilePlaybackSettings(
      languageCode: 'de',
      preferredAudioLanguageCode: 'de',
      subtitleUrl: 'https://subtitles.example.com/test.vtt',
    );

    test('builds movie URLs for all enabled providers', () {
      final providers =
          const ProviderCatalog().orderedProviders(ProviderConfig.defaults());
      final urls = <String>[
        for (final provider in providers)
          ProviderCatalog.buildUri(
            provider: provider,
            tmdbId: 385687,
            mediaType: MediaType.movie,
            settings: settings,
          )!
              .toString(),
      ];

      expect(urls.take(2), <String>[
        'https://www.vidking.net/embed/movie/385687?autoPlay=true',
        'https://vixsrc.to/movie/385687?lang=de&autoplay=true',
      ]);
      expect(urls.toSet(), <String>{
        'https://www.vidking.net/embed/movie/385687?autoPlay=true',
        'https://vixsrc.to/movie/385687?lang=de&autoplay=true',
        'https://vaplayer.ru/embed/movie/385687?autoplay=1&controls=false&overlay=false&showTitle=false&ds_lang=de',
        'https://vidnest.fun/movie/385687?autoplay=1',
        'https://vidapi.xyz/embed/movie/385687?autoplay=1&muted=1',
        'https://vidsrc.xyz/embed/movie?tmdb=385687&autoplay=1',
        'https://111movies.com/movie/385687?autoplay=1',
        'https://player.autoembed.cc/embed/movie/385687?autoplay=1',
        'https://vidsrc.cc/v3/embed/movie/385687?autoPlay=true',
        'https://vidsrc.to/embed/movie/385687?autoplay=1&mute=1',
        'https://vsembed.ru/embed/movie/385687?autoplay=1&mute=1',
        'https://embed.su/embed/movie/385687?autoplay=1&mute=1',
        'https://vsrc.su/embed/movie/385687?autoplay=1&mute=1',
        'https://vidsrc.me/embed/movie/385687?autoplay=1&mute=1',
        'https://vidlink.pro/movie/385687',
        'https://vidsrc-embed.ru/embed/movie?tmdb=385687&autoplay=1&mute=1&ds_lang=de&sub_url=https%3A%2F%2Fsubtitles.example.com%2Ftest.vtt',
        'https://vidembed.cc/movie/385687',
        'https://vidzee.wtf/movie/385687',
        'https://maplestage.com/movie/385687',
        'https://primewire.tf/embed/movie?tmdb=385687',
        'https://multiembed.mov/?video_id=385687&tmdb=1',
        'https://autoembed.co/embed/movie/385687',
        'https://2embed.cc/embed/385687',
        'https://111movies.net/movie/385687',
        'https://hdrezka.ag/',
      });
    });

    test('builds episode URLs for all enabled providers', () {
      final providers =
          const ProviderCatalog().orderedProviders(ProviderConfig.defaults());
      final urls = <String>[
        for (final provider in providers)
          ProviderCatalog.buildUri(
            provider: provider,
            tmdbId: 1399,
            mediaType: MediaType.tv,
            seasonNumber: 1,
            episodeNumber: 1,
            settings: settings,
          )!
              .toString(),
      ];

      expect(urls.take(2), <String>[
        'https://www.vidking.net/embed/tv/1399/1/1?autoPlay=true',
        'https://vixsrc.to/tv/1399/1/1?lang=de&autoplay=true',
      ]);
      expect(urls.toSet(), <String>{
        'https://www.vidking.net/embed/tv/1399/1/1?autoPlay=true',
        'https://vixsrc.to/tv/1399/1/1?lang=de&autoplay=true',
        'https://vaplayer.ru/embed/tv/1399/1/1?autoplay=1&controls=false&overlay=false&showTitle=false&ds_lang=de',
        'https://vidnest.fun/tv/1399/1/1?autoplay=1',
        'https://vidapi.xyz/embed/tv/1399/1/1?autoplay=1&muted=1',
        'https://vidsrc.xyz/embed/tv?tmdb=1399&season=1&episode=1&autoplay=1',
        'https://111movies.com/tv/1399/1/1?autoplay=1',
        'https://player.autoembed.cc/embed/tv/1399/1/1?autoplay=1',
        'https://vidsrc.cc/v3/embed/tv/1399/1/1?autoPlay=true',
        'https://vidsrc.to/embed/tv/1399/1/1?autoplay=1&autonext=1&mute=1',
        'https://vsembed.ru/embed/tv/1399/1/1?autoplay=1&autonext=1&mute=1',
        'https://embed.su/embed/tv/1399/1/1?autoplay=1&autonext=1&mute=1',
        'https://vsrc.su/embed/tv/1399/1/1?autoplay=1&autonext=1&mute=1',
        'https://vidsrc.me/embed/tv/1399/1/1?autoplay=1&autonext=1&mute=1',
        'https://vidlink.pro/tv/1399/1/1',
        'https://vidsrc-embed.ru/embed/tv?tmdb=1399&season=1&episode=1&autoplay=1&autonext=1&mute=1&ds_lang=de&sub_url=https%3A%2F%2Fsubtitles.example.com%2Ftest.vtt',
        'https://vidembed.cc/episode/1399-1-1',
        'https://vidzee.wtf/tv/1399/1/1',
        'https://maplestage.com/tv/1399/1/1',
        'https://primewire.tf/embed/tv?tmdb=1399&s=1&e=1',
        'https://multiembed.mov/?video_id=1399&tmdb=1&s=1&e=1',
        'https://autoembed.co/embed/tv/1399/1/1',
        'https://2embed.cc/embedtv/1399&s=1&e=1',
        'https://111movies.net/tv/1399/1/1',
        'https://hdrezka.ag/',
      });
    });

    test('respects config overrides and disabled providers', () {
      final config = ProviderConfig(
        providerPriority: const <String>['vidsrc', 'vidlink'],
        providerTimeoutSeconds: 5,
        disabledProviders: const <String>{'vidlink', 'videasy'},
      );

      final ordered = const ProviderCatalog().orderedProviders(config);
      expect(ordered.first.key, 'vidsrc');
      expect(ordered.any((provider) => provider.key == 'vidlink'), isFalse);
      expect(ordered.any((provider) => provider.key == 'videasy'), isFalse);
    });
  });

  group('EmbedPlaybackProvider', () {
    test('races providers and retains the slower validated fallback', () async {
      final resolver = _DelayedSourceResolverService(
        delays: const <int, Duration>{
          6: Duration(milliseconds: 220),
          3: Duration(milliseconds: 35),
        },
      );
      final provider = EmbedPlaybackProvider(
        providerCatalog: const ProviderCatalog(),
        preferenceStore: _MemoryPreferenceStore(),
        profileSettingsStore: const _StaticSettingsStore(),
        providerConfig: const ProviderConfig(
          providerPriority: <String>['vidsrc', 'videasy'],
          providerTimeoutSeconds: 4,
          disabledProviders: <String>{},
        ),
        probe: _FailingProbe(),
        sourceResolverService: resolver,
        directSourceValidator: const _AlwaysValidDirectSourceValidator(),
        raceInitialSources: true,
      );

      final first = await provider.resolveTitle(
        profileId: 'profile-1',
        tmdbId: 44242,
        mediaType: MediaType.tv,
        seasonNumber: 1,
        episodeNumber: 2,
      );
      expect(first?.providerIndex, 3);

      final fallback = await provider.resolveNextSource(
        profileId: 'profile-1',
        tmdbId: 44242,
        mediaType: MediaType.tv,
        currentProviderIndex: 3,
        seasonNumber: 1,
        episodeNumber: 2,
      );
      expect(fallback?.providerIndex, 6);
      expect(resolver.requestedProviderIndices.where((index) => index == 6),
          hasLength(1));
      expect(resolver.requestedProviderIndices.where((index) => index == 3),
          hasLength(1));
    });

    test('gives faster VidKing a short opportunity over ready VixSrc',
        () async {
      final resolver = _DelayedSourceResolverService(
        delays: const <int, Duration>{
          17: Duration(milliseconds: 180),
          23: Duration(milliseconds: 30),
        },
      );
      final provider = EmbedPlaybackProvider(
        providerCatalog: const ProviderCatalog(),
        preferenceStore: _MemoryPreferenceStore(),
        profileSettingsStore: const _StaticSettingsStore(),
        providerConfig: ProviderConfig.defaults(),
        probe: _FailingProbe(),
        sourceResolverService: resolver,
        directSourceValidator: const _AlwaysValidDirectSourceValidator(),
        raceInitialSources: true,
      );

      final first = await provider.resolveTitle(
        profileId: 'profile-1',
        tmdbId: 44242,
        mediaType: MediaType.tv,
        seasonNumber: 1,
        episodeNumber: 2,
      );

      expect(first?.providerKey, 'vidking');
      expect(first?.providerIndex, 17);
    });

    test('invalidates stale resolution results when the episode changes',
        () async {
      final resolver = _DelayedSourceResolverService(
        delaysByEpisode: const <int, Duration>{
          1: Duration(milliseconds: 220),
          2: Duration(milliseconds: 20),
        },
      );
      final provider = EmbedPlaybackProvider(
        providerCatalog: const ProviderCatalog(),
        preferenceStore: _MemoryPreferenceStore(),
        profileSettingsStore: const _StaticSettingsStore(),
        providerConfig: const ProviderConfig(
          providerPriority: <String>['videasy'],
          providerTimeoutSeconds: 4,
          disabledProviders: <String>{},
        ),
        probe: _FailingProbe(),
        sourceResolverService: resolver,
        directSourceValidator: const _AlwaysValidDirectSourceValidator(),
        raceInitialSources: true,
      );

      final stale = provider.resolveTitle(
        profileId: 'profile-1',
        tmdbId: 44242,
        mediaType: MediaType.tv,
        seasonNumber: 1,
        episodeNumber: 1,
      );
      await Future<void>.delayed(const Duration(milliseconds: 15));
      final current = await provider.resolveTitle(
        profileId: 'profile-1',
        tmdbId: 44242,
        mediaType: MediaType.tv,
        seasonNumber: 1,
        episodeNumber: 2,
      );
      expect(current?.uri.path, contains('/2/'));
      expect(await stale, isNull);
    });

    test(
        'advances immediately to another direct extractor when VidKing is unavailable',
        () async {
      final resolver = _MapSourceResolverService(
        unavailableProviderIndices: <int>{17},
      );
      final provider = EmbedPlaybackProvider(
        providerCatalog: const ProviderCatalog(),
        preferenceStore: _MemoryPreferenceStore(),
        profileSettingsStore: const _StaticSettingsStore(),
        providerConfig: ProviderConfig(
          providerPriority: ProviderConfig.defaults().providerPriority,
          providerTimeoutSeconds:
              ProviderConfig.defaults().providerTimeoutSeconds,
          disabledProviders: const <String>{'vixsrc'},
        ),
        probe: _UnusedProbe(),
        sourceResolverService: resolver,
      );

      final target = await provider.resolveTitle(
        profileId: 'profile-1',
        tmdbId: 1399,
        mediaType: MediaType.tv,
        seasonNumber: 1,
        episodeNumber: 1,
      );

      expect(target, isNotNull);
      expect(target!.providerKey, 'vidsrc');
      expect(target.sourceKind, PlaybackSourceKind.file);
      expect(resolver.requestedProviderIndices, <int>[17, 6]);
    });

    test('prefers an available direct extractor when advancing past VidAPI',
        () async {
      final resolver = _MapSourceResolverService();
      final provider = EmbedPlaybackProvider(
        providerCatalog: const ProviderCatalog(),
        preferenceStore: _MemoryPreferenceStore(),
        profileSettingsStore: const _StaticSettingsStore(),
        providerConfig: ProviderConfig.defaults(),
        probe: _UnusedProbe(),
        sourceResolverService: resolver,
      );

      final target = await provider.resolveNextSource(
        profileId: 'profile-1',
        tmdbId: 385687,
        mediaType: MediaType.movie,
        currentProviderIndex: 18,
      );

      expect(target, isNotNull);
      expect(target!.providerKey, 'vidnest');
      expect(target.sourceKind, PlaybackSourceKind.file);
      expect(resolver.requestedProviderIndices.first, 19);
    });

    test('skips embed fallback when native-only playback is enabled', () async {
      final resolver = _MapSourceResolverService(
        unavailableProviderIndices: <int>{6},
      );
      final provider = EmbedPlaybackProvider(
        providerCatalog: const ProviderCatalog(),
        preferenceStore: _MemoryPreferenceStore(),
        profileSettingsStore: const _StaticSettingsStore(),
        providerConfig: const ProviderConfig(
          providerPriority: <String>['vidsrc', 'videasy'],
          providerTimeoutSeconds: 8,
          disabledProviders: <String>{},
        ),
        probe: _UnusedProbe(),
        sourceResolverService: resolver,
        allowEmbedFallback: false,
      );

      final target = await provider.resolveTitle(
        profileId: 'profile-1',
        tmdbId: 385687,
        mediaType: MediaType.movie,
      );

      expect(target, isNotNull);
      expect(target!.providerKey, 'videasy');
      expect(resolver.requestedProviderIndices, <int>[6, 3]);
    });

    test('marks the first successful provider after playback opens', () async {
      final preferenceStore = _MemoryPreferenceStore();
      final provider = EmbedPlaybackProvider(
        providerCatalog: const ProviderCatalog(),
        preferenceStore: preferenceStore,
        profileSettingsStore: const _StaticSettingsStore(),
        providerConfig: const ProviderConfig(
          providerPriority: <String>['vidsrc', 'vidsrc_embed'],
          providerTimeoutSeconds: 8,
          disabledProviders: <String>{},
        ),
        probe: _UnusedProbe(),
        sourceResolverService: _MapSourceResolverService(
          unavailableProviderIndices: <int>{6},
        ),
      );

      final target = await provider.resolveTitle(
        profileId: 'profile-1',
        tmdbId: 1399,
        mediaType: MediaType.tv,
        seasonNumber: 1,
        episodeNumber: 1,
      );

      expect(target, isNotNull);
      expect(target!.providerKey, 'vidsrc');
      expect(
        await preferenceStore.getLastGoodProviderIndex(
          profileId: 'profile-1',
          tmdbId: 1399,
          mediaType: MediaType.tv,
        ),
        isNull,
      );

      await provider.recordSourceSuccess(
        profileId: 'profile-1',
        tmdbId: 1399,
        mediaType: MediaType.tv,
        seasonNumber: 1,
        episodeNumber: 1,
        providerIndex: target.providerIndex,
      );

      expect(
        await preferenceStore.getLastGoodProviderIndex(
          profileId: 'profile-1',
          tmdbId: 1399,
          mediaType: MediaType.tv,
        ),
        6,
      );
    });

    test('cools down a failed provider before retrying it again', () async {
      var now = DateTime(2026, 3, 23, 10, 0);
      final provider = EmbedPlaybackProvider(
        providerCatalog: const ProviderCatalog(),
        preferenceStore: _MemoryPreferenceStore(),
        profileSettingsStore: const _StaticSettingsStore(),
        providerConfig: const ProviderConfig(
          providerPriority: <String>['vidsrc', 'videasy'],
          providerTimeoutSeconds: 8,
          disabledProviders: <String>{},
        ),
        probe: _UnusedProbe(),
        sourceResolverService: _MapSourceResolverService(),
        clock: () => now,
      );

      final firstTarget = await provider.resolveTitle(
        profileId: 'profile-1',
        tmdbId: 385687,
        mediaType: MediaType.movie,
      );

      expect(firstTarget, isNotNull);
      expect(firstTarget!.providerKey, 'vidsrc');

      provider.recordSourceFailure(
        profileId: 'profile-1',
        tmdbId: 385687,
        mediaType: MediaType.movie,
        providerIndex: firstTarget.providerIndex,
        kind: SourceFailureKind.load,
      );

      final secondTarget = await provider.resolveTitle(
        profileId: 'profile-1',
        tmdbId: 385687,
        mediaType: MediaType.movie,
      );

      expect(secondTarget, isNotNull);
      expect(secondTarget!.providerKey, 'videasy');

      now = now.add(const Duration(seconds: 31));

      final thirdTarget = await provider.resolveTitle(
        profileId: 'profile-1',
        tmdbId: 385687,
        mediaType: MediaType.movie,
      );

      expect(thirdTarget, isNotNull);
      // Expiring the exact-title cooldown does not erase catalogue performance
      // immediately. The provider remains eligible, but the healthier direct
      // source stays ahead until fresh results improve the score.
      expect(thirdTarget!.providerKey, 'videasy');
    });

    test('respects a known-good provider instead of retrying VidKing',
        () async {
      final preferenceStore = _MemoryPreferenceStore()
        ..store(
          profileId: 'profile-1',
          tmdbId: 438631,
          mediaType: MediaType.movie,
          providerIndex: 6,
        );
      final resolver = _MapSourceResolverService();
      final provider = EmbedPlaybackProvider(
        providerCatalog: const ProviderCatalog(),
        preferenceStore: preferenceStore,
        profileSettingsStore: const _StaticSettingsStore(),
        providerConfig: ProviderConfig.defaults(),
        probe: _UnusedProbe(),
        sourceResolverService: resolver,
      );

      final target = await provider.resolveTitle(
        profileId: 'profile-1',
        tmdbId: 438631,
        mediaType: MediaType.movie,
      );

      expect(target, isNotNull);
      expect(target!.providerKey, 'vidsrc');
      expect(resolver.requestedProviderIndices.first, 6);
    });
    test('starts from the last known good provider on the next resolve',
        () async {
      final preferenceStore = _MemoryPreferenceStore()
        ..store(
          profileId: 'profile-1',
          tmdbId: 438631,
          mediaType: MediaType.movie,
          providerIndex: 6,
        );
      final resolver = _MapSourceResolverService();
      final provider = EmbedPlaybackProvider(
        providerCatalog: const ProviderCatalog(),
        preferenceStore: preferenceStore,
        profileSettingsStore: const _StaticSettingsStore(),
        providerConfig: const ProviderConfig(
          providerPriority: <String>['vidsrc', 'videasy'],
          providerTimeoutSeconds: 8,
          disabledProviders: <String>{},
        ),
        probe: _UnusedProbe(),
        sourceResolverService: resolver,
      );

      final target = await provider.resolveTitle(
        profileId: 'profile-1',
        tmdbId: 438631,
        mediaType: MediaType.movie,
      );

      expect(target, isNotNull);
      expect(target!.providerKey, 'vidsrc');
      expect(resolver.requestedProviderIndices.first, 6);
    });

    test('resolveNextSource skips the current provider', () async {
      final resolver = _MapSourceResolverService();
      final provider = EmbedPlaybackProvider(
        providerCatalog: const ProviderCatalog(),
        preferenceStore: _MemoryPreferenceStore(),
        profileSettingsStore: const _StaticSettingsStore(),
        providerConfig: const ProviderConfig(
          providerPriority: <String>['vidsrc', 'vidsrc_embed', 'videasy'],
          providerTimeoutSeconds: 8,
          disabledProviders: <String>{},
        ),
        probe: _UnusedProbe(),
        sourceResolverService: resolver,
      );

      final target = await provider.resolveNextSource(
        profileId: 'profile-1',
        tmdbId: 1399,
        mediaType: MediaType.tv,
        currentProviderIndex: 2,
        seasonNumber: 1,
        episodeNumber: 1,
      );

      expect(target, isNotNull);
      expect(target!.providerKey, 'videasy');
      expect(resolver.requestedProviderIndices.first, 3);
    });

    test('cycles all enabled providers before returning no source', () async {
      final catalog = const ProviderCatalog();
      final orderedProviderIndices = catalog
          .orderedProviders(ProviderConfig.defaults())
          .map((provider) => provider.canonicalIndex)
          .toList(growable: false);
      final resolver = _MapSourceResolverService(
        unavailableProviderIndices: orderedProviderIndices.toSet(),
      );
      final provider = EmbedPlaybackProvider(
        providerCatalog: catalog,
        preferenceStore: _MemoryPreferenceStore(),
        profileSettingsStore: const _StaticSettingsStore(),
        providerConfig: ProviderConfig.defaults(),
        probe: _FailingProbe(),
        sourceResolverService: resolver,
        allowEmbedFallback: false,
      );

      final target = await provider.resolveTitle(
        profileId: 'profile-1',
        tmdbId: 385687,
        mediaType: MediaType.movie,
      );

      expect(target, isNull);
      expect(
        resolver.requestedProviderIndices.toSet(),
        orderedProviderIndices.toSet(),
      );
      expect(
        resolver.requestedProviderIndices.take(9).toSet(),
        <int>{17, 23, 6, 13, 12, 14, 15, 2, 3},
      );
    });

    test('still opens provider pages when probing is too conservative',
        () async {
      final resolver = _MapSourceResolverService(
        unavailableProviderIndices: <int>{6},
      );
      final provider = EmbedPlaybackProvider(
        providerCatalog: const ProviderCatalog(),
        preferenceStore: _MemoryPreferenceStore(),
        profileSettingsStore: const _StaticSettingsStore(),
        providerConfig: const ProviderConfig(
          providerPriority: <String>['vidsrc'],
          providerTimeoutSeconds: 8,
          disabledProviders: <String>{},
        ),
        probe: _FailingProbe(),
        sourceResolverService: resolver,
      );

      final target = await provider.resolveTitle(
        profileId: 'profile-1',
        tmdbId: 385687,
        mediaType: MediaType.movie,
      );

      expect(target, isNotNull);
      expect(target!.providerKey, 'vidsrc');
      expect(target.sourceKind, PlaybackSourceKind.embed);
      expect(resolver.requestedProviderIndices, <int>[6]);
    });

    test('accepts embed targets returned by a resolver when fallback is on',
        () async {
      final resolver = _FixedSourceResolverService(
        PlaybackTarget(
          uri: Uri.parse('https://resolver.example.com/embed/movie/385687'),
          providerKey: 'resolver',
          providerLabel: 'Resolver',
          providerIndex: 6,
          sourceKind: PlaybackSourceKind.embed,
        ),
      );
      final provider = EmbedPlaybackProvider(
        providerCatalog: const ProviderCatalog(),
        preferenceStore: _MemoryPreferenceStore(),
        profileSettingsStore: const _StaticSettingsStore(),
        providerConfig: const ProviderConfig(
          providerPriority: <String>['vidsrc'],
          providerTimeoutSeconds: 8,
          disabledProviders: <String>{},
        ),
        probe: _UnusedProbe(),
        sourceResolverService: resolver,
      );

      final target = await provider.resolveTitle(
        profileId: 'profile-1',
        tmdbId: 385687,
        mediaType: MediaType.movie,
      );

      expect(target, isNotNull);
      expect(target!.uri.toString(),
          'https://resolver.example.com/embed/movie/385687');
      expect(target.sourceKind, PlaybackSourceKind.embed);
    });

    test('falls back to the provider page when the resolver is unavailable',
        () async {
      final provider = EmbedPlaybackProvider(
        providerCatalog: const ProviderCatalog(),
        preferenceStore: _MemoryPreferenceStore(),
        profileSettingsStore: const _StaticSettingsStore(),
        providerConfig: const ProviderConfig(
          providerPriority: <String>['vidsrc'],
          providerTimeoutSeconds: 8,
          disabledProviders: <String>{},
        ),
        probe: _UnusedProbe(),
        sourceResolverService: const MissingSourceResolverService(),
      );

      final target = await provider.resolveTitle(
        profileId: 'profile-1',
        tmdbId: 385687,
        mediaType: MediaType.movie,
      );

      expect(target, isNotNull);
      expect(target!.providerKey, 'vidsrc');
      expect(target.sourceKind, PlaybackSourceKind.embed);
      expect(target.uri.toString(),
          'https://vidsrc.to/embed/movie/385687?autoplay=1&mute=1');
    });
  });
}

class _MapSourceResolverService implements SourceResolverService {
  _MapSourceResolverService({
    Set<int>? unavailableProviderIndices,
  }) : _unavailableProviderIndices =
            unavailableProviderIndices ?? const <int>{};

  final Set<int> _unavailableProviderIndices;
  final List<int> requestedProviderIndices = <int>[];

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
    throw UnimplementedError();
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
    throw UnimplementedError();
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
    requestedProviderIndices.add(providerIndex);
    if (_unavailableProviderIndices.contains(providerIndex)) {
      return null;
    }

    final provider = const ProviderCatalog().defaultProviders.firstWhere(
          (candidate) => candidate.canonicalIndex == providerIndex,
        );
    final uri = ProviderCatalog.buildUri(
      provider: provider,
      tmdbId: tmdbId,
      mediaType: mediaType,
      settings: settings,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
    if (uri == null) {
      return null;
    }

    return PlaybackTarget(
      uri: uri,
      providerKey: provider.key,
      providerLabel: provider.label,
      providerIndex: provider.canonicalIndex,
      sourceKind: uri.path.endsWith('.m3u8')
          ? PlaybackSourceKind.hls
          : PlaybackSourceKind.file,
      pageUri: uri,
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

class _DelayedSourceResolverService implements SourceResolverService {
  _DelayedSourceResolverService({
    this.delays = const <int, Duration>{},
    this.delaysByEpisode = const <int, Duration>{},
  });

  final Map<int, Duration> delays;
  final Map<int, Duration> delaysByEpisode;
  final List<int> requestedProviderIndices = <int>[];

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
    requestedProviderIndices.add(providerIndex);
    final allowedIndices = delays.isNotEmpty ? delays.keys.toSet() : <int>{3};
    if (!allowedIndices.contains(providerIndex)) {
      return null;
    }
    await Future<void>.delayed(
      delaysByEpisode[episodeNumber] ?? delays[providerIndex] ?? Duration.zero,
    );
    final descriptor = const ProviderCatalog()
        .defaultProviders
        .firstWhere((provider) => provider.canonicalIndex == providerIndex);
    return PlaybackTarget(
      uri: Uri.parse(
        'https://media.example.com/$providerIndex/${episodeNumber ?? 0}/video.m3u8',
      ),
      providerKey: descriptor.key,
      providerLabel: descriptor.label,
      providerIndex: providerIndex,
      sourceKind: PlaybackSourceKind.hls,
    );
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
  }) async =>
      null;

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
  }) async =>
      null;

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
  }) async =>
      null;
}

class _AlwaysValidDirectSourceValidator implements DirectSourceValidator {
  const _AlwaysValidDirectSourceValidator();
  @override
  Future<DirectSourceValidationResult> validate(PlaybackTarget target) async {
    return const DirectSourceValidationResult(
      playable: true,
      stage: 'test',
    );
  }
}

class _FixedSourceResolverService implements SourceResolverService {
  const _FixedSourceResolverService(this.target);

  final PlaybackTarget? target;

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
    return target;
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
    return target;
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
    return target;
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

class _UnusedProbe implements EmbedProbe {
  @override
  Future<bool> canLoad(Uri uri, Duration timeout) async => true;
}

class _FailingProbe implements EmbedProbe {
  @override
  Future<bool> canLoad(Uri uri, Duration timeout) async => false;
}

class _MemoryPreferenceStore implements ProviderPreferenceStore {
  final Map<String, int> _values = <String, int>{};

  @override
  Future<int?> getLastGoodProviderIndex({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
  }) async {
    return _values[_key(profileId, tmdbId, mediaType)];
  }

  @override
  Future<void> saveLastGoodProviderIndex({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
  }) async {
    _values[_key(profileId, tmdbId, mediaType)] = providerIndex;
  }

  void store({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
  }) {
    _values[_key(profileId, tmdbId, mediaType)] = providerIndex;
  }

  String _key(String profileId, int tmdbId, MediaType mediaType) {
    return '$profileId:$tmdbId:${mediaType.name}';
  }
}

class _StaticSettingsStore implements ProfileSettingsStore {
  const _StaticSettingsStore();

  @override
  Future<ProfilePlaybackSettings> loadPlaybackSettings(String profileId) async {
    return const ProfilePlaybackSettings(languageCode: 'en');
  }

  @override
  Future<void> savePlaybackSettings(
    String profileId,
    ProfilePlaybackSettings settings,
  ) async {}
}
