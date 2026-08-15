import '../services/tmdb_image_service.dart';
import 'media_summary.dart';

class TitleMetadata {
  const TitleMetadata({
    required this.summary,
    this.certification,
    this.tagline,
    this.status,
    this.originalTitle,
    this.originalLanguage,
    this.homepage,
    this.genres = const <String>[],
    this.studios = const <String>[],
    this.networks = const <String>[],
    this.spokenLanguages = const <String>[],
    this.originCountries = const <String>[],
    this.creators = const <String>[],
    this.writers = const <String>[],
    this.cast = const <TitleCredit>[],
    this.crew = const <TitleCredit>[],
  });

  final MediaSummary summary;
  final String? certification;
  final String? tagline;
  final String? status;
  final String? originalTitle;
  final String? originalLanguage;
  final String? homepage;
  final List<String> genres;
  final List<String> studios;
  final List<String> networks;
  final List<String> spokenLanguages;
  final List<String> originCountries;
  final List<String> creators;
  final List<String> writers;
  final List<TitleCredit> cast;
  final List<TitleCredit> crew;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'summary': summary.toJson(),
      'certification': certification,
      'tagline': tagline,
      'status': status,
      'original_title': originalTitle,
      'original_language': originalLanguage,
      'homepage': homepage,
      'genres': genres,
      'studios': studios,
      'networks': networks,
      'spoken_languages': spokenLanguages,
      'origin_countries': originCountries,
      'creators': creators,
      'writers': writers,
      'cast': cast.map((item) => item.toJson()).toList(growable: false),
      'crew': crew.map((item) => item.toJson()).toList(growable: false),
    };
  }

  factory TitleMetadata.fromJson(Map<String, dynamic> json) {
    return TitleMetadata(
      summary: MediaSummary.fromJson(json['summary'] as Map<String, dynamic>),
      certification: json['certification'] as String?,
      tagline: json['tagline'] as String?,
      status: json['status'] as String?,
      originalTitle: json['original_title'] as String?,
      originalLanguage: json['original_language'] as String?,
      homepage: json['homepage'] as String?,
      genres: (json['genres'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
      studios: (json['studios'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
      networks: (json['networks'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
      spokenLanguages:
          (json['spoken_languages'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<String>()
              .toList(growable: false),
      originCountries:
          (json['origin_countries'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<String>()
              .toList(growable: false),
      creators: (json['creators'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
      writers: (json['writers'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
      cast: (json['cast'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(TitleCredit.fromJson)
          .toList(growable: false),
      crew: (json['crew'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(TitleCredit.fromJson)
          .toList(growable: false),
    );
  }
}

class TitleCredit {
  const TitleCredit({
    required this.name,
    required this.role,
    this.profilePath,
    this.department,
  });

  final String name;
  final String role;
  final String? profilePath;
  final String? department;

  String? get profileUrl => TmdbImageService.directUrlForPath(
        profilePath,
        TmdbImagePreset.castProfile,
      );

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'role': role,
      'profile_path': profilePath,
      'department': department,
    };
  }

  factory TitleCredit.fromJson(Map<String, dynamic> json) {
    return TitleCredit(
      name: json['name'] as String? ?? 'Unknown',
      role: json['role'] as String? ?? '',
      profilePath: json['profile_path'] as String?,
      department: json['department'] as String?,
    );
  }
}
