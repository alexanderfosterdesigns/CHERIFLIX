part of 'player_screen.dart';

class _PlaybackSurfaceException implements Exception {
  const _PlaybackSurfaceException(this.message);

  final String message;
}

PlaybackSurfaceController _defaultPlaybackSurfaceFactory() {
  return _AdaptivePlaybackSurfaceController();
}

enum _PlaybackSurfaceMode {
  direct,
  extractingDirectSource,
}

class _AdaptivePlaybackSurfaceController
    implements
        PlaybackSurfaceController,
        PlaybackFrameExtractor,
        PlaybackReadAheadController {
  _AdaptivePlaybackSurfaceController({
    PlaybackSurfaceController? directController,
    PlaybackSurfaceController? embedController,
  })  : _directController =
            directController ?? _NativeStreamPlaybackSurfaceController(),
        _embedController =
            embedController ?? _InAppPlaybackSurfaceController() {
    _subscriptions.addAll(<StreamSubscription<PlaybackSurfaceEvent>>[
      _directController.events.listen((event) {
        if (_activeMode.value == _PlaybackSurfaceMode.direct) {
          _events.add(event);
        }
      }),
      _embedController.events.listen((event) {
        if (_activeMode.value != _PlaybackSurfaceMode.extractingDirectSource) {
          return;
        }
        if (event is PlaybackSurfacePlayerStateChanged) {
          return;
        }
        if (_activeMode.value == _PlaybackSurfaceMode.extractingDirectSource) {
          _events.add(event);
        }
      }),
    ]);
    _directController.playerState.addListener(_handleDirectPlayerStateChanged);
    _embedController.playerState.addListener(_handleEmbedPlayerStateChanged);
    _handleDirectPlayerStateChanged();
  }

  final PlaybackSurfaceController _directController;
  final PlaybackSurfaceController _embedController;
  final StreamController<PlaybackSurfaceEvent> _events =
      StreamController<PlaybackSurfaceEvent>.broadcast();
  final ValueNotifier<PlaybackPresentation> _playerState =
      ValueNotifier<PlaybackPresentation>(const PlaybackPresentation());
  final ValueNotifier<_PlaybackSurfaceMode> _activeMode =
      ValueNotifier<_PlaybackSurfaceMode>(_PlaybackSurfaceMode.direct);
  final List<StreamSubscription<PlaybackSurfaceEvent>> _subscriptions =
      <StreamSubscription<PlaybackSurfaceEvent>>[];
  Duration _pendingSubtitleDelay = Duration.zero;
  Duration _pendingAudioDelay = Duration.zero;
  bool _initialized = false;

  @override
  Stream<PlaybackSurfaceEvent> get events => _events.stream;

  @override
  ValueListenable<PlaybackPresentation> get playerState => _playerState;

  @override
  ValueListenable<List<String>> get subtitleLines => _controlsPlaybackDirectly
      ? _directController.subtitleLines
      : _embedController.subtitleLines;

  bool get _controlsPlaybackDirectly =>
      _activeMode.value == _PlaybackSurfaceMode.direct;
  String get debugActiveModeLabel => _activeMode.value.name;
  bool get canApplySubtitleDelayImmediately => _controlsPlaybackDirectly;

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    await _directController.initialize();
    await _embedController.initialize();
    _handleDirectPlayerStateChanged();
  }

  @override
  Future<void> load(PlaybackLoadRequest request) async {
    if (request.sourceKind == PlaybackSourceKind.embed) {
      if (_activeMode.value == _PlaybackSurfaceMode.direct) {
        await _pauseControllerIfPlaying(_directController);
      }
      _activeMode.value = _PlaybackSurfaceMode.extractingDirectSource;
      _playerState.value = _presentationForHiddenExtraction(request);
      await _embedController.load(request);
      return;
    }

    if (_activeMode.value == _PlaybackSurfaceMode.extractingDirectSource) {
      await _pauseControllerIfPlaying(_embedController);
    }
    _activeMode.value = _PlaybackSurfaceMode.direct;
    _handleDirectPlayerStateChanged();
    await _directController.load(request);
    await _directController.setSubtitleDelay(_pendingSubtitleDelay);
    await _directController.setAudioDelay(_pendingAudioDelay);
    _handleDirectPlayerStateChanged();
  }

  @override
  Widget buildView() {
    return ValueListenableBuilder<_PlaybackSurfaceMode>(
      valueListenable: _activeMode,
      builder: (context, mode, child) {
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _directController.buildView(),
            if (mode == _PlaybackSurfaceMode.extractingDirectSource)
              Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 1,
                  height: 1,
                  child: IgnorePointer(
                    child: _embedController.buildView(),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Future<void> requestPlayerState() async {
    if (!_controlsPlaybackDirectly) {
      return;
    }
    await _directController.requestPlayerState();
  }

  @override
  Future<void> play() async {
    if (!_controlsPlaybackDirectly) {
      return;
    }
    await _directController.play();
  }

  @override
  Future<void> pause() async {
    if (!_controlsPlaybackDirectly) {
      return;
    }
    await _directController.pause();
  }

  @override
  Future<void> togglePlayPause() async {
    if (!_controlsPlaybackDirectly) {
      return;
    }
    await _directController.togglePlayPause();
  }

  @override
  Future<void> attemptAutoplay() async {
    if (!_controlsPlaybackDirectly) {
      return;
    }
    await _directController.attemptAutoplay();
  }

  @override
  Future<void> seekBy(Duration offset) async {
    if (!_controlsPlaybackDirectly) {
      return;
    }
    await _directController.seekBy(offset);
  }

  @override
  Future<void> seekTo(Duration position) async {
    if (!_controlsPlaybackDirectly) {
      return;
    }
    await _directController.seekTo(position);
  }

  @override
  Future<void> toggleMute() async {
    if (!_controlsPlaybackDirectly) {
      return;
    }
    await _directController.toggleMute();
  }

  @override
  Future<void> cyclePlaybackRate() async {
    if (!_controlsPlaybackDirectly) {
      return;
    }
    await _directController.cyclePlaybackRate();
  }

  @override
  Future<void> stepPlaybackRate(int direction) async {
    if (!_controlsPlaybackDirectly) {
      return;
    }
    await _directController.stepPlaybackRate(direction);
  }

  @override
  Future<void> toggleCaptions() async {
    if (!_controlsPlaybackDirectly) {
      return;
    }
    await _directController.toggleCaptions();
  }

  @override
  Future<void> selectAudioTrack(String trackId) async {
    if (!_controlsPlaybackDirectly) {
      return;
    }
    await _directController.selectAudioTrack(trackId);
  }

  @override
  Future<void> selectCaptionTrack(String? trackId) async {
    if (!_controlsPlaybackDirectly) {
      return;
    }
    await _directController.selectCaptionTrack(trackId);
  }

  @override
  Future<void> setCaptionTracks(
    List<CaptionTrack> tracks, {
    String? selectedTrackId,
  }) async {
    if (!_controlsPlaybackDirectly) {
      return;
    }
    await _directController.setCaptionTracks(
      tracks,
      selectedTrackId: selectedTrackId,
    );
  }

  @override
  Future<void> setAudioDelay(Duration offset) async {
    _pendingAudioDelay = offset;
    if (!_controlsPlaybackDirectly) {
      return;
    }
    await _directController.setAudioDelay(offset);
  }

  @override
  Future<void> setSubtitleDelay(Duration offset) async {
    _pendingSubtitleDelay = offset;
    if (!_controlsPlaybackDirectly) {
      return;
    }
    await _directController.setSubtitleDelay(offset);
  }

  @override
  Future<void> cycleQuality() async {
    if (!_controlsPlaybackDirectly) {
      return;
    }
    await _directController.cycleQuality();
  }

  @override
  Future<void> adjustZoom(double delta) async {
    if (!_controlsPlaybackDirectly) {
      return;
    }
    await _directController.adjustZoom(delta);
  }

  @override
  Future<void> quietStop() async {
    await _directController.quietStop();
    await _embedController.quietStop();
    _activeMode.value = _PlaybackSurfaceMode.direct;
    _handleDirectPlayerStateChanged();
  }

  @override
  Future<Uint8List?> extractFrame(Duration position) async {
    if (!_controlsPlaybackDirectly) {
      return null;
    }
    final directController = _directController;
    if (directController is! PlaybackFrameExtractor) {
      return null;
    }
    return (directController as PlaybackFrameExtractor).extractFrame(position);
  }

  @override
  Future<void> promoteReadAheadAfterStartup() async {
    if (!_controlsPlaybackDirectly) {
      return;
    }
    final controller = _directController;
    if (controller is PlaybackReadAheadController) {
      await (controller as PlaybackReadAheadController)
          .promoteReadAheadAfterStartup();
    }
  }

  void _handleDirectPlayerStateChanged() {
    if (_activeMode.value != _PlaybackSurfaceMode.direct) {
      return;
    }
    _playerState.value = _directController.playerState.value;
  }

  void _handleEmbedPlayerStateChanged() {
    if (_activeMode.value != _PlaybackSurfaceMode.extractingDirectSource) {
      return;
    }
    final current = _playerState.value;
    _playerState.value = current.copyWith(
      captionTracks: current.captionTracks,
      selectedCaptionTrackId: current.selectedCaptionTrackId,
      selectedCaptionLabel: current.selectedCaptionLabel,
      captionsAvailable: current.captionsAvailable,
      captionsEnabled: current.captionsEnabled,
      bridgeAvailable: false,
      currentPosition: Duration.zero,
      totalDuration: Duration.zero,
      isPaused: true,
      isMuted: false,
      playbackRate: 1,
    );
  }

  PlaybackPresentation _presentationForHiddenExtraction(
    PlaybackLoadRequest request,
  ) {
    return PlaybackPresentation(
      isPaused: true,
      bridgeAvailable: false,
      captionTracks: request.captionTracks,
      selectedCaptionTrackId: request.selectedCaptionTrackId,
      selectedCaptionLabel: _selectedCaptionLabelForTracks(
        request.captionTracks,
        request.selectedCaptionTrackId,
      ),
      captionsAvailable: request.captionTracks.isNotEmpty,
      captionsEnabled: request.selectedCaptionTrackId != null,
    );
  }

  String _selectedCaptionLabelForTracks(
    List<CaptionTrack> tracks,
    String? selectedTrackId,
  ) {
    return _genericTrackLabelForId(tracks, selectedTrackId);
  }

  Future<void> _pauseControllerIfPlaying(
    PlaybackSurfaceController controller,
  ) async {
    if (controller.playerState.value.isPaused) {
      return;
    }
    try {
      await controller.pause();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    _directController.playerState
        .removeListener(_handleDirectPlayerStateChanged);
    _embedController.playerState.removeListener(_handleEmbedPlayerStateChanged);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await quietStop();
    _activeMode.dispose();
    _playerState.dispose();
    _events.close();
    await _directController.dispose();
    await _embedController.dispose();
  }
}

const Duration _thumbnailMediaWarmupDelay = Duration(milliseconds: 45);
const int _scrubThumbnailTargetWidth = 128;
const int _scrubThumbnailTargetHeight = 72;
const int _scrubThumbnailJpegQuality = 24;

@visibleForTesting
bool shouldMountThumbnailRendererStrip({
  required bool isAndroid,
  required PlaybackSourceKind? activeMediaSourceKind,
  required int mountedSlotCount,
}) {
  if (mountedSlotCount <= 0) {
    return false;
  }
  if (!isAndroid) {
    return true;
  }
  return activeMediaSourceKind == PlaybackSourceKind.hls;
}

class _NativeStreamPlaybackSurfaceController
    implements
        PlaybackSurfaceController,
        PlaybackFrameExtractor,
        PlaybackReadAheadController {
  static const Size _fallbackVideoOutputSize = Size(1280, 720);
  static const double _maxVideoOutputWidth = 1920;
  static const double _maxVideoOutputHeight = 1080;
  static const Duration _videoOutputResizeDebounce =
      Duration(milliseconds: 120);
  static const int _androidThumbnailExtractionSlotCount = 1;
  static const int _desktopThumbnailExtractionSlotCount = 2;
  static const int _thumbnailBackgroundQueueLimit = 4;
  static const int _thumbnailPriorityQueueLimit = 3;
  static const Duration _thumbnailSeekSettleDelay = Duration(milliseconds: 55);
  static const Duration _playbackSeekSettleDelay = Duration(milliseconds: 180);
  static const Duration _playbackSeekWaitTimeout = Duration(seconds: 2);
  static const Duration _playbackSeekTolerance = Duration(milliseconds: 450);
  static const Duration _subtitleTrackApplyTimeout = Duration(seconds: 4);
  static const Duration _frameHealthProbePlaybackThreshold =
      Duration(milliseconds: 2500);
  static const Duration _frameHealthProbeFollowUpDelay =
      Duration(milliseconds: 650);
  static const Duration _frameHealthStartupTelemetryWindow =
      Duration(seconds: 12);
  static const bool _enableAndroidEmergencyFrameMirror = bool.fromEnvironment(
    'CHERIFLIX_ANDROID_EMERGENCY_FRAME_MIRROR',
    defaultValue: false,
  );
  static const Duration _frameMirrorCaptureInterval =
      Duration(milliseconds: 420);
  static const Duration _frameMirrorWarmupVisibleThreshold =
      Duration(milliseconds: 1800);
  static const double _defaultPlaybackVolume = kCheriflixDefaultPlaybackVolume;
  // Keep enough RAM read-ahead for unstable TV Wi-Fi without forcing the
  // viewer to wait for a huge cache before the first frame. Disk caching HLS
  // playlists can also preserve stale signed segments across recovery.
  static const int _streamingBufferSizeBytes = 96 * 1024 * 1024;
  static const Duration _startupReadAhead = _nativeStartupReadAhead;
  static const Duration _startupCushion = _nativeStartupCushion;
  static const Duration _stableReadAhead = _nativeStableReadAhead;
  static const Duration _stableRebufferCushion = _nativeStableRebufferCushion;

  _NativeStreamPlaybackSurfaceController() {
    _player = _createPlayer();
    _videoController =
        _createVideoController(_rendererProfile, player: _player);
    _bindAndroidWidTracking(_videoController);
    _thumbnailSlots.addAll(
      List<_ThumbnailExtractionSlot>.generate(
        _thumbnailExtractionSlotCountForPlatform(),
        (_) => _ThumbnailExtractionSlot(
          onControllerAllocated: _notifyThumbnailStripChanged,
        ),
      ),
    );
    _availableThumbnailSlots.addAll(_thumbnailSlots);
  }

  final StreamController<PlaybackSurfaceEvent> _events =
      StreamController<PlaybackSurfaceEvent>.broadcast();
  final ValueNotifier<PlaybackPresentation> _playerState =
      ValueNotifier<PlaybackPresentation>(
    const PlaybackPresentation(
      bridgeAvailable: true,
    ),
  );
  final ValueNotifier<List<String>> _subtitleLines =
      ValueNotifier<List<String>>(const <String>[]);

  late Player _player;
  late VideoController _videoController;
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  List<CaptionTrack> _captionTracks = const <CaptionTrack>[];
  String? _selectedCaptionTrackId;
  double _lastNonZeroVolume = _defaultPlaybackVolume;
  bool _userAdjustedVolumeDuringSession = false;
  bool _userMutedPlayback = false;
  bool _initialized = false;
  bool _aggressiveReadAheadEnabled = false;
  Stopwatch? _startupTimeline;
  bool _loggedMetadataReady = false;
  bool _loggedDecoderReady = false;
  bool _loggedFirstTimelineProgress = false;
  bool? _lastLoggedBuffering;
  Size? _configuredVideoOutputSize;
  Uri? _activeMediaUri;
  Map<String, String> _activeMediaHeaders = const <String, String>{};
  PlaybackSourceKind? _activeMediaSourceKind;
  String _preferredAudioLanguage = 'en';
  String? _activeProviderKey;
  String? _activeOriginalLanguageCode;
  String? _manualAudioTrackId;
  Duration _audioDelay = Duration.zero;
  bool _disposed = false;
  PlaybackRendererProfile _rendererProfile = PlaybackRendererProfile.standard;
  bool _renderHealthChecked = false;
  bool _hasVerifiedVideoFrame = true;
  bool _renderHealthProbeInFlight = false;
  int _renderHealthProbeGeneration = 0;
  int _renderHealthProbeAttemptCount = 0;
  Timer? _pendingVideoOutputResizeTimer;
  Size? _pendingVideoOutputSize;
  Future<bool>? _ffmpegAvailabilityFuture;
  bool _loggedFfmpegUnavailableForScrubber = false;
  final Queue<_ThumbnailExtractionTask> _priorityThumbnailExtractionQueue =
      Queue<_ThumbnailExtractionTask>();
  final Queue<_ThumbnailExtractionTask> _thumbnailExtractionQueue =
      Queue<_ThumbnailExtractionTask>();
  final Queue<_ThumbnailExtractionSlot> _availableThumbnailSlots =
      Queue<_ThumbnailExtractionSlot>();
  final List<_ThumbnailExtractionSlot> _thumbnailSlots =
      <_ThumbnailExtractionSlot>[];
  final ValueNotifier<int> _thumbnailStripGeneration = ValueNotifier<int>(0);
  final ValueNotifier<Uint8List?> _frameMirrorImage =
      ValueNotifier<Uint8List?>(null);
  bool _thumbnailQueueScheduled = false;
  Future<void> _playerCommandQueue = Future<void>.value();
  ValueListenable<dynamic>? _androidWidListenable;
  VoidCallback? _androidWidListener;
  int _latestAndroidWid = 0;
  bool _loggedMissingAndroidWid = false;
  int _lastObservedAndroidFrameCallbackCount = -1;
  Timer? _frameMirrorTimer;
  bool _frameMirrorCaptureInFlight = false;
  int _frameMirrorGeneration = 0;

  @override
  Stream<PlaybackSurfaceEvent> get events => _events.stream;

  @override
  ValueListenable<PlaybackPresentation> get playerState => _playerState;

  @override
  ValueListenable<List<String>> get subtitleLines => _subtitleLines;

  Future<T> _runSerializedPlayerCommand<T>(
    String label,
    Future<T> Function() command,
  ) {
    final previous = _playerCommandQueue;
    final gate = Completer<void>();
    _playerCommandQueue = gate.future;
    return previous.catchError((_) {}).then((_) async {
      try {
        final result = await command();
        return result;
      } catch (error, stackTrace) {
        _logPlayerDiagnostic(
          'Native playback command failed: $label.',
          error: error,
          stackTrace: stackTrace,
        );
        rethrow;
      } finally {
        if (!gate.isCompleted) {
          gate.complete();
        }
      }
    });
  }

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    try {
      _logPlayerDiagnostic('Native playback controller initialize() started.');
      _initialized = true;
      _attachPlaybackRuntimeListeners();
      await _applyStreamingBufferConfiguration(aggressive: false);
      await _applyPlaybackVolumeForNewPlayer();
      _emitPlayerState();
      unawaited(_ensureFfmpegAvailability());
      _logPlayerDiagnostic('Native playback controller initialize() finished.');
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Native playback controller initialize() failed.',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Player _createPlayer() {
    return Player(
      configuration: const PlayerConfiguration(
        libass: false,
        bufferSize: _streamingBufferSizeBytes,
      ),
    );
  }

  Future<void> _applyStreamingBufferConfiguration({
    required bool aggressive,
  }) async {
    try {
      final readAhead = aggressive ? _stableReadAhead : _startupReadAhead;
      final cushion = aggressive ? _stableRebufferCushion : _startupCushion;
      _logPlayerDiagnostic(
        'Applying ${aggressive ? 'stable' : 'startup'} streaming buffer '
        'configuration readAheadSeconds=${readAhead.inSeconds} '
        'cushionSeconds=${cushion.inSeconds}.',
      );
      await _setNativePlaybackProperty(
        'cache-secs',
        '${readAhead.inSeconds}',
      );
      await _setNativePlaybackProperty(
        'demuxer-readahead-secs',
        '${readAhead.inSeconds}',
      );
      await _setNativePlaybackProperty('cache-pause', 'yes');
      await _setNativePlaybackProperty('cache-pause-initial', 'no');
      await _setNativePlaybackProperty('cache-on-disk', 'no');
      await _setNativePlaybackProperty(
        'cache-pause-wait',
        '${cushion.inSeconds}',
      );
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Failed to apply streaming buffer configuration.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _setNativePlaybackProperty(String name, String value) async {
    final dynamic native = _player.platform;
    if (native == null) {
      return;
    }
    // media_kit's public setProperty method calls mpv_set_property_string
    // synchronously. Changing cache properties while libmpv is actively
    // demuxing can then wait on mpv's core lock and freeze Android's UI thread.
    // The command API uses mpv_command_async with the default native player
    // configuration, so live cache/audio adjustments cannot cause an ANR.
    await native.command(<String>['set', name, value]);
  }

  int _thumbnailExtractionSlotCountForPlatform() {
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return isAndroid
        ? _androidThumbnailExtractionSlotCount
        : _desktopThumbnailExtractionSlotCount;
  }

  Future<void> _applyPlaybackVolumeForNewPlayer() async {
    final targetVolume = _userAdjustedVolumeDuringSession
        ? (_userMutedPlayback ? 0.0 : _lastNonZeroVolume)
        : _defaultPlaybackVolume;
    try {
      await _player.setVolume(targetVolume);
      if (targetVolume > 0) {
        _lastNonZeroVolume = targetVolume;
      }
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Failed to apply playback volume.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _attachPlaybackRuntimeListeners() {
    _subscriptions.addAll(<StreamSubscription<dynamic>>[
      _player.stream.position.listen((_) => _emitPlayerState()),
      _player.stream.duration.listen((_) => _emitPlayerState()),
      _player.stream.playing.listen((_) => _emitPlayerState()),
      _player.stream.buffering.listen((_) => _emitPlayerState()),
      _player.stream.bufferingPercentage.listen((_) => _emitPlayerState()),
      _player.stream.volume.listen((_) => _emitPlayerState()),
      _player.stream.rate.listen((_) => _emitPlayerState()),
      _player.stream.width.listen((_) => _emitPlayerState()),
      _player.stream.height.listen((_) => _emitPlayerState()),
      _player.stream.track.listen((_) => _emitPlayerState()),
      _player.stream.tracks.listen((_) => _emitPlayerState()),
      _player.stream.subtitle.listen(_updateSubtitleLines),
      _player.stream.error.listen((message) {
        _logPlayerDiagnostic(
          'Native player error uriHost=${_activeMediaUri?.host ?? '-'} '
          'message=$message',
        );
      }),
      _player.stream.log.listen((entry) {
        final level = entry.level.trim().toLowerCase();
        if (level == 'error' || level == 'fatal' || level == 'warn') {
          _logPlayerDiagnostic(
            'Native player log level=$level prefix=${entry.prefix} '
            'uriHost=${_activeMediaUri?.host ?? '-'} text=${entry.text}',
          );
        }
      }),
    ]);
    _videoController.id.addListener(_handleRenderedFrameStateChanged);
    _videoController.rect.addListener(_handleRenderedFrameStateChanged);
  }

  Future<void> _detachPlaybackRuntimeListeners() async {
    _videoController.id.removeListener(_handleRenderedFrameStateChanged);
    _videoController.rect.removeListener(_handleRenderedFrameStateChanged);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }

  @override
  Future<void> load(PlaybackLoadRequest request) {
    return _runSerializedPlayerCommand('load', () async {
      if (!_initialized) {
        await initialize();
      }
      await _ensureRendererProfile(request.rendererProfile);
      _aggressiveReadAheadEnabled = false;
      await _applyStreamingBufferConfiguration(aggressive: false);
      _logPlayerDiagnostic(
        'Native playback load() uri=${request.uri} '
        'renderer=${request.rendererProfile.name} '
        'headers=${jsonEncode(request.httpHeaders)}',
      );
      _activeMediaUri = request.uri;
      _startupTimeline = Stopwatch()..start();
      _loggedMetadataReady = false;
      _loggedDecoderReady = false;
      _loggedFirstTimelineProgress = false;
      _lastLoggedBuffering = null;
      _activeMediaHeaders =
          Map<String, String>.unmodifiable(request.httpHeaders);
      _activeMediaSourceKind = request.sourceKind;
      _preferredAudioLanguage = request.preferredAudioLanguage;
      _activeProviderKey = request.providerKey;
      _activeOriginalLanguageCode = request.originalLanguageCode;
      _manualAudioTrackId = null;
      _captionTracks = request.captionTracks;
      _selectedCaptionTrackId = request.selectedCaptionTrackId;
      _subtitleLines.value = const <String>[];
      _frameMirrorImage.value = null;
      _restartFrameMirrorCapture();
      _resetFrameHealthProbe();
      await _setPreferredAudioLanguageOption(_preferredAudioLanguage);
      await _player.open(
        Media(
          request.uri.toString(),
          httpHeaders: request.httpHeaders,
        ),
        play: false,
      );
      _captureFrameMirrorSample();
      _emitPlayerState();
      unawaited(_applyStartupTracksInBackground(request));
      _logPlayerDiagnostic(
        'Native playback load() finished '
        'duration=${_player.state.duration} '
        'width=${_player.state.width} height=${_player.state.height}',
      );
    });
  }

  @override
  Future<void> promoteReadAheadAfterStartup() {
    return _runSerializedPlayerCommand('promote-read-ahead', () async {
      if (_aggressiveReadAheadEnabled) {
        return;
      }
      _aggressiveReadAheadEnabled = true;
      await _applyStreamingBufferConfiguration(aggressive: true);
      _logPlayerDiagnostic(
        'Playback stable; promoted read-ahead to '
        '${_stableReadAhead.inSeconds}s.',
      );
    });
  }

  Future<void> _applyStartupTracksInBackground(
    PlaybackLoadRequest request,
  ) async {
    try {
      await _applyPreferredAudioTrack(request.preferredAudioLanguage);
      await _applySelectedCaptionTrack();
      _emitPlayerState();
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Deferred audio/caption track selection failed.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  String _audioLanguageLabel(String? languageCode) {
    final normalized =
        (languageCode ?? '').trim().toLowerCase().split(RegExp('[-_]')).first;
    return switch (normalized) {
      'en' || 'eng' => 'English',
      'es' || 'spa' => 'Spanish',
      'fr' || 'fra' || 'fre' => 'French',
      'de' || 'deu' || 'ger' => 'German',
      'it' || 'ita' => 'Italian',
      'pt' || 'por' => 'Portuguese',
      'ru' || 'rus' => 'Russian',
      'ja' || 'jpn' => 'Japanese',
      'ko' || 'kor' => 'Korean',
      'zh' || 'zho' || 'chi' => 'Chinese',
      'hi' || 'hin' => 'Hindi',
      _ => (languageCode ?? '').trim().toUpperCase(),
    };
  }

  List<PlaybackAudioTrack> _availableAudioTracks() {
    final tracks = _player.state.tracks.audio
        .where((track) => track.id != 'auto' && track.id != 'no')
        .toList(growable: false);
    return List<PlaybackAudioTrack>.generate(tracks.length, (index) {
      final track = tracks[index];
      final language = _audioLanguageLabel(track.language);
      final title = (track.title ?? '').trim();
      final label = language.isNotEmpty && title.isNotEmpty
          ? (title.toLowerCase().contains(language.toLowerCase())
              ? title
              : '$language — $title')
          : language.isNotEmpty
              ? language
              : title.isNotEmpty
                  ? title
                  : 'Audio ${index + 1}';
      return PlaybackAudioTrack(
        id: track.id,
        label: label,
        languageCode: track.language,
        title: track.title,
        providerKey: _activeProviderKey,
        sourceUri: _activeMediaUri,
        isOriginal: normalizeAudioLanguageCode(track.language ?? '').isEmpty ||
                normalizeAudioLanguageCode(
                  _activeOriginalLanguageCode ?? '',
                ).isEmpty
            ? null
            : normalizeAudioLanguageCode(track.language ?? '') ==
                normalizeAudioLanguageCode(_activeOriginalLanguageCode ?? ''),
      );
    });
  }

  String _selectedAudioTrackLabel(List<PlaybackAudioTrack> tracks) {
    final selectedId = _player.state.track.audio.id;
    for (final track in tracks) {
      if (track.id == selectedId) {
        return track.label;
      }
    }
    return tracks.isEmpty ? 'Unavailable' : 'Default';
  }

  Future<void> _applyPreferredAudioTrack(String languageCode) async {
    if (_manualAudioTrackId != null) {
      return;
    }
    final normalizedLanguage =
        languageCode.trim().toLowerCase().split(RegExp('[-_]')).first;
    if (normalizedLanguage.isEmpty) {
      return;
    }
    AudioTrack? findPreferred(List<AudioTrack> tracks) {
      for (final track in tracks) {
        if (track.id == 'auto' || track.id == 'no') {
          continue;
        }
        final language = (track.language ?? '').trim().toLowerCase();
        final title = (track.title ?? '').trim().toLowerCase();
        if (language == normalizedLanguage ||
            language.startsWith('$normalizedLanguage-') ||
            (normalizedLanguage == 'en' &&
                (language == 'eng' || title.contains('english')))) {
          return track;
        }
      }
      return null;
    }

    try {
      var preferred = findPreferred(_player.state.tracks.audio);
      if (preferred == null) {
        final tracks = await _player.stream.tracks
            .firstWhere((tracks) => findPreferred(tracks.audio) != null)
            .timeout(const Duration(seconds: 3));
        preferred = findPreferred(tracks.audio);
      }
      if (preferred != null && preferred.id != _player.state.track.audio.id) {
        await _player.setAudioTrack(preferred);
        _logPlayerDiagnostic(
          'Selected preferred audio track '
          'language=$normalizedLanguage id=${preferred.id} '
          'title=${preferred.title ?? '-'}',
        );
      }
    } catch (_) {
      // Keep the stream's default track when no preferred language is exposed.
    }
  }

  Future<void> _setPreferredAudioLanguageOption(String languageCode) async {
    final normalizedLanguage =
        languageCode.trim().toLowerCase().split(RegExp('[-_]')).first;
    if (normalizedLanguage.isEmpty) {
      return;
    }
    try {
      final priority =
          normalizedLanguage == 'en' ? 'en,eng' : normalizedLanguage;
      await _setNativePlaybackProperty('alang', priority);
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Failed to set preferred audio language before opening media.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Widget buildView() {
    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _syncVideoOutputSizeForLayout(
            constraints.biggest,
            MediaQuery.devicePixelRatioOf(context),
          );
          return ValueListenableBuilder<PlaybackPresentation>(
            valueListenable: _playerState,
            builder: (context, presentation, child) {
              final videoWidth = _player.state.width;
              final videoHeight = _player.state.height;
              final aspectRatio = videoWidth != null &&
                      videoHeight != null &&
                      videoWidth > 0 &&
                      videoHeight > 0
                  ? videoWidth / videoHeight
                  : null;
              final video = Video(
                controller: _videoController,
                controls: NoVideoControls,
                fit: presentation.zoomScale > 1 ? BoxFit.cover : BoxFit.contain,
                alignment: Alignment.center,
                subtitleViewConfiguration: const SubtitleViewConfiguration(
                  visible: false,
                ),
              );
              final laidOutVideo = aspectRatio == null
                  ? SizedBox.expand(child: video)
                  : Center(
                      child: AspectRatio(
                        aspectRatio: aspectRatio,
                        child: video,
                      ),
                    );
              final zoomedVideo = ClipRect(
                child: Transform.scale(
                  scale: presentation.zoomScale,
                  alignment: Alignment.center,
                  child: laidOutVideo,
                ),
              );
              final showFrameMirror = _shouldUseAndroidFrameMirror();
              final videoLayer = showFrameMirror
                  ? Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        zoomedVideo,
                        ValueListenableBuilder<Uint8List?>(
                          valueListenable: _frameMirrorImage,
                          builder: (context, bytes, child) {
                            return _buildFrameMirrorLayer(
                              frameBytes: bytes,
                              zoomScale: presentation.zoomScale,
                              aspectRatio: aspectRatio,
                            );
                          },
                        ),
                      ],
                    )
                  : zoomedVideo;

              return SizedBox.expand(
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    videoLayer,
                    ValueListenableBuilder<int>(
                      valueListenable: _thumbnailStripGeneration,
                      builder: (context, _, child) {
                        final mountedSlots = _thumbnailSlots
                            .where((slot) => slot.hasVideoController)
                            .toList(growable: false);
                        if (!_shouldMountThumbnailStrip(mountedSlots.length)) {
                          return const SizedBox.shrink();
                        }
                        return Positioned(
                          right: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: _HiddenThumbnailRendererStrip(
                              slots: mountedSlots,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  Future<void> requestPlayerState() async {
    _emitPlayerState();
  }

  @override
  Future<void> play() {
    return _runSerializedPlayerCommand('play', () async {
      await _player.play();
      await _applyPreferredAudioTrack(_preferredAudioLanguage);
      _emitPlayerState();
    });
  }

  @override
  Future<void> pause() {
    return _runSerializedPlayerCommand('pause', () async {
      await _player.pause();
      _emitPlayerState();
    });
  }

  @override
  Future<void> togglePlayPause() {
    return _runSerializedPlayerCommand('togglePlayPause', () async {
      final shouldPause = _player.state.playing;
      _playerState.value = _playerState.value.copyWith(isPaused: shouldPause);
      if (shouldPause) {
        await _player.pause();
      } else {
        await _player.play();
        await _applyPreferredAudioTrack(_preferredAudioLanguage);
      }
      _emitPlayerState();
    });
  }

  @override
  Future<void> attemptAutoplay() {
    return play();
  }

  @override
  Future<void> seekBy(Duration offset) {
    return _runSerializedPlayerCommand('seekBy', () async {
      final state = _player.state;
      var next = state.position + offset;
      if (next.isNegative) {
        next = Duration.zero;
      }
      if (state.duration > Duration.zero && next > state.duration) {
        next = state.duration;
      }
      await _player.seek(next);
      _emitPlayerState();
    });
  }

  @override
  Future<void> seekTo(Duration position) {
    return _runSerializedPlayerCommand('seekTo', () async {
      final target = _clampPlaybackPosition(position);
      final wasPlaying = _player.state.playing;
      if (wasPlaying) {
        await _player.pause();
      }
      await _player.seek(target);
      await _waitForPlayerPosition(
        target,
        timeout: _playbackSeekWaitTimeout,
        tolerance: _playbackSeekTolerance,
      );
      await Future<void>.delayed(_playbackSeekSettleDelay);
      _logPlayerDiagnostic(
        'Playback seek settled '
        'target=${target.inMilliseconds}ms '
        'actual=${_player.state.position.inMilliseconds}ms '
        'wasPlaying=$wasPlaying',
      );
      if (wasPlaying) {
        await _player.play();
      }
      _emitPlayerState();
    });
  }

  @override
  Future<void> toggleMute() {
    return _runSerializedPlayerCommand('toggleMute', () async {
      final volume = _player.state.volume;
      _userAdjustedVolumeDuringSession = true;
      if (volume > 0) {
        _lastNonZeroVolume = volume;
        _userMutedPlayback = true;
        await _player.setVolume(0);
      } else {
        _userMutedPlayback = false;
        await _player.setVolume(
          _lastNonZeroVolume <= 0 ? _defaultPlaybackVolume : _lastNonZeroVolume,
        );
      }
      _emitPlayerState();
    });
  }

  @override
  Future<void> cyclePlaybackRate() {
    return _runSerializedPlayerCommand('cyclePlaybackRate', () async {
      const rates = <double>[0.75, 1, 1.25, 1.5, 1.75, 2];
      final current = _player.state.rate;
      final currentIndex =
          rates.indexWhere((rate) => (rate - current).abs() < 0.01);
      final nextRate = rates[(currentIndex + 1 + rates.length) % rates.length];
      await _player.setRate(nextRate);
      _emitPlayerState();
    });
  }

  @override
  Future<void> stepPlaybackRate(int direction) {
    return _runSerializedPlayerCommand('stepPlaybackRate', () async {
      const rates = <double>[0.75, 1, 1.25, 1.5, 1.75, 2];
      final current = _player.state.rate;
      final currentIndex =
          rates.indexWhere((rate) => (rate - current).abs() < 0.01);
      final normalizedIndex = currentIndex < 0 ? 1 : currentIndex;
      final nextIndex =
          (normalizedIndex + direction).clamp(0, rates.length - 1);
      await _player.setRate(rates[nextIndex]);
      _emitPlayerState();
    });
  }

  @override
  Future<void> toggleCaptions() async {
    final nextTrackId =
        _selectedCaptionTrackId == null && _captionTracks.isNotEmpty
            ? _captionTracks.first.id
            : null;
    await _setSelectedCaptionTrackId(nextTrackId);
  }

  @override
  Future<void> selectAudioTrack(String trackId) {
    return _runSerializedPlayerCommand('selectAudioTrack', () async {
      final selected =
          _player.state.tracks.audio.cast<AudioTrack?>().firstWhere(
                (track) => track?.id == trackId,
                orElse: () => null,
              );
      if (selected == null || selected.id == 'auto' || selected.id == 'no') {
        return;
      }
      _manualAudioTrackId = selected.id;
      final wasPlaying = _player.state.playing;
      await _player.setAudioTrack(selected);
      if (wasPlaying && !_player.state.playing) {
        await _player.play();
      }
      _emitPlayerState();
    });
  }

  @override
  Future<void> selectCaptionTrack(String? trackId) {
    return _runSerializedPlayerCommand('selectCaptionTrack', () async {
      await _setSelectedCaptionTrackId(
        trackId,
        preservePlayback: _player.state.playing,
      );
    });
  }

  @override
  Future<void> setCaptionTracks(
    List<CaptionTrack> tracks, {
    String? selectedTrackId,
  }) {
    return _runSerializedPlayerCommand('setCaptionTracks', () async {
      _captionTracks = tracks;
      final nextSelection = selectedTrackId ??
          (_selectedCaptionTrackId != null &&
                  tracks.any((track) => track.id == _selectedCaptionTrackId)
              ? _selectedCaptionTrackId
              : tracks.isEmpty
                  ? null
                  : tracks.first.id);
      await _setSelectedCaptionTrackId(
        nextSelection,
        preservePlayback: _player.state.playing,
      );
    });
  }

  @override
  Future<void> setAudioDelay(Duration offset) {
    return _runSerializedPlayerCommand('setAudioDelay', () async {
      final clampedMs = offset.inMilliseconds.clamp(-5000, 5000).toInt();
      final clamped = Duration(milliseconds: clampedMs);
      final seconds = clampedMs / 1000;
      try {
        await _setNativePlaybackProperty(
          'audio-delay',
          seconds.toStringAsFixed(3),
        );
        _audioDelay = clamped;
      } catch (_) {}
      _emitPlayerState();
    });
  }

  @override
  Future<void> setSubtitleDelay(Duration offset) {
    return _runSerializedPlayerCommand('setSubtitleDelay', () async {
      final seconds = offset.inMilliseconds / 1000;
      try {
        await _setNativePlaybackProperty(
          'sub-delay',
          seconds.toStringAsFixed(3),
        );
      } catch (_) {}
    });
  }

  @override
  Future<void> cycleQuality() {
    return _runSerializedPlayerCommand('cycleQuality', () async {
      final videoTracks = _selectableVideoTracks();
      if (videoTracks.isEmpty) {
        _emitPlayerState();
        return;
      }

      final currentTrack = _player.state.track.video;
      final currentIndex = videoTracks
          .indexWhere((candidate) => candidate.id == currentTrack.id);
      final nextDisplayIndex = (currentIndex + 2) % (videoTracks.length + 1);
      if (nextDisplayIndex == 0) {
        await _player.setVideoTrack(VideoTrack.auto());
      } else {
        await _player.setVideoTrack(videoTracks[nextDisplayIndex - 1]);
      }
      _emitPlayerState();
    });
  }

  @override
  Future<void> adjustZoom(double delta) async {
    _playerState.value = _playerState.value.copyWith(
      zoomScale: (_playerState.value.zoomScale + delta)
          .clamp(_playerZoomMinScale, _playerZoomMaxScale)
          .toDouble(),
    );
    _events.add(
      PlaybackSurfacePlayerStateChanged(_playerState.value),
    );
  }

  @override
  Future<Uint8List?> extractFrame(Duration position) async {
    return _extractFrameInternal(position, prioritizeVisible: false);
  }

  Future<Uint8List?> extractFrameWithPriority(
    Duration position, {
    required bool prioritizeVisible,
  }) async {
    return _extractFrameInternal(
      position,
      prioritizeVisible: prioritizeVisible,
    );
  }

  Future<Uint8List?> _extractFrameInternal(
    Duration position, {
    required bool prioritizeVisible,
  }) async {
    if (_disposed) {
      return null;
    }
    final mediaUri = _activeMediaUri;
    if (mediaUri == null) {
      return null;
    }
    final normalizedPosition = _clampThumbnailPosition(position);
    final signature = _frameExtractionSignature(mediaUri, _activeMediaHeaders);
    if (prioritizeVisible) {
      _logPlayerDiagnostic(
        'Thumbnail extraction requested '
        'uri=$mediaUri '
        'position=${_formatFfmpegTimestamp(normalizedPosition)} '
        'signature=$signature '
        'priority=visible',
      );
    }

    final useFfmpeg = shouldUseFfmpegScrubExtraction(
      sourceKind: _activeMediaSourceKind,
      mediaUri: mediaUri,
    );
    if (useFfmpeg) {
      final ffmpegAvailable = await _ensureFfmpegAvailability();
      if (ffmpegAvailable) {
        final ffmpegBytes = await _acceptScrubFrameBytes(
          await _extractFrameWithFfmpeg(
            mediaUri: mediaUri,
            httpHeaders: _activeMediaHeaders,
            position: normalizedPosition,
          ),
          source: 'ffmpeg',
          position: normalizedPosition,
        );
        if (ffmpegBytes != null) {
          return ffmpegBytes;
        }
        _logPlayerDiagnostic(
          'ffmpeg extraction failed for '
          'position=${_formatFfmpegTimestamp(normalizedPosition)} '
          'and will fall back to media_kit screenshot.',
        );
      } else {
        if (!_loggedFfmpegUnavailableForScrubber) {
          _loggedFfmpegUnavailableForScrubber = true;
          _logPlayerDiagnostic(
            'ffmpeg is unavailable on PATH and the media_kit fallback will be '
            'used for scrub thumbnails.',
          );
        }
      }
    } else if (prioritizeVisible) {
      _logPlayerDiagnostic(
        'Skipping ffmpeg scrub extraction for '
        'sourceKind=${_activeMediaSourceKind?.name ?? 'unknown'} '
        'uri=$mediaUri '
        'position=${_formatFfmpegTimestamp(normalizedPosition)} '
        'because media_kit better matches playback timeline.',
      );
    }

    return _acceptScrubFrameBytes(
      await _extractFrameWithMediaKit(
        mediaUri: mediaUri,
        httpHeaders: _activeMediaHeaders,
        position: normalizedPosition,
        prioritizeVisible: prioritizeVisible,
      ),
      source: 'media_kit',
      position: normalizedPosition,
    );
  }

  Future<Uint8List?> _acceptScrubFrameBytes(
    Uint8List? bytes, {
    required String source,
    required Duration position,
  }) async {
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    if (await _isLikelyBlankScrubFrame(bytes)) {
      _logPlayerDiagnostic(
        'Rejected likely blank scrub frame '
        'source=$source '
        'position=${_formatFfmpegTimestamp(position)} '
        'bytes=${bytes.length}',
      );
      return null;
    }
    return bytes;
  }

  @override
  Future<void> quietStop() async {
    await _runSerializedPlayerCommand('quietStop', () async {
      try {
        await _player.pause();
      } catch (_) {}
      try {
        await _player.stop();
      } catch (_) {}
    });
    if (_disposed) {
      return;
    }
    _subtitleLines.value = const <String>[];
    _stopFrameMirrorPump();
    _frameMirrorImage.value = null;
    _resetFrameHealthProbe();
    _emitPlayerState();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    await quietStop();
    _disposed = true;
    _stopFrameMirrorPump();
    _unbindAndroidWidTracking();
    _pendingVideoOutputResizeTimer?.cancel();
    _pendingVideoOutputResizeTimer = null;
    _pendingVideoOutputSize = null;
    _drainPendingThumbnailRequests();
    await _disposePlaybackRuntime();
    for (final slot in _thumbnailSlots) {
      await slot.dispose();
    }
    _events.close();
    _subtitleLines.dispose();
    _thumbnailStripGeneration.dispose();
    _frameMirrorImage.dispose();
    _playerState.dispose();
  }

  Future<Uint8List?> _extractFrameWithFfmpeg({
    required Uri mediaUri,
    required Map<String, String> httpHeaders,
    required Duration position,
  }) async {
    final tempDirectory = await _createScrubFrameTempDirectory();
    final outputFile = _scrubFrameOutputFile(tempDirectory, position);
    try {
      _logPlayerDiagnostic(
        'ffmpeg extraction attempt '
        'uri=$mediaUri '
        'position=${_formatFfmpegTimestamp(position)} '
        'output=${outputFile.path}',
      );
      final inputPath = _ffmpegInputPath(mediaUri);
      final args = <String>[
        '-hide_banner',
        '-loglevel',
        'error',
        '-nostdin',
      ];
      final headerString = _ffmpegHeaderString(httpHeaders);
      if (headerString != null) {
        args.addAll(<String>['-headers', headerString]);
      }
      args.addAll(<String>[
        '-i',
        inputPath,
        // Seek after input so the scrub thumbnail matches the requested time
        // instead of snapping back to the previous keyframe.
        '-ss',
        _formatFfmpegTimestamp(position),
        '-frames:v',
        '1',
        '-vf',
        'scale=$_scrubThumbnailTargetWidth:-2',
        '-q:v',
        '$_scrubThumbnailJpegQuality',
        '-y',
        outputFile.path,
      ]);
      final result = await Process.run(
        'ffmpeg',
        args,
        runInShell: false,
      );
      final stdoutText = result.stdout.toString().trim();
      final stderrText = result.stderr.toString().trim();
      _logPlayerDiagnostic(
        'ffmpeg extraction finished '
        'exitCode=${result.exitCode} '
        'stdout=${stdoutText.isEmpty ? '<empty>' : stdoutText} '
        'stderr=${stderrText.isEmpty ? '<empty>' : stderrText}',
      );
      if (result.exitCode != 0 || _disposed) {
        return null;
      }
      if (!await outputFile.exists()) {
        _logPlayerDiagnostic(
          'ffmpeg extraction produced no output file at ${outputFile.path}.',
        );
        return null;
      }
      final fileLength = await outputFile.length();
      if (fileLength <= 0) {
        _logPlayerDiagnostic(
          'ffmpeg extraction wrote an empty file at ${outputFile.path}.',
        );
        return null;
      }
      final bytes = await outputFile.readAsBytes();
      if (bytes.isEmpty) {
        _logPlayerDiagnostic(
          'ffmpeg extraction bytes were empty for ${outputFile.path}.',
        );
        return null;
      }
      _logPlayerDiagnostic(
        'ffmpeg extraction succeeded '
        'bytes=${bytes.length} '
        'path=${outputFile.path}',
      );
      return bytes;
    } on ProcessException catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'ffmpeg extraction failed to start.',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'ffmpeg extraction failed unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    } finally {
      await _deleteDirectoryQuietly(tempDirectory);
    }
  }

  Future<Uint8List?> _extractFrameWithMediaKit({
    required Uri mediaUri,
    required Map<String, String> httpHeaders,
    required Duration position,
    required bool prioritizeVisible,
  }) async {
    if (_disposed) {
      return null;
    }

    final request = _ThumbnailExtractionTask(
      uri: mediaUri,
      httpHeaders: Map<String, String>.unmodifiable(httpHeaders),
      signature: _frameExtractionSignature(mediaUri, httpHeaders),
      position: position,
      prioritizeVisible: prioritizeVisible,
      sourceKind: _activeMediaSourceKind,
    );
    final queue = prioritizeVisible
        ? _priorityThumbnailExtractionQueue
        : _thumbnailExtractionQueue;
    _capThumbnailQueue(
      queue,
      prioritizeVisible
          ? _thumbnailPriorityQueueLimit
          : _thumbnailBackgroundQueueLimit,
    );
    queue.addLast(request);
    if (prioritizeVisible || _priorityThumbnailExtractionQueue.isNotEmpty) {
      _logPlayerDiagnostic(
        'Queued thumbnail extraction '
        'position=${_formatFfmpegTimestamp(position)} '
        'priority=${prioritizeVisible ? 'visible' : 'background'} '
        'visibleQueue=${_priorityThumbnailExtractionQueue.length} '
        'backgroundQueue=${_thumbnailExtractionQueue.length}',
      );
    }
    _scheduleThumbnailExtraction();
    return request.completer.future;
  }

  void _capThumbnailQueue(
    Queue<_ThumbnailExtractionTask> queue,
    int limit,
  ) {
    while (queue.length >= limit && queue.isNotEmpty) {
      final dropped = queue.removeFirst();
      if (!dropped.completer.isCompleted) {
        dropped.completer.complete(null);
      }
    }
  }

  void _scheduleThumbnailExtraction() {
    if (_thumbnailQueueScheduled || _disposed) {
      return;
    }
    _thumbnailQueueScheduled = true;
    scheduleMicrotask(() {
      _thumbnailQueueScheduled = false;
      if (_disposed) {
        _drainPendingThumbnailRequests();
        return;
      }
      while ((_priorityThumbnailExtractionQueue.isNotEmpty ||
              _thumbnailExtractionQueue.isNotEmpty) &&
          _availableThumbnailSlots.isNotEmpty) {
        final slot = _availableThumbnailSlots.removeFirst();
        final request = _priorityThumbnailExtractionQueue.isNotEmpty
            ? _priorityThumbnailExtractionQueue.removeFirst()
            : _thumbnailExtractionQueue.removeFirst();
        unawaited(_runThumbnailExtraction(slot, request));
      }
    });
  }

  Future<void> _runThumbnailExtraction(
    _ThumbnailExtractionSlot slot,
    _ThumbnailExtractionTask request,
  ) async {
    Uint8List? bytes;
    try {
      if (request.prioritizeVisible) {
        _logPlayerDiagnostic(
          'media_kit thumbnail extraction attempt '
          'uri=${request.uri} '
          'position=${_formatFfmpegTimestamp(request.position)} '
          'signature=${request.signature} '
          'priority=visible',
        );
      }
      await slot.ensureMediaLoaded(
        uri: request.uri,
        httpHeaders: request.httpHeaders,
        signature: request.signature,
      );
      if (!_disposed && slot.mediaSignature == request.signature) {
        bytes = await slot.captureFrame(
          request.position,
          settleDelay: _thumbnailSeekSettleDelay,
          requiresPlaybackWarmup: request.sourceKind == PlaybackSourceKind.hls,
        );
      }
      if (bytes != null && bytes.isNotEmpty) {
        if (request.prioritizeVisible) {
          _logPlayerDiagnostic(
            'media_kit thumbnail extraction succeeded '
            'bytes=${bytes.length} '
            'uri=${request.uri} '
            'position=${_formatFfmpegTimestamp(request.position)} '
            'priority=visible',
          );
        }
      } else {
        _logPlayerDiagnostic(
          'media_kit thumbnail extraction returned no bytes '
          'uri=${request.uri} '
          'position=${_formatFfmpegTimestamp(request.position)} '
          'priority=${request.prioritizeVisible ? 'visible' : 'background'}',
        );
      }
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'media_kit thumbnail extraction failed.',
        error: error,
        stackTrace: stackTrace,
      );
      bytes = null;
    } finally {
      if (!request.completer.isCompleted) {
        request.completer.complete(bytes);
      }
      if (_disposed) {
        return;
      }
      _availableThumbnailSlots.addLast(slot);
      _scheduleThumbnailExtraction();
    }
  }

  void _drainPendingThumbnailRequests() {
    while (_priorityThumbnailExtractionQueue.isNotEmpty) {
      final request = _priorityThumbnailExtractionQueue.removeFirst();
      if (!request.completer.isCompleted) {
        request.completer.complete(null);
      }
    }
    while (_thumbnailExtractionQueue.isNotEmpty) {
      final request = _thumbnailExtractionQueue.removeFirst();
      if (!request.completer.isCompleted) {
        request.completer.complete(null);
      }
    }
  }

  Future<bool> _ensureFfmpegAvailability() {
    return _ffmpegAvailabilityFuture ??= _probeFfmpegAvailability();
  }

  Future<bool> _probeFfmpegAvailability() async {
    if (_disposed) {
      return false;
    }
    if (!cheriflixShouldProbeFfmpegForPlatform(defaultTargetPlatform)) {
      _logPlayerDiagnostic(
        'Skipping ffmpeg process probe on this platform.',
      );
      return false;
    }
    _logPlayerDiagnostic(
      'Probing ffmpeg availability with `ffmpeg -version`.',
    );
    try {
      final result = await Process.run(
        'ffmpeg',
        <String>['-version'],
        runInShell: false,
      );
      final stdoutText = result.stdout.toString().trim();
      final stderrText = result.stderr.toString().trim();
      _logPlayerDiagnostic(
        'ffmpeg probe finished '
        'exitCode=${result.exitCode} '
        'stdout=${stdoutText.isEmpty ? '<empty>' : stdoutText} '
        'stderr=${stderrText.isEmpty ? '<empty>' : stderrText}',
      );
      return result.exitCode == 0;
    } on ProcessException catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'ffmpeg probe failed to start.',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'ffmpeg probe failed unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<Directory> _createScrubFrameTempDirectory() async {
    try {
      final baseDirectory = await getTemporaryDirectory();
      final tempDirectory = Directory(
        '${baseDirectory.path}${Platform.pathSeparator}'
        'cheriflix_scrub_${DateTime.now().microsecondsSinceEpoch}',
      );
      return tempDirectory.create(recursive: true);
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'path_provider temporary directory lookup failed; falling back to '
        'system temp.',
        error: error,
        stackTrace: stackTrace,
      );
      return Directory.systemTemp.createTemp('cheriflix_scrub_frame_');
    }
  }

  File _scrubFrameOutputFile(Directory directory, Duration position) {
    return File(
      '${directory.path}${Platform.pathSeparator}'
      'frame_${position.inMilliseconds}_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
  }

  String _ffmpegInputPath(Uri uri) {
    if (uri.scheme == 'file') {
      try {
        return uri.toFilePath(windows: Platform.isWindows);
      } catch (_) {}
    }
    return uri.toString();
  }

  String? _ffmpegHeaderString(Map<String, String> headers) {
    if (headers.isEmpty) {
      return null;
    }
    final buffer = StringBuffer();
    for (final entry in headers.entries) {
      final key = entry.key.trim();
      final value = entry.value.trim();
      if (key.isEmpty || value.isEmpty) {
        continue;
      }
      buffer.write('$key: $value\r\n');
    }
    final headerString = buffer.toString();
    if (headerString.isEmpty) {
      return null;
    }
    return '$headerString\r\n';
  }

  String _formatFfmpegTimestamp(Duration position) {
    final clamped = position.isNegative ? Duration.zero : position;
    final totalSeconds = clamped.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final fractional = clamped.inMilliseconds % 1000;
    final minutesText = minutes.toString().padLeft(2, '0');
    final secondsText = seconds.toString().padLeft(2, '0');
    final fractionalText = fractional.toString().padLeft(3, '0');
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutesText:$secondsText.'
          '$fractionalText';
    }
    return '$minutesText:$secondsText.$fractionalText';
  }

  Future<void> _deleteDirectoryQuietly(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<void> _ensureRendererProfile(
    PlaybackRendererProfile profile,
  ) async {
    if (_rendererProfile == profile) {
      return;
    }
    _logPlayerDiagnostic(
      'Switching native renderer profile '
      'from=${_rendererProfile.name} '
      'to=${profile.name} '
      'by rebuilding the playback runtime.',
    );
    await _rebuildPlaybackRuntime(profile);
    _emitPlayerState();
  }

  Future<void> _rebuildPlaybackRuntime(PlaybackRendererProfile profile) async {
    final previousPlayer = _player;
    final previousController = _videoController;
    final previousZoomScale = _playerState.value.zoomScale;
    _restartFrameMirrorCapture();
    _frameMirrorImage.value = null;
    await _detachPlaybackRuntimeListeners();
    _unbindAndroidWidTracking();
    _rendererProfile = profile;
    _player = _createPlayer();
    _videoController = _createVideoController(profile, player: _player);
    _bindAndroidWidTracking(_videoController);
    _resetFrameHealthProbe();
    if (_initialized) {
      _attachPlaybackRuntimeListeners();
      await _applyStreamingBufferConfiguration(
        aggressive: _aggressiveReadAheadEnabled,
      );
      await _applyPlaybackVolumeForNewPlayer();
      _playerState.value = _playerState.value.copyWith(
        currentPosition: Duration.zero,
        totalDuration: Duration.zero,
        isPaused: true,
        isBuffering: false,
        bridgeAvailable: true,
        videoWidth: 0,
        videoHeight: 0,
        hasRenderedFrame: false,
        renderHealthChecked: false,
        hasVerifiedVideoFrame: true,
        zoomScale: previousZoomScale,
      );
    }
    await previousPlayer.dispose();
    _logPlayerDiagnostic(
      'Rebuilt native playback runtime '
      'profile=${profile.name} '
      'controllerTexture=${_videoController.id.value} '
      'rect=${_videoController.rect.value}.',
    );
    if (identical(previousController, _videoController)) {
      _logPlayerDiagnostic(
        'Native playback runtime rebuild reused the previous controller unexpectedly.',
      );
    }
  }

  Future<void> _disposePlaybackRuntime() async {
    _stopFrameMirrorPump();
    await _detachPlaybackRuntimeListeners();
    _unbindAndroidWidTracking();
    await _player.dispose();
  }

  VideoController _createVideoController(
    PlaybackRendererProfile profile, {
    required Player player,
  }) {
    try {
      final isAndroid =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      final initialOutputSize = isAndroid ? null : _initialVideoOutputSize();
      _configuredVideoOutputSize = initialOutputSize;
      _logPlayerDiagnostic(
        'Creating native VideoController '
        'profile=${profile.name} '
        'output='
        '${initialOutputSize?.width.round() ?? 'native'}x'
        '${initialOutputSize?.height.round() ?? 'native'}...',
      );
      final controller = VideoController(
        player,
        configuration: VideoControllerConfiguration(
          vo: _videoOutputNameForProfile(profile),
          hwdec: _hardwareDecodeForProfile(profile),
          androidAttachSurfaceAfterVideoParameters:
              _attachSurfaceAfterParametersForProfile(profile),
          androidForceSurfaceTexture: _forceSurfaceTextureForProfile(profile),
          width: initialOutputSize?.width.round(),
          height: initialOutputSize?.height.round(),
        ),
      );
      _logPlayerDiagnostic('Native VideoController created successfully.');
      return controller;
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Native VideoController creation failed.',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  String? _videoOutputNameForProfile(PlaybackRendererProfile profile) {
    if (kIsWeb) return null;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return switch (profile) {
        PlaybackRendererProfile.androidSoftwareFallback => 'sw',
        _ => 'libmpv', // 'libmpv' helps resolve black screens on Windows
      };
    }
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    if (!isAndroid) {
      return null;
    }
    return switch (profile) {
      PlaybackRendererProfile.standard => 'mediacodec_embed',
      PlaybackRendererProfile.androidAttachEarlyFallback => 'mediacodec_embed',
      PlaybackRendererProfile.androidProducerStandardFallback => 'gpu',
      PlaybackRendererProfile.androidProducerAttachEarlyFallback => 'gpu',
      PlaybackRendererProfile.androidMediacodecEmbedFallback =>
        'mediacodec_embed',
      PlaybackRendererProfile.androidSoftwareFallback => 'gpu',
    };
  }

  String? _hardwareDecodeForProfile(PlaybackRendererProfile profile) {
    if (kIsWeb) return null;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return switch (profile) {
        PlaybackRendererProfile.androidSoftwareFallback => 'no',
        _ =>
          'auto', // Use auto instead of auto-safe to bypass hardware decoding block
      };
    }
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    if (!isAndroid) {
      return null;
    }
    return switch (profile) {
      PlaybackRendererProfile.standard => 'mediacodec',
      PlaybackRendererProfile.androidAttachEarlyFallback => 'mediacodec',
      PlaybackRendererProfile.androidProducerStandardFallback => 'auto-safe',
      PlaybackRendererProfile.androidProducerAttachEarlyFallback => 'auto-safe',
      PlaybackRendererProfile.androidMediacodecEmbedFallback => 'mediacodec',
      PlaybackRendererProfile.androidSoftwareFallback => 'no',
    };
  }

  bool? _attachSurfaceAfterParametersForProfile(
    PlaybackRendererProfile profile,
  ) {
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (!isAndroid) {
      return null;
    }
    return switch (profile) {
      PlaybackRendererProfile.standard => false,
      PlaybackRendererProfile.androidAttachEarlyFallback => false,
      PlaybackRendererProfile.androidProducerStandardFallback => true,
      PlaybackRendererProfile.androidProducerAttachEarlyFallback => false,
      PlaybackRendererProfile.androidMediacodecEmbedFallback => false,
      PlaybackRendererProfile.androidSoftwareFallback => false,
    };
  }

  bool? _forceSurfaceTextureForProfile(PlaybackRendererProfile profile) {
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (!isAndroid) {
      return null;
    }
    return switch (profile) {
      PlaybackRendererProfile.standard => false,
      PlaybackRendererProfile.androidAttachEarlyFallback => true,
      PlaybackRendererProfile.androidProducerStandardFallback => false,
      PlaybackRendererProfile.androidProducerAttachEarlyFallback => false,
      PlaybackRendererProfile.androidMediacodecEmbedFallback => false,
      PlaybackRendererProfile.androidSoftwareFallback => false,
    };
  }

  void _notifyThumbnailStripChanged() {
    if (_disposed) {
      return;
    }
    _thumbnailStripGeneration.value += 1;
  }

  bool _shouldMountThumbnailStrip(int mountedSlotCount) {
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return shouldMountThumbnailRendererStrip(
      isAndroid: isAndroid,
      activeMediaSourceKind: _activeMediaSourceKind,
      mountedSlotCount: mountedSlotCount,
    );
  }

  Future<void> _setSelectedCaptionTrackId(
    String? trackId, {
    bool preservePlayback = false,
  }) async {
    final wasPlaying = preservePlayback && _player.state.playing;
    _selectedCaptionTrackId = trackId;
    await _applySelectedCaptionTrack();
    if (wasPlaying && !_player.state.playing) {
      _logPlayerDiagnostic(
        'Subtitle track application paused playback; restoring play state.',
      );
      await _player.play();
    }
    _emitPlayerState();
  }

  Future<void> _applySelectedCaptionTrack() async {
    final trackId = _selectedCaptionTrackId;
    _subtitleLines.value = const <String>[];
    if (trackId == null) {
      await _player
          .setSubtitleTrack(SubtitleTrack.no())
          .timeout(_subtitleTrackApplyTimeout);
      return;
    }

    final selectedTrack = _captionTracks.cast<CaptionTrack?>().firstWhere(
          (track) => track?.id == trackId,
          orElse: () => null,
        );
    if (selectedTrack == null) {
      await _player
          .setSubtitleTrack(SubtitleTrack.no())
          .timeout(_subtitleTrackApplyTimeout);
      _selectedCaptionTrackId = null;
      return;
    }

    try {
      await _player
          .setSubtitleTrack(
            SubtitleTrack.uri(
              selectedTrack.url.toString(),
              title: _genericTrackLabelForId(_captionTracks, selectedTrack.id),
              language: selectedTrack.languageCode,
            ),
          )
          .timeout(_subtitleTrackApplyTimeout);
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Failed to apply subtitle source ${selectedTrack.id}.',
        error: error,
        stackTrace: stackTrace,
      );
      _selectedCaptionTrackId = null;
      _subtitleLines.value = const <String>[];
      try {
        await _player
            .setSubtitleTrack(SubtitleTrack.no())
            .timeout(_subtitleTrackApplyTimeout);
      } catch (_) {}
    }
  }

  void _updateSubtitleLines(List<String> value) {
    if (_disposed) {
      return;
    }
    _subtitleLines.value = List<String>.unmodifiable(
      value
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false),
    );
  }

  List<VideoTrack> _selectableVideoTracks() {
    return _player.state.tracks.video
        .whereType<VideoTrack>()
        .where(
          (track) => track.id != 'auto' && track.id != 'no',
        )
        .toList(growable: false);
  }

  List<String> _qualityOptionsForTracks(List<VideoTrack> tracks) {
    if (tracks.isEmpty) {
      return const <String>['Auto'];
    }
    return <String>[
      'Auto',
      for (var index = 0; index < tracks.length; index += 1)
        _labelForVideoTrack(tracks[index], index),
    ];
  }

  String _selectedQualityLabel(List<VideoTrack> tracks) {
    final currentTrack = _player.state.track.video;
    if (currentTrack.id == 'auto' || currentTrack.id == 'no') {
      return 'Auto';
    }

    final index =
        tracks.indexWhere((candidate) => candidate.id == currentTrack.id);
    if (index < 0) {
      return 'Auto';
    }
    return _labelForVideoTrack(tracks[index], index);
  }

  String _labelForVideoTrack(VideoTrack track, int index) {
    final height = track.h;
    if (height != null && height > 0) {
      return '${height}p';
    }
    final width = track.w;
    if (width != null && width > 0) {
      return '${width}w';
    }
    return 'Quality ${index + 1}';
  }

  void _handleRenderedFrameStateChanged() {
    if (!_initialized) {
      return;
    }
    _emitPlayerState();
  }

  bool _hasRenderedFrame() {
    final textureId = _videoController.id.value;
    final textureRect = _videoController.rect.value;
    final videoWidth = _player.state.width ?? 0;
    final videoHeight = _player.state.height ?? 0;
    if (_shouldUseAndroidFrameMirror()) {
      final frameBytes = _frameMirrorImage.value;
      if (frameBytes != null &&
          frameBytes.isNotEmpty &&
          videoWidth > 0 &&
          videoHeight > 0) {
        return true;
      }
      if (videoWidth > 0 &&
          videoHeight > 0 &&
          _player.state.position >= _frameMirrorWarmupVisibleThreshold) {
        // Avoid aggressive renderer retries while mirror mode is warming up.
        return true;
      }
    }
    final hasTextureMetadata = textureId != null &&
        textureRect != null &&
        textureRect.width > 1.0 &&
        textureRect.height > 1.0 &&
        videoWidth > 0 &&
        videoHeight > 0;
    if (!hasTextureMetadata) {
      return false;
    }
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (isAndroid && _latestAndroidWid <= 0) {
      if (!_loggedMissingAndroidWid) {
        _loggedMissingAndroidWid = true;
        _logPlayerDiagnostic(
          'Android texture metadata is ready but a usable wid '
          'has not been observed yet; '
          'treating frame as not rendered yet. '
          'textureId=$textureId rect=$textureRect '
          'video=${videoWidth}x$videoHeight',
        );
      }
      return false;
    }
    _loggedMissingAndroidWid = false;
    return true;
  }

  void _bindAndroidWidTracking(VideoController controller) {
    _unbindAndroidWidTracking();
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (!isAndroid) {
      return;
    }
    unawaited(() async {
      try {
        final platformController = await controller.platform.future;
        if (_disposed || !identical(controller, _videoController)) {
          return;
        }
        final dynamic dynamicPlatformController = platformController;
        final dynamic widCandidate = dynamicPlatformController.wid;
        if (widCandidate is! ValueListenable) {
          _latestAndroidWid = 0;
          return;
        }
        _androidWidListenable = widCandidate;
        _latestAndroidWid = _coerceAndroidWidValue(widCandidate.value);
        void handleWidChanged() {
          final nextWid = _coerceAndroidWidValue(widCandidate.value);
          if (nextWid == _latestAndroidWid) {
            return;
          }
          _latestAndroidWid = nextWid;
          if (nextWid > 0) {
            _loggedMissingAndroidWid = false;
          }
          _emitPlayerState();
        }

        _androidWidListener = handleWidChanged;
        widCandidate.addListener(handleWidChanged);
        _emitPlayerState();
      } catch (error, stackTrace) {
        _logPlayerDiagnostic(
          'Failed to bind Android wid listener.',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }());
  }

  void _unbindAndroidWidTracking() {
    final widListenable = _androidWidListenable;
    final widListener = _androidWidListener;
    if (widListenable != null && widListener != null) {
      widListenable.removeListener(widListener);
    }
    _androidWidListenable = null;
    _androidWidListener = null;
    _latestAndroidWid = 0;
    _loggedMissingAndroidWid = false;
  }

  void _resetFrameHealthProbe() {
    _renderHealthProbeGeneration += 1;
    _renderHealthChecked = false;
    _hasVerifiedVideoFrame = true;
    _renderHealthProbeInFlight = false;
    _renderHealthProbeAttemptCount = 0;
    _lastObservedAndroidFrameCallbackCount = -1;
  }

  void _maybeScheduleFrameHealthProbe({
    required bool hasRenderedFrame,
  }) {
    if (!hasRenderedFrame) {
      _renderHealthChecked = false;
      _hasVerifiedVideoFrame = true;
      _renderHealthProbeInFlight = false;
      _renderHealthProbeAttemptCount = 0;
      _lastObservedAndroidFrameCallbackCount = -1;
      return;
    }

    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (!isAndroid) {
      _renderHealthChecked = true;
      _hasVerifiedVideoFrame = true;
      return;
    }
    if (_shouldUseAndroidFrameMirror()) {
      // Mirror mode already verifies visibility via decoded screenshots.
      // Skip additional probe screenshots to avoid playback churn.
      _renderHealthChecked = true;
      _hasVerifiedVideoFrame = true;
      _renderHealthProbeInFlight = false;
      return;
    }
    if (_player.state.buffering) {
      return;
    }

    if (_renderHealthChecked || _renderHealthProbeInFlight) {
      return;
    }

    if (_player.state.position < _frameHealthProbePlaybackThreshold) {
      return;
    }

    _renderHealthProbeInFlight = true;
    final generation = _renderHealthProbeGeneration;
    _logPlayerDiagnostic(
      'Running frame-health probe '
      'profile=${_rendererProfile.name} '
      'position=${_player.state.position} '
      'uri=$_activeMediaUri',
    );
    unawaited(_runFrameHealthProbe(generation));
  }

  Future<void> _runFrameHealthProbe(int generation) async {
    final attempt = _renderHealthProbeAttemptCount + 1;
    _renderHealthProbeAttemptCount = attempt;
    var healthy = false;
    var primaryProbe = _FrameScreenshotProbeOutcome.missing;
    var followUpProbe = _FrameScreenshotProbeOutcome.missing;
    _AndroidVideoOutputState? outputState;
    try {
      outputState = await _readAndroidVideoOutputState();
      primaryProbe = await _captureFrameScreenshotProbeOutcome();
      if (primaryProbe != _FrameScreenshotProbeOutcome.visible) {
        await Future<void>.delayed(_frameHealthProbeFollowUpDelay);
        if (_disposed || generation != _renderHealthProbeGeneration) {
          return;
        }
        followUpProbe = await _captureFrameScreenshotProbeOutcome();
      }

      final hasVisibleScreenshot =
          primaryProbe == _FrameScreenshotProbeOutcome.visible ||
              followUpProbe == _FrameScreenshotProbeOutcome.visible;
      final screenshotMissing =
          primaryProbe == _FrameScreenshotProbeOutcome.missing &&
              followUpProbe == _FrameScreenshotProbeOutcome.missing;
      final hasFrameCallbacks = outputState?.hasFrameCallbacks ?? false;
      final useSurfaceTexture = outputState?.useSurfaceTexture ?? false;
      final hasAttachedSurface = outputState?.hasAttachedSurface ?? false;
      final frameCallbackCount = outputState?.frameAvailableCount ?? -1;
      final previousFrameCallbackCount = _lastObservedAndroidFrameCallbackCount;
      final hasFrameCallbacksProgressed = frameCallbackCount >= 0 &&
          frameCallbackCount > previousFrameCallbackCount;
      if (frameCallbackCount >= 0) {
        if (frameCallbackCount > _lastObservedAndroidFrameCallbackCount) {
          _lastObservedAndroidFrameCallbackCount = frameCallbackCount;
        }
      }
      final startupPhase =
          _player.state.position <= _frameHealthStartupTelemetryWindow;

      healthy = evaluateAndroidFrameHealth(
        hasVisibleScreenshot: hasVisibleScreenshot,
        screenshotMissing: screenshotMissing,
        hasFrameCallbacks: hasFrameCallbacks,
        hasFrameCallbacksProgressed: hasFrameCallbacksProgressed,
        useSurfaceTexture: useSurfaceTexture,
        hasAttachedSurface: hasAttachedSurface,
        startupPhase: startupPhase,
        surfaceAttachRetryCount: outputState?.surfaceAttachRetryCount ?? 0,
        frameWatchdogReattachCount:
            outputState?.frameWatchdogReattachCount ?? 0,
      );

      _logPlayerDiagnostic(
        'Frame-health probe sample '
        'attempt=$attempt '
        'primary=${_describeFrameProbeOutcome(primaryProbe)} '
        'followUp=${_describeFrameProbeOutcome(followUpProbe)} '
        'hasFrameCallbacks=$hasFrameCallbacks '
        'callbacksProgressed=$hasFrameCallbacksProgressed '
        'frameCallbackCount=$frameCallbackCount '
        'surfaceTexture=${outputState?.useSurfaceTexture ?? false} '
        'wid=${outputState?.wid ?? 0} '
        'watchdogReattach=${outputState?.frameWatchdogReattachCount ?? 0} '
        'attachRetries=${outputState?.surfaceAttachRetryCount ?? 0}',
      );
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Frame-health probe failed.',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (_disposed || generation != _renderHealthProbeGeneration) {
        return;
      }
      _renderHealthProbeInFlight = false;
      _renderHealthChecked = true;
      _hasVerifiedVideoFrame = healthy;
      _logPlayerDiagnostic(
        'Frame-health probe result '
        'healthy=$healthy '
        'attempt=$attempt '
        'profile=${_rendererProfile.name} '
        'position=${_player.state.position}',
      );
      _emitPlayerState();
    }
  }

  String _describeFrameProbeOutcome(_FrameScreenshotProbeOutcome outcome) {
    return switch (outcome) {
      _FrameScreenshotProbeOutcome.visible => 'visible',
      _FrameScreenshotProbeOutcome.blank => 'blank',
      _FrameScreenshotProbeOutcome.missing => 'missing',
    };
  }

  Future<_FrameScreenshotProbeOutcome>
      _captureFrameScreenshotProbeOutcome() async {
    final screenshot = await _player.screenshot(format: 'image/png');
    if (screenshot == null || screenshot.isEmpty) {
      return _FrameScreenshotProbeOutcome.missing;
    }
    final likelyBlank = await _isLikelyBlankScrubFrame(screenshot);
    return likelyBlank
        ? _FrameScreenshotProbeOutcome.blank
        : _FrameScreenshotProbeOutcome.visible;
  }

  Future<_AndroidVideoOutputState?> _readAndroidVideoOutputState() async {
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (!isAndroid) {
      return null;
    }
    try {
      final controller = _videoController;
      final platformController = await controller.platform.future;
      if (_disposed || !identical(controller, _videoController)) {
        return null;
      }
      final dynamic dynamicPlatformController = platformController;
      final dynamic response =
          await dynamicPlatformController.debugVideoOutputState();
      return _AndroidVideoOutputState.tryParse(response);
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Failed to read Android video output state for frame-health probing.',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Size _initialVideoOutputSize() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) {
      return _fallbackVideoOutputSize;
    }
    final view = views.first;
    return _normalizeVideoOutputSize(view.physicalSize);
  }

  void _syncVideoOutputSizeForLayout(
      Size logicalSize, double devicePixelRatio) {
    if (_usesManagedAndroidSurface()) {
      return;
    }
    if (!logicalSize.width.isFinite ||
        !logicalSize.height.isFinite ||
        logicalSize.width <= 0 ||
        logicalSize.height <= 0) {
      return;
    }
    final outputSize = _normalizeVideoOutputSize(
      Size(
        logicalSize.width * devicePixelRatio,
        logicalSize.height * devicePixelRatio,
      ),
    );
    if (_configuredVideoOutputSize == outputSize) {
      return;
    }
    _configuredVideoOutputSize = outputSize;
    _logPlayerDiagnostic(
      'Resizing native video output to '
      '${outputSize.width.round()}x${outputSize.height.round()}.',
    );
    _scheduleVideoOutputResize(outputSize);
  }

  void _scheduleVideoOutputResize(Size outputSize) {
    _pendingVideoOutputSize = outputSize;
    _pendingVideoOutputResizeTimer?.cancel();
    _pendingVideoOutputResizeTimer = Timer(
      _videoOutputResizeDebounce,
      _flushPendingVideoOutputResize,
    );
  }

  void _flushPendingVideoOutputResize() {
    final outputSize = _pendingVideoOutputSize;
    _pendingVideoOutputSize = null;
    if (_disposed || outputSize == null || _usesManagedAndroidSurface()) {
      return;
    }
    unawaited(
      _videoController.setSize(
        width: outputSize.width.round(),
        height: outputSize.height.round(),
      ),
    );
  }

  Size _normalizeVideoOutputSize(Size size) {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      return _fallbackVideoOutputSize;
    }
    final scale = math.min(
      1.0,
      math.min(_maxVideoOutputWidth / size.width,
          _maxVideoOutputHeight / size.height),
    );
    return Size(
      (size.width * scale).roundToDouble().clamp(1.0, _maxVideoOutputWidth),
      (size.height * scale).roundToDouble().clamp(1.0, _maxVideoOutputHeight),
    );
  }

  bool _usesManagedAndroidSurface() {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  }

  bool _shouldUseAndroidFrameMirror() {
    // Disabled entirely as it bypasses video texture mechanisms
    // and causes extreme UI lag by taking sequential JPEG screenshots.
    return false;
  }

  Widget _buildFrameMirrorLayer({
    required Uint8List? frameBytes,
    required double zoomScale,
    required double? aspectRatio,
  }) {
    if (frameBytes == null || frameBytes.isEmpty) {
      return const SizedBox.shrink();
    }
    final image = Image.memory(
      frameBytes,
      fit: zoomScale > 1 ? BoxFit.cover : BoxFit.contain,
      alignment: Alignment.center,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
    );
    final laidOutImage = aspectRatio == null
        ? SizedBox.expand(child: image)
        : Center(
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: image,
            ),
          );
    return IgnorePointer(
      child: ClipRect(
        child: Transform.scale(
          scale: zoomScale,
          alignment: Alignment.center,
          child: laidOutImage,
        ),
      ),
    );
  }

  void _restartFrameMirrorCapture() {
    _frameMirrorGeneration += 1;
    _frameMirrorCaptureInFlight = false;
    _frameMirrorTimer?.cancel();
    _frameMirrorTimer = null;
  }

  void _stopFrameMirrorPump() {
    _frameMirrorTimer?.cancel();
    _frameMirrorTimer = null;
  }

  void _syncFrameMirrorPump() {
    if (_disposed || !_shouldUseAndroidFrameMirror()) {
      _stopFrameMirrorPump();
      return;
    }
    if (_player.state.buffering) {
      _stopFrameMirrorPump();
      return;
    }
    if (!_player.state.playing) {
      _stopFrameMirrorPump();
      _captureFrameMirrorSample();
      return;
    }
    if (_frameMirrorTimer != null) {
      return;
    }
    _frameMirrorTimer = Timer.periodic(
      _frameMirrorCaptureInterval,
      (_) => _captureFrameMirrorSample(),
    );
  }

  void _captureFrameMirrorSample() {
    if (_disposed || !_shouldUseAndroidFrameMirror()) {
      return;
    }
    if (_player.state.buffering) {
      return;
    }
    if (_frameMirrorCaptureInFlight) {
      return;
    }
    _frameMirrorCaptureInFlight = true;
    final generation = _frameMirrorGeneration;
    unawaited(() async {
      try {
        final screenshot = await _player.screenshot(format: 'image/jpeg');
        if (_disposed || generation != _frameMirrorGeneration) {
          return;
        }
        if (screenshot != null && screenshot.isNotEmpty) {
          _frameMirrorImage.value = screenshot;
        }
      } catch (_) {
      } finally {
        if (!_disposed && generation == _frameMirrorGeneration) {
          _frameMirrorCaptureInFlight = false;
        }
      }
    }());
  }

  Duration _clampThumbnailPosition(Duration position) {
    return _clampPlaybackPosition(position);
  }

  Duration _clampPlaybackPosition(Duration position) {
    final totalDuration = _playerState.value.totalDuration;
    if (totalDuration <= Duration.zero) {
      return position.isNegative ? Duration.zero : position;
    }
    if (position <= Duration.zero) {
      return Duration.zero;
    }
    if (position >= totalDuration) {
      return totalDuration;
    }
    return position;
  }

  Future<void> _waitForPlayerPosition(
    Duration target, {
    required Duration timeout,
    required Duration tolerance,
  }) async {
    final current = _player.state.position;
    if ((current - target).abs() <= tolerance) {
      return;
    }

    try {
      await _player.stream.position
          .firstWhere((value) => (value - target).abs() <= tolerance)
          .timeout(timeout);
    } catch (_) {}
  }

  String _frameExtractionSignature(
    Uri uri,
    Map<String, String> httpHeaders,
  ) {
    final headers = httpHeaders.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    return <String>[
      uri.toString(),
      for (final entry in headers) '${entry.key}=${entry.value}',
    ].join('|');
  }

  void _emitPlayerState() {
    if (_disposed) {
      return;
    }
    final hasRenderedFrame = _hasRenderedFrame();
    _traceNativeStartupState(hasRenderedFrame: hasRenderedFrame);
    _maybeScheduleFrameHealthProbe(hasRenderedFrame: hasRenderedFrame);
    _syncFrameMirrorPump();
    final videoTracks = _selectableVideoTracks();
    final audioTracks = _availableAudioTracks();
    final presentation = PlaybackPresentation(
      currentPosition: _player.state.position,
      totalDuration: _player.state.duration,
      isPaused: !_player.state.playing,
      isCompleted: _player.state.completed,
      isBuffering: _player.state.buffering,
      bufferingPercentage: _player.state.bufferingPercentage,
      isMuted: _player.state.volume <= 0,
      playbackRate: _player.state.rate,
      audioDelay: _audioDelay,
      zoomScale: _playerState.value.zoomScale,
      audioTracks: audioTracks,
      selectedAudioTrackId: _player.state.track.audio.id,
      selectedAudioTrackLabel: _selectedAudioTrackLabel(audioTracks),
      captionsAvailable: _captionTracks.isNotEmpty,
      captionsEnabled: _selectedCaptionTrackId != null,
      captionTracks: _captionTracks,
      selectedCaptionTrackId: _selectedCaptionTrackId,
      selectedCaptionLabel: _selectedCaptionLabelForTracks(
        _captionTracks,
        _selectedCaptionTrackId,
      ),
      qualityOptions: _qualityOptionsForTracks(videoTracks),
      selectedQualityLabel: _selectedQualityLabel(videoTracks),
      bridgeAvailable: true,
      videoWidth: _player.state.width ?? 0,
      videoHeight: _player.state.height ?? 0,
      hasRenderedFrame: hasRenderedFrame,
      renderHealthChecked: _renderHealthChecked,
      hasVerifiedVideoFrame: _hasVerifiedVideoFrame,
    );
    _playerState.value = presentation;
    _events.add(PlaybackSurfacePlayerStateChanged(presentation));
  }

  void _traceNativeStartupState({required bool hasRenderedFrame}) {
    final watch = _startupTimeline;
    if (watch == null) {
      return;
    }
    final elapsedMs = watch.elapsedMilliseconds;
    if (!_loggedMetadataReady && _player.state.duration > Duration.zero) {
      _loggedMetadataReady = true;
      _logPlayerDiagnostic(
        'Native startup stage=metadata-ready elapsedMs=$elapsedMs '
        'durationMs=${_player.state.duration.inMilliseconds}.',
      );
    }
    final width = _player.state.width ?? 0;
    final height = _player.state.height ?? 0;
    if (!_loggedDecoderReady && hasRenderedFrame && width > 0 && height > 0) {
      _loggedDecoderReady = true;
      _logPlayerDiagnostic(
        'Native startup stage=decoder-ready elapsedMs=$elapsedMs '
        'width=$width height=$height.',
      );
    }
    if (!_loggedFirstTimelineProgress &&
        _player.state.position > Duration.zero) {
      _loggedFirstTimelineProgress = true;
      _logPlayerDiagnostic(
        'Native startup stage=timeline-progress elapsedMs=$elapsedMs '
        'positionMs=${_player.state.position.inMilliseconds}.',
      );
    }
    final buffering = _player.state.buffering;
    if (_lastLoggedBuffering != buffering) {
      _lastLoggedBuffering = buffering;
      _logPlayerDiagnostic(
        'Native startup stage=buffering-state elapsedMs=$elapsedMs '
        'buffering=$buffering positionMs=${_player.state.position.inMilliseconds}.',
      );
    }
  }

  String _selectedCaptionLabelForTracks(
    List<CaptionTrack> tracks,
    String? selectedCaptionTrackId,
  ) {
    return _genericTrackLabelForId(tracks, selectedCaptionTrackId);
  }
}

class _ThumbnailExtractionTask {
  _ThumbnailExtractionTask({
    required this.uri,
    required this.httpHeaders,
    required this.signature,
    required this.position,
    required this.prioritizeVisible,
    required this.sourceKind,
  });

  final Uri uri;
  final Map<String, String> httpHeaders;
  final String signature;
  final Duration position;
  final bool prioritizeVisible;
  final PlaybackSourceKind? sourceKind;
  final Completer<Uint8List?> completer = Completer<Uint8List?>();
}

class _HiddenThumbnailRendererStrip extends StatelessWidget {
  const _HiddenThumbnailRendererStrip({
    required this.slots,
  });

  final List<_ThumbnailExtractionSlot> slots;

  @override
  Widget build(BuildContext context) {
    if (slots.isEmpty) {
      return const SizedBox.shrink();
    }

    return Opacity(
      opacity: 0.001,
      child: SizedBox(
        width: slots.length * 64,
        height: 36,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final slot in slots)
              SizedBox(
                width: 64,
                height: 36,
                child: Video(
                  controller: slot.videoController,
                  controls: NoVideoControls,
                  fit: BoxFit.fill,
                  subtitleViewConfiguration: const SubtitleViewConfiguration(
                    visible: false,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThumbnailExtractionSlot {
  static const Duration _positionTolerance = Duration(milliseconds: 300);
  static const Duration _retrySeekOffset = Duration(milliseconds: 80);
  static const Duration _retryPlaybackKickDelay = Duration(milliseconds: 24);
  static const Duration _seekPlaybackWarmupDelay = Duration(milliseconds: 180);

  _ThumbnailExtractionSlot({
    this.onControllerAllocated,
  }) : player = Player(
          configuration: const PlayerConfiguration(
            libass: false,
          ),
        );

  final Player player;
  final VoidCallback? onControllerAllocated;
  VideoController? _videoController;
  String? mediaSignature;

  bool get hasVideoController => _videoController != null;

  VideoController get videoController => _videoController!;

  Future<VideoController> _ensureVideoController() async {
    final existing = _videoController;
    if (existing != null) {
      return existing;
    }
    final controller = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        width: 256,
        height: 144,
      ),
    );
    _videoController = controller;
    onControllerAllocated?.call();
    return controller;
  }

  Future<void> ensureMediaLoaded({
    required Uri uri,
    required Map<String, String> httpHeaders,
    required String signature,
  }) async {
    if (mediaSignature == signature) {
      return;
    }
    final controller = await _ensureVideoController();
    await _waitForVideoControllerReady(controller);
    await player.open(
      Media(
        uri.toString(),
        httpHeaders: httpHeaders,
      ),
      play: true,
    );
    await player.setVolume(0);
    _logPlayerDiagnostic(
      'Thumbnail slot opened media '
      'uri=$uri '
      'controllerTexture=${controller.id.value} '
      'rect=${controller.rect.value}',
    );
    try {
      await controller.waitUntilFirstFrameRendered.timeout(
        const Duration(seconds: 2),
      );
      _logPlayerDiagnostic(
        'Thumbnail slot rendered first frame '
        'uri=$uri '
        'controllerTexture=${controller.id.value} '
        'rect=${controller.rect.value}',
      );
    } catch (_) {
      _logPlayerDiagnostic(
        'Thumbnail slot timed out waiting for first rendered frame '
        'uri=$uri '
        'controllerTexture=${controller.id.value} '
        'rect=${controller.rect.value}',
      );
    }
    await _waitForVideoDecode();
    await Future<void>.delayed(_thumbnailMediaWarmupDelay);
    await player.pause();
    await Future<void>.delayed(_thumbnailMediaWarmupDelay);
    mediaSignature = signature;
  }

  Future<Uint8List?> captureFrame(
    Duration position, {
    required Duration settleDelay,
    required bool requiresPlaybackWarmup,
  }) async {
    final attempts = <Duration>[
      position,
      position + _retrySeekOffset,
    ];

    for (var index = 0; index < attempts.length; index += 1) {
      final target = attempts[index];
      await player.seek(target);
      await _waitForPlaybackPosition(target, timeout: settleDelay * 2);
      if (requiresPlaybackWarmup) {
        await player.play();
        await Future<void>.delayed(_seekPlaybackWarmupDelay);
        await player.pause();
      }
      await Future<void>.delayed(settleDelay);
      final screenshot = await player.screenshot(format: 'image/png');
      final bytesLength = screenshot?.length ?? 0;
      _logPlayerDiagnostic(
        'Thumbnail capture attempt '
        'target=${target.inMilliseconds}ms '
        'actual=${player.state.position.inMilliseconds}ms '
        'attempt=${index + 1}/${attempts.length} '
        'bytes=$bytesLength '
        'requiresPlaybackWarmup=$requiresPlaybackWarmup '
        'width=${player.state.width} '
        'height=${player.state.height}',
      );
      if (screenshot != null && screenshot.isNotEmpty) {
        if (await _isLikelyBlankScrubFrame(screenshot)) {
          _logPlayerDiagnostic(
            'Thumbnail capture attempt rejected likely blank frame '
            'target=${target.inMilliseconds}ms '
            'attempt=${index + 1}/${attempts.length}',
          );
        } else {
          return screenshot;
        }
      }

      if (index == 0) {
        await player.play();
        await Future<void>.delayed(_retryPlaybackKickDelay);
        await player.pause();
      }
    }

    _logPlayerDiagnostic(
      'Thumbnail capture exhausted retries '
      'position=${position.inMilliseconds}ms '
      'width=${player.state.width} '
      'height=${player.state.height} '
      'controllerTexture=${_videoController?.id.value} '
      'rect=${_videoController?.rect.value}',
    );
    return null;
  }

  void invalidate() {
    mediaSignature = null;
  }

  Future<void> _waitForVideoDecode() async {
    final width = player.state.width ?? 0;
    final height = player.state.height ?? 0;
    if (width > 0 && height > 0) {
      return;
    }

    try {
      await Future.any(<Future<void>>[
        Future.wait<void>(<Future<void>>[
          player.stream.width
              .firstWhere((value) => value != null && value > 0)
              .then((_) {}),
          player.stream.height
              .firstWhere((value) => value != null && value > 0)
              .then((_) {}),
        ]),
        Future<void>.delayed(_thumbnailMediaWarmupDelay * 2),
      ]);
    } catch (_) {}
  }

  Future<void> _waitForVideoControllerReady(VideoController controller) async {
    try {
      await controller.platform.future.timeout(const Duration(seconds: 2));
      if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android) {
        await controller.setSize(
          width: _scrubThumbnailTargetWidth,
          height: _scrubThumbnailTargetHeight,
        );
      }
    } catch (error, stackTrace) {
      _logPlayerDiagnostic(
        'Thumbnail slot video controller did not become ready in time.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _waitForPlaybackPosition(
    Duration target, {
    required Duration timeout,
  }) async {
    final current = player.state.position;
    if ((current - target).abs() <= _positionTolerance) {
      return;
    }

    try {
      await player.stream.position
          .firstWhere(
            (value) => (value - target).abs() <= _positionTolerance,
          )
          .timeout(timeout);
    } catch (_) {}
  }

  Future<void> dispose() async {
    await player.dispose();
  }
}

// ignore: unused_element
class _InAppPlaybackSurfaceController implements PlaybackSurfaceController {
  final StreamController<PlaybackSurfaceEvent> _events =
      StreamController<PlaybackSurfaceEvent>.broadcast();
  final ValueNotifier<PlaybackPresentation> _playerState =
      ValueNotifier<PlaybackPresentation>(const PlaybackPresentation());
  final ValueNotifier<List<String>> _subtitleLines =
      ValueNotifier<List<String>>(const <String>[]);

  final Completer<InAppWebViewController> _controllerCompleter =
      Completer<InAppWebViewController>();
  InAppWebViewController? _controller;
  PlaybackLoadRequest? _pendingRequest;
  Uri? _activeRequestUri;
  Set<String> _allowedHostSuffixes = const <String>{};
  bool _initialized = false;
  String? _lastBlockedHost;
  int _loadSequence = 0;
  String _activeLoadToken = '0';
  String? _activeFrameId;
  bool _didRejectActiveLoad = false;
  bool _hasReadyPlayback = false;
  bool _autoplayRequested = false;
  String? _reportedDirectSourceSignature;
  bool _disposed = false;

  @override
  Stream<PlaybackSurfaceEvent> get events => _events.stream;

  @override
  ValueListenable<PlaybackPresentation> get playerState => _playerState;

  @override
  ValueListenable<List<String>> get subtitleLines => _subtitleLines;

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
  }

  @override
  Future<void> load(PlaybackLoadRequest request) async {
    if (_disposed) {
      return;
    }
    _allowedHostSuffixes = request.allowedHostSuffixes
        .map((host) => host.trim().toLowerCase())
        .where((host) => host.isNotEmpty)
        .toSet();
    _lastBlockedHost = null;
    _activeLoadToken = (++_loadSequence).toString();
    _activeFrameId = null;
    _activeRequestUri = request.uri;
    _didRejectActiveLoad = false;
    _hasReadyPlayback = false;
    _autoplayRequested = false;
    _reportedDirectSourceSignature = null;
    _playerState.value = PlaybackPresentation(
      captionTracks: request.captionTracks,
      selectedCaptionTrackId: request.selectedCaptionTrackId,
      selectedCaptionLabel: _selectedCaptionLabelForTracks(
        request.captionTracks,
        request.selectedCaptionTrackId,
      ),
      captionsAvailable: request.captionTracks.isNotEmpty,
      captionsEnabled: request.selectedCaptionTrackId != null,
    );
    _pendingRequest = request;

    if (_controller == null) {
      return;
    }

    await _performLoad(request);
  }

  @override
  Widget buildView() {
    return InAppWebView(
      initialSettings: InAppWebViewSettings(
        transparentBackground: true,
        cacheEnabled: false,
        disableContextMenu: true,
        allowsInlineMediaPlayback: true,
        iframeAllow:
            'autoplay; fullscreen; encrypted-media; picture-in-picture',
        iframeAllowFullscreen: true,
        supportZoom: false,
        mediaPlaybackRequiresUserGesture: false,
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: false,
        userAgent: _desktopUserAgent,
        useShouldOverrideUrlLoading: true,
        useOnLoadResource: true,
        useShouldInterceptAjaxRequest: true,
        useShouldInterceptFetchRequest: true,
        useShouldInterceptRequest: true,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        if (!_controllerCompleter.isCompleted) {
          _controllerCompleter.complete(controller);
        }
        controller.addJavaScriptHandler(
          handlerName: 'cheriflixPlayerMessage',
          callback: (arguments) {
            if (arguments.isEmpty || arguments.first is! Map) {
              return null;
            }
            _handleWebMessage(
              Map<dynamic, dynamic>.from(arguments.first as Map),
            );
            return null;
          },
        );
        final pendingRequest = _pendingRequest;
        if (pendingRequest != null) {
          unawaited(_performLoad(pendingRequest));
        }
      },
      onLoadStart: (controller, url) {
        final resolvedUri = _tryParseUri(url);
        if (resolvedUri != null && resolvedUri.host.trim().isNotEmpty) {
          _activeRequestUri = resolvedUri;
        }
      },
      onLoadStop: (controller, url) {
        final resolvedUri = _tryParseUri(url);
        if (resolvedUri != null && resolvedUri.host.trim().isNotEmpty) {
          _activeRequestUri = resolvedUri;
        }
        _hasReadyPlayback = true;
        unawaited(_runAdScrubberPass());
        if (_autoplayRequested) {
          _scheduleEmbedAutoplayPasses(_activeLoadToken);
        }
      },
      onLoadResource: (controller, resource) {
        _emitInterceptedDirectSourceCandidate(
          uri: _tryParseUri(resource.url),
          pageUri: _activeRequestUri,
          allowFileSource: false,
        );
      },
      onUpdateVisitedHistory: (controller, url, isReload) {
        _handleUrlChanged(_tryParseUri(url));
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final uri = _tryParseUri(navigationAction.request.url);
        if (uri == null || uri.host.trim().isEmpty) {
          return NavigationActionPolicy.ALLOW;
        }
        final requestHeaders = _normalizeStringHeaders(
          navigationAction.request.headers,
        );
        final sourceKind = _inferDirectSourceKind(
          uri,
          headers: requestHeaders,
        );
        if (sourceKind != null && sourceKind != PlaybackSourceKind.embed) {
          _emitInterceptedDirectSourceCandidate(
            uri: uri,
            pageUri: _activeRequestUri,
            requestHeaders: requestHeaders,
            explicitSourceKind: sourceKind,
          );
          return NavigationActionPolicy.CANCEL;
        }
        final host = uri.host.trim().toLowerCase();
        if (_isAllowedHost(host)) {
          _activeRequestUri = uri;
          _lastBlockedHost = null;
          return NavigationActionPolicy.ALLOW;
        }
        _notifyBlockedNavigation(uri);
        return NavigationActionPolicy.CANCEL;
      },
      onCreateWindow: (controller, createWindowAction) async {
        final uri = _tryParseUri(createWindowAction.request.url);
        if (uri != null) {
          _notifyBlockedNavigation(uri);
        }
        return false;
      },
      shouldInterceptRequest: (controller, request) async {
        _emitInterceptedDirectSourceCandidate(
          uri: _tryParseUri(request.url),
          pageUri: _activeRequestUri,
          requestHeaders: _normalizeStringHeaders(request.headers),
          allowFileSource: false,
        );
        return null;
      },
      shouldInterceptFetchRequest: (controller, fetchRequest) async {
        _emitInterceptedDirectSourceCandidate(
          uri: _tryParseUri(fetchRequest.url),
          pageUri: _activeRequestUri,
          requestHeaders: _normalizeStringHeaders(fetchRequest.headers),
        );
        return fetchRequest;
      },
      shouldInterceptAjaxRequest: (controller, ajaxRequest) async {
        _emitInterceptedDirectSourceCandidate(
          uri: _tryParseUri(ajaxRequest.responseURL ?? ajaxRequest.url),
          pageUri: _activeRequestUri,
          requestHeaders: _normalizeStringHeaders(
            ajaxRequest.headers?.getHeaders(),
          ),
          responseHeaders: _normalizeStringHeaders(ajaxRequest.responseHeaders),
        );
        return ajaxRequest;
      },
      onAjaxReadyStateChange: (controller, ajaxRequest) async {
        _emitInterceptedDirectSourceCandidate(
          uri: _tryParseUri(ajaxRequest.responseURL ?? ajaxRequest.url),
          pageUri: _activeRequestUri,
          requestHeaders: _normalizeStringHeaders(
            ajaxRequest.headers?.getHeaders(),
          ),
          responseHeaders: _normalizeStringHeaders(ajaxRequest.responseHeaders),
        );
        return AjaxRequestAction.PROCEED;
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame != true) {
          return;
        }

        final requestUri = _tryParseUri(request.url);
        if (requestUri == null || !_isFatalWebResourceError(error)) {
          return;
        }

        final description = error.description.trim().toLowerCase();
        if (error.type == WebResourceErrorType.CANCELLED ||
            description.contains('err_aborted') ||
            description.contains('net::err_aborted') ||
            description.contains('blocked by client')) {
          return;
        }
        final activeHost = _activeRequestUri?.host.trim().toLowerCase() ?? '';
        final requestHost = requestUri.host.trim().toLowerCase();
        if (activeHost.isNotEmpty &&
            requestHost.isNotEmpty &&
            requestHost != activeHost &&
            !requestHost.endsWith('.$activeHost')) {
          return;
        }
        _rejectActiveLoad('This source failed to load in the in-app player.');
      },
      onPermissionRequest: (controller, permissionRequest) async {
        return PermissionResponse(
          action: PermissionResponseAction.DENY,
          resources: permissionRequest.resources,
        );
      },
    );
  }

  @override
  Future<void> requestPlayerState() {
    return _runPlayerBridgeCommand('requestState');
  }

  @override
  Future<void> play() {
    _autoplayRequested = true;
    _playerState.value = _playerState.value.copyWith(isPaused: false);
    _scheduleEmbedAutoplayPasses(_activeLoadToken);
    return _runPlayerBridgeCommand('play');
  }

  @override
  Future<void> pause() {
    _autoplayRequested = false;
    _playerState.value = _playerState.value.copyWith(isPaused: true);
    return _runPlayerBridgeCommand('pause');
  }

  @override
  Future<void> togglePlayPause() {
    final shouldPause = !_playerState.value.isPaused;
    _autoplayRequested = !shouldPause;
    _playerState.value = _playerState.value.copyWith(isPaused: shouldPause);
    return _runPlayerBridgeCommand('togglePlayPause');
  }

  @override
  Future<void> attemptAutoplay() {
    _autoplayRequested = true;
    _scheduleEmbedAutoplayPasses(_activeLoadToken);
    return _runPlayerBridgeCommand('attemptAutoplay');
  }

  void _scheduleEmbedAutoplayPasses(String loadToken) {
    for (final delay in const <Duration>[
      Duration(milliseconds: 250),
      Duration(milliseconds: 750),
      Duration(milliseconds: 1500),
      Duration(milliseconds: 2500),
    ]) {
      unawaited(Future<void>.delayed(delay, () async {
        if (_disposed || !_autoplayRequested || loadToken != _activeLoadToken) {
          return;
        }
        await _runPlayerBridgeCommand('attemptAutoplay');
      }));
    }
  }

  @override
  Future<void> seekBy(Duration offset) {
    return _runPlayerBridgeCommand('seekBy', argument: offset.inSeconds);
  }

  @override
  Future<void> seekTo(Duration position) {
    return _runPlayerBridgeCommand('seekTo', argument: position.inSeconds);
  }

  @override
  Future<void> toggleMute() {
    return _runPlayerBridgeCommand('toggleMute');
  }

  @override
  Future<void> cyclePlaybackRate() {
    return _runPlayerBridgeCommand('cyclePlaybackRate');
  }

  @override
  Future<void> stepPlaybackRate(int direction) {
    return _runPlayerBridgeCommand('stepPlaybackRate', argument: direction);
  }

  @override
  Future<void> toggleCaptions() {
    return _runPlayerBridgeCommand('toggleCaptions');
  }

  @override
  Future<void> selectAudioTrack(String trackId) {
    return _runPlayerBridgeCommand('selectAudioTrack', argument: trackId);
  }

  @override
  Future<void> selectCaptionTrack(String? trackId) {
    return _runPlayerBridgeCommand('selectCaptionTrack', argument: trackId);
  }

  @override
  Future<void> setCaptionTracks(
    List<CaptionTrack> tracks, {
    String? selectedTrackId,
  }) async {
    _playerState.value = _playerState.value.copyWith(
      captionTracks: tracks,
      selectedCaptionTrackId: selectedTrackId,
      selectedCaptionLabel: _selectedCaptionLabelForTracks(
        tracks,
        selectedTrackId,
      ),
      captionsAvailable: tracks.isNotEmpty,
      captionsEnabled: selectedTrackId != null,
    );
    await _runPlayerBridgeCommand(
      'setCaptionTracks',
      argument: <String, dynamic>{
        'tracks': tracks.map((track) => track.toJson()).toList(growable: false),
        'selectedTrackId': selectedTrackId,
      },
    );
  }

  @override
  Future<void> setAudioDelay(Duration offset) async {}

  @override
  Future<void> setSubtitleDelay(Duration offset) async {}

  @override
  Future<void> cycleQuality() {
    return _runPlayerBridgeCommand('cycleQuality');
  }

  @override
  Future<void> adjustZoom(double delta) {
    return _runPlayerBridgeCommand('adjustZoom', argument: delta);
  }

  @override
  Future<void> quietStop() async {
    if (_disposed) {
      return;
    }
    _pendingRequest = null;
    _activeRequestUri = null;
    _activeFrameId = null;
    _didRejectActiveLoad = false;
    _hasReadyPlayback = false;
    _autoplayRequested = false;
    _reportedDirectSourceSignature = null;
    _playerState.value = const PlaybackPresentation();
    _subtitleLines.value = const <String>[];
    final controller = _controller;
    if (controller == null) {
      return;
    }
    try {
      await controller.evaluateJavascript(source: '''
(() => {
  try {
    document.querySelectorAll('video').forEach((video) => {
      try {
        video.pause();
        video.removeAttribute('src');
        video.load();
      } catch (_) {}
    });
  } catch (_) {}
})();
''');
    } catch (_) {}
    try {
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri('about:blank')),
      );
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    await quietStop();
    _disposed = true;
    _controller = null;
    _events.close();
    _subtitleLines.dispose();
    _playerState.dispose();
  }

  Future<void> _performLoad(PlaybackLoadRequest request) async {
    if (_disposed) {
      return;
    }
    final controller = await _waitForController();
    if (_disposed) {
      return;
    }
    await controller.removeUserScriptsByGroupName(groupName: 'cheriflix');
    await controller.addUserScript(
      userScript: UserScript(
        groupName: 'cheriflix',
        source: _buildSiteHardeningBootstrapScript(
          request.allowedHostSuffixes,
          _activeLoadToken,
          request.captionTracks,
          request.selectedCaptionTrackId,
        ),
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ),
    );
    await controller.loadUrl(
      urlRequest: URLRequest(
        url: WebUri.uri(request.uri),
      ),
    );
  }

  Future<InAppWebViewController> _waitForController() async {
    final existing = _controller;
    if (existing != null) {
      return existing;
    }
    return _controllerCompleter.future;
  }

  Uri? _tryParseUri(WebUri? uri) {
    if (uri == null) {
      return null;
    }
    return Uri.tryParse(uri.toString());
  }

  void _handleUrlChanged(Uri? uri) {
    if (uri == null || uri.host.trim().isEmpty) {
      return;
    }

    final sourceKind = _inferDirectSourceKind(uri);
    if (sourceKind != null && sourceKind != PlaybackSourceKind.embed) {
      _emitInterceptedDirectSourceCandidate(
        uri: uri,
        pageUri: _activeRequestUri,
        explicitSourceKind: sourceKind,
      );
      return;
    }

    final host = uri.host.trim().toLowerCase();
    if (_isAllowedHost(host)) {
      _activeRequestUri = uri;
      _lastBlockedHost = null;
      return;
    }

    if (_lastBlockedHost == host) {
      return;
    }

    _notifyBlockedNavigation(uri);
  }

  bool _isAllowedHost(String host) {
    if (_allowedHostSuffixes.isEmpty) {
      return true;
    }

    for (final allowedHost in _allowedHostSuffixes) {
      if (host == allowedHost || host.endsWith('.$allowedHost')) {
        return true;
      }
    }

    return false;
  }

  bool _isFatalWebResourceError(WebResourceError error) {
    return error.type == WebResourceErrorType.BAD_URL ||
        error.type == WebResourceErrorType.CANNOT_CONNECT_TO_HOST ||
        error.type == WebResourceErrorType.FILE_NOT_FOUND ||
        error.type == WebResourceErrorType.HOST_LOOKUP ||
        error.type == WebResourceErrorType.FAILED_SSL_HANDSHAKE ||
        error.type == WebResourceErrorType.TOO_MANY_REDIRECTS ||
        error.type == WebResourceErrorType.TIMEOUT ||
        error.type == WebResourceErrorType.UNSAFE_RESOURCE;
  }

  Future<void> _runAdScrubberPass() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    try {
      await controller.evaluateJavascript(source: _siteHardeningFollowUpScript);
    } catch (_) {
      // Keep playback alive even when a provider page rejects script execution.
    }
  }

  void _notifyBlockedNavigation(Uri uri) {
    if (_lastBlockedHost == uri.host.trim().toLowerCase()) {
      return;
    }
    _lastBlockedHost = uri.host.trim().toLowerCase();
    _events.add(
      PlaybackSurfaceBlockedNavigation(
        uri,
        keepCurrentPlayback: _hasReadyPlayback,
      ),
    );
    // Keep the current surface mounted and let the player retry silently.
  }

  void _handleWebMessage(dynamic message) {
    if (_disposed) {
      return;
    }
    if (message is! Map) {
      return;
    }

    final token = '${message['token'] ?? ''}'.trim();
    final channel = '${message['channel'] ?? ''}'.trim();
    final type = '${message['type'] ?? ''}'.trim();

    if (channel == 'cheriflix-player') {
      if (token.isNotEmpty && token != _activeLoadToken) {
        return;
      }
      if (type == 'state') {
        final frameId = '${message['frameId'] ?? ''}'.trim();
        if (frameId.isNotEmpty && message['bridgeAvailable'] == true) {
          _activeFrameId = frameId;
        }
        _updateSubtitleLinesFromMessage(message);
        final presentation = _presentationFromMessage(message);
        _playerState.value = presentation;
        _emitDirectSourceCandidateFromMessage(message, frameId: frameId);
        _events.add(PlaybackSurfacePlayerStateChanged(presentation));
      }
      return;
    }

    if (token.isEmpty || token != _activeLoadToken) {
      return;
    }

    if (channel != 'cheriflix-frame') {
      return;
    }

    final fatal = message['fatal'] == true;
    if (!fatal) {
      return;
    }

    if (message['isTopFrame'] == false) {
      return;
    }

    final reason = '${message['reason'] ?? ''}'.trim();
    if (reason.isEmpty) {
      return;
    }

    _rejectActiveLoad(reason);
  }

  void _rejectActiveLoad(String reason) {
    if (_didRejectActiveLoad) {
      return;
    }

    _didRejectActiveLoad = true;
    _events.add(PlaybackSurfaceSourceRejected(reason));
  }

  void _emitDirectSourceCandidateFromMessage(
    Map<dynamic, dynamic> message, {
    required String frameId,
  }) {
    final rawSourceUrl = '${message['detectedSourceUrl'] ?? ''}'.trim();
    if (rawSourceUrl.isEmpty) {
      return;
    }

    final uri = Uri.tryParse(rawSourceUrl);
    if (uri == null || !uri.hasScheme) {
      return;
    }

    final sourceKind =
        PlaybackSourceKind.tryParse(message['detectedSourceKind']) ??
            _inferDirectSourceKind(uri);
    if (sourceKind == null || sourceKind == PlaybackSourceKind.embed) {
      return;
    }

    final httpHeaders = _readMessageHeaders(message['detectedSourceHeaders']);
    final confidence = switch (message['detectedSourceConfidence']) {
      final num value => value.toDouble(),
      _ => null,
    };
    if (!_isEligibleDirectSourceCandidate(
      uri,
      sourceKind: sourceKind,
      headers: httpHeaders,
      confidence: confidence,
    )) {
      return;
    }
    final pageUrlValue = '${message['detectedSourcePageUrl'] ?? ''}'.trim();
    final pageUri = pageUrlValue.isEmpty ? null : Uri.tryParse(pageUrlValue);
    final signature = _directSourceMessageSignature(
      uri: uri,
      sourceKind: sourceKind,
      httpHeaders: httpHeaders,
      pageUri: pageUri,
    );
    if (signature == _reportedDirectSourceSignature) {
      return;
    }

    if (_activeFrameId == null && frameId.isNotEmpty) {
      _activeFrameId = frameId;
    }

    _emitInterceptedDirectSourceCandidate(
      uri: uri,
      pageUri: pageUri,
      requestHeaders: httpHeaders,
      explicitSourceKind: sourceKind,
    );
  }

  Map<String, String> _readMessageHeaders(Object? value) {
    return _normalizeStringHeaders(value);
  }

  void _emitInterceptedDirectSourceCandidate({
    required Uri? uri,
    Uri? pageUri,
    Map<String, String> requestHeaders = const <String, String>{},
    Map<String, String> responseHeaders = const <String, String>{},
    PlaybackSourceKind? explicitSourceKind,
    bool allowFileSource = true,
  }) {
    if (uri == null || !uri.hasScheme) {
      return;
    }

    final inferenceHeaders = <String, String>{
      ...requestHeaders,
      ...responseHeaders,
    };
    final sourceKind = explicitSourceKind ??
        _inferDirectSourceKind(
          uri,
          headers: inferenceHeaders,
        );
    if (sourceKind == null || sourceKind == PlaybackSourceKind.embed) {
      return;
    }
    if (!allowFileSource && sourceKind == PlaybackSourceKind.file) {
      return;
    }
    if (!_isEligibleDirectSourceCandidate(
      uri,
      sourceKind: sourceKind,
      headers: inferenceHeaders,
    )) {
      return;
    }

    final effectivePageUri = pageUri ?? _activeRequestUri;
    final httpHeaders = _buildDirectPlaybackHeaders(
      requestHeaders,
      pageUri: effectivePageUri,
    );
    final signature = _directSourceMessageSignature(
      uri: uri,
      sourceKind: sourceKind,
      httpHeaders: httpHeaders,
      pageUri: effectivePageUri,
    );
    if (signature == _reportedDirectSourceSignature) {
      return;
    }

    _reportedDirectSourceSignature = signature;
    _events.add(
      PlaybackSurfaceDirectSourceDetected(
        uri: uri,
        sourceKind: sourceKind,
        httpHeaders: httpHeaders,
        pageUri: effectivePageUri,
      ),
    );
  }

  Map<String, String> _normalizeStringHeaders(Object? value) {
    if (value is! Map) {
      return const <String, String>{};
    }

    return <String, String>{
      for (final entry in value.entries)
        if (entry.key.toString().trim().isNotEmpty &&
            '${entry.value ?? ''}'.trim().isNotEmpty)
          entry.key.toString().trim(): '${entry.value ?? ''}'.trim(),
    };
  }

  PlaybackSourceKind? _inferDirectSourceKind(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
  }) {
    final normalizedUrl = uri.toString().toLowerCase();
    final normalizedPath = uri.path.toLowerCase();
    if (normalizedUrl.contains('.m3u8')) {
      return PlaybackSourceKind.hls;
    }

    final contentType =
        (_headerValue(headers, 'content-type') ?? '').toLowerCase();
    if (normalizedPath.endsWith('.mp3') ||
        normalizedPath.endsWith('.aac') ||
        normalizedPath.endsWith('.ogg') ||
        normalizedPath.endsWith('.opus') ||
        normalizedPath.endsWith('.flac') ||
        normalizedPath.endsWith('.wav') ||
        normalizedPath.endsWith('.m4a') ||
        contentType.startsWith('audio/')) {
      return null;
    }
    final accept = (_headerValue(headers, 'accept') ?? '').toLowerCase();
    final headerHints = '$contentType $accept';
    if (headerHints.contains('application/vnd.apple.mpegurl') ||
        headerHints.contains('application/x-mpegurl') ||
        headerHints.contains('mpegurl')) {
      return PlaybackSourceKind.hls;
    }

    if (normalizedUrl.contains('.mp4') ||
        normalizedUrl.contains('.mkv') ||
        normalizedUrl.contains('.m4v') ||
        normalizedUrl.contains('.webm') ||
        normalizedUrl.contains('.mov')) {
      return PlaybackSourceKind.file;
    }

    if (contentType.startsWith('video/') ||
        contentType.contains('matroska') ||
        contentType.contains('application/mp4') ||
        accept.contains('video/') ||
        accept.contains('matroska') ||
        accept.contains('application/mp4')) {
      return PlaybackSourceKind.file;
    }

    return null;
  }

  bool _isEligibleDirectSourceCandidate(
    Uri uri, {
    required PlaybackSourceKind sourceKind,
    Map<String, String> headers = const <String, String>{},
    double? confidence,
  }) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return false;
    }

    final normalizedUrl = uri.toString().toLowerCase();
    final normalizedPath = uri.path.toLowerCase();
    if (normalizedUrl.contains('.vtt') ||
        normalizedUrl.contains('.srt') ||
        normalizedUrl.contains('.ass') ||
        normalizedUrl.contains('.ssa') ||
        normalizedUrl.contains('subtitle') ||
        normalizedUrl.contains('captions')) {
      return false;
    }
    if (normalizedPath.endsWith('.ts') ||
        normalizedPath.endsWith('.m4s') ||
        normalizedPath.endsWith('.mp3') ||
        normalizedPath.endsWith('.aac') ||
        normalizedPath.endsWith('.ogg') ||
        normalizedPath.endsWith('.opus') ||
        normalizedPath.endsWith('.flac') ||
        normalizedPath.endsWith('.wav') ||
        normalizedPath.endsWith('.m4a') ||
        normalizedPath.endsWith('.jpg') ||
        normalizedPath.endsWith('.jpeg') ||
        normalizedPath.endsWith('.png') ||
        normalizedPath.endsWith('.gif') ||
        normalizedPath.endsWith('.svg') ||
        normalizedPath.endsWith('.css') ||
        normalizedPath.endsWith('.js') ||
        normalizedPath.endsWith('.ico') ||
        normalizedPath.endsWith('.html') ||
        normalizedPath.endsWith('.htm')) {
      return false;
    }

    final contentType =
        (_headerValue(headers, 'content-type') ?? '').toLowerCase();
    if (contentType.startsWith('audio/')) {
      return false;
    }
    if (sourceKind == PlaybackSourceKind.hls) {
      return normalizedUrl.contains('.m3u8') ||
          contentType.contains('mpegurl') ||
          contentType.contains('application/vnd.apple.mpegurl') ||
          contentType.contains('application/x-mpegurl');
    }

    if (sourceKind == PlaybackSourceKind.file) {
      final hasVideoMime = contentType.startsWith('video/') ||
          contentType.contains('matroska') ||
          contentType.contains('application/mp4');
      final hasVideoExtension = normalizedUrl.contains('.mp4') ||
          normalizedUrl.contains('.mkv') ||
          normalizedUrl.contains('.m4v') ||
          normalizedUrl.contains('.webm') ||
          normalizedUrl.contains('.mov');
      if (confidence != null && confidence < 2 && !hasVideoMime) {
        return false;
      }
      return hasVideoExtension || hasVideoMime;
    }

    return false;
  }

  Map<String, String> _buildDirectPlaybackHeaders(
    Map<String, String> requestHeaders, {
    Uri? pageUri,
  }) {
    const blockedHeaderNames = <String>{
      'accept-encoding',
      'connection',
      'content-length',
      'host',
      'range',
      'upgrade',
    };

    final headers = <String, String>{};
    for (final entry in requestHeaders.entries) {
      final name = entry.key.trim();
      final value = entry.value.trim();
      if (name.isEmpty || value.isEmpty) {
        continue;
      }

      final normalizedName = name.toLowerCase();
      if (blockedHeaderNames.contains(normalizedName) ||
          normalizedName.startsWith('sec-')) {
        continue;
      }

      headers[_canonicalDirectPlaybackHeaderName(name)] = value;
    }

    final effectivePageUri = pageUri;
    if (effectivePageUri != null &&
        effectivePageUri.hasScheme &&
        effectivePageUri.host.trim().isNotEmpty) {
      _setHeaderIfMissing(
        headers,
        'Referer',
        effectivePageUri.toString(),
      );
      final origin = _originForUri(effectivePageUri);
      if (origin != null) {
        _setHeaderIfMissing(headers, 'Origin', origin);
      }
    }

    _setHeaderIfMissing(headers, 'User-Agent', _desktopUserAgent);
    return headers;
  }

  String? _headerValue(Map<String, String> headers, String name) {
    final normalizedName = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == normalizedName) {
        return entry.value;
      }
    }
    return null;
  }

  void _setHeaderIfMissing(
    Map<String, String> headers,
    String name,
    String value,
  ) {
    if (_headerValue(headers, name) != null) {
      return;
    }
    headers[name] = value;
  }

  String _canonicalDirectPlaybackHeaderName(String name) {
    return switch (name.toLowerCase()) {
      'authorization' => 'Authorization',
      'cookie' => 'Cookie',
      'origin' => 'Origin',
      'referer' => 'Referer',
      'user-agent' => 'User-Agent',
      _ => name,
    };
  }

  String? _originForUri(Uri uri) {
    if (!uri.hasScheme || uri.host.trim().isEmpty) {
      return null;
    }
    final portPart = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$portPart';
  }

  String _directSourceMessageSignature({
    required Uri uri,
    required PlaybackSourceKind sourceKind,
    required Map<String, String> httpHeaders,
    Uri? pageUri,
  }) {
    final normalizedHeaders = httpHeaders.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    return <String>[
      sourceKind.name,
      uri.toString(),
      pageUri?.toString() ?? '',
      for (final entry in normalizedHeaders) '${entry.key}=${entry.value}',
    ].join('|');
  }

  Future<void> _runPlayerBridgeCommand(
    String command, {
    Object? argument,
  }) async {
    if (_disposed || !_initialized || _controller == null) {
      return;
    }

    final argumentJson = jsonEncode(argument);
    final activeFrameIdJson = jsonEncode(_activeFrameId);
    try {
      await _controller!.evaluateJavascript(source: '''
(() => {
  try {
    const payload = {
      type: 'cheriflix-command',
      command: ${jsonEncode(command)},
      argument: $argumentJson,
      targetFrameId: $activeFrameIdJson,
    };
    if (window.__cheriflixDispatchPlayerCommand) {
      window.__cheriflixDispatchPlayerCommand(payload);
    }
  } catch (_) {}
})();
''');
    } catch (_) {
      // Keep playback alive if a hostile provider rejects script execution.
    }
  }

  PlaybackPresentation _presentationFromMessage(Map<dynamic, dynamic> message) {
    final currentSeconds = (message['currentSeconds'] as num?)?.toDouble() ?? 0;
    final durationSeconds =
        (message['durationSeconds'] as num?)?.toDouble() ?? 0;
    final playbackRate = (message['playbackRate'] as num?)?.toDouble() ?? 1;
    final zoomScale = (message['zoomScale'] as num?)?.toDouble() ?? 1;
    final qualities =
        (message['qualityOptions'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>()
            .toList(growable: false);
    final captionTracks =
        (message['captionTracks'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<dynamic, dynamic>>()
            .map((track) => CaptionTrack.fromJson(
                  Map<String, dynamic>.from(track),
                ))
            .toList(growable: false);
    final selectedCaptionTrackId =
        '${message['selectedCaptionTrackId'] ?? ''}'.trim();
    final selectedCaptionTrackIdOrNull =
        selectedCaptionTrackId.isEmpty ? null : selectedCaptionTrackId;
    return PlaybackPresentation(
      currentPosition: Duration(milliseconds: (currentSeconds * 1000).round()),
      totalDuration: Duration(milliseconds: (durationSeconds * 1000).round()),
      isPaused: message['paused'] != false,
      isMuted: message['muted'] == true,
      playbackRate: playbackRate,
      zoomScale: zoomScale,
      captionsAvailable: message['captionsAvailable'] == true,
      captionsEnabled: message['captionsEnabled'] == true,
      captionTracks: captionTracks,
      selectedCaptionTrackId: selectedCaptionTrackIdOrNull,
      selectedCaptionLabel: _genericTrackLabelForId(
        captionTracks,
        selectedCaptionTrackIdOrNull,
      ),
      qualityOptions: qualities.isEmpty ? const <String>['Auto'] : qualities,
      selectedQualityLabel:
          '${message['selectedQualityLabel'] ?? 'Auto'}'.trim().isEmpty
              ? 'Auto'
              : '${message['selectedQualityLabel']}',
      bridgeAvailable: message['bridgeAvailable'] == true,
      videoWidth: (message['videoWidth'] as num?)?.round() ?? 0,
      videoHeight: (message['videoHeight'] as num?)?.round() ?? 0,
      hasRenderedFrame: message['hasRenderedFrame'] == true,
    );
  }

  void _updateSubtitleLinesFromMessage(Map<dynamic, dynamic> message) {
    if (_disposed) {
      return;
    }
    final rawLines = message['subtitleLines'];
    if (rawLines is! List) {
      return;
    }
    _subtitleLines.value = List<String>.unmodifiable(
      rawLines
          .map((line) => '$line'.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false),
    );
  }

  String _selectedCaptionLabelForTracks(
    List<CaptionTrack> tracks,
    String? selectedTrackId,
  ) {
    return _genericTrackLabelForId(tracks, selectedTrackId);
  }
}
