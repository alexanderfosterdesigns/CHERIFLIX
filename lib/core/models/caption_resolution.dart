import 'caption_track.dart';

class CaptionFailureCode {
  static const String missingApiKey = 'missing_api_key';
  static const String noMatch = 'no_match';
  static const String prepareFailed = 'prepare_failed';
  static const String serviceError = 'service_error';
}

class CaptionResolution {
  const CaptionResolution({
    this.tracks = const <CaptionTrack>[],
    this.selectedTrackId,
    this.failureCode,
  });

  final List<CaptionTrack> tracks;
  final String? selectedTrackId;
  final String? failureCode;

  static const CaptionResolution empty = CaptionResolution();

  CaptionResolution copyWith({
    List<CaptionTrack>? tracks,
    String? selectedTrackId,
    String? failureCode,
  }) {
    return CaptionResolution(
      tracks: tracks ?? this.tracks,
      selectedTrackId: selectedTrackId ?? this.selectedTrackId,
      failureCode: failureCode ?? this.failureCode,
    );
  }

  factory CaptionResolution.fromJson(Map<String, dynamic> json) {
    return CaptionResolution(
      tracks: (json['tracks'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(CaptionTrack.fromJson)
          .toList(growable: false),
      selectedTrackId: json['selectedTrackId'] as String? ??
          json['selected_track_id'] as String?,
      failureCode:
          json['failureCode'] as String? ?? json['failure_code'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'tracks': tracks.map((track) => track.toJson()).toList(growable: false),
      'selectedTrackId': selectedTrackId,
      'failureCode': failureCode,
    };
  }
}
