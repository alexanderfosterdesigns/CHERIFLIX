import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'source_resolver.dart';
import 'source_resolver_models.dart';

class SourceResolverHttpService {
  const SourceResolverHttpService({
    required this.resolver,
    this.requestReadTimeout = const Duration(seconds: 4),
    this.maxRequestBodyBytes = 64 * 1024,
  });

  final SourceResolver resolver;
  final Duration requestReadTimeout;
  final int maxRequestBodyBytes;

  Future<void> handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (request.method == 'GET' &&
          (path == '/health' || path == '/v1/health')) {
        await _writeJson(
          request,
          <String, dynamic>{'ok': true},
        );
        return;
      }

      if (request.method == 'POST' && path == '/v1/sources/resolve') {
        await _handleResolve(request, resolver.resolveTitle);
        return;
      }
      if (request.method == 'POST' && path == '/v1/sources/resolve-next') {
        await _handleResolve(request, resolver.resolveNextSource);
        return;
      }
      if (request.method == 'POST' && path == '/v1/sources/resolve-specific') {
        await _handleResolve(request, resolver.resolveSpecificSource);
        return;
      }
      if (request.method == 'POST' && path == '/v1/sources/success') {
        await _handleSuccess(request);
        return;
      }
      if (request.method == 'POST' && path == '/v1/sources/failure') {
        await _handleFailure(request);
        return;
      }
      if (request.method == 'POST' && path == '/v1/sources/retry-delay') {
        await _handleRetryDelay(request);
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
      stderr.writeln(
        '[source_resolver_http_service] Unhandled request error: $error',
      );
      stderr.writeln(stackTrace);
      await _writeJson(
        request,
        <String, dynamic>{'error': 'Internal server error'},
        statusCode: HttpStatus.internalServerError,
      );
    }
  }

  Future<void> _handleResolve(
    HttpRequest request,
    Future<PlaybackTarget?> Function(SourceResolverRequest request) action,
  ) async {
    final payload = await _readJsonBody(request);
    final sourceRequest = _parseSourceRequest(payload);
    final target = await action(sourceRequest);
    await _writeJson(
      request,
      <String, dynamic>{
        'target': target?.toJson(),
      },
    );
  }

  Future<void> _handleSuccess(HttpRequest request) async {
    final payload = await _readJsonBody(request);
    await resolver.reportSourceSuccess(_parseSourceRequest(payload));
    await _writeJson(request, <String, dynamic>{'ok': true});
  }

  Future<void> _handleFailure(HttpRequest request) async {
    final payload = await _readJsonBody(request);
    await resolver.reportSourceFailure(_parseSourceRequest(payload));
    await _writeJson(request, <String, dynamic>{'ok': true});
  }

  Future<void> _handleRetryDelay(HttpRequest request) async {
    final payload = await _readJsonBody(request);
    final delay = await resolver.estimateNextSourceRetryDelay(
      _parseSourceRequest(payload),
    );
    await _writeJson(
      request,
      <String, dynamic>{
        'retryAfterMilliseconds': delay?.inMilliseconds,
      },
    );
  }

  SourceResolverRequest _parseSourceRequest(Map<String, dynamic> payload) {
    try {
      return SourceResolverRequest.fromJson(payload);
    } catch (_) {
      throw _HttpRequestException.badRequest(
        'Invalid source resolver request payload.',
      );
    }
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
    throw _HttpRequestException.badRequest(
      'JSON payload must be an object.',
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
