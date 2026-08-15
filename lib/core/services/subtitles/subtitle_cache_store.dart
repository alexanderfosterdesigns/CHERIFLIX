import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';

import 'subdl_models.dart';

class SubtitleSearchCacheEntry {
  const SubtitleSearchCacheEntry({
    required this.searchKey,
    required this.fetchedAtUtc,
    required this.subtitles,
  });

  final String searchKey;
  final DateTime fetchedAtUtc;
  final List<SubdlSubtitle> subtitles;
}

class SubtitleOffsetCacheEntry {
  const SubtitleOffsetCacheEntry({
    required this.offsetKey,
    required this.offsetMs,
    this.updatedAtUtc,
  });

  final String offsetKey;
  final int offsetMs;
  final DateTime? updatedAtUtc;
}

class SubtitleCacheStore {
  SubtitleCacheStore({
    required Box<String> metadataBox,
    required Box<int> offsetBox,
    required Directory subtitleRootDirectory,
  })  : _metadataBox = metadataBox,
        _offsetBox = offsetBox,
        _subtitleRootDirectory = subtitleRootDirectory;

  static const Duration artifactTtl = Duration(days: 30);

  final Box<String> _metadataBox;
  final Box<int> _offsetBox;
  final Directory _subtitleRootDirectory;

  Directory get subtitleRootDirectory => _subtitleRootDirectory;

  Future<void> initializeDirectories() {
    return _subtitleRootDirectory.create(recursive: true);
  }

  Future<SubtitleSearchCacheEntry?> readSearchEntry(String searchKey) async {
    final raw = _metadataBox.get('search:$searchKey');
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final fetchedAtRaw = '${decoded['fetchedAtUtc'] ?? ''}';
    final fetchedAt = DateTime.tryParse(fetchedAtRaw)?.toUtc();
    if (fetchedAt == null) {
      return null;
    }
    final subtitles =
        (decoded['subtitles'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(SubdlSubtitle.fromJson)
            .toList(growable: false);
    return SubtitleSearchCacheEntry(
      searchKey: searchKey,
      fetchedAtUtc: fetchedAt,
      subtitles: subtitles,
    );
  }

  Future<void> writeSearchEntry(
    String searchKey,
    List<SubdlSubtitle> subtitles,
  ) {
    final payload = <String, dynamic>{
      'fetchedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'subtitles': subtitles
          .map((subtitle) => subtitle.toJson())
          .toList(growable: false),
    };
    return _metadataBox.put('search:$searchKey', jsonEncode(payload));
  }

  Future<String?> readArtifactPath(String subtitleId) async {
    final raw = _metadataBox.get('artifact:$subtitleId');
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final expiresAtRaw = '${decoded['expiresAtUtc'] ?? ''}';
    final path = '${decoded['path'] ?? ''}'.trim();
    final expiresAt = DateTime.tryParse(expiresAtRaw)?.toUtc();
    if (path.isEmpty || expiresAt == null) {
      return null;
    }
    if (DateTime.now().toUtc().isAfter(expiresAt)) {
      return null;
    }
    if (!await File(path).exists()) {
      return null;
    }
    return path;
  }

  Future<void> writeArtifactPath({
    required String subtitleId,
    required String path,
  }) {
    final expiresAt = DateTime.now().toUtc().add(artifactTtl);
    return _metadataBox.put(
      'artifact:$subtitleId',
      jsonEncode(
        <String, dynamic>{
          'path': path,
          'expiresAtUtc': expiresAt.toIso8601String(),
          'updatedAtUtc': DateTime.now().toUtc().toIso8601String(),
        },
      ),
    );
  }

  int readSubtitleOffsetMs(String offsetKey) {
    return _offsetBox.get(offsetKey) ?? 0;
  }

  int? readSubtitleOffsetMsIfPresent(String offsetKey) {
    if (!_offsetBox.containsKey(offsetKey)) {
      return null;
    }
    return _offsetBox.get(offsetKey);
  }

  List<SubtitleOffsetCacheEntry> readSubtitleOffsetEntriesByPrefix(
    String offsetKeyPrefix,
  ) {
    final entries = <SubtitleOffsetCacheEntry>[];
    for (final key in _offsetBox.keys) {
      final keyValue = '$key';
      if (!keyValue.startsWith(offsetKeyPrefix)) {
        continue;
      }
      final value = _offsetBox.get(keyValue);
      if (value == null) {
        continue;
      }
      DateTime? updatedAtUtc;
      final metadataRaw = _metadataBox.get('offsetmeta:$keyValue');
      if (metadataRaw != null && metadataRaw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(metadataRaw) as Map<String, dynamic>;
          final updatedAtRaw = '${decoded['updatedAtUtc'] ?? ''}'.trim();
          updatedAtUtc = DateTime.tryParse(updatedAtRaw)?.toUtc();
        } catch (_) {}
      }
      entries.add(
        SubtitleOffsetCacheEntry(
          offsetKey: keyValue,
          offsetMs: value,
          updatedAtUtc: updatedAtUtc,
        ),
      );
    }
    return entries;
  }

  Future<void> writeSubtitleOffsetMs(String offsetKey, int offsetMs) async {
    await _offsetBox.put(offsetKey, offsetMs);
    await _metadataBox.put(
      'offsetmeta:$offsetKey',
      jsonEncode(<String, dynamic>{
        'updatedAtUtc': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  Future<void> cleanupExpiredEntries() async {
    final now = DateTime.now().toUtc();
    final keysToDelete = <dynamic>[];
    for (final key in _metadataBox.keys) {
      final keyValue = '$key';
      if (!keyValue.startsWith('artifact:')) {
        continue;
      }
      final raw = _metadataBox.get(keyValue);
      if (raw == null || raw.trim().isEmpty) {
        keysToDelete.add(keyValue);
        continue;
      }
      Map<String, dynamic>? decoded;
      try {
        decoded = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        keysToDelete.add(keyValue);
        continue;
      }
      final path = '${decoded['path'] ?? ''}'.trim();
      final expiresAtRaw = '${decoded['expiresAtUtc'] ?? ''}';
      final expiresAt = DateTime.tryParse(expiresAtRaw)?.toUtc();
      final expired = expiresAt == null || now.isAfter(expiresAt);
      if (!expired) {
        continue;
      }
      keysToDelete.add(keyValue);
      if (path.isNotEmpty) {
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
    }
    if (keysToDelete.isNotEmpty) {
      await _metadataBox.deleteAll(keysToDelete);
    }
  }
}
