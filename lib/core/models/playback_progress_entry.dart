import '../services/tmdb_image_service.dart';
import 'media_summary.dart';

class PlaybackProgressEntry {
  const PlaybackProgressEntry({
    required this.summary,
    required this.position,
    required this.totalDuration,
    required this.updatedAt,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeTitle,
    this.episodeStillPath,
  });

  final MediaSummary summary;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeTitle;
  final String? episodeStillPath;
  final Duration position;
  final Duration totalDuration;
  final DateTime updatedAt;

  String get saveKey => summary.saveKey;

  String get entryKey {
    final season = seasonNumber ?? 0;
    final episode = episodeNumber ?? 0;
    return '${summary.saveKey}:$season:$episode';
  }

  bool get isEpisode =>
      summary.mediaType.name == 'tv' &&
      seasonNumber != null &&
      episodeNumber != null;

  String? get episodeLabel {
    final season = seasonNumber;
    final episode = episodeNumber;
    if (season == null || episode == null) {
      return null;
    }
    return 'S$season:E$episode';
  }

  bool get hasStarted => position >= const Duration(seconds: 30);

  bool get isCompleted {
    final durationMillis = totalDuration.inMilliseconds;
    if (durationMillis <= 0) {
      return false;
    }

    final remainingMillis = durationMillis - position.inMilliseconds;
    return remainingMillis <= const Duration(minutes: 2).inMilliseconds ||
        position.inMilliseconds / durationMillis >= 0.95;
  }

  bool get isInProgress => hasStarted && !isCompleted;

  double get progressFraction {
    final durationMillis = totalDuration.inMilliseconds;
    if (durationMillis <= 0) {
      return 0;
    }
    return (position.inMilliseconds / durationMillis).clamp(0.0, 1.0);
  }

  String get displayTitle {
    if (!isEpisode) {
      return summary.title;
    }
    final title = episodeTitle?.trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }
    return episodeLabel ?? summary.title;
  }

  String get displaySubtitle {
    final remaining = _remainingLabel;
    if (!isEpisode) {
      return <String>[
        summary.metadataLabel,
        if (remaining != null) remaining,
      ].join('  •  ');
    }

    final label = episodeLabel;
    final episodeContext = label == null ? summary.title : '$label  ${summary.title}';
    return <String>[
      episodeContext,
      if (remaining != null) remaining,
    ].join('  •  ');
  }

  String? get _remainingLabel {
    if (totalDuration <= Duration.zero || position >= totalDuration) {
      return null;
    }
    final remainingMinutes =
        ((totalDuration - position).inSeconds / 60).ceil().clamp(1, 9999);
    return '${remainingMinutes}m left';
  }

  String? get artworkPath {
    final stillPath = episodeStillPath?.trim();
    if (stillPath != null && stillPath.isNotEmpty) {
      return stillPath;
    }
    return summary.posterPath ?? summary.backdropPath;
  }

  String? get artworkUrl {
    final path = artworkPath;
    if (path == null || path.isEmpty) {
      return null;
    }
    return TmdbImageService.directUrlForPath(
      path,
      episodeStillPath != null && episodeStillPath!.trim().isNotEmpty
          ? TmdbImagePreset.episodeStill
          : TmdbImagePreset.smallPoster,
    );
  }

  Duration get resumePosition => isInProgress ? position : Duration.zero;

  PlaybackProgressEntry copyWith({
    MediaSummary? summary,
    int? seasonNumber,
    int? episodeNumber,
    String? episodeTitle,
    String? episodeStillPath,
    Duration? position,
    Duration? totalDuration,
    DateTime? updatedAt,
  }) {
    return PlaybackProgressEntry(
      summary: summary ?? this.summary,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      episodeStillPath: episodeStillPath ?? this.episodeStillPath,
      position: position ?? this.position,
      totalDuration: totalDuration ?? this.totalDuration,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
