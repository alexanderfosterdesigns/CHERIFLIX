import 'media_summary.dart';

enum SeasonReleaseState { upcoming, currentlyAiring, recentlyStarted }

class UpcomingSeasonEntry {
  const UpcomingSeasonEntry({
    required this.summary,
    required this.seasonNumber,
    required this.premiereDate,
    required this.state,
  });

  final MediaSummary summary;
  final int seasonNumber;
  final DateTime premiereDate;
  final SeasonReleaseState state;

  factory UpcomingSeasonEntry.fromJson(Map<String, dynamic> json) {
    return UpcomingSeasonEntry(
      summary: MediaSummary.fromJson(json['summary'] as Map<String, dynamic>),
      seasonNumber: (json['season_number'] as num).toInt(),
      premiereDate: DateTime.parse(json['premiere_date'] as String),
      state: SeasonReleaseState.values.firstWhere(
        (value) => value.name == json['state'],
        orElse: () => SeasonReleaseState.upcoming,
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'summary': summary.toJson(),
        'season_number': seasonNumber,
        'premiere_date': premiereDate.toIso8601String(),
        'state': state.name,
      };
}

class UpcomingCatalog {
  const UpcomingCatalog({
    required this.movies,
    required this.series,
    required this.seasons,
  });

  final List<MediaSummary> movies;
  final List<MediaSummary> series;
  final List<UpcomingSeasonEntry> seasons;

  List<MediaSummary> get mixed {
    final result = <MediaSummary>[...movies, ...series]
      ..sort((a, b) => a.releaseDate!.compareTo(b.releaseDate!));
    return result;
  }

  factory UpcomingCatalog.fromJson(Map<String, dynamic> json) {
    List<MediaSummary> summaries(String key) =>
        (json[key] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(MediaSummary.fromJson)
            .toList(growable: false);
    return UpcomingCatalog(
      movies: summaries('movies'),
      series: summaries('series'),
      seasons: (json['seasons'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(UpcomingSeasonEntry.fromJson)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'movies': movies.map((item) => item.toJson()).toList(),
        'series': series.map((item) => item.toJson()).toList(),
        'seasons': seasons.map((item) => item.toJson()).toList(),
      };
}
