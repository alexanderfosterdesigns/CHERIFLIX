enum CaptionTrackKind {
  manual,
  auto,
  override,
}

enum CaptionTrackFormat {
  vtt,
}

class CaptionTrack {
  const CaptionTrack({
    required this.id,
    required this.label,
    required this.languageCode,
    required this.kind,
    required this.format,
    required this.url,
    this.isDefault = false,
    this.isHI = false,
  });

  final String id;
  final String label;
  final String languageCode;
  final CaptionTrackKind kind;
  final CaptionTrackFormat format;
  final Uri url;
  final bool isDefault;
  final bool isHI;

  CaptionTrack copyWith({
    String? id,
    String? label,
    String? languageCode,
    CaptionTrackKind? kind,
    CaptionTrackFormat? format,
    Uri? url,
    bool? isDefault,
    bool? isHI,
  }) {
    return CaptionTrack(
      id: id ?? this.id,
      label: label ?? this.label,
      languageCode: languageCode ?? this.languageCode,
      kind: kind ?? this.kind,
      format: format ?? this.format,
      url: url ?? this.url,
      isDefault: isDefault ?? this.isDefault,
      isHI: isHI ?? this.isHI,
    );
  }

  factory CaptionTrack.fromJson(Map<String, dynamic> json) {
    return CaptionTrack(
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
      isDefault:
          json['isDefault'] as bool? ?? json['is_default'] as bool? ?? false,
      isHI: json['isHI'] as bool? ?? json['is_hi'] as bool? ?? false,
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
      'isHI': isHI,
    };
  }
}
