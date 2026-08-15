import '../models/media_type.dart';
import '../models/playback_target.dart';

class OfflineMediaKey {
  const OfflineMediaKey({
    required this.tmdbId,
    required this.mediaType,
    this.seasonNumber,
    this.episodeNumber,
  });

  final int tmdbId;
  final MediaType mediaType;
  final int? seasonNumber;
  final int? episodeNumber;

  String get value =>
      '${mediaType.name}:$tmdbId:${seasonNumber ?? 0}:${episodeNumber ?? 0}';

  @override
  bool operator ==(Object other) =>
      other is OfflineMediaKey && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

abstract interface class OfflineMediaLibrary {
  Future<PlaybackTarget?> findCompletedTarget(OfflineMediaKey key);
}
