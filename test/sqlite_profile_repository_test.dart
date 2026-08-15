import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/data/sqlite_database.dart';
import 'package:cheriflix/core/data/sqlite_profile_repository.dart';
import 'package:cheriflix/core/models/maturity_tier.dart';
import 'package:cheriflix/core/models/profile.dart';
import 'package:cheriflix/core/models/trakt_account.dart';
import 'package:cheriflix/core/services/profile_avatar_catalog.dart';
import 'package:cheriflix/core/services/trakt_credential_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'createProfile assigns unique default avatars while defaults remain',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'cheriflix_profile_repo_',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      await _seedAvatarFiles(
        root: tempDirectory,
        defaultFiles: const <String>[
          'blue.png',
          'pink.png',
        ],
      );

      final database = await CheriflixDatabase.open(
        databasePath: _databasePath(tempDirectory),
      );
      addTearDown(database.close);

      final repository = SqliteProfileRepository(
        database,
        avatarCatalogService: ProfileAvatarCatalogService(
          searchRoots: <Directory>[tempDirectory],
        ),
        credentialStore: MemoryTraktCredentialStore(),
      );

      final first = await repository.createProfile(
        name: 'Alice',
        languageCode: 'en',
        maturityTier: MaturityTier.mature,
      );
      final second = await repository.createProfile(
        name: 'Bob',
        languageCode: 'en',
        maturityTier: MaturityTier.mature,
      );

      expect(first.avatarLabel, startsWith('Default/'));
      expect(second.avatarLabel, startsWith('Default/'));
      expect(first.avatarLabel, 'Default/blue.png');
      expect(second.avatarLabel, 'Default/pink.png');
      expect(second.avatarLabel, isNot(equals(first.avatarLabel)));
    },
  );

  test(
    'createProfile reuses defaults when all default avatars are used',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'cheriflix_profile_repo_',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      await _seedAvatarFiles(
        root: tempDirectory,
        defaultFiles: const <String>['only-default.png'],
      );

      final database = await CheriflixDatabase.open(
        databasePath: _databasePath(tempDirectory),
      );
      addTearDown(database.close);

      final repository = SqliteProfileRepository(
        database,
        avatarCatalogService: ProfileAvatarCatalogService(
          searchRoots: <Directory>[tempDirectory],
        ),
        credentialStore: MemoryTraktCredentialStore(),
      );

      final first = await repository.createProfile(
        name: 'First',
        languageCode: 'en',
        maturityTier: MaturityTier.mature,
      );
      final second = await repository.createProfile(
        name: 'Second',
        languageCode: 'en',
        maturityTier: MaturityTier.mature,
      );

      expect(first.avatarLabel, 'Default/only-default.png');
      expect(second.avatarLabel, 'Default/only-default.png');
    },
  );

  test('updateProfile preserves explicit avatar selection', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'cheriflix_profile_repo_',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    await _seedAvatarFiles(
      root: tempDirectory,
      defaultFiles: const <String>['default.png'],
    );

    final database = await CheriflixDatabase.open(
      databasePath: _databasePath(tempDirectory),
    );
    addTearDown(database.close);

    final repository = SqliteProfileRepository(
      database,
      avatarCatalogService: ProfileAvatarCatalogService(
        searchRoots: <Directory>[tempDirectory],
      ),
      credentialStore: MemoryTraktCredentialStore(),
    );

    final created = await repository.createProfile(
      name: 'Before',
      languageCode: 'en',
      maturityTier: MaturityTier.mature,
    );
    final updated = await repository.updateProfile(
      created.copyWith(
        name: 'After',
        avatarLabel: 'pink-choice.png',
      ),
    );

    expect(updated.name, 'After');
    expect(updated.avatarLabel, 'pink-choice.png');

    final profiles = await repository.fetchProfiles();
    final persisted =
        profiles.singleWhere((profile) => profile.id == created.id);
    expect(persisted.avatarLabel, 'pink-choice.png');
  });

  test('createProfile preserves an explicitly supplied avatar label', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'cheriflix_profile_repo_',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    await _seedAvatarFiles(
      root: tempDirectory,
      defaultFiles: const <String>['default.png'],
    );

    final database = await CheriflixDatabase.open(
      databasePath: _databasePath(tempDirectory),
    );
    addTearDown(database.close);

    final repository = SqliteProfileRepository(
      database,
      avatarCatalogService: ProfileAvatarCatalogService(
        searchRoots: <Directory>[tempDirectory],
      ),
      credentialStore: MemoryTraktCredentialStore(),
    );

    final created = await repository.createProfile(
      name: 'Custom',
      languageCode: 'en',
      maturityTier: MaturityTier.mature,
      avatarLabel: 'manual-choice.png',
    );

    expect(created.avatarLabel, 'manual-choice.png');

    final persisted = (await repository.fetchProfiles()).single;
    expect(persisted.avatarLabel, 'manual-choice.png');
  });

  test('updateProfile persists Trakt account data for a profile', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'cheriflix_profile_repo_',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    await _seedAvatarFiles(
      root: tempDirectory,
      defaultFiles: const <String>['default.png'],
    );

    final database = await CheriflixDatabase.open(
      databasePath: _databasePath(tempDirectory),
    );
    addTearDown(database.close);

    final repository = SqliteProfileRepository(
      database,
      avatarCatalogService: ProfileAvatarCatalogService(
        searchRoots: <Directory>[tempDirectory],
      ),
      credentialStore: MemoryTraktCredentialStore(),
    );

    final created = await repository.createProfile(
      name: 'Trakt User',
      languageCode: 'en',
      maturityTier: MaturityTier.mature,
    );
    final connected = await repository.updateProfile(
      created.copyWith(
        traktAccount: TraktAccount(
          username: 'cherif',
          accessToken: 'access-token',
          refreshToken: 'refresh-token',
          tokenType: 'bearer',
          scope: 'public',
          tokenCreatedAt: DateTime.utc(2026, 3, 28, 10, 0),
          expiresInSeconds: 86400,
        ),
      ),
    );

    expect(connected.traktAccount?.username, 'cherif');
    expect(connected.traktAccount?.accessToken, 'access-token');

    final persisted = (await repository.fetchProfiles()).single;
    expect(persisted.traktAccount?.username, 'cherif');
    expect(persisted.traktAccount?.refreshToken, 'refresh-token');
    expect(persisted.traktAccount?.expiresInSeconds, 86400);

    final rows = await database.query('profiles');
    expect(rows.single['trakt_access_token'], isNull);
    expect(rows.single['trakt_refresh_token'], isNull);
  });

  test('fetchProfiles migrates legacy plaintext Trakt tokens', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'cheriflix_profile_repo_',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    await _seedAvatarFiles(
      root: tempDirectory,
      defaultFiles: const <String>['default.png'],
    );

    final database = await CheriflixDatabase.open(
      databasePath: _databasePath(tempDirectory),
    );
    addTearDown(database.close);

    final credentialStore = MemoryTraktCredentialStore();
    await database.insert(
      'profiles',
      Profile(
        id: 'legacy',
        name: 'Legacy',
        avatarLabel: 'default.png',
        languageCode: 'en',
        maturityTier: MaturityTier.mature,
        createdAt: DateTime.utc(2026, 3, 28),
        traktAccount: TraktAccount(
          username: 'legacy-user',
          accessToken: 'legacy-access',
          refreshToken: 'legacy-refresh',
          tokenType: 'bearer',
          scope: 'public',
          tokenCreatedAt: DateTime.utc(2026, 3, 28, 10, 0),
          expiresInSeconds: 86400,
        ),
      ).toMap(),
    );

    final repository = SqliteProfileRepository(
      database,
      avatarCatalogService: ProfileAvatarCatalogService(
        searchRoots: <Directory>[tempDirectory],
      ),
      credentialStore: credentialStore,
    );

    final profile = (await repository.fetchProfiles()).single;
    expect(profile.traktAccount?.accessToken, 'legacy-access');
    expect(
      (await credentialStore.read('legacy'))?.refreshToken,
      'legacy-refresh',
    );

    final rows = await database.query('profiles');
    expect(rows.single['trakt_access_token'], isNull);
    expect(rows.single['trakt_refresh_token'], isNull);
  });
}

String _databasePath(Directory root) {
  return '${root.path}${Platform.pathSeparator}app.db';
}

Future<void> _seedAvatarFiles({
  required Directory root,
  required List<String> defaultFiles,
}) async {
  final profilePicturesRoot = Directory(
    '${root.path}${Platform.pathSeparator}profile-pictures',
  );
  final defaults = Directory(
    '${profilePicturesRoot.path}${Platform.pathSeparator}Default',
  );
  await defaults.create(recursive: true);

  for (final filename in defaultFiles) {
    final file = File('${defaults.path}${Platform.pathSeparator}$filename');
    await file.writeAsBytes(const <int>[137, 80, 78, 71], flush: true);
  }

  final extra =
      File('${profilePicturesRoot.path}${Platform.pathSeparator}extra.png');
  await extra.writeAsBytes(const <int>[137, 80, 78, 71], flush: true);
}
