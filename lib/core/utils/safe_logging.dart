import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

const bool _isReleaseMode = bool.fromEnvironment('dart.vm.product');

void cheriflixLog(
  String component,
  String message, {
  Object? error,
  StackTrace? stackTrace,
}) {
  const releaseVisibleComponents = <String>{
    'playback-pipeline',
    'playback-provider',
    'player',
    'hls-proxy',
  };
  final releaseVisible = releaseVisibleComponents.contains(component);
  if (_isReleaseMode && error == null && !releaseVisible) {
    return;
  }
  final safeMessage = redactSensitive(message);
  developer.log(
    safeMessage,
    name: 'CHERIFLIX.$component',
    error: error == null ? null : redactSensitive(error),
    stackTrace: stackTrace,
  );
  // dart:developer events are not consistently surfaced by logcat in a
  // product APK. Keep the bounded playback trace visible on real Android TV
  // builds so resolver-to-first-frame failures can be diagnosed in situ.
  if (_isReleaseMode && releaseVisible) {
    debugPrint(
      '[CHERIFLIX.$component] $safeMessage'
      '${error == null ? '' : ' error=${redactSensitive(error)}'}',
    );
  }
}

String redactSensitive(Object? value) {
  var text = '$value';
  const patterns = <String>[
    r'(api[_-]?key=)[^&\s]+',
    r'(access[_-]?token=)[^&\s]+',
    r'([?&]token=)[^&\s]+',
    r'([?&](?:sig|signature|auth)=)[^&\s]+',
    r'((?:%3[fF]|%26)token%3[dD])[^%&\s]+',
    r'((?:%3[fF]|%26)(?:sig|signature|auth)%3[dD])[^%&\s]+',
    r'(refresh[_-]?token=)[^&\s]+',
    r'(client[_-]?secret=)[^&\s]+',
    r'(authorization:\s*bearer\s+)[^\s]+',
    r'(bearer\s+)[A-Za-z0-9._~+/=-]+',
    r'("accessToken"\s*:\s*")[^"]+',
    r'("refreshToken"\s*:\s*")[^"]+',
    r'("clientSecret"\s*:\s*")[^"]+',
    r'("apiKey"\s*:\s*")[^"]+',
  ];
  for (final pattern in patterns) {
    text = text.replaceAllMapped(
      RegExp(pattern, caseSensitive: false),
      (match) => '${match.group(1)}[redacted]',
    );
  }
  return text;
}
