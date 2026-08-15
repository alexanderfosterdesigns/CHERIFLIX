import '../models/media_type.dart';

abstract interface class ProviderPreferenceStore {
  Future<int?> getLastGoodProviderIndex({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
  });

  Future<void> saveLastGoodProviderIndex({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required int providerIndex,
  });
}
