import '../services/tmdb_image_service.dart';

class TmdbTitleLogo {
  const TmdbTitleLogo({
    required this.filePath,
    required this.width,
    required this.height,
    this.languageCode,
    this.voteAverage = 0,
    this.voteCount = 0,
  });

  final String filePath;
  final int width;
  final int height;
  final String? languageCode;
  final double voteAverage;
  final int voteCount;

  String? get imageUrl => TmdbImageService.directUrlForPath(
        filePath,
        TmdbImagePreset.titleLogo,
      );

  factory TmdbTitleLogo.fromJson(Map<String, dynamic> json) {
    return TmdbTitleLogo(
      filePath: json['file_path'] as String? ?? '',
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      languageCode: json['iso_639_1'] as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0,
      voteCount: (json['vote_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'file_path': filePath,
        'width': width,
        'height': height,
        'iso_639_1': languageCode,
        'vote_average': voteAverage,
        'vote_count': voteCount,
      };
}
