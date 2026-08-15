import 'media_summary.dart';

class HomeCatalogData {
  const HomeCatalogData({
    required this.featured,
    required this.newOnStreaming,
    required this.trending,
    required this.popularMovies,
    required this.popularSeries,
    required this.newAndPopular,
  });

  final MediaSummary featured;
  final List<MediaSummary> newOnStreaming;
  final List<MediaSummary> trending;
  final List<MediaSummary> popularMovies;
  final List<MediaSummary> popularSeries;
  final List<MediaSummary> newAndPopular;

  factory HomeCatalogData.fromJson(Map<String, dynamic> json) {
    return HomeCatalogData(
      featured: MediaSummary.fromJson(json['featured'] as Map<String, dynamic>),
      newOnStreaming: _decodeList(json['new_on_streaming'] as List<dynamic>?),
      trending: _decodeList(json['trending'] as List<dynamic>?),
      popularMovies: _decodeList(json['popular_movies'] as List<dynamic>?),
      popularSeries: _decodeList(json['popular_series'] as List<dynamic>?),
      newAndPopular: _decodeList(json['new_and_popular'] as List<dynamic>?),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'featured': featured.toJson(),
      'new_on_streaming': newOnStreaming.map((item) => item.toJson()).toList(),
      'trending': trending.map((item) => item.toJson()).toList(),
      'popular_movies': popularMovies.map((item) => item.toJson()).toList(),
      'popular_series': popularSeries.map((item) => item.toJson()).toList(),
      'new_and_popular': newAndPopular.map((item) => item.toJson()).toList(),
    };
  }

  static List<MediaSummary> _decodeList(List<dynamic>? items) {
    return (items ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(MediaSummary.fromJson)
        .toList();
  }
}
