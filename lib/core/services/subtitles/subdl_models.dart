class SubdlSubtitle {
  const SubdlSubtitle({
    required this.id,
    required this.language,
    required this.releaseName,
    required this.author,
    required this.hi,
    required this.url,
    required this.rating,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeFrom,
    this.episodeEnd,
    this.fullSeason = false,
  });

  final String id;
  final String language;
  final String releaseName;
  final String author;
  final bool hi;
  final String url;
  final double rating;
  final int? seasonNumber;
  final int? episodeNumber;
  final int? episodeFrom;
  final int? episodeEnd;
  final bool fullSeason;

  factory SubdlSubtitle.fromJson(Map<String, dynamic> json) {
    final subtitleIdRaw = json['subtitle_id'] ?? json['id'] ?? '';
    final language = '${json['language'] ?? json['lang'] ?? 'EN'}'.trim();
    final releaseName =
        '${json['release_name'] ?? json['release'] ?? ''}'.trim();
    final author = '${json['author'] ?? json['uploader'] ?? ''}'.trim();
    final hiValue = json['hi'] ?? json['hearing_impaired'] ?? false;
    final ratingValue = json['rating'] as num?;
    final url = '${json['url'] ?? ''}'.trim();
    final seasonNumber = _asInt(json['season'] ?? json['season_number']);
    final episodeNumber = _asInt(json['episode'] ?? json['episode_number']);
    final episodeFrom = _asInt(json['episode_from']);
    final episodeEnd = _asInt(json['episode_end']);
    final fullSeasonValue = json['full_season'] ?? false;
    final releaseEpisode = _extractSeasonEpisodeFromRelease(releaseName);
    final parsedIdFromUrl = _extractIdFromUrl(url);
    final subtitleId = '$subtitleIdRaw'.trim().isNotEmpty
        ? '$subtitleIdRaw'.trim()
        : parsedIdFromUrl.isNotEmpty
            ? parsedIdFromUrl
            : _fallbackIdFromUrl(url);
    return SubdlSubtitle(
      id: subtitleId,
      language: language.isEmpty ? 'EN' : language,
      releaseName: releaseName,
      author: author,
      hi: hiValue == true || '$hiValue'.trim() == '1',
      url: url,
      rating: ratingValue?.toDouble() ?? 0,
      seasonNumber: seasonNumber ?? releaseEpisode.$1,
      episodeNumber: episodeNumber ?? releaseEpisode.$2,
      episodeFrom: episodeFrom,
      episodeEnd: episodeEnd,
      fullSeason: fullSeasonValue == true || '$fullSeasonValue'.trim() == '1',
    );
  }

  bool get hasDownloadReference =>
      resolveDownloadUri() != null || id.trim().isNotEmpty;

  Uri? resolveDownloadUri() {
    if (url.trim().isNotEmpty) {
      final parsed = Uri.tryParse(url.trim());
      if (parsed != null) {
        if (parsed.hasScheme) {
          return parsed;
        }
        final normalizedPath =
            parsed.path.startsWith('/') ? parsed.path : '/${parsed.path}';
        return Uri.parse('https://dl.subdl.com$normalizedPath');
      }
      final normalizedPath = url.startsWith('/') ? url : '/$url';
      return Uri.parse('https://dl.subdl.com$normalizedPath');
    }
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) {
      return null;
    }
    return Uri.parse('https://dl.subdl.com/subtitle/$normalizedId.zip');
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'subtitle_id': id,
      'language': language,
      'release_name': releaseName,
      'author': author,
      'hi': hi,
      'url': url,
      'rating': rating,
      'season': seasonNumber,
      'episode': episodeNumber,
      'episode_from': episodeFrom,
      'episode_end': episodeEnd,
      'full_season': fullSeason,
    };
  }

  bool matchesEpisode({
    required int seasonNumber,
    required int episodeNumber,
  }) {
    if (this.seasonNumber != null && this.seasonNumber != seasonNumber) {
      return false;
    }
    if (this.episodeNumber != null && this.episodeNumber == episodeNumber) {
      return true;
    }
    if (episodeFrom != null && episodeEnd != null) {
      return episodeNumber >= episodeFrom! && episodeNumber <= episodeEnd!;
    }
    if (episodeFrom != null && episodeEnd == null) {
      return episodeNumber == episodeFrom;
    }
    if (episodeEnd != null && episodeFrom == null) {
      return episodeNumber == episodeEnd;
    }
    return fullSeason && this.seasonNumber == seasonNumber;
  }

  static String _extractIdFromUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final parsed = Uri.tryParse(trimmed);
    final candidate = parsed?.pathSegments.isNotEmpty == true
        ? parsed!.pathSegments.last
        : trimmed.split('/').last;
    final withoutZip =
        candidate.toLowerCase().endsWith('.zip') && candidate.length > 4
            ? candidate.substring(0, candidate.length - 4)
            : candidate;
    return withoutZip.trim();
  }

  static String _fallbackIdFromUrl(String rawUrl) {
    final normalized = rawUrl.trim().toLowerCase();
    if (normalized.isEmpty) {
      return '';
    }
    var hash = 0x811c9dc5;
    for (final codeUnit in normalized.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return 'url_${hash.toRadixString(16)}';
  }

  static int? _asInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  static (int?, int?) _extractSeasonEpisodeFromRelease(String releaseName) {
    if (releaseName.trim().isEmpty) {
      return (null, null);
    }
    final normalized = releaseName.toLowerCase();
    final match = RegExp(r's(\d{1,2})e(\d{1,3})').firstMatch(normalized);
    if (match == null) {
      return (null, null);
    }
    return (
      int.tryParse(match.group(1)!),
      int.tryParse(match.group(2)!),
    );
  }
}

class SubtitleTrack {
  const SubtitleTrack({
    required this.languageCode,
    required this.label,
    required this.uri,
    required this.isHI,
  });

  final String languageCode;
  final String label;
  final Uri uri;
  final bool isHI;
}
