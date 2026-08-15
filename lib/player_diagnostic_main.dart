import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'core/utils/safe_logging.dart';

void _logDiagnostic(
  String message, {
  Object? error,
  StackTrace? stackTrace,
}) {
  cheriflixLog(
    'player diagnostic',
    message,
    error: error,
    stackTrace: stackTrace,
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _logDiagnostic(
      'Flutter framework error.',
      error: details.exception,
      stackTrace: details.stack,
    );
  };
  runApp(const _PlayerDiagnosticApp());
}

class _PlayerDiagnosticApp extends StatelessWidget {
  const _PlayerDiagnosticApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _PlayerDiagnosticScreen(),
    );
  }
}

class _PlayerDiagnosticScreen extends StatefulWidget {
  const _PlayerDiagnosticScreen();

  @override
  State<_PlayerDiagnosticScreen> createState() =>
      _PlayerDiagnosticScreenState();
}

class _PlayerDiagnosticScreenState extends State<_PlayerDiagnosticScreen> {
  static final Uri _diagnosticUri = Uri.parse(
    const String.fromEnvironment(
      'CHERIFLIX_DIAGNOSTIC_URI',
      defaultValue: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    ),
  );
  static const bool _enableHardwareAcceleration = bool.fromEnvironment(
    'CHERIFLIX_DIAGNOSTIC_HWACCEL',
    defaultValue: true,
  );
  static const String _screenshotPath = String.fromEnvironment(
    'CHERIFLIX_DIAGNOSTIC_SCREENSHOT_PATH',
    defaultValue: '',
  );
  static const bool _verboseMpvLogs = bool.fromEnvironment(
    'CHERIFLIX_DIAGNOSTIC_VERBOSE_MPV',
    defaultValue: false,
  );
  static const int _configuredVideoWidth = int.fromEnvironment(
    'CHERIFLIX_DIAGNOSTIC_VIDEO_WIDTH',
    defaultValue: 0,
  );
  static const int _configuredVideoHeight = int.fromEnvironment(
    'CHERIFLIX_DIAGNOSTIC_VIDEO_HEIGHT',
    defaultValue: 0,
  );

  late final Player _player = Player(
    configuration: PlayerConfiguration(
      libass: false,
      logLevel: _verboseMpvLogs ? MPVLogLevel.trace : MPVLogLevel.error,
    ),
  );
  VideoController? _controller;
  Timer? _logTimer;
  Timer? _exitTimer;
  StreamSubscription<PlayerLog>? _playerLogSubscription;
  StreamSubscription<String>? _playerErrorSubscription;
  Timer? _screenshotTimer;
  String? _errorMessage;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initializePlayer());
  }

  @override
  void dispose() {
    _logTimer?.cancel();
    _exitTimer?.cancel();
    _screenshotTimer?.cancel();
    _playerLogSubscription?.cancel();
    _playerErrorSubscription?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    try {
      _logDiagnostic('Creating VideoController for minimal desktop harness.');
      final controller = VideoController(
        _player,
        configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: _enableHardwareAcceleration,
          width: _configuredVideoWidth > 0 ? _configuredVideoWidth : null,
          height: _configuredVideoHeight > 0 ? _configuredVideoHeight : null,
        ),
      );
      _controller = controller;
      controller.id.addListener(() {
        _logDiagnostic('VideoController texture id=${controller.id.value}');
      });
      controller.rect.addListener(() {
        _logDiagnostic('VideoController rect=${controller.rect.value}');
      });
      if (_verboseMpvLogs) {
        _playerLogSubscription = _player.stream.log.listen((event) {
          _logDiagnostic(
            'mpv log prefix=${event.prefix} level=${event.level} text=${event.text}',
          );
        });
      }
      _playerErrorSubscription = _player.stream.error.listen((event) {
        _logDiagnostic('player error stream event=$event');
      });
      _logDiagnostic('VideoController created successfully.');
      await controller.platform.future;
      _logDiagnostic('VideoController native platform attached.');
      _logDiagnostic(
        'Opening diagnostic stream uri=$_diagnosticUri '
        'hwaccel=$_enableHardwareAcceleration '
        'configuredSize=${_configuredVideoWidth}x$_configuredVideoHeight',
      );
      await _player.open(
        Media(_diagnosticUri.toString()),
        play: true,
      );
      await _player.play();
      _logDiagnostic('Player open/play completed successfully.');
      _screenshotTimer = Timer(const Duration(seconds: 5), () {
        unawaited(_captureScreenshot());
      });
      _logTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final state = _player.state;
        _logDiagnostic(
          'state playing=${state.playing} position=${state.position} '
          'duration=${state.duration} width=${state.width} height=${state.height}',
        );
      });
      _exitTimer = Timer(const Duration(seconds: 12), () async {
        final state = _player.state;
        _logDiagnostic(
          'Exiting diagnostic app '
          'playing=${state.playing} position=${state.position} '
          'duration=${state.duration} width=${state.width} height=${state.height}',
        );
        await _player.dispose();
        exit(0);
      });
      if (!mounted) {
        return;
      }
      setState(() {
        _ready = true;
      });
    } catch (error, stackTrace) {
      _logDiagnostic(
        'Minimal desktop harness failed during initialization.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
      });
      _exitTimer = Timer(const Duration(seconds: 2), () => exit(1));
    }
  }

  Future<void> _captureScreenshot() async {
    try {
      final screenshot = await _player.screenshot(format: 'image/png');
      _logDiagnostic(
        'Screenshot capture completed bytes=${screenshot?.length ?? 0}',
      );
      if (screenshot == null ||
          screenshot.isEmpty ||
          _screenshotPath.trim().isEmpty) {
        return;
      }
      final outputFile = File(_screenshotPath);
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsBytes(screenshot, flush: true);
      _logDiagnostic('Saved screenshot to ${outputFile.path}');
    } catch (error, stackTrace) {
      _logDiagnostic(
        'Screenshot capture failed.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final videoWidth = _player.state.width;
    final videoHeight = _player.state.height;
    final aspectRatio = videoWidth != null &&
            videoHeight != null &&
            videoWidth > 0 &&
            videoHeight > 0
        ? videoWidth / videoHeight
        : 16 / 9;

    return Scaffold(
      backgroundColor: Colors.black,
      body: _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : !_ready || controller == null
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: AspectRatio(
                    aspectRatio: aspectRatio,
                    child: Video(
                      controller: controller,
                      controls: NoVideoControls,
                      fit: BoxFit.contain,
                      subtitleViewConfiguration:
                          const SubtitleViewConfiguration(
                        visible: false,
                      ),
                    ),
                  ),
                ),
    );
  }
}
