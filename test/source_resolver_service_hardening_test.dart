import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/media_type.dart';
import 'package:cheriflix/core/models/profile_playback_settings.dart';
import 'package:cheriflix/core/models/provider_config.dart';
import 'package:cheriflix/core/services/source_resolver_service.dart';

void main() {
  test('HttpSourceResolverService retries transient HTTP failures', () async {
    var attempts = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });
    () async {
      await for (final request in server) {
        await utf8.decoder.bind(request).join();
        attempts += 1;
        if (attempts < 3) {
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
                'target': <String, dynamic>{
                  'uri': 'https://streams.example.com/main.m3u8',
                  'providerKey': 'videasy',
                  'providerLabel': 'Videasy',
                  'providerIndex': 3,
                  'sourceKind': 'hls',
                },
              },
            ),
          );
        await request.response.close();
      }
    }();

    final service = HttpSourceResolverService(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      timeout: const Duration(seconds: 2),
      maxAttempts: 3,
      retryBaseDelay: const Duration(milliseconds: 1),
      maxRetryDelay: const Duration(milliseconds: 4),
      circuitBreakerFailureThreshold: 20,
      random: math.Random(1),
    );

    final target = await service.resolveTitle(
      profileId: 'profile-1',
      tmdbId: 385687,
      mediaType: MediaType.movie,
      providerConfig: ProviderConfig.defaults(),
      settings: const ProfilePlaybackSettings(languageCode: 'en'),
    );

    expect(target, isNotNull);
    expect(target!.providerKey, 'videasy');
    expect(attempts, 3);
  });

  test('HttpSourceResolverService opens a circuit after repeated failures',
      () async {
    var attempts = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });
    () async {
      await for (final request in server) {
        await utf8.decoder.bind(request).join();
        attempts += 1;
        request.response
          ..statusCode = HttpStatus.serviceUnavailable
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(<String, dynamic>{'error': 'busy'}));
        await request.response.close();
      }
    }();

    final service = HttpSourceResolverService(
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
      await expectLater(
        () => service.resolveTitle(
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          providerConfig: ProviderConfig.defaults(),
          settings: const ProfilePlaybackSettings(languageCode: 'en'),
        ),
        throwsA(isA<SourceResolverUnavailableException>()),
      );
    }

    final attemptsBeforeCircuit = attempts;
    await expectLater(
      () => service.resolveTitle(
        profileId: 'profile-1',
        tmdbId: 385687,
        mediaType: MediaType.movie,
        providerConfig: ProviderConfig.defaults(),
        settings: const ProfilePlaybackSettings(languageCode: 'en'),
      ),
      throwsA(
        isA<SourceResolverUnavailableException>().having(
          (error) => error.message,
          'message',
          contains('temporarily paused'),
        ),
      ),
    );
    expect(attempts, attemptsBeforeCircuit);
  });
}
