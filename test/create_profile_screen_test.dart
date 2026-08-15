import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/profile.dart';
import 'package:cheriflix/core/services/profile_avatar_catalog.dart';
import 'package:cheriflix/core/widgets/tv_shortcuts.dart';
import 'package:cheriflix/features/profile/create_profile_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('CreateProfileScreen updates name from the on-screen keyboard',
      (tester) async {
    _setWideTestView(tester);
    final harness = await _avatarCatalogHarness();
    addTearDown(() async => harness.dispose());

    String? createdName;
    String? createdAvatar;

    await tester.pumpWidget(
      MaterialApp(
        home: CreateProfileScreen(
          profiles: const <Profile>[],
          avatarCatalogService: harness.service,
          onBack: () {},
          onCreateProfile: (name, avatarLabel) async {
            createdName = name;
            createdAvatar = avatarLabel;
          },
        ),
      ),
    );

    await _settleCreateProfileScreen(tester);
    await tester.tap(find.widgetWithText(TvActionButton, 'Done'));
    await tester.pump();
    expect(createdName, isNull);

    await tester.tap(find.text('A').first);
    await tester.pump();
    await tester.tap(find.text('L').first);
    await tester.pump();
    await tester.tap(find.text('I').first);
    await tester.pump();

    expect(find.text('ALI'), findsOneWidget);

    await tester.tap(find.widgetWithText(TvActionButton, 'Done'));
    await tester.pump();

    expect(createdName, 'ALI');
    expect(createdAvatar, 'Default/default-one.png');
  });

  testWidgets('CreateProfileScreen utility keys edit the current name',
      (tester) async {
    _setWideTestView(tester);
    final harness = await _avatarCatalogHarness();
    addTearDown(() async => harness.dispose());

    await tester.pumpWidget(
      MaterialApp(
        home: CreateProfileScreen(
          profiles: const <Profile>[],
          avatarCatalogService: harness.service,
          onBack: () {},
          onCreateProfile: (_, __) async {},
        ),
      ),
    );

    await _settleCreateProfileScreen(tester);
    await tester.tap(find.text('A').first);
    await tester.pump();
    await tester.tap(find.text('SP').first);
    await tester.pump();
    await tester.tap(find.text('B').first);
    await tester.pump();
    expect(find.text('A B'), findsOneWidget);

    await tester.tap(find.text('DEL').first);
    await tester.pump();
    expect(find.text('A '), findsOneWidget);

    await tester.tap(find.text('CLR').first);
    await tester.pump();
    expect(find.text('Use the on-screen keyboard'), findsOneWidget);
  });

  testWidgets('CreateProfileScreen submits the selected avatar',
      (tester) async {
    _setWideTestView(tester);
    final harness = await _avatarCatalogHarness();
    addTearDown(() async => harness.dispose());

    String? createdAvatar;

    await tester.pumpWidget(
      MaterialApp(
        home: CreateProfileScreen(
          profiles: const <Profile>[],
          avatarCatalogService: harness.service,
          onBack: () {},
          onCreateProfile: (_, avatarLabel) async {
            createdAvatar = avatarLabel;
          },
        ),
      ),
    );

    await _settleCreateProfileScreen(tester);
    await tester
        .tap(find.widgetWithText(TvActionButton, 'Select Profile Picture'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey<String>('AvatarTile:alt-avatar.png')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Z').first);
    await tester.pump();
    await tester.tap(find.widgetWithText(TvActionButton, 'Done'));
    await tester.pump();

    expect(createdAvatar, 'alt-avatar.png');
  });

  testWidgets('CreateProfileScreen calls back on Back without creating',
      (tester) async {
    _setWideTestView(tester);
    final harness = await _avatarCatalogHarness();
    addTearDown(() async => harness.dispose());

    var backInvoked = false;
    var createInvoked = false;

    await tester.pumpWidget(
      MaterialApp(
        home: CreateProfileScreen(
          profiles: const <Profile>[],
          avatarCatalogService: harness.service,
          onBack: () => backInvoked = true,
          onCreateProfile: (_, __) async => createInvoked = true,
        ),
      ),
    );

    await _settleCreateProfileScreen(tester);
    await tester.tap(find.widgetWithText(TvActionButton, 'Back'));
    await tester.pump();

    expect(backInvoked, isTrue);
    expect(createInvoked, isFalse);
  });

  testWidgets(
      'CreateProfileScreen back closes the avatar picker before leaving profile creation',
      (tester) async {
    _setWideTestView(tester);
    final harness = await _avatarCatalogHarness();
    addTearDown(() async => harness.dispose());

    var backInvoked = false;

    await tester.pumpWidget(
      MaterialApp(
        home: CreateProfileScreen(
          profiles: const <Profile>[],
          avatarCatalogService: harness.service,
          onBack: () => backInvoked = true,
          onCreateProfile: (_, __) async {},
        ),
      ),
    );

    await _settleCreateProfileScreen(tester);
    await tester
        .tap(find.widgetWithText(TvActionButton, 'Select Profile Picture'));
    await tester.pumpAndSettle();

    expect(find.text('Choose Profile Picture'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Choose Profile Picture'), findsNothing);
    expect(backInvoked, isFalse);
    expect(find.text('Create Profile'), findsOneWidget);
  });

  testWidgets('CreateProfileScreen uses a centered TV-sized keypad',
      (tester) async {
    _setWideTestView(tester);
    final harness = await _avatarCatalogHarness();
    addTearDown(() async => harness.dispose());

    await tester.pumpWidget(
      MaterialApp(
        home: CreateProfileScreen(
          profiles: const <Profile>[],
          avatarCatalogService: harness.service,
          onBack: () {},
          onCreateProfile: (_, __) async {},
        ),
      ),
    );

    await _settleCreateProfileScreen(tester);

    final keyboard = find.byKey(
      const ValueKey<String>('create_profile_keyboard'),
    );
    final keyboardRect = tester.getRect(keyboard);
    final firstKeySize = tester.getSize(
      find.widgetWithText(TvActionButton, 'A'),
    );

    expect(keyboardRect.width, lessThanOrEqualTo(780.1));
    expect(keyboardRect.width, greaterThan(700));
    expect(keyboardRect.center.dx, closeTo(800, 1));
    expect(firstKeySize.width, inInclusiveRange(85, 140));
    expect(firstKeySize.height, lessThanOrEqualTo(42));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'CreateProfileScreen keeps the compact TV layout stable at high DPR',
      (tester) async {
    _setCompactHighDprTestView(tester);
    final harness = await _avatarCatalogHarness();
    addTearDown(() async => harness.dispose());

    await tester.pumpWidget(
      MaterialApp(
        home: CreateProfileScreen(
          profiles: const <Profile>[],
          avatarCatalogService: harness.service,
          onBack: () {},
          onCreateProfile: (_, __) async {},
        ),
      ),
    );

    await _settleCreateProfileScreen(tester);

    expect(find.text('Create Profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _setWideTestView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _setCompactHighDprTestView(WidgetTester tester) {
  tester.view.physicalSize = const Size(2560, 1440);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _settleCreateProfileScreen(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
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

  @override
  Future<ProfileAvatarOption?> resolveAvatarOption(String avatarLabel) async {
    final normalized = normalizeAvatarKey(avatarLabel);
    if (normalized == null) {
      return null;
    }
    return _catalog.byKeyLower[normalized.toLowerCase()];
  }

  @override
  Future<String?> pickRandomDefaultAvatarKey({
    required Set<String> usedAvatarLabels,
  }) async {
    return _defaultAvatar.key;
  }
}
