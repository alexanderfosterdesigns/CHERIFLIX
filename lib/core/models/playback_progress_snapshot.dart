import 'media_summary.dart';
import 'playback_progress_entry.dart';

class PlaybackProgressSnapshot {
  PlaybackProgressSnapshot(Iterable<PlaybackProgressEntry> entries)
      : entries = List<PlaybackProgressEntry>.unmodifiable(entries);

  PlaybackProgressSnapshot.empty() : entries = const <PlaybackProgressEntry>[];

  final List<PlaybackProgressEntry> entries;

  late final Map<String, PlaybackProgressEntry> byEntryKey =
      <String, PlaybackProgressEntry>{
    for (final entry in entries) entry.entryKey: entry,
  };

  late final Map<String, List<PlaybackProgressEntry>> byTitleKey =
      <String, List<PlaybackProgressEntry>>{
    for (final titleKey in _orderedTitleKeys)
      titleKey: List<PlaybackProgressEntry>.unmodifiable(
        entries.where((entry) => entry.saveKey == titleKey),
      ),
  };

  late final Map<String, PlaybackProgressEntry> latestByTitleKey =
      _firstMatchingByTitle((entry) => entry.hasStarted || entry.isCompleted);

  late final Map<String, PlaybackProgressEntry> latestResumeByTitleKey =
      _firstMatchingByTitle((entry) => entry.isInProgress);

  late final Map<String, PlaybackProgressEntry> latestCompletedByTitleKey =
      _firstMatchingByTitle((entry) => entry.isCompleted);

  late final Map<String, PlaybackProgressEntry> preferredByTitleKey =
      <String, PlaybackProgressEntry>{
    for (final titleKey in _orderedTitleKeys)
      if (latestResumeByTitleKey[titleKey] != null ||
          latestCompletedByTitleKey[titleKey] != null ||
          latestByTitleKey[titleKey] != null)
        titleKey: latestResumeByTitleKey[titleKey] ??
            latestCompletedByTitleKey[titleKey] ??
            latestByTitleKey[titleKey]!,
  };

  late final List<PlaybackProgressEntry> continueWatchingEntries =
      List<PlaybackProgressEntry>.unmodifiable(
    latestResumeByTitleKey.values.toList(growable: false),
  );

  late final List<PlaybackProgressEntry> alreadyWatchedEntries =
      List<PlaybackProgressEntry>.unmodifiable(
    _orderedTitleKeys
        .where((titleKey) => !latestResumeByTitleKey.containsKey(titleKey))
        .map((titleKey) => latestCompletedByTitleKey[titleKey])
        .whereType<PlaybackProgressEntry>()
        .toList(growable: false),
  );

  PlaybackProgressEntry? latestForTitle(MediaSummary summary) =>
      latestByTitleKey[summary.saveKey];

  PlaybackProgressEntry? preferredForTitle(MediaSummary summary) =>
      preferredByTitleKey[summary.saveKey];

  PlaybackProgressEntry? latestResumeForTitle(MediaSummary summary) =>
      latestResumeByTitleKey[summary.saveKey];

  PlaybackProgressEntry? entryForTarget({
    required MediaSummary summary,
    int? seasonNumber,
    int? episodeNumber,
  }) {
    final season = seasonNumber ?? 0;
    final episode = episodeNumber ?? 0;
    return byEntryKey['${summary.saveKey}:$season:$episode'];
  }

  Map<String, PlaybackProgressEntry> episodeProgressByCodeForTitle(
    MediaSummary summary,
  ) {
    final entriesForTitle = byTitleKey[summary.saveKey];
    if (entriesForTitle == null || entriesForTitle.isEmpty) {
      return const <String, PlaybackProgressEntry>{};
    }

    final result = <String, PlaybackProgressEntry>{};
    for (final entry in entriesForTitle) {
      final season = entry.seasonNumber;
      final episode = entry.episodeNumber;
      if (season == null || episode == null) {
        continue;
      }
      result['$season:$episode'] = entry;
    }
    return result;
  }

  List<String> get _orderedTitleKeys {
    final seen = <String>{};
    final keys = <String>[];
    for (final entry in entries) {
      if (seen.add(entry.saveKey)) {
        keys.add(entry.saveKey);
      }
    }
    return keys;
  }

  Map<String, PlaybackProgressEntry> _firstMatchingByTitle(
    bool Function(PlaybackProgressEntry entry) predicate,
  ) {
    final result = <String, PlaybackProgressEntry>{};
    for (final entry in entries) {
      if (!predicate(entry) || result.containsKey(entry.saveKey)) {
        continue;
      }
      result[entry.saveKey] = entry;
    }
    return result;
  }
}
