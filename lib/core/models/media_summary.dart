import '../services/tmdb_image_service.dart';
import 'media_type.dart';
import '../utils/release_date_utils.dart';

class MediaSummary {
  const MediaSummary({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.rating,
    this.releaseDate,
    this.genreIds = const <int>[],
    this.genreNames = const <String>[],
    this.runtimeMinutes,
    this.seasonCount,
    this.collectionId,
    this.collectionName,
    this.originalLanguage,
  });

  final int tmdbId;
  final MediaType mediaType;
  final String title;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final double? rating;
  final DateTime? releaseDate;
  final List<int> genreIds;
  final List<String> genreNames;
  final int? runtimeMinutes;
  final int? seasonCount;
  final int? collectionId;
  final String? collectionName;
  final String? originalLanguage;

  bool get isUpcoming => isFutureRelease(releaseDate);

  factory MediaSummary.fromTmdbJson(Map<String, dynamic> json) {
    final mediaTypeValue = json['media_type'] as String? ??
        (json.containsKey('title') ? 'movie' : 'tv');
    final releaseDateRaw = json['release_date'] ?? json['first_air_date'];
    return MediaSummary(
      tmdbId: json['id'] as int,
      mediaType: mediaTypeValue == 'tv' ? MediaType.tv : MediaType.movie,
      title: (json['title'] ?? json['name'] ?? 'Untitled') as String,
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      rating: (json['vote_average'] as num?)?.toDouble(),
      releaseDate: releaseDateRaw is String && releaseDateRaw.isNotEmpty
          ? DateTime.tryParse(releaseDateRaw)
          : null,
      genreIds: _parseGenreIds(json),
      genreNames: (json['genres'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map((genre) => genre['name'] as String?)
          .whereType<String>()
          .where((genre) => genre.isNotEmpty)
          .toList(growable: false),
      runtimeMinutes: _parseRuntimeMinutes(json),
      seasonCount: (json['number_of_seasons'] as num?)?.toInt(),
      collectionId: (json['belongs_to_collection']
          as Map<String, dynamic>?)?['id'] as int?,
      collectionName: (json['belongs_to_collection']
          as Map<String, dynamic>?)?['name'] as String?,
      originalLanguage: json['original_language'] as String?,
    );
  }

  factory MediaSummary.fromJson(Map<String, dynamic> json) {
    return MediaSummary(
      tmdbId: json['tmdb_id'] as int,
      mediaType: (json['media_type'] as String) == 'tv'
          ? MediaType.tv
          : MediaType.movie,
      title: json['title'] as String,
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      releaseDate: json['release_date'] == null
          ? null
          : DateTime.tryParse(json['release_date'] as String),
      genreIds: (json['genre_ids'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<num>()
          .map((genreId) => genreId.toInt())
          .toList(growable: false),
      genreNames: (json['genre_names'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
      runtimeMinutes: (json['runtime_minutes'] as num?)?.toInt(),
      seasonCount: (json['season_count'] as num?)?.toInt(),
      collectionId: (json['collection_id'] as num?)?.toInt(),
      collectionName: json['collection_name'] as String?,
      originalLanguage: json['original_language'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'tmdb_id': tmdbId,
      'media_type': mediaType.name,
      'title': title,
      'overview': overview,
      'poster_path': posterPath,
      'backdrop_path': backdropPath,
      'rating': rating,
      'release_date': releaseDate?.toIso8601String(),
      'genre_ids': genreIds,
      'genre_names': genreNames,
      'runtime_minutes': runtimeMinutes,
      'season_count': seasonCount,
      'collection_id': collectionId,
      'collection_name': collectionName,
      'original_language': originalLanguage,
    };
  }

  String? get posterUrl => TmdbImageService.directUrlForPath(
        posterPath,
        TmdbImagePreset.smallPoster,
      );

  String? get backdropUrl => TmdbImageService.directUrlForPath(
        backdropPath,
        TmdbImagePreset.heroBackdrop,
      );

  String get badgeLabel {
    final year = releaseDate?.year;
    final score = rating?.toStringAsFixed(1);
    final parts = <String>[
      if (mediaType == MediaType.movie) 'Movie' else 'Series',
      if (year != null) '$year',
      if (score != null) score,
    ];
    return parts.join('  |  ');
  }

  String get mediaLabel => mediaType == MediaType.movie ? 'MOVIE' : 'TV SHOW';

  String get metadataLabel {
    final parts = <String>[
      mediaLabel,
      if (releaseDate?.year != null) '${releaseDate!.year}',
      if (rating != null) 'Rating ${rating!.toStringAsFixed(1)}',
    ];
    return parts.join('  ');
  }

  String get tmdbRatingLabel =>
      rating == null ? 'Rating' : 'Rating ${rating!.toStringAsFixed(1)}';

  String get saveKey => '${mediaType.name}:$tmdbId';

  String? get primaryGenre => genreNames.isEmpty ? null : genreNames.first;

  String get releaseYearLabel =>
      releaseDate == null ? 'N/A' : '${releaseDate!.year}';

  String? get runtimeLabel {
    final minutes = runtimeMinutes;
    if (minutes == null || minutes <= 0) {
      return null;
    }
    return '${minutes}m';
  }

  String? get seasonLabel {
    final count = seasonCount;
    if (count == null || count <= 0) {
      return null;
    }
    return count == 1 ? '1 Season' : '$count Seasons';
  }

  static int? _parseRuntimeMinutes(Map<String, dynamic> json) {
    final runtime = (json['runtime'] as num?)?.toInt();
    if (runtime != null && runtime > 0) {
      return runtime;
    }

    final episodeRunTime = json['episode_run_time'];
    if (episodeRunTime is List) {
      for (final value in episodeRunTime) {
        if (value is num && value > 0) {
          return value.toInt();
        }
      }
    }

    return null;
  }

  static List<int> _parseGenreIds(Map<String, dynamic> json) {
    final ids = <int>[];
    final detailedGenres = json['genres'];
    if (detailedGenres is List) {
      for (final genre in detailedGenres) {
        if (genre is Map<String, dynamic>) {
          final id = (genre['id'] as num?)?.toInt();
          if (id != null) {
            ids.add(id);
          }
        }
      }
    }

    final compactGenres = json['genre_ids'];
    if (compactGenres is List) {
      for (final genreId in compactGenres) {
        if (genreId is num) {
          ids.add(genreId.toInt());
        }
      }
    }

    return ids.toSet().toList(growable: false);
  }
}
