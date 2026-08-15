import 'dart:io';
import 'dart:typed_data';

import '../../models/media_type.dart';
import 'subdl_client.dart';
import 'subdl_models.dart';
import 'subtitle_cache_store.dart';
import 'subtitle_processing.dart';
import 'subtitle_provider.dart';

class SubdlProvider implements SubtitleProvider {
  SubdlProvider({
    required SubdlClient client,
    required SubtitleCacheStore cacheStore,
    SrtToVttConverter converter = const SrtToVttConverter(),
  })  : _client = client,
        _cacheStore = cacheStore,
        _converter = converter;

  final SubdlClient _client;
  final SubtitleCacheStore _cacheStore;
  final SrtToVttConverter _converter;

  @override
  Future<List<SubdlSubtitle>> search(SubtitleSearchRequest request) async {
    final searchKey = request.normalizedEpisodeKey;
    final cached = await _cacheStore.readSearchEntry(searchKey);
    if (cached != null &&
        DateTime.now().toUtc().difference(cached.fetchedAtUtc) <
            SubtitleCacheStore.artifactTtl) {
      return cached.subtitles;
    }

    final normalizedLanguages = _normalizeLanguages(request.languageCodes);
    List<SubdlSubtitle> results = const <SubdlSubtitle>[];
    if (request.imdbId?.trim().isNotEmpty == true) {
      results = await _client.searchByImdb(
        imdbId: request.imdbId!.trim(),
        mediaType: request.mediaType,
        seasonNumber: request.seasonNumber,
        episodeNumber: request.episodeNumber,
        languages: normalizedLanguages,
        year: request.year,
      );
    }
    if (results.isEmpty && request.tmdbId != null) {
      results = await _client.searchByTmdb(
        tmdbId: request.tmdbId!,
        mediaType: request.mediaType,
        seasonNumber: request.seasonNumber,
        episodeNumber: request.episodeNumber,
        languages: normalizedLanguages,
        year: request.year,
      );
    }
    if (results.isEmpty && request.filmName?.trim().isNotEmpty == true) {
      results = await _client.searchByName(
        filmName: request.filmName!.trim(),
        mediaType: request.mediaType,
        seasonNumber: request.seasonNumber,
        episodeNumber: request.episodeNumber,
        languages: normalizedLanguages,
        year: request.year,
      );
    }

    final deduped = _dedupeSubtitles(results);
    final ranked = _rankForRequest(deduped, request);
    if (ranked.isNotEmpty) {
      await _cacheStore.writeSearchEntry(searchKey, ranked);
    }
    return ranked;
  }

  @override
  Future<SubtitleTrack?> downloadAndPrepareTrack(
    SubdlSubtitle subtitle, {
    required String expectedLanguageCode,
    required bool preferHi,
  }) async {
    final cachedPath = await _cacheStore.readArtifactPath(subtitle.id);
    if (cachedPath != null) {
      return SubtitleTrack(
        languageCode: _normalizeLanguageCode(subtitle.language),
        label: _buildLabel(subtitle),
        uri: Uri.file(cachedPath),
        isHI: subtitle.hi,
      );
    }

    final bytes = await _client.downloadSubtitleByMetadata(subtitle);
    if (bytes.isEmpty) {
      return null;
    }
    final extraction = await extractBestSrtFromZipInBackground(
      SubtitleZipExtractionRequest(
        zipBytes: Uint8List.fromList(bytes),
        expectedLanguageCode: expectedLanguageCode,
        preferHi: preferHi,
      ),
    );
    final webVtt = await _converter.convertInBackground(extraction.srtText);
    await _cacheStore.initializeDirectories();
    final safeId = subtitle.id.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final target = File(
      '${_cacheStore.subtitleRootDirectory.path}${Platform.pathSeparator}$safeId.vtt',
    );
    await target.writeAsString(webVtt, flush: true);
    await _cacheStore.writeArtifactPath(
      subtitleId: subtitle.id,
      path: target.path,
    );
    return SubtitleTrack(
      languageCode: _normalizeLanguageCode(subtitle.language),
      label: _buildLabel(subtitle),
      uri: Uri.file(target.path),
      isHI: extraction.isHi || subtitle.hi,
    );
  }

  @override
  Future<void> prefetch(SubtitleSearchRequest request) async {
    final subtitles = await search(request);
    if (subtitles.isEmpty) {
      return;
    }
    final preferredLanguage =
        request.languageCodes.isEmpty ? 'en' : request.languageCodes.first;
    final target = subtitles.first;
    try {
      await downloadAndPrepareTrack(
        target,
        expectedLanguageCode: preferredLanguage,
        preferHi: false,
      );
    } catch (_) {}
  }

  List<String> _normalizeLanguages(List<String> languages) {
    final result = <String>{
      for (final language in languages)
        language.trim().isEmpty
            ? ''
            : _normalizeLanguageCode(language).toUpperCase(),
      'EN',
    };
    result.remove('');
    return result.toList(growable: false);
  }

  List<SubdlSubtitle> _dedupeSubtitles(List<SubdlSubtitle> subtitles) {
    final byId = <String, SubdlSubtitle>{};
    for (final subtitle in subtitles) {
      if (!subtitle.hasDownloadReference) {
        continue;
      }
      byId[subtitle.id] = subtitle;
    }
    final values = byId.values.toList(growable: false);
    values.sort((left, right) {
      final languageCompare = left.language.compareTo(right.language);
      if (languageCompare != 0) {
        return languageCompare;
      }
      final hiCompare = (left.hi ? 0 : 1).compareTo(right.hi ? 0 : 1);
      if (hiCompare != 0) {
        return hiCompare;
      }
      return right.rating.compareTo(left.rating);
    });
    return values;
  }

  List<SubdlSubtitle> _rankForRequest(
    List<SubdlSubtitle> subtitles,
    SubtitleSearchRequest request,
  ) {
    if (subtitles.isEmpty) {
      return subtitles;
    }
    if (request.mediaType != MediaType.tv ||
        request.seasonNumber == null ||
        request.episodeNumber == null) {
      return subtitles;
    }

    final targetSeason = request.seasonNumber!;
    final targetEpisode = request.episodeNumber!;
    final exactMatches = subtitles
        .where(
          (subtitle) =>
              subtitle.seasonNumber == targetSeason &&
              subtitle.episodeNumber == targetEpisode,
        )
        .toList(growable: false);
    if (exactMatches.isNotEmpty) {
      final sortedExact = exactMatches.toList(growable: false)
        ..sort((left, right) => right.rating.compareTo(left.rating));
      return sortedExact;
    }

    final scored = subtitles
        .map(
          (subtitle) => (
            subtitle: subtitle,
            score: _tvMatchScore(
              subtitle,
              targetSeason: targetSeason,
              targetEpisode: targetEpisode,
            ),
          ),
        )
        .toList(growable: false);

    scored.sort((left, right) {
      final scoreCompare = right.score.compareTo(left.score);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return right.subtitle.rating.compareTo(left.subtitle.rating);
    });

    final bestScore = scored.first.score;
    final filtered = bestScore > 0
        ? scored.where((entry) => entry.score > 0).toList(growable: false)
        : scored;
    return filtered.map((entry) => entry.subtitle).toList(growable: false);
  }

  int _tvMatchScore(
    SubdlSubtitle subtitle, {
    required int targetSeason,
    required int targetEpisode,
  }) {
    var score = 0;
    if (subtitle.seasonNumber == targetSeason &&
        subtitle.episodeNumber == targetEpisode) {
      score += 120;
    } else if (subtitle.matchesEpisode(
      seasonNumber: targetSeason,
      episodeNumber: targetEpisode,
    )) {
      score += subtitle.fullSeason ? 80 : 100;
    }

    if (subtitle.seasonNumber != null &&
        subtitle.seasonNumber != targetSeason) {
      score -= 50;
    }
    if (subtitle.episodeNumber != null &&
        subtitle.episodeNumber != targetEpisode &&
        subtitle.episodeFrom == null &&
        subtitle.episodeEnd == null) {
      score -= 20;
    }
    return score;
  }

  String _normalizeLanguageCode(String value) {
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return 'en';
    }
    if (trimmed.length >= 2) {
      return trimmed.substring(0, 2);
    }
    return trimmed;
  }

  String _buildLabel(SubdlSubtitle subtitle) {
    final languageCode =
        _normalizeLanguageCode(subtitle.language).toUpperCase();
    final hiSuffix = subtitle.hi ? ' [HI]' : '';
    final release =
        subtitle.releaseName.isEmpty ? '' : ' - ${subtitle.releaseName}';
    return '$languageCode$hiSuffix$release';
  }
}
