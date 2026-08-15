import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'app/cheriflix_app.dart';
import 'core/utils/safe_logging.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      await _runCheriflix();
    },
    (error, stackTrace) {
      _logUncaughtError('Uncaught zone error', error, stackTrace);
    },
  );
}

Future<void> _runCheriflix() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _logUncaughtError(
      'Uncaught Flutter error',
      details.exception,
      details.stack,
    );
  };
  ui.PlatformDispatcher.instance.onError = (error, stackTrace) {
    _logUncaughtError('Uncaught platform error', error, stackTrace);
    return true;
  };
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setPreferredOrientations(
      <DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
    );
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );
  }
  MediaKit.ensureInitialized();
  final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  PaintingBinding.instance.imageCache
    // Now that images are backed by an on-disk LRU cache
    // (CachedNetworkImage), the in-memory tier can be more generous.
    // The runtime-pressure controller still trims this on low-memory.
    ..maximumSize = isAndroid ? 140 : 200
    ..maximumSizeBytes = isAndroid ? 100 << 20 : 160 << 20;
  runApp(const CheriflixApp());
}

void _logUncaughtError(
  String label,
  Object error,
  StackTrace? stackTrace,
) {
  cheriflixLog('app', label, error: error, stackTrace: stackTrace);
}
