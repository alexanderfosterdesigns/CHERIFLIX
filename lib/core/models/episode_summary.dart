import '../services/tmdb_image_service.dart';
import '../utils/release_date_utils.dart';

class EpisodeSummary {
  const EpisodeSummary({
    required this.seasonNumber,
    required this.episodeNumber,
    required this.title,
    this.tmdbEpisodeId,
    this.overview,
    this.stillPath,
    this.runtimeMinutes,
    this.airDate,
  });

  final int seasonNumber;
  final int episodeNumber;
  final String title;
  final int? tmdbEpisodeId;
  final String? overview;
  final String? stillPath;
  final int? runtimeMinutes;
  final DateTime? airDate;

  bool get isUpcoming => isFutureRelease(airDate);

  factory EpisodeSummary.fromTmdbJson(
    Map<String, dynamic> json, {
    required int seasonNumber,
    int? fallbackRuntimeMinutes,
  }) {
    final rawRuntime = json['runtime'] as num?;
    final airDateRaw = json['air_date'] as String?;
    return EpisodeSummary(
      seasonNumber: seasonNumber,
      episodeNumber: (json['episode_number'] as num?)?.toInt() ?? 0,
      title: (json['name'] ?? 'Episode') as String,
      tmdbEpisodeId: (json['id'] as num?)?.toInt(),
      overview: json['overview'] as String?,
      stillPath: json['still_path'] as String?,
      runtimeMinutes: rawRuntime?.toInt() ?? fallbackRuntimeMinutes,
      airDate: airDateRaw == null || airDateRaw.isEmpty
          ? null
          : DateTime.tryParse(airDateRaw),
    );
  }

  String? get stillUrl => TmdbImageService.directUrlForPath(
        stillPath,
        TmdbImagePreset.episodeStill,
      );

  String get runtimeLabel {
    final minutes = runtimeMinutes;
    if (minutes == null || minutes <= 0) {
      return '--m';
    }
    return '${minutes}m';
  }
}
