import 'dart:io';
import 'dart:typed_data';

import 'package:cheriflix/services/thumbnail_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThumbnailCacheManager', () {
    test('stores and retrieves exact thumbnail by exact timestamp', () async {
      final root = await Directory.systemTemp.createTemp('thumb-cache-test-1');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final manager = ThumbnailCacheManager(cacheRootDirectory: root);
      await manager.initialize();

      await manager.storeThumbnail(
        videoId: 'video-a',
        videoPath: 'C:/videos/a.mp4',
        timestampMs: 1234,
        width: 320,
        height: 180,
        exact: true,
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      );

      final exactFile = await manager.getCachedThumbnailFile(
        videoId: 'video-a',
        timeMs: 1234,
        width: 320,
        height: 180,
        exact: true,
      );
      expect(exactFile, isNotNull);
      expect(await exactFile!.exists(), isTrue);
    });

    test('returns nearest preview thumbnail within distance tolerance',
        () async {
      final root = await Directory.systemTemp.createTemp('thumb-cache-test-2');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final manager = ThumbnailCacheManager(cacheRootDirectory: root);
      await manager.initialize();

      await manager.storeThumbnail(
        videoId: 'video-b',
        videoPath: 'C:/videos/b.mp4',
        timestampMs: 1000,
        width: 320,
        height: 180,
        exact: false,
        bytes: Uint8List.fromList(<int>[4, 5, 6]),
      );
      await manager.storeThumbnail(
        videoId: 'video-b',
        videoPath: 'C:/videos/b.mp4',
        timestampMs: 2000,
        width: 320,
        height: 180,
        exact: false,
        bytes: Uint8List.fromList(<int>[7, 8, 9]),
      );

      final hit = await manager.getCachedThumbnailFile(
        videoId: 'video-b',
        timeMs: 1900,
        width: 320,
        height: 180,
        exact: false,
        maxPreviewDistanceMs: 500,
      );
      expect(hit, isNotNull);
      expect(hit!.path.contains('t2000_'), isTrue);
    });

    test('evicts videos inactive for over one hour', () async {
      final root = await Directory.systemTemp.createTemp('thumb-cache-test-3');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      var now = DateTime(2026, 4, 6, 10, 0, 0);
      final manager = ThumbnailCacheManager(
        cacheRootDirectory: root,
        now: () => now,
      );
      await manager.initialize();

      await manager.storeThumbnail(
        videoId: 'video-old',
        videoPath: 'C:/videos/old.mp4',
        timestampMs: 0,
        width: 320,
        height: 180,
        exact: false,
        bytes: Uint8List.fromList(<int>[1]),
      );

      now = now.add(const Duration(hours: 2));
      await manager.evictInactiveAndOverflow();

      final hit = await manager.getCachedThumbnailFile(
        videoId: 'video-old',
        timeMs: 0,
        width: 320,
        height: 180,
        exact: false,
      );
      expect(hit, isNull);
    });

    test('enforces max 5 cached videos using LRU order', () async {
      final root = await Directory.systemTemp.createTemp('thumb-cache-test-4');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      var now = DateTime(2026, 4, 6, 10, 0, 0);
      final manager = ThumbnailCacheManager(
        cacheRootDirectory: root,
        maxVideosCached: 5,
        now: () => now,
      );
      await manager.initialize();

      for (var i = 0; i < 6; i += 1) {
        await manager.storeThumbnail(
          videoId: 'video-$i',
          videoPath: 'C:/videos/$i.mp4',
          timestampMs: 0,
          width: 320,
          height: 180,
          exact: false,
          bytes: Uint8List.fromList(<int>[i]),
        );
        now = now.add(const Duration(minutes: 1));
      }

      final oldestHit = await manager.getCachedThumbnailFile(
        videoId: 'video-0',
        timeMs: 0,
        width: 320,
        height: 180,
        exact: false,
      );
      final newestHit = await manager.getCachedThumbnailFile(
        videoId: 'video-5',
        timeMs: 0,
        width: 320,
        height: 180,
        exact: false,
      );

      expect(oldestHit, isNull);
      expect(newestHit, isNotNull);
    });

    test('trimMemory clears memory entries without deleting disk cache',
        () async {
      final root = await Directory.systemTemp.createTemp('thumb-cache-test-5');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final manager = ThumbnailCacheManager(cacheRootDirectory: root);
      await manager.initialize();

      await manager.storeThumbnail(
        videoId: 'video-memory',
        videoPath: 'C:/videos/memory.mp4',
        timestampMs: 0,
        width: 320,
        height: 180,
        exact: false,
        bytes: Uint8List.fromList(<int>[10, 11, 12]),
      );
      expect(manager.debugMemoryEntryCount, 1);

      await manager.trimMemory();
      expect(manager.debugMemoryEntryCount, 0);

      final diskHit = await manager.getCachedThumbnailFile(
        videoId: 'video-memory',
        timeMs: 0,
        width: 320,
        height: 180,
        exact: false,
      );
      expect(diskHit, isNotNull);
      expect(await diskHit!.exists(), isTrue);
    });

    test('bounds thumbnail memory by bytes as well as entry count', () async {
      final root = await Directory.systemTemp.createTemp('thumb-cache-bytes');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final manager = ThumbnailCacheManager(
        cacheRootDirectory: root,
        memoryEntryLimit: 100,
        memoryByteLimit: 5,
      );

      for (var i = 0; i < 3; i += 1) {
        await manager.storeThumbnail(
          videoId: 'video-bytes',
          videoPath: '/video',
          timestampMs: i,
          width: 1,
          height: 1,
          exact: true,
          bytes: Uint8List.fromList(<int>[i, i]),
        );
      }

      expect(manager.debugMemoryBytes, lessThanOrEqualTo(5));
      expect(manager.debugMemoryEntryCount, 2);
    });

    test('batches cache-hit manifest persistence until explicit flush',
        () async {
      final root = await Directory.systemTemp.createTemp('thumb-cache-flush');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final manager = ThumbnailCacheManager(
        cacheRootDirectory: root,
        manifestFlushInterval: const Duration(minutes: 1),
      );
      await manager.storeThumbnail(
        videoId: 'video-flush',
        videoPath: '/video',
        timestampMs: 0,
        width: 1,
        height: 1,
        exact: true,
        bytes: Uint8List.fromList(<int>[1]),
      );

      await manager.getCachedThumbnailBytes(
        videoId: 'video-flush',
        timeMs: 0,
        width: 1,
        height: 1,
        exact: true,
      );
      expect(manager.debugPendingManifestCount, 1);

      await manager.flushPendingManifests();
      expect(manager.debugPendingManifestCount, 0);
      await manager.dispose();
    });
  });
}
