import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/thumbnail_service.dart';

typedef ScrubSeekCommit = Future<void> Function(int timeMs);

/// Progressive scrub preview widget:
/// - While dragging: fast preview requests (cache-first, approximate allowed).
/// - On short pause or drag end: exact timestamp extraction and replacement.
class ScrubThumbnailPreview extends StatefulWidget {
  const ScrubThumbnailPreview({
    super.key,
    required this.thumbnailService,
    required this.videoId,
    required this.videoPath,
    required this.durationMs,
    required this.currentTimeMs,
    this.onScrubPositionChanged,
    this.onScrubCommitted,
    this.thumbnailWidth = 240,
    this.thumbnailHeight = 135,
    this.exactDebounce = const Duration(milliseconds: 150),
    this.enabled = true,
  });

  final ThumbnailService thumbnailService;
  final String videoId;
  final String videoPath;
  final int durationMs;
  final int currentTimeMs;
  final ValueChanged<int>? onScrubPositionChanged;
  final ScrubSeekCommit? onScrubCommitted;
  final int thumbnailWidth;
  final int thumbnailHeight;
  final Duration exactDebounce;
  final bool enabled;

  @override
  State<ScrubThumbnailPreview> createState() => _ScrubThumbnailPreviewState();
}

class _ScrubThumbnailPreviewState extends State<ScrubThumbnailPreview> {
  bool _isDragging = false;
  double _sliderValue = 0;
  Uint8List? _currentThumbnailBytes;
  bool _currentThumbnailExact = false;
  int _displayedTimeMs = 0;
  int _lastDragTimeMs = 0;
  int _latestInteractionToken = 0;
  int _latestExactToken = 0;
  Timer? _exactDebounceTimer;

  @override
  void initState() {
    super.initState();
    _sliderValue = widget.currentTimeMs.toDouble();
    _displayedTimeMs = widget.currentTimeMs;
    unawaited(widget.thumbnailService.initialize());
    unawaited(_loadPreviewFor(widget.currentTimeMs,
        token: ++_latestInteractionToken));
  }

  @override
  void didUpdateWidget(covariant ScrubThumbnailPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging && widget.currentTimeMs != oldWidget.currentTimeMs) {
      _sliderValue = _clampMs(widget.currentTimeMs).toDouble();
      _displayedTimeMs = _clampMs(widget.currentTimeMs);
    }
  }

  @override
  void dispose() {
    _exactDebounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeTimeMs =
        _clampMs(_isDragging ? _sliderValue.round() : _displayedTimeMs);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _buildThumbnailCard(context, activeTimeMs),
        const SizedBox(height: 10),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            min: 0,
            max: math.max(1, widget.durationMs).toDouble(),
            value: _sliderValue.clamp(
                0, math.max(1, widget.durationMs).toDouble()),
            onChangeStart: widget.enabled ? _handleDragStart : null,
            onChanged: widget.enabled ? _handleDragUpdate : null,
            onChangeEnd: widget.enabled ? _handleDragEnd : null,
          ),
        ),
      ],
    );
  }

  Widget _buildThumbnailCard(BuildContext context, int activeTimeMs) {
    final width = widget.thumbnailWidth.toDouble();
    final height = widget.thumbnailHeight.toDouble();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 120),
      child: Container(
        key: ValueKey<String>(
          'thumb-${_currentThumbnailExact ? 'exact' : 'preview'}-$activeTimeMs-${_currentThumbnailBytes?.length ?? 0}',
        ),
        width: width,
        height: height + 34,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xE61A1A1A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x40FFFFFF)),
        ),
        child: Column(
          children: <Widget>[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _currentThumbnailBytes == null
                    ? const ColoredBox(
                        color: Color(0xFF101010),
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : Image.memory(
                        _currentThumbnailBytes!,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.low,
                        gaplessPlayback: true,
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  _formatTime(activeTimeMs),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                Text(
                  _currentThumbnailExact ? 'EXACT' : 'PREVIEW',
                  style: TextStyle(
                    color: _currentThumbnailExact
                        ? const Color(0xFF5DFFB3)
                        : const Color(0xFFFFD166),
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _handleDragStart(double value) {
    _isDragging = true;
    _sliderValue = value;
    final timeMs = _clampMs(value.round());
    _lastDragTimeMs = timeMs;
    _displayedTimeMs = timeMs;
    widget.onScrubPositionChanged?.call(timeMs);

    final token = ++_latestInteractionToken;
    unawaited(_loadPreviewFor(timeMs, token: token));
    _scheduleExactDebounce(timeMs, token: token);
  }

  void _handleDragUpdate(double value) {
    _sliderValue = value;
    final timeMs = _clampMs(value.round());
    _displayedTimeMs = timeMs;
    widget.onScrubPositionChanged?.call(timeMs);

    final direction = timeMs.compareTo(_lastDragTimeMs);
    _lastDragTimeMs = timeMs;

    final token = ++_latestInteractionToken;
    unawaited(_loadPreviewFor(timeMs, token: token));
    _scheduleExactDebounce(timeMs, token: token);
    unawaited(
      widget.thumbnailService.prefetchPreviewAround(
        widget.videoId,
        widget.videoPath,
        timeMs,
        direction: direction,
        width: widget.thumbnailWidth,
        height: widget.thumbnailHeight,
      ),
    );

    if (mounted) {
      setState(() {});
    }
  }

  void _handleDragEnd(double value) {
    _isDragging = false;
    final timeMs = _clampMs(value.round());
    _displayedTimeMs = timeMs;
    _sliderValue = timeMs.toDouble();

    widget.onScrubPositionChanged?.call(timeMs);
    unawaited(widget.onScrubCommitted?.call(timeMs));

    _exactDebounceTimer?.cancel();
    final token = ++_latestInteractionToken;
    unawaited(_loadExactFor(timeMs, token: token));
    if (mounted) {
      setState(() {});
    }
  }

  void _scheduleExactDebounce(int timeMs, {required int token}) {
    _exactDebounceTimer?.cancel();
    _exactDebounceTimer = Timer(widget.exactDebounce, () {
      if (!mounted || token != _latestInteractionToken) {
        return;
      }
      unawaited(_loadExactFor(timeMs, token: token));
    });
  }

  Future<void> _loadPreviewFor(int timeMs, {required int token}) async {
    final bytes = await widget.thumbnailService.getThumbnailBytes(
      widget.videoId,
      widget.videoPath,
      timeMs,
      exact: false,
      width: widget.thumbnailWidth,
      height: widget.thumbnailHeight,
    );
    if (!mounted || token != _latestInteractionToken) {
      return;
    }
    // Don't let a late preview overwrite an exact thumbnail for the same token.
    if (_currentThumbnailExact && token == _latestExactToken) {
      return;
    }
    if (bytes == null || bytes.isEmpty) {
      return;
    }
    setState(() {
      _currentThumbnailBytes = bytes;
      _currentThumbnailExact = false;
      _displayedTimeMs = _clampMs(timeMs);
    });
  }

  Future<void> _loadExactFor(int timeMs, {required int token}) async {
    _latestExactToken = token;
    final bytes = await widget.thumbnailService.getThumbnailBytes(
      widget.videoId,
      widget.videoPath,
      timeMs,
      exact: true,
      width: widget.thumbnailWidth,
      height: widget.thumbnailHeight,
    );
    if (!mounted || token != _latestInteractionToken) {
      return;
    }
    if (bytes == null || bytes.isEmpty) {
      return;
    }
    setState(() {
      _currentThumbnailBytes = bytes;
      _currentThumbnailExact = true;
      _displayedTimeMs = _clampMs(timeMs);
    });
  }

  int _clampMs(int value) {
    final maxValue = math.max(0, widget.durationMs);
    return value.clamp(0, maxValue);
  }

  String _formatTime(int timeMs) {
    var totalSeconds = timeMs ~/ 1000;
    if (totalSeconds < 0) {
      totalSeconds = 0;
    }
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
