import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/playback_target.dart';

void main() {
  test('PlaybackTarget serializes direct stream metadata', () {
    final target = PlaybackTarget(
      uri: Uri.parse('https://streams.example.com/movie/385687.m3u8'),
      providerKey: 'videasy',
      providerLabel: 'VidEasy',
      providerIndex: 3,
      sourceKind: PlaybackSourceKind.hls,
      httpHeaders: const <String, String>{
        'Referer': 'https://player.example.com/videasy',
      },
      pageUri: Uri.parse('https://player.example.com/videasy'),
      expiresAtEpochMs: 1,
      fallbackUris: <Uri>[
        Uri.parse('https://backup.example.com/movie/385687.m3u8'),
      ],
    );

    final json = target.toJson();
    final decoded = PlaybackTarget.fromJson(json);

    expect(decoded.uri, target.uri);
    expect(decoded.providerKey, target.providerKey);
    expect(decoded.providerLabel, target.providerLabel);
    expect(decoded.providerIndex, target.providerIndex);
    expect(decoded.sourceKind, PlaybackSourceKind.hls);
    expect(decoded.httpHeaders, target.httpHeaders);
    expect(decoded.pageUri, target.pageUri);
    expect(decoded.expiresAtEpochMs, target.expiresAtEpochMs);
    expect(decoded.fallbackUris, target.fallbackUris);
  });

  test(
      'PlaybackTarget remains backward compatible with legacy uri-only payloads',
      () {
    final decoded = PlaybackTarget.fromJson(
      <String, dynamic>{
        'uri': 'https://cdn.example.com/movie/385687.mp4',
        'providerKey': 'legacy',
        'providerLabel': 'Legacy',
        'providerIndex': 9,
      },
    );

    expect(decoded.uri, Uri.parse('https://cdn.example.com/movie/385687.mp4'));
    expect(decoded.providerKey, 'legacy');
    expect(decoded.providerLabel, 'Legacy');
    expect(decoded.providerIndex, 9);
    expect(decoded.sourceKind, PlaybackSourceKind.file);
    expect(decoded.httpHeaders, isEmpty);
    expect(decoded.pageUri, isNull);
    expect(decoded.expiresAtEpochMs, isNull);
    expect(decoded.fallbackUris, isEmpty);
  });

  test('PlaybackTarget recognizes MKV payloads as direct files', () {
    final decoded = PlaybackTarget.fromJson(
      <String, dynamic>{
        'uri': 'https://cdn.example.com/movie/385687.mkv',
        'providerKey': 'legacy',
        'providerLabel': 'Legacy',
        'providerIndex': 9,
      },
    );

    expect(decoded.sourceKind, PlaybackSourceKind.file);
    expect(decoded.isDirectPlayable, isTrue);
  });
}
