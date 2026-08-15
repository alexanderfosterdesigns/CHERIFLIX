import '../models/maturity_tier.dart';
import '../models/profile.dart';
import '../models/profile_playback_settings.dart';

abstract interface class ProfileRepository implements ProfileSettingsStore {
  Future<List<Profile>> fetchProfiles();

  Future<Profile> createProfile({
    required String name,
    required String languageCode,
    required MaturityTier maturityTier,
    String? avatarLabel,
  });

  Future<String?> getLastActiveProfileId();

  Future<void> setLastActiveProfileId(String profileId);

  Future<Profile> updateProfile(Profile profile);
}

abstract interface class ProfileSettingsStore {
  Future<ProfilePlaybackSettings> loadPlaybackSettings(String profileId);

  Future<void> savePlaybackSettings(
    String profileId,
    ProfilePlaybackSettings settings,
  );
}
