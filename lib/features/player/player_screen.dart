import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/models/caption_resolution.dart';
import '../../core/models/caption_track.dart';
import '../../core/models/episode_summary.dart';
import '../../core/models/media_summary.dart';
import '../../core/models/media_type.dart';
import '../../core/models/playback_load_request.dart';
import '../../core/models/playback_progress_entry.dart';
import '../../core/models/playback_progress_snapshot.dart';
import '../../core/models/playback_target.dart';
import '../../core/models/profile_playback_settings.dart';
import '../../core/services/caption_service.dart';
import '../../core/services/audio_language_preference_store.dart';
import '../../core/services/embed_playback_provider.dart';
import '../../core/services/hls_unwrap_proxy.dart';
import '../../core/services/media_catalog_service.dart';
import '../../core/services/playback_diagnostics.dart';
import '../../core/services/provider_catalog.dart';
import '../../core/services/runtime_pressure.dart';
import '../../core/services/source_health_store.dart';
import '../../core/services/source_resolver_service.dart';
import '../../core/services/subtitles/subdl_caption_service.dart';
import '../../core/services/tmdb_media_catalog_service.dart';
import '../../core/theme/cheriflix_theme.dart';
import '../../core/theme/tv_layout.dart';
import '../../core/utils/safe_logging.dart';
import '../../core/utils/user_facing_errors.dart';
import '../../core/widgets/tv_shortcuts.dart';
import '../../services/thumbnail_cache_manager.dart';
import '../../services/thumbnail_service.dart';
import '../episodes/episodes_browser.dart';
import '../episodes/episodes_screen.dart';
import 'widgets/player_scrub_bar.dart';

part 'player_overlays.dart';
part 'player_surfaces.dart';
part 'player_web_scripts.dart';

typedef PlaybackSurfaceFactory = PlaybackSurfaceController Function();
typedef ScrubThumbnailUrlResolver = Future<String?> Function(
  int episodeId,
  int timestampMs,
);

const double _playerZoomMinScale = 0.5;
const double _playerZoomMaxScale = 3.0;
const Duration _nativeStartupReadAhead = Duration(seconds: 3);
const Duration _nativeStartupCushion = Duration(seconds: 1);
const Duration _nativeStableReadAhead = Duration(seconds: 180);
const Duration _nativeStableRebufferCushion = Duration(seconds: 6);
@visibleForTesting
const double kCheriflixDefaultPlaybackVolume = 100;

@visibleForTesting
const double kCheriflixDefaultWebPlaybackVolume = 1.0;

@visibleForTesting
bool cheriflixShouldProbeFfmpegForPlatform(TargetPlatform platform) =>
    !kIsWeb && platform != TargetPlatform.android;

void _logPlayerDiagnostic(
  String message, {
  Object? error,
  StackTrace? stackTrace,
}) {
  cheriflixLog('player', message, error: error, stackTrace: stackTrace);
}

int _coerceAndroidWidValue(dynamic rawValue) {
  if (rawValue is num) {
    return rawValue.toInt();
  }
  return 0;
}

class PlaybackAudioTrack {
  const PlaybackAudioTrack({
    required this.id,
    required this.label,
    this.languageCode,
    this.title,
    this.providerKey,
    this.sourceUri,
    this.isOriginal,
  });

  final String id;
  final String label;
  final String? languageCode;
  final String? title;
  final String? providerKey;
  final Uri? sourceUri;
  final bool? isOriginal;
}

class PlaybackPresentation {
  const PlaybackPresentation({
    this.currentPosition = Duration.zero,
    this.totalDuration = Duration.zero,
    this.isPaused = true,
    this.isCompleted = false,
    this.isBuffering = false,
    this.bufferingPercentage = 0,
    this.isMuted = false,
    this.playbackRate = 1,
    this.audioDelay = Duration.zero,
    this.zoomScale = 1,
    this.audioTracks = const <PlaybackAudioTrack>[],
    this.selectedAudioTrackId,
    this.selectedAudioTrackLabel = 'Default',
    this.captionsAvailable = false,
    this.captionsEnabled = false,
    this.captionTracks = const <CaptionTrack>[],
    this.selectedCaptionTrackId,
    this.selectedCaptionLabel = 'Off',
    this.qualityOptions = const <String>['Auto'],
    this.selectedQualityLabel = 'Auto',
    this.bridgeAvailable = false,
    this.videoWidth = 0,
    this.videoHeight = 0,
    this.hasRenderedFrame = false,
    this.renderHealthChecked = false,
    this.hasVerifiedVideoFrame = true,
  });

  final Duration currentPosition;
  final Duration totalDuration;
  final bool isPaused;
  final bool isCompleted;
  final bool isBuffering;

  /// Native libmpv/media_kit buffering progress, not a timer estimate.
  final double bufferingPercentage;
  final bool isMuted;
  final double playbackRate;
  final Duration audioDelay;
  final double zoomScale;
  final List<PlaybackAudioTrack> audioTracks;
  final String? selectedAudioTrackId;
  final String selectedAudioTrackLabel;
  final bool captionsAvailable;
  final bool captionsEnabled;
  final List<CaptionTrack> captionTracks;
  final String? selectedCaptionTrackId;
  final String selectedCaptionLabel;
  final List<String> qualityOptions;
  final String selectedQualityLabel;
  final bool bridgeAvailable;
  final int videoWidth;
  final int videoHeight;
  final bool hasRenderedFrame;
  final bool renderHealthChecked;
  final bool hasVerifiedVideoFrame;

  bool get hasVisibleVideo {
    if (!hasRenderedFrame) {
      return false;
    }
    if (!renderHealthChecked) {
      // Keep the fast metadata/texture precheck behavior until a pixel-health
      // probe says otherwise.
      return true;
    }
    return hasVerifiedVideoFrame;
  }

  PlaybackPresentation copyWith({
    Duration? currentPosition,
    Duration? totalDuration,
    bool? isPaused,
    bool? isCompleted,
    bool? isBuffering,
    double? bufferingPercentage,
    bool? isMuted,
    double? playbackRate,
    Duration? audioDelay,
    double? zoomScale,
    List<PlaybackAudioTrack>? audioTracks,
    String? selectedAudioTrackId,
    String? selectedAudioTrackLabel,
    bool? captionsAvailable,
    bool? captionsEnabled,
    List<CaptionTrack>? captionTracks,
    String? selectedCaptionTrackId,
    String? selectedCaptionLabel,
    List<String>? qualityOptions,
    String? selectedQualityLabel,
    bool? bridgeAvailable,
    int? videoWidth,
    int? videoHeight,
    bool? hasRenderedFrame,
    bool? renderHealthChecked,
    bool? hasVerifiedVideoFrame,
  }) {
    return PlaybackPresentation(
      currentPosition: currentPosition ?? this.currentPosition,
      totalDuration: totalDuration ?? this.totalDuration,
      isPaused: isPaused ?? this.isPaused,
      isCompleted: isCompleted ?? this.isCompleted,
      isBuffering: isBuffering ?? this.isBuffering,
      bufferingPercentage: bufferingPercentage ?? this.bufferingPercentage,
      isMuted: isMuted ?? this.isMuted,
      playbackRate: playbackRate ?? this.playbackRate,
      audioDelay: audioDelay ?? this.audioDelay,
      zoomScale: zoomScale ?? this.zoomScale,
      audioTracks: audioTracks ?? this.audioTracks,
      selectedAudioTrackId: selectedAudioTrackId ?? this.selectedAudioTrackId,
      selectedAudioTrackLabel:
          selectedAudioTrackLabel ?? this.selectedAudioTrackLabel,
      captionsAvailable: captionsAvailable ?? this.captionsAvailable,
      captionsEnabled: captionsEnabled ?? this.captionsEnabled,
      captionTracks: captionTracks ?? this.captionTracks,
      selectedCaptionTrackId:
          selectedCaptionTrackId ?? this.selectedCaptionTrackId,
      selectedCaptionLabel: selectedCaptionLabel ?? this.selectedCaptionLabel,
      qualityOptions: qualityOptions ?? this.qualityOptions,
      selectedQualityLabel: selectedQualityLabel ?? this.selectedQualityLabel,
      bridgeAvailable: bridgeAvailable ?? this.bridgeAvailable,
      videoWidth: videoWidth ?? this.videoWidth,
      videoHeight: videoHeight ?? this.videoHeight,
      hasRenderedFrame: hasRenderedFrame ?? this.hasRenderedFrame,
      renderHealthChecked: renderHealthChecked ?? this.renderHealthChecked,
      hasVerifiedVideoFrame:
          hasVerifiedVideoFrame ?? this.hasVerifiedVideoFrame,
    );
  }
}

String _genericTrackLabelForIndex(int index) => 'Source ${index + 1}';

String _genericTrackLabelForId(
  List<CaptionTrack> tracks,
  String? selectedTrackId,
) {
  if (selectedTrackId == null) {
    return 'Off';
  }
  final index = tracks.indexWhere((track) => track.id == selectedTrackId);
  if (index < 0) {
    return 'Off';
  }
  return _genericTrackLabelForIndex(index);
}

enum _FrameScreenshotProbeOutcome {
  visible,
  blank,
  missing,
}

class _AndroidVideoOutputState {
  const _AndroidVideoOutputState({
    required this.textureId,
    required this.wid,
    required this.width,
    required this.height,
    required this.useSurfaceTexture,
    required this.surfaceAttachRetryCount,
    required this.frameAvailableCount,
    required this.lastFrameAvailableAtMs,
    required this.frameWatchdogReattachCount,
  });

  final int textureId;
  final int wid;
  final int width;
  final int height;
  final bool useSurfaceTexture;
  final int surfaceAttachRetryCount;
  final int frameAvailableCount;
  final int lastFrameAvailableAtMs;
  final int frameWatchdogReattachCount;

  bool get hasAttachedSurface => wid > 0;
  bool get hasFrameCallbacks => frameAvailableCount > 0;

  static _AndroidVideoOutputState? tryParse(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final map = raw.cast<Object?, Object?>();
    int parseInt(String key) {
      final value = map[key];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      if (value is String) {
        return int.tryParse(value) ?? 0;
      }
      return 0;
    }

    bool parseBool(String key) {
      final value = map[key];
      if (value is bool) {
        return value;
      }
      if (value is num) {
        return value != 0;
      }
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        return normalized == '1' ||
            normalized == 'true' ||
            normalized == 'yes' ||
            normalized == 'on';
      }
      return false;
    }

    return _AndroidVideoOutputState(
      textureId: parseInt('id'),
      wid: parseInt('wid'),
      width: parseInt('width'),
      height: parseInt('height'),
      useSurfaceTexture: parseBool('useSurfaceTexture'),
      surfaceAttachRetryCount: parseInt('surfaceAttachRetryCount'),
      frameAvailableCount: parseInt('frameAvailableCount'),
      lastFrameAvailableAtMs: parseInt('lastFrameAvailableAtMs'),
      frameWatchdogReattachCount: parseInt('frameWatchdogReattachCount'),
    );
  }
}

abstract class PlaybackSurfaceEvent {
  const PlaybackSurfaceEvent();
}

class PlaybackSurfaceBlockedNavigation extends PlaybackSurfaceEvent {
  const PlaybackSurfaceBlockedNavigation(
    this.uri, {
    this.keepCurrentPlayback = false,
  });

  final Uri uri;
  final bool keepCurrentPlayback;
}

class PlaybackSurfaceDirectSourceDetected extends PlaybackSurfaceEvent {
  const PlaybackSurfaceDirectSourceDetected({
    required this.uri,
    required this.sourceKind,
    this.httpHeaders = const <String, String>{},
    this.pageUri,
  });

  final Uri uri;
  final PlaybackSourceKind sourceKind;
  final Map<String, String> httpHeaders;
  final Uri? pageUri;
}

class PlaybackSurfaceSourceRejected extends PlaybackSurfaceEvent {
  const PlaybackSurfaceSourceRejected(this.reason);

  final String reason;
}

class PlaybackSurfacePlayerStateChanged extends PlaybackSurfaceEvent {
  const PlaybackSurfacePlayerStateChanged(this.presentation);

  final PlaybackPresentation presentation;
}

abstract class PlaybackSurfaceController {
  Stream<PlaybackSurfaceEvent> get events;
  ValueListenable<PlaybackPresentation> get playerState;
  ValueListenable<List<String>> get subtitleLines;

  Future<void> initialize();

  Future<void> load(PlaybackLoadRequest request);

  Widget buildView();

  Future<void> requestPlayerState();

  Future<void> play();

  Future<void> pause();

  Future<void> togglePlayPause();

  Future<void> attemptAutoplay();

  Future<void> seekBy(Duration offset);

  Future<void> seekTo(Duration position);

  Future<void> toggleMute();

  Future<void> cyclePlaybackRate();

  Future<void> stepPlaybackRate(int direction);

  Future<void> toggleCaptions();

  Future<void> selectAudioTrack(String trackId);

  Future<void> setAudioDelay(Duration offset);

  Future<void> selectCaptionTrack(String? trackId);

  Future<void> setCaptionTracks(
    List<CaptionTrack> tracks, {
    String? selectedTrackId,
  });

  Future<void> setSubtitleDelay(Duration offset);

  Future<void> cycleQuality();

  Future<void> adjustZoom(double delta);

  Future<void> quietStop();

  Future<void> dispose();
}

abstract interface class PlaybackFrameExtractor {
  Future<Uint8List?> extractFrame(Duration position);
}

abstract interface class PlaybackReadAheadController {
  Future<void> promoteReadAheadAfterStartup();
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.playbackProvider,
    required this.mediaCatalogService,
    this.captionService = const NoOpCaptionService(),
    this.playbackSettings = const ProfilePlaybackSettings(languageCode: 'en'),
    this.playbackProgress,
    this.audioLanguagePreferenceStore =
        const NoOpAudioLanguagePreferenceStore(),
    this.hideSpoilers = false,
    required this.profileId,
    required this.tmdbId,
    required this.mediaType,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.languageCode,
    required this.onBack,
    this.initialSummary,
    this.initialResumePosition = Duration.zero,
    this.onProgressChanged,
    this.onTraktPlaybackReported,
    this.onPlaybackSettingsChanged,
    this.getWebViewVersion,
    this.playbackSurfaceFactory,
    this.scrubThumbnailUrlResolver,
  });

  final EmbedPlaybackProvider playbackProvider;
  final CaptionService captionService;
  final MediaCatalogService? mediaCatalogService;
  final ProfilePlaybackSettings playbackSettings;
  final PlaybackProgressSnapshot? playbackProgress;
  final AudioLanguagePreferenceStore audioLanguagePreferenceStore;
  final bool hideSpoilers;
  final String profileId;
  final int tmdbId;
  final MediaType mediaType;
  final int seasonNumber;
  final int episodeNumber;
  final String languageCode;
  final VoidCallback onBack;
  final MediaSummary? initialSummary;
  final Duration initialResumePosition;
  final Future<void> Function(PlaybackProgressEntry entry)? onProgressChanged;
  final Future<void> Function(PlaybackProgressEntry entry, bool paused)?
      onTraktPlaybackReported;
  final ValueChanged<ProfilePlaybackSettings>? onPlaybackSettingsChanged;
  final Future<String?> Function()? getWebViewVersion;
  final PlaybackSurfaceFactory? playbackSurfaceFactory;
  final ScrubThumbnailUrlResolver? scrubThumbnailUrlResolver;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  static const int _subtitleOffsetLimitMs = 3600000;
  static const ValueKey<String> _surfaceInteractionGateKey =
      ValueKey<String>('player-surface-interaction-gate');
  static Duration get _embedPromotionTimeout => Platform.isAndroid
      ? const Duration(seconds: 12)
      : const Duration(seconds: 15);
  static Duration get _directFrameTimeout => Platform.isAndroid
      ? const Duration(seconds: 25)
      : const Duration(seconds: 12);
  static Duration get _playbackLoadTimeout => Platform.isAndroid
      ? const Duration(seconds: 40)
      : const Duration(seconds: 20);
  static Duration get _playbackStartupEscapeTimeout => Platform.isAndroid
      ? const Duration(seconds: 22)
      : const Duration(seconds: 26);
  static const Duration _androidDirectStartupStabilityWindow =
      Duration(milliseconds: 1500);
  // A decoder can expose dimensions and one frame at ~125 ms even when the
  // next HLS segment is unreachable. Do not call that playback success: the
  // native timeline must make meaningful forward progress first.
  static const Duration _minimumConfirmedPlaybackProgress =
      Duration(milliseconds: 750);
  static const Duration _chromeAutoHideDelay = Duration(seconds: 10);
  static const Duration _overlayDoubleBackWindow = Duration(milliseconds: 1500);
  static const Duration _chromeBackConsumedGuardDuration =
      Duration(milliseconds: 260);
  static const Duration _scrubFrameCacheStep = Duration(seconds: 5);
  static const String _directScrubStrategyVersion =
      _scrubFrameExtractionStrategyVersion;
  static const int _directScrubCacheVideoLimit = 3;
  static const Duration _directScrubCacheTtl = Duration(minutes: 30);
  static const Duration _scrubPreviewRequestTimeout = Duration(seconds: 6);
  static const Duration _scrubEpisodeProbeTimeout = Duration(milliseconds: 700);
  static const Duration _scrubEpisodeResolveTimeout = Duration(seconds: 3);
  static const Duration _scrubThumbnailUrlTimeout = Duration(seconds: 2);
  static const bool _enableHardcodedOnStreamEpisodeProbe = true;
  static const int _hardcodedOnStreamEpisodeIdProbe = 1522699;
  static const Duration _seekLoadingTolerance = Duration(milliseconds: 700);
  static const Duration _viewerSeekDebounceDelay = Duration(milliseconds: 180);
  static const Duration _viewerSeekHandoffDelay = Duration(milliseconds: 70);
  static const Duration _seekLoadingFallbackDelay = Duration(seconds: 5);
  static const Duration _postSeekRegressionTolerance = Duration(seconds: 4);
  static const Duration _postSeekRegressionGuardDuration =
      Duration(seconds: 90);
  static const Duration _playerExitStopTimeout = Duration(seconds: 2);
  static const Duration _playerSurfaceDisposeTimeout = Duration(seconds: 5);
  static const Duration _resumeSettleTolerance = Duration(seconds: 3);
  static const int _maxResumeSeekAttempts = 2;
  static const Duration _resumeNearEndThreshold = Duration(minutes: 2);
  static const Duration _resumeProgressGuardThreshold = Duration(seconds: 30);
  static const Duration _progressCheckpointInterval = Duration(seconds: 5);
  static const Duration _progressStateRefreshTimeout =
      Duration(milliseconds: 750);
  static const Duration _unexpectedPositionResetThreshold =
      Duration(seconds: 30);
  static const Duration _rapidBackwardJumpTolerance =
      Duration(milliseconds: 900);
  static const Duration _rapidBackwardJumpWindow = Duration(seconds: 15);
  static const int _rapidBackwardJumpRecoveryCount = 2;
  static const Duration _playbackStallWatchdogInterval = Duration(seconds: 4);
  static const int _playbackStoppedWatchdogTicks = 3;
  static const int _playbackBufferingWatchdogTicks = 4;
  static const int _playbackStallHardRecoveryDelayTicks = 1;
  static const Duration _longPauseStreamRefreshThreshold =
      Duration(seconds: 45);
  static const double _zoomStep = 0.05;
  static const String _scrubThumbnailDeviceInfo =
      'WrT6CpcNvD08SIQvy8DdM3pgn5mtu/ePO/9B7hncyiM5qJyeKwGUljH2YdbqMpgfpqS18yC/SQTfys0cIaCipyrKvWb0bFcrm4uh+BKXrT8EJdPJP6B0P0ftUwShb5j92sDLUd/9+UUD53w6020+T1h8FR1Ts26Q04GXD8v4fRD2bLADr+vl6Dyt/LOF+C8mKrpSUzv7V4Iv4d4aIGP8wUOeiYfEKEkeOlRm5kGM6wegSHlgSOnHQUnexqJFjQm9ekKdTnWKaPjnY5IQsZ04bse14dtLkjNiF8ib6rChQ6bT6U1m+B2BgW3pRKHvXEqSsAeHOoQ1ZOOdqjO4O83BKpck+Z9/UyJZAXZfhAEFCEu3pr9XMcaO4mUVAwNzBrQeNRE7W+9eZ0rxFcrLgx6H2b6pxSvoxkz62WaCgZVNiDWfOx6Y7+sy5st0eqSkBfANN552g4bxFV7Y607jfJZqUqfRtfhhsnoRKKIoaZx8mOGqT75dGzQ/Y4v/Tet/MsRUu2vJd6Kr+1FHmzT54AeoML0w4uPjtOF3m8PP1v6Dl2PsoEb0WxPtYm2FQ==';

  late final PlaybackSurfaceController _playbackSurface;
  late final StreamSubscription<PlaybackSurfaceEvent>
      _playbackSurfaceEventsSubscription;

  PlaybackTarget? _committedTarget;
  PlaybackTarget? _pendingTarget;
  MediaSummary? _summary;
  late int _activeSeasonNumber;
  late int _activeEpisodeNumber;
  final Map<int, List<EpisodeSummary>> _seasonEpisodesByNumber =
      <int, List<EpisodeSummary>>{};
  CaptionResolution _captionResolution = CaptionResolution.empty;
  Future<CaptionResolution>? _captionResolutionInFlight;
  int _subtitleOffsetMs = 0;
  int _audioDelayMs = 0;
  String _effectiveAudioLanguage = 'en';
  bool _preferHiSubtitles = false;
  String? _error;
  String? _statusMessage;
  bool _resolvingSource = true;
  bool _surfaceLoading = false;
  bool _surfaceReady = false;
  bool _surfaceInitialized = false;
  int _surfaceLoadToken = 0;
  int _contentGeneration = 0;
  late final ThumbnailService _directScrubThumbnailService = ThumbnailService(
    cacheManager: ThumbnailCacheManager(
      maxVideosCached: _directScrubCacheVideoLimit,
      inactivityTtl: _directScrubCacheTtl,
      memoryEntryLimit: 80,
    ),
    previewBucketMs: _scrubFrameCacheStep.inMilliseconds,
    defaultMaxPreviewDistanceMs: _scrubFrameCacheStep.inMilliseconds * 2,
  );
  final Map<int, String> _scrubFrameCache = <int, String>{};
  final Map<int, Future<String?>> _scrubFrameRequests =
      <int, Future<String?>>{};
  final Map<int, _EpisodePreviewPathData> _episodePreviewPathCache =
      <int, _EpisodePreviewPathData>{};
  final Map<int, Future<_EpisodePreviewPathData?>> _episodePreviewPathRequests =
      <int, Future<_EpisodePreviewPathData?>>{};
  final Set<int> _episodesWithoutPreviewPath = <int>{};
  final Map<String, int> _resolvedScrubEpisodeIdByContentKey = <String, int>{};
  final Map<String, Future<int?>> _resolvedScrubEpisodeIdRequestsByContentKey =
      <String, Future<int?>>{};
  final Set<String> _unresolvedScrubContentKeys = <String>{};
  final Set<String> _scrubPrefetchAttemptedContentKeys = <String>{};
  final Set<String> _scrubPrefetchInFlightContentKeys = <String>{};
  final Set<String> _scrubPrefetchCompletedContentKeys = <String>{};
  int _scrubFrameCacheGeneration = 0;
  ThumbnailDirectSession? _directScrubSession;
  String? _directScrubSessionKey;
  _HlsScrubFrameCoordinator? _hlsScrubCoordinator;
  String? _hlsScrubCoordinatorKey;
  Duration _lastReportedProgressPosition = Duration.zero;
  Duration _lastTrustedPlaybackPosition = Duration.zero;
  PlaybackPresentation? _lastPersistableProgressPresentation;
  bool _lastReportedPaused = true;
  String? _recordedSuccessfulTargetSignature;
  final Set<String> _confirmedPlayableTargetSignatures = <String>{};
  final Map<String, Duration> _confirmedStartupDurations = <String, Duration>{};
  String? _lastPromotedDirectSourceSignature;
  String? _embedPromotedDirectTargetSignature;
  Timer? _embedPromotionTimeoutTimer;
  Timer? _directFrameTimeoutTimer;
  Timer? _playbackStartupEscapeTimer;
  Timer? _playbackStallWatchdogTimer;
  Timer? _progressCheckpointTimer;
  Timer? _unexpectedStopRecoveryTimer;
  Timer? _longPauseRefreshArmTimer;
  String? _directNoFrameRecoveryTargetSignature;
  final Set<int> _autoRecoveryFailedProviderIndexes = <int>{};
  final Set<int> _loopRecoveryRetriedProviderIndexes = <int>{};
  String? _directStartupStabilitySignature;
  DateTime? _directStartupHealthySince;
  Duration? _directStartupProgressAnchor;
  bool _directStartupStable = false;
  Duration? _resumeAnchorPosition;
  bool _resumePending = false;
  bool _resumeSeekIssued = false;
  int _resumeSeekAttempts = 0;
  bool _resumeIntentInFlight = false;
  bool _switchResumeSeekInFlight = false;
  bool _pendingLoadShouldRemainPaused = false;
  bool _resumePlaybackAfterLifecyclePause = false;
  bool _intendedPlaybackPlaying = true;
  bool _playbackRecoveryInFlight = false;
  bool _unexpectedStopRecoveryInFlight = false;
  bool _longPauseRefreshInFlight = false;
  bool _viewerPauseNeedsRefresh = false;
  DateTime? _viewerPauseStartedAt;
  DateTime? _lastPlaybackRecoveryAt;
  String? _stallWatchdogTargetSignature;
  Duration? _stallWatchdogPosition;
  Duration? _lastObservedPlaybackPosition;
  DateTime? _rapidBackwardJumpWindowStartedAt;
  int _rapidBackwardJumpCount = 0;
  int _stallWatchdogTicks = 0;
  int _stallBackwardJumpCount = 0;
  int _stallSameSourceReloads = 0;
  bool _stallRecoveryInFlight = false;
  bool _sourceRecoveryInFlight = false;
  bool _appLifecycleActive = true;
  EpisodeSummary? _nextEpisodeTarget;
  bool _nextEpisodePromptVisible = false;
  bool _nextEpisodePromptWasPlaying = false;
  int _nextEpisodeCountdownSeconds = 0;
  Timer? _nextEpisodeCountdownTimer;
  Timer? _chromeHideTimer;
  Timer? _overlayDoubleBackTimer;
  Timer? _chromeBackConsumedGuardTimer;
  Timer? _viewerSeekDebounceTimer;
  Timer? _seekLoadingFallbackTimer;
  Timer? _postSeekRegressionTimer;
  Duration? _postSeekRegressionTarget;
  bool _postSeekRegressionMayRejectSource = false;
  bool _seekRecoveryInFlight = false;
  bool _chromeVisible = true;
  bool _chromeForceDismissed = false;
  bool _chromeAutoHideActive = false;
  bool _awaitingSecondOverlayBack = false;
  bool _chromeBackConsumedGuardActive = false;
  bool _scrubUiVisible = false;
  bool _exitConfirmationVisible = false;
  int _playerModalOverlayDepth = 0;
  bool _chromeFocusRequestQueued = false;
  bool _fatalPlaybackDialogVisible = false;
  bool _suppressProgressReporting = false;
  bool _playbackSurfaceTeardownStarted = false;
  int _activeSeekOperations = 0;
  Duration? _pendingSeekTarget;
  bool _pendingSeekMayRejectSource = false;
  int _manualSeekGeneration = 0;
  bool _viewerSeekCommitInFlight = false;
  bool _viewerSeekCommitQueued = false;
  bool _manualSeekRetryInFlight = false;
  DateTime? _manualSeekProtectionUntil;
  bool _initialScrubFocusQueued = false;
  bool _initialScrubFocusRequested = false;
  static const String _noSourcesErrorMessage = 'No sources found.';
  static const String _noSourcesTitle = 'No sources';
  late final FocusNode _backCaptureFocusNode =
      FocusNode(debugLabel: 'PlayerBackCapture');
  late final FocusNode _backFocusNode = FocusNode(debugLabel: 'PlayerBack');
  late final FocusNode _playPauseFocusNode =
      FocusNode(debugLabel: 'PlayerPlayPause');
  late final FocusNode _scrubFocusNode =
      FocusNode(debugLabel: 'PlayerScrubBar');
  late final FocusNode _seekBackwardFocusNode =
      FocusNode(debugLabel: 'PlayerBack10');
  late final FocusNode _seekForwardFocusNode =
      FocusNode(debugLabel: 'PlayerForward10');
  late final FocusNode _episodesFocusNode =
      FocusNode(debugLabel: 'PlayerEpisodes');
  late final FocusNode _captionsFocusNode =
      FocusNode(debugLabel: 'PlayerCaptions');
  late final FocusNode _audioLanguageFocusNode =
      FocusNode(debugLabel: 'PlayerAudioLanguage');
  late final FocusNode _settingsFocusNode =
      FocusNode(debugLabel: 'PlayerSettings');
  late final FocusNode _nextEpisodeFocusNode =
      FocusNode(debugLabel: 'PlayerNextEpisode');
  late final FocusNode _zoomOutFocusNode =
      FocusNode(debugLabel: 'PlayerZoomOut');
  late final FocusNode _zoomInFocusNode = FocusNode(debugLabel: 'PlayerZoomIn');
  late final FocusNode _fullscreenFocusNode =
      FocusNode(debugLabel: 'PlayerFullscreenPlaceholder');

  // ignore: unused_element
  PlaybackTarget? get _visibleTarget => _pendingTarget ?? _committedTarget;

  PlaybackTarget? get _currentRecoveryTarget =>
      _pendingTarget ?? _committedTarget;

  bool get _hasCommittedTarget => _committedTarget != null;

  bool get _isTvEpisodePlayer => widget.mediaType == MediaType.tv;

  List<FocusNode> get _chromeFocusNodes => <FocusNode>[
        _backFocusNode,
        _playPauseFocusNode,
        _scrubFocusNode,
        _seekBackwardFocusNode,
        _seekForwardFocusNode,
        _episodesFocusNode,
        _captionsFocusNode,
        _audioLanguageFocusNode,
        _settingsFocusNode,
        _nextEpisodeFocusNode,
        _zoomOutFocusNode,
        _zoomInFocusNode,
        _fullscreenFocusNode,
      ];

  bool _shouldKeepChromeVisible(PlaybackPresentation _) {
    return !_hasCommittedTarget ||
        _resolvingSource ||
        _surfaceLoading ||
        _pendingTarget != null ||
        _nextEpisodePromptVisible ||
        _error != null;
  }

  bool get _shouldHideChromeWhileLoading =>
      _resolvingSource || _surfaceLoading || _pendingTarget != null;

  bool _canAutoHideChrome(PlaybackPresentation presentation) {
    return !_shouldHideChromeWhileLoading &&
        !_shouldKeepChromeVisible(presentation);
  }

  bool _isChromeVisibleToUser(PlaybackPresentation presentation) {
    if (_shouldHideChromeWhileLoading) {
      return false;
    }
    final forcedVisible =
        _shouldKeepChromeVisible(presentation) && !_chromeForceDismissed;
    return forcedVisible || _chromeVisible;
  }

  void _handleChromeFocusChange() {
    if (!_chromeFocusNodes.any((node) => node.hasFocus)) {
      return;
    }
    _clearOverlayBackWindow();
    _registerChromeInteraction();
  }

  void _handleChromePointerActivity() {
    _registerChromeInteraction();
  }

  bool _handlePlayerHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return false;
    }
    if (_exitConfirmationVisible) {
      return false;
    }
    if (_isAssistantInterruptionKey(event.logicalKey)) {
      final shouldResume = _surfaceReady && _intendedPlaybackPlaying;
      _resumePlaybackAfterLifecyclePause =
          _resumePlaybackAfterLifecyclePause || shouldResume;
      _logPlayerDiagnostic(
        'Assistant/mic key observed '
        'key=${event.logicalKey.keyLabel.isEmpty ? event.logicalKey.debugName : event.logicalKey.keyLabel} '
        'surfaceReady=$_surfaceReady '
        'intendedPlaying=$_intendedPlaybackPlaying '
        'armedResume=$_resumePlaybackAfterLifecyclePause',
      );
    }
    if (_isChromeActivityKey(event.logicalKey)) {
      _registerChromeInteraction();
    }
    return false;
  }

  bool _isPlayerBackKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack ||
        key == LogicalKeyboardKey.gameButtonB;
  }

  bool _isAssistantInterruptionKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.launchAssistant ||
        key == LogicalKeyboardKey.microphoneToggle ||
        key == LogicalKeyboardKey.microphoneVolumeMute ||
        key == LogicalKeyboardKey.microphoneVolumeUp ||
        key == LogicalKeyboardKey.microphoneVolumeDown ||
        key == LogicalKeyboardKey.voiceDial;
  }

  bool _isChromeActivityKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.gameButtonStart ||
        key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause ||
        key == LogicalKeyboardKey.mediaFastForward ||
        key == LogicalKeyboardKey.mediaRewind ||
        _isAssistantInterruptionKey(key);
  }

  void _registerChromeInteraction() {
    final presentation = _playbackSurface.playerState.value;
    final canAutoHide = _canAutoHideChrome(presentation);
    final wasHidden = !_isChromeVisibleToUser(presentation);
    if ((!_chromeVisible || _chromeForceDismissed) && mounted) {
      setState(() {
        _chromeVisible = true;
        _chromeForceDismissed = false;
      });
    }
    if (_chromeVisible) {
      _clearOverlayBackWindow();
    }
    _chromeAutoHideActive = canAutoHide;
    if (canAutoHide) {
      _scheduleChromeHide(presentation);
    } else {
      _cancelChromeHide();
    }
    if (wasHidden) {
      _requestChromeInitialFocus();
    }
  }

  void _cancelChromeHide() {
    _chromeHideTimer?.cancel();
    _chromeHideTimer = null;
  }

  void _scheduleChromeHide([PlaybackPresentation? presentation]) {
    final currentPresentation =
        presentation ?? _playbackSurface.playerState.value;
    _cancelChromeHide();
    if (!_chromeVisible || !_canAutoHideChrome(currentPresentation)) {
      return;
    }
    _chromeHideTimer = Timer(_chromeAutoHideDelay, () {
      if (!mounted) {
        return;
      }
      final latestPresentation = _playbackSurface.playerState.value;
      if (_canAutoHideChrome(latestPresentation)) {
        setState(() {
          _chromeVisible = false;
          _chromeForceDismissed = false;
          _chromeAutoHideActive = false;
        });
        _requestPlayerSurfaceFocus();
      }
    });
  }

  void _syncChromeVisibility(PlaybackPresentation presentation) {
    if (!_canAutoHideChrome(presentation)) {
      _cancelChromeHide();
      _chromeAutoHideActive = false;
      if (_chromeForceDismissed) {
        return;
      }
      if (!_chromeVisible) {
        setState(() {
          _chromeVisible = true;
        });
        _requestChromeInitialFocus();
      }
      return;
    }
    if (_chromeVisible && !_chromeAutoHideActive) {
      _chromeAutoHideActive = true;
      _scheduleChromeHide(presentation);
      return;
    }
  }

  void _maybeRequestInitialChromeFocus({
    required bool showChrome,
    required PlaybackPresentation presentation,
  }) {
    if (_initialScrubFocusRequested || _initialScrubFocusQueued) {
      return;
    }
    if (!showChrome ||
        !_surfaceReady ||
        presentation.totalDuration <= Duration.zero) {
      return;
    }

    _initialScrubFocusQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialScrubFocusQueued = false;
      if (!mounted || _initialScrubFocusRequested) {
        return;
      }
      final latestPresentation = _playbackSurface.playerState.value;
      if (!_surfaceReady ||
          latestPresentation.totalDuration <= Duration.zero ||
          (_playPauseFocusNode.context == null &&
              _backFocusNode.context == null)) {
        return;
      }
      _initialScrubFocusRequested = true;
      _requestChromeInitialFocus(force: true);
    });
  }

  void _requestChromeInitialFocus({bool force = false}) {
    if (!mounted || _exitConfirmationVisible || _chromeFocusRequestQueued) {
      return;
    }
    if (!force && _chromeFocusNodes.any((node) => node.hasFocus)) {
      return;
    }
    _chromeFocusRequestQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chromeFocusRequestQueued = false;
      if (!mounted || _exitConfirmationVisible) {
        return;
      }
      final presentation = _playbackSurface.playerState.value;
      if (!_isChromeVisibleToUser(presentation)) {
        return;
      }
      if (!force && _chromeFocusNodes.any((node) => node.hasFocus)) {
        return;
      }
      final target = _playPauseFocusNode.context != null
          ? _playPauseFocusNode
          : _backFocusNode.context != null
              ? _backFocusNode
              : null;
      target?.requestFocus();
    });
  }

  void _requestPlayerSurfaceFocus() {
    if (mounted) {
      _backCaptureFocusNode.requestFocus();
    }
  }

  void _handleScrubUiVisibilityChanged(bool visible) {
    if (_scrubUiVisible == visible) {
      return;
    }
    if (visible) {
      _registerChromeInteraction();
    }
    setState(() {
      _scrubUiVisible = visible;
    });
    _syncScrubBackgroundWork(_playbackSurface.playerState.value);
  }

  void _disposeScrubCoordinators() {
    _disposeDirectScrubSession();
    _disposeHlsScrubCoordinator();
  }

  void _disposeDirectScrubSession() {
    _directScrubSession?.dispose();
    _directScrubSession = null;
    _directScrubSessionKey = null;
  }

  void _disposeHlsScrubCoordinator() {
    _hlsScrubCoordinator?.dispose();
    _hlsScrubCoordinator = null;
    _hlsScrubCoordinatorKey = null;
  }

  String _scrubSessionKeyForTarget(PlaybackTarget target) {
    return <String>[
      _scrubContentKey,
      _playbackTargetSignature(target),
      _directScrubStrategyVersion,
    ].join('|');
  }

  String _scrubSourceSignatureForTarget(PlaybackTarget target) {
    return _directSourceSignature(
      providerIndex: target.providerIndex,
      uri: target.uri,
      sourceKind: target.sourceKind,
      httpHeaders: target.httpHeaders,
      pageUri: target.pageUri,
    );
  }

  ThumbnailDirectSession _ensureDirectScrubSession(PlaybackTarget target) {
    final sessionKey = _scrubSessionKeyForTarget(target);
    final durationMs =
        _playbackSurface.playerState.value.totalDuration.inMilliseconds;
    if (_directScrubSessionKey != sessionKey || _directScrubSession == null) {
      _disposeDirectScrubSession();
      _directScrubSessionKey = sessionKey;
      _directScrubSession = _directScrubThumbnailService.openDirectSession(
        videoId: sessionKey,
        sourceUri: target.uri.toString(),
        httpHeaders: target.httpHeaders,
        sourceSignature: _scrubSourceSignatureForTarget(target),
        strategyVersion: _directScrubStrategyVersion,
        durationMs: durationMs,
        width: _scrubThumbnailTargetWidth,
        height: _scrubThumbnailTargetHeight,
        bucketMs: _scrubFrameCacheStep.inMilliseconds,
        jpegQuality: 72,
      );
    } else {
      _directScrubSession!.updateDurationMs(durationMs);
    }
    _syncScrubBackgroundWork(_playbackSurface.playerState.value);
    return _directScrubSession!;
  }

  _HlsScrubFrameCoordinator _ensureHlsScrubCoordinator(PlaybackTarget target) {
    final sessionKey = _scrubSessionKeyForTarget(target);
    if (_hlsScrubCoordinatorKey != sessionKey || _hlsScrubCoordinator == null) {
      _disposeHlsScrubCoordinator();
      _hlsScrubCoordinatorKey = sessionKey;
      _hlsScrubCoordinator = _HlsScrubFrameCoordinator(
        bucketStep: _scrubFrameCacheStep,
        extractor: ({
          required Duration position,
          required bool prioritizeVisible,
        }) {
          return _fallbackExtractedScrubThumbnailDataUri(
            position,
            prioritizeVisible: prioritizeVisible,
          );
        },
      );
    }
    _syncScrubBackgroundWork(_playbackSurface.playerState.value);
    return _hlsScrubCoordinator!;
  }

  void _syncScrubBackgroundWork(PlaybackPresentation presentation) {
    final shouldPause = _resolvingSource ||
        _surfaceLoading ||
        _pendingTarget != null ||
        _scrubUiVisible ||
        _activeSeekOperations > 0 ||
        _pendingSeekTarget != null ||
        presentation.isBuffering ||
        !_isPresentationPausedForUi(presentation);
    if (shouldPause) {
      _directScrubSession?.pauseBackgroundWork();
      _hlsScrubCoordinator?.pauseBackgroundWork();
      return;
    }
    _directScrubSession?.resumeBackgroundWork();
    unawaited(_directScrubSession?.primeFullMovie());
    _hlsScrubCoordinator?.resumeBackgroundWork();
  }

  void _showNoSourcesState() {
    _resetScrubFrameCache();
    _resetDirectStartupStability();
    _autoRecoveryFailedProviderIndexes.clear();
    _loopRecoveryRetriedProviderIndexes.clear();
    _pendingLoadShouldRemainPaused = false;
    _committedTarget = null;
    _pendingTarget = null;
    _resolvingSource = false;
    _surfaceLoading = false;
    _surfaceReady = false;
    _directFrameTimeoutTimer?.cancel();
    _playbackStartupEscapeTimer?.cancel();
    _error = _noSourcesErrorMessage;
    _statusMessage = _noSourcesTitle;
  }

  EpisodeSummary? get _activeEpisodeSummary {
    final episodes = _seasonEpisodesByNumber[_activeSeasonNumber];
    if (episodes == null) {
      return null;
    }

    for (final episode in episodes) {
      if (episode.episodeNumber == _activeEpisodeNumber) {
        return episode;
      }
    }

    return null;
  }

  String get _playerTitle {
    final fallbackTitle = _summary?.title ?? 'Loading title...';
    if (!_isTvEpisodePlayer) {
      return fallbackTitle;
    }

    final episodeTitle = _activeEpisodeSummary?.title ?? fallbackTitle;
    return '[S$_activeSeasonNumber:E$_activeEpisodeNumber] $episodeTitle';
  }

  String get _nextEpisodePromptTitle {
    final candidate = _nextEpisodeTarget;
    if (candidate == null) {
      return 'Next episode';
    }

    final episodeTitle = candidate.title.isNotEmpty
        ? candidate.title
        : 'Episode ${candidate.episodeNumber}';
    return '[S${candidate.seasonNumber}:E${candidate.episodeNumber}] '
        '$episodeTitle';
  }

  @override
  void initState() {
    super.initState();
    _playbackSurface =
        (widget.playbackSurfaceFactory ?? _defaultPlaybackSurfaceFactory)();
    _playbackSurfaceEventsSubscription =
        _playbackSurface.events.listen(_handlePlaybackSurfaceEvent);
    _playbackSurface.playerState.addListener(_handlePlayerStateChanged);
    _summary = widget.initialSummary;
    _activeSeasonNumber = widget.seasonNumber;
    _activeEpisodeNumber = widget.episodeNumber;
    HardwareKeyboard.instance.addHandler(_handlePlayerHardwareKey);
    for (final focusNode in _chromeFocusNodes) {
      focusNode.addListener(_handleChromeFocusChange);
    }
    WidgetsBinding.instance.addObserver(this);
    _playbackStallWatchdogTimer = Timer.periodic(
      _playbackStallWatchdogInterval,
      (_) => _checkForPlaybackStall(),
    );
    _progressCheckpointTimer = Timer.periodic(
      _progressCheckpointInterval,
      (_) => unawaited(_checkpointPlaybackProgress()),
    );
    _runGuardedPlayerTask(
      'Initialize scrub thumbnail service',
      _directScrubThumbnailService.initialize,
    );
    _setResumeAnchor(widget.initialResumePosition);
    _runGuardedPlayerTask('Hydrate subtitle offset', _hydrateSubtitleOffset);
    _runGuardedPlayerTask(
      'Resolve initial playback target',
      _resolveInitialTarget,
      fatal: true,
    );
    _runGuardedPlayerTask('Load title metadata', _loadSummary);
    _runGuardedPlayerTask('Warm episode metadata', _warmEpisodeMetadata);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playbackSurface.playerState.removeListener(_handlePlayerStateChanged);
    HardwareKeyboard.instance.removeHandler(_handlePlayerHardwareKey);
    _cancelChromeHide();
    _clearOverlayBackWindow();
    _clearChromeBackConsumedGuard();
    _cancelQueuedViewerSeek(clearPending: false);
    _cancelSeekLoadingFallback();
    _clearPostSeekRegressionGuard();
    unawaited(_flushProgress(force: true, awaitCallbacks: true));
    _nextEpisodeCountdownTimer?.cancel();
    _embedPromotionTimeoutTimer?.cancel();
    _directFrameTimeoutTimer?.cancel();
    _playbackStartupEscapeTimer?.cancel();
    _playbackStallWatchdogTimer?.cancel();
    _progressCheckpointTimer?.cancel();
    _unexpectedStopRecoveryTimer?.cancel();
    _longPauseRefreshArmTimer?.cancel();
    _disposeScrubCoordinators();
    _trimPlayerMemory();
    _playbackSurfaceEventsSubscription.cancel();
    unawaited(_disposePlaybackSurface());
    for (final focusNode in _chromeFocusNodes) {
      focusNode.removeListener(_handleChromeFocusChange);
    }
    _backCaptureFocusNode.dispose();
    _backFocusNode.dispose();
    _playPauseFocusNode.dispose();
    _scrubFocusNode.dispose();
    _seekBackwardFocusNode.dispose();
    _seekForwardFocusNode.dispose();
    _episodesFocusNode.dispose();
    _captionsFocusNode.dispose();
    _audioLanguageFocusNode.dispose();
    _settingsFocusNode.dispose();
    _nextEpisodeFocusNode.dispose();
    _zoomOutFocusNode.dispose();
    _zoomInFocusNode.dispose();
    _fullscreenFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _appLifecycleActive = false;
        _resetPlaybackStallWatchdog(resetRecoveryAttempts: false);
        final presentation = _playbackSurface.playerState.value;
        final shouldResumeAfterInterruption = _surfaceReady &&
            _intendedPlaybackPlaying &&
            !_isPresentationPausedForUi(presentation);
        _resumePlaybackAfterLifecyclePause =
            _resumePlaybackAfterLifecyclePause || shouldResumeAfterInterruption;
        _logPlayerDiagnostic(
          'Lifecycle interruption state=${state.name} '
          'enginePaused=${_isPresentationPausedForUi(presentation)} '
          'intendedPlaying=$_intendedPlaybackPlaying '
          'armedResume=$_resumePlaybackAfterLifecyclePause',
        );
        _trimPlayerMemory();
        unawaited(_flushProgress(force: true, awaitCallbacks: true));
        return;
      case AppLifecycleState.resumed:
        _appLifecycleActive = true;
        _resetPlaybackStallWatchdog(resetRecoveryAttempts: false);
        _logPlayerDiagnostic(
          'Lifecycle resumed '
          'armedResume=$_resumePlaybackAfterLifecyclePause '
          'intendedPlaying=$_intendedPlaybackPlaying',
        );
        unawaited(_handleLifecycleResumed());
        return;
    }
  }

  @override
  void didHaveMemoryPressure() {
    CheriflixRuntimePressureController.instance.handleMemoryPressure();
    _logPlayerDiagnostic(
      'Memory pressure received; trimming caches without stopping playback.',
    );
    _trimPlayerMemory();
  }

  void _trimPlayerMemory() {
    _scrubFrameCache.clear();
    unawaited(_directScrubThumbnailService.trimMemory());
  }

  Future<void> _handleLifecycleResumed() async {
    final shouldResumePlayback = _resumePlaybackAfterLifecyclePause;
    _resumePlaybackAfterLifecyclePause = false;
    if (_resumePending) {
      _resumeSeekIssued = false;
    }

    try {
      await _playbackSurface.requestPlayerState();
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Refreshing playback state after app resume failed.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (!mounted) {
      return;
    }

    final resumeHandled =
        _applyResumeIfNeeded(_playbackSurface.playerState.value);
    if (!resumeHandled &&
        shouldResumePlayback &&
        _surfaceReady &&
        _isPresentationPausedForUi(_playbackSurface.playerState.value)) {
      await _recoverPlaybackIfNeeded('lifecycle-resume', force: true);
    }
    if (mounted) {
      _handlePlayerStateChanged();
    }
  }

  Future<void> _stopPlaybackSurfaceForExit() async {
    try {
      await _playbackSurface.quietStop().timeout(_playerExitStopTimeout);
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Stopping playback during player exit failed.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _disposePlaybackSurface() async {
    if (_playbackSurfaceTeardownStarted) {
      return;
    }
    _playbackSurfaceTeardownStarted = true;
    await _stopPlaybackSurfaceForExit();
    try {
      await _playbackSurface.dispose().timeout(_playerSurfaceDisposeTimeout);
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Disposing playback surface failed.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _runGuardedPlayerTask(
    String label,
    Future<void> Function() task, {
    bool fatal = false,
  }) {
    unawaited(
      () async {
        try {
          await task();
        } catch (error, stackTrace) {
          _logPlayerDiagnostic(
            '$label failed.',
            error: error,
            stackTrace: stackTrace,
          );
          if (fatal && mounted) {
            _showFatalPlaybackDialog(_formatPlaybackError(error));
          }
        }
      }(),
    );
  }

  void _showFatalPlaybackDialog(String message) {
    if (!mounted || _fatalPlaybackDialogVisible) {
      return;
    }
    _fatalPlaybackDialogVisible = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _fatalPlaybackDialogVisible = false;
        return;
      }
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: true,
          builder: (context) {
            return _PlaybackErrorDialog(message: message);
          },
        ).whenComplete(() {
          _fatalPlaybackDialogVisible = false;
        }),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final chromeTitle = !_hasCommittedTarget &&
            (_resolvingSource || _surfaceLoading || _pendingTarget != null)
        ? (_statusMessage ?? _playerTitle)
        : _playerTitle;

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        _handleBack();
      },
      child: TvShortcutScope(
        onBack: _handleBack,
        autoEnsureVisible: false,
        child: Focus(
          focusNode: _backCaptureFocusNode,
          skipTraversal: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                !_exitConfirmationVisible &&
                _isPlayerBackKey(event.logicalKey)) {
              _handleBack();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.mediaPlayPause):
                  _PlayerShortcutIntent.playPause(),
              SingleActivator(LogicalKeyboardKey.mediaPlay):
                  _PlayerShortcutIntent.play(),
              SingleActivator(LogicalKeyboardKey.mediaPause):
                  _PlayerShortcutIntent.pause(),
              SingleActivator(LogicalKeyboardKey.mediaFastForward):
                  _PlayerShortcutIntent.seekForward(),
              SingleActivator(LogicalKeyboardKey.mediaRewind):
                  _PlayerShortcutIntent.seekBackward(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                _PlayerShortcutIntent: CallbackAction<_PlayerShortcutIntent>(
                  onInvoke: (intent) {
                    return _handlePlayerShortcut(intent.action);
                  },
                ),
              },
              child: Scaffold(
                body: SizedBox.expand(
                  child: ValueListenableBuilder<PlaybackPresentation>(
                    valueListenable: _playbackSurface.playerState,
                    builder: (context, presentation, child) {
                      final chromePresentation =
                          _presentationForChrome(presentation);
                      final showChrome =
                          _isChromeVisibleToUser(chromePresentation);
                      _maybeRequestInitialChromeFocus(
                        showChrome: showChrome,
                        presentation: chromePresentation,
                      );
                      return Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: _buildBody(presentation),
                          ),
                          Positioned.fill(
                            child: Listener(
                              behavior: HitTestBehavior.translucent,
                              onPointerDown: (_) =>
                                  _handleChromePointerActivity(),
                              onPointerHover: (_) =>
                                  _handleChromePointerActivity(),
                              onPointerMove: (_) =>
                                  _handleChromePointerActivity(),
                              onPointerSignal: (_) =>
                                  _handleChromePointerActivity(),
                              child: const SizedBox.expand(),
                            ),
                          ),
                          _PlayerSubtitleOverlay(
                            linesListenable: _playbackSurface.subtitleLines,
                            showControls: showChrome,
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              key: const ValueKey<String>(
                                'player_chrome_overlay_gate',
                              ),
                              ignoring: !showChrome,
                              child: AnimatedOpacity(
                                opacity: showChrome ? 1 : 0,
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOutCubic,
                                child: _PlayerChromeOverlayV2(
                                  title: chromeTitle,
                                  presentation: chromePresentation,
                                  playbackHint: _playbackHintForPresentation(
                                    presentation,
                                  ),
                                  onBack: _handleBack,
                                  onPlayPause:
                                      _surfaceReady ? _togglePlayPause : null,
                                  onSeekBackward: _surfaceReady
                                      ? () => _runGuardedPlayerTask(
                                            'Seek backward',
                                            _seekBackward,
                                          )
                                      : null,
                                  onSeekForward: _surfaceReady
                                      ? () => _runGuardedPlayerTask(
                                            'Seek forward',
                                            _seekForward,
                                          )
                                      : null,
                                  onSeekToPosition:
                                      _surfaceReady ? _seekToPosition : null,
                                  onRequestScrubFrame: _surfaceReady
                                      ? _requestVisibleScrubFrame
                                      : null,
                                  scrubFrameCache: _scrubFrameCache,
                                  onExitScrubFocus: _exitScrubFocus,
                                  onOpenEpisodes: _surfaceReady &&
                                          widget.mediaType == MediaType.tv
                                      ? () => _runGuardedPlayerTask(
                                            'Open episodes overlay',
                                            _openEpisodesModal,
                                          )
                                      : null,
                                  onOpenCaptions: _surfaceReady
                                      ? () => _runGuardedPlayerTask(
                                            'Open caption picker',
                                            _openCaptionPicker,
                                          )
                                      : null,
                                  onOpenAudioLanguage: _surfaceReady
                                      ? () => _runGuardedPlayerTask(
                                            'Open audio language picker',
                                            _openAudioTrackPicker,
                                          )
                                      : null,
                                  onOpenSettings: _surfaceReady
                                      ? () => _runGuardedPlayerTask(
                                            'Open playback settings',
                                            _openSettings,
                                          )
                                      : null,
                                  onNextEpisode: _surfaceReady &&
                                          _nextEpisodeTarget != null
                                      ? () => _runGuardedPlayerTask(
                                            'Play next episode',
                                            _playNextEpisode,
                                          )
                                      : null,
                                  onZoomOut: _surfaceReady
                                      ? () => _runGuardedPlayerTask(
                                            'Zoom out',
                                            _zoomOut,
                                          )
                                      : null,
                                  onZoomIn: _surfaceReady
                                      ? () => _runGuardedPlayerTask(
                                            'Zoom in',
                                            _zoomIn,
                                          )
                                      : null,
                                  onPlaceholderFullscreenExit:
                                      _placeholderFullscreenExit,
                                  backFocusNode: _backFocusNode,
                                  playPauseFocusNode: _playPauseFocusNode,
                                  scrubFocusNode: _scrubFocusNode,
                                  seekBackwardFocusNode: _seekBackwardFocusNode,
                                  seekForwardFocusNode: _seekForwardFocusNode,
                                  episodesFocusNode: _episodesFocusNode,
                                  captionsFocusNode: _captionsFocusNode,
                                  audioLanguageFocusNode:
                                      _audioLanguageFocusNode,
                                  settingsFocusNode: _settingsFocusNode,
                                  nextEpisodeFocusNode: _nextEpisodeFocusNode,
                                  zoomOutFocusNode: _zoomOutFocusNode,
                                  zoomInFocusNode: _zoomInFocusNode,
                                  fullscreenFocusNode: _fullscreenFocusNode,
                                  showNextEpisodeButton: _surfaceReady &&
                                      _nextEpisodeTarget != null,
                                  showEpisodesButton: _surfaceReady &&
                                      widget.mediaType == MediaType.tv,
                                  scrubUiVisible: _scrubUiVisible,
                                  onScrubUiVisibilityChanged:
                                      _handleScrubUiVisibilityChanged,
                                ),
                              ),
                            ),
                          ),
                          if (_nextEpisodePromptVisible &&
                              _nextEpisodeTarget != null)
                            Positioned.fill(
                              child: _NextEpisodePromptOverlay(
                                title: _playerTitle,
                                nextEpisodeTitle: _nextEpisodePromptTitle,
                                countdownSeconds: _nextEpisodeCountdownSeconds,
                                onPlayNow: () => _runGuardedPlayerTask(
                                  'Play next episode prompt',
                                  _playNextEpisode,
                                ),
                                onCancel: _dismissNextEpisodePrompt,
                                playButtonFocusNode: _nextEpisodeFocusNode,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(PlaybackPresentation presentation) {
    if (!_hasCommittedTarget) {
      if (_resolvingSource || _surfaceLoading || _pendingTarget != null) {
        return Container(
          color: Colors.black,
          child: Center(
            child: _PlaybackLoadingIndicator(
              message: _userFacingLoadingStage(presentation),
            ),
          ),
        );
      }

      final title = _error == _noSourcesErrorMessage
          ? _noSourcesTitle
          : 'Playback unavailable';
      return _StatePanel(
        title: title,
        message: _error ?? 'No working playback source was found.',
        icon: Icons.error_outline_rounded,
      );
    }

    return Container(
      color: Colors.black,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: IgnorePointer(
              key: _surfaceInteractionGateKey,
              ignoring: !_shouldAllowSurfaceInteraction(presentation),
              child: _playbackSurface.buildView(),
            ),
          ),
          if (_surfaceLoading ||
              _resolvingSource ||
              (!presentation.hasVisibleVideo && presentation.isBuffering))
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: const Color(0x55000000),
                  child: Center(
                    child: _PlaybackLoadingIndicator(
                      message: _userFacingLoadingStage(presentation),
                    ),
                  ),
                ),
              ),
            ),
          if (_pendingSeekTarget != null)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: const Color(0x55000000),
                  child: Center(
                    child: SizedBox(
                      key: const ValueKey<String>(
                        'player_seek_loading_indicator',
                      ),
                      width: 36,
                      height: 36,
                      child: const CircularProgressIndicator(),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _shouldAllowSurfaceInteraction(PlaybackPresentation presentation) {
    return false;
  }

  String _userFacingLoadingStage(PlaybackPresentation presentation) {
    if (_resolvingSource || !_hasCommittedTarget) return 'Finding source…';
    if (presentation.isBuffering) {
      final percentage = presentation.bufferingPercentage.round();
      if (percentage > 0 && percentage < 100) {
        return 'Buffering… $percentage%';
      }
      if (percentage >= 100) return 'Preparing video…';
      return 'Buffering…';
    }
    return 'Preparing video…';
  }

  bool _isUncontrolledEmbedPlayback(
    PlaybackPresentation presentation, {
    PlaybackTarget? target,
  }) {
    return false;
  }

  bool _isPresentationPausedForUi(
    PlaybackPresentation presentation, {
    PlaybackTarget? target,
  }) {
    return _isUncontrolledEmbedPlayback(presentation, target: target) ||
        presentation.isPaused;
  }

  PlaybackPresentation _presentationForChrome(
    PlaybackPresentation presentation,
  ) {
    final optimisticPosition = _pendingSeekTarget;
    if (optimisticPosition == null) {
      return presentation;
    }
    return presentation.copyWith(currentPosition: optimisticPosition);
  }

  String? _playbackHintForPresentation(PlaybackPresentation presentation) {
    return null;
  }

  Future<void> _resolveInitialTarget() async {
    final contentGeneration = _contentGeneration;
    final rememberedLanguage =
        await widget.audioLanguagePreferenceStore.getPreferredLanguage(
      profileId: widget.profileId,
      tmdbId: widget.tmdbId,
      mediaType: widget.mediaType,
    );
    if (!mounted || contentGeneration != _contentGeneration) return;
    _effectiveAudioLanguage = normalizeAudioLanguageCode(
      rememberedLanguage ?? widget.playbackSettings.preferredAudioLanguageCode,
    );
    if (_effectiveAudioLanguage.isEmpty) _effectiveAudioLanguage = 'en';
    widget.playbackProvider.beginPlaybackAttempt(
      profileId: widget.profileId,
      tmdbId: widget.tmdbId,
      mediaType: widget.mediaType,
      seasonNumber: _isTvEpisodePlayer ? _activeSeasonNumber : null,
      episodeNumber: _isTvEpisodePlayer ? _activeEpisodeNumber : null,
    );
    _autoRecoveryFailedProviderIndexes.clear();
    _loopRecoveryRetriedProviderIndexes.clear();
    setState(() {
      _resolvingSource = true;
      _surfaceLoading = false;
      _error = null;
      _statusMessage = 'Resolving playback source...';
    });

    PlaybackTarget? target;
    try {
      target = await _resolveTargetFromStart();
    } catch (error) {
      if (!mounted || contentGeneration != _contentGeneration) {
        return;
      }
      setState(() {
        _committedTarget = null;
        _pendingTarget = null;
        _resolvingSource = false;
        _surfaceLoading = false;
        _surfaceReady = false;
        _error = _formatPlaybackError(error);
        _statusMessage = 'Playback unavailable';
      });
      return;
    }

    if (!mounted || contentGeneration != _contentGeneration) {
      _suppressProgressReporting = false;
      return;
    }

    if (target == null) {
      setState(_showNoSourcesState);
      return;
    }

    setState(() {
      _pendingTarget = target;
      _resolvingSource = false;
      _surfaceLoading = true;
      _error = null;
      _statusMessage = _loadingStatusMessageForTarget(target!);
    });

    await _loadPlaybackTarget(target);
  }

  Future<PlaybackTarget?> _resolveTargetFromStart() async {
    final enabledProviders = widget.playbackProvider.listEnabledProviders();
    if (enabledProviders.isEmpty) {
      return null;
    }

    final target = await widget.playbackProvider.resolveTitleWithLanguage(
      profileId: widget.profileId,
      tmdbId: widget.tmdbId,
      mediaType: widget.mediaType,
      seasonNumber: _isTvEpisodePlayer ? _activeSeasonNumber : null,
      episodeNumber: _isTvEpisodePlayer ? _activeEpisodeNumber : null,
      preferredAudioLanguage: _effectiveAudioLanguage,
    );

    if (!mounted) {
      return null;
    }

    return target;
  }

  Future<PlaybackTarget?> _resolveTargetAfterFailure({
    required int currentProviderIndex,
    String? blockedStreamHost,
  }) async {
    final enabledProviders = widget.playbackProvider.listEnabledProviders();
    if (enabledProviders.isEmpty) {
      return null;
    }

    _autoRecoveryFailedProviderIndexes.add(currentProviderIndex);
    final normalizedBlockedHost = blockedStreamHost?.trim().toLowerCase();
    PlaybackTarget? sameHostLastResort;

    bool usesBlockedHost(PlaybackTarget target) {
      return normalizedBlockedHost != null &&
          normalizedBlockedHost.isNotEmpty &&
          target.uri.host.trim().toLowerCase() == normalizedBlockedHost;
    }

    var afterProviderIndex = currentProviderIndex;
    for (var attempt = 0; attempt < enabledProviders.length; attempt += 1) {
      final candidate = await widget.playbackProvider.resolveNextSource(
        profileId: widget.profileId,
        tmdbId: widget.tmdbId,
        mediaType: widget.mediaType,
        currentProviderIndex: afterProviderIndex,
        seasonNumber: _isTvEpisodePlayer ? _activeSeasonNumber : null,
        episodeNumber: _isTvEpisodePlayer ? _activeEpisodeNumber : null,
        preferredAudioLanguage: _effectiveAudioLanguage,
        probeCandidates: true,
      );
      if (!mounted) {
        return null;
      }
      if (candidate == null) {
        break;
      }
      afterProviderIndex = candidate.providerIndex;
      if (_autoRecoveryFailedProviderIndexes
          .contains(candidate.providerIndex)) {
        continue;
      }
      if (!usesBlockedHost(candidate)) {
        return candidate;
      }
      sameHostLastResort ??= candidate;
      _autoRecoveryFailedProviderIndexes.add(candidate.providerIndex);
    }

    return sameHostLastResort;
  }

  Future<void> _loadSummary() async {
    final service = widget.mediaCatalogService;
    if (service == null) {
      return;
    }

    try {
      final summary = await service.fetchTitleDetails(
        tmdbId: widget.tmdbId,
        mediaType: widget.mediaType,
        languageCode: widget.languageCode,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _summary = summary;
      });
    } catch (_) {
      // Metadata loading is secondary to playback.
    }
  }

  TmdbMediaCatalogService? get _tmdbCatalogService {
    final service = widget.mediaCatalogService;
    if (service is TmdbMediaCatalogService) {
      return service;
    }
    return null;
  }

  Future<void> _warmEpisodeMetadata() async {
    if (!_isTvEpisodePlayer) {
      return;
    }

    unawaited(_ensureSeasonEpisodesLoaded(_activeSeasonNumber));
    _refreshNextEpisodeTarget();
  }

  Future<List<EpisodeSummary>?> _ensureSeasonEpisodesLoaded(
    int seasonNumber,
  ) async {
    if (!_isTvEpisodePlayer || seasonNumber <= 0) {
      return null;
    }

    final cached = _seasonEpisodesByNumber[seasonNumber];
    if (cached != null) {
      return cached;
    }

    final catalogService = _tmdbCatalogService;
    if (catalogService == null) {
      return null;
    }

    try {
      final episodes = await catalogService.fetchSeasonEpisodes(
        tmdbId: widget.tmdbId,
        seasonNumber: seasonNumber,
        languageCode: widget.languageCode,
        fallbackRuntimeMinutes:
            _summary?.runtimeMinutes ?? widget.initialSummary?.runtimeMinutes,
      );
      if (!mounted) {
        return episodes;
      }

      setState(() {
        _seasonEpisodesByNumber[seasonNumber] = episodes;
      });
      _refreshNextEpisodeTarget();
      unawaited(
        _primeScrubPreviewPathForCurrentContent(allowRetryIfAttempted: true),
      );
      return episodes;
    } catch (_) {
      return null;
    }
  }

  void _refreshNextEpisodeTarget() {
    if (!_isTvEpisodePlayer) {
      if (_nextEpisodeTarget != null) {
        setState(() {
          _nextEpisodeTarget = null;
        });
      }
      return;
    }

    EpisodeSummary? candidate;
    final currentSeasonEpisodes = _seasonEpisodesByNumber[_activeSeasonNumber];
    if (currentSeasonEpisodes != null) {
      for (final episode in currentSeasonEpisodes) {
        if (episode.episodeNumber == _activeEpisodeNumber + 1) {
          candidate = episode;
          break;
        }
      }

      if (candidate == null && currentSeasonEpisodes.isNotEmpty) {
        final seasonCount =
            _summary?.seasonCount ?? widget.initialSummary?.seasonCount;
        if (seasonCount != null && _activeSeasonNumber < seasonCount) {
          final nextSeasonNumber = _activeSeasonNumber + 1;
          final nextSeasonEpisodes = _seasonEpisodesByNumber[nextSeasonNumber];
          if (nextSeasonEpisodes != null && nextSeasonEpisodes.isNotEmpty) {
            candidate = nextSeasonEpisodes.first;
          } else {
            unawaited(_ensureSeasonEpisodesLoaded(nextSeasonNumber));
          }
        }
      }
    } else {
      unawaited(_ensureSeasonEpisodesLoaded(_activeSeasonNumber));
    }

    if (candidate?.seasonNumber != _nextEpisodeTarget?.seasonNumber ||
        candidate?.episodeNumber != _nextEpisodeTarget?.episodeNumber ||
        candidate?.title != _nextEpisodeTarget?.title) {
      setState(() {
        _nextEpisodeTarget = candidate;
      });
    }
  }

  void _cancelNextEpisodePrompt() {
    _nextEpisodeCountdownTimer?.cancel();
    _nextEpisodeCountdownTimer = null;
    if (!_nextEpisodePromptVisible &&
        _nextEpisodeCountdownSeconds == 0 &&
        !_nextEpisodePromptWasPlaying) {
      return;
    }

    setState(() {
      _nextEpisodePromptVisible = false;
      _nextEpisodePromptWasPlaying = false;
      _nextEpisodeCountdownSeconds = 0;
    });
  }

  void _dismissNextEpisodePrompt() {
    final shouldResume = _nextEpisodePromptWasPlaying;
    _cancelNextEpisodePrompt();
    if (shouldResume &&
        _surfaceReady &&
        _playbackSurface.playerState.value.isPaused) {
      unawaited(
        _setPlaybackPlaying(
          true,
          reason: 'next-episode-prompt-dismiss-resume',
          updateIntent: false,
        ),
      );
    }
  }

  void _updateNextEpisodePrompt(PlaybackPresentation presentation) {
    if (!_isTvEpisodePlayer ||
        !_surfaceReady ||
        _nextEpisodeTarget == null ||
        widget.playbackSettings.autoplayNextEpisode == false) {
      if (_nextEpisodePromptVisible) {
        _cancelNextEpisodePrompt();
      }
      return;
    }

    final totalSeconds = presentation.totalDuration.inSeconds;
    if (totalSeconds <= 0) {
      return;
    }

    final currentSeconds = presentation.currentPosition.inSeconds;
    final isNearEnd = currentSeconds >= totalSeconds - 5;
    if (!isNearEnd) {
      if (_nextEpisodePromptVisible) {
        _cancelNextEpisodePrompt();
      }
      return;
    }

    if (_nextEpisodePromptVisible) {
      return;
    }

    _nextEpisodePromptWasPlaying = !presentation.isPaused;
    if (_nextEpisodePromptWasPlaying) {
      unawaited(
        _setPlaybackPlaying(
          false,
          reason: 'next-episode-prompt-pause',
          updateIntent: false,
        ),
      );
    }

    setState(() {
      _nextEpisodePromptVisible = true;
      _nextEpisodeCountdownSeconds = 5;
    });

    _nextEpisodeCountdownTimer?.cancel();
    _nextEpisodeCountdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (!mounted || !_nextEpisodePromptVisible) {
          timer.cancel();
          return;
        }

        if (_nextEpisodeCountdownSeconds <= 1) {
          timer.cancel();
          unawaited(_playNextEpisode());
          return;
        }

        setState(() {
          _nextEpisodeCountdownSeconds -= 1;
        });
      },
    );
  }

  Future<void> _playNextEpisode() async {
    final nextEpisode = _nextEpisodeTarget;
    if (!_isTvEpisodePlayer || nextEpisode == null) {
      return;
    }

    _cancelNextEpisodePrompt();
    await _activateEpisode(
      seasonNumber: nextEpisode.seasonNumber,
      episodeNumber: nextEpisode.episodeNumber,
    );
  }

  // ignore: unused_element
  Future<void> _tryNextSource() async {
    final currentTarget = _currentRecoveryTarget;
    if (currentTarget == null || _resolvingSource || _surfaceLoading) {
      return;
    }

    await _recoverFromSourceFailure(
      currentProviderIndex: currentTarget.providerIndex,
      failureKind: SourceFailureKind.load,
      failureReason:
          '${currentTarget.providerLabel} failed. Trying the next source...',
    );
  }

  Future<void> _recoverFromSourceFailure({
    required int currentProviderIndex,
    required SourceFailureKind failureKind,
    String? blockedHost,
    String? blockedStreamHost,
    String? failureReason,
    Duration? recoveryResumePosition,
    bool skipInternalFallbacks = false,
  }) async {
    if (_sourceRecoveryInFlight || !mounted) {
      return;
    }
    _sourceRecoveryInFlight = true;
    try {
      await _recoverFromSourceFailureInternal(
        currentProviderIndex: currentProviderIndex,
        failureKind: failureKind,
        blockedHost: blockedHost,
        blockedStreamHost: blockedStreamHost,
        failureReason: failureReason,
        recoveryResumePosition: recoveryResumePosition,
        skipInternalFallbacks: skipInternalFallbacks,
      );
    } finally {
      _sourceRecoveryInFlight = false;
    }
  }

  Future<void> _recoverFromSourceFailureInternal({
    required int currentProviderIndex,
    required SourceFailureKind failureKind,
    String? blockedHost,
    String? blockedStreamHost,
    String? failureReason,
    Duration? recoveryResumePosition,
    bool skipInternalFallbacks = false,
  }) async {
    if (!mounted) {
      return;
    }

    final recoveryContentGeneration = _contentGeneration;
    bool recoveryIsCurrent() =>
        mounted && recoveryContentGeneration == _contentGeneration;

    final failurePresentation = _playbackSurface.playerState.value;
    final preservedPosition = recoveryResumePosition ??
        (failurePresentation.currentPosition > Duration.zero
            ? failurePresentation.currentPosition
            : _lastTrustedPlaybackPosition);
    final shouldRemainPaused = !_intendedPlaybackPlaying;
    final failedTarget = _currentRecoveryTarget;
    final diagnosticSessionId = failedTarget?.diagnosticSessionId;
    if (diagnosticSessionId != null) {
      PlaybackDiagnostics.instance.record(
        sessionId: diagnosticSessionId,
        stage: PlaybackDiagnosticStage.failover,
        providerKey: failedTarget!.providerKey,
        outcome: failureKind.name,
        details: <String, Object?>{
          if (failureReason != null) 'reason': failureReason,
          if (blockedHost != null) 'blockedHost': blockedHost,
        },
      );
    }
    if (!skipInternalFallbacks &&
        failedTarget != null &&
        failedTarget.providerIndex == currentProviderIndex &&
        failedTarget.fallbackUris.isNotEmpty) {
      final fallbackUri = failedTarget.fallbackUris.first;
      final fallbackTarget = PlaybackTarget(
        uri: fallbackUri,
        providerKey: failedTarget.providerKey,
        providerLabel: failedTarget.providerLabel,
        providerIndex: failedTarget.providerIndex,
        sourceKind: _directSourceKindForUri(fallbackUri),
        httpHeaders: failedTarget.httpHeaders,
        pageUri: failedTarget.pageUri,
        expiresAtEpochMs: failedTarget.expiresAtEpochMs,
        fallbackUris: failedTarget.fallbackUris.skip(1).toList(growable: false),
        diagnosticSessionId: failedTarget.diagnosticSessionId,
        offlineStorageAllowed: failedTarget.offlineStorageAllowed,
        qualityLabel: failedTarget.qualityLabel,
        bitrateBitsPerSecond: failedTarget.bitrateBitsPerSecond,
      );
      _logPlayerDiagnostic(
        'Trying internal fallback for ${failedTarget.providerLabel} '
        'remaining=${fallbackTarget.fallbackUris.length} '
        'uri=$fallbackUri',
      );
      await _haltSurfacePlaybackForRecovery();
      if (!recoveryIsCurrent()) {
        return;
      }
      setState(() {
        _resolvingSource = false;
        _surfaceLoading = true;
        _surfaceReady = false;
        _pendingTarget = fallbackTarget;
        _error = null;
        _statusMessage =
            'Trying a backup stream from ${failedTarget.providerLabel}...';
      });
      await _loadPlaybackTarget(
        fallbackTarget,
        switchResumePosition:
            preservedPosition > Duration.zero ? preservedPosition : null,
        switchShouldRemainPaused: shouldRemainPaused,
      );
      return;
    }

    final sourceLabel =
        _currentRecoveryTarget?.providerLabel ?? 'The current source';

    widget.playbackProvider.recordSourceFailure(
      profileId: widget.profileId,
      tmdbId: widget.tmdbId,
      mediaType: widget.mediaType,
      seasonNumber: _isTvEpisodePlayer ? _activeSeasonNumber : null,
      episodeNumber: _isTvEpisodePlayer ? _activeEpisodeNumber : null,
      providerIndex: currentProviderIndex,
      kind: failureKind,
    );

    _logPlayerDiagnostic(
      'Recovering from source failure '
      'providerIndex=$currentProviderIndex '
      'kind=${failureKind.name} '
      'blockedHost=${blockedHost ?? '-'} '
      'reason=${failureReason ?? '-'}',
    );
    await _haltSurfacePlaybackForRecovery();

    // Episode selection invalidates every recovery job belonging to the
    // outgoing episode. Without this guard a watchdog firing as the episodes
    // overlay closed could resolve a fallback using the incoming episode's
    // IDs and overwrite its correctly resolved native source.
    if (!recoveryIsCurrent()) {
      return;
    }

    setState(() {
      _resolvingSource = true;
      _surfaceLoading = true;
      if (_committedTarget == null) {
        _surfaceReady = false;
      }
      _pendingTarget = null;
      _error = null;
      _statusMessage = blockedHost != null
          ? 'Blocked off-domain redirect from $sourceLabel. Trying the next source...'
          : failureReason ?? 'Trying the next playback source...';
    });

    PlaybackTarget? nextTarget;
    try {
      nextTarget = await _resolveTargetAfterFailure(
        currentProviderIndex: currentProviderIndex,
        blockedStreamHost: blockedStreamHost,
      );
    } catch (error) {
      if (!recoveryIsCurrent()) {
        return;
      }
      setState(() {
        _committedTarget = null;
        _pendingTarget = null;
        _resolvingSource = false;
        _surfaceLoading = false;
        _surfaceReady = false;
        _error = _formatPlaybackError(error);
        _statusMessage = 'Playback unavailable';
      });
      return;
    }

    if (!recoveryIsCurrent() || nextTarget == null) {
      if (!recoveryIsCurrent()) {
        return;
      }

      setState(_showNoSourcesState);
      return;
    }

    setState(() {
      _pendingTarget = nextTarget;
      _resolvingSource = false;
      _surfaceLoading = true;
      _error = null;
      _statusMessage = _loadingStatusMessageForTarget(nextTarget!);
    });

    await _loadPlaybackTarget(
      nextTarget,
      switchResumePosition:
          preservedPosition > Duration.zero ? preservedPosition : null,
      switchShouldRemainPaused: shouldRemainPaused,
    );
  }

  Future<void> _loadPlaybackTarget(
    PlaybackTarget target, {
    bool fromEmbedPromotion = false,
    PlaybackRendererProfile rendererProfile = PlaybackRendererProfile.standard,
    Duration? switchResumePosition,
    bool switchShouldRemainPaused = false,
  }) async {
    _cancelQueuedViewerSeek(clearPending: true);
    final currentToken = ++_surfaceLoadToken;
    _pendingLoadShouldRemainPaused = switchShouldRemainPaused;
    final effectiveRendererProfile =
        _resolveRendererProfileForLoad(target, rendererProfile);
    if (_resumePending) {
      _resumeSeekIssued = false;
    }
    _resetDirectStartupStability();
    _resetScrubFrameCache();
    _clearPostSeekRegressionGuard();
    _embedPromotionTimeoutTimer?.cancel();
    _directFrameTimeoutTimer?.cancel();
    _playbackStartupEscapeTimer?.cancel();
    _embedPromotedDirectTargetSignature =
        fromEmbedPromotion ? _playbackTargetSignature(target) : null;
    _directNoFrameRecoveryTargetSignature = null;

    setState(() {
      _pendingTarget = target;
      _surfaceLoading = true;
      _error = null;
      _statusMessage = _loadingStatusMessageForTarget(target);
    });
    _schedulePlaybackStartupEscape(
      target,
      loadToken: currentToken,
      recoveryPosition: switchResumePosition,
    );

    try {
      await _hydrateSubtitleOffset(providerKey: target.providerKey);
      _logPlayerDiagnostic(
        'Loading playback target provider=${target.providerLabel} '
        'kind=${target.sourceKind.name} direct=${target.isDirectPlayable} '
        'uri=${target.uri}',
      );
      if (!target.uri.hasScheme) {
        throw const _PlaybackSurfaceException(
          'The playback source returned an invalid target.',
        );
      }

      // Subtitle discovery is secondary to video startup and may involve a
      // remote service. Begin it in parallel, but never hold the first frame
      // behind its timeout.
      final captionResolutionTask = _resolveCaptionResolution();
      await _ensureSurfaceInitialized();
      final diagnosticsSession = target.diagnosticSessionId;
      if (diagnosticsSession != null) {
        PlaybackDiagnostics.instance.record(
          sessionId: diagnosticsSession,
          stage: PlaybackDiagnosticStage.playerLoadStarted,
          providerKey: target.providerKey,
        );
      }
      await _playbackSurface
          .load(
            PlaybackLoadRequest(
              uri: target.uri,
              sourceKind: target.sourceKind,
              httpHeaders: target.httpHeaders,
              allowedHostSuffixes: _allowedHostSuffixesForTarget(target.uri),
              captionTracks: const <CaptionTrack>[],
              selectedCaptionTrackId: null,
              preferredAudioLanguage: _effectiveAudioLanguage,
              providerKey: target.providerKey,
              originalLanguageCode: _summary?.originalLanguage,
              rendererProfile: effectiveRendererProfile,
            ),
          )
          .timeout(_playbackLoadTimeout);
      if (diagnosticsSession != null) {
        PlaybackDiagnostics.instance.record(
          sessionId: diagnosticsSession,
          stage: PlaybackDiagnosticStage.playerLoadFinished,
          providerKey: target.providerKey,
        );
      }
      unawaited(
        _applyCaptionsAfterStartup(
          captionResolutionTask,
          loadToken: currentToken,
        ),
      );
      await _applySubtitleOffset();
      if (_resumePending && target.isDirectPlayable) {
        await _playbackSurface.requestPlayerState();
      }

      if (!mounted || currentToken != _surfaceLoadToken) {
        return;
      }

      final resolvedDirectPlayback = target.isDirectPlayable;
      final initialPresentation = _playbackSurface.playerState.value;
      final initialHasVisibleVideo =
          resolvedDirectPlayback && initialPresentation.hasVisibleVideo;
      setState(() {
        _committedTarget = target;
        _pendingTarget = null;
        _surfaceLoading = !initialHasVisibleVideo;
        _surfaceReady = initialHasVisibleVideo;
        _error = null;
        _statusMessage = initialHasVisibleVideo
            ? 'Playing from ${target.providerLabel}.'
            : resolvedDirectPlayback
                ? 'Waiting for the first video frame from ${target.providerLabel}...'
                : 'Extracting a direct stream from ${target.providerLabel}...';
      });
      if (resolvedDirectPlayback) {
        final deferPlaybackIntentUntilResume = _resumePending &&
            switchResumePosition == null &&
            initialHasVisibleVideo;
        if (switchResumePosition != null &&
            switchResumePosition > Duration.zero) {
          _switchResumeSeekInFlight = true;
          setState(() {
            _activeSeekOperations += 1;
            _pendingSeekTarget = switchResumePosition;
            _pendingSeekMayRejectSource = true;
          });
          _scheduleSeekLoadingFallback();
          try {
            await _playbackSurface
                .seekTo(switchResumePosition)
                .timeout(const Duration(seconds: 8));
          } finally {
            _switchResumeSeekInFlight = false;
            if (mounted) {
              setState(() {
                _activeSeekOperations = math.max(0, _activeSeekOperations - 1);
              });
            }
          }
          if (!mounted || currentToken != _surfaceLoadToken) {
            return;
          }
          await _playbackSurface.requestPlayerState();
          _syncSeekLoadingState(_playbackSurface.playerState.value);
        }
        if (!deferPlaybackIntentUntilResume) {
          await _applySwitchPlaybackIntent(
            shouldRemainPaused: switchShouldRemainPaused,
          );
          if (!mounted || currentToken != _surfaceLoadToken) {
            return;
          }
          if (!_hasConfirmedPlayableTarget(target)) {
            _scheduleDirectFrameTimeout(target, loadToken: currentToken);
          }
        }
      } else {
        // Android WebView commonly blocks provider autoplay even when the page
        // and video are fully ready. Persist an explicit play intent so the
        // surface can retry it as the provider's iframe/video element appears.
        await _applySwitchPlaybackIntent(
          shouldRemainPaused: switchShouldRemainPaused,
        );
        if (!mounted || currentToken != _surfaceLoadToken) {
          return;
        }
      }
      _handlePlayerStateChanged();
      if (resolvedDirectPlayback) {
        unawaited(_playbackSurface.requestPlayerState());
      } else {
        unawaited(_primeScrubPreviewPathForCurrentContent());
      }
      unawaited(_warmEpisodeMetadata());
      _scheduleEmbedPromotionTimeout(target, loadToken: currentToken);
    } on _PlaybackSurfaceException catch (error) {
      if (!mounted || currentToken != _surfaceLoadToken) {
        return;
      }

      setState(() {
        _committedTarget = null;
        _pendingTarget = null;
        _resolvingSource = false;
        _surfaceLoading = false;
        _surfaceReady = false;
        _error = error.message;
        _statusMessage = 'Playback unavailable';
      });
    } catch (error) {
      if (!mounted || currentToken != _surfaceLoadToken) {
        return;
      }

      await _recoverFromSourceFailure(
        currentProviderIndex: target.providerIndex,
        failureKind: SourceFailureKind.load,
        failureReason: _formatPlaybackError(error),
      );
    }
  }

  Future<void> _applyCaptionsAfterStartup(
    Future<CaptionResolution> resolutionTask, {
    required int loadToken,
  }) async {
    try {
      final resolution = await resolutionTask;
      if (!mounted || loadToken != _surfaceLoadToken) {
        return;
      }
      await _playbackSurface.setCaptionTracks(
        resolution.tracks,
        selectedTrackId: resolution.selectedTrackId,
      );
      await _applySubtitleOffset();
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Deferred caption application failed.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _applySwitchPlaybackIntent({
    required bool shouldRemainPaused,
  }) async {
    if (!shouldRemainPaused) {
      await _setPlaybackPlaying(
        true,
        reason: 'load-switch-play-intent',
        updateIntent: true,
      );
      return;
    }

    await _setPlaybackPlaying(
      false,
      reason: 'load-switch-paused-intent',
      updateIntent: true,
    );
  }

  void _scheduleEmbedPromotionTimeout(
    PlaybackTarget target, {
    required int loadToken,
  }) {
    if (target.isDirectPlayable) {
      return;
    }

    final targetSignature = _playbackTargetSignature(target);
    _embedPromotionTimeoutTimer = Timer(_embedPromotionTimeout, () {
      if (!mounted || loadToken != _surfaceLoadToken || _resolvingSource) {
        return;
      }

      final activeTarget = _committedTarget;
      if (activeTarget == null ||
          activeTarget.isDirectPlayable ||
          _surfaceReady ||
          _playbackTargetSignature(activeTarget) != targetSignature) {
        return;
      }

      _surfaceLoadToken += 1;
      unawaited(
        _recoverFromSourceFailure(
          currentProviderIndex: activeTarget.providerIndex,
          failureKind: SourceFailureKind.sourceRejected,
          failureReason:
              '${activeTarget.providerLabel} never exposed a direct stream. '
              'Trying the next source...',
        ),
      );
    });
  }

  void _schedulePlaybackStartupEscape(
    PlaybackTarget target, {
    required int loadToken,
    Duration? recoveryPosition,
  }) {
    _playbackStartupEscapeTimer?.cancel();
    final targetSignature = _playbackTargetSignature(target);
    _playbackStartupEscapeTimer = Timer(_playbackStartupEscapeTimeout, () {
      _playbackStartupEscapeTimer = null;
      if (!mounted || loadToken != _surfaceLoadToken) {
        return;
      }

      final activeTarget = _currentRecoveryTarget;
      if (activeTarget == null ||
          _playbackTargetSignature(activeTarget) != targetSignature) {
        return;
      }
      if (_surfaceReady &&
          !_surfaceLoading &&
          !_resolvingSource &&
          _pendingTarget == null) {
        return;
      }

      final presentation = _playbackSurface.playerState.value;
      final preservedPosition =
          recoveryPosition != null && recoveryPosition > Duration.zero
              ? recoveryPosition
              : presentation.currentPosition > Duration.zero
                  ? presentation.currentPosition
                  : _lastTrustedPlaybackPosition;
      _logPlayerDiagnostic(
        'Playback startup watchdog abandoning hung source '
        'provider=${activeTarget.providerLabel} '
        'pending=${_pendingTarget != null} '
        'surfaceLoading=$_surfaceLoading '
        'position=$preservedPosition.',
      );
      _surfaceLoadToken += 1;
      _directFrameTimeoutTimer?.cancel();
      _embedPromotionTimeoutTimer?.cancel();
      unawaited(
        _recoverFromSourceFailure(
          currentProviderIndex: activeTarget.providerIndex,
          failureKind: SourceFailureKind.startupStall,
          failureReason:
              '${activeTarget.providerLabel} took too long to start. Trying the next source...',
          recoveryResumePosition:
              preservedPosition > Duration.zero ? preservedPosition : null,
        ),
      );
    });
  }

  void _cancelPlaybackStartupEscapeWhenReady() {
    if (!_surfaceReady ||
        _surfaceLoading ||
        _resolvingSource ||
        _pendingTarget != null) {
      return;
    }
    _playbackStartupEscapeTimer?.cancel();
    _playbackStartupEscapeTimer = null;
  }

  void _scheduleDirectFrameTimeout(
    PlaybackTarget target, {
    required int loadToken,
  }) {
    if (!target.isDirectPlayable) {
      return;
    }

    _directFrameTimeoutTimer?.cancel();
    final targetSignature = _playbackTargetSignature(target);
    _directFrameTimeoutTimer = Timer(_directFrameTimeout, () {
      if (!mounted || loadToken != _surfaceLoadToken || _resolvingSource) {
        return;
      }

      final activeTarget = _committedTarget;
      final presentation = _playbackSurface.playerState.value;
      if (activeTarget == null ||
          !activeTarget.isDirectPlayable ||
          ((_hasConfirmedPlayableTarget(activeTarget) ||
                  _isConfirmedPlayablePresentation(
                    activeTarget,
                    presentation,
                  )) &&
              !_hasTargetExpired(activeTarget)) ||
          _activeSeekOperations > 0 ||
          _pendingSeekTarget != null ||
          _playbackTargetSignature(activeTarget) != targetSignature) {
        return;
      }

      _triggerDirectNoFrameRecovery(
        activeTarget,
        presentation,
        triggerReason:
            '${activeTarget.providerLabel} never produced a video frame.',
      );
    });
  }

  Future<CaptionResolution> _resolveCaptionResolution() async {
    if (_captionResolutionInFlight != null) {
      return _captionResolutionInFlight!;
    }
    final task = _resolveCaptionResolutionInternal();
    _captionResolutionInFlight = task;
    try {
      return await task;
    } finally {
      if (identical(_captionResolutionInFlight, task)) {
        _captionResolutionInFlight = null;
      }
    }
  }

  Future<CaptionResolution> _resolveCaptionResolutionInternal() async {
    final mediaItem = (
      title: _summary?.title ?? widget.initialSummary?.title ?? 'Unknown',
      imdbId: null as String?,
      tmdbId: widget.tmdbId as int?,
    );
    cheriflixLog(
      'subtitles',
      'Searching for subtitles. mediaType=${widget.mediaType.name} '
          'tmdbId=${mediaItem.tmdbId ?? "unknown"}',
    );
    final tracks = <CaptionTrack>[];
    final overrideUrl = widget.playbackSettings.subtitleUrl?.trim();
    if (overrideUrl != null && overrideUrl.isNotEmpty) {
      tracks.add(
        CaptionTrack(
          id: 'profile-override',
          label: 'Profile Override',
          languageCode: widget.languageCode,
          kind: CaptionTrackKind.override,
          format: CaptionTrackFormat.vtt,
          url: Uri.parse(overrideUrl),
          isDefault: true,
        ),
      );
    }

    CaptionResolution serviceResolution;
    try {
      serviceResolution = await widget.captionService
          .resolveCaptions(
            tmdbId: widget.tmdbId,
            mediaType: widget.mediaType,
            languageCode: widget.languageCode,
            seasonNumber: _isTvEpisodePlayer ? _activeSeasonNumber : null,
            episodeNumber: _isTvEpisodePlayer ? _activeEpisodeNumber : null,
            imdbId: mediaItem.imdbId,
            title: mediaItem.title,
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      serviceResolution = const CaptionResolution(
        failureCode: CaptionFailureCode.serviceError,
      );
    }
    cheriflixLog(
      'subtitles',
      'Service returned ${serviceResolution.tracks.length} tracks. '
          'failureCode=${serviceResolution.failureCode}',
    );

    final preferredTracks = _preferHiSubtitles
        ? serviceResolution.tracks
            .where((track) => track.isHI)
            .toList(growable: false)
        : serviceResolution.tracks
            .where((track) => !track.isHI)
            .toList(growable: false);
    final sourceTracks =
        preferredTracks.isNotEmpty ? preferredTracks : serviceResolution.tracks;
    final backendTracks = sourceTracks.map((track) {
      return track.copyWith(isDefault: false);
    });
    tracks.addAll(backendTracks);

    final selectedTrackId = tracks.isEmpty
        ? null
        : tracks
            .firstWhere(
              (track) =>
                  track.id == 'profile-override' ||
                  track.id == serviceResolution.selectedTrackId ||
                  track.isDefault,
              orElse: () => tracks.first,
            )
            .id;
    final normalizedTracks = tracks
        .map((track) => track.copyWith(isDefault: track.id == selectedTrackId))
        .toList(growable: false);

    final resolution = CaptionResolution(
      tracks: normalizedTracks,
      selectedTrackId: selectedTrackId,
      failureCode:
          normalizedTracks.isEmpty ? serviceResolution.failureCode : null,
    );
    _captionResolution = resolution;
    return resolution;
  }

  Future<void> _ensureSurfaceInitialized() async {
    if (_surfaceInitialized) {
      return;
    }

    try {
      _logPlayerDiagnostic('Initializing playback surface...');
      await _playbackSurface.initialize();
      _surfaceInitialized = true;
      _logPlayerDiagnostic('Playback surface initialized successfully.');
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Playback surface initialization failed.',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Set<String> _allowedHostSuffixesForTarget(Uri uri) {
    final host = uri.host.trim().toLowerCase();
    final normalized = <String>{
      ..._trustedPlaybackHostSuffixes,
    };

    if (host.isNotEmpty) {
      normalized.add(host);
      if (host.startsWith('www.')) {
        normalized.add(host.substring(4));
      } else {
        normalized.add('www.$host');
      }
    }

    return normalized;
  }

  String _loadingStatusMessageForTarget(PlaybackTarget target) {
    return target.isDirectPlayable
        ? 'Opening ${target.providerLabel} in the native player...'
        : 'Extracting a direct stream from ${target.providerLabel}...';
  }

  PlaybackSourceKind _directSourceKindForUri(Uri uri) {
    return uri.toString().toLowerCase().contains('.m3u8')
        ? PlaybackSourceKind.hls
        : PlaybackSourceKind.file;
  }

  String _formatPlaybackError(Object error) {
    if (error is _PlaybackSurfaceException) {
      return error.message;
    }

    if (error is SourceResolverUnavailableException) {
      return error.message;
    }

    if (error is PlatformException && error.message != null) {
      return error.message!;
    }

    return 'The in-app player could not open this source.';
  }

  Future<void> _haltSurfacePlaybackForRecovery() async {
    try {
      await _playbackSurface.quietStop().timeout(
            const Duration(seconds: 3),
          );
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Failed to quiet-stop playback surface before recovery.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _handlePlaybackSurfaceEvent(PlaybackSurfaceEvent event) {
    if (!mounted || _resolvingSource) {
      return;
    }

    if (event is PlaybackSurfaceBlockedNavigation) {
      final currentTarget = _currentRecoveryTarget;
      if (currentTarget == null ||
          currentTarget.isDirectPlayable ||
          currentTarget.sourceKind != PlaybackSourceKind.embed) {
        return;
      }
      if (event.keepCurrentPlayback) {
        return;
      }

      _surfaceLoadToken += 1;
      unawaited(
        _recoverFromSourceFailure(
          currentProviderIndex: currentTarget.providerIndex,
          failureKind: SourceFailureKind.blockedNavigation,
          blockedHost: event.uri.host.trim().toLowerCase(),
        ),
      );
      return;
    }

    if (event is PlaybackSurfaceDirectSourceDetected) {
      unawaited(_promoteDetectedDirectSource(event));
      return;
    }

    if (event is! PlaybackSurfaceSourceRejected) {
      return;
    }

    final currentTarget = _currentRecoveryTarget;
    final currentTargetSignature =
        currentTarget == null ? null : _playbackTargetSignature(currentTarget);
    if (currentTargetSignature != null &&
        currentTargetSignature == _embedPromotedDirectTargetSignature) {
      return;
    }
    final waitingForDirectExtraction = currentTarget != null &&
        currentTarget.sourceKind == PlaybackSourceKind.embed &&
        !currentTarget.isDirectPlayable;
    if ((_surfaceLoading || !_surfaceReady) && !waitingForDirectExtraction) {
      return;
    }

    final reason = event.reason.trim();
    if (reason.isEmpty) {
      return;
    }

    if (currentTarget != null &&
        _hasConfirmedPlayableTarget(currentTarget) &&
        !_hasTargetExpired(currentTarget)) {
      _logPlayerDiagnostic(
        'Ignoring source rejection after playback was confirmed '
        'provider=${currentTarget.providerLabel} reason=$reason',
      );
      return;
    }

    _surfaceLoadToken += 1;
    if (currentTarget == null) {
      return;
    }

    unawaited(
      _recoverFromSourceFailure(
        currentProviderIndex: currentTarget.providerIndex,
        failureKind: SourceFailureKind.sourceRejected,
        failureReason: reason,
      ),
    );
  }

  Future<void> _promoteDetectedDirectSource(
    PlaybackSurfaceDirectSourceDetected event,
  ) async {
    final activeTarget = _pendingTarget ?? _committedTarget;
    if (activeTarget == null ||
        activeTarget.sourceKind != PlaybackSourceKind.embed) {
      return;
    }
    final diagnosticSessionId = activeTarget.diagnosticSessionId;
    if (diagnosticSessionId != null) {
      PlaybackDiagnostics.instance.record(
        sessionId: diagnosticSessionId,
        stage: PlaybackDiagnosticStage.manifestReady,
        providerKey: activeTarget.providerKey,
        outcome: 'detected-in-controlled-embed',
        details: <String, Object?>{'host': event.uri.host},
      );
    }

    // VidNest uses a custom HLS.js/MSE pipeline whose advertised playlist
    // contains PNG-wrapped media chunks. It plays correctly in the provider
    // WebView, but promoting that URL to the native decoder always fails.
    if (activeTarget.providerKey == 'vidnest') {
      final wrappedUri = await HlsUnwrapProxy.instance.wrap(
        event.uri,
        headers: event.httpHeaders,
      );
      await _loadPlaybackTarget(
        PlaybackTarget(
          uri: wrappedUri,
          providerKey: activeTarget.providerKey,
          providerLabel: activeTarget.providerLabel,
          providerIndex: activeTarget.providerIndex,
          sourceKind: PlaybackSourceKind.hls,
          pageUri: activeTarget.pageUri ?? activeTarget.uri,
          diagnosticSessionId: activeTarget.diagnosticSessionId,
          offlineStorageAllowed: activeTarget.offlineStorageAllowed,
          qualityLabel: activeTarget.qualityLabel,
          bitrateBitsPerSecond: activeTarget.bitrateBitsPerSecond,
        ),
        fromEmbedPromotion: true,
      );
      return;
    }

    final signature = _directSourceSignature(
      providerIndex: activeTarget.providerIndex,
      uri: event.uri,
      sourceKind: event.sourceKind,
      httpHeaders: event.httpHeaders,
      pageUri: event.pageUri,
    );
    if (signature == _lastPromotedDirectSourceSignature) {
      return;
    }

    _lastPromotedDirectSourceSignature = signature;
    await _loadPlaybackTarget(
      PlaybackTarget(
        uri: event.uri,
        providerKey: activeTarget.providerKey,
        providerLabel: activeTarget.providerLabel,
        providerIndex: activeTarget.providerIndex,
        sourceKind: event.sourceKind,
        httpHeaders: event.httpHeaders,
        pageUri: event.pageUri ?? activeTarget.pageUri ?? activeTarget.uri,
        diagnosticSessionId: activeTarget.diagnosticSessionId,
        offlineStorageAllowed: activeTarget.offlineStorageAllowed,
        qualityLabel: activeTarget.qualityLabel,
        bitrateBitsPerSecond: activeTarget.bitrateBitsPerSecond,
      ),
      fromEmbedPromotion: true,
    );
  }

  String _directSourceSignature({
    required int providerIndex,
    required Uri uri,
    required PlaybackSourceKind sourceKind,
    required Map<String, String> httpHeaders,
    Uri? pageUri,
  }) {
    final normalizedHeaders = httpHeaders.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    return <String>[
      '$providerIndex',
      sourceKind.name,
      uri.toString(),
      pageUri?.toString() ?? '',
      for (final entry in normalizedHeaders) '${entry.key}=${entry.value}',
    ].join('|');
  }

  void _togglePlayPause() {
    _registerChromeInteraction();
    unawaited(_togglePlayPauseAndWait().catchError((_) {}));
  }

  Future<void> _togglePlayPauseAndWait() async {
    final shouldPlay =
        _isPresentationPausedForUi(_playbackSurface.playerState.value);
    await _setPlaybackPlaying(
      shouldPlay,
      reason: 'user-toggle',
      updateIntent: true,
    );
  }

  Future<void> _setPlaybackPlaying(
    bool shouldPlay, {
    required String reason,
    required bool updateIntent,
  }) async {
    final isViewerCommand =
        reason == 'user-toggle' || reason.startsWith('shortcut-');
    final pauseStartedAt = _viewerPauseStartedAt;
    final pauseExceededRefreshThreshold = _viewerPauseNeedsRefresh;
    if (updateIntent) {
      _intendedPlaybackPlaying = shouldPlay;
      if (!shouldPlay && isViewerCommand) {
        _viewerPauseStartedAt = DateTime.now();
        _viewerPauseNeedsRefresh = false;
        _longPauseRefreshArmTimer?.cancel();
        _longPauseRefreshArmTimer = Timer(
          _longPauseStreamRefreshThreshold,
          () {
            if (mounted && !_intendedPlaybackPlaying) {
              _viewerPauseNeedsRefresh = true;
            }
          },
        );
      } else if (shouldPlay && isViewerCommand) {
        _viewerPauseStartedAt = null;
        _viewerPauseNeedsRefresh = false;
        _longPauseRefreshArmTimer?.cancel();
        _longPauseRefreshArmTimer = null;
      }
    }
    if (shouldPlay &&
        isViewerCommand &&
        _shouldRefreshStreamAfterPause(
          pauseStartedAt,
          pauseExceededRefreshThreshold: pauseExceededRefreshThreshold,
        )) {
      await _refreshStreamAfterLongPause(reason);
      if (mounted) {
        _handlePlayerStateChanged();
      }
      return;
    }
    _logPlayerDiagnostic(
      'Playback command reason=$reason '
      'targetPlaying=$shouldPlay '
      'updateIntent=$updateIntent '
      'intendedPlaying=$_intendedPlaybackPlaying',
    );
    try {
      if (shouldPlay) {
        await _playbackSurface.play();
      } else {
        await _playbackSurface.pause();
      }
      await _playbackSurface.requestPlayerState();
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Playback command failed reason=$reason targetPlaying=$shouldPlay.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (shouldPlay) {
      await _recoverPlaybackIfNeeded(reason, force: true);
    }
    if (mounted) {
      _handlePlayerStateChanged();
    }
  }

  bool _shouldRefreshStreamAfterPause(
    DateTime? pauseStartedAt, {
    required bool pauseExceededRefreshThreshold,
  }) {
    final target = _committedTarget;
    if (target == null || !_surfaceReady || _longPauseRefreshInFlight) {
      return false;
    }
    if (_hasTargetExpired(target)) {
      return true;
    }
    return pauseExceededRefreshThreshold ||
        (pauseStartedAt != null &&
            DateTime.now().difference(pauseStartedAt) >=
                _longPauseStreamRefreshThreshold);
  }

  Future<void> _refreshStreamAfterLongPause(String reason) async {
    final target = _committedTarget;
    if (target == null || _longPauseRefreshInFlight || !mounted) {
      return;
    }
    final presentation = _playbackSurface.playerState.value;
    final resumePosition =
        _lastTrustedPlaybackPosition > presentation.currentPosition
            ? _lastTrustedPlaybackPosition
            : presentation.currentPosition;
    _longPauseRefreshInFlight = true;
    try {
      _logPlayerDiagnostic(
        'Refreshing stream after a long pause reason=$reason '
        'provider=${target.providerLabel} position=$resumePosition.',
      );
      setState(() {
        _resolvingSource = true;
        _surfaceLoading = true;
        _pendingTarget = null;
        _error = null;
        _statusMessage = 'Refreshing the stream after a long pause...';
      });
      await _haltSurfacePlaybackForRecovery();
      if (!mounted) {
        return;
      }
      PlaybackTarget? refreshedTarget;
      try {
        refreshedTarget = await widget.playbackProvider.resolveSpecificSource(
          profileId: widget.profileId,
          tmdbId: widget.tmdbId,
          mediaType: widget.mediaType,
          providerIndex: target.providerIndex,
          seasonNumber: _isTvEpisodePlayer ? _activeSeasonNumber : null,
          episodeNumber: _isTvEpisodePlayer ? _activeEpisodeNumber : null,
          preferredAudioLanguage: _effectiveAudioLanguage,
          probeCandidate: true,
        );
      } catch (_) {
        refreshedTarget = null;
      }
      if (!mounted) {
        return;
      }
      if (refreshedTarget == null) {
        await _recoverFromSourceFailure(
          currentProviderIndex: target.providerIndex,
          failureKind: SourceFailureKind.expired,
          blockedStreamHost: target.uri.host,
          failureReason:
              '${target.providerLabel} session expired while paused. Switching servers...',
          recoveryResumePosition: resumePosition,
          skipInternalFallbacks: true,
        );
        return;
      }
      await _loadPlaybackTarget(
        refreshedTarget,
        switchResumePosition:
            resumePosition > Duration.zero ? resumePosition : null,
        switchShouldRemainPaused: false,
      );
    } finally {
      _longPauseRefreshInFlight = false;
    }
  }

  bool get _manualSeekProtectionActive {
    final protectedUntil = _manualSeekProtectionUntil;
    return protectedUntil != null && DateTime.now().isBefore(protectedUntil);
  }

  bool _isUnexpectedPlaybackPositionReset(
    PlaybackPresentation presentation,
  ) {
    if (_manualSeekProtectionActive ||
        _suppressProgressReporting ||
        !_surfaceReady ||
        _surfaceLoading ||
        _resolvingSource ||
        _pendingTarget != null ||
        _resumePending ||
        _resumeIntentInFlight ||
        _switchResumeSeekInFlight ||
        _pendingSeekTarget != null ||
        _activeSeekOperations > 0 ||
        !_intendedPlaybackPlaying ||
        _lastTrustedPlaybackPosition < _resumeProgressGuardThreshold) {
      return false;
    }
    return _lastTrustedPlaybackPosition - presentation.currentPosition >=
        _unexpectedPositionResetThreshold;
  }

  bool _trackTrustedPlaybackPosition(PlaybackPresentation presentation) {
    if (_isUnexpectedPlaybackPositionReset(presentation)) {
      if (_stallRecoveryInFlight || _seekRecoveryInFlight) {
        return true;
      }
      final target = _committedTarget;
      if (target != null && target.isDirectPlayable) {
        final trustedPosition = _lastTrustedPlaybackPosition;
        _logPlayerDiagnostic(
          'Detected unexplained playback timestamp reset '
          'reported=${presentation.currentPosition} '
          'trusted=$trustedPosition provider=${target.providerLabel}.',
        );
        unawaited(
          _recoverStalledPlayback(
            target,
            presentation,
            recoveryPosition: trustedPosition,
            preferDifferentStream: true,
          ),
        );
      }
      return true;
    }
    if (!_surfaceLoading &&
        !_resolvingSource &&
        _pendingTarget == null &&
        !_resumePending &&
        presentation.currentPosition > _lastTrustedPlaybackPosition) {
      _lastTrustedPlaybackPosition = presentation.currentPosition;
    }
    return false;
  }

  bool _trackRapidBackwardPlaybackJumps(
    PlaybackPresentation presentation,
  ) {
    final target = _committedTarget;
    final eligible = target != null &&
        target.isDirectPlayable &&
        !_suppressProgressReporting &&
        _surfaceReady &&
        !_surfaceLoading &&
        !_resolvingSource &&
        _pendingTarget == null &&
        !_resumePending &&
        !_resumeIntentInFlight &&
        !_switchResumeSeekInFlight &&
        _pendingSeekTarget == null &&
        _activeSeekOperations == 0 &&
        _playerModalOverlayDepth == 0 &&
        _intendedPlaybackPlaying &&
        !_seekRecoveryInFlight &&
        !_stallRecoveryInFlight &&
        !_manualSeekProtectionActive &&
        !presentation.isBuffering &&
        presentation.hasVisibleVideo;
    if (!eligible) {
      _lastObservedPlaybackPosition = presentation.currentPosition;
      _rapidBackwardJumpWindowStartedAt = null;
      _rapidBackwardJumpCount = 0;
      return false;
    }

    final previousPosition = _lastObservedPlaybackPosition;
    final currentPosition = presentation.currentPosition;
    _lastObservedPlaybackPosition = currentPosition;
    if (previousPosition == null) {
      return false;
    }
    final backwardJump = previousPosition - currentPosition;
    if (backwardJump < _rapidBackwardJumpTolerance ||
        backwardJump >= _unexpectedPositionResetThreshold) {
      return false;
    }

    final now = DateTime.now();
    final windowStartedAt = _rapidBackwardJumpWindowStartedAt;
    if (windowStartedAt == null ||
        now.difference(windowStartedAt) > _rapidBackwardJumpWindow) {
      _rapidBackwardJumpWindowStartedAt = now;
      _rapidBackwardJumpCount = 1;
    } else {
      _rapidBackwardJumpCount += 1;
    }
    _logPlayerDiagnostic(
      'Observed rapid backward playback jump '
      'provider=${target.providerLabel} '
      'previous=$previousPosition current=$currentPosition '
      'count=$_rapidBackwardJumpCount.',
    );
    if (_rapidBackwardJumpCount < _rapidBackwardJumpRecoveryCount) {
      return true;
    }

    _rapidBackwardJumpWindowStartedAt = null;
    _rapidBackwardJumpCount = 0;
    final recoveryPosition = _lastTrustedPlaybackPosition > previousPosition
        ? _lastTrustedPlaybackPosition
        : previousPosition;
    unawaited(
      _recoverStalledPlayback(
        target,
        presentation,
        recoveryPosition: recoveryPosition,
        preferDifferentStream: true,
        retryCurrentProviderFirst: true,
      ),
    );
    return true;
  }

  void _resetPlaybackStallWatchdog({bool resetRecoveryAttempts = true}) {
    _stallWatchdogPosition = null;
    _lastObservedPlaybackPosition = null;
    _rapidBackwardJumpWindowStartedAt = null;
    _rapidBackwardJumpCount = 0;
    _stallWatchdogTicks = 0;
    _stallBackwardJumpCount = 0;
    if (resetRecoveryAttempts) {
      _stallSameSourceReloads = 0;
    }
  }

  int? get _expectedRuntimeMinutesForActiveContent {
    if (_isTvEpisodePlayer) {
      final episodeRuntime = _activeEpisodeSummary?.runtimeMinutes;
      if (episodeRuntime != null && episodeRuntime > 0) {
        return episodeRuntime;
      }
    }
    final summaryRuntime =
        _summary?.runtimeMinutes ?? widget.initialSummary?.runtimeMinutes;
    return summaryRuntime != null && summaryRuntime > 0 ? summaryRuntime : null;
  }

  bool _isCredibleNaturalCompletion(PlaybackPresentation presentation) {
    if (!presentation.isCompleted || !presentation.isPaused) {
      return false;
    }
    final expectedRuntimeMinutes = _expectedRuntimeMinutesForActiveContent;
    if (expectedRuntimeMinutes == null) {
      // Without catalog runtime evidence, prefer recovering a possible false
      // end-of-file over trapping the viewer on the final decoded frame.
      return false;
    }
    final earliestCredibleEnd =
        Duration(minutes: expectedRuntimeMinutes) - const Duration(minutes: 4);
    return presentation.currentPosition >= earliestCredibleEnd &&
        presentation.totalDuration >= earliestCredibleEnd;
  }

  void _syncUnexpectedStopRecovery(PlaybackPresentation presentation) {
    final target = _committedTarget;
    final shouldRecover = _appLifecycleActive &&
        target != null &&
        target.isDirectPlayable &&
        _playerModalOverlayDepth == 0 &&
        !_stallRecoveryInFlight &&
        !_seekRecoveryInFlight &&
        !_unexpectedStopRecoveryInFlight &&
        !_isCredibleNaturalCompletion(presentation) &&
        _shouldRecoverPlayback(presentation);
    if (!shouldRecover) {
      _unexpectedStopRecoveryTimer?.cancel();
      _unexpectedStopRecoveryTimer = null;
      return;
    }
    if (_unexpectedStopRecoveryTimer != null) {
      return;
    }
    _unexpectedStopRecoveryTimer = Timer(
      const Duration(milliseconds: 700),
      () {
        _unexpectedStopRecoveryTimer = null;
        unawaited(_recoverUnexpectedStoppedPlayback());
      },
    );
  }

  Future<void> _recoverUnexpectedStoppedPlayback() async {
    final target = _committedTarget;
    var presentation = _playbackSurface.playerState.value;
    if (_unexpectedStopRecoveryInFlight ||
        _seekRecoveryInFlight ||
        target == null ||
        !target.isDirectPlayable ||
        !_appLifecycleActive ||
        _playerModalOverlayDepth > 0 ||
        _isCredibleNaturalCompletion(presentation) ||
        !_shouldRecoverPlayback(presentation)) {
      return;
    }
    _unexpectedStopRecoveryInFlight = true;
    try {
      final recoveryPosition =
          _lastTrustedPlaybackPosition > presentation.currentPosition
              ? _lastTrustedPlaybackPosition
              : presentation.currentPosition;
      _logPlayerDiagnostic(
        'Detected an unrequested player stop; attempting immediate recovery '
        'provider=${target.providerLabel} position=$recoveryPosition.',
      );
      if (presentation.isCompleted) {
        await _recoverStalledPlayback(
          target,
          presentation,
          recoveryPosition: recoveryPosition,
          preferDifferentStream: true,
        );
        return;
      }
      await _recoverPlaybackIfNeeded('unexpected-player-stop', force: true);
      if (!mounted) {
        return;
      }
      await _playbackSurface.requestPlayerState();
      presentation = _playbackSurface.playerState.value;
      if (!_shouldRecoverPlayback(presentation)) {
        return;
      }
      await _recoverStalledPlayback(
        target,
        presentation,
        recoveryPosition: recoveryPosition,
        preferDifferentStream: true,
      );
    } finally {
      _unexpectedStopRecoveryInFlight = false;
    }
  }

  void _checkForPlaybackStall() {
    final target = _committedTarget;
    final presentation = _playbackSurface.playerState.value;
    if (!_appLifecycleActive ||
        !mounted ||
        _suppressProgressReporting ||
        target == null ||
        !target.isDirectPlayable ||
        !_hasConfirmedPlayableTarget(target) ||
        !_surfaceReady ||
        _surfaceLoading ||
        _resolvingSource ||
        _pendingTarget != null ||
        _resumePending ||
        _resumeIntentInFlight ||
        _pendingSeekTarget != null ||
        _activeSeekOperations > 0 ||
        _playerModalOverlayDepth > 0 ||
        _nextEpisodePromptVisible ||
        !_intendedPlaybackPlaying ||
        _seekRecoveryInFlight ||
        _stallRecoveryInFlight) {
      _resetPlaybackStallWatchdog(resetRecoveryAttempts: false);
      return;
    }

    if (_isCredibleNaturalCompletion(presentation)) {
      _resetPlaybackStallWatchdog(resetRecoveryAttempts: false);
      return;
    }

    final signature = _playbackTargetSignature(target);
    if (_stallWatchdogTargetSignature != signature) {
      _stallWatchdogTargetSignature = signature;
      _resetPlaybackStallWatchdog();
      _stallWatchdogPosition = presentation.currentPosition;
      return;
    }

    final previousPosition = _stallWatchdogPosition;
    final currentPosition = presentation.currentPosition;
    if (previousPosition != null &&
        previousPosition - currentPosition >=
            _unexpectedPositionResetThreshold) {
      _stallWatchdogTicks = 0;
      unawaited(
        _recoverStalledPlayback(
          target,
          presentation,
          recoveryPosition: _lastTrustedPlaybackPosition > previousPosition
              ? _lastTrustedPlaybackPosition
              : previousPosition,
          preferDifferentStream: true,
        ),
      );
      return;
    }
    if (previousPosition == null) {
      _stallWatchdogPosition = currentPosition;
      _stallWatchdogTicks = 0;
      return;
    }
    if (currentPosition < previousPosition) {
      _stallWatchdogPosition = currentPosition;
      _stallWatchdogTicks = 0;
      _stallBackwardJumpCount += 1;
      if (_stallBackwardJumpCount >= 2) {
        _stallBackwardJumpCount = 0;
        unawaited(
          _recoverStalledPlayback(
            target,
            presentation,
            recoveryPosition: _lastTrustedPlaybackPosition > previousPosition
                ? _lastTrustedPlaybackPosition
                : previousPosition,
            preferDifferentStream: true,
          ),
        );
      }
      return;
    }
    if (currentPosition - previousPosition >=
        const Duration(milliseconds: 750)) {
      _stallWatchdogPosition = currentPosition;
      _stallWatchdogTicks = 0;
      if (currentPosition >= _lastTrustedPlaybackPosition) {
        _stallBackwardJumpCount = 0;
      }
      _stallSameSourceReloads = 0;
      return;
    }

    _stallWatchdogTicks += 1;
    final stallThreshold = presentation.isBuffering
        ? _playbackBufferingWatchdogTicks
        : _playbackStoppedWatchdogTicks;
    if (_stallWatchdogTicks == stallThreshold) {
      if (presentation.isCompleted &&
          !_isCredibleNaturalCompletion(presentation)) {
        _stallWatchdogTicks = 0;
        unawaited(
          _recoverStalledPlayback(
            target,
            presentation,
            preferDifferentStream: true,
          ),
        );
      } else {
        unawaited(_nudgeStalledPlayback(target, presentation));
      }
      return;
    }
    if (_stallWatchdogTicks <
        stallThreshold + _playbackStallHardRecoveryDelayTicks) {
      return;
    }

    _stallWatchdogTicks = 0;
    unawaited(_recoverStalledPlayback(target, presentation));
  }

  Future<void> _nudgeStalledPlayback(
    PlaybackTarget target,
    PlaybackPresentation presentation,
  ) async {
    if (_stallRecoveryInFlight || !mounted) {
      return;
    }
    _logPlayerDiagnostic(
      'Playback watchdog nudging stalled source '
      'provider=${target.providerLabel} '
      'position=${presentation.currentPosition} '
      'buffering=${presentation.isBuffering}.',
    );
    try {
      await _playbackSurface.play();
      await _playbackSurface.requestPlayerState();
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Playback watchdog nudge failed.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _recoverStalledPlayback(
    PlaybackTarget target,
    PlaybackPresentation presentation, {
    Duration? recoveryPosition,
    bool preferDifferentStream = false,
    bool retryCurrentProviderFirst = false,
  }) async {
    if (_stallRecoveryInFlight ||
        !mounted ||
        _committedTarget != target ||
        !_intendedPlaybackPlaying) {
      return;
    }
    final trustedRecoveryPosition = recoveryPosition ??
        (presentation.currentPosition > Duration.zero
            ? presentation.currentPosition
            : _lastTrustedPlaybackPosition);
    _stallRecoveryInFlight = true;
    try {
      final canSafelyReloadSameSource =
          target.sourceKind == PlaybackSourceKind.file &&
              target.uri.scheme == 'file';
      if (!preferDifferentStream &&
          canSafelyReloadSameSource &&
          _stallSameSourceReloads == 0) {
        _stallSameSourceReloads = 1;
        _logPlayerDiagnostic(
          'Playback watchdog reloading stalled source at same position '
          'provider=${target.providerLabel} '
          'position=$trustedRecoveryPosition.',
        );
        await _haltSurfacePlaybackForRecovery();
        if (!mounted || _committedTarget != target) {
          return;
        }
        await _loadPlaybackTarget(
          target,
          switchResumePosition: trustedRecoveryPosition > Duration.zero
              ? trustedRecoveryPosition
              : null,
          switchShouldRemainPaused: false,
        );
        return;
      }

      _logPlayerDiagnostic(
        'Playback watchdog rotating persistently stalled source '
        'provider=${target.providerLabel} '
        'position=${presentation.currentPosition}.',
      );
      _surfaceLoadToken += 1;
      if (preferDifferentStream &&
          retryCurrentProviderFirst &&
          _loopRecoveryRetriedProviderIndexes.add(target.providerIndex)) {
        if (target.fallbackUris.isNotEmpty) {
          await _recoverFromSourceFailure(
            currentProviderIndex: target.providerIndex,
            failureKind: SourceFailureKind.load,
            failureReason:
                '${target.providerLabel} looped. Trying another stream from the same server...',
            recoveryResumePosition: trustedRecoveryPosition,
          );
          return;
        }

        _logPlayerDiagnostic(
          'Refreshing the only known stream for looping provider '
          'provider=${target.providerLabel} position=$trustedRecoveryPosition.',
        );
        await _haltSurfacePlaybackForRecovery();
        if (!mounted || _committedTarget != target) {
          return;
        }
        setState(() {
          _resolvingSource = true;
          _surfaceLoading = true;
          _pendingTarget = null;
          _error = null;
          _statusMessage =
              'Refreshing ${target.providerLabel} before switching servers...';
        });
        PlaybackTarget? refreshedTarget;
        try {
          refreshedTarget = await widget.playbackProvider.resolveSpecificSource(
            profileId: widget.profileId,
            tmdbId: widget.tmdbId,
            mediaType: widget.mediaType,
            providerIndex: target.providerIndex,
            seasonNumber: _isTvEpisodePlayer ? _activeSeasonNumber : null,
            episodeNumber: _isTvEpisodePlayer ? _activeEpisodeNumber : null,
            preferredAudioLanguage: _effectiveAudioLanguage,
            probeCandidate: true,
          );
        } catch (_) {
          refreshedTarget = null;
        }
        if (!mounted) {
          return;
        }
        if (refreshedTarget != null) {
          setState(() {
            _pendingTarget = refreshedTarget;
            _resolvingSource = false;
            _surfaceLoading = true;
            _error = null;
            _statusMessage = _loadingStatusMessageForTarget(refreshedTarget!);
          });
          await _loadPlaybackTarget(
            refreshedTarget,
            switchResumePosition: trustedRecoveryPosition > Duration.zero
                ? trustedRecoveryPosition
                : null,
            switchShouldRemainPaused: false,
          );
          return;
        }
      }

      await _recoverFromSourceFailure(
        currentProviderIndex: target.providerIndex,
        failureKind: SourceFailureKind.playbackStall,
        blockedStreamHost: preferDifferentStream ? target.uri.host : null,
        failureReason: preferDifferentStream
            ? '${target.providerLabel} ended the video early. Switching servers...'
            : '${target.providerLabel} stopped responding. Trying a backup stream...',
        recoveryResumePosition: trustedRecoveryPosition,
        skipInternalFallbacks: preferDifferentStream,
      );
    } finally {
      _stallRecoveryInFlight = false;
    }
  }

  Future<void> _recoverPlaybackIfNeeded(
    String reason, {
    bool force = false,
  }) async {
    if (!_shouldRecoverPlayback(_playbackSurface.playerState.value)) {
      return;
    }
    if (_playbackRecoveryInFlight) {
      return;
    }
    final now = DateTime.now();
    final lastRecovery = _lastPlaybackRecoveryAt;
    if (!force &&
        lastRecovery != null &&
        now.difference(lastRecovery) < const Duration(milliseconds: 450)) {
      return;
    }
    _playbackRecoveryInFlight = true;
    _lastPlaybackRecoveryAt = now;
    try {
      _logPlayerDiagnostic(
        'Recovering diverged playback state reason=$reason '
        'position=${_playbackSurface.playerState.value.currentPosition.inMilliseconds}ms',
      );
      await _playbackSurface.play();
      await _playbackSurface.requestPlayerState();
      if (!_shouldRecoverPlayback(_playbackSurface.playerState.value)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await _playbackSurface.requestPlayerState();
      if (!_shouldRecoverPlayback(_playbackSurface.playerState.value)) {
        return;
      }
      await _playbackSurface.attemptAutoplay();
      await Future<void>.delayed(const Duration(milliseconds: 180));
      await _playbackSurface.requestPlayerState();
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Playback recovery failed reason=$reason.',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _playbackRecoveryInFlight = false;
    }
  }

  bool _shouldRecoverPlayback(PlaybackPresentation presentation) {
    if (!_surfaceReady ||
        _suppressProgressReporting ||
        _surfaceLoading ||
        _resolvingSource ||
        _pendingTarget != null ||
        _resumePending ||
        _resumeIntentInFlight ||
        _pendingSeekTarget != null ||
        _activeSeekOperations > 0 ||
        !_intendedPlaybackPlaying ||
        !mounted) {
      return false;
    }
    if (!_isPresentationPausedForUi(presentation) || presentation.isBuffering) {
      return false;
    }
    final totalDuration = presentation.totalDuration;
    if (totalDuration > _resumeNearEndThreshold &&
        totalDuration - presentation.currentPosition <=
            _resumeNearEndThreshold) {
      return false;
    }
    return true;
  }

  Duration get _viewerSeekBasePosition =>
      _pendingSeekTarget ?? _playbackSurface.playerState.value.currentPosition;

  Future<void> _seekBackward() async {
    _registerChromeInteraction();
    _queueViewerSeek(
      _clampSeekTarget(
        _viewerSeekBasePosition - const Duration(seconds: 10),
      ),
    );
  }

  Future<void> _seekForward() async {
    _registerChromeInteraction();
    _queueViewerSeek(
      _clampSeekTarget(
        _viewerSeekBasePosition + const Duration(seconds: 10),
      ),
    );
  }

  Future<void> _seekToPosition(Duration position) async {
    _registerChromeInteraction();
    _queueViewerSeek(
      _clampSeekTarget(position),
      delay: Duration.zero,
    );
  }

  Duration _clampSeekTarget(Duration position) {
    final totalDuration = _playbackSurface.playerState.value.totalDuration;
    if (position <= Duration.zero) {
      return Duration.zero;
    }
    if (totalDuration > Duration.zero && position >= totalDuration) {
      return totalDuration;
    }
    return position;
  }

  void _queueViewerSeek(
    Duration target, {
    Duration delay = _viewerSeekDebounceDelay,
  }) {
    if (!mounted) {
      return;
    }
    ++_manualSeekGeneration;
    _manualSeekProtectionUntil =
        DateTime.now().add(const Duration(seconds: 30));

    // Viewer intent wins over startup resume and any older decoder response.
    _clearResumeAnchor();
    _clearPostSeekRegressionGuard();
    _cancelSeekLoadingFallback();
    setState(() {
      _pendingSeekTarget = target;
      _pendingSeekMayRejectSource = false;
    });
    if (delay == Duration.zero) {
      _viewerSeekDebounceTimer?.cancel();
      _viewerSeekDebounceTimer = null;
      unawaited(_commitQueuedViewerSeek(_manualSeekGeneration));
    } else {
      _scheduleQueuedViewerSeekCommit(delay: delay);
    }
  }

  void _scheduleQueuedViewerSeekCommit({required Duration delay}) {
    _viewerSeekDebounceTimer?.cancel();
    final generation = _manualSeekGeneration;
    _viewerSeekDebounceTimer = Timer(delay, () {
      _viewerSeekDebounceTimer = null;
      unawaited(_commitQueuedViewerSeek(generation));
    });
  }

  Future<void> _commitQueuedViewerSeek(int generation) async {
    if (!mounted ||
        generation != _manualSeekGeneration ||
        _pendingSeekTarget == null) {
      return;
    }
    if (_viewerSeekCommitInFlight || _manualSeekRetryInFlight) {
      _viewerSeekCommitQueued = true;
      return;
    }

    final target = _pendingSeekTarget!;
    _viewerSeekCommitInFlight = true;
    _viewerSeekCommitQueued = false;
    setState(() {
      _activeSeekOperations += 1;
    });

    try {
      // Exactly one absolute seek reaches the decoder for a burst of remote
      // presses. This prevents out-of-order completions and random snapbacks.
      await _playbackSurface.seekTo(target).timeout(const Duration(seconds: 8));
      if (mounted && generation == _manualSeekGeneration) {
        await _playbackSurface.requestPlayerState();
      }
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Viewer seek did not settle; keeping the current source.',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _viewerSeekCommitInFlight = false;
      if (mounted) {
        setState(() {
          _activeSeekOperations = math.max(0, _activeSeekOperations - 1);
        });

        final hasNewerTarget = generation != _manualSeekGeneration;
        if (hasNewerTarget || _viewerSeekCommitQueued) {
          _viewerSeekCommitQueued = false;
          _scheduleQueuedViewerSeekCommit(delay: _viewerSeekHandoffDelay);
        } else {
          _syncSeekLoadingState(_playbackSurface.playerState.value);
          if (_pendingSeekTarget != null) {
            _scheduleSeekLoadingFallback();
          }
        }
      }
    }
  }

  void _cancelQueuedViewerSeek({required bool clearPending}) {
    _viewerSeekDebounceTimer?.cancel();
    _viewerSeekDebounceTimer = null;
    _viewerSeekCommitQueued = false;
    ++_manualSeekGeneration;
    if (clearPending && mounted && !_viewerSeekCommitInFlight) {
      setState(() {
        _pendingSeekTarget = null;
        _pendingSeekMayRejectSource = false;
      });
    }
  }

  void _scheduleSeekLoadingFallback() {
    _seekLoadingFallbackTimer?.cancel();
    _seekLoadingFallbackTimer = Timer(_seekLoadingFallbackDelay, () {
      _seekLoadingFallbackTimer = null;
      if (!mounted ||
          _viewerSeekDebounceTimer != null ||
          _pendingSeekTarget == null ||
          _activeSeekOperations > 0) {
        return;
      }
      _syncSeekLoadingState(_playbackSurface.playerState.value);
      if (!mounted ||
          _viewerSeekDebounceTimer != null ||
          _pendingSeekTarget == null ||
          _activeSeekOperations > 0) {
        return;
      }

      final rejectedTarget = _pendingSeekTarget!;
      final activeTarget = _committedTarget;
      if (_pendingSeekMayRejectSource &&
          activeTarget != null &&
          activeTarget.isDirectPlayable &&
          (activeTarget.uri.scheme == 'http' ||
              activeTarget.uri.scheme == 'https')) {
        unawaited(
          _recoverFromRejectedSeek(
            activeTarget,
            rejectedTarget,
            reason: 'The stream ignored a recovery seek to $rejectedTarget.',
          ),
        );
        return;
      }

      // A slow manual skip is not evidence that the source disappeared. Retry
      // the latest absolute target once on the same source, then release the
      // seek UI without quarantining a server that was already playing.
      unawaited(_retryManualSeekOnCurrentSource(rejectedTarget));
    });
  }

  Future<void> _retryManualSeekOnCurrentSource(Duration target) async {
    if (!mounted ||
        _manualSeekRetryInFlight ||
        _pendingSeekTarget != target ||
        _pendingSeekMayRejectSource) {
      return;
    }
    final generation = _manualSeekGeneration;
    _manualSeekRetryInFlight = true;
    _manualSeekProtectionUntil =
        DateTime.now().add(const Duration(seconds: 30));
    try {
      await _playbackSurface.seekTo(target).timeout(const Duration(seconds: 8));
      if (!mounted || generation != _manualSeekGeneration) {
        return;
      }
      await _playbackSurface.requestPlayerState();
      _syncSeekLoadingState(_playbackSurface.playerState.value);
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Manual seek retry did not settle; keeping the current source.',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _manualSeekRetryInFlight = false;
      if (mounted && _viewerSeekCommitQueued) {
        _viewerSeekCommitQueued = false;
        _scheduleQueuedViewerSeekCommit(delay: _viewerSeekHandoffDelay);
      }
      if (mounted &&
          generation == _manualSeekGeneration &&
          _pendingSeekTarget == target) {
        setState(() {
          _pendingSeekTarget = null;
          _pendingSeekMayRejectSource = false;
        });
        _cancelSeekLoadingFallback();
      }
    }
  }

  void _cancelSeekLoadingFallback() {
    _seekLoadingFallbackTimer?.cancel();
    _seekLoadingFallbackTimer = null;
  }

  void _armPostSeekRegressionGuard(
    Duration target, {
    bool mayRejectSource = false,
  }) {
    _postSeekRegressionTimer?.cancel();
    _postSeekRegressionTarget = target;
    _postSeekRegressionMayRejectSource = mayRejectSource;
    _postSeekRegressionTimer = Timer(_postSeekRegressionGuardDuration, () {
      _postSeekRegressionTimer = null;
      _postSeekRegressionTarget = null;
      _postSeekRegressionMayRejectSource = false;
    });
  }

  void _clearPostSeekRegressionGuard() {
    _postSeekRegressionTimer?.cancel();
    _postSeekRegressionTimer = null;
    _postSeekRegressionTarget = null;
    _postSeekRegressionMayRejectSource = false;
  }

  void _checkPostSeekRegression(PlaybackPresentation presentation) {
    final requestedTarget = _postSeekRegressionTarget;
    final activeTarget = _committedTarget;
    if (requestedTarget == null ||
        activeTarget == null ||
        !activeTarget.isDirectPlayable ||
        _seekRecoveryInFlight ||
        _resolvingSource ||
        _surfaceLoading ||
        _pendingTarget != null ||
        _resumePending ||
        _resumeIntentInFlight ||
        _switchResumeSeekInFlight ||
        _pendingSeekTarget != null ||
        _activeSeekOperations > 0 ||
        presentation.isBuffering ||
        !presentation.hasVisibleVideo) {
      return;
    }
    if (presentation.currentPosition + _postSeekRegressionTolerance >=
        requestedTarget) {
      return;
    }

    final mayRejectSource = _postSeekRegressionMayRejectSource;
    _clearPostSeekRegressionGuard();
    if (mayRejectSource) {
      unawaited(
        _recoverFromRejectedSeek(
          activeTarget,
          requestedTarget,
          reason: 'The stream jumped back after seeking to $requestedTarget.',
        ),
      );
      return;
    }

    // A native decoder can report an old timestamp briefly after a viewer
    // seek. Re-issue the absolute seek without rejecting the working source.
    unawaited(_retryManualSeekAfterRegression(requestedTarget));
  }

  Future<void> _retryManualSeekAfterRegression(Duration target) async {
    if (!mounted || _manualSeekRetryInFlight) {
      return;
    }
    _manualSeekRetryInFlight = true;
    _manualSeekProtectionUntil =
        DateTime.now().add(const Duration(seconds: 30));
    try {
      await _playbackSurface.seekTo(target).timeout(const Duration(seconds: 8));
      if (mounted) {
        await _playbackSurface.requestPlayerState();
      }
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Post-seek timestamp regressed; kept the current source.',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _manualSeekRetryInFlight = false;
    }
  }

  Future<void> _recoverFromRejectedSeek(
    PlaybackTarget target,
    Duration requestedTarget, {
    required String reason,
  }) async {
    if (!mounted || _seekRecoveryInFlight || _committedTarget != target) {
      return;
    }
    final resumeAnchor = _resumeAnchorPosition;
    if (resumeAnchor != null &&
        (resumeAnchor - requestedTarget).abs() <= _resumeSettleTolerance) {
      _clearResumeAnchor();
    }
    _seekRecoveryInFlight = true;
    _cancelSeekLoadingFallback();
    _clearPostSeekRegressionGuard();
    setState(() {
      _pendingSeekTarget = null;
    });
    _surfaceLoadToken += 1;
    try {
      await _recoverFromSourceFailure(
        currentProviderIndex: target.providerIndex,
        failureKind: SourceFailureKind.sourceRejected,
        blockedStreamHost: target.uri.host,
        failureReason: '$reason Switching to a different provider...',
        recoveryResumePosition: requestedTarget,
        skipInternalFallbacks: true,
      );
    } finally {
      _seekRecoveryInFlight = false;
    }
  }

  Future<String?> _requestVisibleScrubFrame(Duration position) {
    return _loadScrubFrame(position, prioritize: true);
  }

  Future<void> _primeScrubPreviewPathForCurrentContent({
    bool allowRetryIfAttempted = false,
  }) async {
    final key = _scrubContentKey;
    if (allowRetryIfAttempted) {
      _unresolvedScrubContentKeys.remove(key);
      _scrubPrefetchAttemptedContentKeys.remove(key);
    }
    if (_scrubPrefetchCompletedContentKeys.contains(key)) {
      return;
    }
    if (!allowRetryIfAttempted &&
        _scrubPrefetchAttemptedContentKeys.contains(key)) {
      return;
    }
    if (!_scrubPrefetchInFlightContentKeys.add(key)) {
      return;
    }
    _scrubPrefetchAttemptedContentKeys.add(key);
    try {
      final episodeId = await _resolveScrubEpisodeId().timeout(
        _scrubEpisodeResolveTimeout,
        onTimeout: () => null,
      );
      if (episodeId == null) {
        return;
      }
      final previewPath = await _previewPathDataForEpisode(episodeId).timeout(
        _scrubPreviewRequestTimeout,
        onTimeout: () => null,
      );
      if (previewPath != null) {
        _scrubPrefetchCompletedContentKeys.add(key);
      }
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Failed priming scrub preview path content=$key',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _scrubPrefetchInFlightContentKeys.remove(key);
    }
  }

  String get _scrubContentKey {
    if (_isTvEpisodePlayer) {
      return 'tv:${widget.tmdbId}:s$_activeSeasonNumber:e$_activeEpisodeNumber';
    }
    return 'movie:${widget.tmdbId}';
  }

  List<int> _candidateScrubEpisodeIds() {
    final candidates = <int>[];
    final seen = <int>{};

    void addCandidate(int? value) {
      if (value == null || value <= 0 || !seen.add(value)) {
        return;
      }
      candidates.add(value);
    }

    if (widget.scrubThumbnailUrlResolver == null &&
        _enableHardcodedOnStreamEpisodeProbe) {
      addCandidate(_hardcodedOnStreamEpisodeIdProbe);
    }

    Iterable<int> numericTokensFromText(
      String text, {
      int minimumDigits = 1,
    }) sync* {
      for (final match in RegExp(r'\d+').allMatches(text)) {
        final token = match.group(0);
        if (token == null || token.length < minimumDigits) {
          continue;
        }
        final parsed = int.tryParse(token);
        if (parsed != null && parsed > 0) {
          yield parsed;
        }
      }
    }

    Iterable<int> idsFromUri(Uri? uri) sync* {
      if (uri == null) {
        return;
      }
      for (final segment in uri.pathSegments) {
        final parsed = int.tryParse(segment);
        if (parsed != null && parsed > 0) {
          yield parsed;
          continue;
        }
        yield* numericTokensFromText(segment, minimumDigits: 3);
      }
      for (final entry in uri.queryParameters.entries) {
        final rawValue = entry.value.trim();
        if (rawValue.isEmpty) {
          continue;
        }
        final parsed = int.tryParse(rawValue);
        if (parsed != null && parsed > 0) {
          yield parsed;
          continue;
        }
        final key = entry.key.toLowerCase();
        final minimumDigits = switch (key) {
          'id' ||
          'episodeid' ||
          'episode_id' ||
          'ep' ||
          'eid' ||
          'tmdb' ||
          'tmdbid' ||
          'tmdb_id' =>
            1,
          _ => 3,
        };
        yield* numericTokensFromText(rawValue, minimumDigits: minimumDigits);
      }
    }

    final activeTarget = _pendingTarget ?? _committedTarget;
    for (final candidate in idsFromUri(activeTarget?.uri)) {
      addCandidate(candidate);
    }
    for (final candidate in idsFromUri(activeTarget?.pageUri)) {
      addCandidate(candidate);
    }
    for (final headerValue
        in activeTarget?.httpHeaders.values ?? const <String>[]) {
      for (final candidate in numericTokensFromText(
        headerValue,
        minimumDigits: 3,
      )) {
        addCandidate(candidate);
      }
    }

    if (_isTvEpisodePlayer) {
      addCandidate(_activeEpisodeSummary?.tmdbEpisodeId);
    }
    addCandidate(widget.tmdbId);
    if (_isTvEpisodePlayer) {
      addCandidate(_activeEpisodeNumber);
      addCandidate(widget.episodeNumber);
    }

    return candidates;
  }

  Future<int?> _resolveScrubEpisodeId() async {
    final key = _scrubContentKey;
    if (_resolvedScrubEpisodeIdByContentKey.containsKey(key)) {
      return _resolvedScrubEpisodeIdByContentKey[key];
    }
    if (_unresolvedScrubContentKeys.contains(key)) {
      return null;
    }
    final inFlightRequest = _resolvedScrubEpisodeIdRequestsByContentKey[key];
    if (inFlightRequest != null) {
      return inFlightRequest;
    }

    if (widget.scrubThumbnailUrlResolver != null) {
      final candidates = _candidateScrubEpisodeIds();
      final selected = candidates.isEmpty ? null : candidates.first;
      _logPlayerDiagnostic(
        'Resolved scrub episode id with injected resolver '
        'content=$key '
        'selected=$selected',
      );
      if (selected != null) {
        _resolvedScrubEpisodeIdByContentKey[key] = selected;
        _unresolvedScrubContentKeys.remove(key);
      } else {
        _unresolvedScrubContentKeys.add(key);
      }
      return selected;
    }

    final request = () async {
      final candidates = _candidateScrubEpisodeIds();
      final activeTarget = _pendingTarget ?? _committedTarget;
      _logPlayerDiagnostic(
        'Resolving scrub episode id '
        'content=$key '
        'provider=${activeTarget?.providerKey} '
        'streamUri=${activeTarget?.uri} '
        'pageUri=${activeTarget?.pageUri} '
        'candidates=$candidates',
      );
      for (final candidate in candidates.take(10)) {
        _logPlayerDiagnostic(
          'Probing OnStream episode detail '
          'content=$key '
          'candidateEpisodeId=$candidate',
        );
        final previewPathData =
            await _previewPathDataForEpisode(candidate).timeout(
          _scrubEpisodeProbeTimeout,
          onTimeout: () => null,
        );
        if (previewPathData != null) {
          _logPlayerDiagnostic(
            'Resolved scrub episode id $candidate for content=$key',
          );
          _resolvedScrubEpisodeIdByContentKey[key] = candidate;
          _unresolvedScrubContentKeys.remove(key);
          return candidate;
        }
      }
      _logPlayerDiagnostic(
        'Unable to resolve scrub episode id for content=$key',
      );
      _unresolvedScrubContentKeys.add(key);
      return null;
    }()
        .whenComplete(() {
      _resolvedScrubEpisodeIdRequestsByContentKey.remove(key);
    });
    _resolvedScrubEpisodeIdRequestsByContentKey[key] = request;
    return request;
  }

  Future<String?> _loadScrubFrame(
    Duration position, {
    bool prioritize = false,
  }) async {
    final normalizedPosition = _normalizeScrubFramePosition(position);
    final cacheKey = normalizedPosition.inSeconds;
    final cachedFrameUrl = _scrubFrameCache[cacheKey];
    if (cachedFrameUrl != null) {
      return cachedFrameUrl;
    }

    final inFlightRequest = _scrubFrameRequests[cacheKey];
    if (inFlightRequest != null) {
      return inFlightRequest;
    }

    final generation = _scrubFrameCacheGeneration;
    final timestampMs = normalizedPosition.inMilliseconds;
    final request = () async {
      final activeTarget = _pendingTarget ?? _committedTarget;
      String? resolvedThumbnail;
      _logPlayerDiagnostic(
        'Scrub thumbnail request '
        'content=$_scrubContentKey '
        'provider=${activeTarget?.providerKey} '
        'streamUri=${activeTarget?.uri} '
        'pageUri=${activeTarget?.pageUri} '
        'timestampMs=$timestampMs',
      );
      if (activeTarget != null && activeTarget.isDirectPlayable) {
        resolvedThumbnail = await _loadDirectScrubFrame(
          activeTarget,
          normalizedPosition,
          prioritize: prioritize,
        );
      }
      resolvedThumbnail ??= await _loadProviderPreviewScrubFrame(
        normalizedPosition,
      );
      final validatedUrl = _validateScrubFrameUrl(resolvedThumbnail);
      if (!mounted ||
          generation != _scrubFrameCacheGeneration ||
          validatedUrl == null) {
        return validatedUrl;
      }
      if (_scrubFrameCache[cacheKey] != validatedUrl) {
        if (prioritize) {
          setState(() {
            _scrubFrameCache[cacheKey] = validatedUrl;
          });
        } else {
          _scrubFrameCache[cacheKey] = validatedUrl;
        }
      }
      return validatedUrl;
    }()
        .catchError((Object error, StackTrace stackTrace) {
      _logPlayerDiagnostic(
        'Scrub thumbnail URL request failed '
        'timestampMs=$timestampMs',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }).whenComplete(() {
      _scrubFrameRequests.remove(cacheKey);
    });
    _scrubFrameRequests[cacheKey] = request;
    return request;
  }

  Future<String?> _loadDirectScrubFrame(
    PlaybackTarget target,
    Duration position, {
    required bool prioritize,
  }) async {
    if (target.sourceKind == PlaybackSourceKind.hls) {
      final coordinator = _ensureHlsScrubCoordinator(target);
      return coordinator.resolveFrameUri(
        position,
        prioritize: prioritize,
      );
    }

    final session = _ensureDirectScrubSession(target);
    return session.getFrameUri(
      position.inMilliseconds,
      prioritize: prioritize,
    );
  }

  Future<String?> _loadProviderPreviewScrubFrame(
    Duration normalizedPosition,
  ) async {
    await _primeScrubPreviewPathForCurrentContent();
    final episodeId = await _resolveScrubEpisodeId().timeout(
      _scrubEpisodeResolveTimeout,
      onTimeout: () => null,
    );
    if (episodeId == null) {
      return null;
    }
    final timestampMs = normalizedPosition.inMilliseconds;
    final url = await getThumbnailUrl(episodeId, timestampMs).timeout(
      _scrubThumbnailUrlTimeout,
      onTimeout: () => null,
    );
    return _validateScrubFrameUrl(url);
  }

  Future<String?> _fallbackExtractedScrubThumbnailDataUri(
    Duration position, {
    bool prioritizeVisible = true,
  }) async {
    final surfaceController = _playbackSurface;
    if (surfaceController is! PlaybackFrameExtractor) {
      return null;
    }
    final frameExtractor = surfaceController as PlaybackFrameExtractor;

    Future<Uint8List?> extractAt(Duration probePosition) {
      if (surfaceController is _NativeStreamPlaybackSurfaceController) {
        return surfaceController.extractFrameWithPriority(
          probePosition,
          prioritizeVisible: prioritizeVisible,
        );
      }
      return frameExtractor.extractFrame(probePosition);
    }

    final capturePosition = scrubFrameCapturePosition(position);
    for (final probePosition in _scrubFrameCaptureProbes(capturePosition)) {
      final bytes = await extractAt(probePosition);
      if (bytes == null || bytes.isEmpty) {
        continue;
      }
      if (await isLikelyBlankScrubFrame(bytes)) {
        continue;
      }
      final encoded = base64Encode(bytes);
      return 'data:image/png;base64,$encoded';
    }

    return null;
  }

  String? _validateScrubFrameUrl(String? url) {
    final normalizedUrl = url?.trim();
    if (normalizedUrl == null || normalizedUrl.isEmpty) {
      return null;
    }
    return normalizedUrl;
  }

  Duration _normalizeScrubFramePosition(Duration position) {
    final totalDuration = _playbackSurface.playerState.value.totalDuration;
    if (totalDuration <= Duration.zero) {
      return Duration.zero;
    }
    var normalized = position;
    if (normalized.isNegative) {
      normalized = Duration.zero;
    } else if (normalized > totalDuration) {
      normalized = totalDuration;
    }
    final alignedSeconds =
        (normalized.inSeconds ~/ _scrubFrameCacheStep.inSeconds) *
            _scrubFrameCacheStep.inSeconds;
    return Duration(seconds: alignedSeconds);
  }

  void _resetScrubFrameCache() {
    _scrubFrameCacheGeneration += 1;
    _scrubFrameCache.clear();
    _scrubFrameRequests.clear();
    _disposeScrubCoordinators();
    _resolvedScrubEpisodeIdByContentKey.clear();
    _resolvedScrubEpisodeIdRequestsByContentKey.clear();
    _unresolvedScrubContentKeys.clear();
    _scrubPrefetchAttemptedContentKeys.clear();
    _scrubPrefetchInFlightContentKeys.clear();
    _scrubPrefetchCompletedContentKeys.clear();
  }

  Future<String?> getThumbnailUrl(
    int episodeId,
    int timestampMs,
  ) async {
    if (widget.scrubThumbnailUrlResolver != null) {
      return widget.scrubThumbnailUrlResolver!(episodeId, timestampMs);
    }
    final previewPathData = await _previewPathDataForEpisode(episodeId);
    if (previewPathData == null) {
      return null;
    }
    return previewPathData.thumbnailUrlForTimestamp(timestampMs);
  }

  Future<_EpisodePreviewPathData?> _previewPathDataForEpisode(
    int episodeId,
  ) async {
    if (_episodePreviewPathCache.containsKey(episodeId)) {
      return _episodePreviewPathCache[episodeId];
    }
    if (_episodesWithoutPreviewPath.contains(episodeId)) {
      return null;
    }
    final inFlightRequest = _episodePreviewPathRequests[episodeId];
    if (inFlightRequest != null) {
      return inFlightRequest;
    }

    final request = _loadEpisodePreviewPathData(episodeId)
        .then<_EpisodePreviewPathData?>((previewPathData) {
      if (previewPathData != null) {
        _episodePreviewPathCache[episodeId] = previewPathData;
      } else {
        _episodesWithoutPreviewPath.add(episodeId);
      }
      return previewPathData;
    }).catchError((Object error, StackTrace stackTrace) {
      if (error is TimeoutException) {
        _logPlayerDiagnostic(
          'Timed out loading preview_path for episode $episodeId; '
          'negative caching for this session.',
          error: error,
        );
        _episodesWithoutPreviewPath.add(episodeId);
        return null;
      }
      _logPlayerDiagnostic(
        'Failed loading preview_path for episode $episodeId.',
        error: error,
        stackTrace: stackTrace,
      );
      _episodesWithoutPreviewPath.add(episodeId);
      return null;
    }).whenComplete(() {
      _episodePreviewPathRequests.remove(episodeId);
    });
    _episodePreviewPathRequests[episodeId] = request;
    return request;
  }

  Future<_EpisodePreviewPathData?> _loadEpisodePreviewPathData(
    int episodeId,
  ) async {
    final requestUri = Uri.parse(
      'https://p.freewings.boo/v3/app/episodes/get-detail/$episodeId',
    );
    try {
      final response = await http.get(
        requestUri,
        headers: const <String, String>{
          'device-info': _scrubThumbnailDeviceInfo,
        },
      ).timeout(
        _scrubPreviewRequestTimeout,
      );
      _logEpisodeDetailApiResponse(
        episodeId: episodeId,
        requestUri: requestUri,
        response: response,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logPlayerDiagnostic(
          'Episode detail request returned ${response.statusCode} '
          'episodeId=$episodeId '
          'contentType=${response.headers['content-type']}',
        );
        return null;
      }

      final payload = jsonDecode(utf8.decode(response.bodyBytes));
      final previewPath = _extractPreviewPathFromPayload(payload);
      if (previewPath == null || previewPath.isEmpty) {
        _logPlayerDiagnostic(
          'Episode detail did not include preview_path '
          'episodeId=$episodeId',
        );
        return null;
      }
      return _EpisodePreviewPathData.fromPreviewPath(previewPath);
    } on TimeoutException catch (error) {
      _logPlayerDiagnostic(
        'Timed out loading preview_path for episode $episodeId; '
        'negative caching for this session.',
        error: error,
      );
      return null;
    } on FormatException catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Episode detail parse failed episodeId=$episodeId',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  void _logEpisodeDetailApiResponse({
    required int episodeId,
    required Uri requestUri,
    required http.Response response,
  }) {
    final headersText = response.headers.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('; ');
    final bodyBytes = response.bodyBytes;
    String? decodedBody;
    try {
      decodedBody = utf8.decode(bodyBytes);
    } on FormatException {
      decodedBody = null;
    }
    final bodyBase64 = base64Encode(bodyBytes);
    _logPlayerDiagnostic(
      'OnStream episode detail raw response '
      'episodeId=$episodeId '
      'requestUri=$requestUri '
      'status=${response.statusCode} '
      'headers={$headersText} '
      'bodyUtf8=${decodedBody ?? '<non-utf8>'} '
      'bodyBase64=$bodyBase64',
    );
  }

  String? _extractPreviewPathFromPayload(Object? payload) {
    if (payload is Map) {
      final direct = payload['preview_path'];
      if (direct is String && direct.trim().isNotEmpty) {
        return direct.trim();
      }

      for (final value in payload.values) {
        final nested = _extractPreviewPathFromPayload(value);
        if (nested != null && nested.isNotEmpty) {
          return nested;
        }
      }
      return null;
    }

    if (payload is List) {
      for (final value in payload) {
        final nested = _extractPreviewPathFromPayload(value);
        if (nested != null && nested.isNotEmpty) {
          return nested;
        }
      }
    }
    return null;
  }

  void _exitScrubFocus() {
    if (_playPauseFocusNode.context != null &&
        _playPauseFocusNode.canRequestFocus) {
      _playPauseFocusNode.requestFocus();
      return;
    }

    if (_scrubFocusNode.context != null) {
      _scrubFocusNode.focusInDirection(TraversalDirection.down);
    }
  }

  Future<void> _toggleMute() async {
    _registerChromeInteraction();
    await _playbackSurface.toggleMute();
  }

  Future<void> _selectCaptionTrack(String? trackId) async {
    _registerChromeInteraction();
    final shouldResumeAfterSwitch = _intendedPlaybackPlaying;
    _logPlayerDiagnostic(
      'Subtitle source switch requested '
      'track=${trackId ?? 'off'} '
      'shouldResumeAfterSwitch=$shouldResumeAfterSwitch',
    );
    await _playbackSurface.selectCaptionTrack(trackId);
    await _applySubtitleOffset();
    if (shouldResumeAfterSwitch &&
        _isPresentationPausedForUi(_playbackSurface.playerState.value)) {
      await _recoverPlaybackIfNeeded('subtitle-source-switch', force: true);
    }
  }

  Future<void> _hydrateSubtitleOffset({String? providerKey}) async {
    if (widget.captionService is! SubtitleOffsetStore) {
      _subtitleOffsetMs = 0;
      return;
    }
    final offsetStore = widget.captionService as SubtitleOffsetStore;
    final effectiveProviderKey = _effectiveSubtitleProviderKey(providerKey);
    final allowScopedFallback =
        _shouldAllowProviderScopedOffsetFallback(effectiveProviderKey);
    final persisted = await offsetStore.readOffsetMs(
      tmdbId: widget.tmdbId,
      mediaType: widget.mediaType,
      seasonNumber: _isTvEpisodePlayer ? _activeSeasonNumber : null,
      episodeNumber: _isTvEpisodePlayer ? _activeEpisodeNumber : null,
      providerKey: effectiveProviderKey,
      allowProviderScopedFallback: allowScopedFallback,
    );
    _logPlayerDiagnostic(
      'Hydrated subtitle delay '
      'provider=${effectiveProviderKey ?? 'default'} '
      'season=${_isTvEpisodePlayer ? _activeSeasonNumber : '-'} '
      'episode=${_isTvEpisodePlayer ? _activeEpisodeNumber : '-'} '
      'allowScopedFallback=$allowScopedFallback '
      'offsetMs=$persisted',
    );
    if (!mounted) {
      _subtitleOffsetMs = persisted
          .clamp(-_subtitleOffsetLimitMs, _subtitleOffsetLimitMs)
          .toInt();
      return;
    }
    setState(() {
      _subtitleOffsetMs = persisted
          .clamp(-_subtitleOffsetLimitMs, _subtitleOffsetLimitMs)
          .toInt();
    });
  }

  Future<void> _updateSubtitleOffset(int nextOffsetMs) async {
    final clamped = nextOffsetMs
        .clamp(-_subtitleOffsetLimitMs, _subtitleOffsetLimitMs)
        .toInt();
    if (clamped == _subtitleOffsetMs) {
      return;
    }
    if (mounted) {
      setState(() => _subtitleOffsetMs = clamped);
    } else {
      _subtitleOffsetMs = clamped;
    }
    await _applySubtitleOffset();
    await _persistSubtitleOffset();
  }

  Future<void> _applySubtitleOffset() async {
    final effectiveProviderKey = _effectiveSubtitleProviderKey(null);
    final playbackMode = _activePlaybackModeLabel();
    final immediateApply =
        _playbackSurface is _AdaptivePlaybackSurfaceController
            ? _playbackSurface.canApplySubtitleDelayImmediately
            : true;
    _logPlayerDiagnostic(
      'Applying subtitle delay '
      'provider=${effectiveProviderKey ?? 'default'} '
      'mode=$playbackMode '
      'immediate=$immediateApply '
      'offsetMs=$_subtitleOffsetMs',
    );
    final offset = Duration(milliseconds: _subtitleOffsetMs);
    await _playbackSurface.setSubtitleDelay(offset);
  }

  Future<void> _persistSubtitleOffset() async {
    if (widget.captionService is! SubtitleOffsetStore) {
      return;
    }
    final offsetStore = widget.captionService as SubtitleOffsetStore;
    final effectiveProviderKey = _effectiveSubtitleProviderKey(null);
    await offsetStore.writeOffsetMs(
      tmdbId: widget.tmdbId,
      mediaType: widget.mediaType,
      seasonNumber: _isTvEpisodePlayer ? _activeSeasonNumber : null,
      episodeNumber: _isTvEpisodePlayer ? _activeEpisodeNumber : null,
      offsetMs: _subtitleOffsetMs,
      providerKey: effectiveProviderKey,
    );
  }

  String? _effectiveSubtitleProviderKey(String? providerKeyOverride) {
    final normalizedOverride = providerKeyOverride?.trim();
    if (normalizedOverride != null && normalizedOverride.isNotEmpty) {
      return normalizedOverride;
    }
    final activeKey = _visibleTarget?.providerKey.trim();
    if (activeKey != null && activeKey.isNotEmpty) {
      return activeKey;
    }
    return null;
  }

  bool _shouldAllowProviderScopedOffsetFallback(String? providerKey) {
    final normalized = (providerKey ?? '').trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    return normalized.startsWith('vidsrc');
  }

  String _activePlaybackModeLabel() {
    final surface = _playbackSurface;
    if (surface is _AdaptivePlaybackSurfaceController) {
      return surface.debugActiveModeLabel;
    }
    return 'direct';
  }

  Future<void> _cyclePlaybackRate() async {
    _registerChromeInteraction();
    await _playbackSurface.cyclePlaybackRate();
  }

  Future<void> _adjustZoom(double delta) async {
    _registerChromeInteraction();
    await _playbackSurface.adjustZoom(delta);
  }

  Future<void> _zoomOut() async {
    await _adjustZoom(-_zoomStep);
  }

  Future<void> _zoomIn() async {
    await _adjustZoom(_zoomStep);
  }

  Future<void> _cycleQuality() async {
    _registerChromeInteraction();
    await _playbackSurface.cycleQuality();
  }

  void _placeholderFullscreenExit() {}

  bool get _canOpenServerPicker =>
      _hasCommittedTarget &&
      !_resolvingSource &&
      !_surfaceLoading &&
      widget.playbackProvider.listEnabledProviders().length > 1;

  List<ProviderDescriptor> get _enabledProviders =>
      widget.playbackProvider.listEnabledProviders();

  Future<T?> _showPlayerModalOverlay<T>({
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    bool useSafeArea = true,
  }) async {
    if (!mounted) {
      return null;
    }
    _playerModalOverlayDepth += 1;
    try {
      return await showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        useSafeArea: useSafeArea,
        builder: builder,
      );
    } finally {
      _playerModalOverlayDepth = math.max(0, _playerModalOverlayDepth - 1);
    }
  }

  void _closeTopPlayerModalOverlay() {
    if (!mounted || _playerModalOverlayDepth <= 0) {
      return;
    }
    unawaited(Navigator.of(context, rootNavigator: true).maybePop());
  }

  Future<void> _openServerPicker() async {
    _registerChromeInteraction();
    final currentTarget = _committedTarget;
    if (currentTarget == null || !_canOpenServerPicker) {
      return;
    }

    final selectedProviderIndex = await _showPlayerModalOverlay<int>(
      builder: (context) {
        return _ServerPickerDialog(
          currentProviderIndex: currentTarget.providerIndex,
          providers: _enabledProviders,
        );
      },
    );

    if (!mounted ||
        selectedProviderIndex == null ||
        selectedProviderIndex == currentTarget.providerIndex) {
      return;
    }

    await _switchToProvider(selectedProviderIndex);
  }

  Future<void> _openAudioTrackPicker() async {
    _registerChromeInteraction();
    final presentation = _playbackSurface.playerState.value;
    if (presentation.audioTracks.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('This stream does not expose another audio language.'),
          ),
        );
      }
      return;
    }
    final selectedTrackId = await _showPlayerModalOverlay<String>(
      builder: (context) => _AudioTrackPickerDialog(
        tracks: presentation.audioTracks,
        selectedTrackId: presentation.selectedAudioTrackId,
        originalLanguageCode: _summary?.originalLanguage,
      ),
    );
    if (!mounted || selectedTrackId == null) {
      return;
    }
    final shouldResume = _intendedPlaybackPlaying;
    final selectedTrack =
        presentation.audioTracks.cast<PlaybackAudioTrack?>().firstWhere(
              (track) => track?.id == selectedTrackId,
              orElse: () => null,
            );
    await _playbackSurface.selectAudioTrack(selectedTrackId);
    final selectedLanguage =
        normalizeAudioLanguageCode(selectedTrack?.languageCode ?? '');
    if (selectedLanguage.isNotEmpty) {
      _effectiveAudioLanguage = selectedLanguage;
      await widget.audioLanguagePreferenceStore.setPreferredLanguage(
        profileId: widget.profileId,
        tmdbId: widget.tmdbId,
        mediaType: widget.mediaType,
        languageCode: selectedLanguage,
      );
    }
    await _playbackSurface.requestPlayerState();
    if (shouldResume &&
        _isPresentationPausedForUi(_playbackSurface.playerState.value)) {
      await _recoverPlaybackIfNeeded('audio-track-switch', force: true);
    }
  }

  Future<void> _updateAudioDelay(int nextOffsetMs) async {
    final clamped = nextOffsetMs.clamp(-5000, 5000).toInt();
    if (clamped == _audioDelayMs) {
      return;
    }
    if (mounted) {
      setState(() => _audioDelayMs = clamped);
    } else {
      _audioDelayMs = clamped;
    }
    await _playbackSurface.setAudioDelay(
      Duration(milliseconds: _audioDelayMs),
    );
  }

  Future<void> _openAudioSyncPicker() async {
    _registerChromeInteraction();
    final result = await _showPlayerModalOverlay<int>(
      builder: (context) => _AudioSyncDialog(
        initialOffsetMs: _audioDelayMs,
        onOffsetChanged: (offsetMs) {
          unawaited(_updateAudioDelay(offsetMs));
        },
      ),
    );
    if (result != null) {
      await _updateAudioDelay(result);
    }
  }

  Future<void> _openSettings() async {
    _registerChromeInteraction();
    await _showPlayerModalOverlay<void>(
      builder: (context) {
        return _PlayerSettingsDialog(
          playerState: _playbackSurface.playerState,
          currentProviderLabel: _committedTarget?.providerLabel,
          canOpenServerPicker: _canOpenServerPicker,
          onOpenServerPicker: _openServerPicker,
          onOpenCaptionPicker: _openCaptionPicker,
          onOpenAudioTrackPicker: _openAudioTrackPicker,
          audioDelayMs: _audioDelayMs,
          onOpenAudioSyncPicker: _openAudioSyncPicker,
          onCycleQuality: _cycleQuality,
          onCyclePlaybackRate: _cyclePlaybackRate,
          onToggleMute: _toggleMute,
        );
      },
    );
  }

  Future<void> _openEpisodesModal() async {
    _registerChromeInteraction();
    if (!_isTvEpisodePlayer || !_surfaceReady) {
      return;
    }

    final presentation = _playbackSurface.playerState.value;
    final wasPlaying = !presentation.isPaused;
    if (wasPlaying) {
      await _setPlaybackPlaying(
        false,
        reason: 'episodes-overlay-pause',
        updateIntent: false,
      );
    }

    if (!mounted) {
      return;
    }

    final selection = await _showPlayerModalOverlay<_EpisodeSelection>(
      useSafeArea: false,
      builder: (context) {
        return _PlayerEpisodesOverlayDialog(
          summary: _summary ?? widget.initialSummary,
          activeSeasonNumber: _activeSeasonNumber,
          languageCode: widget.languageCode,
          hideSpoilers: widget.hideSpoilers,
          playbackProgress:
              widget.playbackProgress ?? PlaybackProgressSnapshot.empty(),
          mediaCatalogService: widget.mediaCatalogService,
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (selection == null) {
      if (wasPlaying && _playbackSurface.playerState.value.isPaused) {
        await _setPlaybackPlaying(
          true,
          reason: 'episodes-overlay-cancel-resume',
          updateIntent: false,
        );
      }
      return;
    }

    if (selection.seasonNumber == _activeSeasonNumber &&
        selection.episodeNumber == _activeEpisodeNumber) {
      if (wasPlaying && _playbackSurface.playerState.value.isPaused) {
        await _setPlaybackPlaying(
          true,
          reason: 'episodes-overlay-same-episode-resume',
          updateIntent: false,
        );
      }
      return;
    }

    await _activateEpisode(
      seasonNumber: selection.seasonNumber,
      episodeNumber: selection.episodeNumber,
    );
  }

  Future<void> _openCaptionPicker() async {
    _registerChromeInteraction();
    var presentation = _playbackSurface.playerState.value;
    if (presentation.captionTracks.isEmpty &&
        _captionResolution.tracks.isEmpty) {
      try {
        final refreshed = await _resolveCaptionResolution();
        await _playbackSurface.setCaptionTracks(
          refreshed.tracks,
          selectedTrackId: refreshed.selectedTrackId,
        );
        presentation = _playbackSurface.playerState.value;
      } catch (_) {}
    }

    if (presentation.captionTracks.isEmpty &&
        _captionResolution.tracks.isEmpty) {
      if (!mounted) {
        return;
      }
      cheriflixLog(
        'subtitles',
        'No subtitles available. presentationTracks='
            '${presentation.captionTracks.length}, cachedTracks='
            '${_captionResolution.tracks.length}, '
            'failureCode=${_captionResolution.failureCode}, '
            'service=${widget.captionService.runtimeType}',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(_captionFailureMessage(_captionResolution.failureCode))),
      );
      return;
    }

    final result = await _showPlayerModalOverlay<_CaptionPickerResult>(
      builder: (context) {
        return _CaptionPickerDialog(
          tracks: presentation.captionTracks.isNotEmpty
              ? presentation.captionTracks
              : _captionResolution.tracks,
          selectedTrackId: presentation.selectedCaptionTrackId,
          subtitleOffsetMs: _subtitleOffsetMs,
          preferHi: _preferHiSubtitles,
          onSubtitleOffsetChanged: (offsetMs) {
            unawaited(_updateSubtitleOffset(offsetMs));
          },
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (result == null) {
      return;
    }
    _preferHiSubtitles = result.preferHi;
    await _updateSubtitleOffset(result.subtitleOffsetMs);
    await _selectCaptionTrack(result.selectedTrackId);
  }

  String _captionFailureMessage(String? failureCode) {
    switch (failureCode) {
      case CaptionFailureCode.missingApiKey:
        return 'Subtitles unavailable: subtitle API key is missing.';
      case CaptionFailureCode.noMatch:
        return 'No subtitles found for this title/episode.';
      case CaptionFailureCode.prepareFailed:
        return 'Subtitles were found, but could not be prepared.';
      case CaptionFailureCode.serviceError:
        return 'Subtitle service is temporarily unavailable.';
      default:
        return 'No subtitles found.';
    }
  }

  Future<void> _activateEpisode({
    required int seasonNumber,
    required int episodeNumber,
  }) async {
    if (!_isTvEpisodePlayer ||
        seasonNumber == _activeSeasonNumber &&
            episodeNumber == _activeEpisodeNumber) {
      return;
    }

    final contentGeneration = ++_contentGeneration;

    // Freeze reporting before changing the episode identity. Otherwise the
    // outgoing surface can checkpoint its near-end position under the incoming
    // episode while source resolution is still in flight.
    _suppressProgressReporting = true;
    await _flushProgress(force: true, awaitCallbacks: true);
    _cancelNextEpisodePrompt();
    _autoRecoveryFailedProviderIndexes.clear();
    _loopRecoveryRetriedProviderIndexes.clear();
    _surfaceLoadToken += 1;
    _embedPromotionTimeoutTimer?.cancel();
    _directFrameTimeoutTimer?.cancel();
    _playbackStartupEscapeTimer?.cancel();
    _unexpectedStopRecoveryTimer?.cancel();
    _resetPlaybackStallWatchdog();
    await _haltSurfacePlaybackForRecovery();
    if (!mounted || contentGeneration != _contentGeneration) {
      return;
    }

    setState(() {
      _activeSeasonNumber = seasonNumber;
      _activeEpisodeNumber = episodeNumber;
      _committedTarget = null;
      _pendingTarget = null;
      _surfaceReady = false;
      _lastTrustedPlaybackPosition = Duration.zero;
      _lastReportedProgressPosition = Duration.zero;
      _lastPersistableProgressPresentation = null;
      _lastReportedPaused = true;
      _recordedSuccessfulTargetSignature = null;
      _captionResolution = CaptionResolution.empty;
      _captionResolutionInFlight = null;
      _intendedPlaybackPlaying = true;
      _clearResumeAnchor();
      _resolvingSource = true;
      _surfaceLoading = true;
      _error = null;
      _statusMessage = 'Loading next episode inside the app...';
    });
    widget.playbackProvider.beginPlaybackAttempt(
      profileId: widget.profileId,
      tmdbId: widget.tmdbId,
      mediaType: widget.mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
    await _hydrateSubtitleOffset();

    PlaybackTarget? target;
    try {
      target = await _resolveTargetFromStart();
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Resolving the next episode failed.',
        error: error,
        stackTrace: stackTrace,
      );
    }

    if (!mounted || contentGeneration != _contentGeneration) {
      return;
    }

    if (target == null) {
      _suppressProgressReporting = false;
      setState(_showNoSourcesState);
      return;
    }

    setState(() {
      _pendingTarget = target;
      _resolvingSource = false;
      _surfaceLoading = true;
      _error = null;
      _statusMessage = _loadingStatusMessageForTarget(target!);
    });

    try {
      await _loadPlaybackTarget(target);
    } finally {
      if (mounted) {
        _suppressProgressReporting = false;
        _handlePlayerStateChanged();
      }
    }
    unawaited(_warmEpisodeMetadata());
  }

  Future<void> _switchToProvider(int providerIndex) async {
    final currentTarget = _committedTarget;
    if (currentTarget == null || _resolvingSource || _surfaceLoading) {
      return;
    }

    final currentPresentation = _playbackSurface.playerState.value;
    final switchResumePosition =
        _isUnexpectedPlaybackPositionReset(currentPresentation)
            ? _lastTrustedPlaybackPosition
            : currentPresentation.currentPosition;
    final hasSwitchResumePosition = switchResumePosition > Duration.zero;
    final shouldRemainPaused = !_intendedPlaybackPlaying ||
        _isPresentationPausedForUi(currentPresentation);

    _autoRecoveryFailedProviderIndexes.clear();
    _loopRecoveryRetriedProviderIndexes.clear();
    _registerChromeInteraction();
    _cancelNextEpisodePrompt();
    _clearResumeAnchor();
    _suppressProgressReporting = true;
    setState(() {
      _resolvingSource = true;
      _surfaceLoading = true;
      _error = null;
      _statusMessage = 'Switching playback source...';
    });

    PlaybackTarget? target;
    try {
      target = await widget.playbackProvider.resolveSpecificSource(
        profileId: widget.profileId,
        tmdbId: widget.tmdbId,
        mediaType: widget.mediaType,
        providerIndex: providerIndex,
        seasonNumber: _isTvEpisodePlayer ? _activeSeasonNumber : null,
        episodeNumber: _isTvEpisodePlayer ? _activeEpisodeNumber : null,
        preferredAudioLanguage: _effectiveAudioLanguage,
        probeCandidate: true,
      );
    } catch (_) {
      target = null;
    }

    if (!mounted) {
      return;
    }

    if (target == null) {
      await _recoverFromSourceFailure(
        currentProviderIndex: providerIndex,
        failureKind: SourceFailureKind.manualSwitch,
        failureReason: 'The selected server could not be opened.',
      );
      if (!mounted) {
        _suppressProgressReporting = false;
        return;
      }
      final latestPresentation = _playbackSurface.playerState.value;
      _lastReportedProgressPosition = latestPresentation.currentPosition;
      _lastReportedPaused = latestPresentation.isPaused;
      _suppressProgressReporting = false;
      return;
    }

    final selectedTarget = target;

    setState(() {
      _pendingTarget = selectedTarget;
      _resolvingSource = false;
      _surfaceLoading = true;
      _error = null;
      _statusMessage = _loadingStatusMessageForTarget(selectedTarget);
    });

    await _loadPlaybackTarget(
      selectedTarget,
      switchResumePosition:
          hasSwitchResumePosition ? switchResumePosition : null,
      switchShouldRemainPaused: shouldRemainPaused,
    );
    if (!mounted) {
      _suppressProgressReporting = false;
      return;
    }
    final latestPresentation = _playbackSurface.playerState.value;
    _lastReportedProgressPosition = latestPresentation.currentPosition;
    _lastReportedPaused = latestPresentation.isPaused;
    _suppressProgressReporting = false;
  }

  void _handleBack() {
    if (_exitConfirmationVisible) {
      return;
    }
    if (_chromeBackConsumedGuardActive) {
      return;
    }
    if (_playerModalOverlayDepth > 0) {
      _closeTopPlayerModalOverlay();
      return;
    }
    if (_nextEpisodePromptVisible) {
      _dismissNextEpisodePrompt();
      return;
    }
    final presentation = _playbackSurface.playerState.value;
    if (_isChromeVisibleToUser(presentation)) {
      _startChromeBackConsumedGuard();
      _startOverlayBackWindow();
      _hideChromeOverlay(presentation);
      return;
    }
    if (_awaitingSecondOverlayBack) {
      _clearOverlayBackWindow();
      unawaited(_confirmExitPlayer());
      return;
    }
    unawaited(_confirmExitPlayer());
  }

  void _hideChromeOverlay(PlaybackPresentation presentation) {
    _cancelChromeHide();
    _chromeAutoHideActive = false;
    if (mounted) {
      setState(() {
        _chromeVisible = false;
        _chromeForceDismissed = _shouldKeepChromeVisible(presentation);
      });
    } else {
      _chromeVisible = false;
      _chromeForceDismissed = _shouldKeepChromeVisible(presentation);
    }
    _requestPlayerSurfaceFocus();
  }

  void _startOverlayBackWindow() {
    _overlayDoubleBackTimer?.cancel();
    _awaitingSecondOverlayBack = true;
    _overlayDoubleBackTimer = Timer(_overlayDoubleBackWindow, () {
      _awaitingSecondOverlayBack = false;
      _overlayDoubleBackTimer = null;
    });
  }

  void _clearOverlayBackWindow() {
    _overlayDoubleBackTimer?.cancel();
    _overlayDoubleBackTimer = null;
    _awaitingSecondOverlayBack = false;
  }

  void _startChromeBackConsumedGuard() {
    _chromeBackConsumedGuardTimer?.cancel();
    _chromeBackConsumedGuardActive = true;
    _chromeBackConsumedGuardTimer = Timer(_chromeBackConsumedGuardDuration, () {
      _chromeBackConsumedGuardActive = false;
      _chromeBackConsumedGuardTimer = null;
    });
  }

  void _clearChromeBackConsumedGuard() {
    _chromeBackConsumedGuardTimer?.cancel();
    _chromeBackConsumedGuardTimer = null;
    _chromeBackConsumedGuardActive = false;
  }

  void _dismissPlayerOverlaysForExit() {
    _clearOverlayBackWindow();
    _clearChromeBackConsumedGuard();
    _cancelChromeHide();
    if (mounted) {
      _cancelNextEpisodePrompt();
      Navigator.of(context, rootNavigator: true).popUntil(
        (route) => route.isFirst,
      );
      setState(() {
        _scrubUiVisible = false;
        _chromeVisible = false;
        _chromeForceDismissed = true;
      });
    } else {
      _scrubUiVisible = false;
      _chromeVisible = false;
      _chromeForceDismissed = true;
      _nextEpisodeCountdownTimer?.cancel();
      _nextEpisodeCountdownTimer = null;
      _nextEpisodePromptVisible = false;
      _nextEpisodePromptWasPlaying = false;
      _nextEpisodeCountdownSeconds = 0;
    }
    _playerModalOverlayDepth = 0;
    _fatalPlaybackDialogVisible = false;
  }

  Future<void> _confirmExitPlayer() async {
    if (!mounted || _exitConfirmationVisible) {
      return;
    }

    _clearOverlayBackWindow();
    _clearChromeBackConsumedGuard();
    _cancelChromeHide();
    _exitConfirmationVisible = true;
    final shouldExit = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return const _ExitPlayerConfirmationDialog();
          },
        ) ??
        false;
    _exitConfirmationVisible = false;

    if (!mounted || !shouldExit) {
      return;
    }

    _dismissPlayerOverlaysForExit();
    if (!mounted) {
      return;
    }
    await _refreshProgressPresentation();
    if (!mounted) {
      return;
    }
    final progressSaved = _flushProgress(force: true, awaitCallbacks: true);
    await _stopPlaybackSurfaceForExit();
    await progressSaved;
    widget.onBack();
  }

  Future<void> _handlePlayerShortcut(_PlayerShortcutAction action) async {
    if (!_surfaceReady) {
      return;
    }
    _registerChromeInteraction();

    final presentation = _playbackSurface.playerState.value;
    final isPausedForUi = _isPresentationPausedForUi(presentation);
    if (action == _PlayerShortcutAction.playPause) {
      await _togglePlayPauseAndWait();
      return;
    }
    if (action == _PlayerShortcutAction.play) {
      if (isPausedForUi) {
        await _setPlaybackPlaying(
          true,
          reason: 'shortcut-play',
          updateIntent: true,
        );
      }
      return;
    }
    if (action == _PlayerShortcutAction.pause) {
      if (!isPausedForUi) {
        await _setPlaybackPlaying(
          false,
          reason: 'shortcut-pause',
          updateIntent: true,
        );
      }
      return;
    }
    if (action == _PlayerShortcutAction.seekForward) {
      await _seekForward();
      return;
    }
    await _seekBackward();
  }

  void _handlePlayerStateChanged() {
    final presentation = _playbackSurface.playerState.value;
    _syncSeekLoadingState(presentation);
    _checkPostSeekRegression(presentation);
    _syncDirectPlaybackVisibility(presentation);
    _syncEmbedPlaybackVisibility(presentation);
    _syncScrubBackgroundWork(presentation);
    _syncEmbedPromotionTimeout();
    _cancelPlaybackStartupEscapeWhenReady();
    _maybeRecordSourceSuccess(presentation);
    _syncUnexpectedStopRecovery(presentation);
    final issuedResume = _applyResumeIfNeeded(presentation);
    final rejectedRapidBackwardJump =
        !issuedResume && _trackRapidBackwardPlaybackJumps(presentation);
    final rejectedTimestampReset = !issuedResume &&
        !rejectedRapidBackwardJump &&
        _trackTrustedPlaybackPosition(presentation);
    if (!issuedResume &&
        !rejectedRapidBackwardJump &&
        !rejectedTimestampReset) {
      unawaited(_flushProgress(presentation: presentation));
    }
    _updateNextEpisodePrompt(presentation);
    _syncChromeVisibility(presentation);
  }

  void _syncSeekLoadingState(PlaybackPresentation presentation) {
    final pendingSeekTarget = _pendingSeekTarget;
    if (pendingSeekTarget == null ||
        _viewerSeekDebounceTimer != null ||
        _activeSeekOperations > 0 ||
        !mounted) {
      return;
    }
    if (!_isSeekPresentationSettled(presentation, pendingSeekTarget)) {
      return;
    }
    final mayRejectSource = _pendingSeekMayRejectSource;
    setState(() {
      _pendingSeekTarget = null;
      _pendingSeekMayRejectSource = false;
      _lastTrustedPlaybackPosition = pendingSeekTarget;
    });
    _cancelSeekLoadingFallback();
    _armPostSeekRegressionGuard(
      pendingSeekTarget,
      mayRejectSource: mayRejectSource,
    );
    if (!mayRejectSource) {
      unawaited(_flushProgress(force: true));
    }
  }

  bool _isAndroidDirectTarget(PlaybackTarget target) {
    return !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        target.isDirectPlayable;
  }

  bool _isNativeAndroidDirectTarget(PlaybackTarget target) {
    return _isAndroidDirectTarget(target) &&
        _playbackSurface is _NativeStreamPlaybackSurfaceController;
  }

  void _resetDirectStartupStability() {
    _directStartupStabilitySignature = null;
    _directStartupHealthySince = null;
    _directStartupProgressAnchor = null;
    _directStartupStable = false;
  }

  PlaybackRendererProfile _resolveRendererProfileForLoad(
    PlaybackTarget target,
    PlaybackRendererProfile requestedProfile,
  ) {
    if (_isAndroidDirectTarget(target)) {
      return PlaybackRendererProfile.standard;
    }
    return requestedProfile;
  }

  bool _isDirectPlaybackStableForUi(
    PlaybackTarget target,
    PlaybackPresentation presentation,
  ) {
    if (!_isNativeAndroidDirectTarget(target)) {
      return presentation.hasVisibleVideo;
    }

    final stabilitySignature = _playbackTargetSignature(target);
    if (_directStartupStabilitySignature != stabilitySignature) {
      _directStartupStabilitySignature = stabilitySignature;
      _directStartupHealthySince = null;
      _directStartupProgressAnchor = null;
      _directStartupStable = false;
    }

    if (_resumePending || _resumeIntentInFlight) {
      _directStartupHealthySince = null;
      _directStartupProgressAnchor = null;
      _directStartupStable = false;
      return false;
    }

    if (!presentation.hasVisibleVideo || presentation.isBuffering) {
      _directStartupHealthySince = null;
      _directStartupProgressAnchor = null;
      _directStartupStable = false;
      return false;
    }

    final now = DateTime.now();
    _directStartupHealthySince ??= now;
    _directStartupProgressAnchor ??= presentation.currentPosition;
    final progressed =
        presentation.currentPosition - _directStartupProgressAnchor!;
    if (!_directStartupStable &&
        progressed >= _minimumConfirmedPlaybackProgress &&
        now.difference(_directStartupHealthySince!) >=
            _androidDirectStartupStabilityWindow) {
      _directStartupStable = true;
    }
    return _directStartupStable;
  }

  bool _isSeekPresentationSettled(
    PlaybackPresentation presentation,
    Duration target,
  ) {
    if ((presentation.currentPosition - target).abs() > _seekLoadingTolerance) {
      return false;
    }
    final committedTarget = _committedTarget;
    if (committedTarget != null && committedTarget.isDirectPlayable) {
      return !presentation.isBuffering && presentation.hasVisibleVideo;
    }
    return true;
  }

  void _syncDirectPlaybackVisibility(PlaybackPresentation presentation) {
    // During a source switch the surface state can flip to the new media
    // before the target is formally committed, so follow the pending target
    // to avoid attributing startup failures to the outgoing source.
    final target = _visibleTarget;
    if (target == null || !target.isDirectPlayable) {
      _resetDirectStartupStability();
      _directFrameTimeoutTimer?.cancel();
      _directNoFrameRecoveryTargetSignature = null;
      return;
    }

    final hasVisibleVideo = presentation.hasVisibleVideo;
    final hasConfirmedPlayback = _hasConfirmedPlayableTarget(target);
    final stableForUi = hasConfirmedPlayback ||
        _isDirectPlaybackStableForUi(target, presentation);
    final startupStabilizing =
        !hasConfirmedPlayback && hasVisibleVideo && !stableForUi;
    if (stableForUi) {
      if (!hasConfirmedPlayback &&
          _isConfirmedPlayablePresentation(target, presentation)) {
        _markTargetPlaybackConfirmed(target);
      }
      // Metadata, dimensions, or a decoded-but-static surface are not proof
      // that playback started. Keep the bounded startup watchdog armed until
      // the native timeline has genuinely advanced and the target has been
      // confirmed. This lets a segment-validated source that stalls at 0:00
      // fail over to the next candidate instead of hanging forever.
      if (_hasConfirmedPlayableTarget(target)) {
        _directFrameTimeoutTimer?.cancel();
        _directNoFrameRecoveryTargetSignature = null;
      }
    } else if (_shouldRecoverFromDirectNoFrame(target, presentation)) {
      _triggerDirectNoFrameRecovery(
        target,
        presentation,
        triggerReason:
            '${target.providerLabel} played audio without a visible video frame.',
      );
    }

    final nextSurfaceReady = stableForUi;
    final nextSurfaceLoading = !stableForUi;
    final nextStatusMessage = stableForUi
        ? 'Playing from ${target.providerLabel}.'
        : startupStabilizing
            ? 'Stabilizing video from ${target.providerLabel}...'
            : 'Waiting for the first video frame from ${target.providerLabel}...';

    if (_surfaceReady == nextSurfaceReady &&
        _surfaceLoading == nextSurfaceLoading &&
        _statusMessage == nextStatusMessage) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _surfaceReady = nextSurfaceReady;
      _surfaceLoading = nextSurfaceLoading;
      _statusMessage = nextStatusMessage;
    });
  }

  void _syncEmbedPlaybackVisibility(PlaybackPresentation presentation) {
    final target = _visibleTarget;
    if (target == null || target.isDirectPlayable) {
      return;
    }
    final ready = presentation.bridgeAvailable &&
        presentation.hasVisibleVideo &&
        presentation.totalDuration > Duration.zero;
    if (!ready || !mounted) {
      return;
    }
    _embedPromotionTimeoutTimer?.cancel();
    _embedPromotionTimeoutTimer = null;
    _playbackStartupEscapeTimer?.cancel();
    _playbackStartupEscapeTimer = null;
    if (_surfaceReady && !_surfaceLoading) {
      return;
    }
    setState(() {
      _surfaceReady = true;
      _surfaceLoading = false;
      _statusMessage = 'Playing from ${target.providerLabel}.';
    });
  }

  bool _hasConfirmedPlayableTarget(PlaybackTarget target) {
    return _confirmedPlayableTargetSignatures.contains(
      _playbackTargetSignature(target),
    );
  }

  void _markTargetPlaybackConfirmed(PlaybackTarget target) {
    final firstConfirmation = _confirmedPlayableTargetSignatures.add(
      _playbackTargetSignature(target),
    );
    if (!firstConfirmation) {
      return;
    }
    final diagnosticSessionId = target.diagnosticSessionId;
    if (diagnosticSessionId != null) {
      final startupDuration =
          PlaybackDiagnostics.instance.elapsedForSession(diagnosticSessionId);
      if (startupDuration != null) {
        _confirmedStartupDurations[_playbackTargetSignature(target)] =
            startupDuration;
      }
      PlaybackDiagnostics.instance.record(
        sessionId: diagnosticSessionId,
        stage: PlaybackDiagnosticStage.firstFrame,
        providerKey: target.providerKey,
        outcome: 'playable',
        details: <String, Object?>{
          'initialPositionMs':
              _playbackSurface.playerState.value.currentPosition.inMilliseconds,
        },
      );
      PlaybackDiagnostics.instance.record(
        sessionId: diagnosticSessionId,
        stage: PlaybackDiagnosticStage.initialBuffer,
        providerKey: target.providerKey,
        outcome: 'startup-stable',
        details: <String, Object?>{
          'startupReadAheadTargetSeconds': _nativeStartupReadAhead.inSeconds,
          'startupCushionSeconds': _nativeStartupCushion.inSeconds,
        },
      );
      PlaybackDiagnostics.instance.finishSession(diagnosticSessionId);
    }
    final surface = _playbackSurface;
    if (surface is PlaybackReadAheadController) {
      unawaited(
        (surface as PlaybackReadAheadController).promoteReadAheadAfterStartup(),
      );
    }
  }

  bool _isConfirmedPlayablePresentation(
    PlaybackTarget target,
    PlaybackPresentation presentation,
  ) {
    if (presentation.isBuffering || !presentation.hasVisibleVideo) {
      return false;
    }
    if (target.isDirectPlayable) {
      if (_isNativeAndroidDirectTarget(target)) {
        return _directStartupStable;
      }
      return presentation.currentPosition >= _minimumConfirmedPlaybackProgress;
    }
    return presentation.bridgeAvailable &&
        presentation.currentPosition >= _minimumConfirmedPlaybackProgress;
  }

  bool _shouldRecoverFromDirectNoFrame(
    PlaybackTarget target,
    PlaybackPresentation presentation,
  ) {
    if (_resolvingSource ||
        (_hasConfirmedPlayableTarget(target) && !_hasTargetExpired(target)) ||
        _pendingTarget != null ||
        presentation.hasVisibleVideo ||
        presentation.isBuffering ||
        _activeSeekOperations > 0 ||
        _pendingSeekTarget != null) {
      return false;
    }
    return presentation.currentPosition >= const Duration(seconds: 2);
  }

  bool _hasTargetExpired(PlaybackTarget target) {
    final expiresAtEpochMs = target.expiresAtEpochMs;
    if (expiresAtEpochMs == null) {
      return false;
    }
    return DateTime.now().millisecondsSinceEpoch >= expiresAtEpochMs;
  }

  void _triggerDirectNoFrameRecovery(
    PlaybackTarget target,
    PlaybackPresentation presentation, {
    required String triggerReason,
  }) {
    final targetSignature = _playbackTargetSignature(target);
    if (_directNoFrameRecoveryTargetSignature == targetSignature) {
      return;
    }
    _directNoFrameRecoveryTargetSignature = targetSignature;
    _logPlayerDiagnostic(
      'Detected progressing playback without visible frame. '
      'provider=${target.providerLabel} '
      'position=${presentation.currentPosition} '
      'duration=${presentation.totalDuration} '
      'buffering=${presentation.isBuffering}. '
      'Triggering recovery path.',
    );
    unawaited(
      _handleDirectNoFrameRecovery(
        target,
        triggerReason: triggerReason,
      ),
    );
  }

  Future<void> _handleDirectNoFrameRecovery(
    PlaybackTarget target, {
    required String triggerReason,
  }) async {
    if (!mounted) {
      return;
    }
    _surfaceLoadToken += 1;
    await _recoverFromSourceFailure(
      currentProviderIndex: target.providerIndex,
      failureKind: SourceFailureKind.startupStall,
      failureReason: '$triggerReason Trying the next source...',
    );
  }

  void _syncEmbedPromotionTimeout() {
    final target = _committedTarget;
    if (target == null || target.isDirectPlayable || !_surfaceReady) {
      return;
    }

    _embedPromotionTimeoutTimer?.cancel();
    _embedPromotionTimeoutTimer = null;
  }

  void _maybeRecordSourceSuccess(PlaybackPresentation presentation) {
    final target = _committedTarget;
    if (!_surfaceReady || target == null) {
      return;
    }

    final targetSignature = _playbackTargetSignature(target);
    if (_recordedSuccessfulTargetSignature == targetSignature) {
      return;
    }

    final canRecordSuccess = target.isDirectPlayable
        ? Platform.isAndroid
            ? _isConfirmedPlayablePresentation(target, presentation)
            : !presentation.isPaused ||
                presentation.currentPosition > Duration.zero ||
                presentation.totalDuration > Duration.zero
        : presentation.bridgeAvailable &&
            presentation.currentPosition > Duration.zero;
    if (!canRecordSuccess) {
      return;
    }

    if (_isConfirmedPlayablePresentation(target, presentation)) {
      _markTargetPlaybackConfirmed(target);
    }
    _recordedSuccessfulTargetSignature = targetSignature;
    // Keep providers that failed during this title session quarantined. Clearing
    // them here lets two broken mirrors cycle back to one another forever.
    unawaited(
      widget.playbackProvider.recordSourceSuccess(
        profileId: widget.profileId,
        tmdbId: widget.tmdbId,
        mediaType: widget.mediaType,
        seasonNumber: _isTvEpisodePlayer ? _activeSeasonNumber : null,
        episodeNumber: _isTvEpisodePlayer ? _activeEpisodeNumber : null,
        providerIndex: target.providerIndex,
        startupDuration: _confirmedStartupDurations[targetSignature],
      ),
    );
  }

  String _playbackTargetSignature(PlaybackTarget target) {
    final playbackSignature = _directSourceSignature(
      providerIndex: target.providerIndex,
      uri: target.uri,
      sourceKind: target.sourceKind,
      httpHeaders: target.httpHeaders,
      pageUri: target.pageUri,
    );
    return '$playbackSignature|$_scrubFrameExtractionStrategyVersion';
  }

  void _setResumeAnchor(Duration position) {
    if (position < _resumeProgressGuardThreshold) {
      _clearResumeAnchor();
      return;
    }
    _resumeAnchorPosition = position;
    _lastTrustedPlaybackPosition = position;
    _resumePending = true;
    _resumeSeekIssued = false;
    _resumeSeekAttempts = 0;
  }

  void _clearResumeAnchor() {
    _resumeAnchorPosition = null;
    _resumePending = false;
    _resumeSeekIssued = false;
    _resumeSeekAttempts = 0;
    _resumeIntentInFlight = false;
  }

  bool _canAttemptResumeSeek(PlaybackPresentation presentation) {
    if (!_resumePending || _resumeSeekIssued) {
      return false;
    }
    if (!presentation.bridgeAvailable) {
      return false;
    }
    final committedTarget = _committedTarget;
    if (committedTarget == null || _pendingTarget != null || _resolvingSource) {
      return false;
    }
    // Native Android players can expose their bridge before the demuxer and
    // decoder are ready to accept seeks. Waiting for the first decoded video
    // frame prevents an early resume command from being rejected and then
    // incorrectly turning a healthy source into a playback failover. Embed
    // targets retain their previous bridge-only behaviour.
    if (committedTarget.isDirectPlayable && !presentation.hasVisibleVideo) {
      return false;
    }
    return true;
  }

  bool _isResumeAnchorInvalidForPresentation(
    PlaybackPresentation presentation,
    Duration targetPosition,
  ) {
    final expectedRuntimeMinutes = _expectedRuntimeMinutesForActiveContent;
    if (expectedRuntimeMinutes != null) {
      return targetPosition >=
          Duration(minutes: expectedRuntimeMinutes) -
              const Duration(minutes: 4);
    }
    final totalDuration = presentation.totalDuration;
    if (totalDuration <= Duration.zero) {
      return false;
    }
    return targetPosition >= totalDuration - _resumeNearEndThreshold;
  }

  bool _hasResumeSettled(
    PlaybackPresentation presentation,
    Duration targetPosition,
  ) {
    if ((presentation.currentPosition - targetPosition).abs() >
        _resumeSettleTolerance) {
      return false;
    }
    final committedTarget = _committedTarget;
    if (committedTarget != null && committedTarget.isDirectPlayable) {
      return !presentation.isBuffering && presentation.hasVisibleVideo;
    }
    return true;
  }

  bool _applyResumeIfNeeded(PlaybackPresentation presentation) {
    final targetPosition = _resumeAnchorPosition;
    if (!_resumePending || targetPosition == null) {
      return false;
    }

    if (_isResumeAnchorInvalidForPresentation(presentation, targetPosition)) {
      _clearResumeAnchor();
      return false;
    }

    if (_resumeIntentInFlight) {
      return true;
    }

    if (_hasResumeSettled(presentation, targetPosition)) {
      _armPostSeekRegressionGuard(
        targetPosition,
        mayRejectSource: true,
      );
      _clearResumeAnchor();
      return false;
    }

    if (!_canAttemptResumeSeek(presentation)) {
      return true;
    }

    _resumeSeekIssued = true;
    _resumeSeekAttempts += 1;
    _resumeIntentInFlight = true;
    final shouldRemainPaused = _pendingLoadShouldRemainPaused;
    unawaited(
      () async {
        try {
          await _playbackSurface
              .seekTo(targetPosition)
              .timeout(const Duration(seconds: 8));
          if (!mounted) {
            return;
          }
          await _applySwitchPlaybackIntent(
            shouldRemainPaused: shouldRemainPaused,
          );
          if (!mounted) {
            return;
          }
          await _playbackSurface.requestPlayerState();
          final actualPosition =
              _playbackSurface.playerState.value.currentPosition;
          if ((actualPosition - targetPosition).abs() >
              _resumeSettleTolerance) {
            if (_resumeSeekAttempts < _maxResumeSeekAttempts) {
              _logPlayerDiagnostic(
                'Resume seek has not settled; scheduling one bounded retry. '
                'target=${targetPosition.inMilliseconds}ms '
                'actual=${actualPosition.inMilliseconds}ms '
                'attempt=$_resumeSeekAttempts.',
              );
              _resumeSeekIssued = false;
              await Future<void>.delayed(const Duration(milliseconds: 350));
              if (mounted) {
                await _playbackSurface.requestPlayerState();
              }
            } else {
              _logPlayerDiagnostic(
                'Resume seek did not settle after $_resumeSeekAttempts attempts; '
                'releasing the anchor so playback and manual seeks can advance. '
                'target=${targetPosition.inMilliseconds}ms '
                'actual=${actualPosition.inMilliseconds}ms',
              );
              _armPostSeekRegressionGuard(
                targetPosition,
                mayRejectSource: true,
              );
              _clearResumeAnchor();
            }
          }
        } catch (error, stackTrace) {
          _logPlayerDiagnostic(
            'Initial resume seek failed.',
            error: error,
            stackTrace: stackTrace,
          );
          final activeTarget = _committedTarget;
          if (mounted &&
              activeTarget != null &&
              activeTarget.isDirectPlayable &&
              (activeTarget.uri.scheme == 'http' ||
                  activeTarget.uri.scheme == 'https')) {
            await _recoverFromRejectedSeek(
              activeTarget,
              targetPosition,
              reason: 'The stream could not resume at $targetPosition.',
            );
          } else if (mounted) {
            _resumeSeekIssued = false;
          }
        } finally {
          _resumeIntentInFlight = false;
          if (mounted) {
            _handlePlayerStateChanged();
          }
        }
      }(),
    );
    return true;
  }

  Future<void> _checkpointPlaybackProgress() async {
    if (!mounted || _playbackSurfaceTeardownStarted || !_surfaceReady) {
      return;
    }
    await _refreshProgressPresentation();
    if (!mounted) {
      return;
    }
    await _flushProgress();
  }

  Future<void> _refreshProgressPresentation() async {
    try {
      await _playbackSurface
          .requestPlayerState()
          .timeout(_progressStateRefreshTimeout);
    } catch (_) {
      // The last trustworthy presentation is still safe to flush on exit.
    }
  }

  bool _isPersistableProgressPresentation(
    PlaybackPresentation presentation,
  ) {
    if (!_surfaceReady ||
        !presentation.bridgeAvailable ||
        presentation.currentPosition.inMilliseconds < 0 ||
        _resumePending ||
        _isUnexpectedPlaybackPositionReset(presentation)) {
      return false;
    }
    if (_resumeAnchorPosition != null &&
        presentation.currentPosition < _resumeProgressGuardThreshold) {
      return false;
    }
    return true;
  }

  Future<void> _flushProgress({
    PlaybackPresentation? presentation,
    bool force = false,
    bool awaitCallbacks = false,
  }) {
    final callback = widget.onProgressChanged;
    final traktCallback = widget.onTraktPlaybackReported;
    if (callback == null && traktCallback == null) {
      return Future<void>.value();
    }

    final current = presentation ?? _playbackSurface.playerState.value;
    final reportingTemporarilyBlocked =
        _suppressProgressReporting || _stallRecoveryInFlight;
    PlaybackPresentation? progressPresentation;
    if (!reportingTemporarilyBlocked &&
        _isPersistableProgressPresentation(current)) {
      _lastPersistableProgressPresentation = current;
      progressPresentation = current;
    } else if (force) {
      progressPresentation = _lastPersistableProgressPresentation;
    }
    if (progressPresentation == null) {
      return Future<void>.value();
    }

    final delta =
        (progressPresentation.currentPosition - _lastReportedProgressPosition)
            .abs();
    final stateChanged = progressPresentation.isPaused != _lastReportedPaused;
    if (!force &&
        delta < _progressCheckpointInterval &&
        !stateChanged &&
        progressPresentation.currentPosition.inMilliseconds > 0) {
      return Future<void>.value();
    }

    _lastReportedProgressPosition = progressPresentation.currentPosition;
    _lastReportedPaused = progressPresentation.isPaused;
    final entry = _buildProgressEntry(progressPresentation);
    final pendingCallbacks = <Future<void>>[];
    if (callback != null) {
      final future = callback(entry);
      if (awaitCallbacks) {
        pendingCallbacks.add(future);
      } else {
        unawaited(future);
      }
    }
    if (traktCallback != null) {
      final future = traktCallback(entry, progressPresentation.isPaused);
      if (awaitCallbacks) {
        pendingCallbacks.add(future);
      } else {
        unawaited(future);
      }
    }
    if (pendingCallbacks.isEmpty) {
      return Future<void>.value();
    }
    return Future.wait<void>(pendingCallbacks).then<void>((_) {}).catchError(
      (Object error, StackTrace stackTrace) {
        _logPlayerDiagnostic(
          'Saving playback progress failed.',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
  }

  PlaybackProgressEntry _buildProgressEntry(PlaybackPresentation presentation) {
    final episodeSummary = _activeEpisodeSummary;
    return PlaybackProgressEntry(
      summary: _summary ??
          widget.initialSummary ??
          MediaSummary(
            tmdbId: widget.tmdbId,
            mediaType: widget.mediaType,
            title: widget.mediaType == MediaType.tv
                ? 'Episode $_activeEpisodeNumber'
                : 'Movie',
          ),
      seasonNumber: _isTvEpisodePlayer ? _activeSeasonNumber : null,
      episodeNumber: _isTvEpisodePlayer ? _activeEpisodeNumber : null,
      episodeTitle: _isTvEpisodePlayer
          ? episodeSummary?.title ?? 'Episode $_activeEpisodeNumber'
          : null,
      episodeStillPath: _isTvEpisodePlayer ? episodeSummary?.stillPath : null,
      position: presentation.currentPosition,
      totalDuration: presentation.totalDuration,
      updatedAt: DateTime.now().toUtc(),
    );
  }
}
