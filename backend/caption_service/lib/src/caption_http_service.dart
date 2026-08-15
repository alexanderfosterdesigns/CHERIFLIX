import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'caption_models.dart';
import 'caption_resolver.dart';

class CaptionHttpService {
  const CaptionHttpService({
    required this.resolver,
    required this.generatedDirectory,
    this.requestReadTimeout = const Duration(seconds: 4),
    this.maxRequestBodyBytes = 64 * 1024,
  });

  final CaptionResolver resolver;
  final Directory generatedDirectory;
  final Duration requestReadTimeout;
  final int maxRequestBodyBytes;
  static final RegExp _generatedFilenamePattern =
      RegExp(r'^[A-Za-z0-9_-]+\.vtt$');
  static final RegExp _languageCodePattern =
      RegExp(r'^[A-Za-z]{2,8}(?:[-_][A-Za-z0-9]{2,8})?$');

  Future<void> handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (request.method == 'GET' &&
          (path == '/health' || path == '/v1/health')) {
        await _writeJson(request, <String, dynamic>{'ok': true});
        return;
      }
      if (request.method == 'GET' && path == '/v1/captions') {
        await _handleResolve(request);
        return;
      }
      if (request.method == 'POST' && path == '/v1/captions/generate') {
        await _handleGenerate(request);
        return;
      }
      if (request.method == 'GET' && path.startsWith('/generated/')) {
        await _handleGeneratedFile(request);
        return;
      }

      await _writeJson(
        request,
        <String, dynamic>{'error': 'Not found'},
        statusCode: HttpStatus.notFound,
      );
    } on _HttpRequestException catch (error) {
      await _writeJson(
        request,
        <String, dynamic>{'error': error.message},
        statusCode: error.statusCode,
      );
    } catch (error, stackTrace) {
      stderr.writeln('[caption_http_service] Unhandled request error: $error');
      stderr.writeln(stackTrace);
      await _writeJson(
        request,
        <String, dynamic>{'error': 'Internal server error'},
        statusCode: HttpStatus.internalServerError,
      );
    }
  }

  Future<void> _handleResolve(HttpRequest request) async {
    final key = _requestKeyFromQuery(request.uri.queryParameters);
    if (key == null) {
      await _writeBadRequest(
          request, 'Missing or invalid caption query parameters.');
      return;
    }
    final payload = await resolver.resolve(
      key,
      publicBaseUri: _publicBaseUriForRequest(request),
    );
    await _writeJson(request, payload.toJson());
  }

  Future<void> _handleGenerate(HttpRequest request) async {
    final payload = await _readJsonBody(request);
    final key = _requestKeyFromMap(payload);
    if (key == null) {
      throw _HttpRequestException.badRequest(
        'Missing or invalid generation payload.',
      );
    }
    final generatedTrack = await resolver.generate(
      key,
      publicBaseUri: _publicBaseUriForRequest(request),
      seedText: payload['seedText'] as String?,
    );
    await _writeJson(request, generatedTrack.toJson());
  }

  Future<void> _handleGeneratedFile(HttpRequest request) async {
    final filename =
        request.uri.pathSegments.isEmpty ? '' : request.uri.pathSegments.last;
    if (!_generatedFilenamePattern.hasMatch(filename)) {
      throw _HttpRequestException.badRequest('Missing generated caption file.');
    }
    final root = generatedDirectory.absolute.path;
    final file =
        File('$root${Platform.pathSeparator}$filename').absolute;
    if (!_isWithinDirectory(root, file.path)) {
      throw _HttpRequestException.badRequest('Invalid generated caption file.');
    }
    if (!await file.exists()) {
      await _writeJson(
        request,
        <String, dynamic>{'error': 'Generated caption file not found.'},
        statusCode: HttpStatus.notFound,
      );
      return;
    }
    request.response.headers.contentType = ContentType('text', 'vtt');
    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
    final bytes = BytesBuilder(copy: false);
    var totalBytes = 0;
    try {
      await for (final chunk in request.timeout(requestReadTimeout)) {
        totalBytes += chunk.length;
        if (totalBytes > maxRequestBodyBytes) {
          throw _HttpRequestException.payloadTooLarge(
            'Request payload exceeds ${maxRequestBodyBytes} bytes.',
          );
        }
        bytes.add(chunk);
      }
    } on TimeoutException {
      throw _HttpRequestException.requestTimeout(
        'Timed out while reading request payload.',
      );
    }

    final rawBody = utf8.decode(bytes.takeBytes());
    if (rawBody.trim().isEmpty) {
      return <String, dynamic>{};
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(rawBody);
    } on FormatException {
      throw _HttpRequestException.badRequest('Invalid JSON payload.');
    }
    if (decoded is Map<String, dynamic>) {
      return <String, dynamic>{...decoded};
    }
    if (decoded is Map) {
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    throw _HttpRequestException.badRequest('JSON payload must be an object.');
  }

  CaptionRequestKey? _requestKeyFromQuery(Map<String, String> query) {
    return _requestKeyFromMap(query);
  }

  CaptionRequestKey? _requestKeyFromMap(Map<dynamic, dynamic> payload) {
    final tmdbId =
        int.tryParse('${payload['tmdbId'] ?? payload['tmdb_id'] ?? ''}');
    final mediaType =
        '${payload['mediaType'] ?? payload['media_type'] ?? ''}'.trim();
    final languageCode =
        '${payload['languageCode'] ?? payload['language_code'] ?? 'en'}'.trim();
    if (tmdbId == null ||
        tmdbId <= 0 ||
        (mediaType != 'movie' && mediaType != 'tv') ||
        !_languageCodePattern.hasMatch(languageCode)) {
      return null;
    }
    final seasonNumber = int.tryParse(
        '${payload['seasonNumber'] ?? payload['season_number'] ?? ''}');
    final episodeNumber = int.tryParse(
      '${payload['episodeNumber'] ?? payload['episode_number'] ?? ''}',
    );
    if ((seasonNumber != null && seasonNumber <= 0) ||
        (episodeNumber != null && episodeNumber <= 0)) {
      return null;
    }
    return CaptionRequestKey(
      tmdbId: tmdbId,
      mediaType: mediaType,
      languageCode: languageCode.isEmpty ? 'en' : languageCode,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
  }

  Uri _publicBaseUriForRequest(HttpRequest request) {
    return Uri(
      scheme: 'http',
      host:
          request.connectionInfo?.remoteAddress.type == InternetAddressType.unix
              ? 'localhost'
              : request.requestedUri.host,
      port: request.requestedUri.port,
    );
  }

  Future<void> _writeBadRequest(HttpRequest request, String message) {
    return _writeJson(
      request,
      <String, dynamic>{'error': message},
      statusCode: HttpStatus.badRequest,
    );
  }

  Future<void> _writeJson(
    HttpRequest request,
    Map<String, dynamic> payload, {
    int statusCode = HttpStatus.ok,
  }) async {
    try {
      request.response
        ..statusCode = statusCode
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(payload));
      await request.response.close();
    } catch (_) {}
  }

  bool _isWithinDirectory(String parentPath, String childPath) {
    final parent = _canonicalDirectory(parentPath);
    final child = _canonicalPath(childPath);
    return child == parent ||
        child.startsWith('$parent${Platform.pathSeparator}');
  }

  String _canonicalDirectory(String path) {
    return _canonicalPath(path).replaceAll(RegExp(r'[\\/]+$'), '');
  }

  String _canonicalPath(String path) {
    return File(path).absolute.path
        .replaceAll('/', Platform.pathSeparator)
        .replaceAll('\\', Platform.pathSeparator);
  }
}

class _HttpRequestException implements Exception {
  const _HttpRequestException({
    required this.statusCode,
    required this.message,
  });

  factory _HttpRequestException.badRequest(String message) {
    return _HttpRequestException(
      statusCode: HttpStatus.badRequest,
      message: message,
    );
  }

  factory _HttpRequestException.payloadTooLarge(String message) {
    return _HttpRequestException(
      statusCode: HttpStatus.requestEntityTooLarge,
      message: message,
    );
  }

  factory _HttpRequestException.requestTimeout(String message) {
    return _HttpRequestException(
      statusCode: HttpStatus.requestTimeout,
      message: message,
    );
  }

  final int statusCode;
  final String message;
}
