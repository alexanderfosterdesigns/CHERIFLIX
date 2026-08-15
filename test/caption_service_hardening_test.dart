import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/media_type.dart';
import 'package:cheriflix/core/services/caption_service.dart';

void main() {
  test('HttpCaptionService retries transient failures', () async {
    var attempts = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });
    () async {
      await for (final request in server) {
        attempts += 1;
        if (attempts == 1) {
          request.response
            ..statusCode = HttpStatus.serviceUnavailable
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(<String, dynamic>{'error': 'busy'}));
          await request.response.close();
          continue;
        }

        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(
              <String, dynamic>{
                'tracks': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'id': 'manual-en',
                    'label': 'English',
                    'languageCode': 'en',
                    'kind': 'manual',
                    'format': 'vtt',
                    'url': 'https://captions.example.com/en.vtt',
                    'isDefault': true,
                    'isHI': false,
                  },
                ],
                'selectedTrackId': 'manual-en',
              },
            ),
          );
        await request.response.close();
      }
    }();

    final service = HttpCaptionService(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      timeout: const Duration(seconds: 2),
      maxAttempts: 2,
      retryBaseDelay: const Duration(milliseconds: 1),
      maxRetryDelay: const Duration(milliseconds: 4),
      random: math.Random(1),
    );

    final resolution = await service.resolveCaptions(
      tmdbId: 385687,
      mediaType: MediaType.movie,
      languageCode: 'en',
    );

    expect(resolution.tracks, hasLength(1));
    expect(resolution.selectedTrackId, 'manual-en');
    expect(attempts, 2);
  });

  test('HttpCaptionService opens a circuit after repeated failures', () async {
    var attempts = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });
    () async {
      await for (final request in server) {
        attempts += 1;
        request.response
          ..statusCode = HttpStatus.serviceUnavailable
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(<String, dynamic>{'error': 'busy'}));
        await request.response.close();
      }
    }();

    final service = HttpCaptionService(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      timeout: const Duration(seconds: 2),
      maxAttempts: 1,
      circuitBreakerFailureThreshold: 2,
      circuitBreakerCooldown: const Duration(minutes: 1),
      retryBaseDelay: const Duration(milliseconds: 1),
      maxRetryDelay: const Duration(milliseconds: 1),
      random: math.Random(1),
    );

    for (var i = 0; i < 2; i += 1) {
      final resolution = await service.resolveCaptions(
        tmdbId: 385687,
        mediaType: MediaType.movie,
        languageCode: 'en',
      );
      expect(resolution.tracks, isEmpty);
      expect(resolution.selectedTrackId, isNull);
    }

    final attemptsBeforeCircuit = attempts;
    final resolution = await service.resolveCaptions(
      tmdbId: 385687,
      mediaType: MediaType.movie,
      languageCode: 'en',
    );
    expect(resolution.tracks, isEmpty);
    expect(resolution.selectedTrackId, isNull);
    expect(attempts, attemptsBeforeCircuit);
  });
}
