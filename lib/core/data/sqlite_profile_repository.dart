import 'package:sqflite/sqflite.dart';

import '../models/maturity_tier.dart';
import '../models/profile.dart';
import '../models/profile_playback_settings.dart';
import '../services/profile_avatar_catalog.dart';
import '../services/profile_repository.dart';
import '../services/trakt_credential_store.dart';
import 'sqlite_app_settings_repository.dart';

class SqliteProfileRepository implements ProfileRepository {
  SqliteProfileRepository(
    this._database, {
    ProfileAvatarCatalogService? avatarCatalogService,
    TraktCredentialStore? credentialStore,
  })  : _appSettingsRepository = SqliteAppSettingsRepository(_database),
        _credentialStore =
            credentialStore ?? const SecureTraktCredentialStore(),
        _avatarCatalogService =
            avatarCatalogService ?? ProfileAvatarCatalogService.instance;

  final Database _database;
  final SqliteAppSettingsRepository _appSettingsRepository;
  final TraktCredentialStore _credentialStore;
  final ProfileAvatarCatalogService _avatarCatalogService;

  @override
  Future<Profile> createProfile({
    required String name,
    required String languageCode,
    required MaturityTier maturityTier,
    String? avatarLabel,
  }) async {
    final resolvedAvatarLabel = avatarLabel?.trim().isNotEmpty == true
        ? avatarLabel!.trim()
        : await _pickDefaultAvatarLabel(name);
    final profile = Profile(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      avatarLabel: resolvedAvatarLabel,
      languageCode: languageCode,
      maturityTier: maturityTier,
      createdAt: DateTime.now().toUtc(),
    );

    await _database.insert(
      'profiles',
      profile.toMap(includeTraktAccount: false),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await savePlaybackSettings(
      profile.id,
      ProfilePlaybackSettings(languageCode: languageCode),
    );

    return profile;
  }

  @override
  Future<List<Profile>> fetchProfiles() async {
    final rows = await _database.query(
      'profiles',
      orderBy: 'created_at ASC',
    );

    final profiles = <Profile>[];
    for (final row in rows) {
      profiles.add(await _profileFromPersistedRow(row));
    }
    return profiles;
  }

  @override
  Future<String?> getLastActiveProfileId() {
    return _appSettingsRepository.readLastActiveProfileId();
  }

  @override
  Future<ProfilePlaybackSettings> loadPlaybackSettings(String profileId) async {
    final rows = await _database.query(
      'profile_playback_settings',
      where: 'profile_id = ?',
      whereArgs: <Object?>[profileId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return const ProfilePlaybackSettings(languageCode: 'en');
    }

    return ProfilePlaybackSettings.fromMap(rows.first);
  }

  @override
  Future<void> savePlaybackSettings(
    String profileId,
    ProfilePlaybackSettings settings,
  ) {
    return _database.insert(
      'profile_playback_settings',
      settings.toMap(profileId),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> setLastActiveProfileId(String profileId) {
    return _appSettingsRepository.writeLastActiveProfileId(profileId);
  }

  @override
  Future<Profile> updateProfile(Profile profile) async {
    await _database.update(
      'profiles',
      profile.toMap(includeTraktAccount: false),
      where: 'id = ?',
      whereArgs: <Object?>[profile.id],
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final account = profile.traktAccount;
    if (account == null) {
      await _credentialStore.delete(profile.id);
    } else {
      await _credentialStore.write(profile.id, account);
    }

    return profile;
  }

  Future<Profile> _profileFromPersistedRow(Map<String, Object?> row) async {
    final profile = Profile.fromMap(row);
    final secureAccount = await _credentialStore.read(profile.id);
    final legacyAccount = profile.traktAccount;

    if (secureAccount != null) {
      if (legacyAccount != null) {
        await _clearLegacyTraktColumns(profile.id);
      }
      return profile.copyWith(traktAccount: secureAccount);
    }

    if (legacyAccount != null) {
      await _credentialStore.write(profile.id, legacyAccount);
      await _clearLegacyTraktColumns(profile.id);
      return profile;
    }

    return profile.copyWith(traktAccount: null);
  }

  Future<void> _clearLegacyTraktColumns(String profileId) {
    return _database.update(
      'profiles',
      const <String, Object?>{
        'trakt_username': null,
        'trakt_access_token': null,
        'trakt_refresh_token': null,
        'trakt_token_type': null,
        'trakt_scope': null,
        'trakt_token_created_at': null,
        'trakt_expires_in': null,
      },
      where: 'id = ?',
      whereArgs: <Object?>[profileId],
    );
  }

  Future<String> _pickDefaultAvatarLabel(String name) async {
    try {
      final usedRows = await _database.query(
        'profiles',
        columns: const <String>['avatar_label'],
      );
      final usedLabels = usedRows
          .map((row) => (row['avatar_label'] as String?) ?? '')
          .where((label) => label.trim().isNotEmpty)
          .toSet();
      final candidate = await _avatarCatalogService.pickRandomDefaultAvatarKey(
        usedAvatarLabels: usedLabels,
      );
      if (candidate != null) {
        return candidate;
      }
    } catch (_) {
      // Fall back to legacy behavior when avatar catalog cannot be resolved.
    }
    return _avatarLabelForName(name);
  }
}

String _avatarLabelForName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return 'C';
  }
  return trimmed.substring(0, 1).toUpperCase();
}
