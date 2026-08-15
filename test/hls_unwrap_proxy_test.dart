import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cheriflix/core/services/hls_unwrap_proxy.dart';

void main() {
  test('rewrites manifests and removes PNG cover bytes from TS segments',
      () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      if (request.uri.path == '/master.m3u8') {
        request.response.write('#EXTM3U\nchild.m3u8\n');
      } else if (request.uri.path == '/child.m3u8') {
        request.response.write('#EXTM3U\n#EXTINF:4,\nsegment.png\n');
      } else {
        request.response.add(<int>[
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
          0,
          0,
          0,
          0,
          73,
          69,
          78,
          68,
          174,
          66,
          96,
          130,
          0x47,
          0x40,
          0x00,
          0x10,
        ]);
      }
      await request.response.close();
    });

    final wrapped = await HlsUnwrapProxy.instance.wrap(
      Uri.parse('http://127.0.0.1:${upstream.port}/master.m3u8'),
    );
    final client = HttpClient();
    final master = await _read(client, wrapped);
    final childUri = Uri.parse(utf8.decode(master).split('\n')[1]);
    final child = await _read(client, childUri);
    final segmentUri = Uri.parse(utf8.decode(child).split('\n')[2]);
    final segment = await _read(client, segmentUri);

    expect(segment, <int>[0x47, 0x40, 0x00, 0x10]);
    client.close(force: true);
    await upstream.close(force: true);
  });

  test('sanitizes only the master and removes provider subtitle renditions',
      () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      request.response.headers.contentType =
          ContentType('application', 'vnd.apple.mpegurl');
      request.response.write('''#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",URI="https://cdn.test/audio.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",URI="https://cdn.test/subs.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=1200000,AUDIO="audio",SUBTITLES="subs"
https://cdn.test/video.m3u8
''');
      await request.response.close();
    });

    final wrapped = await HlsUnwrapProxy.instance.sanitizeMaster(
      Uri.parse('http://127.0.0.1:${upstream.port}/master.m3u8'),
      stripSubtitleTracks: true,
    );
    final client = HttpClient();
    final manifest = utf8.decode(await _read(client, wrapped));

    expect(manifest, contains('TYPE=AUDIO'));
    expect(manifest, isNot(contains('TYPE=SUBTITLES')));
    expect(manifest, isNot(contains('SUBTITLES="subs"')));
    expect(manifest, contains('https://cdn.test/video.m3u8'));
    expect(manifest, isNot(contains('127.0.0.1')));
    client.close(force: true);
    await upstream.close(force: true);
  });

  test('selects one TV-safe variant and retains switchable audio tracks',
      () async {
    final manifest = '''#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",LANGUAGE="it",DEFAULT=YES,URI="it.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",LANGUAGE="en",URI="en.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=1800000,RESOLUTION=854x480,AUDIO="audio"
480.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3500000,RESOLUTION=1280x720,AUDIO="audio"
720.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=5800000,RESOLUTION=1920x1080,AUDIO="audio"
1080.m3u8
''';
    final wrapped = await HlsUnwrapProxy.instance.sanitizeMaster(
      Uri.parse('https://provider.test/master.m3u8'),
      prefetchedManifest: manifest,
      selectSingleVariant: true,
      preferredAudioLanguage: 'en',
    );
    final client = HttpClient();
    final selected = utf8.decode(await _read(client, wrapped));

    expect('#EXT-X-STREAM-INF'.allMatches(selected), hasLength(1));
    expect('TYPE=AUDIO'.allMatches(selected), hasLength(2));
    expect(selected, contains('RESOLUTION=1280x720'));
    expect(selected, contains('LANGUAGE="en"'));
    expect(selected, contains('720.m3u8'));
    expect(selected, isNot(contains('480.m3u8')));
    expect(selected, isNot(contains('1080.m3u8')));
    expect(selected, contains('LANGUAGE="it"'));
    client.close(force: true);
  });

  test('proxies child playlists and preserves segment Range requests',
      () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    String? observedRange;
    var childManifestRequests = 0;
    upstream.listen((request) async {
      if (request.uri.path == '/child.m3u8') {
        childManifestRequests += 1;
        request.response.headers.contentType =
            ContentType('application', 'vnd.apple.mpegurl');
        request.response.write('#EXTM3U\n#EXTINF:4,\nsegment.ts\n');
      } else {
        observedRange = request.headers.value(HttpHeaders.rangeHeader);
        request.response.statusCode = HttpStatus.partialContent;
        request.response.add(<int>[0x47, 0x40, 0x00, 0x10]);
      }
      await request.response.close();
    });

    final origin = 'http://127.0.0.1:${upstream.port}';
    final wrapped = await HlsUnwrapProxy.instance.sanitizeMaster(
      Uri.parse('$origin/master.m3u8'),
      prefetchedManifest: '#EXTM3U\n$origin/child.m3u8\n',
      proxyChildren: true,
    );
    final client = HttpClient();
    final master = utf8.decode(await _read(client, wrapped));
    final childUri = Uri.parse(master.split('\n')[1]);
    expect(childUri.host, '127.0.0.1');
    final child = utf8.decode(await _read(client, childUri));
    expect(utf8.decode(await _read(client, childUri)), child);
    expect(childManifestRequests, 1);
    final segmentUri = Uri.parse(child.split('\n')[2]);
    final request = await client.getUrl(segmentUri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-2047');
    final response = await request.close();
    final bytes = await response
        .fold<List<int>>(<int>[], (buffer, chunk) => buffer..addAll(chunk));

    expect(response.statusCode, HttpStatus.partialContent);
    expect(observedRange, 'bytes=0-2047');
    expect(bytes, <int>[0x47, 0x40, 0x00, 0x10]);
    client.close(force: true);
    await upstream.close(force: true);
  });

  test('serves independent HLS requests concurrently', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      if (request.uri.path == '/slow.ts') {
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
      request.response.add(<int>[0x47]);
      await request.response.close();
    });

    final origin = 'http://127.0.0.1:${upstream.port}';
    final wrapped = await HlsUnwrapProxy.instance.sanitizeMaster(
      Uri.parse('$origin/master.m3u8'),
      prefetchedManifest: '#EXTM3U\n$origin/slow.ts\n$origin/fast.ts\n',
      proxyChildren: true,
    );
    final client = HttpClient();
    final lines = utf8.decode(await _read(client, wrapped)).split('\n');
    final slow = _read(client, Uri.parse(lines[1]));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final fastWatch = Stopwatch()..start();
    final fast = await _read(client, Uri.parse(lines[2]));
    fastWatch.stop();

    expect(fast, <int>[0x47]);
    expect(fastWatch.elapsed, lessThan(const Duration(milliseconds: 300)));
    expect(await slow, <int>[0x47]);
    client.close(force: true);
    await upstream.close(force: true);
  });

  test('does not evict an actively used playback token', () async {
    final first = await HlsUnwrapProxy.instance.sanitizeMaster(
      Uri.parse('https://active.example/master.m3u8'),
      prefetchedManifest: '#EXTM3U\n#EXTINF:4,\nsegment.ts\n',
      proxyChildren: true,
    );
    final client = HttpClient();
    for (var index = 0; index < 60; index += 1) {
      await HlsUnwrapProxy.instance.sanitizeMaster(
        Uri.parse('https://background-$index.example/master.m3u8'),
        prefetchedManifest: '#EXTM3U\n#EXTINF:4,\nsegment.ts\n',
        proxyChildren: true,
      );
      if (index.isEven) {
        expect(utf8.decode(await _read(client, first)), startsWith('#EXTM3U'));
      }
    }

    expect(utf8.decode(await _read(client, first)), startsWith('#EXTM3U'));
    client.close(force: true);
  });
}

Future<List<int>> _read(HttpClient client, Uri uri) async {
  final response = await (await client.getUrl(uri)).close();
  expect(response.statusCode, HttpStatus.ok, reason: uri.toString());
  return response
      .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
}
