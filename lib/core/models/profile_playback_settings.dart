class ProfilePlaybackSettings {
  static const Object _unset = Object();

  const ProfilePlaybackSettings({
    required this.languageCode,
    this.preferredAudioLanguageCode = 'en',
    this.subtitleUrl,
    this.autoplayNextEpisode = true,
    this.autoplayPreviews = true,
    this.muteAutoplayTrailers = true,
    this.preferredAndroidRendererProfile,
  });

  final String languageCode;
  final String preferredAudioLanguageCode;
  final String? subtitleUrl;
  final bool autoplayNextEpisode;
  final bool autoplayPreviews;
  final bool muteAutoplayTrailers;
  final String? preferredAndroidRendererProfile;

  ProfilePlaybackSettings copyWith({
    String? languageCode,
    String? preferredAudioLanguageCode,
    Object? subtitleUrl = _unset,
    bool? autoplayNextEpisode,
    bool? autoplayPreviews,
    bool? muteAutoplayTrailers,
    Object? preferredAndroidRendererProfile = _unset,
  }) {
    return ProfilePlaybackSettings(
      languageCode: languageCode ?? this.languageCode,
      preferredAudioLanguageCode:
          preferredAudioLanguageCode ?? this.preferredAudioLanguageCode,
      subtitleUrl: identical(subtitleUrl, _unset)
          ? this.subtitleUrl
          : subtitleUrl as String?,
      autoplayNextEpisode: autoplayNextEpisode ?? this.autoplayNextEpisode,
      autoplayPreviews: autoplayPreviews ?? this.autoplayPreviews,
      muteAutoplayTrailers: muteAutoplayTrailers ?? this.muteAutoplayTrailers,
      preferredAndroidRendererProfile:
          identical(preferredAndroidRendererProfile, _unset)
              ? this.preferredAndroidRendererProfile
              : preferredAndroidRendererProfile as String?,
    );
  }

  factory ProfilePlaybackSettings.fromMap(Map<String, Object?> map) {
    return ProfilePlaybackSettings.fromJson(Map<String, dynamic>.from(map));
  }

  Map<String, Object?> toMap(String profileId) {
    return <String, Object?>{
      'profile_id': profileId,
      'language_code': languageCode,
      'preferred_audio_language_code': preferredAudioLanguageCode,
      'subtitle_url': subtitleUrl,
      'autoplay_next_episode': autoplayNextEpisode ? 1 : 0,
      'autoplay_previews': autoplayPreviews ? 1 : 0,
      'mute_autoplay_trailers': muteAutoplayTrailers ? 1 : 0,
      'preferred_android_renderer_profile': preferredAndroidRendererProfile,
    };
  }

  factory ProfilePlaybackSettings.fromJson(Map<String, dynamic> json) {
    final subtitleUrl =
        (json['subtitle_url'] ?? json['subtitleUrl'])?.toString().trim();
    final preferredRenderer = (json['preferred_android_renderer_profile'] ??
            json['preferredAndroidRendererProfile'])
        ?.toString()
        .trim();
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
      preferredAndroidRendererProfile:
          preferredRenderer == null || preferredRenderer.isEmpty
              ? null
              : preferredRenderer,
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
      'preferred_android_renderer_profile': preferredAndroidRendererProfile,
    };
  }

  static bool? _readBool(Object? value) {
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
}
