import 'package:flutter/foundation.dart';

import '../../models/caption_resolution.dart';
import '../../models/caption_track.dart';
import '../../models/media_summary.dart';
import '../../models/media_type.dart';
import '../../utils/safe_logging.dart';
import '../caption_service.dart';
import 'subdl_models.dart';
import 'subtitle_cache_store.dart';
import 'subtitle_provider.dart';

abstract interface class SubtitlePrefetchService {
  Future<void> prefetchForSummary(
    MediaSummary summary, {
    String? preferredLanguageCode,
  });
}

abstract interface class SubtitleOffsetStore {
  Future<int> readOffsetMs({
    required int tmdbId,
    required MediaType mediaType,
    required int? seasonNumber,
    required int? episodeNumber,
    String? providerKey,
    bool allowProviderScopedFallback = false,
  });

  Future<void> writeOffsetMs({
    required int tmdbId,
    required MediaType mediaType,
    required int? seasonNumber,
    required int? episodeNumber,
    required int offsetMs,
    String? providerKey,
  });
}

class SubdlCaptionService
    implements CaptionService, SubtitlePrefetchService, SubtitleOffsetStore {
  SubdlCaptionService({
    required SubtitleProviderCoordinator coordinator,
    required SubtitleCacheStore cacheStore,
    required bool hasConfiguredApiKey,
  })  : _coordinator = coordinator,
        _cacheStore = cacheStore,
        _hasConfiguredApiKey = hasConfiguredApiKey;

  final SubtitleProviderCoordinator _coordinator;
  final SubtitleCacheStore _cacheStore;
  final bool _hasConfiguredApiKey;

  static const int _maxTrackCount = 10;

  @override
  Future<CaptionResolution> resolveCaptions({
    required int? tmdbId,
    required MediaType mediaType,
    required String languageCode,
    int? seasonNumber,
    int? episodeNumber,
    String? imdbId,
    String? title,
  }) async {
    if (!_hasConfiguredApiKey) {
      return const CaptionResolution(
        failureCode: CaptionFailureCode.missingApiKey,
      );
    }

    final request = SubtitleSearchRequest(
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      languageCodes: _searchLanguagesFor(languageCode),
      imdbId: imdbId,
      filmName: title,
    );
    cheriflixLog(
      'subtitles',
      'Provider search starting. tmdbId=${request.tmdbId ?? "unknown"} '
          'mediaType=${request.mediaType.name} '
          'season=${request.seasonNumber ?? "none"} '
          'episode=${request.episodeNumber ?? "none"}',
    );
    List<SubdlSubtitle> subtitles;
    try {
      subtitles = await _coordinator.search(request);
    } catch (error) {
      cheriflixLog('subtitles', 'Provider search failed.', error: error);
      return const CaptionResolution(
        failureCode: CaptionFailureCode.serviceError,
      );
    }
    cheriflixLog(
      'subtitles',
      'Provider search returned ${subtitles.length} subtitle candidates.',
    );
    if (subtitles.isEmpty) {
      return const CaptionResolution(failureCode: CaptionFailureCode.noMatch);
    }

    final tracks = <CaptionTrack>[];
    for (final subtitle in subtitles.take(_maxTrackCount)) {
      try {
        final prepared = await _coordinator.downloadAndPrepareTrack(
          subtitle,
          expectedLanguageCode: languageCode,
          preferHi: false,
        );
        if (prepared == null) {
          cheriflixLog(
            'subtitles',
            'Dropped subtitle candidate because prepared track was null.',
          );
          continue;
        }
        tracks.add(_toCaptionTrack(subtitle.id, subtitle, prepared));
      } catch (error) {
        cheriflixLog('subtitles', 'Failed to prepare subtitle.', error: error);
      }
    }

    if (tracks.isEmpty) {
      cheriflixLog(
        'subtitles',
        'All subtitle candidates were dropped during download/prepare.',
      );
      return const CaptionResolution(
        failureCode: CaptionFailureCode.prepareFailed,
      );
    }
    final selectedTrackId = _selectDefaultTrackId(
      tracks,
      preferredLanguageCode: languageCode,
    );
    return CaptionResolution(
      tracks: tracks
          .map(
              (track) => track.copyWith(isDefault: track.id == selectedTrackId))
          .toList(growable: false),
      selectedTrackId: selectedTrackId,
    );
  }

  @override
  Future<void> prefetchForSummary(
    MediaSummary summary, {
    String? preferredLanguageCode,
  }) async {
    final request = SubtitleSearchRequest(
      tmdbId: summary.tmdbId,
      mediaType: summary.mediaType,
      languageCodes: _searchLanguagesFor(preferredLanguageCode ?? 'en'),
      year: summary.releaseDate?.year,
      filmName: summary.title,
    );
    try {
      await _coordinator.prefetch(request);
    } catch (_) {}
  }

  @override
  Future<int> readOffsetMs({
    required int tmdbId,
    required MediaType mediaType,
    required int? seasonNumber,
    required int? episodeNumber,
    String? providerKey,
    bool allowProviderScopedFallback = false,
  }) async {
    final key = _offsetKey(
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      providerKey: providerKey,
    );
    final exact = _cacheStore.readSubtitleOffsetMsIfPresent(key);
    if (exact != null) {
      return exact;
    }
    if (!allowProviderScopedFallback ||
        mediaType != MediaType.tv ||
        seasonNumber == null ||
        episodeNumber == null) {
      return 0;
    }

    final providerSegment = _providerSegment(providerKey);
    final seasonPrefix = _offsetSeasonPrefix(
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      providerSegment: providerSegment,
    );
    final targetEpisode = episodeNumber;
    final fallbackCandidates = <MapEntry<SubtitleOffsetCacheEntry, int>>[];
    for (final entry in _cacheStore.readSubtitleOffsetEntriesByPrefix(
      seasonPrefix,
    )) {
      final candidateEpisode = _episodeNumberFromOffsetKey(entry.offsetKey);
      if (candidateEpisode == null || candidateEpisode == targetEpisode) {
        continue;
      }
      fallbackCandidates.add(MapEntry(entry, candidateEpisode));
    }
    if (fallbackCandidates.isEmpty) {
      return 0;
    }
    fallbackCandidates.sort((left, right) {
      final leftDistance = (left.value - targetEpisode).abs();
      final rightDistance = (right.value - targetEpisode).abs();
      final distanceCompare = leftDistance.compareTo(rightDistance);
      if (distanceCompare != 0) {
        return distanceCompare;
      }
      final leftUpdated = left.key.updatedAtUtc;
      final rightUpdated = right.key.updatedAtUtc;
      if (leftUpdated != null && rightUpdated != null) {
        final updatedCompare = rightUpdated.compareTo(leftUpdated);
        if (updatedCompare != 0) {
          return updatedCompare;
        }
      } else if (leftUpdated != null && rightUpdated == null) {
        return -1;
      } else if (leftUpdated == null && rightUpdated != null) {
        return 1;
      }
      return right.value.compareTo(left.value);
    });
    final selectedFallback = fallbackCandidates.first;
    cheriflixLog(
      'subtitles',
      'Offset fallback hit. tmdbId=$tmdbId season=$seasonNumber '
          'episode=$targetEpisode fromEpisode=${selectedFallback.value} '
          'offsetMs=${selectedFallback.key.offsetMs}',
    );
    return selectedFallback.key.offsetMs;
  }

  @override
  Future<void> writeOffsetMs({
    required int tmdbId,
    required MediaType mediaType,
    required int? seasonNumber,
    required int? episodeNumber,
    required int offsetMs,
    String? providerKey,
  }) async {
    final key = _offsetKey(
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      providerKey: providerKey,
    );
    await _cacheStore.writeSubtitleOffsetMs(key, offsetMs);
  }

  Future<void> scheduleCleanup() async {
    Future<void>.delayed(const Duration(seconds: 5), () async {
      try {
        await _cacheStore.cleanupExpiredEntries();
      } catch (error, stackTrace) {
        cheriflixLog(
          'subtitles',
          'SubdlCaptionService cleanup failed.',
          error: error,
          stackTrace: stackTrace,
        );
      }
    });
  }

  List<String> _searchLanguagesFor(String preferredLanguageCode) {
    final normalized = preferredLanguageCode.trim().toUpperCase();
    return <String>[
      if (normalized.isNotEmpty) normalized,
      'EN',
    ];
  }

  CaptionTrack _toCaptionTrack(
    String id,
    SubdlSubtitle subtitle,
    SubtitleTrack track,
  ) {
    return CaptionTrack(
      id: id,
      label: track.label,
      languageCode: track.languageCode,
      kind: CaptionTrackKind.manual,
      format: CaptionTrackFormat.vtt,
      url: track.uri,
      isDefault: false,
      isHI: track.isHI || subtitle.hi,
    );
  }

  String _selectDefaultTrackId(
    List<CaptionTrack> tracks, {
    required String preferredLanguageCode,
  }) {
    final normalizedPreferred = preferredLanguageCode.trim().toLowerCase();
    for (final track in tracks) {
      if (track.languageCode.trim().toLowerCase() == normalizedPreferred &&
          !track.isHI) {
        return track.id;
      }
    }
    for (final track in tracks) {
      if (track.languageCode.trim().toLowerCase() == normalizedPreferred) {
        return track.id;
      }
    }
    for (final track in tracks) {
      if (track.languageCode.trim().toLowerCase() == 'en' && !track.isHI) {
        return track.id;
      }
    }
    return tracks.first.id;
  }

  String _offsetKey({
    required int tmdbId,
    required MediaType mediaType,
    required int? seasonNumber,
    required int? episodeNumber,
    String? providerKey,
  }) {
    final season = seasonNumber ?? 0;
    final episode = episodeNumber ?? 0;
    final providerSegment = _providerSegment(providerKey);
    return 'offset:v2:${mediaType.name}:$tmdbId:$providerSegment:s${season.toString().padLeft(2, '0')}e${episode.toString().padLeft(2, '0')}';
  }

  String _offsetSeasonPrefix({
    required int tmdbId,
    required MediaType mediaType,
    required int seasonNumber,
    required String providerSegment,
  }) {
    return 'offset:v2:${mediaType.name}:$tmdbId:$providerSegment:s${seasonNumber.toString().padLeft(2, '0')}e';
  }

  String _providerSegment(String? providerKey) {
    final normalized = (providerKey ?? '').trim().toLowerCase();
    if (normalized.isEmpty) {
      return 'default';
    }
    return normalized;
  }

  int? _episodeNumberFromOffsetKey(String offsetKey) {
    final match = RegExp(r'e(\d{2,3})$').firstMatch(offsetKey);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1)!);
  }
}
