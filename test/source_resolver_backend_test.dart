// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/media_type.dart';
import 'package:cheriflix/core/models/profile_playback_settings.dart';
import 'package:cheriflix/core/models/provider_config.dart';
import 'package:cheriflix/core/services/source_resolver_service.dart'
    as app_client;

import '../backend/source_resolver_service/lib/source_resolver_service.dart'
    as backend;

void main() {
  test('SourceResolverHttpService rejects invalid JSON without crashing',
      () async {
    final service = backend.SourceResolverHttpService(
      resolver: backend.SourceResolver(),
    );

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });
    final serverLoopErrors = <Object>[];
    () async {
      try {
        await for (final request in server) {
          await service.handle(request);
        }
      } catch (error) {
        serverLoopErrors.add(error);
      }
    }();

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final badRequest = await client.postUrl(
      Uri.parse('http://127.0.0.1:${server.port}/v1/sources/resolve'),
    );
    badRequest.headers.contentType = ContentType.json;
    badRequest.write('{bad-json');
    final badResponse = await badRequest.close();
    final badBody = await utf8.decoder.bind(badResponse).join();

    expect(badResponse.statusCode, HttpStatus.badRequest);
    expect(badBody, contains('Invalid JSON payload'));

    final healthRequest = await client
        .getUrl(Uri.parse('http://127.0.0.1:${server.port}/health'));
    final healthResponse = await healthRequest.close();
    final healthBody = await utf8.decoder.bind(healthResponse).join();

    expect(healthResponse.statusCode, HttpStatus.ok);
    expect(jsonDecode(healthBody), <String, dynamic>{'ok': true});
    expect(serverLoopErrors, isEmpty);
  });

  test('SourceResolver caches a successful target on repeated resolves',
      () async {
    final probe = _RecordingProbe((target) => target.providerKey == 'videasy');
    final service = backend.SourceResolverHttpService(
      resolver: backend.SourceResolver(
        targetExtractorRegistry:
            backend.ProviderPlaybackTargetExtractorRegistry(
          extractors: <String, backend.ProviderPlaybackTargetExtractor>{
            'videasy': _directTargetForProvider,
          },
        ),
        probe: probe,
      ),
    );

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });
    () async {
      await for (final request in server) {
        await service.handle(request);
      }
    }();

    final client = app_client.HttpSourceResolverService(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    const settings = ProfilePlaybackSettings(languageCode: 'en');
    final providerConfig = ProviderConfig(
      providerPriority: const <String>[
        'vidsrc',
        'vidsrc_embed',
        'videasy',
      ],
      providerTimeoutSeconds: 5,
      disabledProviders: const <String>{
        'vidlink',
        '111movies',
        'vidzee',
        '2embed',
        'mapple',
        'primesrc',
        'multiembed',
        'autoembed',
        'embedsu',
        'vsembed',
        'vsrcsu',
        'vidsrcme',
        'hdrezka',
      },
    );

    final first = await client.resolveTitle(
      profileId: 'profile-1',
      tmdbId: 385687,
      mediaType: MediaType.movie,
      providerConfig: providerConfig,
      settings: settings,
    );

    expect(first, isNotNull);
    expect(first!.providerKey, 'videasy');
    final attemptsAfterFirst = probe.attemptedTargets.length;

    final second = await client.resolveTitle(
      profileId: 'profile-1',
      tmdbId: 385687,
      mediaType: MediaType.movie,
      providerConfig: providerConfig,
      settings: settings,
    );

    expect(second, isNotNull);
    expect(second!.providerKey, 'videasy');
    expect(probe.attemptedTargets.length, attemptsAfterFirst);
  });

  test('SourceResolver skips the current provider when resolving next source',
      () async {
    final service = backend.SourceResolverHttpService(
      resolver: backend.SourceResolver(
        targetExtractorRegistry:
            backend.ProviderPlaybackTargetExtractorRegistry(
          extractors: <String, backend.ProviderPlaybackTargetExtractor>{
            'videasy': _directTargetForProvider,
          },
        ),
        probe: _RecordingProbe((target) => target.providerKey == 'videasy'),
      ),
    );

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });
    () async {
      await for (final request in server) {
        await service.handle(request);
      }
    }();

    final client = app_client.HttpSourceResolverService(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    const settings = ProfilePlaybackSettings(languageCode: 'en');
    final providerConfig = ProviderConfig(
      providerPriority: const <String>[
        'vidsrc',
        'vidsrc_embed',
        'videasy',
      ],
      providerTimeoutSeconds: 5,
      disabledProviders: const <String>{},
    );

    final target = await client.resolveNextSource(
      profileId: 'profile-1',
      tmdbId: 385687,
      mediaType: MediaType.movie,
      providerConfig: providerConfig,
      settings: settings,
      currentProviderIndex: 2,
      probeCandidates: true,
    );

    expect(target, isNotNull);
    expect(target!.providerKey, 'videasy');
    expect(target.providerIndex, 3);
  });

  test('SourceResolver honors expiry-aware cache invalidation', () async {
    var now = DateTime.utc(2026, 3, 23, 10, 0);
    var extractionCount = 0;
    final resolver = backend.SourceResolver(
      clock: () => now,
      targetExtractorRegistry: backend.ProviderPlaybackTargetExtractorRegistry(
        extractors: <String, backend.ProviderPlaybackTargetExtractor>{
          'videasy': ({
            required provider,
            required pageUri,
            required request,
          }) async {
            extractionCount += 1;
            return backend.PlaybackTarget(
              uri:
                  Uri.parse('https://streams.example.com/${provider.key}.m3u8'),
              providerKey: provider.key,
              providerLabel: provider.label,
              providerIndex: provider.canonicalIndex,
              sourceKind: backend.PlaybackSourceKind.hls,
              pageUri: pageUri,
              expiresAtEpochMs:
                  now.add(const Duration(seconds: 1)).millisecondsSinceEpoch,
            );
          },
        },
      ),
      probe: _RecordingProbe((_) => true),
    );

    final request = backend.SourceResolverRequest(
      profileId: 'profile-1',
      tmdbId: 385687,
      mediaType: 'movie',
      providerConfig: const backend.ProviderConfig(
        providerPriority: <String>['videasy'],
        providerTimeoutSeconds: 5,
        disabledProviders: <String>{},
      ),
      settings: const backend.ProfilePlaybackSettings(languageCode: 'en'),
    );

    final first = await resolver.resolveTitle(request);
    expect(first, isNotNull);
    expect(extractionCount, 1);

    now = now.add(const Duration(milliseconds: 500));
    final second = await resolver.resolveTitle(request);
    expect(second, isNotNull);
    expect(extractionCount, 1);

    now = now.add(const Duration(seconds: 2));
    final third = await resolver.resolveTitle(request);
    expect(third, isNotNull);
    expect(extractionCount, 2);
  });

  test('SourceResolver returns a retry delay after all providers fail',
      () async {
    final resolver = backend.SourceResolver();
    const request = backend.SourceResolverRequest(
      profileId: 'profile-1',
      tmdbId: 385687,
      mediaType: 'movie',
      providerConfig: backend.ProviderConfig(
        providerPriority: <String>[
          'vidsrc',
          'vidsrc_embed',
          'videasy',
        ],
        providerTimeoutSeconds: 5,
        disabledProviders: <String>{
          'vidlink',
          '111movies',
          'vidzee',
          '2embed',
          'mapple',
          'primesrc',
          'multiembed',
          'autoembed',
          'embedsu',
          'vsembed',
          'vsrcsu',
          'vidsrcme',
          'hdrezka',
        },
      ),
      settings: backend.ProfilePlaybackSettings(languageCode: 'en'),
    );

    await resolver.reportSourceFailure(
      const backend.SourceResolverRequest(
        profileId: 'profile-1',
        tmdbId: 385687,
        mediaType: 'movie',
        providerConfig: backend.ProviderConfig(
          providerPriority: <String>['vidsrc'],
          providerTimeoutSeconds: 5,
          disabledProviders: <String>{},
        ),
        settings: backend.ProfilePlaybackSettings(languageCode: 'en'),
        providerIndex: 6,
        kind: backend.SourceFailureKind.probe,
      ),
    );
    await resolver.reportSourceFailure(
      const backend.SourceResolverRequest(
        profileId: 'profile-1',
        tmdbId: 385687,
        mediaType: 'movie',
        providerConfig: backend.ProviderConfig(
          providerPriority: <String>['vidsrc_embed'],
          providerTimeoutSeconds: 5,
          disabledProviders: <String>{},
        ),
        settings: backend.ProfilePlaybackSettings(languageCode: 'en'),
        providerIndex: 2,
        kind: backend.SourceFailureKind.probe,
      ),
    );
    await resolver.reportSourceFailure(
      const backend.SourceResolverRequest(
        profileId: 'profile-1',
        tmdbId: 385687,
        mediaType: 'movie',
        providerConfig: backend.ProviderConfig(
          providerPriority: <String>['videasy'],
          providerTimeoutSeconds: 5,
          disabledProviders: <String>{},
        ),
        settings: backend.ProfilePlaybackSettings(languageCode: 'en'),
        providerIndex: 3,
        kind: backend.SourceFailureKind.probe,
      ),
    );

    final retryDelay = await resolver.estimateNextSourceRetryDelay(request);

    expect(retryDelay, isNotNull);
    expect(retryDelay!.inMilliseconds, greaterThan(0));
  });
}

Future<backend.PlaybackTarget?> _directTargetForProvider({
  required backend.ProviderDescriptor provider,
  required Uri pageUri,
  required backend.SourceResolverRequest request,
}) async {
  return backend.PlaybackTarget(
    uri: Uri.parse('https://streams.example.com/${provider.key}.m3u8'),
    providerKey: provider.key,
    providerLabel: provider.label,
    providerIndex: provider.canonicalIndex,
    sourceKind: backend.PlaybackSourceKind.hls,
    httpHeaders: <String, String>{
      'Referer': pageUri.toString(),
      'Origin': '${pageUri.scheme}://${pageUri.host}',
    },
    pageUri: pageUri,
  );
}

class _RecordingProbe implements backend.PlaybackTargetProbe {
  _RecordingProbe(this._decision);

  final bool Function(backend.PlaybackTarget target) _decision;
  final List<backend.PlaybackTarget> attemptedTargets =
      <backend.PlaybackTarget>[];

  @override
  Future<bool> canLoad(
    backend.PlaybackTarget target,
    Duration timeout,
  ) async {
    attemptedTargets.add(target);
    return _decision(target);
  }
}
