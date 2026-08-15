import 'dart:convert';
import 'dart:io';

import 'package:cheriflix/core/models/media_type.dart';
import 'package:cheriflix/core/models/playback_target.dart';
import 'package:cheriflix/core/models/profile_playback_settings.dart';
import 'package:cheriflix/core/models/provider_config.dart';
import 'package:cheriflix/core/services/built_in_source_resolver_service.dart';
import 'package:cheriflix/core/services/embed_playback_provider.dart';
import 'package:cheriflix/core/services/profile_repository.dart';
import 'package:cheriflix/core/services/provider_catalog.dart';
import 'package:cheriflix/core/services/provider_preference_store.dart';
import 'package:flutter_test/flutter_test.dart';

typedef RegressionCase = ({
  String title,
  int id,
  MediaType type,
  int? season,
  int? episode,
});

// Resolver coverage deliberately spans decades, movies/TV, early/late seasons,
// and titles outside the user's reported examples. This tool does not call a
// resolver result a playback PASS: only the installed-APK matrix can do that.
const _cases = <RegressionCase>[
  (
    title: 'Burn (2019)',
    id: 508138,
    type: MediaType.movie,
    season: null,
    episode: null
  ),
  (
    title: 'Fight Club',
    id: 550,
    type: MediaType.movie,
    season: null,
    episode: null
  ),
  (
    title: 'The Matrix',
    id: 603,
    type: MediaType.movie,
    season: null,
    episode: null
  ),
  (
    title: 'The Godfather',
    id: 238,
    type: MediaType.movie,
    season: null,
    episode: null
  ),
  (
    title: 'Pulp Fiction',
    id: 680,
    type: MediaType.movie,
    season: null,
    episode: null
  ),
  (
    title: 'The Shawshank Redemption',
    id: 278,
    type: MediaType.movie,
    season: null,
    episode: null
  ),
  (
    title: 'The Dark Knight',
    id: 155,
    type: MediaType.movie,
    season: null,
    episode: null
  ),
  (
    title: 'Inception',
    id: 27205,
    type: MediaType.movie,
    season: null,
    episode: null
  ),
  (
    title: 'Interstellar',
    id: 157336,
    type: MediaType.movie,
    season: null,
    episode: null
  ),
  (
    title: 'Whiplash',
    id: 244786,
    type: MediaType.movie,
    season: null,
    episode: null
  ),
  (
    title: 'Mad Max: Fury Road',
    id: 76341,
    type: MediaType.movie,
    season: null,
    episode: null
  ),
  (
    title: 'Arrival',
    id: 329865,
    type: MediaType.movie,
    season: null,
    episode: null
  ),
  (
    title: 'Get Out',
    id: 419430,
    type: MediaType.movie,
    season: null,
    episode: null
  ),
  (
    title: 'Parasite',
    id: 496243,
    type: MediaType.movie,
    season: null,
    episode: null
  ),
  (
    title: 'Dune',
    id: 438631,
    type: MediaType.movie,
    season: null,
    episode: null
  ),
  (
    title: 'Copshop',
    id: 738652,
    type: MediaType.movie,
    season: null,
    episode: null
  ),
  (
    title: 'Top Gun: Maverick',
    id: 361743,
    type: MediaType.movie,
    season: null,
    episode: null
  ),
  (
    title: 'Everything Everywhere All at Once',
    id: 545611,
    type: MediaType.movie,
    season: null,
    episode: null
  ),
  (
    title: 'Barbie',
    id: 346698,
    type: MediaType.movie,
    season: null,
    episode: null
  ),
  (
    title: 'Oppenheimer',
    id: 872585,
    type: MediaType.movie,
    season: null,
    episode: null
  ),
  (
    title: 'The Rookie S1E1',
    id: 79744,
    type: MediaType.tv,
    season: 1,
    episode: 1
  ),
  (
    title: 'The Rookie S1E2',
    id: 79744,
    type: MediaType.tv,
    season: 1,
    episode: 2
  ),
  (
    title: 'The Rookie S2E5',
    id: 79744,
    type: MediaType.tv,
    season: 2,
    episode: 5
  ),
  (
    title: 'The Rookie S6E10',
    id: 79744,
    type: MediaType.tv,
    season: 6,
    episode: 10
  ),
  (
    title: 'Desperate Housewives S1E1',
    id: 1408,
    type: MediaType.tv,
    season: 1,
    episode: 1
  ),
  (
    title: 'Desperate Housewives S1E2',
    id: 1408,
    type: MediaType.tv,
    season: 1,
    episode: 2
  ),
  (
    title: 'Desperate Housewives S3E7',
    id: 1408,
    type: MediaType.tv,
    season: 3,
    episode: 7
  ),
  (
    title: 'Desperate Housewives S8E23',
    id: 1408,
    type: MediaType.tv,
    season: 8,
    episode: 23
  ),
  (
    title: 'Devious Maids S1E1',
    id: 44242,
    type: MediaType.tv,
    season: 1,
    episode: 1
  ),
  (
    title: 'Devious Maids S1E2',
    id: 44242,
    type: MediaType.tv,
    season: 1,
    episode: 2
  ),
  (
    title: 'Devious Maids S2E1',
    id: 44242,
    type: MediaType.tv,
    season: 2,
    episode: 1
  ),
  (
    title: 'Devious Maids S4E10',
    id: 44242,
    type: MediaType.tv,
    season: 4,
    episode: 10
  ),
  (
    title: 'Breaking Bad S1E1',
    id: 1396,
    type: MediaType.tv,
    season: 1,
    episode: 1
  ),
  (
    title: 'Breaking Bad S5E16',
    id: 1396,
    type: MediaType.tv,
    season: 5,
    episode: 16
  ),
  (
    title: 'Game of Thrones S1E1',
    id: 1399,
    type: MediaType.tv,
    season: 1,
    episode: 1
  ),
  (
    title: 'Game of Thrones S8E6',
    id: 1399,
    type: MediaType.tv,
    season: 8,
    episode: 6
  ),
  (
    title: 'The Office S1E1',
    id: 2316,
    type: MediaType.tv,
    season: 1,
    episode: 1
  ),
  (
    title: 'The Office S9E23',
    id: 2316,
    type: MediaType.tv,
    season: 9,
    episode: 23
  ),
  (
    title: 'Stranger Things S1E1',
    id: 66732,
    type: MediaType.tv,
    season: 1,
    episode: 1
  ),
  (
    title: 'Stranger Things S4E9',
    id: 66732,
    type: MediaType.tv,
    season: 4,
    episode: 9
  ),
  (
    title: 'Better Call Saul S1E1',
    id: 60059,
    type: MediaType.tv,
    season: 1,
    episode: 1
  ),
  (
    title: 'Better Call Saul S6E13',
    id: 60059,
    type: MediaType.tv,
    season: 6,
    episode: 13
  ),
  (
    title: 'Severance S1E1',
    id: 95396,
    type: MediaType.tv,
    season: 1,
    episode: 1
  ),
  (
    title: 'The Last of Us S1E1',
    id: 100088,
    type: MediaType.tv,
    season: 1,
    episode: 1
  ),
];

void main() {
  test(
    'broad live resolver matrix (not an Android playback PASS)',
    () async {
      const catalog = ProviderCatalog();
      final resolver = BuiltInSourceResolverService(providerCatalog: catalog);
      final results = <Map<String, Object?>>[];

      for (var offset = 0; offset < _cases.length; offset += 4) {
        final batch = _cases.skip(offset).take(4);
        results.addAll(await Future.wait([
          for (final testCase in batch)
            _runCase(testCase, catalog: catalog, resolver: resolver),
        ]));
      }

      for (final result in results) {
        stdout.writeln(jsonEncode(result));
      }
      final direct = results
          .where((row) => row['resolverOutcome'] == 'direct-validated')
          .length;
      final embedOnly =
          results.where((row) => row['resolverOutcome'] == 'embed-only').length;
      final unavailable = results
          .where((row) => row['resolverOutcome'] == 'unavailable')
          .length;
      stdout.writeln(jsonEncode(<String, Object?>{
        'summary': true,
        'cases': results.length,
        'directValidated': direct,
        'embedOnly': embedOnly,
        'unavailable': unavailable,
        'warning':
            'Only installed-APK progressing playback is a playback PASS.',
      }));

      expect(results, hasLength(_cases.length));
      expect(direct, greaterThan(0),
          reason: 'Every direct provider path failed.');
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

Future<Map<String, Object?>> _runCase(
  RegressionCase testCase, {
  required ProviderCatalog catalog,
  required BuiltInSourceResolverService resolver,
}) async {
  final provider = EmbedPlaybackProvider(
    providerCatalog: catalog,
    preferenceStore: _MemoryPreferenceStore(),
    profileSettingsStore: const _StaticSettingsStore(),
    providerConfig: ProviderConfig.defaults(),
    probe: HttpEmbedProbe(),
    sourceResolverService: resolver,
    allowEmbedFallback: true,
    raceInitialSources: true,
  );
  final watch = Stopwatch()..start();
  PlaybackTarget? target;
  Object? failure;
  try {
    target = await provider
        .resolveTitle(
          profileId: 'catalogue-regression',
          tmdbId: testCase.id,
          mediaType: testCase.type,
          seasonNumber: testCase.season,
          episodeNumber: testCase.episode,
        )
        .timeout(const Duration(seconds: 35));
  } catch (error) {
    failure = error;
  }
  watch.stop();
  return <String, Object?>{
    'title': testCase.title,
    'tmdbId': testCase.id,
    'mediaType': testCase.type.name,
    if (testCase.season != null) 'season': testCase.season,
    if (testCase.episode != null) 'episode': testCase.episode,
    'elapsedMs': watch.elapsedMilliseconds,
    'resolverOutcome': target == null
        ? 'unavailable'
        : target.isDirectPlayable
            ? 'direct-validated'
            : 'embed-only',
    if (target != null) 'provider': target.providerKey,
    if (target != null) 'kind': target.sourceKind.name,
    if (target != null) 'host': target.uri.host,
    if (failure != null) 'error': failure.runtimeType.toString(),
  };
}

class _MemoryPreferenceStore implements ProviderPreferenceStore {
  final Map<String, int> _values = <String, int>{};
  @override
  Future<int?> getLastGoodProviderIndex({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
  }) async =>
      _values['$profileId:$tmdbId:${mediaType.name}'];

  @override
  Future<void> saveLastGoodProviderIndex({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
  }) async {
    _values['$profileId:$tmdbId:${mediaType.name}'] = providerIndex;
  }
}

class _StaticSettingsStore implements ProfileSettingsStore {
  const _StaticSettingsStore();
  @override
  Future<ProfilePlaybackSettings> loadPlaybackSettings(
          String profileId) async =>
      const ProfilePlaybackSettings(languageCode: 'en');

  @override
  Future<void> savePlaybackSettings(
    String profileId,
    ProfilePlaybackSettings settings,
  ) async {}
}
