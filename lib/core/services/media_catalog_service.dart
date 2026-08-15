import '../models/home_catalog_data.dart';
import '../models/just_released_catalog.dart';
import '../models/media_summary.dart';
import '../models/media_type.dart';

abstract interface class MediaCatalogService {
  Future<HomeCatalogData> fetchHomeCatalog({
    required String languageCode,
  });

  Future<JustReleasedCatalog> fetchJustReleasedCatalog({
    required String languageCode,
    required DateTime releasedAfter,
  });

  Future<List<MediaSummary>> searchTitles({
    required String query,
    required String languageCode,
  });

  Future<MediaSummary> fetchTitleDetails({
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  });
}
