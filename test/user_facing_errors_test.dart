import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/utils/user_facing_errors.dart';

void main() {
  test('userFacingErrorMessage collapses verbose preview errors', () {
    final message = userFacingErrorMessage(
      Exception(
        'Webpage not available http://127.0.0.1:39595/preview_shell.html?src=https://www.youtube-nocookie.com/embed/abc',
      ),
      fallback: 'Preview failed.',
    );

    expect(message, 'Trailer preview unavailable right now.');
  });

  test('userFacingErrorMessage keeps readable short messages', () {
    final message = userFacingErrorMessage(
      Exception('Could not open the link on this device.'),
      fallback: 'Open failed.',
    );

    expect(message, 'Could not open the link on this device.');
  });
}
