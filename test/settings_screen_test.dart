import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/maturity_tier.dart';
import 'package:cheriflix/core/models/profile.dart';
import 'package:cheriflix/core/models/profile_playback_settings.dart';
import 'package:cheriflix/core/widgets/tv_shortcuts.dart';
import 'package:cheriflix/features/settings/settings_screen.dart';

void main() {
  testWidgets('SettingsScreen edits profile names with the TV keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          activeProfile: Profile(
            id: 'profile-1',
            name: 'Cherif',
            avatarLabel: 'C',
            languageCode: 'en',
            maturityTier: MaturityTier.mature,
            createdAt: DateTime.utc(2026, 4, 3),
          ),
          playbackSettings: const ProfilePlaybackSettings(languageCode: 'en'),
          hideSpoilers: false,
          onHideSpoilersChanged: (_) {},
          onBack: () {},
          onSaveProfile: (_) {},
          onSavePlaybackSettings: (_) {},
          onCheckForUpdates: () async {},
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('settings_profile_name')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit Profile Name'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'TvTextEditorKey(0,0)',
    );

    final doneButton = tester.widget<TvActionButton>(
      find.widgetWithText(TvActionButton, 'Done'),
    );
    doneButton.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'TvTextEditorKey(4,0)',
    );

    await tester.tap(find.widgetWithText(TvActionButton, 'CLR'));
    await tester.tap(find.widgetWithText(TvActionButton, 'A'));
    await tester.tap(find.widgetWithText(TvActionButton, 'B'));
    await tester.tap(find.widgetWithText(TvActionButton, 'Done'));
    await tester.pumpAndSettle();

    expect(find.text('NAME  ·  AB'), findsOneWidget);
  });

  testWidgets(
    'SettingsScreen toggles hide trailers immediately and saves each change',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final savedSettings = <ProfilePlaybackSettings>[];

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            activeProfile: Profile(
              id: 'profile-1',
              name: 'Cherif',
              avatarLabel: 'C',
              languageCode: 'en',
              maturityTier: MaturityTier.mature,
              createdAt: DateTime.utc(2026, 4, 3),
            ),
            playbackSettings: const ProfilePlaybackSettings(
              languageCode: 'en',
              autoplayNextEpisode: true,
              autoplayPreviews: true,
              muteAutoplayTrailers: true,
            ),
            hideSpoilers: false,
            onHideSpoilersChanged: (_) {},
            onBack: () {},
            onSaveProfile: (_) {},
            onSavePlaybackSettings: savedSettings.add,
            onCheckForUpdates: () async {},
          ),
        ),
      );

      expect(find.text('Hide trailers: OFF'), findsOneWidget);

      await tester.tap(find.text('Hide trailers: OFF'));
      await tester.pump();

      expect(find.text('Hide trailers: ON'), findsOneWidget);
      expect(savedSettings, isNotEmpty);
      expect(savedSettings.last.autoplayPreviews, isFalse);

      await tester.tap(find.text('Hide trailers: ON'));
      await tester.pump();

      expect(find.text('Hide trailers: OFF'), findsOneWidget);
      expect(savedSettings.last.autoplayPreviews, isTrue);
    },
  );

  testWidgets(
    'SettingsScreen renders the compact TV layout without clipping',
    (tester) async {
      tester.view.physicalSize = const Size(2560, 1440);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            activeProfile: Profile(
              id: 'profile-1',
              name: 'Cherif',
              avatarLabel: 'C',
              languageCode: 'en',
              maturityTier: MaturityTier.mature,
              createdAt: DateTime.utc(2026, 4, 3),
            ),
            playbackSettings: const ProfilePlaybackSettings(
              languageCode: 'en',
              autoplayNextEpisode: true,
              autoplayPreviews: true,
              muteAutoplayTrailers: true,
            ),
            hideSpoilers: false,
            onHideSpoilersChanged: (_) {},
            onBack: () {},
            onSaveProfile: (_) {},
            onSavePlaybackSettings: (_) {},
            onCheckForUpdates: () async {},
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Autoplay controls'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
