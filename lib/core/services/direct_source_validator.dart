import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/playback_target.dart';

class DirectSourceValidationResult {
  const DirectSourceValidationResult({
    required this.playable,
    required this.stage,
    this.statusCode,
    this.reason,
    this.details = const <String, Object?>{},
  });

  final bool playable;
  final String stage;
  final int? statusCode;
  final String? reason;
  final Map<String, Object?> details;
}

abstract interface class DirectSourceValidator {
  Future<DirectSourceValidationResult> validate(PlaybackTarget target);
}

class HttpDirectSourceValidator implements DirectSourceValidator {
  HttpDirectSourceValidator({HttpClient? client})
      : _client = client ?? _createValidationHttpClient();

  final HttpClient _client;
  static const Duration _requestTimeout = Duration(seconds: 5);
  static const int _bodyLimit = 512 * 1024;

  @override
  Future<DirectSourceValidationResult> validate(
    PlaybackTarget target,
  ) async {
    final uri = target.uri;
    if (uri.scheme == 'file') {
      final file = File.fromUri(uri);
      final valid = await file.exists() && await file.length() > 0;
      return DirectSourceValidationResult(
        playable: valid,
        stage: 'local-file',
        reason: valid ? null : 'missing-or-empty',
      );
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      return const DirectSourceValidationResult(
        playable: false,
        stage: 'url',
        reason: 'unsupported-scheme',
      );
    }
    final expiresAt = target.expiresAtEpochMs;
    if (expiresAt != null &&
        expiresAt <= DateTime.now().millisecondsSinceEpoch + 5000) {
      return const DirectSourceValidationResult(
        playable: false,
        stage: 'url',
        reason: 'expired',
      );
    }
    try {
      final path = uri.path.toLowerCase();
      if (target.sourceKind == PlaybackSourceKind.hls ||
          path.endsWith('.m3u8')) {
        // Await here so network timeouts from child manifests or segments are
        // classified as validation failures instead of escaping as resolver
        // exceptions in the provider pipeline.
        return await _validateHls(uri, target.httpHeaders);
      }
      if (path.endsWith('.mpd')) {
        final response = await _read(uri, target.httpHeaders);
        final body = utf8.decode(response.bytes, allowMalformed: true);
        final playable = response.statusCode >= 200 &&
            response.statusCode < 300 &&
            RegExp(r'<(?:[\w-]+:)?MPD(?:\s|>)', caseSensitive: false)
                .hasMatch(body);
        return DirectSourceValidationResult(
          playable: playable,
          stage: 'dash-manifest',
          statusCode: response.statusCode,
          reason: playable ? null : 'invalid-mpd',
        );
      }
      final response = await _read(
        uri,
        <String, String>{...target.httpHeaders, 'Range': 'bytes=0-2047'},
      );
      final prefix = utf8
          .decode(response.bytes.take(128).toList(), allowMalformed: true)
          .trimLeft()
          .toLowerCase();
      final playable =
          (response.statusCode == 200 || response.statusCode == 206) &&
              response.bytes.isNotEmpty &&
              !prefix.startsWith('<!doctype html') &&
              !prefix.startsWith('<html');
      return DirectSourceValidationResult(
        playable: playable,
        stage: 'file-prefix',
        statusCode: response.statusCode,
        reason: playable ? null : 'invalid-media-response',
      );
    } on TimeoutException {
      return const DirectSourceValidationResult(
        playable: false,
        stage: 'network',
        reason: 'timeout',
      );
    } on Object catch (error) {
      return DirectSourceValidationResult(
        playable: false,
        stage: 'network',
        reason: error.runtimeType.toString(),
      );
    }
  }

  Future<DirectSourceValidationResult> _validateHls(
    Uri manifestUri,
    Map<String, String> headers,
  ) async {
    var response = await _read(manifestUri, headers);
    var effectiveManifestUri = response.effectiveUri;
    var manifest = utf8.decode(response.bytes, allowMalformed: true);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !manifest.trimLeft().startsWith('#EXTM3U')) {
      return DirectSourceValidationResult(
        playable: false,
        stage: 'hls-manifest',
        statusCode: response.statusCode,
        reason: 'invalid-manifest',
      );
    }

    var manifestDepth = 0;
    while (_isMasterPlaylist(manifest) && manifestDepth < 3) {
      final childReference = _firstVariantReference(manifest);
      if (childReference == null) {
        return const DirectSourceValidationResult(
          playable: false,
          stage: 'hls-manifest',
          reason: 'master-without-variant',
        );
      }
      final childUri = effectiveManifestUri.resolve(childReference);
      response = await _read(childUri, headers);
      effectiveManifestUri = response.effectiveUri;
      manifest = utf8.decode(response.bytes, allowMalformed: true);
      manifestDepth += 1;
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          !manifest.trimLeft().startsWith('#EXTM3U')) {
        return DirectSourceValidationResult(
          playable: false,
          stage: 'hls-media-manifest',
          statusCode: response.statusCode,
          reason: 'invalid-media-manifest',
          details: <String, Object?>{'depth': manifestDepth},
        );
      }
    }
    if (_isMasterPlaylist(manifest)) {
      return const DirectSourceValidationResult(
        playable: false,
        stage: 'hls-media-manifest',
        reason: 'manifest-nesting-too-deep',
      );
    }

    final keyValidation = await _validateHlsKey(
      effectiveManifestUri,
      manifest,
      headers,
    );
    if (keyValidation != null) return keyValidation;

    final initReference = _quotedAttributeReference(manifest, '#EXT-X-MAP');
    if (initReference != null) {
      final init = await _read(
        effectiveManifestUri.resolve(initReference),
        <String, String>{...headers, 'Range': 'bytes=0-4095'},
      );
      if (!_isUsableMediaResponse(init)) {
        return DirectSourceValidationResult(
          playable: false,
          stage: 'hls-init-segment',
          statusCode: init.statusCode,
          reason: 'invalid-init-segment',
        );
      }
    }

    final reference = _firstMediaReference(manifest);
    if (reference == null) {
      return const DirectSourceValidationResult(
        playable: false,
        stage: 'hls-media-manifest',
        reason: 'empty-media-manifest',
      );
    }
    final mediaUri = effectiveManifestUri.resolve(reference);
    final segment = await _read(
      mediaUri,
      <String, String>{...headers, 'Range': 'bytes=0-4095'},
    );
    final prefix = utf8
        .decode(segment.bytes.take(128).toList(), allowMalformed: true)
        .trimLeft()
        .toLowerCase();
    final playable = _isUsableMediaResponse(segment) &&
        !prefix.startsWith('<!doctype html') &&
        !prefix.startsWith('<html');
    return DirectSourceValidationResult(
      playable: playable,
      stage: 'hls-segment',
      statusCode: segment.statusCode,
      reason: playable ? null : 'invalid-segment',
      details: <String, Object?>{
        'manifestDepth': manifestDepth,
        'segmentHost': segment.effectiveUri.host,
      },
    );
  }

  Future<DirectSourceValidationResult?> _validateHlsKey(
    Uri manifestUri,
    String manifest,
    Map<String, String> headers,
  ) async {
    final keyLine = manifest
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.toUpperCase().startsWith('#EXT-X-KEY:'))
        .firstOrNull;
    if (keyLine == null ||
        RegExp(r'METHOD=NONE(?:,|$)', caseSensitive: false).hasMatch(keyLine)) {
      return null;
    }
    final method = RegExp(r'METHOD=([^,]+)', caseSensitive: false)
            .firstMatch(keyLine)
            ?.group(1)
            ?.trim()
            .toUpperCase() ??
        '';
    // Only AES-128 identity keys can be meaningfully preflighted as ordinary
    // bytes here. Do not reject other key metadata by policy: segment probing
    // and the real Android player remain the authority on playability.
    final keyFormat = RegExp(
      r'KEYFORMAT="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(keyLine)?.group(1);
    if (method != 'AES-128' ||
        keyFormat != null && keyFormat.toLowerCase() != 'identity') {
      return null;
    }
    final keyReference = RegExp(
      r'URI="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(keyLine)?.group(1);
    if (keyReference == null || keyReference.trim().isEmpty) {
      return const DirectSourceValidationResult(
        playable: false,
        stage: 'hls-key',
        reason: 'missing-key-uri',
      );
    }
    final response = await _read(manifestUri.resolve(keyReference), headers);
    final prefix = utf8
        .decode(response.bytes.take(64).toList(), allowMalformed: true)
        .trimLeft()
        .toLowerCase();
    final playable = response.statusCode >= 200 &&
        response.statusCode < 300 &&
        response.bytes.isNotEmpty &&
        !prefix.startsWith('<!doctype html') &&
        !prefix.startsWith('<html');
    return playable
        ? null
        : DirectSourceValidationResult(
            playable: false,
            stage: 'hls-key',
            statusCode: response.statusCode,
            reason: 'key-request-failed',
          );
  }

  bool _isMasterPlaylist(String manifest) =>
      manifest.toUpperCase().contains('#EXT-X-STREAM-INF:');

  String? _firstVariantReference(String manifest) {
    final lines = manifest.split(RegExp(r'[\r\n]+'));
    for (var index = 0; index < lines.length; index += 1) {
      if (!lines[index].trim().toUpperCase().startsWith('#EXT-X-STREAM-INF:')) {
        continue;
      }
      for (var next = index + 1; next < lines.length; next += 1) {
        final candidate = lines[next].trim();
        if (candidate.isEmpty) continue;
        if (candidate.startsWith('#')) break;
        return candidate;
      }
    }
    return null;
  }

  String? _quotedAttributeReference(String manifest, String tag) {
    for (final line in manifest.split(RegExp(r'[\r\n]+'))) {
      if (!line.trim().toUpperCase().startsWith('$tag:')) continue;
      final match =
          RegExp(r'URI="([^"]+)"', caseSensitive: false).firstMatch(line);
      if (match != null) return match.group(1);
    }
    return null;
  }

  bool _isUsableMediaResponse(_ValidationResponse response) =>
      (response.statusCode == 200 || response.statusCode == 206) &&
      response.bytes.isNotEmpty;

  String? _firstMediaReference(String manifest) {
    for (final line in manifest.split(RegExp(r'[\r\n]+'))) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
        return trimmed;
      }
    }
    return null;
  }

  Future<_ValidationResponse> _read(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final request = await _client.getUrl(uri).timeout(_requestTimeout);
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(_requestTimeout);
    final bytes = <int>[];
    await for (final chunk in response.timeout(_requestTimeout)) {
      final remaining = _bodyLimit - bytes.length;
      if (remaining <= 0) break;
      bytes.addAll(chunk.length <= remaining ? chunk : chunk.take(remaining));
    }
    var effectiveUri = uri;
    for (final redirect in response.redirects) {
      effectiveUri = effectiveUri.resolveUri(redirect.location);
    }
    return _ValidationResponse(response.statusCode, bytes, effectiveUri);
  }
}

HttpClient _createValidationHttpClient() {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..idleTimeout = const Duration(seconds: 5);
  return client;
}

class _ValidationResponse {
  const _ValidationResponse(this.statusCode, this.bytes, this.effectiveUri);
  final int statusCode;
  final List<int> bytes;
  final Uri effectiveUri;
}
