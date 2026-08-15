import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Native frame extraction bridge.
///
/// Channel target:
/// - Android: `MediaMetadataRetriever`
/// - iOS: `AVAssetImageGenerator`
///
/// Exact extraction asks native layers for the closest real frame at the
/// requested timestamp. Fast preview extraction permits looser tolerance so
/// scrubbing can usually stay in the 100-400ms response window.
class NativeThumbnailExtractor {
  NativeThumbnailExtractor({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(_defaultThumbnailChannelName);

  static const String _defaultThumbnailChannelName =
      'cheriflix/native_thumbnail_extractor';

  final MethodChannel _channel;

  Future<NativeThumbnailResult?> extractFrame({
    required String sourceUri,
    required int timeMs,
    required int width,
    required int height,
    required bool exact,
    Map<String, String> httpHeaders = const <String, String>{},
    int jpegQuality = 88,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      // Local desktop/web builds have no channel implementation.
      return null;
    }

    final args = <String, Object>{
      'sourceUri': sourceUri,
      'timeMs': timeMs,
      'width': width,
      'height': height,
      'exact': exact,
      'jpegQuality': jpegQuality.clamp(40, 100),
      if (httpHeaders.isNotEmpty) 'httpHeaders': httpHeaders,
    };

    final stopwatch = Stopwatch()..start();
    final dynamic response = await _channel.invokeMethod<dynamic>(
      'extractFrame',
      args,
    );
    stopwatch.stop();

    if (response == null) {
      return null;
    }

    if (response is Uint8List) {
      return NativeThumbnailResult(
        bytes: response,
        requestedTimeMs: timeMs,
        actualTimeMs: timeMs,
        exact: exact,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    }

    if (response is Map<dynamic, dynamic>) {
      final dynamic bytes = response['bytes'];
      final Uint8List? data = bytes is Uint8List ? bytes : null;
      if (data == null || data.isEmpty) {
        return null;
      }
      return NativeThumbnailResult(
        bytes: data,
        requestedTimeMs: timeMs,
        actualTimeMs: _toIntOrNull(response['actualTimeMs']) ?? timeMs,
        exact: exact,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    }

    return null;
  }

  Future<List<NativeThumbnailResult>> extractFrames({
    required String sourceUri,
    required List<int> timeMsList,
    required int width,
    required int height,
    required bool exact,
    Map<String, String> httpHeaders = const <String, String>{},
    int jpegQuality = 88,
  }) async {
    final normalizedTimes = timeMsList
        .map((timeMs) => timeMs < 0 ? 0 : timeMs)
        .toSet()
        .toList(growable: false)
      ..sort();
    if (normalizedTimes.isEmpty) {
      return const <NativeThumbnailResult>[];
    }

    if (!Platform.isAndroid) {
      final results = <NativeThumbnailResult>[];
      for (final timeMs in normalizedTimes) {
        final result = await extractFrame(
          sourceUri: sourceUri,
          timeMs: timeMs,
          width: width,
          height: height,
          exact: exact,
          httpHeaders: httpHeaders,
          jpegQuality: jpegQuality,
        );
        if (result != null) {
          results.add(result);
        }
      }
      return results;
    }

    final args = <String, Object>{
      'sourceUri': sourceUri,
      'timeMsList': normalizedTimes,
      'width': width,
      'height': height,
      'exact': exact,
      'jpegQuality': jpegQuality.clamp(40, 100),
      if (httpHeaders.isNotEmpty) 'httpHeaders': httpHeaders,
    };
    final stopwatch = Stopwatch()..start();
    final dynamic response = await _channel.invokeMethod<dynamic>(
      'extractFrames',
      args,
    );
    stopwatch.stop();

    if (response is! List) {
      return const <NativeThumbnailResult>[];
    }

    final results = <NativeThumbnailResult>[];
    for (final item in response) {
      if (item is! Map<dynamic, dynamic>) {
        continue;
      }
      final dynamic bytes = item['bytes'];
      final Uint8List? data = bytes is Uint8List ? bytes : null;
      if (data == null || data.isEmpty) {
        continue;
      }
      final requestedTimeMs =
          _toIntOrNull(item['requestedTimeMs']) ?? _toIntOrNull(item['timeMs']);
      if (requestedTimeMs == null) {
        continue;
      }
      results.add(
        NativeThumbnailResult(
          bytes: data,
          requestedTimeMs: requestedTimeMs,
          actualTimeMs: _toIntOrNull(item['actualTimeMs']) ?? requestedTimeMs,
          exact: exact,
          latencyMs: stopwatch.elapsedMilliseconds,
        ),
      );
    }
    return results;
  }

  Future<Uint8List?> extractExactFrame(
    String sourceUri,
    int timeMs,
    int width,
    int height,
  ) async {
    final result = await extractFrame(
      sourceUri: sourceUri,
      timeMs: timeMs,
      width: width,
      height: height,
      exact: true,
      jpegQuality: 90,
    );
    return result?.bytes;
  }

  int? _toIntOrNull(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }
}

class NativeThumbnailResult {
  const NativeThumbnailResult({
    required this.bytes,
    required this.requestedTimeMs,
    required this.actualTimeMs,
    required this.exact,
    required this.latencyMs,
  });

  final Uint8List bytes;
  final int requestedTimeMs;
  final int actualTimeMs;
  final bool exact;
  final int latencyMs;
}
