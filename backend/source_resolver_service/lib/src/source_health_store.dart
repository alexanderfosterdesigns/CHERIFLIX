import 'dart:convert';
import 'dart:math' as math;

import 'source_resolver_models.dart';

class SourceHealthStore {
  SourceHealthStore({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<_SourceHealthKey, _SourceHealthRecord> _records =
      <_SourceHealthKey, _SourceHealthRecord>{};

  void recordSuccess({
    required SourceRequestKey key,
    required int providerIndex,
  }) {
    _records.remove(
      _SourceHealthKey(
        key: key,
        providerIndex: providerIndex,
      ),
    );
  }

  void recordFailure({
    required SourceRequestKey key,
    required int providerIndex,
    required String kind,
  }) {
    final healthKey = _SourceHealthKey(
      key: key,
      providerIndex: providerIndex,
    );
    final now = _clock();
    final record = _records.putIfAbsent(healthKey, _SourceHealthRecord.new);
    record.failureStreak += 1;
    record.lastFailureAt = now;
    record.lastFailureKind = kind;
    record.cooldownUntil = now.add(_cooldownFor(kind, record.failureStreak));
  }

  Duration? cooldownRemaining({
    required SourceRequestKey key,
    required int providerIndex,
  }) {
    final healthKey = _SourceHealthKey(
      key: key,
      providerIndex: providerIndex,
    );
    final record = _records[healthKey];
    if (record == null || record.cooldownUntil == null) {
      return null;
    }

    final remaining = record.cooldownUntil!.difference(_clock());
    if (remaining.isNegative || remaining == Duration.zero) {
      _records.remove(healthKey);
      return null;
    }

    return remaining;
  }

  Duration _cooldownFor(String kind, int failureStreak) {
    final baseSeconds = switch (kind) {
      SourceFailureKind.probe => 15,
      SourceFailureKind.load => 30,
      SourceFailureKind.blockedNavigation => 45,
      SourceFailureKind.sourceRejected => 90,
      SourceFailureKind.manualSwitch => 30,
      _ => 30,
    };
    final exponent = failureStreak <= 1
        ? 0
        : failureStreak <= 2
            ? 1
            : failureStreak <= 3
                ? 2
                : 3;
    final multiplier = 1 << exponent;
    final cooldownSeconds = math.min(baseSeconds * multiplier, 300).toInt();
    return Duration(seconds: cooldownSeconds);
  }
}

class SourcePreferenceStore {
  final Map<SourceRequestKey, int> _values = <SourceRequestKey, int>{};

  int? getLastGoodProviderIndex(SourceRequestKey key) {
    return _values[key];
  }

  void saveLastGoodProviderIndex({
    required SourceRequestKey key,
    required int providerIndex,
  }) {
    _values[key] = providerIndex;
  }
}

class SourceTargetCache {
  SourceTargetCache({
    DateTime Function()? clock,
    this.ttl = const Duration(minutes: 2),
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Duration ttl;
  final Map<String, _SourceTargetCacheEntry> _entries =
      <String, _SourceTargetCacheEntry>{};

  PlaybackTarget? read({
    required SourceRequestKey key,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
  }) {
    final cacheKey = _cacheKey(
      key: key,
      providerConfig: providerConfig,
      settings: settings,
    );
    final entry = _entries[cacheKey];
    if (entry == null) {
      return null;
    }

    final now = _clock();
    final expiresAtEpochMs = entry.target.expiresAtEpochMs;
    if (expiresAtEpochMs != null &&
        now.isAfter(
          DateTime.fromMillisecondsSinceEpoch(
            expiresAtEpochMs,
            isUtc: true,
          ),
        )) {
      _entries.remove(cacheKey);
      return null;
    }

    if (expiresAtEpochMs == null && now.difference(entry.cachedAt) > ttl) {
      _entries.remove(cacheKey);
      return null;
    }

    return entry.target;
  }

  void remember({
    required SourceRequestKey key,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    required PlaybackTarget target,
  }) {
    final cacheKey = _cacheKey(
      key: key,
      providerConfig: providerConfig,
      settings: settings,
    );
    _entries[cacheKey] = _SourceTargetCacheEntry(
      target: target,
      cachedAt: _clock(),
    );
  }

  void invalidate({
    required SourceRequestKey key,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
    required int providerIndex,
  }) {
    final cacheKey = _cacheKey(
      key: key,
      providerConfig: providerConfig,
      settings: settings,
    );
    final entry = _entries[cacheKey];
    if (entry == null || entry.target.providerIndex != providerIndex) {
      return;
    }
    _entries.remove(cacheKey);
  }

  String _cacheKey({
    required SourceRequestKey key,
    required ProviderConfig providerConfig,
    required ProfilePlaybackSettings settings,
  }) {
    return jsonEncode(<String, dynamic>{
      'request': <String, dynamic>{
        'profileId': key.profileId,
        'tmdbId': key.tmdbId,
        'mediaType': key.mediaType,
        'seasonNumber': key.seasonNumber,
        'episodeNumber': key.episodeNumber,
      },
      'providerConfig': providerConfig.toJson(),
      'settings': settings.toJson(),
    });
  }
}

class _SourceHealthKey {
  const _SourceHealthKey({
    required this.key,
    required this.providerIndex,
  });

  final SourceRequestKey key;
  final int providerIndex;

  @override
  bool operator ==(Object other) {
    return other is _SourceHealthKey &&
        other.key == key &&
        other.providerIndex == providerIndex;
  }

  @override
  int get hashCode => Object.hash(key, providerIndex);
}

class _SourceHealthRecord {
  int failureStreak = 0;
  DateTime? cooldownUntil;
  DateTime? lastFailureAt;
  String? lastFailureKind;
}

class _SourceTargetCacheEntry {
  _SourceTargetCacheEntry({
    required this.target,
    required this.cachedAt,
  });

  final PlaybackTarget target;
  final DateTime cachedAt;
}
