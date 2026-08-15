import '../../models/media_type.dart';
import 'subdl_models.dart';

class SubtitleSearchRequest {
  const SubtitleSearchRequest({
    required this.tmdbId,
    required this.mediaType,
    required this.languageCodes,
    this.seasonNumber,
    this.episodeNumber,
    this.year,
    this.imdbId,
    this.filmName,
  });

  final int? tmdbId;
  final MediaType mediaType;
  final List<String> languageCodes;
  final int? seasonNumber;
  final int? episodeNumber;
  final int? year;
  final String? imdbId;
  final String? filmName;

  String get normalizedEpisodeKey {
    const cacheVersion = 'v2';
    final season = seasonNumber ?? 0;
    final episode = episodeNumber ?? 0;
    final languages = languageCodes
        .map((value) => value.trim().toUpperCase())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
    final identity = imdbId?.trim().isNotEmpty == true
        ? imdbId!.trim().toLowerCase()
        : tmdbId != null
            ? 'tmdb:$tmdbId'
            : filmName?.trim().isNotEmpty == true
                ? 'name:${filmName!.trim().toLowerCase()}'
                : 'unknown';
    return '$cacheVersion:$identity:s${season.toString().padLeft(2, '0')}e${episode.toString().padLeft(2, '0')}:${languages.join(',')}';
  }
}

abstract interface class SubtitleProvider {
  Future<List<SubdlSubtitle>> search(SubtitleSearchRequest request);

  Future<SubtitleTrack?> downloadAndPrepareTrack(
    SubdlSubtitle subtitle, {
    required String expectedLanguageCode,
    required bool preferHi,
  });

  Future<void> prefetch(SubtitleSearchRequest request);
}

class SubtitleProviderCoordinator {
  SubtitleProviderCoordinator({
    required this.primary,
    this.fallback,
  });

  final SubtitleProvider primary;
  final SubtitleProvider? fallback;

  Future<List<SubdlSubtitle>> search(SubtitleSearchRequest request) async {
    try {
      final results = await primary.search(request);
      if (results.isNotEmpty || fallback == null) {
        return results;
      }
    } catch (_) {
      if (fallback == null) {
        rethrow;
      }
    }
    return fallback!.search(request);
  }

  Future<SubtitleTrack?> downloadAndPrepareTrack(
    SubdlSubtitle subtitle, {
    required String expectedLanguageCode,
    required bool preferHi,
  }) async {
    try {
      final track = await primary.downloadAndPrepareTrack(
        subtitle,
        expectedLanguageCode: expectedLanguageCode,
        preferHi: preferHi,
      );
      if (track != null || fallback == null) {
        return track;
      }
    } catch (_) {
      if (fallback == null) {
        rethrow;
      }
    }
    return fallback!.downloadAndPrepareTrack(
      subtitle,
      expectedLanguageCode: expectedLanguageCode,
      preferHi: preferHi,
    );
  }

  Future<void> prefetch(SubtitleSearchRequest request) async {
    try {
      await primary.prefetch(request);
    } catch (_) {
      if (fallback != null) {
        await fallback!.prefetch(request);
      }
    }
  }
}

class OpenSubtitlesProviderStub implements SubtitleProvider {
  const OpenSubtitlesProviderStub();

  @override
  Future<List<SubdlSubtitle>> search(SubtitleSearchRequest request) async {
    return const <SubdlSubtitle>[];
  }

  @override
  Future<SubtitleTrack?> downloadAndPrepareTrack(
    SubdlSubtitle subtitle, {
    required String expectedLanguageCode,
    required bool preferHi,
  }) async {
    return null;
  }

  @override
  Future<void> prefetch(SubtitleSearchRequest request) async {}
}
