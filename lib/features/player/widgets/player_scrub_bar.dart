import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/cheriflix_theme.dart';
import '../../../core/utils/safe_logging.dart';

void _logScrubBarDiagnostic(
  String message, {
  Object? error,
  StackTrace? stackTrace,
}) {
  cheriflixLog('scrub', message, error: error, stackTrace: stackTrace);
}

typedef PlayerScrubSeekCallback = Future<void> Function(Duration position);
typedef PlayerScrubFrameLoader = Future<String?> Function(Duration position);

class PlayerScrubBar extends StatefulWidget {
  const PlayerScrubBar({
    super.key,
    required this.position,
    required this.totalDuration,
    required this.focusNode,
    required this.frameCache,
    this.thumbnailAspectRatio = defaultThumbnailAspectRatio,
    this.onSeekRequested,
    this.onFrameRequested,
    this.onExitRequested,
    this.onScrubUiVisibilityChanged,
    this.thumbnailHeaders = const <String, String>{},
    this.upFallbackNodes = const <FocusNode>[],
    this.downFallbackNodes = const <FocusNode>[],
    this.enabled = true,
    this.stripHideDelay = _PlayerScrubBarState._stripHideDelay,
  });

  static const double defaultThumbnailAspectRatio = 16 / 9;

  final Duration position;
  final Duration totalDuration;
  final FocusNode focusNode;
  final Map<int, String> frameCache;
  final double thumbnailAspectRatio;
  final PlayerScrubSeekCallback? onSeekRequested;
  final PlayerScrubFrameLoader? onFrameRequested;
  final VoidCallback? onExitRequested;
  final ValueChanged<bool>? onScrubUiVisibilityChanged;
  final Map<String, String> thumbnailHeaders;
  final List<FocusNode> upFallbackNodes;
  final List<FocusNode> downFallbackNodes;
  final bool enabled;
  final Duration stripHideDelay;

  @override
  State<PlayerScrubBar> createState() => _PlayerScrubBarState();
}

class _PlayerScrubBarState extends State<PlayerScrubBar> {
  static const Duration _singleStep = Duration(seconds: 5);
  static const Duration _maxStep = Duration(seconds: 30);
  static const Duration _holdRampDuration = Duration(seconds: 2);
  static const Duration _holdRepeatDelay = Duration(milliseconds: 260);
  static const Duration _holdRepeatInterval = Duration(milliseconds: 180);
  static const Duration _stripHideDelay = Duration(seconds: 90);
  static const Duration _stripEnterDuration = Duration(milliseconds: 110);
  static const Duration _stripExitDuration = Duration(milliseconds: 140);
  static const int _minimumThumbnailCount = 3;
  static const int _maximumThumbnailCount = 6;
  static const double _minimumThumbnailWidth = 180;
  static const double _thumbnailGap = 6;
  static const double _thumbnailLabelGap = 8;
  static const double _thumbnailLabelHeight = 34;
  static const double _stripBottomGap = 6;

  bool _focused = false;
  bool _dragging = false;
  bool _stripVisible = false;
  Duration? _previewPosition;
  bool _hasPendingSeek = false;
  Timer? _holdDelayTimer;
  Timer? _holdRepeatTimer;
  Timer? _stripHideTimer;
  _ScrubDirection? _heldDirection;
  DateTime? _holdStartedAt;
  final Set<int> _loadingFrameKeys = <int>{};
  bool _frameRequestScheduled = false;
  _ThumbnailStripWindow? _pendingStripWindow;

  bool get _showScrubUi => _stripVisible;
  double get _thumbnailAspectRatio {
    final ratio = widget.thumbnailAspectRatio;
    if (!ratio.isFinite || ratio <= 0) {
      return PlayerScrubBar.defaultThumbnailAspectRatio;
    }
    return ratio;
  }

  Duration get _effectivePosition {
    if (_showScrubUi) {
      return _selectedThumbnailPosition();
    }
    return widget.position;
  }

  double get _effectiveProgress {
    final totalMillis = widget.totalDuration.inMilliseconds;
    if (totalMillis <= 0) {
      return 0;
    }
    return (_effectivePosition.inMilliseconds / totalMillis).clamp(0.0, 1.0);
  }

  bool get _isInteractive =>
      widget.enabled &&
      widget.onSeekRequested != null &&
      widget.totalDuration > Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocusNodeChange);
    _focused = widget.focusNode.hasFocus;
  }

  @override
  void didUpdateWidget(PlayerScrubBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusNodeChange);
      widget.focusNode.addListener(_handleFocusNodeChange);
      _focused = widget.focusNode.hasFocus;
    }
    if (!_stripVisible && !_dragging) {
      _previewPosition =
          widget.focusNode.hasFocus ? _alignedPosition(widget.position) : null;
      _hasPendingSeek = false;
    } else if (!_hasPendingSeek && !_dragging && _previewPosition == null) {
      _previewPosition = _alignedPosition(widget.position);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusNodeChange);
    _holdDelayTimer?.cancel();
    _holdRepeatTimer?.cancel();
    _stripHideTimer?.cancel();
    super.dispose();
  }

  void _handleFocusNodeChange() {
    final hasFocus = widget.focusNode.hasFocus;
    if (_focused == hasFocus) {
      return;
    }
    setState(() {
      _focused = hasFocus;
      if (hasFocus) {
        _previewPosition = _alignedPosition(widget.position);
      }
    });
    _stopContinuousScrub();
    _hideStripImmediately(clearPreview: true);
  }

  void _notifyScrubUiVisibility() {
    widget.onScrubUiVisibilityChanged?.call(_stripVisible);
  }

  void _showStrip() {
    _stripHideTimer?.cancel();
    _stripHideTimer = null;
    if (_stripVisible) {
      return;
    }
    setState(() {
      _stripVisible = true;
    });
    _notifyScrubUiVisibility();
  }

  void _scheduleStripHide() {
    if (!_stripVisible) {
      return;
    }
    _stripHideTimer?.cancel();
    _stripHideTimer = Timer(widget.stripHideDelay, () {
      if (!mounted || !_stripVisible) {
        return;
      }
      setState(() {
        _stripVisible = false;
        _previewPosition = null;
        _hasPendingSeek = false;
      });
      _notifyScrubUiVisibility();
    });
  }

  void _hideStripImmediately({bool clearPreview = false}) {
    _stripHideTimer?.cancel();
    _stripHideTimer = null;
    if (!_stripVisible && !clearPreview) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _stripVisible = false;
      if (clearPreview) {
        _previewPosition = null;
        _hasPendingSeek = false;
      }
    });
    _notifyScrubUiVisibility();
  }

  void _stopContinuousScrub() {
    _holdDelayTimer?.cancel();
    _holdDelayTimer = null;
    _holdRepeatTimer?.cancel();
    _holdRepeatTimer = null;
    _heldDirection = null;
    _holdStartedAt = null;
  }

  void _commitPendingSeek() {
    if (!_hasPendingSeek || !_isInteractive) {
      return;
    }
    _hasPendingSeek = false;
    final target = _selectedThumbnailPosition();
    unawaited(widget.onSeekRequested?.call(target));
  }

  Duration _selectedThumbnailPosition() {
    return _alignedPosition(_previewPosition ?? widget.position);
  }

  void _commitSelectedThumbnail() {
    if (!_isInteractive) {
      return;
    }
    final target = _selectedThumbnailPosition();
    setState(() {
      _previewPosition = target;
      _hasPendingSeek = false;
    });
    unawaited(widget.onSeekRequested?.call(target));
  }

  void _handleSelectPressed() {
    _stopContinuousScrub();
    if (!_stripVisible) {
      _activatePreviewIfNeeded();
      _showStrip();
      _scheduleStripHide();
      return;
    }
    if (_hasPendingSeek) {
      _commitSelectedThumbnail();
      _hideStripImmediately(clearPreview: true);
      return;
    }
    _hideStripImmediately(clearPreview: true);
  }

  Duration _clampPosition(Duration position) {
    final upperBound = widget.totalDuration;
    if (upperBound <= Duration.zero) {
      return Duration.zero;
    }
    if (position <= Duration.zero) {
      return Duration.zero;
    }
    if (position >= upperBound) {
      return upperBound;
    }
    return position;
  }

  Duration _alignedPosition(Duration position) {
    final maxAlignedSeconds =
        (widget.totalDuration.inSeconds ~/ _singleStep.inSeconds) *
            _singleStep.inSeconds;
    final clamped = _clampPosition(position);
    final alignedSeconds =
        (clamped.inSeconds ~/ _singleStep.inSeconds) * _singleStep.inSeconds;
    return Duration(seconds: alignedSeconds.clamp(0, maxAlignedSeconds));
  }

  Duration _holdStepSize(Duration elapsed) {
    final progress = (elapsed.inMilliseconds / _holdRampDuration.inMilliseconds)
        .clamp(0.0, 1.0);
    final eased = Curves.easeInOutCubic.transform(progress);
    final steppedSeconds = (lerpDouble(
              _singleStep.inSeconds.toDouble(),
              _maxStep.inSeconds.toDouble(),
              eased,
            )! /
            _singleStep.inSeconds)
        .round()
        .clamp(1, _maxStep.inSeconds ~/ _singleStep.inSeconds);
    return Duration(seconds: steppedSeconds * _singleStep.inSeconds);
  }

  void _applyStep(_ScrubDirection direction, Duration amount) {
    if (!_isInteractive) {
      return;
    }
    final signedAmount =
        direction == _ScrubDirection.forward ? amount : -amount;
    final base = _selectedThumbnailPosition();
    final next = _clampPosition(base + signedAmount);
    setState(() {
      _previewPosition = _alignedPosition(next);
      _hasPendingSeek = true;
    });
  }

  void _beginContinuousScrub(_ScrubDirection direction) {
    if (!_isInteractive) {
      return;
    }
    _showStrip();
    if (_heldDirection == direction) {
      return;
    }
    _stopContinuousScrub();
    _heldDirection = direction;
    _holdStartedAt = DateTime.now();
    _applyStep(direction, _singleStep);
    _holdDelayTimer = Timer(_holdRepeatDelay, () {
      _holdRepeatTimer = Timer.periodic(_holdRepeatInterval, (_) {
        final elapsed = DateTime.now().difference(_holdStartedAt!);
        _applyStep(direction, _holdStepSize(elapsed));
      });
    });
  }

  void _endContinuousScrub(_ScrubDirection direction) {
    if (_heldDirection != direction) {
      return;
    }
    _stopContinuousScrub();
    _scheduleStripHide();
  }

  void _activatePreviewIfNeeded() {
    if (_previewPosition != null) {
      return;
    }
    setState(() {
      _previewPosition = _alignedPosition(widget.position);
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_focused || !_isInteractive) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final direction = switch (key) {
      LogicalKeyboardKey.arrowLeft => _ScrubDirection.backward,
      LogicalKeyboardKey.arrowRight => _ScrubDirection.forward,
      _ => null,
    };

    if (direction != null) {
      _activatePreviewIfNeeded();
      if (event is KeyUpEvent) {
        _endContinuousScrub(direction);
      } else if (event is KeyDownEvent) {
        _beginContinuousScrub(direction);
      }
      return KeyEventResult.handled;
    }

    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (_isExitKey(key)) {
      _stopContinuousScrub();
      _hideStripImmediately(clearPreview: true);
      widget.onExitRequested?.call();
      return KeyEventResult.handled;
    }

    if (_isSelectKey(key)) {
      _handleSelectPressed();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      _moveFocus(
        TraversalDirection.up,
        widget.upFallbackNodes,
      );
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      _moveFocus(
        TraversalDirection.down,
        widget.downFallbackNodes,
      );
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _moveFocus(
    TraversalDirection direction,
    List<FocusNode> fallbackNodes,
  ) {
    _stopContinuousScrub();
    _hideStripImmediately(clearPreview: true);
    for (final node in fallbackNodes) {
      if (node.context == null) {
        continue;
      }
      node.requestFocus();
      return;
    }
    widget.focusNode.focusInDirection(direction);
  }

  int _thumbnailCountForWidth(double width) {
    if (width <= 0) {
      return 1;
    }

    final count =
        ((width + _thumbnailGap) / (_minimumThumbnailWidth + _thumbnailGap))
            .floor()
            .clamp(_minimumThumbnailCount, _maximumThumbnailCount);
    if (count.isEven && count > _minimumThumbnailCount) {
      return count - 1;
    }
    return count;
  }

  double _thumbnailWidthForCount(double width, int thumbnailCount) {
    if (thumbnailCount <= 0) {
      return width;
    }
    return (width - (_thumbnailGap * (thumbnailCount - 1))) / thumbnailCount;
  }

  double _thumbnailCardHeightForWidth(double thumbnailWidth) {
    if (thumbnailWidth <= 0) {
      return 0;
    }
    return thumbnailWidth / _thumbnailAspectRatio;
  }

  double _stripHeightForCardHeight(double thumbnailCardHeight) {
    return thumbnailCardHeight + _thumbnailLabelGap + _thumbnailLabelHeight;
  }

  _ThumbnailStripWindow _thumbnailStripWindowForCount(int thumbnailCount) {
    final maxAlignedSeconds =
        (widget.totalDuration.inSeconds ~/ _singleStep.inSeconds) *
            _singleStep.inSeconds;
    final desiredActiveIndex = thumbnailCount ~/ 2;
    final alignedCurrentPosition = _alignedPosition(_effectivePosition);
    final windowSpanSeconds =
        math.max(0, thumbnailCount - 1) * _singleStep.inSeconds;
    final maxStartSeconds = math.max(0, maxAlignedSeconds - windowSpanSeconds);
    var leadingSeconds = alignedCurrentPosition.inSeconds -
        (desiredActiveIndex * _singleStep.inSeconds);
    if (leadingSeconds < 0) {
      leadingSeconds = 0;
    } else if (leadingSeconds > maxStartSeconds) {
      leadingSeconds = maxStartSeconds;
    }
    final positions = List<Duration>.generate(thumbnailCount, (index) {
      final offsetSeconds = index * _singleStep.inSeconds;
      final positionSeconds = math.min(
        maxAlignedSeconds,
        leadingSeconds + offsetSeconds,
      );
      return Duration(seconds: positionSeconds);
    });
    final activeIndex = ((alignedCurrentPosition.inSeconds - leadingSeconds) ~/
            _singleStep.inSeconds)
        .clamp(0, thumbnailCount - 1);
    return _ThumbnailStripWindow(
      positions: positions,
      activeIndex: activeIndex,
    );
  }

  void _requestVisibleFrames(_ThumbnailStripWindow stripWindow) {
    final loader = widget.onFrameRequested;
    if (!_stripVisible || loader == null) {
      return;
    }
    for (final position in _requestPositionsForWindow(stripWindow)) {
      final cacheKey = position.inSeconds;
      if (widget.frameCache.containsKey(cacheKey) ||
          _loadingFrameKeys.contains(cacheKey)) {
        continue;
      }
      if (mounted) {
        setState(() {
          _loadingFrameKeys.add(cacheKey);
        });
      } else {
        _loadingFrameKeys.add(cacheKey);
      }
      unawaited(() async {
        try {
          final thumbnailUrl = await loader(position);
          if (!mounted || thumbnailUrl == null || thumbnailUrl.trim().isEmpty) {
            return;
          }
          if (widget.frameCache.containsKey(cacheKey)) {
            setState(() {});
          }
        } catch (_) {
        } finally {
          if (!mounted) {
            _loadingFrameKeys.remove(cacheKey);
            return;
          }
          setState(() {
            _loadingFrameKeys.remove(cacheKey);
          });
        }
      }());
    }
  }

  void _scheduleVisibleFrameRequest(_ThumbnailStripWindow stripWindow) {
    final loader = widget.onFrameRequested;
    if (!_stripVisible || loader == null) {
      return;
    }

    _pendingStripWindow = stripWindow;
    if (_frameRequestScheduled) {
      return;
    }

    _frameRequestScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _frameRequestScheduled = false;
      final pendingStripWindow = _pendingStripWindow;
      _pendingStripWindow = null;
      if (!mounted || !_stripVisible || pendingStripWindow == null) {
        return;
      }
      _requestVisibleFrames(pendingStripWindow);
    });
  }

  Iterable<Duration> _requestPositionsForWindow(
    _ThumbnailStripWindow stripWindow,
  ) sync* {
    if (stripWindow.positions.isEmpty) {
      return;
    }

    yield stripWindow.positions[stripWindow.activeIndex];

    for (var offset = 1; offset < stripWindow.positions.length; offset += 1) {
      final previousIndex = stripWindow.activeIndex - offset;
      if (previousIndex >= 0) {
        yield stripWindow.positions[previousIndex];
      }

      final nextIndex = stripWindow.activeIndex + offset;
      if (nextIndex < stripWindow.positions.length) {
        yield stripWindow.positions[nextIndex];
      }
    }
  }

  double _clampProgress(double localDx, double width) {
    if (width <= 0) {
      return 0;
    }
    return (localDx / width).clamp(0.0, 1.0);
  }

  Duration _positionForDx(double localDx, double width) {
    final progress = _clampProgress(localDx, width);
    final totalMillis = widget.totalDuration.inMilliseconds;
    return Duration(milliseconds: (totalMillis * progress).round());
  }

  void _handleDragStart(double localDx, double width) {
    if (!_isInteractive) {
      return;
    }
    widget.focusNode.requestFocus();
    _showStrip();
    final position = _alignedPosition(_positionForDx(localDx, width));
    setState(() {
      _dragging = true;
      _previewPosition = position;
      _hasPendingSeek = true;
    });
  }

  void _handleDragUpdate(double localDx, double width) {
    if (!_isInteractive) {
      return;
    }
    final position = _alignedPosition(_positionForDx(localDx, width));
    setState(() {
      _previewPosition = position;
      _hasPendingSeek = true;
    });
  }

  void _handleDragEnd() {
    if (!_dragging) {
      return;
    }
    setState(() {
      _dragging = false;
    });
    _commitPendingSeek();
    _scheduleStripHide();
  }

  void _handleTap(double localDx, double width) {
    if (!_isInteractive) {
      return;
    }
    widget.focusNode.requestFocus();
    final position = _alignedPosition(_positionForDx(localDx, width));
    setState(() {
      _previewPosition = position;
      _hasPendingSeek = true;
    });
    _commitPendingSeek();
  }

  @override
  Widget build(BuildContext context) {
    final handleDiameter = _focused ? 17.0 : 16.0;
    final stripAnimationDuration =
        _showScrubUi ? _stripEnterDuration : _stripExitDuration;

    return Focus(
      key: const ValueKey<String>('player_scrub_bar'),
      focusNode: widget.focusNode,
      canRequestFocus: widget.enabled,
      onKeyEvent: _handleKeyEvent,
      child: MouseRegion(
        cursor: _isInteractive ? SystemMouseCursors.click : MouseCursor.defer,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            LayoutBuilder(
              builder: (context, constraints) {
                final stripWidth = constraints.maxWidth;
                final thumbnailCount = _thumbnailCountForWidth(stripWidth);
                final thumbnailWidth =
                    _thumbnailWidthForCount(stripWidth, thumbnailCount);
                final thumbnailCardHeight =
                    _thumbnailCardHeightForWidth(thumbnailWidth);
                final stripWindow =
                    _thumbnailStripWindowForCount(thumbnailCount);
                final stripHeight =
                    _stripHeightForCardHeight(thumbnailCardHeight);
                _scheduleVisibleFrameRequest(stripWindow);
                return AnimatedSize(
                  duration: stripAnimationDuration,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    height: _showScrubUi ? stripHeight : 0,
                    child: ClipRect(
                      child: AnimatedSlide(
                        duration: stripAnimationDuration,
                        curve: Curves.easeOutCubic,
                        offset:
                            _showScrubUi ? Offset.zero : const Offset(0, 0.08),
                        child: AnimatedOpacity(
                          duration: stripAnimationDuration,
                          curve: Curves.easeOutCubic,
                          opacity: _showScrubUi ? 1 : 0,
                          child: RepaintBoundary(
                            child: SizedBox(
                              width: stripWidth,
                              height: stripHeight,
                              child: _ThumbnailStrip(
                                positions: stripWindow.positions,
                                activeIndex: stripWindow.activeIndex,
                                thumbnailWidth: thumbnailWidth,
                                thumbnailCardHeight: thumbnailCardHeight,
                                thumbnailAspectRatio: _thumbnailAspectRatio,
                                stripHeight: stripHeight,
                                stripWidth: stripWidth,
                                frameCache: widget.frameCache,
                                loadingFrameKeys: _loadingFrameKeys,
                                thumbnailHeaders: widget.thumbnailHeaders,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: _stripBottomGap),
            SizedBox(
              height: 22,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final progress = _effectiveProgress;
                  final handleOffset = (width - handleDiameter) * progress;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: !_isInteractive
                        ? null
                        : (details) =>
                            _handleTap(details.localPosition.dx, width),
                    onHorizontalDragStart: !_isInteractive
                        ? null
                        : (details) => _handleDragStart(
                              details.localPosition.dx,
                              width,
                            ),
                    onHorizontalDragUpdate: !_isInteractive
                        ? null
                        : (details) => _handleDragUpdate(
                              details.localPosition.dx,
                              width,
                            ),
                    onHorizontalDragEnd:
                        !_isInteractive ? null : (_) => _handleDragEnd(),
                    onHorizontalDragCancel: _handleDragEnd,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: <Widget>[
                        Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0x664B4B4B),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        Container(
                          width: width * progress,
                          height: 4,
                          decoration: BoxDecoration(
                            color: CheriflixColors.accentRed,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: _showScrubUi
                                ? const <BoxShadow>[
                                    BoxShadow(
                                      color: Color(0x55E50914),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        if (_focused)
                          Container(
                            height: 4,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0x22FFFFFF),
                              ),
                            ),
                          ),
                        Positioned(
                          left: handleOffset,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            curve: Curves.easeOutCubic,
                            width: handleDiameter,
                            height: handleDiameter,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: <BoxShadow>[
                                const BoxShadow(
                                  color: Color(0x66000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 1),
                                ),
                                if (_focused)
                                  const BoxShadow(
                                    color: Color(0x33FFFFFF),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThumbnailStrip extends StatelessWidget {
  const _ThumbnailStrip({
    required this.positions,
    required this.activeIndex,
    required this.thumbnailWidth,
    required this.thumbnailCardHeight,
    required this.thumbnailAspectRatio,
    required this.stripHeight,
    required this.stripWidth,
    required this.frameCache,
    required this.loadingFrameKeys,
    required this.thumbnailHeaders,
  });

  final List<Duration> positions;
  final int activeIndex;
  final double thumbnailWidth;
  final double thumbnailCardHeight;
  final double thumbnailAspectRatio;
  final double stripHeight;
  final double stripWidth;
  final Map<int, String> frameCache;
  final Set<int> loadingFrameKeys;
  final Map<String, String> thumbnailHeaders;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizedBox(
        key: const ValueKey<String>('player_scrub_thumbnail_strip'),
        width: stripWidth,
        height: stripHeight,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Positioned.fill(
              child: const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      stops: <double>[0, 0.12, 0.38, 0.72, 1],
                      colors: <Color>[
                        Color(0xFF000000),
                        Color(0xF0000000),
                        Color(0xAE000000),
                        Color(0x36000000),
                        Color(0x00000000),
                      ],
                    ),
                  ),
                  child: SizedBox.expand(),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (var index = 0;
                    index < positions.length;
                    index += 1) ...<Widget>[
                  _buildThumbnailItem(index: index),
                  if (index < positions.length - 1)
                    const SizedBox(width: _PlayerScrubBarState._thumbnailGap),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnailItem({
    required int index,
  }) {
    final isActive = index == activeIndex;
    return SizedBox(
      width: thumbnailWidth,
      child: _ThumbnailCell(
        frameKey: ValueKey<String>(
          'player_scrub_thumbnail_frame_${positions[index].inSeconds}',
        ),
        timestamp: positions[index],
        imageUrl: frameCache[positions[index].inSeconds],
        loading: loadingFrameKeys.contains(positions[index].inSeconds),
        active: isActive,
        width: thumbnailWidth,
        imageHeight: thumbnailCardHeight,
        aspectRatio: thumbnailAspectRatio,
        imageHeaders: thumbnailHeaders,
        borderRadius: BorderRadius.only(
          topLeft: index == 0 ? Radius.zero : const Radius.circular(6),
          bottomLeft: index == 0 ? Radius.zero : const Radius.circular(6),
          topRight: index == positions.length - 1
              ? Radius.zero
              : const Radius.circular(6),
          bottomRight: index == positions.length - 1
              ? Radius.zero
              : const Radius.circular(6),
        ),
      ),
    );
  }
}

class _ThumbnailCell extends StatelessWidget {
  const _ThumbnailCell({
    required this.frameKey,
    required this.timestamp,
    required this.imageUrl,
    required this.loading,
    required this.active,
    required this.width,
    required this.imageHeight,
    required this.aspectRatio,
    required this.imageHeaders,
    required this.borderRadius,
  });

  final Key frameKey;
  final Duration timestamp;
  final String? imageUrl;
  final bool loading;
  final bool active;
  final double width;
  final double imageHeight;
  final double aspectRatio;
  final Map<String, String> imageHeaders;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final label = _formatDurationLabel(timestamp);
    final decodedDataBytes = _tryDecodeDataImageBytes(imageUrl);
    final localImageFile = _tryParseLocalImageFile(imageUrl);
    final devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final cacheWidth = (width * devicePixelRatio).ceil().clamp(1, 512).toInt();
    final cacheHeight =
        (imageHeight * devicePixelRatio).ceil().clamp(1, 288).toInt();
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ClipRRect(
            borderRadius: borderRadius,
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: SizedBox(
                key: frameKey,
                width: width,
                height: imageHeight,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 110),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeOutCubic,
                  layoutBuilder: (currentChild, previousChildren) {
                    return Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        ...previousChildren,
                        if (currentChild != null) currentChild,
                      ],
                    );
                  },
                  child: imageUrl == null
                      ? Stack(
                          key: const ValueKey<String>('thumbnail_placeholder'),
                          fit: StackFit.expand,
                          children: <Widget>[
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                color: Color(0xFF111111),
                              ),
                              child: SizedBox.expand(),
                            ),
                            if (loading)
                              Center(
                                child: SizedBox(
                                  width: active ? 24 : 20,
                                  height: active ? 24 : 20,
                                  child: CircularProgressIndicator(
                                    key: ValueKey<String>(
                                      'thumbnail_loading_indicator_'
                                      '${timestamp.inSeconds}',
                                    ),
                                    strokeWidth: active ? 2.4 : 2.0,
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        )
                      : SizedBox.expand(
                          child: decodedDataBytes != null
                              ? Image.memory(
                                  decodedDataBytes,
                                  key: ValueKey<Object?>(imageUrl),
                                  cacheWidth: cacheWidth,
                                  cacheHeight: cacheHeight,
                                  fit: BoxFit.cover,
                                  filterQuality: FilterQuality.none,
                                  isAntiAlias: false,
                                  gaplessPlayback: true,
                                  errorBuilder: (context, error, stackTrace) {
                                    _logScrubBarDiagnostic(
                                      'Failed to render scrub thumbnail '
                                      'timestamp=${timestamp.inSeconds}s '
                                      'url=$imageUrl',
                                      error: error,
                                      stackTrace: stackTrace,
                                    );
                                    return const DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Color(0xFF111111),
                                      ),
                                      child: SizedBox.expand(),
                                    );
                                  },
                                )
                              : localImageFile != null
                                  ? Image.file(
                                      localImageFile,
                                      key: ValueKey<Object?>(imageUrl),
                                      cacheWidth: cacheWidth,
                                      cacheHeight: cacheHeight,
                                      fit: BoxFit.cover,
                                      filterQuality: FilterQuality.none,
                                      isAntiAlias: false,
                                      gaplessPlayback: true,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                        _logScrubBarDiagnostic(
                                          'Failed to render local scrub '
                                          'thumbnail timestamp='
                                          '${timestamp.inSeconds}s '
                                          'url=$imageUrl',
                                          error: error,
                                          stackTrace: stackTrace,
                                        );
                                        return const DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: Color(0xFF111111),
                                          ),
                                          child: SizedBox.expand(),
                                        );
                                      },
                                    )
                                  : Image.network(
                                      imageUrl!,
                                      key: ValueKey<Object?>(imageUrl),
                                      cacheWidth: cacheWidth,
                                      cacheHeight: cacheHeight,
                                      fit: BoxFit.cover,
                                      filterQuality: FilterQuality.none,
                                      isAntiAlias: false,
                                      gaplessPlayback: true,
                                      headers: imageHeaders.isEmpty
                                          ? null
                                          : imageHeaders,
                                      frameBuilder: (context, child, frame,
                                          wasSyncLoaded) {
                                        if (frame != null || wasSyncLoaded) {
                                          _logScrubBarDiagnostic(
                                            'Rendered scrub thumbnail '
                                            'timestamp=${timestamp.inSeconds}s '
                                            'url=$imageUrl',
                                          );
                                        }
                                        return child;
                                      },
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                        _logScrubBarDiagnostic(
                                          'Failed to render scrub thumbnail '
                                          'timestamp=${timestamp.inSeconds}s '
                                          'url=$imageUrl',
                                          error: error,
                                          stackTrace: stackTrace,
                                        );
                                        return const DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: Color(0xFF111111),
                                          ),
                                          child: SizedBox.expand(),
                                        );
                                      },
                                    ),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: _PlayerScrubBarState._thumbnailLabelGap),
          SizedBox(
            height: _PlayerScrubBarState._thumbnailLabelHeight,
            child: Align(
              alignment: Alignment.center,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? Colors.white : const Color(0xA6FFFFFF),
                  fontFamily: CheriflixTypography.subtitleFamily,
                  fontSize: active ? 15 : 14,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Uint8List? _tryDecodeDataImageBytes(String? url) {
    final value = url?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    if (!value.startsWith('data:image/')) {
      return null;
    }
    final marker = ';base64,';
    final markerIndex = value.indexOf(marker);
    if (markerIndex < 0) {
      return null;
    }
    final encoded = value.substring(markerIndex + marker.length);
    if (encoded.isEmpty) {
      return null;
    }
    try {
      return base64Decode(encoded);
    } on FormatException {
      return null;
    }
  }

  File? _tryParseLocalImageFile(String? url) {
    final value = url?.trim();
    if (value == null || value.isEmpty || !value.startsWith('file://')) {
      return null;
    }
    try {
      final uri = Uri.parse(value);
      return File(uri.toFilePath(windows: Platform.isWindows));
    } catch (_) {
      return null;
    }
  }
}

enum _ScrubDirection {
  backward,
  forward,
}

class _ThumbnailStripWindow {
  const _ThumbnailStripWindow({
    required this.positions,
    required this.activeIndex,
  });

  final List<Duration> positions;
  final int activeIndex;
}

bool _isExitKey(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.escape ||
      key == LogicalKeyboardKey.backspace ||
      key == LogicalKeyboardKey.goBack ||
      key == LogicalKeyboardKey.browserBack ||
      key == LogicalKeyboardKey.gameButtonB ||
      key == LogicalKeyboardKey.mediaPlayPause ||
      key == LogicalKeyboardKey.mediaPlay ||
      key == LogicalKeyboardKey.mediaPause;
}

bool _isSelectKey(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.gameButtonA;
}

String _formatDurationLabel(Duration duration) {
  if (duration.isNegative) {
    duration = Duration.zero;
  }
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}
