import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../utils/safe_logging.dart';

/// Loopback HLS adapter for providers that disguise MPEG-TS segments behind a
/// tiny valid PNG prefix. The native decoder receives ordinary manifests and
/// clean TS bytes while all upstream requests retain the provider headers.
class HlsUnwrapProxy {
  HlsUnwrapProxy._();

  static final HlsUnwrapProxy instance = HlsUnwrapProxy._();

  HttpServer? _server;
  final Map<String, _HlsProxyRequest> _requestsByToken = {};
  static const int _maxRememberedRequests = 48;
  int _nextToken = 0;
  late final HttpClient _upstreamClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..idleTimeout = const Duration(seconds: 20)
    ..maxConnectionsPerHost = 8;

  Future<Uri> wrap(
    Uri upstream, {
    Map<String, String> headers = const {},
  }) async {
    final server = await _ensureServer();
    final token = '${DateTime.now().microsecondsSinceEpoch}-${_nextToken++}';
    _rememberRequest(
      token,
      _HlsProxyRequest(
        headers: Map<String, String>.from(headers),
        masterOnly: false,
        stripSubtitleTracks: false,
        stripPngWrappers: true,
        sanitizedMaster: null,
        masterUpstream: null,
      ),
    );
    return _proxyUri(server, token, upstream);
  }

  /// Serves only a rewritten master manifest from loopback. Child playlists,
  /// encryption keys and media segments remain direct CDN requests, avoiding
  /// a Dart proxy bottleneck during normal playback.
  Future<Uri> sanitizeMaster(
    Uri upstream, {
    Map<String, String> headers = const {},
    bool stripSubtitleTracks = false,
    bool selectSingleVariant = false,
    String? preferredAudioLanguage,
    String? prefetchedManifest,
    bool proxyChildren = false,
  }) async {
    // Fetch once during resolution. Validation and the native player then read
    // the same immutable master from loopback instead of racing two extra
    // requests against a short-lived provider URL.
    final fetchedManifest = prefetchedManifest == null
        ? await _fetchManifest(upstream, headers)
        : _FetchedManifest(prefetchedManifest, upstream);
    final manifest = fetchedManifest.body;
    final sanitizedMaster = _sanitizeMasterManifest(
      manifest,
      stripSubtitleTracks: stripSubtitleTracks,
      selectSingleVariant: selectSingleVariant,
      preferredAudioLanguage: preferredAudioLanguage,
    );
    _traceManifestShape(sanitizedMaster, upstream);
    final server = await _ensureServer();
    final token = '${DateTime.now().microsecondsSinceEpoch}-${_nextToken++}';
    _rememberRequest(
      token,
      _HlsProxyRequest(
        headers: Map<String, String>.from(headers),
        masterOnly: !proxyChildren,
        stripSubtitleTracks: stripSubtitleTracks,
        stripPngWrappers: false,
        sanitizedMaster: sanitizedMaster,
        masterUpstream: upstream,
        masterBaseUri: fetchedManifest.effectiveUri,
      ),
    );
    return _proxyUri(server, token, upstream);
  }

  void _rememberRequest(String token, _HlsProxyRequest request) {
    _requestsByToken[token] = request;
    while (_requestsByToken.length > _maxRememberedRequests) {
      _requestsByToken.remove(_requestsByToken.keys.first);
    }
  }

  Future<HttpServer> _ensureServer() async {
    final existing = _server;
    if (existing != null) return existing;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    // HLS players fetch video, audio, encryption keys and upcoming segments
    // concurrently. Stream.forEach awaits each Future callback and silently
    // serialized all of those requests, which let the decoder render one
    // frame and then stall. Dispatch every accepted request independently.
    server.listen((request) {
      unawaited(_handleRequest(request));
    });
    return server;
  }

  Uri _proxyUri(HttpServer server, String token, Uri upstream) => Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        path: '/hls/$token',
        queryParameters: {'url': upstream.toString()},
      );

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method != 'GET' || request.uri.pathSegments.length != 2) {
        request.response.statusCode = HttpStatus.notFound;
        return;
      }
      final token = request.uri.pathSegments[1];
      final proxyRequest = _requestsByToken.remove(token);
      if (proxyRequest != null) {
        // Keep actively streaming sessions at the end of the insertion-ordered
        // map so background resolution of later titles cannot evict them.
        _requestsByToken[token] = proxyRequest;
      }
      final upstream = Uri.tryParse(request.uri.queryParameters['url'] ?? '');
      if (proxyRequest == null ||
          upstream == null ||
          !{'http', 'https'}.contains(upstream.scheme)) {
        request.response.statusCode = HttpStatus.badRequest;
        return;
      }

      final cachedMaster = proxyRequest.sanitizedMaster;
      if (cachedMaster != null && proxyRequest.masterUpstream == upstream) {
        _traceRequest(
          kind: 'master-manifest',
          upstream: upstream,
          outcome: 'prefetched-cache-hit',
          statusCode: HttpStatus.ok,
          durationMs: 0,
          bytes: cachedMaster.length,
        );
        request.response.headers.contentType =
            ContentType('application', 'vnd.apple.mpegurl');
        request.response.write(
          proxyRequest.masterOnly
              ? cachedMaster
              : _rewriteManifest(
                  cachedMaster,
                  proxyRequest.masterBaseUri ?? upstream,
                  token,
                ),
        );
        return;
      }

      final requestedRange =
          request.headers.value(HttpHeaders.rangeHeader)?.trim();
      final provisionalKind = _resourceKind(upstream);
      final cachedResource =
          requestedRange == null || provisionalKind == 'encryption-key'
              ? proxyRequest.resources[upstream]
              : null;
      if (cachedResource != null) {
        _traceRequest(
          kind: cachedResource.kind,
          upstream: upstream,
          outcome: 'validation-cache-hit',
          statusCode: cachedResource.statusCode,
          durationMs: 0,
          bytes: cachedResource.bytes.length,
        );
        request.response.statusCode = cachedResource.statusCode;
        request.response.headers.contentType = cachedResource.contentType;
        request.response.add(cachedResource.bytes);
        return;
      }

      final requestWatch = Stopwatch()..start();
      final upstreamRequest = await _upstreamClient
          .getUrl(upstream)
          .timeout(const Duration(seconds: 5));
      proxyRequest.headers.forEach(upstreamRequest.headers.set);
      if (requestedRange != null && requestedRange.isNotEmpty) {
        upstreamRequest.headers.set(HttpHeaders.rangeHeader, requestedRange);
      }
      final upstreamResponse =
          await upstreamRequest.close().timeout(const Duration(seconds: 6));
      var effectiveUpstream = upstream;
      for (final redirect in upstreamResponse.redirects) {
        effectiveUpstream = effectiveUpstream.resolveUri(redirect.location);
      }
      if (upstreamResponse.statusCode < 200 ||
          upstreamResponse.statusCode >= 300) {
        request.response.statusCode = upstreamResponse.statusCode;
        _traceRequest(
          kind: provisionalKind,
          upstream: upstream,
          outcome: 'upstream-rejected',
          statusCode: upstreamResponse.statusCode,
          durationMs: requestWatch.elapsedMilliseconds,
        );
        return;
      }
      final metadataSaysManifest = _isManifestByMetadata(
        upstream,
        upstreamResponse.headers.contentType,
      );
      final shouldCacheEncryptionKey = provisionalKind == 'encryption-key';
      if (!metadataSaysManifest &&
          !proxyRequest.stripPngWrappers &&
          !shouldCacheEncryptionKey) {
        request.response.statusCode = upstreamResponse.statusCode;
        _copyStreamingHeaders(upstreamResponse, request.response);
        _traceRequest(
          kind: provisionalKind,
          upstream: upstream,
          outcome: 'streaming-started',
          statusCode: upstreamResponse.statusCode,
          durationMs: requestWatch.elapsedMilliseconds,
        );
        await request.response.addStream(
          upstreamResponse.timeout(const Duration(seconds: 20)),
        );
        _traceRequest(
          kind: provisionalKind,
          upstream: upstream,
          outcome: 'streaming-finished',
          statusCode: upstreamResponse.statusCode,
          durationMs: requestWatch.elapsedMilliseconds,
        );
        return;
      }
      final bytes = await upstreamResponse.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      ).timeout(const Duration(seconds: 20));
      if (metadataSaysManifest ||
          _isManifest(upstream, upstreamResponse.headers.contentType, bytes)) {
        final manifest = utf8.decode(bytes, allowMalformed: true);
        final rewritten = proxyRequest.masterOnly
            ? _sanitizeMasterManifest(
                manifest,
                stripSubtitleTracks: proxyRequest.stripSubtitleTracks,
              )
            : _rewriteManifest(manifest, effectiveUpstream, token);
        final rewrittenBytes = utf8.encode(rewritten);
        if (requestedRange == null) {
          proxyRequest.resources[upstream] = _CachedHlsResource(
            bytes: rewrittenBytes,
            statusCode: HttpStatus.ok,
            contentType: ContentType(
              'application',
              'vnd.apple.mpegurl',
            ),
            kind: 'child-manifest',
          );
        }
        request.response.headers.contentType =
            ContentType('application', 'vnd.apple.mpegurl');
        request.response.add(rewrittenBytes);
        _traceRequest(
          kind: 'child-manifest',
          upstream: upstream,
          outcome: 'fetched-and-rewritten',
          statusCode: upstreamResponse.statusCode,
          durationMs: requestWatch.elapsedMilliseconds,
          bytes: rewrittenBytes.length,
        );
      } else {
        if (proxyRequest.masterOnly) {
          request.response.statusCode = HttpStatus.badRequest;
          return;
        }
        request.response.statusCode = upstreamResponse.statusCode;
        _copyStreamingHeaders(upstreamResponse, request.response);
        if (proxyRequest.stripPngWrappers) {
          request.response.headers.removeAll(HttpHeaders.contentLengthHeader);
          request.response.headers.removeAll(HttpHeaders.contentRangeHeader);
        }
        final cleanBytes =
            proxyRequest.stripPngWrappers ? _stripPngWrapper(bytes) : bytes;
        if (shouldCacheEncryptionKey &&
            upstreamResponse.statusCode == HttpStatus.ok) {
          proxyRequest.resources[upstream] = _CachedHlsResource(
            bytes: cleanBytes,
            statusCode: upstreamResponse.statusCode,
            contentType:
                upstreamResponse.headers.contentType ?? ContentType.binary,
            kind: 'encryption-key',
          );
        }
        request.response.add(cleanBytes);
        _traceRequest(
          kind: provisionalKind,
          upstream: upstream,
          outcome: 'buffered-response',
          statusCode: upstreamResponse.statusCode,
          durationMs: requestWatch.elapsedMilliseconds,
          bytes: cleanBytes.length,
        );
      }
    } catch (error) {
      cheriflixLog(
        'hls-proxy',
        jsonEncode(<String, Object?>{
          'outcome': 'request-failed',
          'errorType': error.runtimeType.toString(),
        }),
      );
      request.response.statusCode = HttpStatus.badGateway;
    } finally {
      await request.response.close();
    }
  }

  String _resourceKind(Uri uri) {
    final path = uri.path.toLowerCase();
    if (path.endsWith('.m3u8')) return 'child-manifest';
    if (path.endsWith('.key') || path.contains('/key')) return 'encryption-key';
    return 'media-segment';
  }

  void _traceRequest({
    required String kind,
    required Uri upstream,
    required String outcome,
    required int statusCode,
    required int durationMs,
    int? bytes,
  }) {
    cheriflixLog(
      'hls-proxy',
      jsonEncode(<String, Object?>{
        'kind': kind,
        'host': upstream.host,
        'outcome': outcome,
        'status': statusCode,
        'durationMs': durationMs,
        if (bytes != null) 'bytes': bytes,
      }),
    );
  }

  bool _isManifestByMetadata(Uri uri, ContentType? type) {
    if (uri.path.toLowerCase().endsWith('.m3u8')) return true;
    return (type?.mimeType.toLowerCase() ?? '').contains('mpegurl');
  }

  void _copyStreamingHeaders(
    HttpClientResponse upstream,
    HttpResponse downstream,
  ) {
    for (final name in <String>[
      HttpHeaders.contentTypeHeader,
      HttpHeaders.contentLengthHeader,
      HttpHeaders.contentRangeHeader,
      HttpHeaders.acceptRangesHeader,
      HttpHeaders.cacheControlHeader,
      HttpHeaders.etagHeader,
      HttpHeaders.lastModifiedHeader,
    ]) {
      final value = upstream.headers.value(name);
      if (value != null) downstream.headers.set(name, value);
    }
  }

  Future<_FetchedManifest> _fetchManifest(
    Uri upstream,
    Map<String, String> headers,
  ) async {
    const timeout = Duration(seconds: 6);
    final request = await _upstreamClient.getUrl(upstream).timeout(timeout);
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'HLS master returned HTTP ${response.statusCode}.',
        uri: upstream,
      );
    }
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 8));
    if (!body.trimLeft().startsWith('#EXTM3U')) {
      throw HttpException('HLS master was malformed.', uri: upstream);
    }
    var effectiveUri = upstream;
    for (final redirect in response.redirects) {
      effectiveUri = effectiveUri.resolveUri(redirect.location);
    }
    return _FetchedManifest(body, effectiveUri);
  }

  bool _isManifest(Uri uri, ContentType? type, List<int> bytes) {
    if (uri.path.toLowerCase().endsWith('.m3u8')) return true;
    final mime = type?.mimeType.toLowerCase() ?? '';
    if (mime.contains('mpegurl')) return true;
    const marker = <int>[35, 69, 88, 84, 77, 51, 85];
    if (bytes.length < marker.length) return false;
    for (var index = 0; index < marker.length; index++) {
      if (bytes[index] != marker[index]) return false;
    }
    return true;
  }

  String _rewriteManifest(String manifest, Uri baseUri, String token) {
    final server = _server!;
    String proxied(String raw) =>
        _proxyUri(server, token, baseUri.resolve(raw.trim())).toString();
    return manifest.split('\n').map((line) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
        return proxied(trimmed);
      }
      return line.replaceAllMapped(
        RegExp(r'URI="([^"]+)"'),
        (match) => 'URI="${proxied(match.group(1)!)}"',
      );
    }).join('\n');
  }

  String _sanitizeMasterManifest(
    String manifest, {
    required bool stripSubtitleTracks,
    bool selectSingleVariant = false,
    String? preferredAudioLanguage,
  }) {
    final withoutSubtitles = stripSubtitleTracks
        ? manifest
            .split('\n')
            .where(
              (line) => !line
                  .trimLeft()
                  .toUpperCase()
                  .startsWith('#EXT-X-MEDIA:TYPE=SUBTITLES'),
            )
            .map(
              (line) => line.replaceAll(
                RegExp(r''',?SUBTITLES="[^"]+"''', caseSensitive: false),
                '',
              ),
            )
            .join('\n')
        : manifest;
    if (!selectSingleVariant) {
      return withoutSubtitles;
    }
    return _selectStartupRenditions(
      withoutSubtitles,
      preferredAudioLanguage: preferredAudioLanguage,
    );
  }

  String _selectStartupRenditions(
    String manifest, {
    String? preferredAudioLanguage,
  }) {
    final lines = manifest.split(RegExp(r'\r?\n'));
    final variants = <_HlsVariant>[];
    for (var index = 0; index < lines.length - 1; index += 1) {
      final info = lines[index].trim();
      if (!info.toUpperCase().startsWith('#EXT-X-STREAM-INF:')) continue;
      var uriIndex = index + 1;
      while (uriIndex < lines.length && lines[uriIndex].trim().isEmpty) {
        uriIndex += 1;
      }
      if (uriIndex >= lines.length || lines[uriIndex].trim().startsWith('#')) {
        continue;
      }
      variants.add(
        _HlsVariant(
          infoLineIndex: index,
          uriLineIndex: uriIndex,
          infoLine: lines[index],
          uriLine: lines[uriIndex],
          bandwidth: _integerAttribute(info, 'BANDWIDTH'),
          width: _resolutionDimension(info, width: true),
          height: _resolutionDimension(info, width: false),
          audioGroup: _quotedAttribute(info, 'AUDIO'),
        ),
      );
    }
    if (variants.length <= 1) return manifest;

    // Android TV startup is materially faster when libmpv does not probe
    // every advertised rendition. A 720p/4 Mbps ceiling is the best startup
    // and picture-quality balance on the tested Android TV targets; if none
    // matches, use the closest available rendition.
    final safe = variants
        .where(
          (variant) =>
              (variant.height == null || variant.height! <= 720) &&
              (variant.bandwidth == null || variant.bandwidth! <= 4000000),
        )
        .toList(growable: false);
    final candidates = safe.isEmpty ? variants : safe;
    candidates.sort((left, right) {
      final height = (right.height ?? 0).compareTo(left.height ?? 0);
      if (height != 0) return height;
      return (right.bandwidth ?? 0).compareTo(left.bandwidth ?? 0);
    });
    final selected = candidates.first;

    final audioLines = <int>[];
    for (var index = 0; index < lines.length; index += 1) {
      final line = lines[index].trim();
      if (line.toUpperCase().startsWith('#EXT-X-MEDIA:TYPE=AUDIO')) {
        audioLines.add(index);
      }
    }
    int? selectedAudioLine;
    var retainedAudioLines = const <int>[];
    final audioGroup = selected.audioGroup;
    if (audioGroup != null) {
      final groupAudio = audioLines
          .where(
            (index) => _quotedAttribute(lines[index], 'GROUP-ID') == audioGroup,
          )
          .toList(growable: false);
      retainedAudioLines = groupAudio;
      final language = preferredAudioLanguage?.trim().toLowerCase();
      if (language != null && language.isNotEmpty) {
        for (final index in groupAudio) {
          final candidateLanguage =
              _quotedAttribute(lines[index], 'LANGUAGE')?.toLowerCase();
          if (candidateLanguage == language ||
              candidateLanguage?.split('-').first ==
                  language.split('-').first) {
            selectedAudioLine = index;
            break;
          }
        }
      }
      selectedAudioLine ??= groupAudio.cast<int?>().firstWhere(
            (index) =>
                index != null &&
                lines[index].toUpperCase().contains('DEFAULT=YES'),
            orElse: () => null,
          );
      selectedAudioLine ??= groupAudio.firstOrNull;
    }

    final variantLineIndexes = <int>{
      for (final variant in variants) ...<int>[
        variant.infoLineIndex,
        variant.uriLineIndex
      ],
    };
    final output = <String>[];
    for (var index = 0; index < lines.length; index += 1) {
      if (variantLineIndexes.contains(index) || audioLines.contains(index)) {
        continue;
      }
      output.add(lines[index]);
    }
    for (final audioLine in retainedAudioLines) {
      output.add(lines[audioLine]);
    }
    output
      ..add(selected.infoLine)
      ..add(selected.uriLine);
    cheriflixLog(
      'hls-proxy',
      jsonEncode(<String, Object?>{
        'kind': 'master-manifest',
        'outcome': 'startup-rendition-selected',
        'height': selected.height,
        'bandwidth': selected.bandwidth,
        'audioLanguage': selectedAudioLine == null
            ? null
            : _quotedAttribute(lines[selectedAudioLine], 'LANGUAGE'),
        'removedVariants': variants.length - 1,
        'removedAudioTracks': audioLines.length - retainedAudioLines.length,
      }),
    );
    return output.join('\n');
  }

  String? _quotedAttribute(String line, String name) => RegExp(
        '$name="([^"]+)"',
        caseSensitive: false,
      ).firstMatch(line)?.group(1);

  int? _integerAttribute(String line, String name) => int.tryParse(
        RegExp('$name=(\\d+)', caseSensitive: false)
                .firstMatch(line)
                ?.group(1) ??
            '',
      );

  int? _resolutionDimension(String line, {required bool width}) {
    final match = RegExp(
      r'RESOLUTION=(\d+)x(\d+)',
      caseSensitive: false,
    ).firstMatch(line);
    return int.tryParse(match?.group(width ? 1 : 2) ?? '');
  }

  void _traceManifestShape(String manifest, Uri upstream) {
    final lines = manifest.split(RegExp(r'\r?\n'));
    cheriflixLog(
      'hls-proxy',
      jsonEncode(<String, Object?>{
        'kind': 'master-manifest',
        'host': upstream.host,
        'outcome': 'shape',
        'bytes': manifest.length,
        'variants':
            lines.where((line) => line.startsWith('#EXT-X-STREAM-INF:')).length,
        'audioTracks': lines
            .where((line) => line.startsWith('#EXT-X-MEDIA:TYPE=AUDIO'))
            .length,
      }),
    );
  }

  List<int> _stripPngWrapper(List<int> bytes) {
    const pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < 16) {
      return bytes;
    }
    for (var index = 0; index < pngSignature.length; index++) {
      if (bytes[index] != pngSignature[index]) return bytes;
    }
    for (var index = 8; index + 8 <= bytes.length; index++) {
      if (bytes[index] == 73 &&
          bytes[index + 1] == 69 &&
          bytes[index + 2] == 78 &&
          bytes[index + 3] == 68) {
        final payloadStart = index + 8;
        if (payloadStart < bytes.length && bytes[payloadStart] == 0x47) {
          return bytes.sublist(payloadStart);
        }
      }
    }
    return bytes;
  }
}

class _HlsProxyRequest {
  _HlsProxyRequest({
    required this.headers,
    required this.masterOnly,
    required this.stripSubtitleTracks,
    required this.stripPngWrappers,
    required this.sanitizedMaster,
    required this.masterUpstream,
    this.masterBaseUri,
  });

  final Map<String, String> headers;
  final bool masterOnly;
  final bool stripSubtitleTracks;
  final bool stripPngWrappers;
  final String? sanitizedMaster;
  final Uri? masterUpstream;
  final Uri? masterBaseUri;
  final Map<Uri, _CachedHlsResource> resources = <Uri, _CachedHlsResource>{};
}

class _FetchedManifest {
  const _FetchedManifest(this.body, this.effectiveUri);

  final String body;
  final Uri effectiveUri;
}

class _HlsVariant {
  const _HlsVariant({
    required this.infoLineIndex,
    required this.uriLineIndex,
    required this.infoLine,
    required this.uriLine,
    required this.bandwidth,
    required this.width,
    required this.height,
    required this.audioGroup,
  });

  final int infoLineIndex;
  final int uriLineIndex;
  final String infoLine;
  final String uriLine;
  final int? bandwidth;
  final int? width;
  final int? height;
  final String? audioGroup;
}

class _CachedHlsResource {
  const _CachedHlsResource({
    required this.bytes,
    required this.statusCode,
    required this.contentType,
    required this.kind,
  });

  final List<int> bytes;
  final int statusCode;
  final ContentType contentType;
  final String kind;
}
