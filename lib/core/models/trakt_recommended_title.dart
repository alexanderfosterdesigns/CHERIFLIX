import 'media_summary.dart';
import 'media_type.dart';

class TraktRecommendedTitle {
  const TraktRecommendedTitle({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.overview,
    this.rating,
    this.releaseDate,
    this.genreNames = const <String>[],
    this.runtimeMinutes,
  });

  final int tmdbId;
  final MediaType mediaType;
  final String title;
  final String? overview;
  final double? rating;
  final DateTime? releaseDate;
  final List<String> genreNames;
  final int? runtimeMinutes;

  MediaSummary toMediaSummary() {
    return MediaSummary(
      tmdbId: tmdbId,
      mediaType: mediaType,
      title: title,
      overview: overview,
      rating: rating,
      releaseDate: releaseDate,
      genreNames: genreNames,
      runtimeMinutes: runtimeMinutes,
    );
  }
}
