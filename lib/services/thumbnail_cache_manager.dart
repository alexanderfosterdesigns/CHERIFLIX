import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class ThumbnailCacheSessionState {
  const ThumbnailCacheSessionState({
    required this.fullMoviePrimed,
  });

  final bool fullMoviePrimed;
}

/// Manages thumbnail persistence.
///
/// Disk layout:
/// `/cache/thumbnails/{videoId}/`
///   `manifest.json`
///   `exact/`
///   `preview/`
///
/// Eviction policy:
/// 1. Remove videos inactive for over 1 hour.
/// 2. Enforce max 5 videos by LRU (least recently accessed video removed first).
class ThumbnailCacheManager {
  ThumbnailCacheManager({
    Directory? cacheRootDirectory,
    this.maxVideosCached = 5,
    this.inactivityTtl = const Duration(hours: 1),
    this.memoryEntryLimit = 120,
    this.memoryByteLimit = 32 << 20,
    this.manifestFlushInterval = const Duration(seconds: 3),
    DateTime Function()? now,
  })  : _configuredRoot = cacheRootDirectory,
        _now = now ?? DateTime.now;

  final Directory? _configuredRoot;
  final int maxVideosCached;
  final Duration inactivityTtl;
  final int memoryEntryLimit;
  final int memoryByteLimit;
  final Duration manifestFlushInterval;
  final DateTime Function() _now;

  Directory? _rootDirectory;
  bool _initialized = false;
  final _AsyncMutex _mutex = _AsyncMutex();

  final Map<String, _VideoManifest> _manifests = <String, _VideoManifest>{};

  // In-memory LRU for recently used thumbnail bytes.
  final LinkedHashMap<String, Uint8List> _memoryLru =
      LinkedHashMap<String, Uint8List>();
  final Set<String> _dirtyManifestIds = <String>{};
  Timer? _manifestFlushTimer;
  int _memoryBytes = 0;

  int get debugMemoryEntryCount => _memoryLru.length;
  int get debugMemoryBytes => _memoryBytes;
  int get debugPendingManifestCount => _dirtyManifestIds.length;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await _mutex.protect(() async {
      if (_initialized) {
        return;
      }
      final root = await _resolveRootDirectory();
      await root.create(recursive: true);
      _rootDirectory = root;
      await _loadExistingManifestsLocked();
      await _enforceEvictionLocked();
      _initialized = true;
    });
  }

  Future<void> trimMemory() async {
    if (!_initialized) {
      _clearMemoryEntries();
      return;
    }
    await _mutex.protect(() async {
      _clearMemoryEntries();
    });
  }

  Future<void> flushPendingManifests() async {
    _manifestFlushTimer?.cancel();
    _manifestFlushTimer = null;
    if (!_initialized || _dirtyManifestIds.isEmpty) {
      return;
    }
    await _mutex.protect(_flushDirtyManifestsLocked);
  }

  Future<void> dispose() async {
    await flushPendingManifests();
    _manifestFlushTimer?.cancel();
    _manifestFlushTimer = null;
    _clearMemoryEntries();
  }

  Future<File?> getCachedThumbnailFile({
    required String videoId,
    required int timeMs,
    required int width,
    required int height,
    required bool exact,
    int maxPreviewDistanceMs = 1200,
  }) async {
    await initialize();
    return _mutex.protect(() async {
      final manifest = await _loadManifestLocked(videoId);
      if (manifest == null) {
        return null;
      }
      final entry = _resolveEntry(
        manifest: manifest,
        timeMs: timeMs,
        width: width,
        height: height,
        exact: exact,
        maxPreviewDistanceMs: maxPreviewDistanceMs,
      );
      if (entry == null) {
        return null;
      }

      final file = File(_joinPath(_videoDirPath(videoId), entry.file));
      if (!await file.exists()) {
        manifest.cachedFiles.remove(entry.file);
        await _saveManifestLocked(manifest);
        return null;
      }

      final touched = _now();
      entry.lastAccessed = touched;
      manifest.lastAccessed = touched;
      _markManifestDirty(manifest);
      return file;
    });
  }

  Future<Uint8List?> getCachedThumbnailBytes({
    required String videoId,
    required int timeMs,
    required int width,
    required int height,
    required bool exact,
    int maxPreviewDistanceMs = 1200,
  }) async {
    await initialize();
    return _mutex.protect(() async {
      final manifest = await _loadManifestLocked(videoId);
      if (manifest == null) {
        return null;
      }
      final entry = _resolveEntry(
        manifest: manifest,
        timeMs: timeMs,
        width: width,
        height: height,
        exact: exact,
        maxPreviewDistanceMs: maxPreviewDistanceMs,
      );
      if (entry == null) {
        return null;
      }

      final memoryKey = _memoryKey(
        videoId: videoId,
        exact: entry.exact,
        timestampMs: entry.timestampMs,
        width: entry.width,
        height: entry.height,
      );
      final memoryHit = _memoryLru[memoryKey];
      if (memoryHit != null) {
        _touchMemoryEntry(memoryKey, memoryHit);
        _touchEntry(manifest, entry);
        _markManifestDirty(manifest);
        return memoryHit;
      }

      final file = File(_joinPath(_videoDirPath(videoId), entry.file));
      if (!await file.exists()) {
        manifest.cachedFiles.remove(entry.file);
        await _saveManifestLocked(manifest);
        return null;
      }

      final bytes = await file.readAsBytes();
      _putMemoryEntry(memoryKey, bytes);
      _touchEntry(manifest, entry);
      _markManifestDirty(manifest);
      return bytes;
    });
  }

  Future<File?> storeThumbnail({
    required String videoId,
    required String videoPath,
    required int timestampMs,
    required int width,
    required int height,
    required bool exact,
    required Uint8List bytes,
  }) async {
    await initialize();
    if (bytes.isEmpty) {
      return null;
    }

    return _mutex.protect(() async {
      final root = _rootDirectory!;
      final videoDir = Directory(_joinPath(root.path, _safeVideoId(videoId)));
      final exactDir = Directory(_joinPath(videoDir.path, 'exact'));
      final previewDir = Directory(_joinPath(videoDir.path, 'preview'));
      await exactDir.create(recursive: true);
      await previewDir.create(recursive: true);

      final pathHash = _stableHash(videoPath);
      final manifest = await _loadManifestLocked(videoId) ??
          _VideoManifest(
            videoId: videoId,
            videoPathHash: pathHash,
            sourceSignature: '',
            strategyVersion: '',
            durationMs: null,
            fullMoviePrimedAt: null,
            lastAccessed: _now(),
            cachedFiles: <String, _CachedFileEntry>{},
          );
      manifest.videoPathHash = pathHash;

      final normalizedTimestamp = timestampMs < 0 ? 0 : timestampMs;
      final fileName = 't$normalizedTimestamp' '_w$width' '_h$height.jpg';
      final relativePath = '${exact ? 'exact' : 'preview'}/$fileName';
      final filePath = _joinPath(videoDir.path, relativePath);
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);

      final stat = await file.stat();
      final touched = _now();
      final entry = _CachedFileEntry(
        file: relativePath,
        exact: exact,
        timestampMs: normalizedTimestamp,
        width: width,
        height: height,
        sizeBytes: stat.size,
        createdAt: touched,
        lastAccessed: touched,
      );
      manifest.cachedFiles[relativePath] = entry;
      manifest.lastAccessed = touched;
      _manifests[videoId] = manifest;

      _putMemoryEntry(
        _memoryKey(
          videoId: videoId,
          exact: exact,
          timestampMs: normalizedTimestamp,
          width: width,
          height: height,
        ),
        bytes,
      );
      await _saveManifestLocked(manifest);
      await _enforceEvictionLocked();
      return file;
    });
  }

  Future<void> touchVideo(String videoId, String videoPath) async {
    await initialize();
    await _mutex.protect(() async {
      final manifest = await _loadManifestLocked(videoId) ??
          _VideoManifest(
            videoId: videoId,
            videoPathHash: _stableHash(videoPath),
            sourceSignature: '',
            strategyVersion: '',
            durationMs: null,
            fullMoviePrimedAt: null,
            lastAccessed: _now(),
            cachedFiles: <String, _CachedFileEntry>{},
          );
      manifest.videoPathHash = _stableHash(videoPath);
      manifest.lastAccessed = _now();
      _manifests[videoId] = manifest;
      await _saveManifestLocked(manifest);
      await _enforceEvictionLocked();
    });
  }

  Future<ThumbnailCacheSessionState> prepareSession({
    required String videoId,
    required String sourceSignature,
    required String strategyVersion,
    int? durationMs,
  }) async {
    await initialize();
    return _mutex.protect(() async {
      final existing = await _loadManifestLocked(videoId);
      if (existing != null &&
          !_manifestMatchesSession(
            existing,
            sourceSignature: sourceSignature,
            strategyVersion: strategyVersion,
            durationMs: durationMs,
          )) {
        await _removeVideoLocked(videoId);
      }

      final manifest = await _loadManifestLocked(videoId) ??
          _VideoManifest(
            videoId: videoId,
            videoPathHash: sourceSignature,
            sourceSignature: sourceSignature,
            strategyVersion: strategyVersion,
            durationMs: durationMs,
            fullMoviePrimedAt: null,
            lastAccessed: _now(),
            cachedFiles: <String, _CachedFileEntry>{},
          );
      manifest.videoPathHash = sourceSignature;
      manifest.sourceSignature = sourceSignature;
      manifest.strategyVersion = strategyVersion;
      manifest.durationMs = durationMs;
      manifest.lastAccessed = _now();
      _manifests[videoId] = manifest;
      await _saveManifestLocked(manifest);
      return ThumbnailCacheSessionState(
        fullMoviePrimed: manifest.fullMoviePrimedAt != null,
      );
    });
  }

  Future<void> markFullMoviePrimed(String videoId) async {
    await initialize();
    await _mutex.protect(() async {
      final manifest = await _loadManifestLocked(videoId);
      if (manifest == null) {
        return;
      }
      manifest.fullMoviePrimedAt = _now();
      manifest.lastAccessed = _now();
      await _saveManifestLocked(manifest);
    });
  }

  Future<void> evictInactiveAndOverflow() async {
    await initialize();
    await _mutex.protect(_enforceEvictionLocked);
  }

  Future<void> clearVideo(String videoId) async {
    await initialize();
    await _mutex.protect(() async {
      await _removeVideoLocked(videoId);
    });
  }

  Future<void> clearAll() async {
    await initialize();
    await _mutex.protect(() async {
      final ids = _manifests.keys.toList(growable: false);
      for (final id in ids) {
        await _removeVideoLocked(id);
      }
      _clearMemoryEntries();
    });
  }

  // --------- Internal ---------

  Future<Directory> _resolveRootDirectory() async {
    if (_configuredRoot != null) {
      return _configuredRoot;
    }
    final temporaryDirectory = await getTemporaryDirectory();
    // On mobile this resolves to app cache storage. Resulting layout becomes:
    // `<app-cache>/thumbnails/<videoId>/...`
    return Directory(_joinPath(temporaryDirectory.path, 'thumbnails'));
  }

  Future<void> _loadExistingManifestsLocked() async {
    final root = _rootDirectory!;
    if (!await root.exists()) {
      return;
    }

    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      final videoId = _unsafedVideoIdFromDirName(_basename(entity.path));
      final manifest = await _loadManifestFromDiskLocked(videoId, entity.path);
      if (manifest != null) {
        _manifests[videoId] = manifest;
      }
    }
  }

  Future<_VideoManifest?> _loadManifestLocked(String videoId) async {
    final cached = _manifests[videoId];
    if (cached != null) {
      return cached;
    }
    final manifest = await _loadManifestFromDiskLocked(
      videoId,
      _videoDirPath(videoId),
    );
    if (manifest != null) {
      _manifests[videoId] = manifest;
    }
    return manifest;
  }

  Future<_VideoManifest?> _loadManifestFromDiskLocked(
    String videoId,
    String videoDirPath,
  ) async {
    final manifestFile = File(_joinPath(videoDirPath, 'manifest.json'));
    if (!await manifestFile.exists()) {
      return _rebuildManifestFromDiskLocked(videoId, videoDirPath);
    }

    try {
      final raw = await manifestFile.readAsString();
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) {
        return _rebuildManifestFromDiskLocked(videoId, videoDirPath);
      }

      final parsed = _VideoManifest.fromJson(map);
      if (parsed.videoId.trim().isEmpty) {
        parsed.videoId = videoId;
      }
      final sanitizedEntries = <String, _CachedFileEntry>{};
      for (final entry in parsed.cachedFiles.values) {
        final file = File(_joinPath(videoDirPath, entry.file));
        if (await file.exists()) {
          sanitizedEntries[entry.file] = entry;
        }
      }
      parsed.cachedFiles
        ..clear()
        ..addAll(sanitizedEntries);
      return parsed;
    } catch (_) {
      return _rebuildManifestFromDiskLocked(videoId, videoDirPath);
    }
  }

  Future<_VideoManifest?> _rebuildManifestFromDiskLocked(
    String videoId,
    String videoDirPath,
  ) async {
    final directory = Directory(videoDirPath);
    if (!await directory.exists()) {
      return null;
    }

    final entries = <String, _CachedFileEntry>{};
    for (final exact in <bool>[true, false]) {
      final folderName = exact ? 'exact' : 'preview';
      final folder = Directory(_joinPath(videoDirPath, folderName));
      if (!await folder.exists()) {
        continue;
      }

      await for (final entity in folder.list(followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        final fileName = _basename(entity.path);
        final parsed = _parseFileMetadata(
          fileName: fileName,
          exact: exact,
        );
        if (parsed == null) {
          continue;
        }
        final stat = await entity.stat();
        final relativePath = '$folderName/$fileName';
        entries[relativePath] = _CachedFileEntry(
          file: relativePath,
          exact: exact,
          timestampMs: parsed.timestampMs,
          width: parsed.width,
          height: parsed.height,
          sizeBytes: stat.size,
          createdAt: stat.changed,
          lastAccessed: stat.accessed.isAfter(DateTime(1971))
              ? stat.accessed
              : stat.changed,
        );
      }
    }

    final manifest = _VideoManifest(
      videoId: videoId,
      videoPathHash: '',
      sourceSignature: '',
      strategyVersion: '',
      durationMs: null,
      fullMoviePrimedAt: null,
      lastAccessed: entries.isEmpty
          ? _now()
          : entries.values
              .map((entry) => entry.lastAccessed)
              .reduce((a, b) => a.isAfter(b) ? a : b),
      cachedFiles: entries,
    );
    await _saveManifestLocked(manifest);
    return manifest;
  }

  Future<void> _saveManifestLocked(_VideoManifest manifest) async {
    final file =
        File(_joinPath(_videoDirPath(manifest.videoId), 'manifest.json'));
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(manifest.toJson()),
    );
    _dirtyManifestIds.remove(manifest.videoId);
  }

  void _markManifestDirty(_VideoManifest manifest) {
    _dirtyManifestIds.add(manifest.videoId);
    _manifestFlushTimer ??= Timer(manifestFlushInterval, () {
      _manifestFlushTimer = null;
      unawaited(_mutex.protect(_flushDirtyManifestsLocked));
    });
  }

  Future<void> _flushDirtyManifestsLocked() async {
    final ids = _dirtyManifestIds.toList(growable: false);
    for (final id in ids) {
      final manifest = _manifests[id];
      if (manifest == null) {
        _dirtyManifestIds.remove(id);
      } else {
        await _saveManifestLocked(manifest);
      }
    }
  }

  _CachedFileEntry? _resolveEntry({
    required _VideoManifest manifest,
    required int timeMs,
    required int width,
    required int height,
    required bool exact,
    required int maxPreviewDistanceMs,
  }) {
    if (manifest.cachedFiles.isEmpty) {
      return null;
    }

    final requested = timeMs < 0 ? 0 : timeMs;

    if (exact) {
      for (final entry in manifest.cachedFiles.values) {
        if (!entry.exact) {
          continue;
        }
        if (entry.timestampMs == requested &&
            entry.width == width &&
            entry.height == height) {
          return entry;
        }
      }
      return null;
    }

    _CachedFileEntry? best;
    var bestDistance = 1 << 30;

    for (final entry in manifest.cachedFiles.values) {
      if (entry.width != width || entry.height != height) {
        continue;
      }
      final distance = (entry.timestampMs - requested).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = entry;
      }
    }

    if (best == null) {
      return null;
    }
    if (bestDistance > maxPreviewDistanceMs) {
      return null;
    }
    return best;
  }

  void _touchEntry(_VideoManifest manifest, _CachedFileEntry entry) {
    final touched = _now();
    entry.lastAccessed = touched;
    manifest.lastAccessed = touched;
  }

  Future<void> _enforceEvictionLocked() async {
    final now = _now();
    final staleIds = <String>[];
    for (final manifest in _manifests.values) {
      final inactiveFor = now.difference(manifest.lastAccessed);
      if (inactiveFor > inactivityTtl) {
        staleIds.add(manifest.videoId);
      }
    }
    for (final staleId in staleIds) {
      await _removeVideoLocked(staleId);
    }

    if (_manifests.length <= maxVideosCached) {
      return;
    }

    final byOldest = _manifests.values.toList(growable: false)
      ..sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed));
    final overflowCount = _manifests.length - maxVideosCached;
    for (var i = 0; i < overflowCount; i += 1) {
      await _removeVideoLocked(byOldest[i].videoId);
    }
  }

  Future<void> _removeVideoLocked(String videoId) async {
    _manifests.remove(videoId);
    _dirtyManifestIds.remove(videoId);
    final keys = _memoryLru.keys
        .where((key) => key.startsWith('$videoId|'))
        .toList(growable: false);
    for (final key in keys) {
      _removeMemoryEntry(key);
    }
    final directory = Directory(_videoDirPath(videoId));
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  void _putMemoryEntry(String key, Uint8List bytes) {
    if (_memoryLru.containsKey(key)) {
      _removeMemoryEntry(key);
    }
    _memoryLru[key] = bytes;
    _memoryBytes += bytes.lengthInBytes;
    while (_memoryLru.length > memoryEntryLimit ||
        _memoryBytes > memoryByteLimit) {
      _removeMemoryEntry(_memoryLru.keys.first);
    }
  }

  void _touchMemoryEntry(String key, Uint8List bytes) {
    _memoryLru.remove(key);
    _memoryLru[key] = bytes;
  }

  void _removeMemoryEntry(String key) {
    final removed = _memoryLru.remove(key);
    if (removed != null) {
      _memoryBytes -= removed.lengthInBytes;
    }
  }

  void _clearMemoryEntries() {
    _memoryLru.clear();
    _memoryBytes = 0;
  }

  String _memoryKey({
    required String videoId,
    required bool exact,
    required int timestampMs,
    required int width,
    required int height,
  }) {
    return '$videoId|${exact ? 'e' : 'p'}|$timestampMs|${width}x$height';
  }

  String _videoDirPath(String videoId) {
    final rootPath = _rootDirectory!.path;
    return _joinPath(rootPath, _safeVideoId(videoId));
  }

  String _safeVideoId(String value) {
    return value.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
  }

  String _unsafedVideoIdFromDirName(String value) {
    // Dir names are sanitized for filesystem safety; we preserve them as stable
    // cache IDs because reverse mapping is not guaranteed.
    return value;
  }

  String _joinPath(String left, String right) {
    final separator = Platform.pathSeparator;
    if (left.endsWith(separator)) {
      return '$left$right';
    }
    return '$left$separator$right';
  }

  String _basename(String path) {
    final separator = Platform.pathSeparator;
    final normalized =
        path.endsWith(separator) ? path.substring(0, path.length - 1) : path;
    final index = normalized.lastIndexOf(separator);
    if (index < 0) {
      return normalized;
    }
    return normalized.substring(index + 1);
  }

  String _stableHash(String input) {
    // FNV-1a 64-bit for stable deterministic cache keying.
    const int fnvOffset = 0xcbf29ce484222325;
    const int fnvPrime = 0x100000001b3;
    var hash = fnvOffset;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * fnvPrime) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  _ParsedFileMetadata? _parseFileMetadata({
    required String fileName,
    required bool exact,
  }) {
    final match = RegExp(r'^t(\d+)_w(\d+)_h(\d+)\.(jpg|jpeg|png)$')
        .firstMatch(fileName.toLowerCase());
    if (match == null) {
      return null;
    }
    final timestampMs = int.tryParse(match.group(1)!);
    final width = int.tryParse(match.group(2)!);
    final height = int.tryParse(match.group(3)!);
    if (timestampMs == null || width == null || height == null) {
      return null;
    }
    return _ParsedFileMetadata(
      timestampMs: timestampMs,
      width: width,
      height: height,
      exact: exact,
    );
  }

  bool _manifestMatchesSession(
    _VideoManifest manifest, {
    required String sourceSignature,
    required String strategyVersion,
    int? durationMs,
  }) {
    if (manifest.sourceSignature.isNotEmpty &&
        manifest.sourceSignature != sourceSignature) {
      return false;
    }
    if (manifest.strategyVersion.isNotEmpty &&
        manifest.strategyVersion != strategyVersion) {
      return false;
    }
    if (durationMs != null &&
        manifest.durationMs != null &&
        manifest.durationMs != durationMs) {
      return false;
    }
    return true;
  }
}

class _ParsedFileMetadata {
  const _ParsedFileMetadata({
    required this.timestampMs,
    required this.width,
    required this.height,
    required this.exact,
  });

  final int timestampMs;
  final int width;
  final int height;
  final bool exact;
}

class _VideoManifest {
  _VideoManifest({
    required this.videoId,
    required this.videoPathHash,
    required this.sourceSignature,
    required this.strategyVersion,
    required this.durationMs,
    required this.fullMoviePrimedAt,
    required this.lastAccessed,
    required this.cachedFiles,
  });

  String videoId;
  String videoPathHash;
  String sourceSignature;
  String strategyVersion;
  int? durationMs;
  DateTime? fullMoviePrimedAt;
  DateTime lastAccessed;
  Map<String, _CachedFileEntry> cachedFiles;

  factory _VideoManifest.fromJson(Map<String, dynamic> json) {
    final cachedFiles = <String, _CachedFileEntry>{};
    final dynamic filesRaw = json['cachedFiles'];
    if (filesRaw is List) {
      for (final item in filesRaw) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final entry = _CachedFileEntry.tryFromJson(item);
        if (entry != null) {
          cachedFiles[entry.file] = entry;
        }
      }
    }
    return _VideoManifest(
      videoId: json['videoId']?.toString() ?? '',
      videoPathHash: json['videoPathHash']?.toString() ?? '',
      sourceSignature:
          (json['sourceSignature'] ?? json['source_signature'] ?? '')
              .toString(),
      strategyVersion:
          (json['strategyVersion'] ?? json['strategy_version'] ?? '')
              .toString(),
      durationMs: _toIntOrNull(json['durationMs'] ?? json['duration_ms']),
      fullMoviePrimedAt: _parseDateTime(
          json['fullMoviePrimedAt'] ?? json['full_movie_primed_at']),
      lastAccessed: _parseDateTimeOrNow(json['lastAccessed']),
      cachedFiles: cachedFiles,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'videoId': videoId,
      'videoPathHash': videoPathHash,
      'sourceSignature': sourceSignature,
      'strategyVersion': strategyVersion,
      if (durationMs != null) 'durationMs': durationMs,
      if (fullMoviePrimedAt != null)
        'fullMoviePrimedAt': fullMoviePrimedAt!.toUtc().toIso8601String(),
      'lastAccessed': lastAccessed.toUtc().toIso8601String(),
      'cachedFiles': cachedFiles.values
          .map((entry) => entry.toJson())
          .toList(growable: false),
    };
  }

  static DateTime _parseDateTimeOrNow(dynamic value) {
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed.toLocal();
      }
    }
    return DateTime.now();
  }

  static int? _toIntOrNull(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value is! String) {
      return null;
    }
    return DateTime.tryParse(value)?.toLocal();
  }
}

class _CachedFileEntry {
  _CachedFileEntry({
    required this.file,
    required this.exact,
    required this.timestampMs,
    required this.width,
    required this.height,
    required this.sizeBytes,
    required this.createdAt,
    required this.lastAccessed,
  });

  String file;
  bool exact;
  int timestampMs;
  int width;
  int height;
  int sizeBytes;
  DateTime createdAt;
  DateTime lastAccessed;

  static _CachedFileEntry? tryFromJson(Map<String, dynamic> json) {
    final file = json['file']?.toString();
    final timestampMs = _toInt(json['timestampMs']);
    final width = _toInt(json['width']);
    final height = _toInt(json['height']);
    if (file == null ||
        timestampMs == null ||
        width == null ||
        height == null) {
      return null;
    }
    return _CachedFileEntry(
      file: file,
      exact: json['exact'] == true,
      timestampMs: timestampMs,
      width: width,
      height: height,
      sizeBytes: _toInt(json['sizeBytes']) ?? 0,
      createdAt: _parseDateTime(json['createdAt']) ?? DateTime.now(),
      lastAccessed: _parseDateTime(json['lastAccessed']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'file': file,
      'exact': exact,
      'timestampMs': timestampMs,
      'width': width,
      'height': height,
      'sizeBytes': sizeBytes,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'lastAccessed': lastAccessed.toUtc().toIso8601String(),
    };
  }

  static int? _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value is! String) {
      return null;
    }
    return DateTime.tryParse(value)?.toLocal();
  }
}

class _AsyncMutex {
  Future<void> _pending = Future<void>.value();

  Future<T> protect<T>(Future<T> Function() action) {
    final completer = Completer<void>();
    final previous = _pending;
    _pending = completer.future;
    return previous.then((_) => action()).whenComplete(() {
      completer.complete();
    });
  }
}
