import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/playback_target.dart';
import 'package:cheriflix/core/services/direct_source_validator.dart';

void main() {
  test('rejects a valid-looking HLS manifest whose segment is forbidden',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      if (request.uri.path == '/stream.m3u8') {
        request.response.write('#EXTM3U\n#EXTINF:4,\nsegment.ts\n');
      } else {
        request.response.statusCode = HttpStatus.forbidden;
      }
      await request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
      await subscription.cancel();
    });
    final result = await HttpDirectSourceValidator().validate(
      PlaybackTarget(
        uri: Uri.parse(
          'http://${InternetAddress.loopbackIPv4.address}:${server.port}/stream.m3u8',
        ),
        providerKey: 'test',
        providerLabel: 'Test',
        providerIndex: 1,
        sourceKind: PlaybackSourceKind.hls,
      ),
    );
    expect(result.playable, isFalse);
    expect(result.stage, 'hls-segment');
  });

  test('accepts HLS only after a real media segment responds', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      if (request.uri.path == '/stream.m3u8') {
        request.response.write('#EXTM3U\n#EXTINF:4,\nsegment.ts\n');
      } else if (request.uri.path == '/segment.ts') {
        request.response.add(List<int>.filled(188, 0x47));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
      await subscription.cancel();
    });
    final result = await HttpDirectSourceValidator().validate(
      PlaybackTarget(
        uri: Uri.parse(
          'http://${InternetAddress.loopbackIPv4.address}:${server.port}/stream.m3u8',
        ),
        providerKey: 'test',
        providerLabel: 'Test',
        providerIndex: 1,
        sourceKind: PlaybackSourceKind.hls,
      ),
    );
    expect(result.playable, isTrue);
    expect(result.stage, 'hls-segment');
  });

  test('rejects HLS when the required encryption key fails', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      switch (request.uri.path) {
        case '/stream.m3u8':
          request.response.write('''#EXTM3U
#EXT-X-KEY:METHOD=AES-128,URI="key.bin"
#EXTINF:4,
segment.ts
''');
        case '/key.bin':
          request.response.statusCode = HttpStatus.forbidden;
        case '/segment.ts':
          request.response.add(List<int>.filled(188, 0x47));
      }
      await request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
      await subscription.cancel();
    });

    final result = await HttpDirectSourceValidator().validate(
      PlaybackTarget(
        uri: Uri.parse('http://127.0.0.1:${server.port}/stream.m3u8'),
        providerKey: 'test',
        providerLabel: 'Test',
        providerIndex: 1,
        sourceKind: PlaybackSourceKind.hls,
      ),
    );

    expect(result.playable, isFalse);
    expect(result.stage, 'hls-key');
    expect(result.reason, 'key-request-failed');
  });

  test('does not reject a source solely from non-AES key metadata', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      switch (request.uri.path) {
        case '/stream.m3u8':
          request.response.write('''#EXTM3U
#EXT-X-KEY:METHOD=SAMPLE-AES,URI="key.bin",KEYFORMAT="com.example.key"
#EXTINF:4,
segment.ts
''');
        case '/key.bin':
          request.response.statusCode = HttpStatus.forbidden;
        case '/segment.ts':
          request.response.add(List<int>.filled(188, 0x47));
      }
      await request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
      await subscription.cancel();
    });

    final result = await HttpDirectSourceValidator().validate(
      PlaybackTarget(
        uri: Uri.parse('http://127.0.0.1:${server.port}/stream.m3u8'),
        providerKey: 'test',
        providerLabel: 'Test',
        providerIndex: 1,
        sourceKind: PlaybackSourceKind.hls,
      ),
    );

    expect(result.playable, isTrue);
    expect(result.stage, 'hls-segment');
  });

  test('uses the final redirect URL as the child-playlist base', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      switch (request.uri.path) {
        case '/start.m3u8':
          request.response.redirect(
            Uri.parse('http://127.0.0.1:${server.port}/nested/master.m3u8'),
          );
        case '/nested/master.m3u8':
          request.response.write(
            '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nchild.m3u8\n',
          );
        case '/nested/child.m3u8':
          request.response.write('#EXTM3U\n#EXTINF:4,\nsegment.ts\n');
        case '/nested/segment.ts':
          request.response.add(List<int>.filled(188, 0x47));
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
      await subscription.cancel();
    });

    final result = await HttpDirectSourceValidator().validate(
      PlaybackTarget(
        uri: Uri.parse('http://127.0.0.1:${server.port}/start.m3u8'),
        providerKey: 'test',
        providerLabel: 'Test',
        providerIndex: 1,
        sourceKind: PlaybackSourceKind.hls,
      ),
    );

    expect(result.playable, isTrue);
    expect(result.details['manifestDepth'], 1);
  });
}
