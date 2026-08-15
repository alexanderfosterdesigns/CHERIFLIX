import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/services/profile_avatar_catalog.dart';
import 'package:cheriflix/features/profile/profile_avatar_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ProfileAvatarPickerGallery selects an avatar tile',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final harness = await _avatarCatalogHarness();
    addTearDown(() async => harness.dispose());

    String? selectedAvatar;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: ProfileAvatarPickerGallery(
              selectedAvatarLabel: 'Default/default-one.png',
              avatarCatalogService: harness.service,
              requestInitialFocus: false,
              onSelect: (key) => selectedAvatar = key,
            ),
          ),
        ),
      ),
    );

    await _settleAvatarPicker(tester);
    await tester
        .tap(find.byKey(const ValueKey<String>('AvatarTile:alt-avatar.png')));
    await tester.pump();

    expect(selectedAvatar, 'alt-avatar.png');
  });

  testWidgets(
      'ProfileAvatarPickerGallery keeps the compact TV layout readable at high DPR',
      (tester) async {
    tester.view.physicalSize = const Size(2560, 1440);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final harness = await _avatarCatalogHarness();
    addTearDown(() async => harness.dispose());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 360,
            child: ProfileAvatarPickerGallery(
              selectedAvatarLabel: 'Default/default-one.png',
              avatarCatalogService: harness.service,
              requestInitialFocus: false,
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );

    await _settleAvatarPicker(tester);

    expect(find.text('Choose profile picture'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<_AvatarCatalogHarness> _avatarCatalogHarness() async {
  return _AvatarCatalogHarness(
    service: _FakeAvatarCatalogService(),
  );
}

class _AvatarCatalogHarness {
  _AvatarCatalogHarness({
    required this.service,
  });

  final ProfileAvatarCatalogService service;

  Future<void> dispose() async {}
}

Future<void> _settleAvatarPicker(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

class _FakeAvatarCatalogService extends ProfileAvatarCatalogService {
  _FakeAvatarCatalogService();

  static const ProfileAvatarOption _defaultAvatar = ProfileAvatarOption(
    key: 'Default/default-one.png',
    displayName: 'Default One',
    isDefault: true,
  );
  static const ProfileAvatarOption _altAvatar = ProfileAvatarOption(
    key: 'alt-avatar.png',
    displayName: 'Alt Avatar',
    isDefault: false,
  );
  static const ProfileAvatarCatalog _catalog = ProfileAvatarCatalog(
    defaultOptions: <ProfileAvatarOption>[_defaultAvatar],
    otherOptions: <ProfileAvatarOption>[_altAvatar],
    categories: <ProfileAvatarCategory>[
      ProfileAvatarCategory(
        id: 'misc',
        title: 'Misc',
        options: <ProfileAvatarOption>[_altAvatar],
      ),
    ],
    validationIssues: <String>[],
  );

  @override
  Future<ProfileAvatarCatalog> loadCatalog({bool refresh = false}) async {
    return _catalog;
  }
}
