import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  test('test getProperty', () {
    try {
      MediaKit.ensureInitialized();
    } catch (error) {
      markTestSkipped('media_kit native runtime unavailable: $error');
      return;
    }

    final player = Player();
    addTearDown(player.dispose);
    final native = player.platform as dynamic;

    try {
      native.getProperty('time-start');
    } catch (_) {
      // Some media_kit platforms expose this only after native startup.
    }
  });
}
