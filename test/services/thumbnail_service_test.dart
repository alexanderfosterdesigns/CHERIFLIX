import 'dart:async';
import 'dart:io';

import 'package:cheriflix/services/native_thumbnail_extractor.dart';
import 'package:cheriflix/services/thumbnail_cache_manager.dart';
import 'package:cheriflix/services/thumbnail_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeNativeThumbnailExtractor extends NativeThumbnailExtractor {
  _FakeNativeThumbnailExtractor()
      : super(channel: const MethodChannel('cheriflix/test_thumbnail'));

  int singleFrameCalls = 0;
  final List<List<int>> batchFrameCalls = <List<int>>[];

  @override
  Future<NativeThumbnailResult?> extractFrame({
    required String sourceUri,
    required int timeMs,
    required int width,
    required int height,
    required bool exact,
    Map<String, String> httpHeaders = const <String, String>{},
    int jpegQuality = 88,
  }) async {
    singleFrameCalls += 1;
    return NativeThumbnailResult(
      bytes: Uint8List.fromList(<int>[1, 2, 3, timeMs % 255]),
      requestedTimeMs: timeMs,
      actualTimeMs: timeMs,
      exact: exact,
      latencyMs: 1,
    );
  }

  @override
  Future<List<NativeThumbnailResult>> extractFrames({
    required String sourceUri,
    required List<int> timeMsList,
    required int width,
    required int height,
    required bool exact,
    Map<String, String> httpHeaders = const <String, String>{},
    int jpegQuality = 88,
  }) async {
    batchFrameCalls.add(List<int>.from(timeMsList));
    return timeMsList
        .map(
          (timeMs) => NativeThumbnailResult(
            bytes: Uint8List.fromList(<int>[7, 8, 9, timeMs % 255]),
            requestedTimeMs: timeMs,
            actualTimeMs: timeMs,
            exact: exact,
            latencyMs: 1,
          ),
        )
        .toList(growable: false);
  }
}

class _BlockingNativeThumbnailExtractor extends NativeThumbnailExtractor {
  _BlockingNativeThumbnailExtractor()
      : super(channel: const MethodChannel('cheriflix/test_thumbnail'));

  int singleFrameCalls = 0;
  final List<List<int>> batchFrameCalls = <List<int>>[];
  final List<_PendingBatch> pendingBatches = <_PendingBatch>[];
  Completer<NativeThumbnailResult?>? pendingSingle;

  @override
  Future<NativeThumbnailResult?> extractFrame({
    required String sourceUri,
    required int timeMs,
    required int width,
    required int height,
    required bool exact,
    Map<String, String> httpHeaders = const <String, String>{},
    int jpegQuality = 88,
  }) {
    singleFrameCalls += 1;
    final completer = pendingSingle ??= Completer<NativeThumbnailResult?>();
    return completer.future;
  }

  @override
  Future<List<NativeThumbnailResult>> extractFrames({
    required String sourceUri,
    required List<int> timeMsList,
    required int width,
    required int height,
    required bool exact,
    Map<String, String> httpHeaders = const <String, String>{},
    int jpegQuality = 88,
  }) {
    batchFrameCalls.add(List<int>.from(timeMsList));
    final completer = Completer<List<NativeThumbnailResult>>();
    pendingBatches.add(_PendingBatch(timeMsList, completer));
    return completer.future;
  }

  void completeSingle() {
    final completer = pendingSingle;
    if (completer == null || completer.isCompleted) {
      return;
    }
    completer.complete(
      NativeThumbnailResult(
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        requestedTimeMs: 5000,
        actualTimeMs: 5000,
        exact: false,
        latencyMs: 1,
      ),
    );
  }

  void completeNextBatch() {
    if (pendingBatches.isEmpty) {
      return;
    }
    final pending = pendingBatches.removeAt(0);
    pending.completer.complete(
      pending.timeMsList
          .map(
            (timeMs) => NativeThumbnailResult(
              bytes: Uint8List.fromList(<int>[7, 8, 9, timeMs % 255]),
              requestedTimeMs: timeMs,
              actualTimeMs: timeMs,
              exact: false,
              latencyMs: 1,
            ),
          )
          .toList(growable: false),
    );
  }

  void completeAllBatches() {
    while (pendingBatches.isNotEmpty) {
      completeNextBatch();
    }
  }
}

class _PendingBatch {
  const _PendingBatch(this.timeMsList, this.completer);

  final List<int> timeMsList;
  final Completer<List<NativeThumbnailResult>> completer;
}

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < timeout) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for async thumbnail work.');
}

Future<void> _deleteDirectoryWhenUnlocked(Directory directory) async {
  for (var attempt = 0; attempt < 8; attempt += 1) {
    if (!await directory.exists()) {
      return;
    }
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 7) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}

void main() {
  group('ThumbnailService direct sessions', () {
    test('invalidates cached thumbnails when the source signature changes',
        () async {
      final root = await Directory.systemTemp.createTemp('thumb-service-1');
      final extractor = _FakeNativeThumbnailExtractor();
      final service = ThumbnailService(
        cacheManager: ThumbnailCacheManager(cacheRootDirectory: root),
        nativeExtractor: extractor,
      );

      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final firstSession = service.openDirectSession(
        videoId: 'movie-1',
        sourceUri: 'https://example.com/video.mp4',
        sourceSignature: 'sig-a',
        strategyVersion: 'strategy-a',
        durationMs: 120000,
      );
      final firstUri = await firstSession.getFrameUri(5000);
      expect(firstUri, startsWith('file://'));
      expect(extractor.singleFrameCalls, 1);

      final secondSession = service.openDirectSession(
        videoId: 'movie-1',
        sourceUri: 'https://example.com/video.mp4',
        sourceSignature: 'sig-b',
        strategyVersion: 'strategy-a',
        durationMs: 120000,
      );
      final secondUri = await secondSession.getFrameUri(5000);
      expect(secondUri, startsWith('file://'));
      expect(extractor.singleFrameCalls, 2);
    });

    test('invalidates cached thumbnails when the duration changes', () async {
      final root = await Directory.systemTemp.createTemp('thumb-service-2');
      final extractor = _FakeNativeThumbnailExtractor();
      final service = ThumbnailService(
        cacheManager: ThumbnailCacheManager(cacheRootDirectory: root),
        nativeExtractor: extractor,
      );

      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final firstSession = service.openDirectSession(
        videoId: 'movie-2',
        sourceUri: 'https://example.com/video.mp4',
        sourceSignature: 'sig-a',
        strategyVersion: 'strategy-a',
        durationMs: 120000,
      );
      await firstSession.getFrameUri(5000);
      expect(extractor.singleFrameCalls, 1);

      final secondSession = service.openDirectSession(
        videoId: 'movie-2',
        sourceUri: 'https://example.com/video.mp4',
        sourceSignature: 'sig-a',
        strategyVersion: 'strategy-a',
        durationMs: 180000,
      );
      await secondSession.getFrameUri(5000);
      expect(extractor.singleFrameCalls, 2);
    });

    test('invalidates cached thumbnails when the strategy version changes',
        () async {
      final root = await Directory.systemTemp.createTemp('thumb-service-5');
      final extractor = _FakeNativeThumbnailExtractor();
      final service = ThumbnailService(
        cacheManager: ThumbnailCacheManager(cacheRootDirectory: root),
        nativeExtractor: extractor,
      );

      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final firstSession = service.openDirectSession(
        videoId: 'movie-5',
        sourceUri: 'https://example.com/video.mp4',
        sourceSignature: 'uri+headers-a',
        strategyVersion: 'strategy-a',
        durationMs: 120000,
      );
      await firstSession.getFrameUri(5000);
      expect(extractor.singleFrameCalls, 1);

      final secondSession = service.openDirectSession(
        videoId: 'movie-5',
        sourceUri: 'https://example.com/video.mp4',
        sourceSignature: 'uri+headers-a',
        strategyVersion: 'strategy-b',
        durationMs: 120000,
      );
      await secondSession.getFrameUri(5000);
      expect(extractor.singleFrameCalls, 2);
    });

    test('dedupes concurrent direct-session frame requests', () async {
      final root = await Directory.systemTemp.createTemp('thumb-service-3');
      final extractor = _FakeNativeThumbnailExtractor();
      final service = ThumbnailService(
        cacheManager: ThumbnailCacheManager(cacheRootDirectory: root),
        nativeExtractor: extractor,
      );

      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final session = service.openDirectSession(
        videoId: 'movie-3',
        sourceUri: 'https://example.com/video.mp4',
        sourceSignature: 'sig-a',
        strategyVersion: 'strategy-a',
        durationMs: 120000,
      );

      final results = await Future.wait<String?>(<Future<String?>>[
        session.getFrameUri(5000),
        session.getFrameUri(5000),
      ]);

      expect(results.whereType<String>(), hasLength(2));
      expect(extractor.singleFrameCalls, 1);
    });

    test('primes the visible strip as a sync-frame batch', () async {
      final root = await Directory.systemTemp.createTemp('thumb-service-4');
      final extractor = _FakeNativeThumbnailExtractor();
      final service = ThumbnailService(
        cacheManager: ThumbnailCacheManager(cacheRootDirectory: root),
        nativeExtractor: extractor,
      );

      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final session = service.openDirectSession(
        videoId: 'movie-4',
        sourceUri: 'https://example.com/video.mp4',
        sourceSignature: 'sig-a',
        strategyVersion: 'strategy-a',
        durationMs: 120000,
      );

      await session.primeVisibleStrip(10000);

      expect(extractor.batchFrameCalls, hasLength(1));
      expect(
        extractor.batchFrameCalls.single,
        <int>[0, 5000, 10000, 15000, 20000],
      );
    });

    test('caps queued full-movie background batches', () async {
      final root = await Directory.systemTemp.createTemp('thumb-service-6');
      final extractor = _BlockingNativeThumbnailExtractor();
      final service = ThumbnailService(
        cacheManager: ThumbnailCacheManager(cacheRootDirectory: root),
        nativeExtractor: extractor,
        defaultBatchSize: 1,
      );

      addTearDown(() async {
        extractor.completeAllBatches();
        await Future<void>.delayed(Duration.zero);
        await _deleteDirectoryWhenUnlocked(root);
      });

      final session = service.openDirectSession(
        videoId: 'movie-6',
        sourceUri: 'https://example.com/video.mp4',
        sourceSignature: 'sig-a',
        strategyVersion: 'strategy-a',
        durationMs: 600000,
      );

      await session.primeFullMovie();
      await _waitUntil(() => extractor.batchFrameCalls.isNotEmpty);

      expect(extractor.batchFrameCalls, isNotEmpty);
      expect(
        session.debugPendingBackgroundBatchCount,
        lessThanOrEqualTo(ThumbnailDirectSession.maxQueuedBackgroundBatches),
      );
      session.dispose();
    });

    test('drops stale background batches when duration changes', () async {
      final root = await Directory.systemTemp.createTemp('thumb-service-7');
      final extractor = _BlockingNativeThumbnailExtractor();
      final service = ThumbnailService(
        cacheManager: ThumbnailCacheManager(cacheRootDirectory: root),
        nativeExtractor: extractor,
        defaultBatchSize: 1,
      );

      addTearDown(() async {
        extractor.completeAllBatches();
        await Future<void>.delayed(Duration.zero);
        await _deleteDirectoryWhenUnlocked(root);
      });

      final session = service.openDirectSession(
        videoId: 'movie-7',
        sourceUri: 'https://example.com/video.mp4',
        sourceSignature: 'sig-a',
        strategyVersion: 'strategy-a',
        durationMs: 600000,
      );

      await session.primeFullMovie();
      await _waitUntil(() => extractor.batchFrameCalls.isNotEmpty);

      expect(extractor.batchFrameCalls, hasLength(1));
      expect(session.debugPendingBackgroundBatchCount, greaterThan(0));

      session.updateDurationMs(30000);
      expect(session.debugPendingBackgroundBatchCount, 0);

      extractor.completeNextBatch();
      await Future<void>.delayed(Duration.zero);

      expect(extractor.batchFrameCalls, hasLength(1));
      session.dispose();
    });

    test('dispose completes pending direct-session frame request with null',
        () async {
      final root = await Directory.systemTemp.createTemp('thumb-service-8');
      final extractor = _BlockingNativeThumbnailExtractor();
      final service = ThumbnailService(
        cacheManager: ThumbnailCacheManager(cacheRootDirectory: root),
        nativeExtractor: extractor,
      );

      addTearDown(() async {
        extractor.completeSingle();
        await Future<void>.delayed(Duration.zero);
        await _deleteDirectoryWhenUnlocked(root);
      });

      final session = service.openDirectSession(
        videoId: 'movie-8',
        sourceUri: 'https://example.com/video.mp4',
        sourceSignature: 'sig-a',
        strategyVersion: 'strategy-a',
        durationMs: 120000,
      );

      final frameFuture = session.getFrameUri(5000);
      await _waitUntil(() => extractor.singleFrameCalls == 1);

      expect(extractor.singleFrameCalls, 1);

      session.dispose();

      await expectLater(
        frameFuture.timeout(const Duration(milliseconds: 100)),
        completion(isNull),
      );
    });
  });
}
