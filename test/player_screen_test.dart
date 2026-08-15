import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/caption_resolution.dart';
import 'package:cheriflix/core/models/caption_track.dart';
import 'package:cheriflix/core/models/episode_summary.dart';
import 'package:cheriflix/core/models/media_summary.dart';
import 'package:cheriflix/core/models/media_type.dart';
import 'package:cheriflix/core/models/playback_load_request.dart';
import 'package:cheriflix/core/models/playback_progress_entry.dart';
import 'package:cheriflix/core/models/playback_progress_snapshot.dart';
import 'package:cheriflix/core/models/playback_target.dart';
import 'package:cheriflix/core/models/profile_playback_settings.dart';
import 'package:cheriflix/core/models/provider_config.dart';
import 'package:cheriflix/core/services/caption_service.dart';
import 'package:cheriflix/core/services/audio_language_preference_store.dart';
import 'package:cheriflix/core/services/embed_playback_provider.dart';
import 'package:cheriflix/core/services/json_cache_store.dart';
import 'package:cheriflix/core/services/profile_repository.dart';
import 'package:cheriflix/core/services/provider_catalog.dart';
import 'package:cheriflix/core/services/provider_preference_store.dart';
import 'package:cheriflix/core/services/source_health_store.dart';
import 'package:cheriflix/core/services/source_resolver_service.dart';
import 'package:cheriflix/core/services/subtitles/subdl_caption_service.dart';
import 'package:cheriflix/core/services/tmdb_client.dart';
import 'package:cheriflix/core/services/tmdb_media_catalog_service.dart';
import 'package:cheriflix/core/widgets/tv_shortcuts.dart';
import 'package:cheriflix/features/player/player_screen.dart';
import 'package:cheriflix/features/player/widgets/player_scrub_bar.dart';

Finder _iconButton(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TvIconButton && widget.label == label,
  );
}

Finder _actionButton(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TvActionButton && widget.label == label,
  );
}

Finder _actionButtonPrefix(String prefix) {
  return find.byWidgetPredicate(
    (widget) => widget is TvActionButton && widget.label.startsWith(prefix),
  );
}

Finder _chromeOverlayGate() =>
    find.byKey(const ValueKey<String>('player_chrome_overlay_gate'));

String _primaryFocusLabel() {
  return FocusManager.instance.primaryFocus?.debugLabel ?? '';
}

Future<void> _focusScrubBar(WidgetTester tester) async {
  if (_primaryFocusLabel() != 'PlayerScrubBar') {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
  }
  expect(_primaryFocusLabel(), 'PlayerScrubBar');
}

final Uint8List _transparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7ZzE0AAAAASUVORK5CYII=',
);
final Uint8List _opaqueBlackPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAANSURBVBhXY2BgYPgPAAEEAQBwIGULAAAAAElFTkSuQmCC',
);
final Uint8List _opaqueWhitePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAANSURBVBhXY/j///9/AAn7A/0FQ0XKAAAAAElFTkSuQmCC',
);

String _scrubThumbnailUrl(int episodeId, int timestampMs) =>
    'https://example.com/preview/$episodeId/${timestampMs ~/ 1000}.jpg';

void main() {
  test('PlayerScreen uses a louder default playback volume', () {
    expect(kCheriflixDefaultPlaybackVolume, 100);
    expect(kCheriflixDefaultWebPlaybackVolume, moreOrLessEquals(1.0));
  });

  test('Android skips ffmpeg process probing', () {
    expect(
      cheriflixShouldProbeFfmpegForPlatform(TargetPlatform.android),
      isFalse,
    );
    expect(
      cheriflixShouldProbeFfmpegForPlatform(TargetPlatform.windows),
      isTrue,
    );
  });

  test('Android thumbnail strip stays unmounted until HLS fallback slots exist',
      () {
    expect(
      shouldMountThumbnailRendererStrip(
        isAndroid: true,
        activeMediaSourceKind: PlaybackSourceKind.hls,
        mountedSlotCount: 0,
      ),
      isFalse,
    );
    expect(
      shouldMountThumbnailRendererStrip(
        isAndroid: true,
        activeMediaSourceKind: PlaybackSourceKind.file,
        mountedSlotCount: 2,
      ),
      isFalse,
    );
    expect(
      shouldMountThumbnailRendererStrip(
        isAndroid: true,
        activeMediaSourceKind: PlaybackSourceKind.hls,
        mountedSlotCount: 2,
      ),
      isTrue,
    );
    expect(
      shouldMountThumbnailRendererStrip(
        isAndroid: false,
        activeMediaSourceKind: PlaybackSourceKind.file,
        mountedSlotCount: 1,
      ),
      isTrue,
    );
  });

  test('Blank scrub frame detector rejects opaque black samples', () async {
    expect(await isLikelyBlankScrubFrame(_opaqueBlackPng), isTrue);
    expect(await isLikelyBlankScrubFrame(_opaqueWhitePng), isFalse);
  });

  test(
      'Android frame-health accepts visible screenshot evidence when SurfaceTexture callbacks are alive',
      () {
    expect(
      evaluateAndroidFrameHealth(
        hasVisibleScreenshot: true,
        screenshotMissing: false,
        hasFrameCallbacks: true,
        hasFrameCallbacksProgressed: true,
        useSurfaceTexture: true,
        hasAttachedSurface: true,
        startupPhase: true,
      ),
      isTrue,
    );
  });

  test(
      'Android frame-health rejects screenshot-only evidence when SurfaceTexture callback path is dead',
      () {
    expect(
      evaluateAndroidFrameHealth(
        hasVisibleScreenshot: true,
        screenshotMissing: false,
        hasFrameCallbacks: false,
        hasFrameCallbacksProgressed: false,
        useSurfaceTexture: true,
        hasAttachedSurface: true,
        startupPhase: true,
      ),
      isFalse,
    );
  });

  test(
      'Android frame-health requires callback progression for SurfaceTexture when screenshots are inconclusive',
      () {
    expect(
      evaluateAndroidFrameHealth(
        hasVisibleScreenshot: false,
        screenshotMissing: false,
        hasFrameCallbacks: true,
        hasFrameCallbacksProgressed: false,
        useSurfaceTexture: true,
        hasAttachedSurface: true,
        startupPhase: false,
      ),
      isFalse,
    );
  });

  test(
      'Android frame-health treats startup dead-surface telemetry as unhealthy',
      () {
    expect(
      evaluateAndroidFrameHealth(
        hasVisibleScreenshot: false,
        screenshotMissing: false,
        hasFrameCallbacks: true,
        hasFrameCallbacksProgressed: true,
        useSurfaceTexture: false,
        hasAttachedSurface: true,
        startupPhase: true,
        surfaceAttachRetryCount: 1,
      ),
      isFalse,
    );
    expect(
      evaluateAndroidFrameHealth(
        hasVisibleScreenshot: true,
        screenshotMissing: false,
        hasFrameCallbacks: false,
        hasFrameCallbacksProgressed: false,
        useSurfaceTexture: true,
        hasAttachedSurface: true,
        startupPhase: true,
        frameWatchdogReattachCount: 1,
      ),
      isFalse,
    );
  });

  test(
      'Android frame-health rejects decode-only producer screenshots when startup telemetry reports dead surface',
      () {
    expect(
      evaluateAndroidFrameHealth(
        hasVisibleScreenshot: true,
        screenshotMissing: false,
        hasFrameCallbacks: false,
        hasFrameCallbacksProgressed: false,
        useSurfaceTexture: false,
        hasAttachedSurface: true,
        startupPhase: true,
        surfaceAttachRetryCount: 1,
      ),
      isFalse,
    );
  });

  test('Android frame-health allows producer path with visible screenshots',
      () {
    expect(
      evaluateAndroidFrameHealth(
        hasVisibleScreenshot: true,
        screenshotMissing: false,
        hasFrameCallbacks: false,
        hasFrameCallbacksProgressed: false,
        useSurfaceTexture: false,
        hasAttachedSurface: true,
        startupPhase: false,
      ),
      isTrue,
    );
  });

  test('Android frame-health rejects missing screenshots on producer path', () {
    expect(
      evaluateAndroidFrameHealth(
        hasVisibleScreenshot: false,
        screenshotMissing: true,
        hasFrameCallbacks: false,
        hasFrameCallbacksProgressed: false,
        useSurfaceTexture: false,
        hasAttachedSurface: true,
        startupPhase: false,
      ),
      isFalse,
    );
  });

  test('Scrub frame capture uses the exact label time', () {
    expect(
      scrubFrameCapturePosition(const Duration(seconds: 5)),
      const Duration(seconds: 5),
    );
    expect(
      scrubFrameCapturePosition(const Duration(milliseconds: 80)),
      const Duration(milliseconds: 80),
    );
  });

  test('ffmpeg scrub extraction is disabled for HLS sources', () {
    expect(
      shouldUseFfmpegScrubExtraction(
        sourceKind: PlaybackSourceKind.hls,
        mediaUri: Uri.parse('https://streams.example.com/video/master.m3u8'),
      ),
      isFalse,
    );
    expect(
      shouldUseFfmpegScrubExtraction(
        sourceKind: PlaybackSourceKind.file,
        mediaUri: Uri.parse('https://cdn.example.com/video.mp4'),
      ),
      isTrue,
    );
  });

  testWidgets('PlayerScreen loads direct playback into the in-app surface',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    final preferenceStore = _MemoryPreferenceStore();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            preferenceStore: preferenceStore,
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(surface.loadedUris, <Uri>[
      Uri.parse('https://streams.example.com/vidlink/movie/385687.m3u8'),
    ]);
    expect(surface.loadedSourceKinds, <PlaybackSourceKind>[
      PlaybackSourceKind.hls,
    ]);
    expect(
      find.text(
          'Fake playback: https://streams.example.com/vidlink/movie/385687.m3u8'),
      findsOneWidget,
    );
    expect(surface.playerState.value.isPaused, isFalse);
    expect(
      await preferenceStore.getLastGoodProviderIndex(
        profileId: 'profile-1',
        tmdbId: 385687,
        mediaType: MediaType.movie,
      ),
      1,
    );
  });

  testWidgets('PlayerScreen shows no sources when no source resolves',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    final previousErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('Cannot get renderObject of inactive element')) {
        return;
      }
      previousErrorHandler?.call(details);
    };
    addTearDown(() {
      FlutterError.onError = previousErrorHandler;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
            disabledProviders: _vidlinkOnlyDisabledProviders,
            sourceResolverService: const _UnavailableSourceResolverService(),
            probe: _FailingProbe(),
            allowEmbedFallback: false,
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('No sources'), findsOneWidget);
    expect(find.text('No sources found.'), findsOneWidget);
    expect(surface.loadedUris, isEmpty);
  });

  testWidgets('PlayerScreen uses local frame extraction while scrubbing',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    final requestedTimestamps = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async {
            requestedTimestamps.add(timestampMs);
            return _scrubThumbnailUrl(episodeId, timestampMs);
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await _focusScrubBar(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(surface.extractedFramePositions, isNotEmpty);
    expect(
      surface.extractedFramePositions.map((position) => position.inSeconds),
      contains(5),
    );
    expect(requestedTimestamps, isEmpty);
  });

  testWidgets(
      'PlayerScreen falls back to preview URLs when local scrub extraction fails',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      returnNullFrameExtractions: true,
    );
    final requestedTimestamps = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async {
            requestedTimestamps.add(timestampMs);
            return _scrubThumbnailUrl(episodeId, timestampMs);
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await _focusScrubBar(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(surface.extractedFramePositions, isNotEmpty);
    expect(requestedTimestamps, isNotEmpty);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('PlayerScreen resumes from the saved position', (tester) async {
    final surface = _FakePlaybackSurfaceController(startPausedOnLoad: true);

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          initialResumePosition: const Duration(minutes: 2),
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(surface.seekToCalls, <Duration>[const Duration(minutes: 2)]);
    expect(surface.playCalls, 1);
  });

  testWidgets('PlayerScreen retries a silently ignored initial resume seek',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      startPausedOnLoad: true,
      ignoredSeekAttempts: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          initialResumePosition: const Duration(minutes: 2),
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(surface.seekToCalls, <Duration>[
      const Duration(minutes: 2),
      const Duration(minutes: 2),
    ]);
    expect(
      surface.playerState.value.currentPosition,
      const Duration(minutes: 2),
    );
    expect(surface.playCalls, greaterThanOrEqualTo(1));
  });
  testWidgets('PlayerScreen manual seek cancels a pending resume retry',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      startPausedOnLoad: true,
      ignoredSeekAttempts: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          initialResumePosition: const Duration(minutes: 2),
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(surface.seekToCalls, <Duration>[const Duration(minutes: 2)]);

    await tester.sendKeyEvent(LogicalKeyboardKey.mediaFastForward);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(surface.seekToCalls, <Duration>[
      const Duration(minutes: 2),
      const Duration(seconds: 10),
    ]);
    expect(
      surface.playerState.value.currentPosition,
      const Duration(seconds: 10),
    );
  });

  testWidgets(
      'PlayerScreen leaves the provider when resumed playback snaps back',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      startPausedOnLoad: true,
      snapBackSeekAttempts: 1,
    );
    final initialUri =
        Uri.parse('https://streams.example.com/vidlink/movie/385687.m3u8');
    final backupUri =
        Uri.parse('https://streams.example.com/videasy/movie/385687.m3u8');
    final sameProviderFallbackUri =
        Uri.parse('https://mirror.example.com/vidlink/movie/385687.m3u8');

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink', 'videasy'],
            sourceResolverService: _ScriptedSourceResolverService(
              fallbackUris: <Uri>[sameProviderFallbackUri],
            ),
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          initialResumePosition: const Duration(minutes: 2),
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));

    expect(surface.loadedUris, <Uri>[initialUri, backupUri]);
    expect(
      surface.seekToCalls,
      <Duration>[
        const Duration(minutes: 2),
        const Duration(minutes: 2),
      ],
    );
    expect(
        surface.playerState.value.currentPosition, const Duration(minutes: 2));
  });
  testWidgets('PlayerScreen resumes even before direct duration is known',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      startPausedOnLoad: true,
      totalDuration: Duration.zero,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          initialResumePosition: const Duration(minutes: 2),
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(surface.seekToCalls, <Duration>[const Duration(minutes: 2)]);
    expect(surface.playCalls, 1);
  });

  testWidgets('PlayerScreen ignores tiny resume anchors near the beginning',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(startPausedOnLoad: true);

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          initialResumePosition: const Duration(seconds: 12),
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(surface.seekToCalls, isEmpty);
  });

  testWidgets('PlayerScreen keeps the resume anchor across source failover',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      directLoadsWithoutFrame: 1,
      directLoadsWithoutFrameReportMetadata: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink', 'videasy'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          initialResumePosition: const Duration(minutes: 2),
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    // A resume seek must not be used as a synthetic readiness probe. The
    // first source reports metadata but never renders, so let the normal
    // direct-frame watchdog reject it before verifying that the resume anchor
    // survives the failover.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 13));
    await tester.pump(const Duration(milliseconds: 100));

    expect(surface.loadedUris, <Uri>[
      Uri.parse('https://streams.example.com/vidlink/movie/385687.m3u8'),
      Uri.parse('https://streams.example.com/videasy/movie/385687.m3u8'),
    ]);
    expect(surface.loadedRendererProfiles, <PlaybackRendererProfile>[
      PlaybackRendererProfile.standard,
      PlaybackRendererProfile.standard,
    ]);
    expect(surface.seekToCalls, isNotEmpty);
    expect(
      surface.seekToCalls
          .every((position) => position == const Duration(minutes: 2)),
      isTrue,
    );
  });

  testWidgets(
      'PlayerScreen blocks low-position progress updates while resume is pending',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      initialPosition: const Duration(seconds: 5),
    );
    final progressUpdates = <PlaybackProgressEntry>[];

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          initialResumePosition: const Duration(minutes: 2),
          onBack: () {},
          onProgressChanged: (entry) async => progressUpdates.add(entry),
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(progressUpdates, isNotEmpty);
    expect(
      progressUpdates
          .where((entry) => entry.position < const Duration(seconds: 30)),
      isEmpty,
    );
    expect(
      progressUpdates.last.position,
      greaterThanOrEqualTo(const Duration(minutes: 2)),
    );
  });

  testWidgets('PlayerScreen reaches and uses the scrub bar with the d-pad',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_primaryFocusLabel(), 'PlayerPlayPause');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(_primaryFocusLabel(), 'PlayerScrubBar');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_primaryFocusLabel(), 'PlayerPlayPause');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(_primaryFocusLabel(), 'PlayerScrubBar');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(surface.seekToCalls, isEmpty);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(surface.seekToCalls, isEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(surface.seekToCalls, <Duration>[const Duration(seconds: 5)]);
  });

  testWidgets('PlayerScreen reuses local scrub thumbnails for same timestamp',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await _focusScrubBar(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    final firstCenterFrameCount = surface.extractedFramePositions
        .where((position) => position.inSeconds == 5)
        .length;

    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(
      surface.extractedFramePositions
          .where((position) => position.inSeconds == 5)
          .length,
      firstCenterFrameCount,
    );
  });

  testWidgets('PlayerScreen throttles direct HLS scrub extraction work',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      frameExtractionDelay: const Duration(milliseconds: 60),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await _focusScrubBar(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(surface.maxConcurrentFrameExtractions, lessThanOrEqualTo(1));
  });

  testWidgets('PlayerScreen keeps subtitles visible while scrubbing',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    surface.setSubtitleLines(const <String>['Hello there']);
    await tester.pump();

    expect(_primaryFocusLabel(), 'PlayerPlayPause');
    await _focusScrubBar(tester);
    expect(find.text('\u2013Hello there'), findsOneWidget);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('player_scrub_thumbnail_strip')),
          )
          .height,
      0,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('player_scrub_thumbnail_strip')),
          )
          .height,
      greaterThan(0),
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('player_scrub_thumbnail_strip')),
          )
          .width,
      closeTo(800, 0.1),
    );
    expect(
      find.byKey(const ValueKey<String>('player_scrub_playhead_cursor')),
      findsNothing,
    );
    final firstFrameSize = tester.getSize(
      find.byKey(const ValueKey<String>('player_scrub_thumbnail_frame_5')),
    );
    expect(
      firstFrameSize.width / firstFrameSize.height,
      closeTo(PlayerScrubBar.defaultThumbnailAspectRatio, 0.02),
    );
    expect(surface.extractedFramePositions, isNotEmpty);
    expect(find.text('\u2013Hello there'), findsOneWidget);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));

    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('player_scrub_thumbnail_strip')),
          )
          .height,
      greaterThan(0),
    );
    expect(find.text('\u2013Hello there'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('player_scrub_thumbnail_strip')),
          )
          .height,
      greaterThan(0),
    );
    expect(find.text('\u2013Hello there'), findsOneWidget);

    // Model genuine playback progression before advancing the fake clock far
    // enough to exercise scrub timeout behaviour. A visible surface frozen at
    // 0:00 is now intentionally treated as a failed startup source.
    surface.updatePlayerState(
      (presentation) => presentation.copyWith(
        currentPosition: const Duration(seconds: 10),
        isBuffering: false,
        hasRenderedFrame: true,
      ),
    );
    await tester.pump();

    final playbackProgressTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => surface.updatePlayerState(
        (presentation) => presentation.copyWith(
          currentPosition:
              presentation.currentPosition + const Duration(seconds: 1),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 88));
    playbackProgressTimer.cancel();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('player_scrub_thumbnail_strip')),
          )
          .height,
      0,
    );
    expect(find.text('\u2013Hello there'), findsOneWidget);
  });

  testWidgets(
      'PlayerScreen hides the scrubber and shows seek loading while a scrub jump is in progress',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      seekDelay: const Duration(milliseconds: 100),
      seekLoadedDelay: const Duration(milliseconds: 350),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_primaryFocusLabel(), 'PlayerPlayPause');
    await _focusScrubBar(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('player_scrub_thumbnail_strip')),
          )
          .height,
      greaterThan(0),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(surface.seekToCalls, <Duration>[const Duration(seconds: 5)]);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('player_scrub_thumbnail_strip')),
          )
          .height,
      0,
    );
    expect(
      find.byKey(const ValueKey<String>('player_seek_loading_indicator')),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 150));

    expect(
      find.byKey(const ValueKey<String>('player_seek_loading_indicator')),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 350));

    expect(
      find.byKey(const ValueKey<String>('player_seek_loading_indicator')),
      findsNothing,
    );
  });

  testWidgets('PlayerScreen clears stale seek loading if backend misses ready',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      seekNeverClearsBuffering: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await _focusScrubBar(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('player_seek_loading_indicator')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 6));

    expect(
      find.byKey(const ValueKey<String>('player_seek_loading_indicator')),
      findsNothing,
    );
  });

  testWidgets(
      'PlayerScreen accumulates rapid forward skips using absolute targets',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      initialPosition: const Duration(minutes: 1),
      seekDelay: const Duration(milliseconds: 250),
    );
    final initialUri =
        Uri.parse('https://streams.example.com/vidlink/movie/385687.m3u8');

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink', 'videasy'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaFastForward);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaFastForward);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaFastForward);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      surface.seekToCalls,
      <Duration>[
        const Duration(seconds: 90),
      ],
    );
    expect(surface.loadedUris, <Uri>[initialUri]);
    expect(
      surface.playerState.value.currentPosition,
      const Duration(seconds: 90),
    );
  });

  testWidgets(
      'PlayerScreen applies the latest target after a slow seek finishes',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      initialPosition: const Duration(minutes: 1),
      seekDelay: const Duration(milliseconds: 500),
    );
    final initialUri =
        Uri.parse('https://streams.example.com/vidlink/movie/385687.m3u8');

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink', 'videasy'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaFastForward);
    await tester.pump(const Duration(milliseconds: 220));
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaFastForward);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaFastForward);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(
      surface.seekToCalls,
      <Duration>[
        const Duration(seconds: 70),
        const Duration(seconds: 90),
      ],
    );
    expect(surface.loadedUris, <Uri>[initialUri]);
    expect(
      surface.playerState.value.currentPosition,
      const Duration(seconds: 90),
    );
  });
  testWidgets(
      'PlayerScreen retries an ignored manual skip without rejecting its source',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      initialPosition: const Duration(minutes: 1),
      ignoredSeekAttempts: 1,
    );
    final initialUri =
        Uri.parse('https://streams.example.com/vidlink/movie/385687.m3u8');

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink', 'videasy'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaFastForward);
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));

    expect(
      surface.seekToCalls,
      <Duration>[
        const Duration(seconds: 70),
        const Duration(seconds: 70),
      ],
    );
    expect(surface.loadedUris, <Uri>[initialUri]);
    expect(
      surface.playerState.value.currentPosition,
      const Duration(seconds: 70),
    );
    expect(
      find.byKey(const ValueKey<String>('player_seek_loading_indicator')),
      findsNothing,
    );
  });
  testWidgets(
      'PlayerScreen does not reject a working source while a manual seek settles',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      initialPosition: const Duration(minutes: 1),
      snapBackSeekAttempts: 2,
    );
    final initialUri =
        Uri.parse('https://streams.example.com/vidlink/movie/385687.m3u8');

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink', 'videasy'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaFastForward);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(surface.loadedUris, <Uri>[initialUri]);
    expect(surface.seekToCalls, isNotEmpty);
    expect(
      find.text('No sources found.'),
      findsNothing,
    );
  });
  testWidgets(
      'PlayerScreen keyboard traversal reaches the right-side controls row',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_primaryFocusLabel(), 'PlayerPlayPause');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_primaryFocusLabel(), 'PlayerBack10');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_primaryFocusLabel(), 'PlayerForward10');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_primaryFocusLabel(), 'PlayerZoomOut');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_primaryFocusLabel(), 'PlayerZoomIn');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_primaryFocusLabel(), 'PlayerFullscreenPlaceholder');
  });

  testWidgets(
      'PlayerScreen routes top-right controls down to the scrub bar and back to play',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(_primaryFocusLabel(), 'PlayerPlayPause');

    final settingsButton = tester.widget<TvIconButton>(_iconButton('Settings'));
    settingsButton.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    expect(_primaryFocusLabel(), 'PlayerSettings');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_primaryFocusLabel(), 'PlayerScrubBar');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_primaryFocusLabel(), 'PlayerPlayPause');
  });

  testWidgets(
      'PlayerScreen opens the shared episodes overlay and dismisses it cleanly',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    final summary = MediaSummary(
      tmdbId: 79744,
      mediaType: MediaType.tv,
      title: 'The Rookie',
      overview: 'John Nolan starts over and joins the LAPD.',
      seasonCount: 2,
      runtimeMinutes: 43,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: _FakeTmdbMediaCatalogService(
            episodesBySeason: <int, List<EpisodeSummary>>{
              1: <EpisodeSummary>[
                const EpisodeSummary(
                  seasonNumber: 1,
                  episodeNumber: 1,
                  title: 'Pilot',
                  runtimeMinutes: 43,
                ),
              ],
              2: <EpisodeSummary>[
                const EpisodeSummary(
                  seasonNumber: 2,
                  episodeNumber: 1,
                  title: 'The Green Light',
                  runtimeMinutes: 43,
                ),
              ],
            },
          ),
          initialSummary: summary,
          playbackProgress: PlaybackProgressSnapshot.empty(),
          profileId: 'profile-1',
          tmdbId: 79744,
          mediaType: MediaType.tv,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(surface.playerState.value.isPaused, isFalse);

    await tester.tap(_iconButton('Browse episodes'));
    await tester.pumpAndSettle();

    expect(surface.playerState.value.isPaused, isTrue);
    expect(find.text('Season 1'), findsOneWidget);
    expect(
      find.text(
        'Playback is paused while you browse. Pick an episode to jump straight back in.',
      ),
      findsNothing,
    );

    await tester.ensureVisible(find.text('Season 1'));
    await tester.tap(find.text('Season 1'));
    await tester.pumpAndSettle();
    expect(_primaryFocusLabel(), startsWith('TvActionButton(Season'));
    final firstRailFocus = _primaryFocusLabel();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_primaryFocusLabel(), startsWith('TvActionButton(Season'));
    expect(_primaryFocusLabel(), isNot(equals(firstRailFocus)));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Season 1'), findsNothing);
    expect(surface.playerState.value.isPaused, isFalse);
  });

  testWidgets('PlayerScreen loads the selected episode from the shared overlay',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    final summary = MediaSummary(
      tmdbId: 79744,
      mediaType: MediaType.tv,
      title: 'The Rookie',
      overview: 'John Nolan starts over and joins the LAPD.',
      seasonCount: 2,
      runtimeMinutes: 43,
    );
    final catalogService = _FakeTmdbMediaCatalogService(
      episodesBySeason: <int, List<EpisodeSummary>>{
        1: <EpisodeSummary>[
          const EpisodeSummary(
            seasonNumber: 1,
            episodeNumber: 1,
            title: 'Pilot',
            runtimeMinutes: 43,
          ),
        ],
        2: <EpisodeSummary>[
          const EpisodeSummary(
            seasonNumber: 2,
            episodeNumber: 1,
            title: 'The Green Light',
            runtimeMinutes: 43,
          ),
        ],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: catalogService,
          initialSummary: summary,
          playbackProgress: PlaybackProgressSnapshot.empty(),
          profileId: 'profile-1',
          tmdbId: 79744,
          mediaType: MediaType.tv,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(
      surface.loadedUris,
      <Uri>[
        Uri.parse('https://streams.example.com/vidlink/tv/79744/1/1.m3u8'),
      ],
    );

    await tester.tap(_iconButton('Browse episodes'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Season 1'));
    await tester.tap(find.text('Season 1'));
    await tester.pumpAndSettle();
    expect(_primaryFocusLabel(), startsWith('TvActionButton(Season'));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_primaryFocusLabel(), startsWith('TvActionButton(Season'));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Episode 1 - The Green Light'));
    await tester.tap(find.text('Episode 1 - The Green Light'));
    await tester.pumpAndSettle();

    expect(
      surface.loadedUris.last,
      Uri.parse('https://streams.example.com/vidlink/tv/79744/2/1.m3u8'),
    );
    expect(
      surface.loadedUris,
      <Uri>[
        Uri.parse('https://streams.example.com/vidlink/tv/79744/1/1.m3u8'),
        Uri.parse('https://streams.example.com/vidlink/tv/79744/2/1.m3u8'),
      ],
    );
  });

  testWidgets(
      'PlayerScreen does not save outgoing progress under the next episode while resolving',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      initialPosition: const Duration(minutes: 42),
      totalDuration: const Duration(minutes: 43),
    );
    final progressUpdates = <PlaybackProgressEntry>[];
    final summary = MediaSummary(
      tmdbId: 79744,
      mediaType: MediaType.tv,
      title: 'The Rookie',
      seasonCount: 1,
      runtimeMinutes: 43,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
            sourceResolverService: const _ScriptedSourceResolverService(
              laterEpisodeResolutionDelay: Duration(seconds: 8),
            ),
          ),
          mediaCatalogService: _FakeTmdbMediaCatalogService(),
          initialSummary: summary,
          playbackProgress: PlaybackProgressSnapshot.empty(),
          profileId: 'profile-1',
          tmdbId: 79744,
          mediaType: MediaType.tv,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          onProgressChanged: (entry) async => progressUpdates.add(entry),
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(_actionButton('Next episode'), findsOneWidget);
    progressUpdates.clear();

    tester
        .widget<TvActionButton>(_actionButton('Next episode'))
        .onPressed!
        .call();
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));

    final incomingEpisodeUpdates = progressUpdates.where(
      (entry) => entry.seasonNumber == 1 && entry.episodeNumber == 2,
    );
    expect(incomingEpisodeUpdates, isEmpty);
    expect(surface.quietStopCalls, greaterThanOrEqualTo(1));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets(
      'PlayerScreen rotates away from a next episode that buffers without a frame',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      directLoadsWithoutFrameAreBuffering: true,
    );
    final summary = MediaSummary(
      tmdbId: 79744,
      mediaType: MediaType.tv,
      title: 'The Rookie',
      seasonCount: 1,
      runtimeMinutes: 43,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink', 'videasy'],
          ),
          mediaCatalogService: _FakeTmdbMediaCatalogService(),
          initialSummary: summary,
          playbackProgress: PlaybackProgressSnapshot.empty(),
          profileId: 'profile-1',
          tmdbId: 79744,
          mediaType: MediaType.tv,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(_actionButton('Next episode'), findsOneWidget);
    surface.stallNextDirectLoad();

    tester
        .widget<TvActionButton>(_actionButton('Next episode'))
        .onPressed!
        .call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      surface.loadedUris,
      contains(
        Uri.parse('https://streams.example.com/vidlink/tv/79744/1/2.m3u8'),
      ),
    );

    await tester.pump(const Duration(seconds: 13));
    await tester.pump(const Duration(milliseconds: 500));

    expect(surface.loadedUris.length, greaterThanOrEqualTo(3));
    expect(
      surface.loadedUris.last,
      isNot(
        Uri.parse('https://streams.example.com/vidlink/tv/79744/1/2.m3u8'),
      ),
    );
    expect(surface.playerState.value.hasVisibleVideo, isTrue);
    expect(surface.playerState.value.isBuffering, isFalse);
  });

  testWidgets(
      'PlayerScreen zoom controls update the player zoom state and label',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Zoom 100%'), findsOneWidget);

    await tester.tap(_iconButton('Zoom In'));
    await tester.pump();
    expect(surface.playerState.value.zoomScale, closeTo(1.05, 0.0001));
    expect(find.text('Zoom 105%'), findsOneWidget);

    await tester.tap(_iconButton('Zoom Out'));
    await tester.pump();
    expect(surface.playerState.value.zoomScale, closeTo(1.0, 0.0001));
    expect(find.text('Zoom 100%'), findsOneWidget);

    for (var index = 0; index < 50; index += 1) {
      await tester.tap(_iconButton('Zoom In'));
      await tester.pump();
    }
    expect(surface.playerState.value.zoomScale, closeTo(3.0, 0.0001));
    expect(find.text('Zoom 300%'), findsOneWidget);

    for (var index = 0; index < 70; index += 1) {
      await tester.tap(_iconButton('Zoom Out'));
      await tester.pump();
    }
    expect(surface.playerState.value.zoomScale, closeTo(0.5, 0.0001));
    expect(find.text('Zoom 50%'), findsOneWidget);
  });

  testWidgets(
      'PlayerScreen play/pause responds on key down without waiting for key up',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_primaryFocusLabel(), 'PlayerPlayPause');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    expect(surface.pauseCalls, 1);

    await tester.pump();
    expect(surface.playerState.value.isPaused, isTrue);
    expect(_iconButton('Play'), findsOneWidget);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(surface.pauseCalls, 1);
  });

  testWidgets(
      'PlayerScreen single back hides chrome and double back asks to exit',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    var backCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () => backCalls += 1,
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.widget<IgnorePointer>(_chromeOverlayGate()).ignoring,
      isFalse,
    );

    tester.widget<TvIconButton>(_iconButton('Back')).onPressed!.call();
    await tester.pump();
    expect(backCalls, 0);
    expect(
      tester.widget<IgnorePointer>(_chromeOverlayGate()).ignoring,
      isTrue,
    );

    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(backCalls, 0);
    expect(find.text('Are you sure you want to exit?'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Are you sure you want to exit?'), findsOneWidget);

    tester.widget<TvActionButton>(_actionButton('No')).onPressed!.call();
    await tester.pumpAndSettle();
    expect(backCalls, 0);
    expect(find.text('Are you sure you want to exit?'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Are you sure you want to exit?'), findsOneWidget);

    tester.widget<TvActionButton>(_actionButton('Yes')).onPressed!.call();
    await tester.pumpAndSettle();
    expect(backCalls, 1);
  });

  testWidgets(
      'PlayerScreen hardware back hides chrome before showing exit confirmation',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    var backCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () => backCalls += 1,
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.widget<IgnorePointer>(_chromeOverlayGate()).ignoring,
      isFalse,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.text('Are you sure you want to exit?'), findsNothing);
    expect(backCalls, 0);
    expect(
      tester.widget<IgnorePointer>(_chromeOverlayGate()).ignoring,
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Are you sure you want to exit?'), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Are you sure you want to exit?'), findsOneWidget);
  });

  testWidgets(
      'PlayerScreen ignores duplicate back handlers after hiding chrome',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    var backCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () => backCalls += 1,
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Are you sure you want to exit?'), findsNothing);
    expect(
      tester.widget<IgnorePointer>(_chromeOverlayGate()).ignoring,
      isTrue,
    );

    tester.widget<TvIconButton>(_iconButton('Back')).onPressed!.call();
    await tester.pump();
    expect(find.text('Are you sure you want to exit?'), findsNothing);
    expect(backCalls, 0);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Are you sure you want to exit?'), findsOneWidget);
  });

  testWidgets('PlayerScreen closes playback settings before exit prompts',
      (tester) async {
    var surface = _FakePlaybackSurfaceController();
    var backCalls = 0;

    Future<void> pumpPlayer() async {
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            playbackProvider: _buildPlaybackProvider(
              providerPriority: const <String>['vidlink'],
            ),
            mediaCatalogService: null,
            profileId: 'profile-1',
            tmdbId: 385687,
            mediaType: MediaType.movie,
            seasonNumber: 1,
            episodeNumber: 1,
            languageCode: 'en',
            onBack: () => backCalls += 1,
            playbackSurfaceFactory: () => surface,
            scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
                _scrubThumbnailUrl(episodeId, timestampMs),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    await pumpPlayer();

    tester.widget<TvIconButton>(_iconButton('Settings')).onPressed!.call();
    await tester.pumpAndSettle();
    expect(find.text('Playback settings'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Playback settings'), findsNothing);
    expect(find.text('Are you sure you want to exit?'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Are you sure you want to exit?'), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Are you sure you want to exit?'), findsOneWidget);

    tester.widget<TvActionButton>(_actionButton('Yes')).onPressed!.call();
    await tester.pumpAndSettle();

    expect(backCalls, 1);
    expect(find.text('Playback settings'), findsNothing);

    surface = _FakePlaybackSurfaceController();
    await pumpPlayer();
    tester.widget<TvIconButton>(_iconButton('Settings')).onPressed!.call();
    await tester.pumpAndSettle();

    expect(find.text('Playback settings'), findsOneWidget);
  });

  testWidgets(
      'PlayerScreen back hides chrome first even while playback is paused',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    var backCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () => backCalls += 1,
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    surface._playerState.value = surface._playerState.value.copyWith(
      isPaused: true,
    );
    await tester.pump();
    expect(
      tester.widget<IgnorePointer>(_chromeOverlayGate()).ignoring,
      isFalse,
    );

    tester.widget<TvIconButton>(_iconButton('Back')).onPressed!.call();
    await tester.pump();
    expect(backCalls, 0);
    expect(
      tester.widget<IgnorePointer>(_chromeOverlayGate()).ignoring,
      isTrue,
    );

    await tester.pump(const Duration(milliseconds: 1600));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(backCalls, 0);
    expect(find.text('Are you sure you want to exit?'), findsOneWidget);

    tester.widget<TvActionButton>(_actionButton('Yes')).onPressed!.call();
    await tester.pump();
    expect(backCalls, 1);
  });

  testWidgets('PlayerScreen auto-hides chrome after 10 seconds of inactivity',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    var backCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () => backCalls += 1,
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 11));

    tester.widget<TvIconButton>(_iconButton('Back')).onPressed!.call();
    await tester.pump();
    expect(backCalls, 0);
    expect(find.text('Are you sure you want to exit?'), findsOneWidget);

    tester.widget<TvActionButton>(_actionButton('Yes')).onPressed!.call();
    await tester.pump();
    expect(backCalls, 1);
  });

  testWidgets('PlayerScreen reports playback progress updates', (tester) async {
    final surface = _FakePlaybackSurfaceController();
    final progressUpdates = <PlaybackProgressEntry>[];

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          onProgressChanged: (entry) async => progressUpdates.add(entry),
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await surface.seekBy(const Duration(seconds: 35));
    await tester.pump();

    expect(progressUpdates, isNotEmpty);
    expect(
      progressUpdates.last.position,
      greaterThanOrEqualTo(const Duration(seconds: 35)),
    );
  });

  testWidgets(
      'PlayerScreen actively checkpoints fresh progress every five seconds',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      initialPosition: const Duration(seconds: 35),
      totalDuration: const Duration(minutes: 100),
    );
    final progressUpdates = <PlaybackProgressEntry>[];

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          onProgressChanged: (entry) async => progressUpdates.add(entry),
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    progressUpdates.clear();
    surface.queuePlayerStateOnNextRequest(
      (presentation) => presentation.copyWith(
        currentPosition: const Duration(minutes: 80),
      ),
    );

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(surface.requestPlayerStateCalls, greaterThan(0));
    expect(progressUpdates, isNotEmpty);
    expect(progressUpdates.last.position, const Duration(minutes: 80));
  });

  testWidgets('PlayerScreen checkpoints TV progress with episode identity',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      initialPosition: const Duration(minutes: 20),
      totalDuration: const Duration(minutes: 45),
    );
    final progressUpdates = <PlaybackProgressEntry>[];

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 1399,
          mediaType: MediaType.tv,
          seasonNumber: 2,
          episodeNumber: 3,
          languageCode: 'en',
          initialSummary: MediaSummary(
            tmdbId: 1399,
            mediaType: MediaType.tv,
            title: 'Game of Thrones',
          ),
          onBack: () {},
          onProgressChanged: (entry) async => progressUpdates.add(entry),
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(progressUpdates, isNotEmpty);
    expect(progressUpdates.last.summary.tmdbId, 1399);
    expect(progressUpdates.last.seasonNumber, 2);
    expect(progressUpdates.last.episodeNumber, 3);
    expect(progressUpdates.last.position, const Duration(minutes: 20));
  });

  testWidgets(
      'PlayerScreen exit flush keeps the last trustworthy position after a reset',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      initialPosition: const Duration(minutes: 80),
      totalDuration: const Duration(minutes: 100),
    );
    final progressUpdates = <PlaybackProgressEntry>[];
    var backCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () => backCalls += 1,
          onProgressChanged: (entry) async => progressUpdates.add(entry),
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(progressUpdates, isNotEmpty);
    progressUpdates.clear();

    surface.updatePlayerState(
      (presentation) => presentation.copyWith(
        bridgeAvailable: false,
        currentPosition: Duration.zero,
        isBuffering: true,
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    tester.widget<TvActionButton>(_actionButton('Yes')).onPressed!.call();
    await tester.pumpAndSettle();

    expect(backCalls, 1);
    expect(progressUpdates, isNotEmpty);
    expect(progressUpdates.last.position, const Duration(minutes: 80));
  });
  testWidgets('PlayerScreen stops playback before leaving on confirmed exit',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      initialPosition: const Duration(seconds: 75),
    );
    final progressSave = Completer<void>();
    var shouldHoldExitSave = false;
    var backCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () => backCalls += 1,
          onProgressChanged: (entry) async {
            if (shouldHoldExitSave) {
              await progressSave.future;
            }
          },
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    shouldHoldExitSave = true;

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    tester.widget<TvActionButton>(_actionButton('Yes')).onPressed!.call();
    await tester.pump();

    expect(surface.quietStopCalls, 1);
    expect(surface.playerState.value.isPaused, isTrue);
    expect(backCalls, 0);

    progressSave.complete();
    await tester.pumpAndSettle();

    expect(backCalls, 1);
  });

  testWidgets('PlayerScreen stops and disposes the playback surface on unmount',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(surface.quietStopCalls, 1);
    expect(surface.disposeCalls, 1);
  });

  testWidgets('PlayerScreen force-saves progress when app lifecycle pauses',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    final progressUpdates = <PlaybackProgressEntry>[];

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          onProgressChanged: (entry) async => progressUpdates.add(entry),
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await surface.seekBy(const Duration(seconds: 35));
    await tester.pump();
    progressUpdates.clear();

    await surface.seekBy(const Duration(seconds: 5));
    await tester.pump();
    expect(progressUpdates, isNotEmpty);
    expect(progressUpdates.last.position, const Duration(seconds: 40));
    progressUpdates.clear();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(progressUpdates, isNotEmpty);
    expect(progressUpdates.last.position, const Duration(seconds: 40));
  });

  testWidgets('PlayerScreen restores active playback after app resumes',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final playCallsBeforePause = surface.playCalls;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    surface.updatePlayerState(
      (presentation) => presentation.copyWith(isPaused: true),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(surface.requestPlayerStateCalls, greaterThanOrEqualTo(1));
    expect(surface.playCalls, playCallsBeforePause + 1);
    expect(surface.playerState.value.isPaused, isFalse);
  });

  testWidgets(
      'PlayerScreen recovers playback after Assistant pauses before lifecycle',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(surface.playerState.value.isPaused, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.launchAssistant);
    surface.updatePlayerState(
      (presentation) => presentation.copyWith(isPaused: true),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    final playCallsBeforeResume = surface.playCalls;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(surface.requestPlayerStateCalls, greaterThanOrEqualTo(1));
    expect(surface.playCalls, playCallsBeforeResume + 1);
    expect(surface.playerState.value.isPaused, isFalse);
  });

  testWidgets('PlayerScreen immediately recovers an unrequested player stop',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    surface.updatePlayerState(
      (presentation) => presentation.copyWith(
        currentPosition: const Duration(minutes: 20),
        totalDuration: const Duration(minutes: 90),
        isPaused: true,
        isCompleted: false,
        isBuffering: false,
      ),
    );
    final playCallsBeforeRecovery = surface.playCalls;

    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();

    expect(surface.playCalls, playCallsBeforeRecovery + 1);
    expect(surface.playerState.value.isPaused, isFalse);
    expect(surface.quietStopCalls, 0);
    expect(surface.seekToCalls, isEmpty);
  });

  testWidgets('PlayerScreen switches servers when a stream ends early',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    final firstUri =
        Uri.parse('https://streams.example.com/vidlink/movie/385687.m3u8');
    final backupUri =
        Uri.parse('https://streams.example.com/videasy/movie/385687.m3u8');

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink', 'videasy'],
          ),
          mediaCatalogService: null,
          initialSummary: const MediaSummary(
            tmdbId: 385687,
            mediaType: MediaType.movie,
            title: 'One of Them Days',
            runtimeMinutes: 97,
          ),
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(surface.loadedUris, <Uri>[firstUri]);
    surface.updatePlayerState(
      (presentation) => presentation.copyWith(
        currentPosition: const Duration(minutes: 24),
        totalDuration: const Duration(minutes: 97),
        isPaused: true,
        isCompleted: true,
        isBuffering: false,
      ),
    );

    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(surface.loadedUris, <Uri>[firstUri, backupUri]);
    expect(surface.seekToCalls.last, const Duration(minutes: 24));
    expect(surface.playerState.value.isPaused, isFalse);
  });

  testWidgets('PlayerScreen keeps playback alive during memory pressure',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(surface.quietStopCalls, 0);
    expect(surface.playerState.value.isPaused, isFalse);

    tester.binding.handleMemoryPressure();
    await tester.pump();

    expect(surface.quietStopCalls, 0);
    expect(surface.playerState.value.isPaused, isFalse);
  });

  testWidgets('PlayerScreen refreshes the stream after a long viewer pause',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    final streamUri =
        Uri.parse('https://streams.example.com/vidlink/movie/385687.m3u8');

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    surface.updatePlayerState(
      (presentation) => presentation.copyWith(
        currentPosition: const Duration(minutes: 20),
        totalDuration: const Duration(minutes: 90),
      ),
    );
    await tester.pump();
    tester.widget<TvIconButton>(_iconButton('Pause')).onPressed!.call();
    await tester.pump();
    expect(surface.playerState.value.isPaused, isTrue);

    await tester.pump(const Duration(seconds: 46));
    tester.widget<TvIconButton>(_iconButton('Play')).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(surface.loadedUris, <Uri>[streamUri, streamUri]);
    expect(surface.seekToCalls.last, const Duration(minutes: 20));
    expect(surface.playerState.value.isPaused, isFalse);
  });

  testWidgets('PlayerScreen does not auto-resume user-paused playback',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    surface.updatePlayerState(
      (presentation) => presentation.copyWith(isPaused: true),
    );

    final autoplayBeforePause = surface.autoplayAttempts;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(surface.requestPlayerStateCalls, greaterThanOrEqualTo(1));
    expect(surface.autoplayAttempts, autoplayBeforePause);
    expect(surface.playerState.value.isPaused, isTrue);
  });

  testWidgets(
      'PlayerScreen manual server selection persists the chosen provider',
      (tester) async {
    final preferenceStore = _MemoryPreferenceStore();
    final firstSurface = _FakePlaybackSurfaceController();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            preferenceStore: preferenceStore,
            providerPriority: const <String>['vidlink', 'videasy'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => firstSurface,
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(
      preferenceStore.readStoredValue(
        profileId: 'profile-1',
        tmdbId: 385687,
        mediaType: MediaType.movie,
      ),
      1,
    );

    tester.widget<TvIconButton>(_iconButton('Settings')).onPressed!.call();
    await tester.pumpAndSettle();
    await tester.tap(_actionButton('Server: VidLink'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VidEasy'));
    await tester.pumpAndSettle();

    expect(
      preferenceStore.readStoredValue(
        profileId: 'profile-1',
        tmdbId: 385687,
        mediaType: MediaType.movie,
      ),
      3,
    );

    final secondSurface = _FakePlaybackSurfaceController();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            preferenceStore: preferenceStore,
            providerPriority: const <String>['vidlink', 'videasy'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => secondSurface,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(secondSurface.loadedUris, <Uri>[
      Uri.parse('https://streams.example.com/videasy/movie/385687.m3u8'),
    ]);
  });

  testWidgets(
      'PlayerScreen manual server switch keeps timestamp and paused intent',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    final progressUpdates = <PlaybackProgressEntry>[];

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink', 'videasy'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          onProgressChanged: (entry) async => progressUpdates.add(entry),
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await surface.seekBy(const Duration(minutes: 2));
    await tester.pump();
    await surface.togglePlayPause();
    await tester.pump();
    expect(surface.playerState.value.isPaused, isTrue);
    final progressCountBeforeSwitch = progressUpdates.length;

    tester.widget<TvIconButton>(_iconButton('Settings')).onPressed!.call();
    await tester.pumpAndSettle();
    await tester.tap(_actionButton('Server: VidLink'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VidEasy'));
    await tester.pumpAndSettle();

    expect(surface.loadedUris, <Uri>[
      Uri.parse('https://streams.example.com/vidlink/movie/385687.m3u8'),
      Uri.parse('https://streams.example.com/videasy/movie/385687.m3u8'),
    ]);
    expect(surface.seekToCalls.last, const Duration(minutes: 2));
    expect(surface.playerState.value.isPaused, isTrue);
    expect(progressUpdates, hasLength(progressCountBeforeSwitch));
  });

  testWidgets(
      'PlayerScreen tries an internal VidKing fallback before another provider',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    final backupUri =
        Uri.parse('https://heavy.example.com/vidking/movie/385687.m3u8');

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidking', 'videasy'],
            sourceResolverService: _ScriptedSourceResolverService(
              fallbackUris: <Uri>[backupUri],
            ),
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    surface.emitRejectedSource('The adaptive stream failed.');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(surface.loadedUris, <Uri>[
      Uri.parse('https://streams.example.com/vidking/movie/385687.m3u8'),
      backupUri,
    ]);
    expect(
      find.text('Fake playback: $backupUri'),
      findsOneWidget,
    );
  });

  testWidgets(
      'PlayerScreen automatically tries the next source after a rejected load',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidsrc', 'videasy'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    surface.emitRejectedSource(
      'This source failed after opening.',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(surface.loadedUris, <Uri>[
      Uri.parse('https://streams.example.com/vidsrc/movie/385687.m3u8'),
      Uri.parse('https://streams.example.com/videasy/movie/385687.m3u8'),
    ]);
    expect(
      find.text(
          'Fake playback: https://streams.example.com/videasy/movie/385687.m3u8'),
      findsOneWidget,
    );
  });

  testWidgets(
      'PlayerScreen keeps a confirmed source during buffering and transient frame loss',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    final initialUri =
        Uri.parse('https://streams.example.com/vidlink/movie/385687.m3u8');

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink', 'videasy'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(surface.loadedUris, <Uri>[initialUri]);

    surface.updatePlayerState(
      (presentation) => presentation.copyWith(
        currentPosition: const Duration(minutes: 4),
        isBuffering: false,
        hasRenderedFrame: true,
        renderHealthChecked: true,
        hasVerifiedVideoFrame: true,
      ),
    );
    await tester.pump();

    surface.updatePlayerState(
      (presentation) => presentation.copyWith(
        isBuffering: true,
        hasRenderedFrame: false,
        renderHealthChecked: true,
        hasVerifiedVideoFrame: false,
      ),
    );
    await tester.pump();

    surface.updatePlayerState(
      (presentation) => presentation.copyWith(
        isBuffering: false,
        hasRenderedFrame: false,
        renderHealthChecked: true,
        hasVerifiedVideoFrame: false,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(surface.loadedUris, <Uri>[initialUri]);
  });

  testWidgets(
      'PlayerScreen escapes a native startup await that never completes',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(initializationHangs: 1);
    final backupUri =
        Uri.parse('https://streams.example.com/videasy/movie/385687.m3u8');

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink', 'videasy'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 27));
    await tester.pump(const Duration(milliseconds: 500));

    expect(surface.loadedUris, <Uri>[backupUri]);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text(
          'Fake playback: https://streams.example.com/videasy/movie/385687.m3u8'),
      findsOneWidget,
    );
  });
  testWidgets('PlayerScreen rotates away from a sustained buffering stream',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    final initialUri =
        Uri.parse('https://streams.example.com/vidlink/movie/385687.m3u8');
    final backupUri =
        Uri.parse('https://streams.example.com/videasy/movie/385687.m3u8');

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink', 'videasy'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    surface.updatePlayerState(
      (presentation) => presentation.copyWith(
        currentPosition: const Duration(minutes: 12),
        isPaused: false,
        isBuffering: false,
        isCompleted: false,
        hasRenderedFrame: true,
        renderHealthChecked: true,
        hasVerifiedVideoFrame: true,
      ),
    );
    await tester.pump();
    surface.updatePlayerState(
      (presentation) => presentation.copyWith(isBuffering: true),
    );
    await tester.pump();

    // A short network wobble is tolerated, but a stream that remains frozen
    // through the nudge and recovery windows must yield to another provider.
    await tester.pump(const Duration(seconds: 25));
    await tester.pump(const Duration(milliseconds: 500));

    expect(surface.loadedUris, <Uri>[initialUri, backupUri]);
    expect(surface.seekToCalls.last, const Duration(minutes: 12));
  });
  testWidgets(
      'PlayerScreen catches repeated backward HLS loops between watchdog ticks',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    final initialUri =
        Uri.parse('https://streams.example.com/vidlink/movie/385687.m3u8');
    final backupUri =
        Uri.parse('https://streams.example.com/videasy/movie/385687.m3u8');
    final sameProviderFallbackUri =
        Uri.parse('https://mirror.example.com/vidlink/movie/385687.m3u8');

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink', 'videasy'],
            sourceResolverService: _ScriptedSourceResolverService(
              fallbackUris: <Uri>[sameProviderFallbackUri],
            ),
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    surface.updatePlayerState(
      (presentation) => presentation.copyWith(
        currentPosition: const Duration(seconds: 60),
        isPaused: false,
        isBuffering: false,
        isCompleted: false,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    surface.updatePlayerState(
      (presentation) =>
          presentation.copyWith(currentPosition: const Duration(seconds: 55)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    surface.updatePlayerState(
      (presentation) =>
          presentation.copyWith(currentPosition: const Duration(seconds: 58)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    surface.updatePlayerState(
      (presentation) =>
          presentation.copyWith(currentPosition: const Duration(seconds: 54)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));

    expect(surface.loadedUris, <Uri>[initialUri, sameProviderFallbackUri]);
    expect(surface.seekToCalls.last, const Duration(seconds: 60));

    // If the alternate stream from the same provider also loops after moving
    // beyond the restored position, quarantine that provider for this viewing
    // session instead of cycling back to it.
    surface.updatePlayerState(
      (presentation) =>
          presentation.copyWith(currentPosition: const Duration(seconds: 70)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    surface.updatePlayerState(
      (presentation) =>
          presentation.copyWith(currentPosition: const Duration(seconds: 65)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    surface.updatePlayerState(
      (presentation) =>
          presentation.copyWith(currentPosition: const Duration(seconds: 68)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    surface.updatePlayerState(
      (presentation) =>
          presentation.copyWith(currentPosition: const Duration(seconds: 64)),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      surface.loadedUris,
      <Uri>[initialUri, sameProviderFallbackUri, backupUri],
    );
    expect(surface.loadedUris.toSet().length, surface.loadedUris.length);
    expect(surface.seekToCalls.last, const Duration(seconds: 70));
  });

  testWidgets(
      'PlayerScreen rotates a stalled HLS stream instead of reloading the same looping URL',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    final initialUri =
        Uri.parse('https://streams.example.com/vidlink/movie/385687.m3u8');
    final backupUri =
        Uri.parse('https://streams.example.com/videasy/movie/385687.m3u8');

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink', 'videasy'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    surface.updatePlayerState(
      (presentation) => presentation.copyWith(
        currentPosition: const Duration(minutes: 1),
        isPaused: false,
        isBuffering: false,
        isCompleted: false,
        hasRenderedFrame: true,
        renderHealthChecked: true,
        hasVerifiedVideoFrame: true,
      ),
    );
    await tester.pump();

    // Keep the position frozen long enough for the watchdog nudge and hard
    // recovery. A looping/broken HLS source must not be reopened verbatim.
    await tester.pump(const Duration(seconds: 25));
    await tester.pump(const Duration(milliseconds: 500));

    expect(surface.loadedUris, <Uri>[initialUri, backupUri]);
    expect(surface.loadedUris.toSet().length, surface.loadedUris.length);
    expect(surface.seekToCalls.last, const Duration(minutes: 1));
  });

  testWidgets(
      'PlayerScreen recovers a zero timestamp reset without corrupting progress',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    final progressUpdates = <PlaybackProgressEntry>[];
    final initialUri =
        Uri.parse('https://streams.example.com/vidlink/movie/385687.m3u8');

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink', 'videasy'],
          ),
          mediaCatalogService: null,
          initialSummary: const MediaSummary(
            tmdbId: 385687,
            mediaType: MediaType.movie,
            title: 'Freaky',
            runtimeMinutes: 102,
          ),
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          onProgressChanged: (entry) async => progressUpdates.add(entry),
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    surface.updatePlayerState(
      (presentation) => presentation.copyWith(
        currentPosition: const Duration(minutes: 80),
        totalDuration: const Duration(minutes: 102),
        isPaused: false,
        isCompleted: false,
        isBuffering: false,
        hasRenderedFrame: true,
        renderHealthChecked: true,
        hasVerifiedVideoFrame: true,
      ),
    );
    await tester.pump();
    expect(progressUpdates.last.position, const Duration(minutes: 80));
    final progressCountAfterTrustedPosition = progressUpdates.length;

    // Reproduce the TV photo: the final decoded frame remains visible while
    // media-kit suddenly reports completion and moves its position to 00:00.
    surface.updatePlayerState(
      (presentation) => presentation.copyWith(
        currentPosition: Duration.zero,
        totalDuration: const Duration(minutes: 80),
        isPaused: true,
        isCompleted: true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      surface.loadedUris,
      <Uri>[
        initialUri,
        Uri.parse(
          'https://streams.example.com/videasy/movie/385687.m3u8',
        ),
      ],
    );
    expect(surface.seekToCalls.last, const Duration(minutes: 80));
    expect(surface.quietStopCalls, greaterThanOrEqualTo(1));
    expect(surface.playerState.value.isPaused, isFalse);
    expect(surface.playCalls, 2);
    expect(progressUpdates.last.position, const Duration(minutes: 80));
    expect(
      progressUpdates
          .skip(progressCountAfterTrustedPosition)
          .where((entry) => entry.position == Duration.zero),
      isEmpty,
    );
  });
  testWidgets('PlayerScreen resume buffers in place without source rotation',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      startPausedOnLoad: true,
      seekLoadedDelay: const Duration(seconds: 1),
    );
    final initialUri =
        Uri.parse('https://streams.example.com/vidlink/movie/385687.m3u8');

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink', 'videasy'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          initialResumePosition: const Duration(minutes: 2),
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(surface.loadedUris, <Uri>[initialUri]);
    expect(surface.seekToCalls, <Duration>[const Duration(minutes: 2)]);

    surface.updatePlayerState(
      (presentation) => presentation.copyWith(
        currentPosition: const Duration(minutes: 2),
        isBuffering: true,
        hasRenderedFrame: false,
        renderHealthChecked: true,
        hasVerifiedVideoFrame: false,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(surface.loadedUris, <Uri>[initialUri]);
    expect(surface.seekToCalls, <Duration>[const Duration(minutes: 2)]);

    surface.updatePlayerState(
      (presentation) => presentation.copyWith(
        isBuffering: false,
        hasRenderedFrame: true,
        renderHealthChecked: true,
        hasVerifiedVideoFrame: true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(surface.loadedUris, <Uri>[initialUri]);
    expect(surface.seekToCalls, <Duration>[const Duration(minutes: 2)]);
  });

  testWidgets(
      'PlayerScreen keeps direct playback loading until a rendered frame appears',
      (tester) async {
    final preferenceStore = _MemoryPreferenceStore();
    final surface = _FakePlaybackSurfaceController(
      directLoadsWithoutFrame: 1,
      directLoadsWithoutFrameReportMetadata: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            preferenceStore: preferenceStore,
            providerPriority: const <String>['vidlink', 'videasy'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      preferenceStore.readStoredValue(
        profileId: 'profile-1',
        tmdbId: 385687,
        mediaType: MediaType.movie,
      ),
      isNull,
    );
    expect(surface.loadedUris, <Uri>[
      Uri.parse('https://streams.example.com/vidlink/movie/385687.m3u8'),
    ]);
  });

  testWidgets(
      'PlayerScreen ignores saved preferred Android renderer profiles and uses standard',
      (tester) async {
    const playbackSettings = ProfilePlaybackSettings(
      languageCode: 'en',
      preferredAndroidRendererProfile: 'androidProducerStandardFallback',
    );
    final surface = _FakePlaybackSurfaceController();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          playbackSettings: playbackSettings,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(surface.loadedRendererProfiles, isNotEmpty);
    expect(
      surface.loadedRendererProfiles.first,
      PlaybackRendererProfile.standard,
    );
  });

  testWidgets(
      'PlayerScreen does not rewrite preferred renderer settings during source failover',
      (tester) async {
    const playbackSettings = ProfilePlaybackSettings(
      languageCode: 'en',
      preferredAndroidRendererProfile: 'standard',
    );
    final settingsStore = _MemoryProfileSettingsStore(
      initialSettings: playbackSettings,
    );
    final surface = _FakePlaybackSurfaceController(
      directLoadsWithBlackFrameHealth: 7,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            profileSettingsStore: settingsStore,
            providerPriority: const <String>['vidlink', 'videasy'],
          ),
          mediaCatalogService: null,
          playbackSettings: playbackSettings,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(settingsStore.saveHistory, isEmpty);
    expect(surface.loadedUris.take(2), <Uri>[
      Uri.parse('https://streams.example.com/vidlink/movie/385687.m3u8'),
      Uri.parse('https://streams.example.com/videasy/movie/385687.m3u8'),
    ]);
    expect(surface.loadedUris.toSet().length, surface.loadedUris.length);
    expect(
      surface.loadedRendererProfiles,
      everyElement(PlaybackRendererProfile.standard),
    );
  });

  testWidgets(
      'PlayerScreen fails over to the next provider when direct video never renders',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      directLoadsWithoutFrame: 1,
      directLoadsWithoutFrameReportMetadata: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink', 'videasy'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(surface.loadedUris, <Uri>[
      Uri.parse('https://streams.example.com/vidlink/movie/385687.m3u8'),
    ]);
    expect(surface.loadedRendererProfiles, <PlaybackRendererProfile>[
      PlaybackRendererProfile.standard,
    ]);

    await tester.pump(const Duration(seconds: 13));
    await tester.pump();

    expect(surface.loadedUris, <Uri>[
      Uri.parse('https://streams.example.com/vidlink/movie/385687.m3u8'),
      Uri.parse('https://streams.example.com/videasy/movie/385687.m3u8'),
    ]);
    expect(surface.loadedRendererProfiles, <PlaybackRendererProfile>[
      PlaybackRendererProfile.standard,
      PlaybackRendererProfile.standard,
    ]);
    expect(
      find.text(
          'Fake playback: https://streams.example.com/videasy/movie/385687.m3u8'),
      findsOneWidget,
    );
  });

  testWidgets('PlayerScreen fails over when one decoded frame never progresses',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      directLoadsWithoutFrame: 1,
      directLoadsWithoutFrameReportMetadata: true,
      directLoadsWithoutFrameHasRenderedFrame: true,
      directLoadsWithoutFramePosition: const Duration(milliseconds: 125),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink', 'videasy'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(surface.playerState.value.hasVisibleVideo, isTrue);
    expect(
      surface.playerState.value.currentPosition,
      const Duration(milliseconds: 125),
    );
    expect(surface.loadedUris, <Uri>[
      Uri.parse('https://streams.example.com/vidlink/movie/385687.m3u8'),
    ]);

    await tester.pump(const Duration(seconds: 13));
    await tester.pump();

    expect(surface.loadedUris, <Uri>[
      Uri.parse('https://streams.example.com/vidlink/movie/385687.m3u8'),
      Uri.parse('https://streams.example.com/videasy/movie/385687.m3u8'),
    ]);
  });

  testWidgets(
      'PlayerScreen fails over when render health marks the direct video black',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      directLoadsWithBlackFrameHealth: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink', 'videasy'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(surface.loadedUris, <Uri>[
      Uri.parse('https://streams.example.com/vidlink/movie/385687.m3u8'),
      Uri.parse('https://streams.example.com/videasy/movie/385687.m3u8'),
    ]);
    expect(surface.loadedRendererProfiles, <PlaybackRendererProfile>[
      PlaybackRendererProfile.standard,
      PlaybackRendererProfile.standard,
    ]);
  });

  testWidgets(
      'PlayerScreen ignores blocked popup navigation when the current embed can keep playing',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    final embedUri = Uri.parse(
      'https://vidsrc.to/embed/movie/385687?autoplay=1&mute=1',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidsrc', 'videasy'],
            sourceResolverService: const MissingSourceResolverService(),
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(surface.loadedUris, <Uri>[embedUri]);

    surface.emitBlockedNavigation(
      Uri.parse('https://ads.example.com/popup'),
      keepCurrentPlayback: true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(surface.loadedUris, <Uri>[embedUri]);
  });

  testWidgets(
      'PlayerScreen promotes embed playback into the native player when a direct stream is detected',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    final preferenceStore = _MemoryPreferenceStore();
    final embedUri = Uri.parse(
      'https://vidsrc.to/embed/movie/385687?autoplay=1&mute=1',
    );
    final directUri =
        Uri.parse('https://streams.example.com/vidsrc/movie/385687.m3u8');

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            preferenceStore: preferenceStore,
            providerPriority: const <String>['vidsrc'],
            sourceResolverService: const MissingSourceResolverService(),
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(surface.loadedUris, <Uri>[embedUri]);
    expect(surface.loadedSourceKinds, <PlaybackSourceKind>[
      PlaybackSourceKind.embed,
    ]);
    expect(
      await preferenceStore.getLastGoodProviderIndex(
        profileId: 'profile-1',
        tmdbId: 385687,
        mediaType: MediaType.movie,
      ),
      isNull,
    );

    surface.emitDirectSourceDetected(
      uri: directUri,
      sourceKind: PlaybackSourceKind.hls,
      httpHeaders: <String, String>{
        'Referer': embedUri.toString(),
        'Origin': 'https://vidsrc.to',
      },
      pageUri: embedUri,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(surface.loadedUris, <Uri>[embedUri, directUri]);
    expect(surface.loadedSourceKinds, <PlaybackSourceKind>[
      PlaybackSourceKind.embed,
      PlaybackSourceKind.hls,
    ]);
    expect(surface.loadedHeaders.last, <String, String>{
      'Referer': embedUri.toString(),
      'Origin': 'https://vidsrc.to',
    });
    expect(
      await preferenceStore.getLastGoodProviderIndex(
        profileId: 'profile-1',
        tmdbId: 385687,
        mediaType: MediaType.movie,
      ),
      6,
    );
  });

  testWidgets(
      'PlayerScreen ignores a late embed rejection after promoting a direct stream',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    final embedUri = Uri.parse(
      'https://vidsrc.to/embed/movie/385687?autoplay=1&mute=1',
    );
    final directUri =
        Uri.parse('https://streams.example.com/vidsrc/movie/385687.m3u8');

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidsrc', 'videasy'],
            sourceResolverService: const MissingSourceResolverService(),
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(surface.loadedUris, <Uri>[embedUri]);

    surface.emitDirectSourceDetected(
      uri: directUri,
      sourceKind: PlaybackSourceKind.hls,
      httpHeaders: <String, String>{
        'Referer': embedUri.toString(),
      },
      pageUri: embedUri,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(surface.loadedUris, <Uri>[embedUri, directUri]);

    surface.emitRejectedSource('Stale embed rejection');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(surface.loadedUris, <Uri>[embedUri, directUri]);
  });

  testWidgets(
      'PlayerScreen abandons a stalled embed surface that never exposes a direct stream',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      stallEmbedPlayback: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidsrc'],
            disabledProviders: const <String>{
              'vidlink',
              'vidsrc_embed',
              'videasy',
              '111movies',
              'vidzee',
              '2embed',
              'mapple',
              'primesrc',
              'multiembed',
              'autoembed',
              'embedsu',
              'vsembed',
              'vsrcsu',
              'vidsrcme',
              'hdrezka',
            },
            sourceResolverService: const MissingSourceResolverService(),
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(surface.loadedSourceKinds, <PlaybackSourceKind>[
      PlaybackSourceKind.embed,
    ]);

    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();

    expect(find.text('No sources'), findsOneWidget);
    expect(find.text('No sources found.'), findsOneWidget);
  });

  testWidgets(
      'PlayerScreen keeps a stalled embed blocked behind the app player surface',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      stallEmbedPlayback: true,
    );
    final embedUri = Uri.parse(
      'https://vidsrc.to/embed/movie/385687?autoplay=1&mute=1',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidsrc'],
            disabledProviders: const <String>{
              'vidlink',
              'vidsrc_embed',
              'videasy',
              '111movies',
              'vidzee',
              '2embed',
              'mapple',
              'primesrc',
              'multiembed',
              'autoembed',
              'embedsu',
              'vsembed',
              'vsrcsu',
              'vidsrcme',
              'hdrezka',
            },
            sourceResolverService: const MissingSourceResolverService(),
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(surface.loadedUris, <Uri>[embedUri]);
    expect(surface.autoplayAttempts, 0);
    expect(find.textContaining('center play button'), findsNothing);
  });

  testWidgets(
      'PlayerScreen keeps a false-playing hidden extractor blocked behind loading state',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      stallEmbedPlayback: true,
      stalledEmbedReportsPlaying: true,
    );
    final embedUri = Uri.parse(
      'https://vidsrc.to/embed/movie/385687?autoplay=1&mute=1',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidsrc'],
            disabledProviders: const <String>{
              'vidlink',
              'vidsrc_embed',
              'videasy',
              '111movies',
              'vidzee',
              '2embed',
              'mapple',
              'primesrc',
              'multiembed',
              'autoembed',
              'embedsu',
              'vsembed',
              'vsrcsu',
              'vidsrcme',
              'hdrezka',
            },
            sourceResolverService: const MissingSourceResolverService(),
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(surface.loadedUris, <Uri>[embedUri]);
    expect(surface.autoplayAttempts, 0);
    expect(find.textContaining('center play button'), findsNothing);
  });

  testWidgets(
      'PlayerScreen abandons a false-playing embed that never advances from 0:00',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      stallEmbedPlayback: true,
      stalledEmbedReportsPlaying: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidsrc'],
            disabledProviders: const <String>{
              'vidlink',
              'vidsrc_embed',
              'videasy',
              '111movies',
              'vidzee',
              '2embed',
              'mapple',
              'primesrc',
              'multiembed',
              'autoembed',
              'embedsu',
              'vsembed',
              'vsrcsu',
              'vidsrcme',
              'hdrezka',
            },
            sourceResolverService: const MissingSourceResolverService(),
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();

    expect(find.text('No sources'), findsOneWidget);
    expect(find.text('No sources found.'), findsOneWidget);
  });

  testWidgets('PlayerScreen caption picker shows direct-playback tracks',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          captionService: _StaticCaptionService(
            CaptionResolution(
              tracks: <CaptionTrack>[
                CaptionTrack(
                  id: 'manual-en',
                  label: 'Handmade English',
                  languageCode: 'en',
                  kind: CaptionTrackKind.manual,
                  format: CaptionTrackFormat.vtt,
                  url: Uri.parse('https://captions.example.com/manual.vtt'),
                  isDefault: true,
                ),
                CaptionTrack(
                  id: 'auto-en',
                  label: 'Auto English',
                  languageCode: 'en',
                  kind: CaptionTrackKind.auto,
                  format: CaptionTrackFormat.vtt,
                  url: Uri.parse('https://captions.example.com/auto.vtt'),
                ),
              ],
              selectedTrackId: 'manual-en',
            ),
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    tester.widget<TvIconButton>(_iconButton('Subtitles')).onPressed!.call();
    await tester.pumpAndSettle();

    expect(find.text('Caption tracks'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Source 1'), findsOneWidget);
    expect(find.text('Source 2'), findsOneWidget);
    expect(find.text('Handmade English  [Handmade]'), findsNothing);
    expect(find.text('Auto English  [Auto]'), findsNothing);
  });

  testWidgets('PlayerScreen restores playback after subtitle source switch',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      pauseOnCaptionSelect: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          captionService: _StaticCaptionService(
            CaptionResolution(
              tracks: <CaptionTrack>[
                CaptionTrack(
                  id: 'manual-en',
                  label: 'Handmade English',
                  languageCode: 'en',
                  kind: CaptionTrackKind.manual,
                  format: CaptionTrackFormat.vtt,
                  url: Uri.parse('https://captions.example.com/manual.vtt'),
                  isDefault: true,
                ),
                CaptionTrack(
                  id: 'auto-en',
                  label: 'Auto English',
                  languageCode: 'en',
                  kind: CaptionTrackKind.auto,
                  format: CaptionTrackFormat.vtt,
                  url: Uri.parse('https://captions.example.com/auto.vtt'),
                ),
              ],
              selectedTrackId: 'manual-en',
            ),
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(surface.playerState.value.isPaused, isFalse);

    tester.widget<TvIconButton>(_iconButton('Subtitles')).onPressed!.call();
    await tester.pumpAndSettle();
    await tester.tap(_actionButton('Source 2'));
    await tester.pumpAndSettle();

    expect(surface.selectedCaptionTrackCalls, <String?>['auto-en']);
    expect(surface.playerState.value.selectedCaptionTrackId, 'auto-en');
    expect(surface.playerState.value.isPaused, isFalse);
  });

  testWidgets(
      'PlayerScreen survives rapid media keys and subtitle switches under playback',
      (tester) async {
    final surface = _FakePlaybackSurfaceController(
      pauseOnCaptionSelect: true,
    );
    final captionResolution = CaptionResolution(
      tracks: <CaptionTrack>[
        CaptionTrack(
          id: 'manual-en',
          label: 'Handmade English',
          languageCode: 'en',
          kind: CaptionTrackKind.manual,
          format: CaptionTrackFormat.vtt,
          url: Uri.parse('https://captions.example.com/manual.vtt'),
          isDefault: true,
        ),
        CaptionTrack(
          id: 'auto-en',
          label: 'Auto English',
          languageCode: 'en',
          kind: CaptionTrackKind.auto,
          format: CaptionTrackFormat.vtt,
          url: Uri.parse('https://captions.example.com/auto.vtt'),
        ),
      ],
      selectedTrackId: 'manual-en',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          captionService: _StaticCaptionService(captionResolution),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    final sequence = <String>['Source 2', 'Source 1', 'Source 2', 'Source 1'];
    for (final label in sequence) {
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPause);
      await tester.pump();
      expect(surface.playerState.value.isPaused, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlay);
      await tester.pump();
      expect(surface.playerState.value.isPaused, isFalse);

      tester.widget<TvIconButton>(_iconButton('Subtitles')).onPressed!.call();
      await tester.pumpAndSettle();
      await tester.tap(_actionButton(label));
      await tester.pumpAndSettle();
      expect(surface.playerState.value.isPaused, isFalse);
    }

    expect(surface.selectedCaptionTrackCalls, hasLength(sequence.length));
    expect(surface.playerState.value.selectedCaptionTrackId, 'manual-en');
  });

  testWidgets(
      'PlayerScreen settings can open subtitle source picker with available tracks',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          captionService: _StaticCaptionService(
            CaptionResolution(
              tracks: <CaptionTrack>[
                CaptionTrack(
                  id: 'manual-en',
                  label: 'Handmade English',
                  languageCode: 'en',
                  kind: CaptionTrackKind.manual,
                  format: CaptionTrackFormat.vtt,
                  url: Uri.parse('https://captions.example.com/manual.vtt'),
                  isDefault: true,
                ),
                CaptionTrack(
                  id: 'auto-en',
                  label: 'Auto English',
                  languageCode: 'en',
                  kind: CaptionTrackKind.auto,
                  format: CaptionTrackFormat.vtt,
                  url: Uri.parse('https://captions.example.com/auto.vtt'),
                ),
              ],
              selectedTrackId: 'manual-en',
            ),
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    tester.widget<TvIconButton>(_iconButton('Settings')).onPressed!.call();
    await tester.pumpAndSettle();
    await tester.tap(_actionButtonPrefix('Subtitles'));
    await tester.pumpAndSettle();

    expect(find.text('Caption tracks'), findsOneWidget);
    expect(find.text('Source 1'), findsOneWidget);
    expect(find.text('Source 2'), findsOneWidget);
    expect(find.text('Handmade English  [Handmade]'), findsNothing);
    expect(find.text('Auto English  [Auto]'), findsNothing);
  });

  testWidgets('PlayerScreen control switches and remembers audio language',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    final audioPreferences = _MemoryAudioLanguagePreferenceStore();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          audioLanguagePreferenceStore: audioPreferences,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    surface.updatePlayerState(
      (presentation) => presentation.copyWith(
        audioTracks: const <PlaybackAudioTrack>[
          PlaybackAudioTrack(
            id: 'audio-es',
            label: 'Spanish',
            languageCode: 'es',
          ),
          PlaybackAudioTrack(
            id: 'audio-en',
            label: 'English',
            languageCode: 'en',
          ),
        ],
        selectedAudioTrackId: 'audio-es',
        selectedAudioTrackLabel: 'Spanish',
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('player_audio_language_button')),
      findsOneWidget,
    );
    tester
        .widget<TvIconButton>(_iconButton('Audio / Language'))
        .onPressed!
        .call();
    await tester.pumpAndSettle();

    expect(find.text('Choose audio language'), findsOneWidget);
    await tester.tap(_actionButton('English'));
    await tester.pumpAndSettle();

    expect(surface.selectedAudioTrackCalls, <String>['audio-en']);
    expect(surface.playerState.value.selectedAudioTrackId, 'audio-en');
    expect(surface.playerState.value.selectedAudioTrackLabel, 'English');
    expect(surface.playerState.value.isPaused, isFalse);
    expect(
      await audioPreferences.getPreferredLanguage(
        profileId: 'profile-1',
        tmdbId: 385687,
        mediaType: MediaType.movie,
      ),
      'en',
    );
  });

  testWidgets('PlayerScreen keeps remembered language when episode lacks it',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    final audioPreferences = _MemoryAudioLanguagePreferenceStore();
    await audioPreferences.setPreferredLanguage(
      profileId: 'profile-1',
      tmdbId: 44242,
      mediaType: MediaType.tv,
      languageCode: 'es',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(),
          mediaCatalogService: null,
          audioLanguagePreferenceStore: audioPreferences,
          playbackSettings: const ProfilePlaybackSettings(
            languageCode: 'en',
            preferredAudioLanguageCode: 'en',
          ),
          profileId: 'profile-1',
          tmdbId: 44242,
          mediaType: MediaType.tv,
          seasonNumber: 2,
          episodeNumber: 7,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(surface.loadedPreferredAudioLanguages, <String>['es']);
    expect(
      await audioPreferences.getPreferredLanguage(
        profileId: 'profile-1',
        tmdbId: 44242,
        mediaType: MediaType.tv,
      ),
      'es',
    );
  });

  testWidgets('PlayerScreen can adjust native audio sync without seeking',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    tester.widget<TvIconButton>(_iconButton('Settings')).onPressed!.call();
    await tester.pumpAndSettle();
    await tester.tap(_actionButton('Audio sync: +0ms'));
    await tester.pumpAndSettle();

    expect(find.text('Audio sync'), findsOneWidget);
    await tester.tap(_actionButton('Audio later +100ms'));
    await tester.pump();
    expect(surface.audioDelayCalls, <Duration>[
      const Duration(milliseconds: 100),
    ]);
    expect(
      surface.playerState.value.audioDelay,
      const Duration(milliseconds: 100),
    );
    expect(surface.seekToCalls, isEmpty);

    await tester.tap(_actionButton('Audio earlier -100ms'));
    await tester.pump();
    expect(surface.audioDelayCalls.last, Duration.zero);
  });

  testWidgets('PlayerScreen shows failure-specific subtitle toast',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
          ),
          captionService: _StaticCaptionService(
            const CaptionResolution(
              failureCode: CaptionFailureCode.missingApiKey,
            ),
          ),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    tester.widget<TvIconButton>(_iconButton('Subtitles')).onPressed!.call();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.textContaining('subtitle API key is missing'), findsOneWidget);
  });

  testWidgets(
      'PlayerScreen subtitle helpers adjust in correct direction and persist immediately',
      (tester) async {
    final surface = _FakePlaybackSurfaceController();
    final captionService = _OffsetAwareCaptionService(
      resolution: CaptionResolution(
        tracks: <CaptionTrack>[
          CaptionTrack(
            id: 'manual-en',
            label: 'Handmade English',
            languageCode: 'en',
            kind: CaptionTrackKind.manual,
            format: CaptionTrackFormat.vtt,
            url: Uri.parse('https://captions.example.com/manual.vtt'),
            isDefault: true,
          ),
        ],
        selectedTrackId: 'manual-en',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidsrc'],
            disabledProviders: const <String>{
              'vidlink',
              'vidsrc_embed',
              'videasy',
              '111movies',
              'vidzee',
              '2embed',
              'mapple',
              'primesrc',
              'multiembed',
              'autoembed',
              'embedsu',
              'vsembed',
              'vsrcsu',
              'vidsrcme',
              'hdrezka',
            },
          ),
          captionService: captionService,
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.tv,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    tester.widget<TvIconButton>(_iconButton('Subtitles')).onPressed!.call();
    await tester.pumpAndSettle();

    await tester.tap(_actionButton('Subtitles ahead'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(
      surface.subtitleDelayCalls,
      contains(const Duration(milliseconds: 500)),
    );
    expect(
      captionService.readStoredOffset(
        tmdbId: 385687,
        mediaType: MediaType.tv,
        seasonNumber: 1,
        episodeNumber: 1,
        providerKey: 'vidsrc',
      ),
      500,
    );

    await tester.tap(_actionButton('Subtitles behind'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(
      surface.subtitleDelayCalls,
      contains(Duration.zero),
    );
    expect(
      captionService.readStoredOffset(
        tmdbId: 385687,
        mediaType: MediaType.tv,
        seasonNumber: 1,
        episodeNumber: 1,
        providerKey: 'vidsrc',
      ),
      0,
    );
  });

  testWidgets('PlayerScreen ignores a stalled caption service', (tester) async {
    final surface = _FakePlaybackSurfaceController();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          playbackProvider: _buildPlaybackProvider(
            providerPriority: const <String>['vidlink'],
            disabledProviders: _vidlinkOnlyDisabledProviders,
          ),
          captionService: _NeverCaptionService(),
          mediaCatalogService: null,
          profileId: 'profile-1',
          tmdbId: 385687,
          mediaType: MediaType.movie,
          seasonNumber: 1,
          episodeNumber: 1,
          languageCode: 'en',
          onBack: () {},
          playbackSurfaceFactory: () => surface,
          scrubThumbnailUrlResolver: (episodeId, timestampMs) async =>
              _scrubThumbnailUrl(episodeId, timestampMs),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 8, milliseconds: 100));
    await tester.pumpAndSettle();

    expect(surface.loadedUris, <Uri>[
      Uri.parse('https://streams.example.com/vidlink/movie/385687.m3u8'),
    ]);
    expect(
      find.text(
          'Fake playback: https://streams.example.com/vidlink/movie/385687.m3u8'),
      findsOneWidget,
    );
  });
}

EmbedPlaybackProvider _buildPlaybackProvider({
  ProviderPreferenceStore? preferenceStore,
  ProfileSettingsStore? profileSettingsStore,
  SourceResolverService? sourceResolverService,
  EmbedProbe? probe,
  List<String> providerPriority = const <String>['vidlink'],
  Set<String> disabledProviders = const <String>{},
  bool allowEmbedFallback = true,
  DateTime Function()? clock,
}) {
  final catalog = const ProviderCatalog();
  // Widget tests declare the exact scripted providers they exercise. Keep
  // newly added catalogue providers from silently changing an unrelated
  // player-state test's fixture when production provider ordering evolves.
  final isolatedDisabledProviders = catalog
      .orderedProviders(ProviderConfig.defaults())
      .map((provider) => provider.key)
      .where((key) => !providerPriority.contains(key))
      .toSet();
  return EmbedPlaybackProvider(
    providerCatalog: catalog,
    preferenceStore: preferenceStore ?? _MemoryPreferenceStore(),
    profileSettingsStore: profileSettingsStore ?? const _StaticSettingsStore(),
    providerConfig: ProviderConfig(
      providerPriority: providerPriority,
      providerTimeoutSeconds: 8,
      disabledProviders: <String>{
        ...isolatedDisabledProviders,
        ...disabledProviders,
      },
    ),
    probe: probe ?? _UnusedProbe(),
    sourceResolverService:
        sourceResolverService ?? _ScriptedSourceResolverService(),
    allowEmbedFallback: allowEmbedFallback,
    clock: clock,
  );
}

class _FakePlaybackSurfaceController
    implements PlaybackSurfaceController, PlaybackFrameExtractor {
  _FakePlaybackSurfaceController({
    this.stallEmbedPlayback = false,
    this.stalledEmbedReportsPlaying = false,
    this.startPausedOnLoad = false,
    this.directLoadsWithoutFrame = 0,
    this.directLoadsWithoutFrameReportMetadata = false,
    this.directLoadsWithoutFrameHasRenderedFrame = false,
    this.directLoadsWithoutFramePosition = Duration.zero,
    this.directLoadsWithoutFrameAreBuffering = false,
    this.directLoadsWithBlackFrameHealth = 0,
    this.totalDuration = const Duration(minutes: 10),
    this.initialPosition = Duration.zero,
    this.frameExtractionDelay = Duration.zero,
    this.returnNullFrameExtractions = false,
    this.seekDelay = Duration.zero,
    this.seekLoadedDelay = Duration.zero,
    this.seekNeverClearsBuffering = false,
    this.ignoredSeekAttempts = 0,
    this.pauseOnCaptionSelect = false,
    this.initializationHangs = 0,
    this.snapBackSeekAttempts = 0,
  });

  final ValueNotifier<String?> _currentUri = ValueNotifier<String?>(null);
  final ValueNotifier<PlaybackPresentation> _playerState =
      ValueNotifier<PlaybackPresentation>(
    const PlaybackPresentation(
      bridgeAvailable: true,
      totalDuration: Duration(minutes: 10),
      videoWidth: 1920,
      videoHeight: 1080,
      hasRenderedFrame: true,
    ),
  );
  final ValueNotifier<List<String>> _subtitleLines =
      ValueNotifier<List<String>>(const <String>[]);
  final StreamController<PlaybackSurfaceEvent> _events =
      StreamController<PlaybackSurfaceEvent>.broadcast();
  final List<Uri> loadedUris = <Uri>[];
  final List<PlaybackSourceKind> loadedSourceKinds = <PlaybackSourceKind>[];
  final List<PlaybackRendererProfile> loadedRendererProfiles =
      <PlaybackRendererProfile>[];
  final List<Map<String, String>> loadedHeaders = <Map<String, String>>[];
  final List<String> loadedPreferredAudioLanguages = <String>[];
  final List<Duration> seekToCalls = <Duration>[];
  final bool stallEmbedPlayback;
  final bool stalledEmbedReportsPlaying;
  final bool startPausedOnLoad;
  final int directLoadsWithoutFrame;
  final bool directLoadsWithoutFrameReportMetadata;
  final bool directLoadsWithoutFrameHasRenderedFrame;
  final Duration directLoadsWithoutFramePosition;
  final bool directLoadsWithoutFrameAreBuffering;
  final int directLoadsWithBlackFrameHealth;
  final Duration totalDuration;
  final Duration initialPosition;
  final Duration frameExtractionDelay;
  final bool returnNullFrameExtractions;
  final Duration seekDelay;
  final Duration seekLoadedDelay;
  final bool seekNeverClearsBuffering;
  final int ignoredSeekAttempts;
  final bool pauseOnCaptionSelect;
  final int initializationHangs;
  final int snapBackSeekAttempts;
  PlaybackSourceKind? _activeSourceKind;
  bool _stalledEmbedActive = false;
  late int _remainingDirectLoadsWithoutFrame = directLoadsWithoutFrame;
  late int _remainingDirectLoadsWithBlackFrameHealth =
      directLoadsWithBlackFrameHealth;
  late int _remainingIgnoredSeekAttempts = ignoredSeekAttempts;
  late int _remainingInitializationHangs = initializationHangs;
  late int _remainingSnapBackSeekAttempts = snapBackSeekAttempts;
  late int _remainingSeekNeverClearsBuffering =
      seekNeverClearsBuffering ? 1 : 0;
  int playCalls = 0;
  int pauseCalls = 0;
  int autoplayAttempts = 0;
  int requestPlayerStateCalls = 0;
  PlaybackPresentation? _pendingStateOnRequest;
  int togglePlayPauseCalls = 0;
  int quietStopCalls = 0;
  int disposeCalls = 0;
  final List<String?> selectedCaptionTrackCalls = <String?>[];
  final List<String> selectedAudioTrackCalls = <String>[];
  final List<Duration> audioDelayCalls = <Duration>[];
  final List<Duration> subtitleDelayCalls = <Duration>[];
  bool initialized = false;
  final List<Duration> extractedFramePositions = <Duration>[];
  final List<Duration> startedFrameExtractions = <Duration>[];
  int _activeFrameExtractions = 0;
  int maxConcurrentFrameExtractions = 0;

  @override
  Stream<PlaybackSurfaceEvent> get events => _events.stream;

  @override
  ValueListenable<PlaybackPresentation> get playerState => _playerState;

  @override
  ValueListenable<List<String>> get subtitleLines => _subtitleLines;

  @override
  Future<void> initialize() async {
    if (_remainingInitializationHangs > 0) {
      _remainingInitializationHangs -= 1;
      await Completer<void>().future;
      return;
    }
    initialized = true;
  }

  @override
  Future<void> load(PlaybackLoadRequest request) async {
    loadedUris.add(request.uri);
    loadedSourceKinds.add(request.sourceKind);
    loadedRendererProfiles.add(request.rendererProfile);
    loadedHeaders.add(Map<String, String>.from(request.httpHeaders));
    loadedPreferredAudioLanguages.add(request.preferredAudioLanguage);
    _activeSourceKind = request.sourceKind;
    _currentUri.value = request.uri.toString();
    _playerState.value = _playerState.value.copyWith(isCompleted: false);
    if (stallEmbedPlayback && request.sourceKind == PlaybackSourceKind.embed) {
      _stalledEmbedActive = true;
      _playerState.value = _playerState.value.copyWith(
        bridgeAvailable: stalledEmbedReportsPlaying,
        isPaused: !stalledEmbedReportsPlaying,
        totalDuration: Duration.zero,
        currentPosition: Duration.zero,
        videoWidth: 0,
        videoHeight: 0,
        hasRenderedFrame: false,
        renderHealthChecked: false,
        hasVerifiedVideoFrame: true,
        captionTracks: request.captionTracks,
        selectedCaptionTrackId: request.selectedCaptionTrackId,
        selectedCaptionLabel: _selectedCaptionLabel(
          request.captionTracks,
          request.selectedCaptionTrackId,
        ),
        captionsAvailable: request.captionTracks.isNotEmpty,
        captionsEnabled: request.selectedCaptionTrackId != null,
      );
      return;
    }
    if (_remainingDirectLoadsWithoutFrame > 0 &&
        request.sourceKind != PlaybackSourceKind.embed) {
      _remainingDirectLoadsWithoutFrame -= 1;
      _stalledEmbedActive = false;
      _playerState.value = _playerState.value.copyWith(
        bridgeAvailable: true,
        isPaused: startPausedOnLoad,
        isBuffering: directLoadsWithoutFrameAreBuffering,
        totalDuration: totalDuration,
        currentPosition: directLoadsWithoutFramePosition,
        videoWidth: directLoadsWithoutFrameReportMetadata ? 1920 : 0,
        videoHeight: directLoadsWithoutFrameReportMetadata ? 1080 : 0,
        hasRenderedFrame: directLoadsWithoutFrameHasRenderedFrame,
        renderHealthChecked: false,
        hasVerifiedVideoFrame: true,
        captionTracks: request.captionTracks,
        selectedCaptionTrackId: request.selectedCaptionTrackId,
        selectedCaptionLabel: _selectedCaptionLabel(
          request.captionTracks,
          request.selectedCaptionTrackId,
        ),
        captionsAvailable: request.captionTracks.isNotEmpty,
        captionsEnabled: request.selectedCaptionTrackId != null,
      );
      return;
    }
    if (_remainingDirectLoadsWithBlackFrameHealth > 0 &&
        request.sourceKind != PlaybackSourceKind.embed) {
      _remainingDirectLoadsWithBlackFrameHealth -= 1;
      _stalledEmbedActive = false;
      _playerState.value = _playerState.value.copyWith(
        bridgeAvailable: true,
        isPaused: startPausedOnLoad,
        isBuffering: false,
        totalDuration: totalDuration,
        currentPosition: const Duration(seconds: 3),
        videoWidth: 1920,
        videoHeight: 1080,
        hasRenderedFrame: true,
        renderHealthChecked: true,
        hasVerifiedVideoFrame: false,
        captionTracks: request.captionTracks,
        selectedCaptionTrackId: request.selectedCaptionTrackId,
        selectedCaptionLabel: _selectedCaptionLabel(
          request.captionTracks,
          request.selectedCaptionTrackId,
        ),
        captionsAvailable: request.captionTracks.isNotEmpty,
        captionsEnabled: request.selectedCaptionTrackId != null,
      );
      return;
    }
    _stalledEmbedActive = false;
    _playerState.value = _playerState.value.copyWith(
      bridgeAvailable: true,
      isPaused: startPausedOnLoad,
      totalDuration: totalDuration,
      currentPosition: initialPosition,
      videoWidth: 1920,
      videoHeight: 1080,
      hasRenderedFrame: true,
      renderHealthChecked: true,
      hasVerifiedVideoFrame: true,
      captionTracks: request.captionTracks,
      selectedCaptionTrackId: request.selectedCaptionTrackId,
      selectedCaptionLabel: _selectedCaptionLabel(
        request.captionTracks,
        request.selectedCaptionTrackId,
      ),
      captionsAvailable: request.captionTracks.isNotEmpty,
      captionsEnabled: request.selectedCaptionTrackId != null,
    );
  }

  @override
  Future<void> requestPlayerState() async {
    requestPlayerStateCalls += 1;
    final pendingState = _pendingStateOnRequest;
    if (pendingState != null) {
      _pendingStateOnRequest = null;
      _playerState.value = pendingState;
    }
  }

  @override
  Future<void> play() async {
    playCalls += 1;
    if (_stalledEmbedActive && _activeSourceKind == PlaybackSourceKind.embed) {
      return;
    }
    _playerState.value = _playerState.value.copyWith(isPaused: false);
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    _playerState.value = _playerState.value.copyWith(isPaused: true);
  }

  @override
  Future<void> attemptAutoplay() async {
    autoplayAttempts += 1;
    await play();
  }

  @override
  Future<void> togglePlayPause() async {
    togglePlayPauseCalls += 1;
    _playerState.value =
        _playerState.value.copyWith(isPaused: !_playerState.value.isPaused);
  }

  @override
  Future<void> seekBy(Duration offset) async {
    final next = _playerState.value.currentPosition + offset;
    _playerState.value = _playerState.value.copyWith(
      currentPosition: next.isNegative ? Duration.zero : next,
    );
  }

  @override
  Future<void> seekTo(Duration position) async {
    seekToCalls.add(position);
    final previousPosition = _playerState.value.currentPosition;
    final shouldSnapBack = _remainingSnapBackSeekAttempts > 0;
    if (shouldSnapBack) {
      _remainingSnapBackSeekAttempts -= 1;
    }
    _playerState.value = _playerState.value.copyWith(isBuffering: true);
    if (_remainingIgnoredSeekAttempts > 0) {
      _remainingIgnoredSeekAttempts -= 1;
      _playerState.value = _playerState.value.copyWith(isBuffering: false);
      return;
    }
    if (seekDelay > Duration.zero) {
      await Future<void>.delayed(seekDelay);
    }
    _playerState.value = _playerState.value.copyWith(
      currentPosition: position,
    );
    if (_remainingSeekNeverClearsBuffering > 0) {
      _remainingSeekNeverClearsBuffering -= 1;
      return;
    }
    if (seekLoadedDelay > Duration.zero) {
      unawaited(() async {
        await Future<void>.delayed(seekLoadedDelay);
        _playerState.value = _playerState.value.copyWith(isBuffering: false);
      }());
      return;
    }
    _playerState.value = _playerState.value.copyWith(isBuffering: false);
    if (shouldSnapBack) {
      Timer(const Duration(seconds: 1), () {
        _playerState.value = _playerState.value.copyWith(
          currentPosition: previousPosition,
        );
      });
    }
  }

  @override
  Future<void> toggleMute() async {
    _playerState.value =
        _playerState.value.copyWith(isMuted: !_playerState.value.isMuted);
  }

  @override
  Future<void> cyclePlaybackRate() async {
    _playerState.value = _playerState.value.copyWith(playbackRate: 1.25);
  }

  @override
  Future<void> stepPlaybackRate(int direction) async {
    _playerState.value = _playerState.value.copyWith(
      playbackRate: direction < 0 ? 0.75 : 1.25,
    );
  }

  @override
  Future<void> selectAudioTrack(String trackId) async {
    selectedAudioTrackCalls.add(trackId);
    final tracks = _playerState.value.audioTracks;
    final selected = tracks.firstWhere((track) => track.id == trackId);
    _playerState.value = _playerState.value.copyWith(
      selectedAudioTrackId: selected.id,
      selectedAudioTrackLabel: selected.label,
    );
  }

  @override
  Future<void> toggleCaptions() async {
    _playerState.value = _playerState.value.copyWith(
      captionsAvailable: true,
      captionsEnabled: !_playerState.value.captionsEnabled,
    );
  }

  @override
  Future<void> selectCaptionTrack(String? trackId) async {
    selectedCaptionTrackCalls.add(trackId);
    _playerState.value = _playerState.value.copyWith(
      captionsAvailable: true,
      captionsEnabled: trackId != null,
      selectedCaptionTrackId: trackId,
      selectedCaptionLabel: trackId == null ? 'Off' : 'Selected',
      isPaused: pauseOnCaptionSelect ? true : _playerState.value.isPaused,
    );
  }

  @override
  Future<void> setCaptionTracks(
    List<CaptionTrack> tracks, {
    String? selectedTrackId,
  }) async {
    _playerState.value = _playerState.value.copyWith(
      captionTracks: tracks,
      captionsAvailable: tracks.isNotEmpty,
      captionsEnabled: selectedTrackId != null,
      selectedCaptionTrackId: selectedTrackId,
      selectedCaptionLabel: selectedTrackId == null ? 'Off' : 'Selected',
    );
  }

  @override
  Future<void> setAudioDelay(Duration offset) async {
    audioDelayCalls.add(offset);
    _playerState.value = _playerState.value.copyWith(audioDelay: offset);
  }

  @override
  Future<void> setSubtitleDelay(Duration offset) async {
    subtitleDelayCalls.add(offset);
  }

  @override
  Future<void> cycleQuality() async {
    _playerState.value = _playerState.value.copyWith(
      qualityOptions: const <String>['Auto', '720p'],
      selectedQualityLabel: '720p',
    );
  }

  @override
  Future<void> adjustZoom(double delta) async {
    _playerState.value = _playerState.value.copyWith(
      zoomScale:
          (_playerState.value.zoomScale + delta).clamp(0.5, 3.0).toDouble(),
    );
  }

  @override
  Future<void> quietStop() async {
    quietStopCalls += 1;
    _playerState.value = _playerState.value.copyWith(
      isPaused: true,
      isBuffering: false,
    );
    _subtitleLines.value = const <String>[];
  }

  @override
  Future<Uint8List?> extractFrame(Duration position) async {
    startedFrameExtractions.add(position);
    extractedFramePositions.add(position);
    _activeFrameExtractions += 1;
    if (_activeFrameExtractions > maxConcurrentFrameExtractions) {
      maxConcurrentFrameExtractions = _activeFrameExtractions;
    }
    if (frameExtractionDelay > Duration.zero) {
      await Future<void>.delayed(frameExtractionDelay);
    }
    _activeFrameExtractions -= 1;
    if (returnNullFrameExtractions) {
      return null;
    }
    return _transparentPng;
  }

  void setSubtitleLines(List<String> lines) {
    _subtitleLines.value = List<String>.unmodifiable(lines);
  }

  void updatePlayerState(
    PlaybackPresentation Function(PlaybackPresentation presentation) update,
  ) {
    _playerState.value = update(_playerState.value);
  }

  void queuePlayerStateOnNextRequest(
    PlaybackPresentation Function(PlaybackPresentation presentation) update,
  ) {
    _pendingStateOnRequest = update(_playerState.value);
  }

  void stallNextDirectLoad() {
    _remainingDirectLoadsWithoutFrame += 1;
  }

  @override
  Widget buildView() {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: ValueListenableBuilder<String?>(
          valueListenable: _currentUri,
          builder: (context, value, child) {
            return Text(
              'Fake playback: ${value ?? 'none'}',
              style: const TextStyle(color: Colors.white),
            );
          },
        ),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    _events.close();
    _currentUri.dispose();
    _playerState.dispose();
    _subtitleLines.dispose();
  }

  void emitRejectedSource(String reason) {
    _events.add(PlaybackSurfaceSourceRejected(reason));
  }

  void emitBlockedNavigation(
    Uri uri, {
    bool keepCurrentPlayback = false,
  }) {
    _events.add(
      PlaybackSurfaceBlockedNavigation(
        uri,
        keepCurrentPlayback: keepCurrentPlayback,
      ),
    );
  }

  void emitDirectSourceDetected({
    required Uri uri,
    required PlaybackSourceKind sourceKind,
    Map<String, String> httpHeaders = const <String, String>{},
    Uri? pageUri,
  }) {
    _events.add(
      PlaybackSurfaceDirectSourceDetected(
        uri: uri,
        sourceKind: sourceKind,
        httpHeaders: httpHeaders,
        pageUri: pageUri,
      ),
    );
  }

  void resumeStalledEmbedPlayback() {
    _stalledEmbedActive = false;
    _playerState.value = _playerState.value.copyWith(
      bridgeAvailable: true,
      isPaused: false,
      currentPosition: const Duration(seconds: 1),
      totalDuration: totalDuration,
    );
  }

  void markFrameRendered() {
    _playerState.value = _playerState.value.copyWith(
      isBuffering: false,
      videoWidth: 1920,
      videoHeight: 1080,
      hasRenderedFrame: true,
    );
  }

  String _selectedCaptionLabel(
    List<CaptionTrack> tracks,
    String? selectedCaptionTrackId,
  ) {
    for (final track in tracks) {
      if (track.id == selectedCaptionTrackId) {
        return track.label;
      }
    }
    return 'Off';
  }
}

class _MemoryAudioLanguagePreferenceStore
    implements AudioLanguagePreferenceStore {
  final Map<String, String> _values = <String, String>{};

  String _key(String profileId, int tmdbId, MediaType mediaType) =>
      '$profileId:${mediaType.name}:$tmdbId';

  @override
  Future<String?> getPreferredLanguage({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
  }) async =>
      _values[_key(profileId, tmdbId, mediaType)];

  @override
  Future<void> setPreferredLanguage({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) async {
    _values[_key(profileId, tmdbId, mediaType)] = languageCode;
  }

  @override
  Future<void> clearPreferredLanguage({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
  }) async {
    _values.remove(_key(profileId, tmdbId, mediaType));
  }

  @override
  Future<void> clearAllForProfile(String profileId) async {
    _values.removeWhere((key, value) => key.startsWith('$profileId:'));
  }
}

class _UnusedProbe implements EmbedProbe {
  @override
  Future<bool> canLoad(Uri uri, Duration timeout) async => true;
}

class _FailingProbe implements EmbedProbe {
  @override
  Future<bool> canLoad(Uri uri, Duration timeout) async => false;
}

class _NeverCaptionService implements CaptionService {
  @override
  Future<CaptionResolution> resolveCaptions({
    required int? tmdbId,
    required MediaType mediaType,
    required String languageCode,
    int? seasonNumber,
    int? episodeNumber,
    String? imdbId,
    String? title,
  }) {
    return Completer<CaptionResolution>().future;
  }
}

class _ScriptedSourceResolverService implements SourceResolverService {
  const _ScriptedSourceResolverService({
    this.fallbackUris = const <Uri>[],
    this.laterEpisodeResolutionDelay = Duration.zero,
  });

  final List<Uri> fallbackUris;
  final Duration laterEpisodeResolutionDelay;

  @override
  Future<PlaybackTarget?> resolveTitle({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<PlaybackTarget?> resolveNextSource({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    required int currentProviderIndex,
    int? seasonNumber,
    int? episodeNumber,
    bool probeCandidates = true,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<PlaybackTarget?> resolveSpecificSource({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    required int providerIndex,
    int? seasonNumber,
    int? episodeNumber,
    bool probeCandidate = false,
  }) async {
    if (mediaType == MediaType.tv &&
        (episodeNumber ?? 0) > 1 &&
        laterEpisodeResolutionDelay > Duration.zero) {
      await Future<void>.delayed(laterEpisodeResolutionDelay);
    }
    final provider = const ProviderCatalog().defaultProviders.firstWhere(
          (candidate) => candidate.canonicalIndex == providerIndex,
        );
    final suffix = mediaType == MediaType.movie
        ? 'movie/$tmdbId'
        : 'tv/$tmdbId/$seasonNumber/$episodeNumber';
    final uri =
        Uri.parse('https://streams.example.com/${provider.key}/$suffix.m3u8');
    return PlaybackTarget(
      uri: uri,
      providerKey: provider.key,
      providerLabel: provider.label,
      providerIndex: providerIndex,
      sourceKind: PlaybackSourceKind.hls,
      httpHeaders: <String, String>{
        'Referer': 'https://player.example.com/${provider.key}',
      },
      pageUri: Uri.parse('https://player.example.com/${provider.key}'),
      fallbackUris: fallbackUris,
    );
  }

  @override
  Future<void> reportSourceFailure({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
    required SourceFailureKind kind,
    int? seasonNumber,
    int? episodeNumber,
  }) async {}

  @override
  Future<void> reportSourceSuccess({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
    int? seasonNumber,
    int? episodeNumber,
  }) async {}

  @override
  Future<Duration?> estimateNextSourceRetryDelay({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    return null;
  }
}

const Set<String> _vidlinkOnlyDisabledProviders = <String>{
  'vidsrc_embed',
  'videasy',
  '111movies',
  'vidzee',
  'vidsrc',
  '2embed',
  'mapple',
  'primesrc',
  'multiembed',
  'autoembed',
  'embedsu',
  'vsembed',
  'vsrcsu',
  'vidsrcme',
  'hdrezka',
};

// ignore: unused_element
class _UnavailableSourceResolverService implements SourceResolverService {
  const _UnavailableSourceResolverService();

  Never _throw() {
    throw const SourceResolverUnavailableException(
      'The source resolver service is unreachable.',
    );
  }

  @override
  Future<PlaybackTarget?> resolveTitle({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    _throw();
  }

  @override
  Future<PlaybackTarget?> resolveNextSource({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    required int currentProviderIndex,
    int? seasonNumber,
    int? episodeNumber,
    bool probeCandidates = true,
  }) async {
    _throw();
  }

  @override
  Future<PlaybackTarget?> resolveSpecificSource({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    required int providerIndex,
    int? seasonNumber,
    int? episodeNumber,
    bool probeCandidate = false,
  }) async {
    _throw();
  }

  @override
  Future<void> reportSourceFailure({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
    required SourceFailureKind kind,
    int? seasonNumber,
    int? episodeNumber,
  }) async {}

  @override
  Future<void> reportSourceSuccess({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
    int? seasonNumber,
    int? episodeNumber,
  }) async {}

  @override
  Future<Duration?> estimateNextSourceRetryDelay({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    _throw();
  }
}

class _StaticCaptionService implements CaptionService {
  const _StaticCaptionService(this.resolution);

  final CaptionResolution resolution;

  @override
  Future<CaptionResolution> resolveCaptions({
    required int? tmdbId,
    required MediaType mediaType,
    required String languageCode,
    int? seasonNumber,
    int? episodeNumber,
    String? imdbId,
    String? title,
  }) async {
    return resolution;
  }
}

class _OffsetAwareCaptionService
    implements CaptionService, SubtitleOffsetStore {
  _OffsetAwareCaptionService({
    required this.resolution,
  });

  final CaptionResolution resolution;
  final Map<String, int> _offsetByKey = <String, int>{};

  @override
  Future<CaptionResolution> resolveCaptions({
    required int? tmdbId,
    required MediaType mediaType,
    required String languageCode,
    int? seasonNumber,
    int? episodeNumber,
    String? imdbId,
    String? title,
  }) async {
    return resolution;
  }

  @override
  Future<int> readOffsetMs({
    required int tmdbId,
    required MediaType mediaType,
    required int? seasonNumber,
    required int? episodeNumber,
    String? providerKey,
    bool allowProviderScopedFallback = false,
  }) async {
    return _offsetByKey[_offsetKey(
          tmdbId: tmdbId,
          mediaType: mediaType,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
          providerKey: providerKey,
        )] ??
        0;
  }

  @override
  Future<void> writeOffsetMs({
    required int tmdbId,
    required MediaType mediaType,
    required int? seasonNumber,
    required int? episodeNumber,
    required int offsetMs,
    String? providerKey,
  }) async {
    _offsetByKey[_offsetKey(
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      providerKey: providerKey,
    )] = offsetMs;
  }

  int readStoredOffset({
    required int tmdbId,
    required MediaType mediaType,
    required int? seasonNumber,
    required int? episodeNumber,
    String? providerKey,
  }) {
    return _offsetByKey[_offsetKey(
          tmdbId: tmdbId,
          mediaType: mediaType,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
          providerKey: providerKey,
        )] ??
        0;
  }

  String _offsetKey({
    required int tmdbId,
    required MediaType mediaType,
    required int? seasonNumber,
    required int? episodeNumber,
    String? providerKey,
  }) {
    final providerSegment = (providerKey ?? '').trim().toLowerCase().isEmpty
        ? 'default'
        : providerKey!.trim().toLowerCase();
    return '${mediaType.name}:$tmdbId:$providerSegment:${seasonNumber ?? 0}:${episodeNumber ?? 0}';
  }
}

class _MemoryPreferenceStore implements ProviderPreferenceStore {
  final Map<String, int> _values = <String, int>{};

  @override
  Future<int?> getLastGoodProviderIndex({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
  }) async {
    return _values['$profileId:$tmdbId:${mediaType.name}'];
  }

  @override
  Future<void> saveLastGoodProviderIndex({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
  }) async {
    _values['$profileId:$tmdbId:${mediaType.name}'] = providerIndex;
  }

  int? readStoredValue({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
  }) {
    return _values['$profileId:$tmdbId:${mediaType.name}'];
  }
}

class _StaticSettingsStore implements ProfileSettingsStore {
  const _StaticSettingsStore();

  @override
  Future<ProfilePlaybackSettings> loadPlaybackSettings(String profileId) async {
    return const ProfilePlaybackSettings(languageCode: 'en');
  }

  @override
  Future<void> savePlaybackSettings(
    String profileId,
    ProfilePlaybackSettings settings,
  ) async {}
}

class _MemoryProfileSettingsStore implements ProfileSettingsStore {
  _MemoryProfileSettingsStore({
    ProfilePlaybackSettings? initialSettings,
  }) : _settings = initialSettings ??
            const ProfilePlaybackSettings(languageCode: 'en');

  ProfilePlaybackSettings _settings;
  final List<ProfilePlaybackSettings> saveHistory = <ProfilePlaybackSettings>[];

  @override
  Future<ProfilePlaybackSettings> loadPlaybackSettings(String profileId) async {
    return _settings;
  }

  @override
  Future<void> savePlaybackSettings(
    String profileId,
    ProfilePlaybackSettings settings,
  ) async {
    _settings = settings;
    saveHistory.add(settings);
  }
}

class _NoopJsonCacheStore implements JsonCacheStore {
  @override
  Future<CachedJsonEntry?> read({
    required String key,
  }) async {
    return null;
  }

  @override
  Future<String?> readFresh({
    required String key,
    required Duration maxAge,
  }) async {
    return null;
  }

  @override
  Future<void> write({
    required String key,
    required String payload,
  }) async {}
}

// ignore: unused_element
class _FakeTmdbMediaCatalogService extends TmdbMediaCatalogService {
  _FakeTmdbMediaCatalogService({
    Map<int, List<EpisodeSummary>>? episodesBySeason,
  })  : episodesBySeason = episodesBySeason ??
            <int, List<EpisodeSummary>>{
              1: _seasonOneEpisodes,
            },
        super(
          tmdbClient: TmdbClient(apiKey: 'test'),
          cacheStore: _NoopJsonCacheStore(),
        );

  final Map<int, List<EpisodeSummary>> episodesBySeason;

  static const MediaSummary _summary = MediaSummary(
    tmdbId: 385687,
    mediaType: MediaType.tv,
    title: 'Demo Show',
    seasonCount: 2,
    runtimeMinutes: 42,
  );

  static const List<EpisodeSummary> _seasonOneEpisodes = <EpisodeSummary>[
    EpisodeSummary(
      seasonNumber: 1,
      episodeNumber: 1,
      title: 'Episode One',
      runtimeMinutes: 42,
    ),
    EpisodeSummary(
      seasonNumber: 1,
      episodeNumber: 2,
      title: 'Episode Two',
      runtimeMinutes: 42,
    ),
  ];

  @override
  Future<MediaSummary> fetchTitleDetails({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) async {
    return _summary;
  }

  @override
  Future<List<EpisodeSummary>> fetchSeasonEpisodes({
    required int tmdbId,
    required int seasonNumber,
    required String languageCode,
    int? fallbackRuntimeMinutes,
  }) async {
    return episodesBySeason[seasonNumber] ?? const <EpisodeSummary>[];
  }
}
