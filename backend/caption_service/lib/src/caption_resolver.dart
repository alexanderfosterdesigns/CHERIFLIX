import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'caption_models.dart';

abstract interface class ManualCaptionCatalog {
  Future<List<CaptionTrackRecord>> findTracks(CaptionRequestKey key);
}

abstract interface class GeneratedCaptionStore {
  Future<Uri?> findGeneratedUri(CaptionRequestKey key, {required Uri publicBaseUri});

  Future<Uri> saveGeneratedCaption(
    CaptionRequestKey key,
    String webVtt, {
    required Uri publicBaseUri,
  });
}

abstract interface class AutoCaptionGenerator {
  Future<String> generate(
    CaptionRequestKey key, {
    String? seedText,
  });
}

class InMemoryManualCaptionCatalog implements ManualCaptionCatalog {
  const InMemoryManualCaptionCatalog(this.entries);

  final Map<String, List<CaptionTrackRecord>> entries;

  @override
  Future<List<CaptionTrackRecord>> findTracks(CaptionRequestKey key) async {
    return entries[key.cacheKey] ?? const <CaptionTrackRecord>[];
  }
}

class HttpManualCaptionCatalog implements ManualCaptionCatalog {
  HttpManualCaptionCatalog({
    required this.catalogUri,
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  final Uri catalogUri;
  final HttpClient _client;
  static const Duration _requestTimeout = Duration(seconds: 10);
  static const int _maxAttempts = 3;

  @override
  Future<List<CaptionTrackRecord>> findTracks(CaptionRequestKey key) async {
    final uri = catalogUri.replace(queryParameters: <String, String>{
      'tmdbId': '${key.tmdbId}',
      'mediaType': key.mediaType,
      if (key.seasonNumber != null) 'seasonNumber': '${key.seasonNumber}',
      if (key.episodeNumber != null) 'episodeNumber': '${key.episodeNumber}',
      'languageCode': key.languageCode,
    });
    for (var attempt = 1; attempt <= _maxAttempts; attempt += 1) {
      try {
        final request = await _client.getUrl(uri).timeout(_requestTimeout);
        final response = await request.close().timeout(_requestTimeout);
        final body = await response
            .transform(utf8.decoder)
            .join()
            .timeout(_requestTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          if (!_isRetriableStatus(response.statusCode) ||
              attempt >= _maxAttempts) {
            return const <CaptionTrackRecord>[];
          }
        } else {
          final payload = jsonDecode(body);
          final rawTracks = switch (payload) {
            {'tracks': final List<dynamic> tracks} => tracks,
            final List<dynamic> tracks => tracks,
            _ => const <dynamic>[],
          };
          return rawTracks
              .whereType<Map<String, dynamic>>()
              .map(CaptionTrackRecord.fromJson)
              .toList(growable: false);
        }
      } on TimeoutException {
        if (attempt >= _maxAttempts) {
          return const <CaptionTrackRecord>[];
        }
      } on SocketException {
        if (attempt >= _maxAttempts) {
          return const <CaptionTrackRecord>[];
        }
      }
      await Future<void>.delayed(Duration(milliseconds: 240 * attempt));
    }
    return const <CaptionTrackRecord>[];
  }

  bool _isRetriableStatus(int statusCode) {
    return statusCode == 429 || statusCode >= 500;
  }
}

class FileGeneratedCaptionStore implements GeneratedCaptionStore {
  FileGeneratedCaptionStore(this.directory);

  final Directory directory;

  @override
  Future<Uri?> findGeneratedUri(CaptionRequestKey key,
      {required Uri publicBaseUri}) async {
    final file = File(
      '${directory.path}${Platform.pathSeparator}${key.cacheKey}.vtt',
    );
    if (!await file.exists()) {
      return null;
    }
    return _publicUriForFile(key, publicBaseUri);
  }

  @override
  Future<Uri> saveGeneratedCaption(
    CaptionRequestKey key,
    String webVtt, {
    required Uri publicBaseUri,
  }) async {
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${key.cacheKey}.vtt',
    );
    await file.writeAsString(webVtt);
    return _publicUriForFile(key, publicBaseUri);
  }

  Uri _publicUriForFile(CaptionRequestKey key, Uri publicBaseUri) {
    return publicBaseUri.replace(
      path:
          '${publicBaseUri.path.replaceFirst(RegExp(r'/$'), '')}/generated/${key.cacheKey}.vtt',
    );
  }
}

class LightEnglishCaptionGenerator implements AutoCaptionGenerator {
  const LightEnglishCaptionGenerator();

  @override
  Future<String> generate(
    CaptionRequestKey key, {
    String? seedText,
  }) async {
    final text = (seedText?.trim().isNotEmpty ?? false)
        ? seedText!.trim()
        : 'Automatic English captions for ${key.mediaType} ${key.tmdbId}.';
    final segments = text
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);
    final buffer = StringBuffer('WEBVTT\n\n');
    var start = Duration.zero;
    for (final segment in segments.take(12)) {
      final end = start + const Duration(seconds: 3);
      buffer
        ..writeln('${_formatTime(start)} --> ${_formatTime(end)}')
        ..writeln(segment.trim())
        ..writeln();
      start = end + const Duration(milliseconds: 250);
    }
    return buffer.toString();
  }

  String _formatTime(Duration value) {
    final hours = value.inHours.toString().padLeft(2, '0');
    final minutes = (value.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    final millis =
        (value.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$hours:$minutes:$seconds.$millis';
  }
}

class CaptionResolver {
  const CaptionResolver({
    required this.manualCatalog,
    required this.generatedCaptionStore,
    required this.autoCaptionGenerator,
  });

  final ManualCaptionCatalog manualCatalog;
  final GeneratedCaptionStore generatedCaptionStore;
  final AutoCaptionGenerator autoCaptionGenerator;

  Future<CaptionResolutionPayload> resolve(
    CaptionRequestKey key, {
    required Uri publicBaseUri,
  }) async {
    final manualTracks = await manualCatalog.findTracks(key);
    final tracks = <CaptionTrackRecord>[
      ...manualTracks.map((track) => track.copyWith(isDefault: false)),
    ];

    final hasManualEnglish = manualTracks.any(
      (track) => track.languageCode.toLowerCase() == 'en',
    );
    if (!hasManualEnglish) {
      final autoTrack =
          await _ensureAutoEnglishTrack(key, publicBaseUri: publicBaseUri);
      tracks.add(autoTrack);
    }

    final selectedTrackId = tracks.isEmpty ? null : tracks.first.id;
    final normalizedTracks = tracks
        .map((track) => track.copyWith(isDefault: track.id == selectedTrackId))
        .toList(growable: false);
    return CaptionResolutionPayload(
      tracks: normalizedTracks,
      selectedTrackId: selectedTrackId,
    );
  }

  Future<CaptionTrackRecord> generate(
    CaptionRequestKey key, {
    required Uri publicBaseUri,
    String? seedText,
  }) async {
    final webVtt = await autoCaptionGenerator.generate(key, seedText: seedText);
    final uri = await generatedCaptionStore.saveGeneratedCaption(
      key,
      webVtt,
      publicBaseUri: publicBaseUri,
    );
    return CaptionTrackRecord(
      id: 'auto-${key.cacheKey}',
      label: 'Auto English',
      languageCode: 'en',
      kind: CaptionTrackKind.auto,
      format: CaptionTrackFormat.vtt,
      url: uri,
      isDefault: false,
    );
  }

  Future<CaptionTrackRecord> _ensureAutoEnglishTrack(
    CaptionRequestKey key, {
    required Uri publicBaseUri,
  }) async {
    final existing = await generatedCaptionStore.findGeneratedUri(
      key,
      publicBaseUri: publicBaseUri,
    );
    if (existing != null) {
      return CaptionTrackRecord(
        id: 'auto-${key.cacheKey}',
        label: 'Auto English',
        languageCode: 'en',
        kind: CaptionTrackKind.auto,
        format: CaptionTrackFormat.vtt,
        url: existing,
      );
    }
    return generate(key, publicBaseUri: publicBaseUri);
  }
}
