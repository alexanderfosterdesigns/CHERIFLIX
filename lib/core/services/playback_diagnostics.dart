import 'dart:convert';

import '../models/media_type.dart';
import '../utils/safe_logging.dart';

enum PlaybackDiagnosticStage {
  playRequested,
  resolutionStarted,
  providerStarted,
  providerFinished,
  firstValidSource,
  manifestReady,
  playerLoadStarted,
  playerLoadFinished,
  firstFrame,
  initialBuffer,
  failover,
  exhausted,
}

class PlaybackDiagnosticEvent {
  const PlaybackDiagnosticEvent({
    required this.sessionId,
    required this.stage,
    required this.elapsedMs,
    required this.timestamp,
    this.providerKey,
    this.outcome,
    this.details = const <String, Object?>{},
  });

  final String sessionId;
  final PlaybackDiagnosticStage stage;
  final int elapsedMs;
  final DateTime timestamp;
  final String? providerKey;
  final String? outcome;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() => <String, Object?>{
        'sessionId': sessionId,
        'stage': stage.name,
        'elapsedMs': elapsedMs,
        'timestamp': timestamp.toUtc().toIso8601String(),
        if (providerKey != null) 'provider': providerKey,
        if (outcome != null) 'outcome': outcome,
        if (details.isNotEmpty) 'details': details,
      };
}

/// A bounded, development-facing playback event log. User-visible errors stay
/// simple while diagnostics retain the failing provider, stage and timing.
class PlaybackDiagnostics {
  PlaybackDiagnostics._();

  static final PlaybackDiagnostics instance = PlaybackDiagnostics._();
  static const int _eventLimit = 300;

  final List<PlaybackDiagnosticEvent> _events = <PlaybackDiagnosticEvent>[];
  final Map<String, Stopwatch> _sessionWatches = <String, Stopwatch>{};
  int _nextSession = 0;

  Duration? elapsedForSession(String sessionId) {
    final watch = _sessionWatches[sessionId];
    return watch?.elapsed;
  }

  List<PlaybackDiagnosticEvent> get recentEvents =>
      List<PlaybackDiagnosticEvent>.unmodifiable(_events);

  String startSession({
    required int tmdbId,
    required MediaType mediaType,
    int? seasonNumber,
    int? episodeNumber,
  }) {
    final sessionId =
        '${DateTime.now().millisecondsSinceEpoch}-${++_nextSession}';
    _sessionWatches[sessionId] = Stopwatch()..start();
    record(
      sessionId: sessionId,
      stage: PlaybackDiagnosticStage.playRequested,
      details: <String, Object?>{
        'tmdbId': tmdbId,
        'mediaType': mediaType.name,
        if (seasonNumber != null) 'season': seasonNumber,
        if (episodeNumber != null) 'episode': episodeNumber,
      },
    );
    return sessionId;
  }

  void record({
    required String sessionId,
    required PlaybackDiagnosticStage stage,
    String? providerKey,
    String? outcome,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    final elapsedMs = _sessionWatches[sessionId]?.elapsedMilliseconds ?? 0;
    final event = PlaybackDiagnosticEvent(
      sessionId: sessionId,
      stage: stage,
      elapsedMs: elapsedMs,
      timestamp: DateTime.now(),
      providerKey: providerKey,
      outcome: outcome,
      details: details,
    );
    _events.add(event);
    if (_events.length > _eventLimit) {
      _events.removeRange(0, _events.length - _eventLimit);
    }
    cheriflixLog('playback-pipeline', jsonEncode(event.toJson()));
  }

  void finishSession(String sessionId) {
    _sessionWatches.remove(sessionId)?.stop();
  }

  void clear() {
    _events.clear();
    for (final watch in _sessionWatches.values) {
      watch.stop();
    }
    _sessionWatches.clear();
  }
}
