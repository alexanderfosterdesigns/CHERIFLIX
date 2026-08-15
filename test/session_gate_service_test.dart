import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/services/session_gate_service.dart';

void main() {
  group('SessionGateService', () {
    const service = SessionGateService(ttl: Duration(hours: 24));

    test('shows the gate when there is no stored unlock timestamp', () {
      expect(
        service.shouldShowGate(
          now: DateTime.utc(2026, 3, 7, 10),
          lastUnlockedAt: null,
        ),
        isTrue,
      );
    });

    test('skips the gate within 24 hours', () {
      expect(
        service.shouldShowGate(
          now: DateTime.utc(2026, 3, 7, 10),
          lastUnlockedAt: DateTime.utc(2026, 3, 6, 12, 1),
        ),
        isFalse,
      );
    });

    test('shows the gate at or after the 24-hour TTL', () {
      expect(
        service.shouldShowGate(
          now: DateTime.utc(2026, 3, 7, 10),
          lastUnlockedAt: DateTime.utc(2026, 3, 6, 10),
        ),
        isTrue,
      );
    });
  });
}
