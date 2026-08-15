import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/maturity_tier.dart';
import 'package:cheriflix/core/models/profile.dart';
import 'package:cheriflix/features/profile/profile_selection_screen.dart';

void main() {
  testWidgets('ProfileSelectionScreen selects the first profile on enter',
      (tester) async {
    Profile? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileSelectionScreen(
          profiles: <Profile>[_profile()],
          onSelectProfile: (profile) => selected = profile,
          onCreateProfile: () {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(selected?.id, 'p1');
  });

  testWidgets('ProfileSelectionScreen opens create flow from plus tile',
      (tester) async {
    var createOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileSelectionScreen(
          profiles: <Profile>[_profile()],
          onSelectProfile: (_) {},
          onCreateProfile: () => createOpened = true,
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(createOpened, isTrue);
  });

  testWidgets('ProfileSelectionScreen autofocuses plus tile when empty',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileSelectionScreen(
          profiles: const <Profile>[],
          onSelectProfile: (_) {},
          onCreateProfile: () {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('CreateProfile'),
    );
  });

  testWidgets(
      'ProfileSelectionScreen renders the compact TV layout without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(2560, 1440);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileSelectionScreen(
          profiles: <Profile>[_profile()],
          onSelectProfile: (_) {},
          onCreateProfile: () {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Who\'s watching?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Profile _profile() {
  return Profile(
    id: 'p1',
    name: 'Cherif',
    avatarLabel: 'C',
    languageCode: 'en',
    maturityTier: MaturityTier.mature,
    createdAt: DateTime.utc(2026, 3, 8),
  );
}
