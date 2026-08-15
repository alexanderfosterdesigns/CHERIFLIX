import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'thumbnail_cache_manager.dart';
import 'native_thumbnail_extractor.dart';

/// Thumbnail pipeline designed for scrub UX:
/// - Cache-first sync-frame previews for AndroidTV scrub strips.
/// - Batch prefetch support for visible-strip, rolling-window, and full-title
///   direct media generation without changing playback behavior.
class ThumbnailService {
  ThumbnailService({
    ThumbnailCacheManager? cacheManager,
    NativeThumbnailExtractor? nativeExtractor,
    this.previewBucketMs = 250,
    this.defaultMaxPreviewDistanceMs = 1200,
    this.defaultBatchSize = 8,
  })  : _cacheManager = cacheManager ?? ThumbnailCacheManager(),
        _nativeExtractor = nativeExtractor ?? NativeThumbnailExtractor();

  final ThumbnailCacheManager _cacheManager;
  final NativeThumbnailExtractor _nativeExtractor;

  final int previewBucketMs;
  final int defaultMaxPreviewDistanceMs;
  final int defaultBatchSize;

  final Map<String, Future<File?>> _inFlightFileRequests =
      <String, Future<File?>>{};
  final Map<String, Future<Uint8List?>> _inFlightByteRequests =
      <String, Future<Uint8List?>>{};
  final Map<String, Future<void>> _inFlightBatchRequests =
      <String, Future<void>>{};

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await _cacheManager.initialize();
    _initialized = true;
  }

  Future<void> trimMemory() => _cacheManager.trimMemory();

  ThumbnailDirectSession openDirectSession({
    required String videoId,
    required String sourceUri,
    Map<String, String> httpHeaders = const <String, String>{},
    required String sourceSignature,
    required String strategyVersion,
    required int durationMs,
    int width = 128,
    int height = 72,
    int? bucketMs,
    int jpegQuality = 72,
  }) {
    return ThumbnailDirectSession._(
      service: this,
      videoId: videoId,
      sourceUri: sourceUri,
      httpHeaders: Map<String, String>.unmodifiable(httpHeaders),
      sourceSignature: sourceSignature,
      strategyVersion: strategyVersion,
      durationMs: durationMs,
      width: width,
      height: height,
      bucketMs: bucketMs ?? 5000,
      jpegQuality: jpegQuality,
    );
  }

  Future<Uint8List?> extractExactFrame(
    String sourceUri,
    int timeMs,
    int width,
    int height, {
    Map<String, String> httpHeaders = const <String, String>{},
  }) async {
    await initialize();
    if (!await _isSupportedSourceUri(sourceUri)) {
      return null;
    }
    return _nativeExtractor.extractExactFrame(
      sourceUri,
      _normalizeTimeMs(timeMs),
      width,
      height,
    );
  }

  Future<File?> getThumbnail(
    String videoId,
    String sourceUri,
    int timeMs, {
    bool exact = false,
    int width = 320,
    int height = 180,
    Map<String, String> httpHeaders = const <String, String>{},
  }) async {
    await initialize();

    if (!await _isSupportedSourceUri(sourceUri)) {
      return null;
    }
    await _prepareLegacySession(videoId, sourceUri);
    await _cacheManager.touchVideo(videoId, sourceUri);

    final requestedTimeMs = _normalizeTimeMs(timeMs);
    final normalizedPreviewTimeMs = _previewTimestampMs(requestedTimeMs);
    final lookupTime = exact ? requestedTimeMs : normalizedPreviewTimeMs;

    final cached = await _cacheManager.getCachedThumbnailFile(
      videoId: videoId,
      timeMs: lookupTime,
      width: width,
      height: height,
      exact: exact,
      maxPreviewDistanceMs: defaultMaxPreviewDistanceMs,
    );
    if (cached != null) {
      return cached;
    }

    final key = _requestKey(
      kind: exact ? 'exact_file' : 'preview_file',
      videoId: videoId,
      timeMs: lookupTime,
      width: width,
      height: height,
    );
    final existing = _inFlightFileRequests[key];
    if (existing != null) {
      return existing;
    }

    final future = () async {
      try {
        final result = await _nativeExtractor.extractFrame(
          sourceUri: sourceUri,
          timeMs: lookupTime,
          width: width,
          height: height,
          exact: exact,
          httpHeaders: httpHeaders,
          jpegQuality: exact ? 90 : 80,
        );

        if (result == null || result.bytes.isEmpty) {
          if (exact) {
            return _cacheManager.getCachedThumbnailFile(
              videoId: videoId,
              timeMs: requestedTimeMs,
              width: width,
              height: height,
              exact: false,
              maxPreviewDistanceMs: defaultMaxPreviewDistanceMs,
            );
          }
          return null;
        }

        final effectiveTimestamp = exact ? requestedTimeMs : lookupTime;
        return _cacheManager.storeThumbnail(
          videoId: videoId,
          videoPath: sourceUri,
          timestampMs: effectiveTimestamp,
          width: width,
          height: height,
          exact: exact,
          bytes: result.bytes,
        );
      } finally {
        _inFlightFileRequests.remove(key);
      }
    }();

    _inFlightFileRequests[key] = future;
    return future;
  }

  Future<Uint8List?> getThumbnailBytes(
    String videoId,
    String sourceUri,
    int timeMs, {
    bool exact = false,
    int width = 320,
    int height = 180,
    Map<String, String> httpHeaders = const <String, String>{},
  }) async {
    await initialize();

    if (!await _isSupportedSourceUri(sourceUri)) {
      return null;
    }
    await _prepareLegacySession(videoId, sourceUri);
    await _cacheManager.touchVideo(videoId, sourceUri);

    final requestedTimeMs = _normalizeTimeMs(timeMs);
    final normalizedPreviewTimeMs = _previewTimestampMs(requestedTimeMs);
    final lookupTime = exact ? requestedTimeMs : normalizedPreviewTimeMs;

    final cachedBytes = await _cacheManager.getCachedThumbnailBytes(
      videoId: videoId,
      timeMs: lookupTime,
      width: width,
      height: height,
      exact: exact,
      maxPreviewDistanceMs: defaultMaxPreviewDistanceMs,
    );
    if (cachedBytes != null) {
      return cachedBytes;
    }

    final key = _requestKey(
      kind: exact ? 'exact_bytes' : 'preview_bytes',
      videoId: videoId,
      timeMs: lookupTime,
      width: width,
      height: height,
    );
    final existing = _inFlightByteRequests[key];
    if (existing != null) {
      return existing;
    }

    final future = () async {
      try {
        final result = await _nativeExtractor.extractFrame(
          sourceUri: sourceUri,
          timeMs: lookupTime,
          width: width,
          height: height,
          exact: exact,
          httpHeaders: httpHeaders,
          jpegQuality: exact ? 90 : 80,
        );
        if (result == null || result.bytes.isEmpty) {
          if (exact) {
            return _cacheManager.getCachedThumbnailBytes(
              videoId: videoId,
              timeMs: requestedTimeMs,
              width: width,
              height: height,
              exact: false,
              maxPreviewDistanceMs: defaultMaxPreviewDistanceMs,
            );
          }
          return null;
        }

        final effectiveTimestamp = exact ? requestedTimeMs : lookupTime;
        await _cacheManager.storeThumbnail(
          videoId: videoId,
          videoPath: sourceUri,
          timestampMs: effectiveTimestamp,
          width: width,
          height: height,
          exact: exact,
          bytes: result.bytes,
        );
        return result.bytes;
      } finally {
        _inFlightByteRequests.remove(key);
      }
    }();
    _inFlightByteRequests[key] = future;
    return future;
  }

  Future<void> prefetchPreviewAround(
    String videoId,
    String sourceUri,
    int centerTimeMs, {
    required int direction,
    int width = 320,
    int height = 180,
    Map<String, String> httpHeaders = const <String, String>{},
  }) async {
    await initialize();
    if (!await _isSupportedSourceUri(sourceUri)) {
      return;
    }

    final normalizedCenter = _normalizeTimeMs(centerTimeMs);
    final offsets =
        direction >= 0 ? <int>[180, 360, 540] : <int>[-180, -360, -540];
    for (final offset in offsets) {
      final target = _normalizeTimeMs(normalizedCenter + offset);
      unawaited(
        getThumbnail(
          videoId,
          sourceUri,
          target,
          exact: false,
          width: width,
          height: height,
          httpHeaders: httpHeaders,
        ),
      );
    }
  }

  Future<void> evictExpired() async {
    await _cacheManager.evictInactiveAndOverflow();
  }

  Future<ThumbnailCacheSessionState> _prepareDirectSession(
    ThumbnailDirectSession session,
  ) async {
    await initialize();
    return _cacheManager.prepareSession(
      videoId: session.videoId,
      sourceSignature: session.sourceSignature,
      strategyVersion: session.strategyVersion,
      durationMs: session.durationMs > 0 ? session.durationMs : null,
    );
  }

  Future<File?> _resolveDirectSessionFrame(
    ThumbnailDirectSession session,
    int timeMs,
  ) async {
    final normalizedTimeMs = session.normalizeBucket(timeMs);
    final key = _requestKey(
      kind: 'direct_session_frame',
      videoId: session.videoId,
      timeMs: normalizedTimeMs,
      width: session.width,
      height: session.height,
    );
    final existing = _inFlightFileRequests[key];
    if (existing != null) {
      return existing;
    }

    final future = () async {
      try {
        await initialize();
        if (!await _isSupportedSourceUri(session.sourceUri)) {
          return null;
        }
        if (session.disposed) {
          return null;
        }
        await _prepareDirectSession(session);
        await _cacheManager.touchVideo(
            session.videoId, session.sourceSignature);
        if (session.disposed) {
          return null;
        }

        final cached = await _cacheManager.getCachedThumbnailFile(
          videoId: session.videoId,
          timeMs: normalizedTimeMs,
          width: session.width,
          height: session.height,
          exact: false,
          maxPreviewDistanceMs: session.bucketMs,
        );
        if (cached != null) {
          return cached;
        }

        final result = await _nativeExtractor.extractFrame(
          sourceUri: session.sourceUri,
          timeMs: normalizedTimeMs,
          width: session.width,
          height: session.height,
          exact: false,
          httpHeaders: session.httpHeaders,
          jpegQuality: session.jpegQuality,
        );
        if (result == null || result.bytes.isEmpty) {
          return null;
        }
        if (session.disposed) {
          return null;
        }
        return _cacheManager.storeThumbnail(
          videoId: session.videoId,
          videoPath: session.sourceSignature,
          timestampMs: normalizedTimeMs,
          width: session.width,
          height: session.height,
          exact: false,
          bytes: result.bytes,
        );
      } finally {
        _inFlightFileRequests.remove(key);
      }
    }();

    _inFlightFileRequests[key] = future;
    return future;
  }

  Future<void> _primeDirectSessionFrames(
    ThumbnailDirectSession session,
    Iterable<int> timestampsMs, {
    required String kind,
  }) async {
    final sessionGeneration = session._backgroundGeneration;
    await initialize();
    if (session.disposed ||
        sessionGeneration != session._backgroundGeneration ||
        !await _isSupportedSourceUri(session.sourceUri)) {
      return;
    }
    if (session.backgroundPaused && kind != 'visible_strip') {
      return;
    }
    await _prepareDirectSession(session);
    await _cacheManager.touchVideo(session.videoId, session.sourceSignature);

    final normalizedTimes = timestampsMs
        .map(session.normalizeBucket)
        .toSet()
        .toList(growable: false)
      ..sort();
    if (normalizedTimes.isEmpty) {
      return;
    }

    final missingTimes = <int>[];
    for (final timeMs in normalizedTimes) {
      final cached = await _cacheManager.getCachedThumbnailFile(
        videoId: session.videoId,
        timeMs: timeMs,
        width: session.width,
        height: session.height,
        exact: false,
        maxPreviewDistanceMs: session.bucketMs,
      );
      if (cached == null) {
        missingTimes.add(timeMs);
      }
    }
    if (missingTimes.isEmpty) {
      return;
    }

    for (final chunk in _chunked(missingTimes, session.batchSize)) {
      if (session.disposed) {
        return;
      }
      final batchKey =
          '$kind|${session.videoId}|${chunk.join(",")}|${session.width}x${session.height}';
      final existing = _inFlightBatchRequests[batchKey];
      if (existing != null) {
        await existing;
        continue;
      }

      final future = () async {
        try {
          final results = await _nativeExtractor.extractFrames(
            sourceUri: session.sourceUri,
            timeMsList: chunk,
            width: session.width,
            height: session.height,
            exact: false,
            httpHeaders: session.httpHeaders,
            jpegQuality: session.jpegQuality,
          );
          for (final result in results) {
            if (session.disposed ||
                sessionGeneration != session._backgroundGeneration ||
                result.bytes.isEmpty) {
              continue;
            }
            await _cacheManager.storeThumbnail(
              videoId: session.videoId,
              videoPath: session.sourceSignature,
              timestampMs: result.requestedTimeMs,
              width: session.width,
              height: session.height,
              exact: false,
              bytes: result.bytes,
            );
          }
        } finally {
          _inFlightBatchRequests.remove(batchKey);
        }
      }();
      _inFlightBatchRequests[batchKey] = future;
      await future;
    }
  }

  Future<void> _markDirectSessionFullMoviePrimed(
    ThumbnailDirectSession session,
  ) {
    return _cacheManager.markFullMoviePrimed(session.videoId);
  }

  Future<void> _prepareLegacySession(
    String videoId,
    String sourceUri,
  ) async {
    await _cacheManager.prepareSession(
      videoId: videoId,
      sourceSignature: sourceUri,
      strategyVersion: 'legacy-preview-v1',
    );
  }

  Future<bool> _isSupportedSourceUri(String sourceUri) async {
    final value = sourceUri.trim();
    if (value.isEmpty) {
      return false;
    }
    final lower = value.toLowerCase();
    if (lower.startsWith('content://')) {
      return true;
    }
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return !lower.contains('.m3u8');
    }
    if (lower.startsWith('file://')) {
      final uri = Uri.tryParse(value);
      final path = uri?.toFilePath(windows: Platform.isWindows);
      return path != null && await File(path).exists();
    }
    return File(value).exists();
  }

  int _normalizeTimeMs(int timeMs) => timeMs < 0 ? 0 : timeMs;

  int _previewTimestampMs(int timeMs) {
    if (previewBucketMs <= 0) {
      return timeMs;
    }
    return (timeMs / previewBucketMs).round() * previewBucketMs;
  }

  String _requestKey({
    required String kind,
    required String videoId,
    required int timeMs,
    required int width,
    required int height,
  }) {
    return '$kind|$videoId|$timeMs|${width}x$height';
  }

  Iterable<List<int>> _chunked(List<int> values, int chunkSize) sync* {
    if (values.isEmpty) {
      return;
    }
    final normalizedChunkSize = chunkSize < 1 ? 1 : chunkSize;
    for (var index = 0; index < values.length; index += normalizedChunkSize) {
      final end = (index + normalizedChunkSize).clamp(0, values.length);
      yield values.sublist(index, end);
    }
  }
}

class ThumbnailDirectSession {
  static const int maxQueuedBackgroundBatches = 4;
  static const Duration _backgroundBatchCooldown = Duration(milliseconds: 80);

  ThumbnailDirectSession._({
    required ThumbnailService service,
    required this.videoId,
    required this.sourceUri,
    required this.httpHeaders,
    required this.sourceSignature,
    required this.strategyVersion,
    required int durationMs,
    required this.width,
    required this.height,
    required this.bucketMs,
    required this.jpegQuality,
  })  : _service = service,
        _durationMs = durationMs < 0 ? 0 : durationMs;

  final ThumbnailService _service;

  final String videoId;
  final String sourceUri;
  final Map<String, String> httpHeaders;
  final String sourceSignature;
  final String strategyVersion;
  final int width;
  final int height;
  final int bucketMs;
  final int jpegQuality;

  int _durationMs;
  bool _initialized = false;
  bool _disposed = false;
  bool _backgroundPaused = false;
  bool _backgroundPumpRunning = false;
  bool _fullMoviePrimeQueued = false;
  bool _fullMoviePrimed = false;
  bool _fullMovieAllQueued = false;
  int? _fullMovieNextTimestampMs;
  int _backgroundGeneration = 0;
  final Completer<void> _disposedCompleter = Completer<void>();
  final Queue<List<int>> _backgroundBatches = Queue<List<int>>();

  bool get disposed => _disposed;
  bool get backgroundPaused => _backgroundPaused;
  int get durationMs => _durationMs;
  int get batchSize => _service.defaultBatchSize;
  int get debugPendingBackgroundBatchCount => _backgroundBatches.length;
  bool get debugFullMoviePrimed => _fullMoviePrimed;

  void updateDurationMs(int durationMs) {
    final normalized = durationMs < 0 ? 0 : durationMs;
    if (_durationMs == normalized) {
      return;
    }
    _durationMs = normalized;
    _initialized = false;
    _fullMoviePrimed = false;
    _fullMoviePrimeQueued = false;
    _fullMovieAllQueued = false;
    _fullMovieNextTimestampMs = null;
    _backgroundGeneration += 1;
    _backgroundBatches.clear();
  }

  int normalizeBucket(int timeMs) {
    final clamped = _durationMs > 0 ? timeMs.clamp(0, _durationMs) : timeMs;
    if (bucketMs <= 0) {
      return clamped < 0 ? 0 : clamped;
    }
    final snapped = (clamped / bucketMs).round() * bucketMs;
    if (_durationMs > 0) {
      return snapped.clamp(0, _durationMs);
    }
    return snapped < 0 ? 0 : snapped;
  }

  Future<String?> getFrameUri(
    int timeMs, {
    bool prioritize = false,
  }) async {
    if (_disposed) {
      return null;
    }
    await _ensurePrepared();
    final normalizedTimeMs = normalizeBucket(timeMs);
    if (prioritize) {
      unawaited(primeVisibleStrip(normalizedTimeMs));
      unawaited(primeRollingWindow(normalizedTimeMs));
    }
    final file = await _nullIfDisposed(
      _service._resolveDirectSessionFrame(
        this,
        normalizedTimeMs,
      ),
    );
    return file?.uri.toString();
  }

  Future<void> primeVisibleStrip(int centerTimeMs) async {
    if (_disposed) {
      return;
    }
    await _ensurePrepared();
    await _service._primeDirectSessionFrames(
      this,
      _visibleStripTimestamps(centerTimeMs),
      kind: 'visible_strip',
    );
  }

  Future<void> primeRollingWindow(int centerTimeMs) async {
    if (_disposed) {
      return;
    }
    await _ensurePrepared();
    await _service._primeDirectSessionFrames(
      this,
      _rollingWindowTimestamps(centerTimeMs),
      kind: 'rolling_window',
    );
  }

  Future<void> primeFullMovie() async {
    if (_disposed ||
        _durationMs <= 0 ||
        bucketMs <= 0 ||
        _fullMoviePrimed ||
        _fullMoviePrimeQueued) {
      return;
    }
    await _ensurePrepared();
    if (_fullMoviePrimed || _disposed || _durationMs <= 0 || bucketMs <= 0) {
      return;
    }
    _fullMoviePrimeQueued = true;
    _fullMovieAllQueued = false;
    _fullMovieNextTimestampMs = 0;
    _fillBackgroundQueue();
    _scheduleBackgroundPump();
  }

  void pauseBackgroundWork() {
    _backgroundPaused = true;
  }

  void resumeBackgroundWork() {
    if (_disposed) {
      return;
    }
    _backgroundPaused = false;
    _scheduleBackgroundPump();
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _backgroundGeneration += 1;
    _backgroundBatches.clear();
    if (!_disposedCompleter.isCompleted) {
      _disposedCompleter.complete();
    }
  }

  Future<void> _ensurePrepared() async {
    if (_initialized) {
      return;
    }
    final state = await _service._prepareDirectSession(this);
    _fullMoviePrimed = state.fullMoviePrimed;
    _initialized = true;
  }

  Iterable<int> _visibleStripTimestamps(int centerTimeMs) sync* {
    const offsets = <int>[-10000, -5000, 0, 5000, 10000];
    final seen = <int>{};
    for (final offset in offsets) {
      final value = normalizeBucket(centerTimeMs + offset);
      if (seen.add(value)) {
        yield value;
      }
    }
  }

  Iterable<int> _rollingWindowTimestamps(int centerTimeMs) sync* {
    const offsets = <int>[
      -30000,
      -25000,
      -20000,
      -15000,
      15000,
      20000,
      25000,
      30000,
    ];
    final seen = <int>{};
    for (final offset in offsets) {
      final value = normalizeBucket(centerTimeMs + offset);
      if (seen.add(value)) {
        yield value;
      }
    }
  }

  void _scheduleBackgroundPump() {
    if (_backgroundPumpRunning || _backgroundPaused || _disposed) {
      return;
    }
    _backgroundPumpRunning = true;
    final generation = _backgroundGeneration;
    scheduleMicrotask(() async {
      try {
        _fillBackgroundQueue();
        while (!_disposed &&
            !_backgroundPaused &&
            generation == _backgroundGeneration &&
            _backgroundBatches.isNotEmpty) {
          final batch = _backgroundBatches.removeFirst();
          await _service._primeDirectSessionFrames(
            this,
            batch,
            kind: 'full_movie',
          );
          if (_disposed ||
              _backgroundPaused ||
              generation != _backgroundGeneration) {
            return;
          }
          await Future<void>.delayed(_backgroundBatchCooldown);
          _fillBackgroundQueue();
        }
        if (!_disposed &&
            !_backgroundPaused &&
            generation == _backgroundGeneration &&
            _backgroundBatches.isEmpty &&
            _fullMovieAllQueued) {
          _fullMoviePrimed = true;
          await _service._markDirectSessionFullMoviePrimed(this);
        }
      } finally {
        _backgroundPumpRunning = false;
        if (!_disposed &&
            !_backgroundPaused &&
            generation == _backgroundGeneration &&
            (_backgroundBatches.isNotEmpty || !_fullMovieAllQueued)) {
          _scheduleBackgroundPump();
        }
      }
    });
  }

  void _fillBackgroundQueue() {
    if (_disposed ||
        _backgroundPaused ||
        !_fullMoviePrimeQueued ||
        _fullMovieAllQueued ||
        _durationMs <= 0 ||
        bucketMs <= 0) {
      return;
    }
    var nextTimeMs = _fullMovieNextTimestampMs ?? 0;
    while (_backgroundBatches.length < maxQueuedBackgroundBatches &&
        nextTimeMs <= _durationMs) {
      final chunk = <int>[];
      while (chunk.length < batchSize && nextTimeMs <= _durationMs) {
        chunk.add(normalizeBucket(nextTimeMs));
        nextTimeMs += bucketMs;
      }
      final normalized = chunk.toSet().toList(growable: false)..sort();
      if (normalized.isNotEmpty) {
        _backgroundBatches.add(normalized);
      }
    }
    _fullMovieNextTimestampMs = nextTimeMs;
    if (nextTimeMs > _durationMs) {
      _fullMovieAllQueued = true;
    }
  }

  Future<T?> _nullIfDisposed<T>(Future<T?> future) async {
    final result = await Future.any<Object?>(<Future<Object?>>[
      future,
      _disposedCompleter.future.then<Object?>((_) => null),
    ]);
    return result as T?;
  }
}
