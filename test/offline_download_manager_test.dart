import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/media_type.dart';
import 'package:cheriflix/core/models/playback_target.dart';
import 'package:cheriflix/core/services/offline_download_manager.dart';

void main() {
  test('accepts validated direct sources without a provider permission flag',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentLength = 4
        ..add(<int>[0, 0, 0, 1]);
      await request.response.close();
    });
    final root = await Directory.systemTemp.createTemp('cheriflix-offline-');
    final manager = await OfflineDownloadManager.open(rootDirectory: root);
    addTearDown(() async {
      manager.dispose();
      await server.close(force: true);
      try {
        if (await root.exists()) await root.delete(recursive: true);
      } on FileSystemException catch (_) {}
    });

    const key = OfflineMediaKey(tmdbId: 1, mediaType: MediaType.movie);
    await manager.enqueue(
      key: key,
      title: 'Direct media',
      target: PlaybackTarget(
        uri: Uri.parse(
          'http://${InternetAddress.loopbackIPv4.address}:${server.port}/video.mp4',
        ),
        providerKey: 'test',
        providerLabel: 'Test',
        providerIndex: 1,
        sourceKind: PlaybackSourceKind.file,
      ),
    );
    await _waitForStatus(manager, key, OfflineDownloadStatus.completed);
  });

  test('selects balanced HLS quality and exposes a validated local target',
      () async {
    final requestedPaths = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serverTask = server.listen((request) async {
      requestedPaths.add(request.uri.path);
      request.response.statusCode = HttpStatus.ok;
      switch (request.uri.path) {
        case '/master.m3u8':
          request.response.write('''#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080
1080.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720
720.m3u8
''');
        case '/720.m3u8':
          request.response.write('''#EXTM3U
#EXT-X-TARGETDURATION:4
#EXTINF:4,
one.ts
#EXTINF:4,
two.ts
#EXT-X-ENDLIST
''');
        case '/one.ts':
          request.response.add(List<int>.filled(188, 0x47));
        case '/two.ts':
          request.response.add(List<int>.filled(376, 0x47));
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final root = await Directory.systemTemp.createTemp('cheriflix-offline-');
    final manager = await OfflineDownloadManager.open(rootDirectory: root);
    addTearDown(() async {
      manager.dispose();
      await server.close(force: true);
      await serverTask.cancel();
      try {
        if (await root.exists()) await root.delete(recursive: true);
      } on FileSystemException catch (_) {}
    });

    const key = OfflineMediaKey(
      tmdbId: 44242,
      mediaType: MediaType.tv,
      seasonNumber: 1,
      episodeNumber: 2,
    );
    await manager.enqueue(
      key: key,
      title: 'Devious Maids S1 E2',
      target: PlaybackTarget(
        uri: Uri.parse(
          'http://${InternetAddress.loopbackIPv4.address}:${server.port}/master.m3u8',
        ),
        providerKey: 'direct-test',
        providerLabel: 'Authorised Test',
        providerIndex: 1,
        sourceKind: PlaybackSourceKind.hls,
        offlineStorageAllowed: true,
      ),
    );

    await _waitForStatus(manager, key, OfflineDownloadStatus.completed);
    expect(requestedPaths, containsAll(<String>['/master.m3u8', '/720.m3u8']));
    expect(requestedPaths, isNot(contains('/1080.m3u8')));
    final target = await manager.findCompletedTarget(key);
    expect(target, isNotNull);
    expect(target!.uri.scheme, 'file');
    expect(target.sourceKind, PlaybackSourceKind.hls);
    expect(await File.fromUri(target.uri).exists(), isTrue);
    expect(manager.recordFor(key)!.bytesDownloaded, 564);
  });
}

Future<void> _waitForStatus(
  OfflineDownloadManager manager,
  OfflineMediaKey key,
  OfflineDownloadStatus status,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (manager.recordFor(key)?.status == status) return;
    final failure = manager.recordFor(key);
    if (failure?.status == OfflineDownloadStatus.failed) {
      fail(failure?.error ?? 'Download failed');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail(
      'Timed out waiting for $status; current=${manager.recordFor(key)?.status}');
}
