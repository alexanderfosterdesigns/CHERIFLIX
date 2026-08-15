import 'package:cheriflix/features/splash/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'arms the finish timer when loading splash becomes branded splash',
    (tester) async {
      var finishedCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            loadingOnly: true,
            onFinished: () {
              finishedCount += 1;
            },
          ),
        ),
      );

      await tester.pump(const Duration(seconds: 3));
      expect(finishedCount, 0);

      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            onFinished: () {
              finishedCount += 1;
            },
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 1599));
      expect(finishedCount, 0);

      await tester.pump(const Duration(milliseconds: 1));
      expect(finishedCount, 1);
    },
  );
}
