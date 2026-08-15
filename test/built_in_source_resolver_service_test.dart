import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/home_catalog_data.dart';
import 'package:cheriflix/core/models/just_released_catalog.dart';
import 'package:cheriflix/core/models/media_summary.dart';
import 'package:cheriflix/core/models/media_type.dart';
import 'package:cheriflix/core/models/playback_target.dart';
import 'package:cheriflix/core/models/profile_playback_settings.dart';
import 'package:cheriflix/core/models/provider_config.dart';
import 'package:cheriflix/core/services/built_in_source_resolver_service.dart';
import 'package:cheriflix/core/services/media_catalog_service.dart';

void main() {
  group('BuiltInSourceResolverService', () {
    test('extracts a direct HLS stream from Vidsrc-family pages', () async {
      final httpClient = _FakeBuiltInResolverHttpClient(
        onGet: (uri, headers) {
          switch (uri.toString()) {
            case 'https://vsembed.ru/embed/movie/385687?autoplay=1&mute=1':
              return const BuiltInResolverResponse(
                statusCode: 200,
                body: '<iframe id="player_iframe" src="/rcp/abc"></iframe>',
              );
            case 'https://vsembed.ru/rcp/abc':
              expect(
                headers['Referer'],
                'https://vsembed.ru/embed/movie/385687?autoplay=1&mute=1',
              );
              return const BuiltInResolverResponse(
                statusCode: 200,
                body: "src: '/prorcp/stream123'",
              );
            case 'https://vsembed.ru/prorcp/stream123':
              expect(headers['Referer'], 'https://vsembed.ru/rcp/abc');
              return const BuiltInResolverResponse(
                statusCode: 200,
                body:
                    'Playerjs({ file: "https://cdn.example.com/master.m3u8", });',
              );
          }

          fail('Unexpected GET: $uri');
        },
      );

      final service = BuiltInSourceResolverService(httpClient: httpClient);
      final target = await service.resolveSpecificSource(
        profileId: 'profile-1',
        tmdbId: 385687,
        mediaType: MediaType.movie,
        providerConfig: ProviderConfig.defaults(),
        settings: const ProfilePlaybackSettings(languageCode: 'en'),
        providerIndex: 13,
      );

      expect(target, isNotNull);
      expect(target!.uri, Uri.parse('https://cdn.example.com/master.m3u8'));
      expect(target.providerKey, 'vsembed');
      expect(target.sourceKind, PlaybackSourceKind.hls);
      expect(target.httpHeaders['Referer'], 'https://vsembed.ru/rcp/abc');
    });

    test('extracts a direct stream from the Videasy API flow', () async {
      final httpClient = _FakeBuiltInResolverHttpClient(
        onGet: (uri, headers) {
          expect(uri.host, 'api.videasy.net');
          expect(uri.path, '/myflixerzupcloud/sources-with-title');
          expect(uri.queryParameters['tmdbId'], '385687');
          expect(uri.queryParameters['title'], 'Test Movie');
          return const BuiltInResolverResponse(
            statusCode: 200,
            body: 'encrypted-payload',
          );
        },
        onPostJson: (uri, body, headers) {
          expect(uri.toString(), 'https://enc-dec.app/api/dec-videasy');
          expect(body, <String, Object?>{
            'text': 'encrypted-payload',
            'id': '385687',
          });
          return BuiltInResolverResponse(
            statusCode: 200,
            body: jsonEncode(
              <String, Object?>{
                'result': jsonEncode(
                  <String, Object?>{
                    'sources': <Map<String, String>>[
                      <String, String>{
                        'url':
                            'https://streams.example.com/videasy/master.m3u8',
                      },
                    ],
                  },
                ),
              },
            ),
          );
        },
      );
      final service = BuiltInSourceResolverService(
        httpClient: httpClient,
        mediaCatalogService: _FakeMediaCatalogService(
          summary: MediaSummary(
            tmdbId: 385687,
            mediaType: MediaType.movie,
            title: 'Test Movie',
            releaseDate: DateTime(2024, 1, 1),
          ),
        ),
      );

      final target = await service.resolveSpecificSource(
        profileId: 'profile-1',
        tmdbId: 385687,
        mediaType: MediaType.movie,
        providerConfig: ProviderConfig.defaults(),
        settings: const ProfilePlaybackSettings(languageCode: 'en'),
        providerIndex: 3,
      );

      expect(target, isNotNull);
      expect(
        target!.uri,
        Uri.parse('https://streams.example.com/videasy/master.m3u8'),
      );
      expect(target.providerKey, 'videasy');
      expect(target.sourceKind, PlaybackSourceKind.hls);
      expect(target.httpHeaders['Referer'], 'https://player.videasy.net/');
    });

    test('resolves the VixSrc episode API to its native HLS playlist',
        () async {
      final httpClient = _FakeBuiltInResolverHttpClient(
        onGet: (uri, headers) {
          if (uri.toString() == 'https://vixsrc.to/api/tv/44242/1/2') {
            expect(
              headers['Referer'],
              'https://vixsrc.to/tv/44242/1/2?lang=en&autoplay=true',
            );
            return const BuiltInResolverResponse(
              statusCode: 200,
              body: '{"src":"/embed/251094?token=page-token&lang=en"}',
            );
          }
          if (uri.toString() ==
              'https://vixsrc.to/embed/251094?token=page-token&lang=en') {
            expect(
              headers['Referer'],
              'https://vixsrc.to/tv/44242/1/2?lang=en&autoplay=true',
            );
            return const BuiltInResolverResponse(
              statusCode: 200,
              body: '''
<script>
window.masterPlaylist = {
  params: {'token': 'media-token', 'expires': '1791551009', 'asn': ''},
  url: 'https://vixsrc.to/playlist/251094',
};
</script>
''',
            );
          }
          if (uri.host == 'vixsrc.to' && uri.path == '/playlist/251094') {
            expect(
              headers['Referer'],
              'https://vixsrc.to/embed/251094?token=page-token&lang=en',
            );
            return const BuiltInResolverResponse(
              statusCode: 200,
              body: '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1200000
https://cdn.example.com/video.m3u8
''',
            );
          }
          fail('Unexpected GET: $uri');
        },
      );
      final service = BuiltInSourceResolverService(httpClient: httpClient);

      final target = await service.resolveSpecificSource(
        profileId: 'profile-1',
        tmdbId: 44242,
        mediaType: MediaType.tv,
        providerConfig: ProviderConfig.defaults(),
        settings: const ProfilePlaybackSettings(languageCode: 'en'),
        providerIndex: 23,
        seasonNumber: 1,
        episodeNumber: 2,
      );

      expect(target, isNotNull);
      expect(target!.providerKey, 'vixsrc');
      expect(target.sourceKind, PlaybackSourceKind.hls);
      expect(target.uri.host, '127.0.0.1');
      final upstream = Uri.parse(target.uri.queryParameters['url']!);
      expect(upstream.host, 'vixsrc.to');
      expect(upstream.path, '/playlist/251094');
      expect(upstream.queryParameters['token'], 'media-token');
      expect(upstream.queryParameters['h'], '1');
      expect(upstream.queryParameters['lang'], 'en');
      expect(target.expiresAtEpochMs, 1791551009000);
      expect(
        target.httpHeaders['Referer'],
        'https://vixsrc.to/embed/251094?token=page-token&lang=en',
      );
      expect(target.httpHeaders['Origin'], 'https://vixsrc.to');
    });

    test('rejects forbidden and malformed direct HLS manifests', () {
      final uri = Uri.parse('https://stream.example.com/master.m3u8?token=x');

      expect(
        isLikelyPlayableDirectManifestResponse(
          uri: uri,
          statusCode: 403,
          body: '<html>Forbidden</html>',
        ),
        isFalse,
      );
      expect(
        isLikelyPlayableDirectManifestResponse(
          uri: uri,
          statusCode: 200,
          body: '<html>Not a manifest</html>',
        ),
        isFalse,
      );
    });

    test('accepts valid HLS and DASH manifests', () {
      expect(
        isLikelyPlayableDirectManifestResponse(
          uri: Uri.parse('https://stream.example.com/master.m3u8'),
          statusCode: 200,
          body: '#EXTM3U\n#EXT-X-VERSION:3',
        ),
        isTrue,
      );
      expect(
        isLikelyPlayableDirectManifestResponse(
          uri: Uri.parse('https://stream.example.com/manifest.mpd'),
          statusCode: 200,
          body: '<?xml version="1.0"?><MPD type="static"></MPD>',
        ),
        isTrue,
      );
    });
  });
}

class _FakeBuiltInResolverHttpClient implements BuiltInResolverHttpClient {
  _FakeBuiltInResolverHttpClient({
    required this.onGet,
    this.onPostJson,
  });

  final BuiltInResolverResponse Function(Uri uri, Map<String, String> headers)
      onGet;
  final BuiltInResolverResponse Function(
    Uri uri,
    Map<String, Object?> body,
    Map<String, String> headers,
  )? onPostJson;

  @override
  Future<BuiltInResolverResponse> get(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    return onGet(uri, headers);
  }

  @override
  Future<BuiltInResolverResponse> postJson(
    Uri uri,
    Map<String, Object?> body, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    final handler = onPostJson;
    if (handler == null) {
      fail('Unexpected POST: $uri');
    }
    return handler(uri, body, headers);
  }
}

class _FakeMediaCatalogService implements MediaCatalogService {
  _FakeMediaCatalogService({required this.summary});

  final MediaSummary summary;

  @override
  Future<MediaSummary> fetchTitleDetails({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) async {
    return summary;
  }

  @override
  Future<HomeCatalogData> fetchHomeCatalog({
    required String languageCode,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<JustReleasedCatalog> fetchJustReleasedCatalog({
    required String languageCode,
    required DateTime releasedAfter,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<MediaSummary>> searchTitles({
    required String query,
    required String languageCode,
  }) {
    throw UnimplementedError();
  }
}
