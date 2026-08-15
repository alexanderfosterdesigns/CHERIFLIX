import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/maturity_tier.dart';
import 'package:cheriflix/core/utils/maturity_policy.dart';
import 'package:cheriflix/core/utils/release_date_utils.dart';

void main() {
  group('release date policy', () {
    final now = DateTime(2026, 8, 14, 22, 30);

    test('today is released and tomorrow is upcoming', () {
      expect(isFutureRelease(DateTime(2026, 8, 14), now: now), isFalse);
      expect(isFutureRelease(DateTime(2026, 8, 15), now: now), isTrue);
      expect(isFutureRelease(null, now: now), isFalse);
    });

    test('release message uses the known calendar date', () {
      expect(
        comingSoonMessage(DateTime(2026, 9, 18), now: now),
        'Coming 18 September 2026',
      );
    });
  });

  group('maturity policy', () {
    test('restrictive profiles reject unknown ratings', () {
      expect(MaturityPolicy.allows(null, MaturityTier.kids), isFalse);
      expect(MaturityPolicy.allows('', MaturityTier.teen), isFalse);
    });

    test('certification thresholds use actual ratings', () {
      expect(MaturityPolicy.allows('G', MaturityTier.kids), isTrue);
      expect(MaturityPolicy.allows('PG-13', MaturityTier.kids), isFalse);
      expect(MaturityPolicy.allows('PG-13', MaturityTier.teen), isTrue);
      expect(MaturityPolicy.allows('MA15+', MaturityTier.teen), isFalse);
      expect(MaturityPolicy.allows(null, MaturityTier.mature), isTrue);
    });
  });
}
