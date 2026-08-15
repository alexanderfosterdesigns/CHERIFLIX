import 'dart:async';
import 'dart:math' as math;

import '../models/media_type.dart';

enum SourceFailureKind {
  probe,
  timeout,
  validation,
  load,
  startupStall,
  playbackStall,
  expired,
  blockedNavigation,
  sourceRejected,
  manualSwitch,
}

typedef SourceHealthPersistence = Future<void> Function(
  Map<String, Object?> state,
);

/// Tracks exact-title cooldowns separately from catalogue-wide performance.
///
/// A failure for one title can temporarily quarantine that provider for the
/// same movie/episode, but never globally blacklists it. Ranking history is
/// also split by movie/TV so a provider's movie performance cannot suppress a
/// working TV source (or vice versa).
class SourceHealthStore {
  SourceHealthStore({
    DateTime Function()? clock,
    Map<String, Object?>? persistedState,
    SourceHealthPersistence? onPersist,
  })  : _clock = clock ?? DateTime.now,
        _onPersist = onPersist {
    if (persistedState != null) {
      _restorePerformance(persistedState);
    }
  }

  final DateTime Function() _clock;
  final SourceHealthPersistence? _onPersist;
  final Map<_SourceHealthKey, _SourceHealthRecord> _records =
      <_SourceHealthKey, _SourceHealthRecord>{};
  final Map<_ProviderPerformanceKey, _ProviderPerformanceRecord>
      _providerPerformance =
      <_ProviderPerformanceKey, _ProviderPerformanceRecord>{};
  Timer? _persistTimer;

  void recordSuccess({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
    int? seasonNumber,
    int? episodeNumber,
    Duration? resolutionDuration,
    Duration? startupDuration,
  }) {
    final key = _SourceHealthKey(
      profileId: profileId,
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      providerIndex: providerIndex,
    );
    final record = _records[key];
    if (record != null) {
      record.failureStreak = 0;
      record.cooldownUntil = null;
    }
    final performance = _performance(providerIndex, mediaType);
    performance.successes += 1;
    performance.consecutiveFailures = 0;
    performance.lastSuccessAt = _clock();
    if (resolutionDuration != null) {
      performance.resolutionEwmaMs = _updateEwma(
        performance.resolutionEwmaMs,
        resolutionDuration.inMilliseconds.toDouble(),
      );
    }
    if (startupDuration != null) {
      performance.startupEwmaMs = _updateEwma(
        performance.startupEwmaMs,
        startupDuration.inMilliseconds.toDouble(),
      );
    }
    _schedulePersist();
  }

  void recordFailure({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
    required SourceFailureKind kind,
    int? seasonNumber,
    int? episodeNumber,
  }) {
    final key = _SourceHealthKey(
      profileId: profileId,
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      providerIndex: providerIndex,
    );
    final now = _clock();
    final record = _records.putIfAbsent(key, _SourceHealthRecord.new);
    record.failureStreak += 1;
    record.lastFailureAt = now;
    record.lastFailureKind = kind;
    record.cooldownUntil = now.add(_cooldownFor(kind, record.failureStreak));

    // Manual switching is a preference, not evidence that media was broken.
    if (kind != SourceFailureKind.manualSwitch) {
      final performance = _performance(providerIndex, mediaType);
      performance.failures += 1;
      performance.consecutiveFailures += 1;
      performance.lastFailureAt = now;
      performance.failuresByKind[kind] =
          (performance.failuresByKind[kind] ?? 0) + 1;
      _schedulePersist();
    }
  }

  void recordResolution({
    required int providerIndex,
    required MediaType mediaType,
    required Duration duration,
    required bool success,
    SourceFailureKind? failureKind,
  }) {
    final performance = _performance(providerIndex, mediaType);
    performance.resolutionEwmaMs = _updateEwma(
      performance.resolutionEwmaMs,
      duration.inMilliseconds.toDouble(),
    );
    if (success) {
      performance.resolutionSuccesses += 1;
    } else {
      performance.resolutionFailures += 1;
      if (failureKind != null) {
        performance.resolutionFailuresByKind[failureKind] =
            (performance.resolutionFailuresByKind[failureKind] ?? 0) + 1;
      }
    }
    _schedulePersist();
  }

  /// Lower scores are preferred. This score only changes ordering; it never
  /// makes a provider ineligible. Scores are contextual to movie/TV playback.
  double priorityScore(int providerIndex, MediaType mediaType) {
    final record =
        _providerPerformance[_ProviderPerformanceKey(providerIndex, mediaType)];
    if (record == null) {
      return 3500;
    }

    final playbackCompleted = record.successes + record.failures;
    final playbackSuccessRate = playbackCompleted == 0
        ? 0.5
        : (record.successes + 2) / (playbackCompleted + 4);
    final resolutionCompleted =
        record.resolutionSuccesses + record.resolutionFailures;
    final resolutionSuccessRate = resolutionCompleted == 0
        ? 0.5
        : (record.resolutionSuccesses + 2) / (resolutionCompleted + 4);
    final resolveMs = math.min(record.resolutionEwmaMs ?? 2500, 10000);
    final startupMs = math.min(record.startupEwmaMs ?? 6500, 15000);
    final recentFailureWeight = _recentFailureWeight(record.lastFailureAt);
    final typedPenalty = _typedFailurePenalty(record) * recentFailureWeight;

    return startupMs * 0.45 +
        resolveMs * 0.2 +
        (1 - playbackSuccessRate) * 1700 +
        (1 - resolutionSuccessRate) * 700 +
        math.min(record.consecutiveFailures, 3) * 550 * recentFailureWeight +
        typedPenalty;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'providers': _providerPerformance.entries
            .map(
              (entry) => <String, Object?>{
                'providerIndex': entry.key.providerIndex,
                'mediaType': entry.key.mediaType.name,
                ...entry.value.toJson(),
              },
            )
            .toList(growable: false),
      };

  double _typedFailurePenalty(_ProviderPerformanceRecord record) {
    double weighted(Map<SourceFailureKind, int> values) {
      var total = 0.0;
      for (final entry in values.entries) {
        final weight = switch (entry.key) {
          SourceFailureKind.probe => 30,
          SourceFailureKind.timeout => 110,
          SourceFailureKind.validation => 180,
          SourceFailureKind.load => 170,
          SourceFailureKind.startupStall => 240,
          SourceFailureKind.playbackStall => 210,
          SourceFailureKind.expired => 80,
          SourceFailureKind.blockedNavigation => 90,
          SourceFailureKind.sourceRejected => 160,
          SourceFailureKind.manualSwitch => 0,
        };
        total += math.min(entry.value, 4) * weight;
      }
      return total;
    }

    return math.min(
      weighted(record.failuresByKind) +
          weighted(record.resolutionFailuresByKind) * 0.5,
      1800,
    );
  }

  double _recentFailureWeight(DateTime? lastFailureAt) {
    if (lastFailureAt == null) return 0;
    final age = _clock().difference(lastFailureAt);
    if (age <= const Duration(hours: 1)) return 1;
    if (age <= const Duration(hours: 12)) return 0.7;
    if (age <= const Duration(days: 2)) return 0.35;
    return 0.1;
  }

  _ProviderPerformanceRecord _performance(
    int providerIndex,
    MediaType mediaType,
  ) =>
      _providerPerformance.putIfAbsent(
        _ProviderPerformanceKey(providerIndex, mediaType),
        _ProviderPerformanceRecord.new,
      );

  double _updateEwma(double? previous, double sample) {
    if (previous == null) return sample;
    const alpha = 0.3;
    return previous * (1 - alpha) + sample * alpha;
  }

  Duration? cooldownRemaining({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
    int? seasonNumber,
    int? episodeNumber,
  }) {
    final key = _SourceHealthKey(
      profileId: profileId,
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      providerIndex: providerIndex,
    );
    final record = _records[key];
    if (record == null || record.cooldownUntil == null) return null;
    final remaining = record.cooldownUntil!.difference(_clock());
    if (remaining <= Duration.zero) {
      record.cooldownUntil = null;
      return null;
    }
    return remaining;
  }

  Duration _cooldownFor(SourceFailureKind kind, int failureStreak) {
    final baseSeconds = switch (kind) {
      SourceFailureKind.probe => 10,
      SourceFailureKind.timeout => 15,
      SourceFailureKind.validation => 30,
      SourceFailureKind.load => 25,
      SourceFailureKind.startupStall => 35,
      SourceFailureKind.playbackStall => 45,
      SourceFailureKind.expired => 5,
      SourceFailureKind.blockedNavigation => 30,
      SourceFailureKind.sourceRejected => 45,
      SourceFailureKind.manualSwitch => 20,
    };
    final exponent = math.min(math.max(failureStreak - 1, 0), 3);
    return Duration(seconds: math.min(baseSeconds * (1 << exponent), 240));
  }

  void _schedulePersist() {
    final persist = _onPersist;
    if (persist == null) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 750), () {
      unawaited(persist(toJson()));
    });
  }

  void _restorePerformance(Map<String, Object?> state) {
    final providers = state['providers'];
    if (providers is! List) return;
    for (final item in providers.whereType<Map>()) {
      final map = item.cast<Object?, Object?>();
      final providerIndex = _readInt(map['providerIndex']);
      final mediaType = MediaType.values
          .where((value) => value.name == '${map['mediaType']}')
          .firstOrNull;
      if (providerIndex == null || mediaType == null) continue;
      _providerPerformance[_ProviderPerformanceKey(providerIndex, mediaType)] =
          _ProviderPerformanceRecord.fromJson(map);
    }
  }

  static int? _readInt(Object? value) =>
      value is int ? value : int.tryParse('$value');

  static double? _readDouble(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value');
}

class _SourceHealthKey {
  const _SourceHealthKey({
    required this.profileId,
    required this.tmdbId,
    required this.mediaType,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.providerIndex,
  });

  final String profileId;
  final int tmdbId;
  final MediaType mediaType;
  final int? seasonNumber;
  final int? episodeNumber;
  final int providerIndex;

  @override
  bool operator ==(Object other) =>
      other is _SourceHealthKey &&
      other.profileId == profileId &&
      other.tmdbId == tmdbId &&
      other.mediaType == mediaType &&
      other.seasonNumber == seasonNumber &&
      other.episodeNumber == episodeNumber &&
      other.providerIndex == providerIndex;

  @override
  int get hashCode => Object.hash(
        profileId,
        tmdbId,
        mediaType,
        seasonNumber,
        episodeNumber,
        providerIndex,
      );
}

class _ProviderPerformanceKey {
  const _ProviderPerformanceKey(this.providerIndex, this.mediaType);
  final int providerIndex;
  final MediaType mediaType;

  @override
  bool operator ==(Object other) =>
      other is _ProviderPerformanceKey &&
      other.providerIndex == providerIndex &&
      other.mediaType == mediaType;

  @override
  int get hashCode => Object.hash(providerIndex, mediaType);
}

class _SourceHealthRecord {
  int failureStreak = 0;
  DateTime? cooldownUntil;
  DateTime? lastFailureAt;
  SourceFailureKind? lastFailureKind;
}

class _ProviderPerformanceRecord {
  _ProviderPerformanceRecord();

  int successes = 0;
  int failures = 0;
  int resolutionSuccesses = 0;
  int resolutionFailures = 0;
  int consecutiveFailures = 0;
  double? resolutionEwmaMs;
  double? startupEwmaMs;
  DateTime? lastSuccessAt;
  DateTime? lastFailureAt;
  final Map<SourceFailureKind, int> failuresByKind = <SourceFailureKind, int>{};
  final Map<SourceFailureKind, int> resolutionFailuresByKind =
      <SourceFailureKind, int>{};

  factory _ProviderPerformanceRecord.fromJson(Map<Object?, Object?> json) {
    final record = _ProviderPerformanceRecord()
      ..successes = SourceHealthStore._readInt(json['successes']) ?? 0
      ..failures = SourceHealthStore._readInt(json['failures']) ?? 0
      ..resolutionSuccesses =
          SourceHealthStore._readInt(json['resolutionSuccesses']) ?? 0
      ..resolutionFailures =
          SourceHealthStore._readInt(json['resolutionFailures']) ?? 0
      ..consecutiveFailures =
          SourceHealthStore._readInt(json['consecutiveFailures']) ?? 0
      ..resolutionEwmaMs =
          SourceHealthStore._readDouble(json['resolutionEwmaMs'])
      ..startupEwmaMs = SourceHealthStore._readDouble(json['startupEwmaMs'])
      ..lastSuccessAt = DateTime.tryParse('${json['lastSuccessAt'] ?? ''}')
      ..lastFailureAt = DateTime.tryParse('${json['lastFailureAt'] ?? ''}');
    _readFailureMap(json['failuresByKind'], record.failuresByKind);
    _readFailureMap(
      json['resolutionFailuresByKind'],
      record.resolutionFailuresByKind,
    );
    return record;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'successes': successes,
        'failures': failures,
        'resolutionSuccesses': resolutionSuccesses,
        'resolutionFailures': resolutionFailures,
        'consecutiveFailures': consecutiveFailures,
        if (resolutionEwmaMs != null) 'resolutionEwmaMs': resolutionEwmaMs,
        if (startupEwmaMs != null) 'startupEwmaMs': startupEwmaMs,
        if (lastSuccessAt != null)
          'lastSuccessAt': lastSuccessAt!.toUtc().toIso8601String(),
        if (lastFailureAt != null)
          'lastFailureAt': lastFailureAt!.toUtc().toIso8601String(),
        'failuresByKind': <String, int>{
          for (final entry in failuresByKind.entries)
            entry.key.name: entry.value,
        },
        'resolutionFailuresByKind': <String, int>{
          for (final entry in resolutionFailuresByKind.entries)
            entry.key.name: entry.value,
        },
      };

  static void _readFailureMap(
    Object? raw,
    Map<SourceFailureKind, int> output,
  ) {
    if (raw is! Map) return;
    for (final entry in raw.entries) {
      final kind = SourceFailureKind.values
          .where((value) => value.name == '${entry.key}')
          .firstOrNull;
      final count = SourceHealthStore._readInt(entry.value);
      if (kind != null && count != null && count > 0) output[kind] = count;
    }
  }
}
