import 'dart:convert';
import 'dart:io';

import 'package:cheriflix/core/models/media_type.dart';
import 'package:cheriflix/core/models/profile_playback_settings.dart';
import 'package:cheriflix/core/models/provider_config.dart';
import 'package:cheriflix/core/services/built_in_source_resolver_service.dart';

Future<void> main(List<String> arguments) async {
  final tmdbId = arguments.isEmpty ? 385687 : int.parse(arguments.first);
  final isTv = arguments.length > 1 && arguments[1].toLowerCase() == 'tv';
  final season = isTv && arguments.length > 2 ? int.parse(arguments[2]) : null;
  final episode = isTv && arguments.length > 3 ? int.parse(arguments[3]) : null;
  final service = BuiltInSourceResolverService();
  final target = await service.resolveSpecificSource(
    profileId: 'vidking-probe',
    tmdbId: tmdbId,
    mediaType: isTv ? MediaType.tv : MediaType.movie,
    providerConfig: ProviderConfig.defaults(),
    settings: const ProfilePlaybackSettings(languageCode: 'en'),
    providerIndex: 17,
    seasonNumber: season,
    episodeNumber: episode,
  );
  if (target == null) {
    throw StateError('VidKing returned no direct source.');
  }
  final client = HttpClient();
  late final int manifestStatus;
  late final String manifestContentType;
  late final String manifestBody;
  try {
    final request = await client.getUrl(target.uri);
    target.httpHeaders.forEach(request.headers.set);
    final response = await request.close();
    manifestStatus = response.statusCode;
    manifestContentType = response.headers.contentType?.mimeType ?? '';
    manifestBody = await response.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
  final segmentProbe = await _probeSegments(
    target.uri,
    manifestBody,
    target.httpHeaders,
  );
  stdout.writeln(jsonEncode(<String, Object?>{
    'provider': target.providerKey,
    'sourceKind': target.sourceKind.name,
    'host': target.uri.host,
    'pathExtension': target.uri.pathSegments.isEmpty
        ? ''
        : target.uri.pathSegments.last.split('?').first,
    'hasPlaybackHeaders': target.httpHeaders.isNotEmpty,
    'manifestStatus': manifestStatus,
    'manifestContentType': manifestContentType,
    'audioTracks': _audioTrackMetadata(manifestBody),
    ...segmentProbe,
  }));
}

List<Map<String, String>> _audioTrackMetadata(String manifestBody) {
  final tracks = <Map<String, String>>[];
  for (final line in const LineSplitter().convert(manifestBody)) {
    if (!line.startsWith('#EXT-X-MEDIA:') || !line.contains('TYPE=AUDIO')) {
      continue;
    }
    final metadata = <String, String>{};
    for (final key in <String>['GROUP-ID', 'NAME', 'LANGUAGE', 'DEFAULT']) {
      final match = RegExp('$key=("[^"]*"|[^,]*)').firstMatch(line);
      if (match != null) {
        metadata[key] = match.group(1)!.replaceAll('"', '');
      }
    }
    tracks.add(metadata);
  }
  return tracks;
}

Future<Map<String, Object?>> _probeSegments(
  Uri manifestUri,
  String manifestBody,
  Map<String, String> headers,
) async {
  final lines = const LineSplitter()
      .convert(manifestBody)
      .map((line) => line.trim())
      .toList(growable: false);
  final segments = <(Uri, double)>[];
  double? pendingDuration;
  for (final line in lines) {
    if (line.startsWith('#EXTINF:')) {
      pendingDuration =
          double.tryParse(line.substring(8).split(',').first.trim());
      continue;
    }
    if (line.isNotEmpty && !line.startsWith('#') && pendingDuration != null) {
      segments.add((manifestUri.resolve(line), pendingDuration));
      pendingDuration = null;
      if (segments.length == 3) {
        break;
      }
    }
  }
  if (segments.isEmpty) {
    final variants = <(Uri, int, String)>[];
    String? streamInfo;
    for (final line in lines) {
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        streamInfo = line.substring('#EXT-X-STREAM-INF:'.length);
        continue;
      }
      if (line.isNotEmpty && !line.startsWith('#') && streamInfo != null) {
        final bandwidthMatch =
            RegExp(r'(?:^|,)BANDWIDTH=(\d+)').firstMatch(streamInfo);
        final resolutionMatch =
            RegExp(r'(?:^|,)RESOLUTION=([^,]+)').firstMatch(streamInfo);
        variants.add((
          manifestUri.resolve(line),
          int.tryParse(bandwidthMatch?.group(1) ?? '') ?? 0,
          resolutionMatch?.group(1) ?? '',
        ));
        streamInfo = null;
      }
    }
    if (variants.isEmpty) {
      return <String, Object?>{'sampleSegments': 0};
    }
    variants.sort((a, b) => a.$2.compareTo(b.$2));
    final selected = variants.lastWhere(
      (variant) => variant.$2 <= 4000000,
      orElse: () => variants.first,
    );
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(selected.$1);
      headers.forEach(request.headers.set);
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 30));
      return <String, Object?>{
        'variants': variants
            .map((variant) => <String, Object?>{
                  'bandwidthMbps': double.parse(
                    (variant.$2 / 1000000).toStringAsFixed(2),
                  ),
                  'resolution': variant.$3,
                })
            .toList(growable: false),
        'probedVariantMbps': double.parse(
          (selected.$2 / 1000000).toStringAsFixed(2),
        ),
        ...await _probeSegments(selected.$1, body, headers),
      };
    } finally {
      client.close(force: true);
    }
  }

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  var bytes = 0;
  var mediaSeconds = 0.0;
  final stopwatch = Stopwatch()..start();
  try {
    for (final segment in segments) {
      final request = await client.getUrl(segment.$1);
      headers.forEach(request.headers.set);
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        bytes += chunk.length;
      }
      mediaSeconds += segment.$2;
    }
  } finally {
    stopwatch.stop();
    client.close(force: true);
  }
  final downloadSeconds = stopwatch.elapsedMicroseconds / 1000000;
  final encodedMbps =
      mediaSeconds <= 0 ? 0.0 : (bytes * 8) / mediaSeconds / 1000000;
  final downloadMbps =
      downloadSeconds <= 0 ? 0.0 : (bytes * 8) / downloadSeconds / 1000000;
  return <String, Object?>{
    'sampleSegments': segments.length,
    'sampleMediaSeconds': double.parse(mediaSeconds.toStringAsFixed(2)),
    'sampleMiB': double.parse((bytes / 1024 / 1024).toStringAsFixed(2)),
    'encodedMbps': double.parse(encodedMbps.toStringAsFixed(2)),
    'downloadMbps': double.parse(downloadMbps.toStringAsFixed(2)),
    'throughputHeadroom': encodedMbps <= 0
        ? null
        : double.parse((downloadMbps / encodedMbps).toStringAsFixed(2)),
  };
}
