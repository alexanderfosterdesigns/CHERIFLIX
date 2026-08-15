import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/profile_playback_settings.dart';

void main() {
  test('ProfilePlaybackSettings serializes preferred Android renderer profile',
      () {
    const settings = ProfilePlaybackSettings(
      languageCode: 'en',
      subtitleUrl: 'https://example.com/subs.vtt',
      preferredAndroidRendererProfile: 'androidAttachEarlyFallback',
    );

    final map = settings.toMap('profile-1');
    expect(
      map['preferred_android_renderer_profile'],
      'androidAttachEarlyFallback',
    );

    final fromMap = ProfilePlaybackSettings.fromMap(map);
    expect(
      fromMap.preferredAndroidRendererProfile,
      'androidAttachEarlyFallback',
    );

    final fromCamelJson = ProfilePlaybackSettings.fromJson(
      <String, dynamic>{
        'languageCode': 'en',
        'preferredAndroidRendererProfile': 'standard',
      },
    );
    expect(fromCamelJson.preferredAndroidRendererProfile, 'standard');
  });

  test(
      'ProfilePlaybackSettings.copyWith can explicitly clear subtitle and preferred renderer',
      () {
    const settings = ProfilePlaybackSettings(
      languageCode: 'en',
      subtitleUrl: 'https://example.com/subs.vtt',
      preferredAndroidRendererProfile: 'standard',
    );

    final cleared = settings.copyWith(
      subtitleUrl: null,
      preferredAndroidRendererProfile: null,
    );

    expect(cleared.subtitleUrl, isNull);
    expect(cleared.preferredAndroidRendererProfile, isNull);
  });
}
