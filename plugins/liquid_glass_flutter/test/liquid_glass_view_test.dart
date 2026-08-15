import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: avoid_relative_lib_imports
import '../lib/liquid_glass_flutter.dart';

void main() {
  testWidgets('renders child content with fallback glass', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: LiquidGlassView(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text('Glass'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Glass'), findsOneWidget);
  });
}
