// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import '../backend/source_resolver_service/lib/source_resolver_service.dart'
    as backend;

void main() {
  test(
      'Source resolver endpoint remains stable under sustained concurrent load',
      () async {
    final resolver = backend.SourceResolver(
      targetExtractorRegistry: backend.ProviderPlaybackTargetExtractorRegistry(
        extractors: <String, backend.ProviderPlaybackTargetExtractor>{
          'videasy': ({
            required provider,
            required pageUri,
            required request,
          }) async {
            await Future<void>.delayed(const Duration(milliseconds: 8));
            return backend.PlaybackTarget(
              uri:
                  Uri.parse('https://streams.example.com/${provider.key}.m3u8'),
              providerKey: provider.key,
              providerLabel: provider.label,
              providerIndex: provider.canonicalIndex,
              sourceKind: backend.PlaybackSourceKind.hls,
              pageUri: pageUri,
            );
          },
        },
      ),
      probe: _AlwaysTrueProbe(),
    );
    final service = backend.SourceResolverHttpService(resolver: resolver);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    const maxInFlight = 64;
    final inFlight = <Future<void>>{};
    () async {
      await for (final request in server) {
        if (inFlight.length >= maxInFlight) {
          request.response
            ..statusCode = HttpStatus.serviceUnavailable
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(<String, dynamic>{'error': 'overloaded'}));
          await request.response.close();
          continue;
        }

        final task = service.handle(request);
        inFlight.add(task);
        task.whenComplete(() {
          inFlight.remove(task);
        });
      }
    }();

    final endpoint =
        Uri.parse('http://127.0.0.1:${server.port}/v1/sources/resolve');
    final client = HttpClient()..maxConnectionsPerHost = 200;
    addTearDown(() => client.close(force: true));

    String payloadFor(int id) {
      return jsonEncode(<String, dynamic>{
        'profileId': 'profile-${id % 7}',
        'tmdbId': 600000 + id,
        'mediaType': 'movie',
        'providerConfig': const <String, dynamic>{
          'providerPriority': <String>['videasy'],
          'providerTimeoutSeconds': 5,
          'disabledProviders': <String>[],
        },
        'settings': const <String, dynamic>{
          'languageCode': 'en',
          'subtitleUrl': null,
          'autoplayNextEpisode': true,
          'autoplayPreviews': true,
          'muteAutoplayTrailers': true,
          'preferredAndroidRendererProfile': null,
        },
      });
    }

    Future<int> fireOne(int id) async {
      final request = await client.postUrl(endpoint);
      request.headers.contentType = ContentType.json;
      request.write(payloadFor(id));
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        return response.statusCode;
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      return decoded['target'] == null ? HttpStatus.noContent : HttpStatus.ok;
    }

    for (var i = 0; i < 70; i += 1) {
      await fireOne(100000 + i);
    }

    const total = 600;
    const concurrency = 50;
    final rssBefore = ProcessInfo.currentRss;
    final latenciesMs = <double>[];
    var errors = 0;

    final benchmark = Stopwatch()..start();
    var launched = 0;
    final clientInFlight = <Future<void>>[];

    Future<void> launchRequest(int id) async {
      final requestTimer = Stopwatch()..start();
      try {
        final status = await fireOne(id);
        if (status != HttpStatus.ok) {
          errors += 1;
        }
      } catch (_) {
        errors += 1;
      } finally {
        requestTimer.stop();
        latenciesMs.add(requestTimer.elapsedMicroseconds / 1000);
      }
    }

    while (launched < total || clientInFlight.isNotEmpty) {
      while (launched < total && clientInFlight.length < concurrency) {
        final id = launched;
        launched += 1;
        final future = launchRequest(id);
        clientInFlight.add(future);
        future.whenComplete(() {
          clientInFlight.remove(future);
        });
      }
      if (clientInFlight.isNotEmpty) {
        await Future.any(clientInFlight);
      }
    }
    benchmark.stop();
    final rssAfter = ProcessInfo.currentRss;

    latenciesMs.sort();
    double percentile(double p) {
      if (latenciesMs.isEmpty) {
        return 0;
      }
      final index = math.max(
        0,
        math.min(
          latenciesMs.length - 1,
          ((latenciesMs.length - 1) * p).round(),
        ),
      );
      return latenciesMs[index];
    }

    final elapsedSeconds = benchmark.elapsedMilliseconds / 1000;
    final throughput = total / elapsedSeconds;
    final errorRate = errors / total;
    final p95 = percentile(0.95);
    final p99 = percentile(0.99);
    final rssDeltaBytes = rssAfter - rssBefore;

    print(
      'Source resolver stress metrics: '
      'throughput_rps=${throughput.toStringAsFixed(2)}, '
      'p95_ms=${p95.toStringAsFixed(2)}, '
      'p99_ms=${p99.toStringAsFixed(2)}, '
      'error_rate=${(errorRate * 100).toStringAsFixed(2)}%, '
      'rss_delta_mb=${(rssDeltaBytes / (1024 * 1024)).toStringAsFixed(2)}',
    );

    expect(errorRate, lessThan(0.01));
    expect(p95, lessThan(260));
    expect(p99, lessThan(340));
    expect(rssDeltaBytes, lessThan(70 * 1024 * 1024));
  });
}

class _AlwaysTrueProbe implements backend.PlaybackTargetProbe {
  @override
  Future<bool> canLoad(
    backend.PlaybackTarget target,
    Duration timeout,
  ) async {
    return true;
  }
}
