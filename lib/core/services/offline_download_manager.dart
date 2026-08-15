import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/media_type.dart';
import '../models/playback_target.dart';
import '../utils/safe_logging.dart';
import 'offline_media_library.dart';

export 'offline_media_library.dart';

enum OfflineDownloadStatus {
  queued,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}

enum OfflineDownloadQuality {
  dataSaver(maxHeight: 480, maxBitrate: 1600000, label: 'Data Saver'),
  balanced(maxHeight: 720, maxBitrate: 3500000, label: 'Balanced 720p'),
  high(maxHeight: 1080, maxBitrate: 6500000, label: 'High 1080p');

  const OfflineDownloadQuality({
    required this.maxHeight,
    required this.maxBitrate,
    required this.label,
  });

  final int maxHeight;
  final int maxBitrate;
  final String label;
}

class OfflineDownloadRecord {
  const OfflineDownloadRecord({
    required this.key,
    required this.title,
    required this.status,
    required this.quality,
    required this.progress,
    required this.bytesDownloaded,
    required this.totalBytes,
    required this.localPath,
    required this.providerKey,
    required this.updatedAt,
    this.error,
  });

  final OfflineMediaKey key;
  final String title;
  final OfflineDownloadStatus status;
  final OfflineDownloadQuality quality;
  final double progress;
  final int bytesDownloaded;
  final int? totalBytes;
  final String localPath;
  final String providerKey;
  final DateTime updatedAt;
  final String? error;

  OfflineDownloadRecord copyWith({
    OfflineDownloadStatus? status,
    double? progress,
    int? bytesDownloaded,
    int? totalBytes,
    String? localPath,
    String? error,
    bool clearError = false,
  }) {
    return OfflineDownloadRecord(
      key: key,
      title: title,
      status: status ?? this.status,
      quality: quality,
      progress: progress ?? this.progress,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      totalBytes: totalBytes ?? this.totalBytes,
      localPath: localPath ?? this.localPath,
      providerKey: providerKey,
      updatedAt: DateTime.now(),
      error: clearError ? null : error ?? this.error,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'tmdbId': key.tmdbId,
        'mediaType': key.mediaType.name,
        if (key.seasonNumber != null) 'seasonNumber': key.seasonNumber,
        if (key.episodeNumber != null) 'episodeNumber': key.episodeNumber,
        'title': title,
        'status': status.name,
        'quality': quality.name,
        'progress': progress,
        'bytesDownloaded': bytesDownloaded,
        if (totalBytes != null) 'totalBytes': totalBytes,
        'localPath': localPath,
        'providerKey': providerKey,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        if (error != null) 'error': error,
      };

  factory OfflineDownloadRecord.fromJson(Map<String, Object?> json) {
    final mediaTypeName = '${json['mediaType']}';
    return OfflineDownloadRecord(
      key: OfflineMediaKey(
        tmdbId: (json['tmdbId'] as num).toInt(),
        mediaType: mediaTypeName == 'tv' ? MediaType.tv : MediaType.movie,
        seasonNumber: (json['seasonNumber'] as num?)?.toInt(),
        episodeNumber: (json['episodeNumber'] as num?)?.toInt(),
      ),
      title: '${json['title']}',
      status: OfflineDownloadStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => OfflineDownloadStatus.failed,
      ),
      quality: OfflineDownloadQuality.values.firstWhere(
        (value) => value.name == json['quality'],
        orElse: () => OfflineDownloadQuality.balanced,
      ),
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      bytesDownloaded: (json['bytesDownloaded'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt(),
      localPath: '${json['localPath']}',
      providerKey: '${json['providerKey']}',
      updatedAt: DateTime.tryParse('${json['updatedAt']}') ?? DateTime.now(),
      error: json['error']?.toString(),
    );
  }
}

class OfflineDownloadException implements Exception {
  const OfflineDownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Downloads direct playback targets through the normal validated media path.
/// HLS manifests and every referenced key, map, and segment are stored together
/// so the local player sees the same media structure as the streaming player.
class OfflineDownloadManager extends ChangeNotifier
    implements OfflineMediaLibrary {
  OfflineDownloadManager._({
    required Directory rootDirectory,
    HttpClient? httpClient,
  })  : _rootDirectory = rootDirectory,
        _httpClient = httpClient ?? HttpClient();

  static Future<OfflineDownloadManager> open({
    required Directory rootDirectory,
    HttpClient? httpClient,
  }) async {
    final manager = OfflineDownloadManager._(
      rootDirectory: rootDirectory,
      httpClient: httpClient,
    );
    await manager._initialize();
    return manager;
  }

  Directory _rootDirectory;
  final HttpClient _httpClient;
  final Map<String, OfflineDownloadRecord> _records =
      <String, OfflineDownloadRecord>{};
  final Map<String, _DownloadControl> _controls = <String, _DownloadControl>{};
  Future<void> _saveQueue = Future<void>.value();
  Timer? _persistDebounce;
  OfflineDownloadQuality defaultQuality = OfflineDownloadQuality.balanced;

  String get downloadLocation => _rootDirectory.path;

  List<OfflineDownloadRecord> get records {
    final result = _records.values.toList(growable: false)
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return result;
  }

  int get completedBytes => _records.values
      .where((record) => record.status == OfflineDownloadStatus.completed)
      .fold(0, (total, record) => total + record.bytesDownloaded);

  OfflineDownloadRecord? recordFor(OfflineMediaKey key) => _records[key.value];

  Future<void> enqueue({
    required OfflineMediaKey key,
    required String title,
    required PlaybackTarget target,
    OfflineDownloadQuality? quality,
  }) async {
    if (!target.isDirectPlayable ||
        target.sourceKind == PlaybackSourceKind.embed) {
      throw const OfflineDownloadException(
        'A validated direct source is required for downloading.',
      );
    }
    final existing = _records[key.value];
    if (existing != null &&
        existing.status != OfflineDownloadStatus.failed &&
        existing.status != OfflineDownloadStatus.cancelled) {
      throw const OfflineDownloadException(
        'This title is already downloaded or downloading.',
      );
    }

    final contentDirectory = Directory(
      '${_rootDirectory.path}${Platform.pathSeparator}${_safeName(key.value)}',
    );
    await contentDirectory.create(recursive: true);
    final record = OfflineDownloadRecord(
      key: key,
      title: title,
      status: OfflineDownloadStatus.queued,
      quality: quality ?? defaultQuality,
      progress: 0,
      bytesDownloaded: 0,
      totalBytes: null,
      localPath: contentDirectory.path,
      providerKey: target.providerKey,
      updatedAt: DateTime.now(),
    );
    _records[key.value] = record;
    final control = _DownloadControl();
    _controls[key.value] = control;
    await _persist();
    notifyListeners();
    unawaited(_runDownload(record, target, control));
  }

  Future<void> pause(OfflineMediaKey key) async {
    final control = _controls[key.value];
    final record = _records[key.value];
    if (control == null ||
        record?.status != OfflineDownloadStatus.downloading) {
      return;
    }
    control.paused = true;
    _replace(record!.copyWith(status: OfflineDownloadStatus.paused));
  }

  Future<void> resume(OfflineMediaKey key) async {
    final control = _controls[key.value];
    final record = _records[key.value];
    if (control == null || record?.status != OfflineDownloadStatus.paused) {
      return;
    }
    control.paused = false;
    control.resumeSignal?.complete();
    control.resumeSignal = null;
    _replace(record!.copyWith(status: OfflineDownloadStatus.downloading));
  }

  Future<void> cancel(OfflineMediaKey key) async {
    final control = _controls[key.value];
    control?.cancelled = true;
    control?.resumeSignal?.complete();
    control?.resumeSignal = null;
    final record = _records[key.value];
    if (record != null) {
      _replace(record.copyWith(status: OfflineDownloadStatus.cancelled));
    }
  }

  Future<void> retry({
    required OfflineMediaKey key,
    required PlaybackTarget target,
  }) async {
    final record = _records[key.value];
    if (record == null) {
      throw const OfflineDownloadException('Download record not found.');
    }
    await delete(key);
    await enqueue(
      key: key,
      title: record.title,
      target: target,
      quality: record.quality,
    );
  }

  Future<void> delete(OfflineMediaKey key) async {
    _controls.remove(key.value)?.cancelled = true;
    final record = _records.remove(key.value);
    if (record != null) {
      final localEntity = File(record.localPath);
      final directory = record.status == OfflineDownloadStatus.completed
          ? localEntity.parent
          : Directory(record.localPath);
      if (await directory.exists() && _isWithinRoot(directory.absolute.path)) {
        await directory.delete(recursive: true);
      }
    }
    await _persist();
    notifyListeners();
  }

  Future<void> changeDownloadLocation(Directory directory) async {
    if (_records.values.any(
      (record) =>
          record.status == OfflineDownloadStatus.downloading ||
          record.status == OfflineDownloadStatus.queued,
    )) {
      throw const OfflineDownloadException(
        'Pause or finish active downloads before changing the location.',
      );
    }
    await directory.create(recursive: true);
    final probe = File(
      '${directory.path}${Platform.pathSeparator}.cheriflix-write-test',
    );
    await probe.writeAsString('ok', flush: true);
    await probe.delete();
    _rootDirectory = directory;
    await _persist();
    notifyListeners();
  }

  @override
  Future<PlaybackTarget?> findCompletedTarget(OfflineMediaKey key) async {
    final record = _records[key.value];
    if (record == null || record.status != OfflineDownloadStatus.completed) {
      return null;
    }
    final mediaFile = File(record.localPath);
    if (!await _isValidCompletedFile(mediaFile)) {
      _replace(
        record.copyWith(
          status: OfflineDownloadStatus.failed,
          error: 'The local download is incomplete or corrupt.',
        ),
      );
      return null;
    }
    return PlaybackTarget(
      uri: mediaFile.uri,
      providerKey: 'offline',
      providerLabel: 'Downloaded',
      providerIndex: -1,
      sourceKind: mediaFile.path.toLowerCase().endsWith('.m3u8')
          ? PlaybackSourceKind.hls
          : PlaybackSourceKind.file,
      offlineStorageAllowed: true,
      qualityLabel: record.quality.label,
    );
  }

  Future<void> _initialize() async {
    await _rootDirectory.create(recursive: true);
    final metadata = _metadataFile;
    if (!await metadata.exists()) {
      return;
    }
    try {
      final decoded = jsonDecode(await metadata.readAsString());
      if (decoded is List) {
        for (final item in decoded.whereType<Map>()) {
          final record = OfflineDownloadRecord.fromJson(
            item.cast<String, Object?>(),
          );
          final recovered = switch (record.status) {
            OfflineDownloadStatus.downloading ||
            OfflineDownloadStatus.queued ||
            OfflineDownloadStatus.paused =>
              record.copyWith(
                status: OfflineDownloadStatus.failed,
                error: 'Download was interrupted. Retry to continue.',
              ),
            _ => record,
          };
          _records[record.key.value] = recovered;
        }
      }
    } catch (error) {
      cheriflixLog('offline-downloads', 'Could not read download metadata.',
          error: error);
    }
  }

  Future<void> _runDownload(
    OfflineDownloadRecord initial,
    PlaybackTarget target,
    _DownloadControl control,
  ) async {
    OfflineDownloadRecord? terminalRecord;
    try {
      _replace(initial.copyWith(status: OfflineDownloadStatus.downloading));
      final output = target.sourceKind == PlaybackSourceKind.hls ||
              target.uri.path.toLowerCase().endsWith('.m3u8')
          ? await _downloadHls(initial, target, control)
          : await _downloadFile(initial, target, control);
      if (control.cancelled) {
        return;
      }
      final current = _records[initial.key.value]!;
      terminalRecord = current.copyWith(
        status: OfflineDownloadStatus.completed,
        progress: 1,
        localPath: output.path,
        clearError: true,
      );
    } on _DownloadCancelled {
      // State was already set by cancel().
    } catch (error, stackTrace) {
      cheriflixLog(
        'offline-downloads',
        'Download failed key=${initial.key.value}.',
        error: error,
        stackTrace: stackTrace,
      );
      final current = _records[initial.key.value];
      if (current != null &&
          current.status != OfflineDownloadStatus.cancelled) {
        terminalRecord = current.copyWith(
          status: OfflineDownloadStatus.failed,
          error: 'Download failed. Check the connection and retry.',
        );
      }
    } finally {
      _persistDebounce?.cancel();
      _controls.remove(initial.key.value);
      await _persist(terminalOverride: terminalRecord);
      if (terminalRecord != null) {
        _records[initial.key.value] = terminalRecord;
      }
      notifyListeners();
    }
  }

  Future<File> _downloadHls(
    OfflineDownloadRecord record,
    PlaybackTarget target,
    _DownloadControl control,
  ) async {
    var manifestUri = target.uri;
    var manifest = utf8.decode(
      await _getBytes(manifestUri, headers: target.httpHeaders),
    );
    for (var depth = 0; depth < 3; depth += 1) {
      final selected = _selectVariant(manifestUri, manifest, record.quality);
      if (selected == null) break;
      manifestUri = selected;
      manifest = utf8.decode(
        await _getBytes(manifestUri, headers: target.httpHeaders),
      );
    }
    if (!manifest.trimLeft().startsWith('#EXTM3U')) {
      throw const OfflineDownloadException('Invalid HLS manifest.');
    }
    final resources = _manifestResources(manifestUri, manifest);
    if (resources.isEmpty) {
      throw const OfflineDownloadException(
          'HLS manifest has no media segments.');
    }
    final outputDirectory = Directory(record.localPath);
    var rewritten = manifest;
    var downloadedBytes = 0;
    for (var index = 0; index < resources.length; index += 1) {
      await _waitIfPaused(control);
      final resource = resources[index];
      final extension = _safeExtension(resource.uri.path);
      final localName =
          'resource_${index.toString().padLeft(5, '0')}$extension';
      final file = File(
        '${outputDirectory.path}${Platform.pathSeparator}$localName.part',
      );
      final bytes = await _getBytes(
        resource.uri,
        headers: target.httpHeaders,
      );
      if (bytes.isEmpty) {
        throw const OfflineDownloadException('An HLS segment was empty.');
      }
      await file.writeAsBytes(bytes, flush: true);
      final completedFile = File(file.path.substring(0, file.path.length - 5));
      await file.rename(completedFile.path);
      rewritten = rewritten.replaceAll(resource.originalReference, localName);
      downloadedBytes += bytes.length;
      final current = _records[record.key.value]!;
      _replace(
        current.copyWith(
          progress: (index + 1) / resources.length,
          bytesDownloaded: downloadedBytes,
        ),
      );
    }
    final playlist = File(
      '${outputDirectory.path}${Platform.pathSeparator}offline.m3u8',
    );
    await playlist.writeAsString(rewritten, flush: true);
    return playlist;
  }

  Future<File> _downloadFile(
    OfflineDownloadRecord record,
    PlaybackTarget target,
    _DownloadControl control,
  ) async {
    final extension = _safeExtension(target.uri.path, fallback: '.mp4');
    final part = File(
      '${record.localPath}${Platform.pathSeparator}media$extension.part',
    );
    final request = await _httpClient.getUrl(target.uri).timeout(
          const Duration(seconds: 10),
        );
    target.httpHeaders.forEach(request.headers.set);
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OfflineDownloadException(
        'Media request failed (${response.statusCode}).',
      );
    }
    final total = response.contentLength > 0 ? response.contentLength : null;
    final sink = part.openWrite();
    var downloaded = 0;
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 25))) {
        await _waitIfPaused(control);
        sink.add(chunk);
        downloaded += chunk.length;
        final current = _records[record.key.value]!;
        _replace(
          current.copyWith(
            progress: total == null ? current.progress : downloaded / total,
            bytesDownloaded: downloaded,
            totalBytes: total,
          ),
        );
      }
    } finally {
      await sink.close();
    }
    if (downloaded <= 0 || total != null && downloaded != total) {
      throw const OfflineDownloadException('Downloaded file is incomplete.');
    }
    final completed = File(part.path.substring(0, part.path.length - 5));
    return part.rename(completed.path);
  }

  Future<Uint8List> _getBytes(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt += 1) {
      try {
        final request = await _httpClient.getUrl(uri).timeout(
              const Duration(seconds: 8),
            );
        headers.forEach(request.headers.set);
        final response = await request.close().timeout(
              const Duration(seconds: 12),
            );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException('HTTP ${response.statusCode}', uri: uri);
        }
        final builder = BytesBuilder(copy: false);
        await for (final chunk
            in response.timeout(const Duration(seconds: 20))) {
          builder.add(chunk);
        }
        return builder.takeBytes();
      } catch (error) {
        lastError = error;
        if (attempt < 2) {
          await Future<void>.delayed(
              Duration(milliseconds: 250 * (attempt + 1)));
        }
      }
    }
    throw OfflineDownloadException('Network request failed: $lastError');
  }

  Uri? _selectVariant(
    Uri baseUri,
    String manifest,
    OfflineDownloadQuality quality,
  ) {
    final lines = manifest.split(RegExp(r'[\r\n]+'));
    final variants = <_HlsVariant>[];
    for (var index = 0; index + 1 < lines.length; index += 1) {
      final line = lines[index].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF:')) {
        continue;
      }
      final next = lines[index + 1].trim();
      if (next.isEmpty || next.startsWith('#')) {
        continue;
      }
      final bandwidth = int.tryParse(
            RegExp(r'BANDWIDTH=(\d+)').firstMatch(line)?.group(1) ?? '',
          ) ??
          0;
      final height = int.tryParse(
            RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(line)?.group(1) ?? '',
          ) ??
          0;
      variants.add(
        _HlsVariant(baseUri.resolve(next),
            bandwidth: bandwidth, height: height),
      );
    }
    if (variants.isEmpty) {
      return null;
    }
    final withinLimit = variants
        .where(
          (variant) =>
              (variant.height == 0 || variant.height <= quality.maxHeight) &&
              (variant.bandwidth == 0 ||
                  variant.bandwidth <= quality.maxBitrate),
        )
        .toList();
    final candidates = withinLimit.isEmpty ? variants : withinLimit;
    candidates.sort((left, right) {
      final height = right.height.compareTo(left.height);
      return height != 0 ? height : right.bandwidth.compareTo(left.bandwidth);
    });
    return candidates.first.uri;
  }

  List<_ManifestResource> _manifestResources(Uri baseUri, String manifest) {
    final result = <_ManifestResource>[];
    final seen = <String>{};
    for (final line in manifest.split(RegExp(r'[\r\n]+'))) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
        final uri = baseUri.resolve(trimmed);
        if (seen.add(uri.toString())) {
          result.add(_ManifestResource(uri, trimmed));
        }
      }
      for (final match in RegExp(r'URI="([^"]+)"').allMatches(line)) {
        final reference = match.group(1)!;
        final uri = baseUri.resolve(reference);
        if (seen.add(uri.toString())) {
          result.add(_ManifestResource(uri, reference));
        }
      }
    }
    return result;
  }

  Future<void> _waitIfPaused(_DownloadControl control) async {
    if (control.cancelled) {
      throw const _DownloadCancelled();
    }
    while (control.paused) {
      control.resumeSignal ??= Completer<void>();
      await control.resumeSignal!.future;
      if (control.cancelled) {
        throw const _DownloadCancelled();
      }
    }
  }

  void _replace(OfflineDownloadRecord record) {
    _records[record.key.value] = record;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(
      const Duration(milliseconds: 750),
      () => unawaited(_persist()),
    );
    notifyListeners();
  }

  Future<void> _persist({OfflineDownloadRecord? terminalOverride}) {
    final snapshot = <OfflineDownloadRecord>[
      for (final record in _records.values)
        if (record.key.value == terminalOverride?.key.value)
          terminalOverride!
        else
          record,
    ];
    _saveQueue = _saveQueue.then((_) async {
      final temporary = File('${_metadataFile.path}.tmp');
      await temporary.writeAsString(
        jsonEncode(snapshot.map((record) => record.toJson()).toList()),
        flush: true,
      );
      if (await _metadataFile.exists()) {
        await _metadataFile.delete();
      }
      await temporary.rename(_metadataFile.path);
    });
    return _saveQueue;
  }

  Future<bool> _isValidCompletedFile(File file) async {
    if (!await file.exists() || await file.length() <= 0) {
      return false;
    }
    if (!file.path.toLowerCase().endsWith('.m3u8')) {
      return true;
    }
    final body = await file.readAsString();
    if (!body.trimLeft().startsWith('#EXTM3U')) {
      return false;
    }
    for (final line in body.split(RegExp(r'[\r\n]+'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }
      final resource = File(
        '${file.parent.path}${Platform.pathSeparator}$trimmed',
      );
      if (!await resource.exists() || await resource.length() <= 0) {
        return false;
      }
    }
    return true;
  }

  File get _metadataFile => File(
        '${_rootDirectory.path}${Platform.pathSeparator}downloads.json',
      );

  bool _isWithinRoot(String path) {
    final root = '${_rootDirectory.absolute.path}${Platform.pathSeparator}';
    return path.startsWith(root);
  }

  String _safeName(String value) => value
      .replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_');

  String _safeExtension(String path, {String fallback = '.bin'}) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || name.length - dot > 8) {
      return fallback;
    }
    final extension = name.substring(dot).toLowerCase();
    return RegExp(r'^\.[a-z0-9]{1,7}$').hasMatch(extension)
        ? extension
        : fallback;
  }

  @override
  void dispose() {
    _persistDebounce?.cancel();
    _httpClient.close(force: true);
    super.dispose();
  }
}

class _DownloadControl {
  bool paused = false;
  bool cancelled = false;
  Completer<void>? resumeSignal;
}

class _HlsVariant {
  const _HlsVariant(this.uri, {required this.bandwidth, required this.height});
  final Uri uri;
  final int bandwidth;
  final int height;
}

class _ManifestResource {
  const _ManifestResource(this.uri, this.originalReference);
  final Uri uri;
  final String originalReference;
}

class _DownloadCancelled implements Exception {
  const _DownloadCancelled();
}
