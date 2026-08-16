import 'package:cheriflix/core/theme/cheriflix_theme.dart';
import 'package:cheriflix/core/theme/tv_layout.dart';
import 'package:cheriflix/core/widgets/tv_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('media cards stay cinematic at every TV width tier', () {
    for (final width in <double>[960, 1280, 1920]) {
      final layout = CheriflixTvLayout.fromWidth(width);
      expect(
        layout.homeRailCardWidth / layout.homeRailCardPosterHeight,
        closeTo(CheriflixTvLayout.mediaCardAspectRatio, 0.001),
      );
      expect(layout.homeRailCardWidth,
          greaterThan(layout.homeRailCardPosterHeight));
    }
  });

  testWidgets('light action buttons always use dark high-contrast ink',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCheriflixTheme(),
        home: Scaffold(
          body: Center(
            child: TvActionButton(
              label: 'Continue',
              icon: Icons.play_arrow_rounded,
              onPressed: () {},
              variant: TvButtonVariant.light,
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    final label = tester.widget<Text>(find.text('Continue'));
    final icon = tester.widget<Icon>(find.byIcon(Icons.play_arrow_rounded));
    expect(label.style?.color, CheriflixColors.inkOnLight);
    expect(icon.color, CheriflixColors.inkOnLight);
  });
}
