enum CaptionTrackKind {
  manual,
  auto,
}

enum CaptionTrackFormat {
  vtt,
}

class CaptionRequestKey {
  const CaptionRequestKey({
    required this.tmdbId,
    required this.mediaType,
    required this.languageCode,
    this.seasonNumber,
    this.episodeNumber,
  });

  final int tmdbId;
  final String mediaType;
  final String languageCode;
  final int? seasonNumber;
  final int? episodeNumber;

  String get cacheKey => [
        mediaType,
        '$tmdbId',
        if (seasonNumber != null) 's$seasonNumber',
        if (episodeNumber != null) 'e$episodeNumber',
        languageCode,
      ].join('_');
}

class CaptionTrackRecord {
  const CaptionTrackRecord({
    required this.id,
    required this.label,
    required this.languageCode,
    required this.kind,
    required this.format,
    required this.url,
    this.isDefault = false,
  });

  final String id;
  final String label;
  final String languageCode;
  final CaptionTrackKind kind;
  final CaptionTrackFormat format;
  final Uri url;
  final bool isDefault;

  CaptionTrackRecord copyWith({
    String? id,
    String? label,
    String? languageCode,
    CaptionTrackKind? kind,
    CaptionTrackFormat? format,
    Uri? url,
    bool? isDefault,
  }) {
    return CaptionTrackRecord(
      id: id ?? this.id,
      label: label ?? this.label,
      languageCode: languageCode ?? this.languageCode,
      kind: kind ?? this.kind,
      format: format ?? this.format,
      url: url ?? this.url,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  factory CaptionTrackRecord.fromJson(Map<String, dynamic> json) {
    return CaptionTrackRecord(
      id: json['id'] as String,
      label: json['label'] as String,
      languageCode: json['languageCode'] as String? ??
          json['language_code'] as String? ??
          'en',
      kind: CaptionTrackKind.values.firstWhere(
        (value) => value.name == (json['kind'] as String? ?? 'auto'),
        orElse: () => CaptionTrackKind.auto,
      ),
      format: CaptionTrackFormat.values.firstWhere(
        (value) => value.name == (json['format'] as String? ?? 'vtt'),
        orElse: () => CaptionTrackFormat.vtt,
      ),
      url: Uri.parse(json['url'] as String),
      isDefault: json['isDefault'] as bool? ?? json['is_default'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'languageCode': languageCode,
      'kind': kind.name,
      'format': format.name,
      'url': url.toString(),
      'isDefault': isDefault,
    };
  }
}

class CaptionResolutionPayload {
  const CaptionResolutionPayload({
    this.tracks = const <CaptionTrackRecord>[],
    this.selectedTrackId,
  });

  final List<CaptionTrackRecord> tracks;
  final String? selectedTrackId;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'tracks': tracks.map((track) => track.toJson()).toList(growable: false),
      'selectedTrackId': selectedTrackId,
    };
  }
}
