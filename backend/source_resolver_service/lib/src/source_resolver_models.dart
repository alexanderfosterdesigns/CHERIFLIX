class SourceFailureKind {
  static const String probe = 'probe';
  static const String load = 'load';
  static const String blockedNavigation = 'blockedNavigation';
  static const String sourceRejected = 'sourceRejected';
  static const String manualSwitch = 'manualSwitch';
}

class ProviderConfig {
  const ProviderConfig({
    required this.providerPriority,
    required this.providerTimeoutSeconds,
    required this.disabledProviders,
  });

  factory ProviderConfig.defaults() {
    return const ProviderConfig(
      providerPriority: <String>[
        'vidsrc',
        'vsembed',
        'embedsu',
        'vsrcsu',
        'vidsrcme',
        'vidlink',
        'vidsrc_embed',
        'videasy',
        'vidzee',
        'mapple',
        'primesrc',
        'multiembed',
        'autoembed',
        '111movies',
        'hdrezka',
      ],
      providerTimeoutSeconds: 8,
      disabledProviders: <String>{'2embed', '111movies'},
    );
  }

  factory ProviderConfig.fromJson(Map<String, dynamic> json) {
    return ProviderConfig(
      providerPriority: _readStringList(
        json['provider_priority'] ?? json['providerPriority'],
      ),
      providerTimeoutSeconds: _readInt(json['provider_timeout_seconds'] ??
              json['providerTimeoutSeconds']) ??
          8,
      disabledProviders: _readStringSet(
        json['disabled_providers'] ?? json['disabledProviders'],
      ),
    );
  }

  final List<String> providerPriority;
  final int providerTimeoutSeconds;
  final Set<String> disabledProviders;

  Map<String, dynamic> toJson() {
    final sortedDisabledProviders = disabledProviders.toList(growable: false)
      ..sort();
    return <String, dynamic>{
      'provider_priority': providerPriority,
      'provider_timeout_seconds': providerTimeoutSeconds,
      'disabled_providers': sortedDisabledProviders,
    };
  }
}

class ProfilePlaybackSettings {
  const ProfilePlaybackSettings({
    required this.languageCode,
    this.preferredAudioLanguageCode = 'en',
    this.subtitleUrl,
    this.autoplayNextEpisode = true,
    this.autoplayPreviews = true,
    this.muteAutoplayTrailers = true,
  });

  final String languageCode;
  final String preferredAudioLanguageCode;
  final String? subtitleUrl;
  final bool autoplayNextEpisode;
  final bool autoplayPreviews;
  final bool muteAutoplayTrailers;

  factory ProfilePlaybackSettings.fromJson(Map<String, dynamic> json) {
    final subtitleUrl =
        (json['subtitle_url'] ?? json['subtitleUrl'])?.toString().trim();
    return ProfilePlaybackSettings(
      languageCode:
          (json['language_code'] ?? json['languageCode'] ?? 'en').toString(),
      preferredAudioLanguageCode: (json['preferred_audio_language_code'] ??
              json['preferredAudioLanguageCode'] ??
              'en')
          .toString(),
      subtitleUrl:
          subtitleUrl == null || subtitleUrl.isEmpty ? null : subtitleUrl,
      autoplayNextEpisode: _readBool(
            json['autoplay_next_episode'] ?? json['autoplayNextEpisode'],
          ) ??
          true,
      autoplayPreviews: _readBool(
            json['autoplay_previews'] ?? json['autoplayPreviews'],
          ) ??
          true,
      muteAutoplayTrailers: _readBool(
            json['mute_autoplay_trailers'] ?? json['muteAutoplayTrailers'],
          ) ??
          true,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'language_code': languageCode,
      'preferred_audio_language_code': preferredAudioLanguageCode,
      'subtitle_url': subtitleUrl,
      'autoplay_next_episode': autoplayNextEpisode,
      'autoplay_previews': autoplayPreviews,
      'mute_autoplay_trailers': muteAutoplayTrailers,
    };
  }
}

enum PlaybackSourceKind {
  hls,
  file;

  static PlaybackSourceKind? tryParse(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return switch (normalized) {
      'hls' => PlaybackSourceKind.hls,
      'file' || 'mp4' || 'mkv' => PlaybackSourceKind.file,
      _ => null,
    };
  }
}

class PlaybackTarget {
  const PlaybackTarget({
    required this.uri,
    required this.providerKey,
    required this.providerLabel,
    required this.providerIndex,
    required this.sourceKind,
    this.httpHeaders = const <String, String>{},
    this.pageUri,
    this.expiresAtEpochMs,
  });

  final Uri uri;
  final String providerKey;
  final String providerLabel;
  final int providerIndex;
  final PlaybackSourceKind sourceKind;
  final Map<String, String> httpHeaders;
  final Uri? pageUri;
  final int? expiresAtEpochMs;

  factory PlaybackTarget.fromJson(Map<String, dynamic> json) {
    final uriValue = json['uri'] ?? json['url'];
    final rawSourceKind =
        json['sourceKind'] ?? json['source_kind'] ?? _inferSourceKind(uriValue);
    final pageUriValue = json['pageUri'] ?? json['page_uri'];
    return PlaybackTarget(
      uri: Uri.parse(uriValue.toString()),
      providerKey:
          (json['providerKey'] ?? json['provider_key'] ?? '').toString(),
      providerLabel:
          (json['providerLabel'] ?? json['provider_label'] ?? '').toString(),
      providerIndex: _readInt(
            json['providerIndex'] ?? json['provider_index'],
          ) ??
          0,
      sourceKind:
          PlaybackSourceKind.tryParse(rawSourceKind) ?? PlaybackSourceKind.file,
      httpHeaders: _readStringMap(
        json['httpHeaders'] ?? json['http_headers'],
      ),
      pageUri: pageUriValue == null || '$pageUriValue'.trim().isEmpty
          ? null
          : Uri.parse(pageUriValue.toString()),
      expiresAtEpochMs: _readInt(
        json['expiresAtEpochMs'] ?? json['expires_at_epoch_ms'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'uri': uri.toString(),
      'providerKey': providerKey,
      'providerLabel': providerLabel,
      'providerIndex': providerIndex,
      'sourceKind': sourceKind.name,
      'httpHeaders': httpHeaders,
      if (pageUri != null) 'pageUri': pageUri.toString(),
      if (expiresAtEpochMs != null) 'expiresAtEpochMs': expiresAtEpochMs,
    };
  }

  bool get isDirectPlayable =>
      uri.hasScheme &&
      (sourceKind == PlaybackSourceKind.hls ||
          sourceKind == PlaybackSourceKind.file);
}

class SourceRequestKey {
  const SourceRequestKey({
    required this.profileId,
    required this.tmdbId,
    required this.mediaType,
    this.seasonNumber,
    this.episodeNumber,
  });

  final String profileId;
  final int tmdbId;
  final String mediaType;
  final int? seasonNumber;
  final int? episodeNumber;

  String get cacheKey => [
        profileId,
        mediaType,
        '$tmdbId',
        if (seasonNumber != null) 's$seasonNumber',
        if (episodeNumber != null) 'e$episodeNumber',
      ].join('_');

  @override
  bool operator ==(Object other) {
    return other is SourceRequestKey &&
        other.profileId == profileId &&
        other.tmdbId == tmdbId &&
        other.mediaType == mediaType &&
        other.seasonNumber == seasonNumber &&
        other.episodeNumber == episodeNumber;
  }

  @override
  int get hashCode =>
      Object.hash(profileId, tmdbId, mediaType, seasonNumber, episodeNumber);
}

class SourceResolverRequest {
  const SourceResolverRequest({
    required this.profileId,
    required this.tmdbId,
    required this.mediaType,
    required this.providerConfig,
    required this.settings,
    this.seasonNumber,
    this.episodeNumber,
    this.currentProviderIndex,
    this.providerIndex,
    this.kind = SourceFailureKind.load,
    this.probeCandidates = true,
    this.probeCandidate = false,
  });

  factory SourceResolverRequest.fromJson(Map<String, dynamic> json) {
    final providerConfigPayload =
        json['provider_config'] ?? json['providerConfig'];
    final settingsPayload = json['settings'] ?? json['playbackSettings'];
    return SourceResolverRequest(
      profileId:
          (json['profileId'] ?? json['profile_id'] ?? '').toString().trim(),
      tmdbId: _readInt(json['tmdbId'] ?? json['tmdb_id']) ?? 0,
      mediaType:
          (json['mediaType'] ?? json['media_type'] ?? '').toString().trim(),
      seasonNumber: _readInt(json['seasonNumber'] ?? json['season_number']),
      episodeNumber: _readInt(json['episodeNumber'] ?? json['episode_number']),
      providerConfig: providerConfigPayload is Map
          ? ProviderConfig.fromJson(
              Map<String, dynamic>.from(providerConfigPayload),
            )
          : ProviderConfig.defaults(),
      settings: settingsPayload is Map
          ? ProfilePlaybackSettings.fromJson(
              Map<String, dynamic>.from(settingsPayload),
            )
          : const ProfilePlaybackSettings(languageCode: 'en'),
      currentProviderIndex: _readInt(
          json['currentProviderIndex'] ?? json['current_provider_index']),
      providerIndex: _readInt(json['providerIndex'] ?? json['provider_index']),
      kind: (json['kind'] ?? json['failureKind'] ?? json['failure_kind'])
              ?.toString() ??
          SourceFailureKind.load,
      probeCandidates: _readBool(
            json['probeCandidates'] ?? json['probe_candidates'],
          ) ??
          true,
      probeCandidate: _readBool(
            json['probeCandidate'] ?? json['probe_candidate'],
          ) ??
          false,
    );
  }

  final String profileId;
  final int tmdbId;
  final String mediaType;
  final int? seasonNumber;
  final int? episodeNumber;
  final ProviderConfig providerConfig;
  final ProfilePlaybackSettings settings;
  final int? currentProviderIndex;
  final int? providerIndex;
  final String kind;
  final bool probeCandidates;
  final bool probeCandidate;

  SourceRequestKey get key => SourceRequestKey(
        profileId: profileId,
        tmdbId: tmdbId,
        mediaType: mediaType,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      );
}

List<String> _readStringList(Object? value) {
  return (value as List<dynamic>? ?? const <dynamic>[])
      .map((item) => item.toString())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

Set<String> _readStringSet(Object? value) {
  return (value as List<dynamic>? ?? const <dynamic>[])
      .map((item) => item.toString())
      .where((item) => item.isNotEmpty)
      .toSet();
}

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

bool? _readBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  final text = value?.toString().trim().toLowerCase();
  if (text == null || text.isEmpty) {
    return null;
  }
  if (text == 'true' || text == '1' || text == 'yes') {
    return true;
  }
  if (text == 'false' || text == '0' || text == 'no') {
    return false;
  }
  return null;
}

Map<String, String> _readStringMap(Object? value) {
  if (value is! Map) {
    return const <String, String>{};
  }
  return <String, String>{
    for (final entry in value.entries)
      entry.key.toString(): entry.value.toString(),
  };
}

PlaybackSourceKind _inferSourceKind(Object? value) {
  final uri = Uri.tryParse(value?.toString() ?? '');
  final path = uri?.path.toLowerCase() ?? '';
  if (path.endsWith('.m3u8')) {
    return PlaybackSourceKind.hls;
  }
  return PlaybackSourceKind.file;
}
