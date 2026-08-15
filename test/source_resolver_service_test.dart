import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/media_type.dart';
import 'package:cheriflix/core/models/profile_playback_settings.dart';
import 'package:cheriflix/core/models/provider_config.dart';
import 'package:cheriflix/core/services/source_resolver_service.dart';

void main() {
  test('MissingSourceResolverService reports a clear configuration error',
      () async {
    const service = MissingSourceResolverService();

    expect(
      () => service.resolveSpecificSource(
        profileId: 'profile-1',
        tmdbId: 1,
        mediaType: MediaType.movie,
        providerConfig: ProviderConfig.defaults(),
        settings: const ProfilePlaybackSettings(languageCode: 'en'),
        providerIndex: 1,
      ),
      throwsA(
        isA<SourceResolverUnavailableException>().having(
          (error) => error.message,
          'message',
          contains('CHERIFLIX_SOURCE_RESOLVER_URL'),
        ),
      ),
    );
  });
}
