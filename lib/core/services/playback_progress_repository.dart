import '../models/media_type.dart';
import '../models/playback_progress_entry.dart';

abstract interface class PlaybackProgressRepository {
  Future<List<PlaybackProgressEntry>> fetchProgressEntries(
    String profileId, {
    int limit = 200,
  });

  Future<void> saveProgress({
    required String profileId,
    required PlaybackProgressEntry entry,
    int limit = 200,
  });

  Future<void> removeProgress({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    int? seasonNumber,
    int? episodeNumber,
  });
}
