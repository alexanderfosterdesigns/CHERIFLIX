import '../models/media_type.dart';

abstract interface class AudioLanguagePreferenceStore {
  Future<String?> getPreferredLanguage({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
  });

  Future<void> setPreferredLanguage({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  });

  Future<void> clearPreferredLanguage({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
  });

  Future<void> clearAllForProfile(String profileId);
}

class NoOpAudioLanguagePreferenceStore implements AudioLanguagePreferenceStore {
  const NoOpAudioLanguagePreferenceStore();

  @override
  Future<String?> getPreferredLanguage({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
  }) async =>
      null;

  @override
  Future<void> setPreferredLanguage({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    required String languageCode,
  }) async {}

  @override
  Future<void> clearPreferredLanguage({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
  }) async {}

  @override
  Future<void> clearAllForProfile(String profileId) async {}
}

String normalizeAudioLanguageCode(String value) {
  final normalized = value.trim().toLowerCase().replaceAll('_', '-');
  if (normalized.isEmpty) return '';
  final primary = normalized.split('-').first;
  return switch (primary) {
    'eng' => 'en',
    'spa' => 'es',
    'fra' || 'fre' => 'fr',
    'deu' || 'ger' => 'de',
    'ita' => 'it',
    'por' => 'pt',
    'rus' => 'ru',
    'jpn' => 'ja',
    'kor' => 'ko',
    'zho' || 'chi' => 'zh',
    'hin' => 'hi',
    'ara' => 'ar',
    _ => primary,
  };
}

String displayAudioLanguage(String? value) {
  final normalized = normalizeAudioLanguageCode(value ?? '');
  return switch (normalized) {
    'en' => 'English',
    'es' => 'Spanish',
    'fr' => 'French',
    'de' => 'German',
    'it' => 'Italian',
    'pt' => 'Portuguese',
    'ru' => 'Russian',
    'ja' => 'Japanese',
    'ko' => 'Korean',
    'zh' => 'Chinese',
    'hi' => 'Hindi',
    'ar' => 'Arabic',
    _ => normalized.isEmpty ? '' : normalized.toUpperCase(),
  };
}
