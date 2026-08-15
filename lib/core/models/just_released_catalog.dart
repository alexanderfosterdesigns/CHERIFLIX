import 'media_summary.dart';

class JustReleasedCatalog {
  const JustReleasedCatalog({
    required this.recentReleases,
    required this.topRatedRecent,
    required this.newThrillers,
    required this.newRomance,
    required this.newDrama,
    required this.justHitStreaming,
  });

  final List<MediaSummary> recentReleases;
  final List<MediaSummary> topRatedRecent;
  final List<MediaSummary> newThrillers;
  final List<MediaSummary> newRomance;
  final List<MediaSummary> newDrama;
  final List<MediaSummary> justHitStreaming;

  factory JustReleasedCatalog.fromJson(Map<String, dynamic> json) {
    return JustReleasedCatalog(
      recentReleases: _decodeList(json['recent_releases'] as List<dynamic>?),
      topRatedRecent: _decodeList(json['top_rated_recent'] as List<dynamic>?),
      newThrillers: _decodeList(json['new_thrillers'] as List<dynamic>?),
      newRomance: _decodeList(json['new_romance'] as List<dynamic>?),
      newDrama: _decodeList(json['new_drama'] as List<dynamic>?),
      justHitStreaming:
          _decodeList(json['just_hit_streaming'] as List<dynamic>?),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'recent_releases':
          recentReleases.map((item) => item.toJson()).toList(growable: false),
      'top_rated_recent':
          topRatedRecent.map((item) => item.toJson()).toList(growable: false),
      'new_thrillers':
          newThrillers.map((item) => item.toJson()).toList(growable: false),
      'new_romance':
          newRomance.map((item) => item.toJson()).toList(growable: false),
      'new_drama':
          newDrama.map((item) => item.toJson()).toList(growable: false),
      'just_hit_streaming':
          justHitStreaming.map((item) => item.toJson()).toList(growable: false),
    };
  }

  static List<MediaSummary> _decodeList(List<dynamic>? items) {
    return (items ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(MediaSummary.fromJson)
        .toList(growable: false);
  }
}
