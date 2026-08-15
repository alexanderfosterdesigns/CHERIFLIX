import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../services/thumbnail_service.dart';
import '../../widgets/scrub_thumbnail_preview.dart';

/// Example integration for exact-timestamp thumbnail scrubbing.
///
/// Assumes `videoPath` points to a local file path.
class SampleScrubPlayerScreen extends StatefulWidget {
  const SampleScrubPlayerScreen({
    super.key,
    required this.videoPath,
    required this.videoId,
  });

  final String videoPath;
  final String videoId;

  @override
  State<SampleScrubPlayerScreen> createState() =>
      _SampleScrubPlayerScreenState();
}

class _SampleScrubPlayerScreenState extends State<SampleScrubPlayerScreen> {
  late final Player _player = Player();
  late final VideoController _videoController = VideoController(_player);
  final ThumbnailService _thumbnailService = ThumbnailService();

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;

  int _durationMs = 0;
  int _positionMs = 0;
  bool _playing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _initialize() async {
    await _thumbnailService.initialize();
    if (!File(widget.videoPath).existsSync()) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Video file not found: ${widget.videoPath}';
      });
      return;
    }

    _positionSub = _player.stream.position.listen((position) {
      if (!mounted) {
        return;
      }
      setState(() {
        _positionMs = position.inMilliseconds;
      });
    });
    _durationSub = _player.stream.duration.listen((duration) {
      if (!mounted) {
        return;
      }
      setState(() {
        _durationMs = math.max(0, duration.inMilliseconds);
      });
    });
    _playingSub = _player.stream.playing.listen((playing) {
      if (!mounted) {
        return;
      }
      setState(() {
        _playing = playing;
      });
    });

    await _player.open(Media(widget.videoPath), play: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Sample Scrub Player'),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: <Widget>[
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Video(
                        controller: _videoController,
                        controls: NoVideoControls,
                        subtitleViewConfiguration:
                            const SubtitleViewConfiguration(visible: false),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ScrubThumbnailPreview(
                    thumbnailService: _thumbnailService,
                    videoId: widget.videoId,
                    videoPath: widget.videoPath,
                    durationMs: _durationMs,
                    currentTimeMs: _positionMs,
                    onScrubCommitted: (timeMs) async {
                      await _player.seek(Duration(milliseconds: timeMs));
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    IconButton(
                      onPressed: () async {
                        if (_playing) {
                          await _player.pause();
                        } else {
                          await _player.play();
                        }
                      },
                      icon: Icon(
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_formatTime(_positionMs)} / ${_formatTime(_durationMs)}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }

  String _formatTime(int ms) {
    final totalSeconds = ms < 0 ? 0 : ms ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
