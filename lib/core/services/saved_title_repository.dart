import '../models/media_summary.dart';
import '../models/media_type.dart';

abstract interface class SavedTitleRepository {
  Future<List<MediaSummary>> fetchSavedTitles(String profileId);

  Future<void> saveTitle({
    required String profileId,
    required MediaSummary summary,
  });

  Future<void> removeTitle({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
  });
}
