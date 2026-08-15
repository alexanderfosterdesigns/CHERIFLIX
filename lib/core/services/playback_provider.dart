import '../models/media_type.dart';
import '../models/playback_target.dart';

abstract interface class PlaybackProvider {
  Future<PlaybackTarget?> resolveTitle({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    int? seasonNumber,
    int? episodeNumber,
  });
}
