import 'dart:async';
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

Future<void> main(List<String> args) async {
  final tmdbId = args.isNotEmpty ? int.parse(args[0]) : 385687;
  final mediaType = args.length > 1 && args[1].toLowerCase() == 'tv'
      ? MediaType.tv
      : MediaType.movie;
  final seasonNumber = args.length > 2 ? int.tryParse(args[2]) : null;
  final episodeNumber = args.length > 3 ? int.tryParse(args[3]) : null;

  const catalog = ProviderCatalog();
  final providerConfig = ProviderConfig.defaults();
  const settings = ProfilePlaybackSettings(languageCode: 'en');
  final sourceResolver = BuiltInSourceResolverService(
    providerCatalog: catalog,
    mediaCatalogService: null,
  );
  final playbackProvider = EmbedPlaybackProvider(
    providerCatalog: catalog,
    preferenceStore: _MemoryPreferenceStore(),
    profileSettingsStore: const _StaticSettingsStore(settings),
    providerConfig: providerConfig,
    probe: HttpEmbedProbe(),
    sourceResolverService: sourceResolver,
    allowEmbedFallback: false,
  );

  stdout.writeln('tmdbId=$tmdbId mediaType=${mediaType.name}');
  stdout.writeln(
    'seasonNumber=${seasonNumber ?? '-'} episodeNumber=${episodeNumber ?? '-'}',
  );

  final orderedProviders = catalog.orderedProviders(providerConfig);
  for (final provider in orderedProviders) {
    stdout.writeln(
      'provider=${provider.label} key=${provider.key} index=${provider.canonicalIndex}',
    );
    try {
      final target = await sourceResolver.resolveSpecificSource(
        profileId: 'diagnostic',
        tmdbId: tmdbId,
        mediaType: mediaType,
        providerConfig: providerConfig,
        settings: settings,
        providerIndex: provider.canonicalIndex,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        probeCandidate: false,
      );
      if (target == null) {
        stdout.writeln('  result=null');
        continue;
      }
      stdout.writeln(
        '  result=${target.sourceKind.name} direct=${target.isDirectPlayable}',
      );
      stdout.writeln('  uri=${target.uri}');
      if (target.httpHeaders.isNotEmpty) {
        stdout.writeln('  headers=${target.httpHeaders}');
      }
      if (target.uri.scheme == 'http' || target.uri.scheme == 'https') {
        await _checkReachability(target, prefix: '  ');
      }
    } catch (error, stackTrace) {
      stdout.writeln('  error=$error');
      stdout.writeln(stackTrace);
    }
  }

  stdout.writeln('---');
  stdout.writeln('Resolving through EmbedPlaybackProvider...');
  final chosenTarget = await playbackProvider.resolveTitle(
    profileId: 'diagnostic',
    tmdbId: tmdbId,
    mediaType: mediaType,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
  );

  if (chosenTarget == null) {
    stdout.writeln('chosenTarget=null');
    return;
  }

  stdout.writeln(
    'chosenTarget provider=${chosenTarget.providerLabel} kind=${chosenTarget.sourceKind.name}',
  );
  stdout.writeln('chosenTarget uri=${chosenTarget.uri}');
  if (chosenTarget.httpHeaders.isNotEmpty) {
    stdout.writeln('chosenTarget headers=${chosenTarget.httpHeaders}');
  }

  if (chosenTarget.uri.scheme == 'http' || chosenTarget.uri.scheme == 'https') {
    await _checkReachability(chosenTarget);
  }
}

Future<void> _checkReachability(
  PlaybackTarget target, {
  String prefix = '',
}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..badCertificateCallback = (_, __, ___) => false;
  try {
    final request = await client.openUrl('HEAD', target.uri);
    target.httpHeaders.forEach(request.headers.set);
    final response = await request.close();
    stdout.writeln('${prefix}reachable status=${response.statusCode}');
    stdout.writeln(
      '${prefix}reachable finalUri=${response.redirects.isEmpty ? target.uri : response.redirects.last.location}',
    );
  } catch (error, stackTrace) {
    stdout.writeln('${prefix}reachable error=$error');
    stdout.writeln(stackTrace);
  } finally {
    client.close(force: true);
  }
}

class _MemoryPreferenceStore implements ProviderPreferenceStore {
  int? _lastGoodProviderIndex;

  @override
  Future<int?> getLastGoodProviderIndex({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
  }) async {
    return _lastGoodProviderIndex;
  }

  @override
  Future<void> saveLastGoodProviderIndex({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
  }) async {
    _lastGoodProviderIndex = providerIndex;
  }
}

class _StaticSettingsStore implements ProfileSettingsStore {
  const _StaticSettingsStore(this.settings);

  final ProfilePlaybackSettings settings;

  @override
  Future<ProfilePlaybackSettings> loadPlaybackSettings(String profileId) async {
    return settings;
  }

  @override
  Future<void> savePlaybackSettings(
    String profileId,
    ProfilePlaybackSettings settings,
  ) async {}
}
