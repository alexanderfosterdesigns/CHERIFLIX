// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/media_type.dart';
import 'package:cheriflix/core/services/caption_service.dart' as app_client;

import '../backend/caption_service/lib/caption_service.dart' as backend;

void main() {
  test('CaptionHttpService rejects invalid JSON without crashing', () async {
    final directory =
        Directory.systemTemp.createTempSync('cheriflix-caption-http-invalid');
    final service = backend.CaptionHttpService(
      resolver: backend.CaptionResolver(
        manualCatalog: const backend.InMemoryManualCaptionCatalog(
            <String, List<backend.CaptionTrackRecord>>{}),
        generatedCaptionStore: backend.FileGeneratedCaptionStore(directory),
        autoCaptionGenerator: const backend.LightEnglishCaptionGenerator(),
      ),
      generatedDirectory: directory,
    );

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });
    final serverLoopErrors = <Object>[];
    () async {
      try {
        await for (final request in server) {
          await service.handle(request);
        }
      } catch (error) {
        serverLoopErrors.add(error);
      }
    }();

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final badRequest = await client.postUrl(
      Uri.parse('http://127.0.0.1:${server.port}/v1/captions/generate'),
    );
    badRequest.headers.contentType = ContentType.json;
    badRequest.write('{bad-json');
    final badResponse = await badRequest.close();
    final badBody = await utf8.decoder.bind(badResponse).join();

    expect(badResponse.statusCode, HttpStatus.badRequest);
    expect(badBody, contains('Invalid JSON payload'));

    final healthRequest = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/v1/health'),
    );
    final healthResponse = await healthRequest.close();
    final healthBody = await utf8.decoder.bind(healthResponse).join();

    expect(healthResponse.statusCode, HttpStatus.ok);
    expect(jsonDecode(healthBody), <String, dynamic>{'ok': true});
    expect(serverLoopErrors, isEmpty);
  });

  test('CaptionResolver returns handmade captions first', () async {
    final resolver = backend.CaptionResolver(
      manualCatalog: backend.InMemoryManualCaptionCatalog(
        <String, List<backend.CaptionTrackRecord>>{
          'movie_385687_en': <backend.CaptionTrackRecord>[
            backend.CaptionTrackRecord(
              id: 'manual-en',
              label: 'Handmade English',
              languageCode: 'en',
              kind: backend.CaptionTrackKind.manual,
              format: backend.CaptionTrackFormat.vtt,
              url: Uri.parse('https://captions.example.com/manual.vtt'),
            ),
          ],
        },
      ),
      generatedCaptionStore: backend.FileGeneratedCaptionStore(
        Directory.systemTemp.createTempSync('cheriflix-caption-store'),
      ),
      autoCaptionGenerator: const backend.LightEnglishCaptionGenerator(),
    );

    final payload = await resolver.resolve(
      const backend.CaptionRequestKey(
        tmdbId: 385687,
        mediaType: 'movie',
        languageCode: 'en',
      ),
      publicBaseUri: Uri.parse('http://localhost:8081'),
    );

    expect(payload.selectedTrackId, 'manual-en');
    expect(payload.tracks, hasLength(1));
    expect(payload.tracks.first.kind, backend.CaptionTrackKind.manual);
  });

  test(
      'CaptionResolver generates and caches auto english when manual is absent',
      () async {
    final directory =
        Directory.systemTemp.createTempSync('cheriflix-caption-cache');
    final resolver = backend.CaptionResolver(
      manualCatalog: const backend.InMemoryManualCaptionCatalog(
          <String, List<backend.CaptionTrackRecord>>{}),
      generatedCaptionStore: backend.FileGeneratedCaptionStore(directory),
      autoCaptionGenerator: const backend.LightEnglishCaptionGenerator(),
    );
    const key = backend.CaptionRequestKey(
      tmdbId: 1399,
      mediaType: 'tv',
      languageCode: 'en',
      seasonNumber: 1,
      episodeNumber: 1,
    );

    final first = await resolver.resolve(
      key,
      publicBaseUri: Uri.parse('http://localhost:8081'),
    );
    final second = await resolver.resolve(
      key,
      publicBaseUri: Uri.parse('http://localhost:8081'),
    );

    expect(first.selectedTrackId, startsWith('auto-'));
    expect(second.selectedTrackId, first.selectedTrackId);
    expect(
      File(
        '${directory.path}${Platform.pathSeparator}${key.cacheKey}.vtt',
      ).existsSync(),
      isTrue,
    );
  });

  test('CaptionHttpService rejects unsafe generated caption filenames',
      () async {
    final directory =
        Directory.systemTemp.createTempSync('cheriflix-caption-safe-file');
    final service = backend.CaptionHttpService(
      resolver: backend.CaptionResolver(
        manualCatalog: const backend.InMemoryManualCaptionCatalog(
            <String, List<backend.CaptionTrackRecord>>{}),
        generatedCaptionStore: backend.FileGeneratedCaptionStore(directory),
        autoCaptionGenerator: const backend.LightEnglishCaptionGenerator(),
      ),
      generatedDirectory: directory,
    );

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });
    () async {
      await for (final request in server) {
        await service.handle(request);
      }
    }();

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/generated/..%2Fbad.vtt'),
    );
    final response = await request.close();

    expect(response.statusCode, HttpStatus.badRequest);
  });

  test('CaptionHttpService rejects invalid caption query values', () async {
    final directory =
        Directory.systemTemp.createTempSync('cheriflix-caption-safe-query');
    final service = backend.CaptionHttpService(
      resolver: backend.CaptionResolver(
        manualCatalog: const backend.InMemoryManualCaptionCatalog(
            <String, List<backend.CaptionTrackRecord>>{}),
        generatedCaptionStore: backend.FileGeneratedCaptionStore(directory),
        autoCaptionGenerator: const backend.LightEnglishCaptionGenerator(),
      ),
      generatedDirectory: directory,
    );

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });
    () async {
      await for (final request in server) {
        await service.handle(request);
      }
    }();

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(
      Uri.parse(
        'http://127.0.0.1:${server.port}/v1/captions'
        '?tmdbId=-1&mediaType=../../bad&languageCode=en',
      ),
    );
    final response = await request.close();

    expect(response.statusCode, HttpStatus.badRequest);
  });

  test('HttpCaptionService reads the backend response contract', () async {
    final directory =
        Directory.systemTemp.createTempSync('cheriflix-caption-http');
    final service = backend.CaptionHttpService(
      resolver: backend.CaptionResolver(
        manualCatalog: backend.InMemoryManualCaptionCatalog(
          <String, List<backend.CaptionTrackRecord>>{
            'movie_385687_en': <backend.CaptionTrackRecord>[
              backend.CaptionTrackRecord(
                id: 'manual-en',
                label: 'Handmade English',
                languageCode: 'en',
                kind: backend.CaptionTrackKind.manual,
                format: backend.CaptionTrackFormat.vtt,
                url: Uri.parse('https://captions.example.com/manual.vtt'),
              ),
            ],
          },
        ),
        generatedCaptionStore: backend.FileGeneratedCaptionStore(directory),
        autoCaptionGenerator: const backend.LightEnglishCaptionGenerator(),
      ),
      generatedDirectory: directory,
    );

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });
    () async {
      await for (final request in server) {
        await service.handle(request);
      }
    }();

    final client = app_client.HttpCaptionService(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
    );

    final resolution = await client.resolveCaptions(
      tmdbId: 385687,
      mediaType: MediaType.movie,
      languageCode: 'en',
    );

    expect(resolution.selectedTrackId, 'manual-en');
    expect(resolution.tracks.single.label, 'Handmade English');
  });
}
