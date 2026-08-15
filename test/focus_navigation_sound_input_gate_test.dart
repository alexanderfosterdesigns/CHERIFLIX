import 'package:cheriflix/app/cheriflix_app.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('focus sound gate only opens for recent user navigation input', () {
    var now = DateTime.utc(2026, 1, 1);
    final gate = FocusNavigationSoundInputGate(clock: () => now);

    expect(gate.hasRecentUserInput, isFalse);

    gate.markDirectionalKey(LogicalKeyboardKey.escape);
    expect(gate.hasRecentUserInput, isFalse);

    gate.markDirectionalKey(LogicalKeyboardKey.arrowRight);
    expect(gate.hasRecentUserInput, isTrue);

    now = now.add(const Duration(milliseconds: 351));
    expect(gate.hasRecentUserInput, isFalse);

    gate.markUserInput();
    expect(gate.hasRecentUserInput, isTrue);
  });
}
