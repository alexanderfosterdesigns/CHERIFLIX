import '../models/maturity_tier.dart';

class MaturityPolicy {
  const MaturityPolicy._();

  static bool allows(String? certification, MaturityTier tier) {
    if (tier == MaturityTier.mature) return true;
    final rating = certification?.trim().toUpperCase();
    // Unknown content is deliberately hidden on restrictive profiles.
    if (rating == null ||
        rating.isEmpty ||
        rating == 'NR' ||
        rating == 'UNRATED') {
      return false;
    }
    final level = _levels[rating];
    if (level == null) return false;
    return switch (tier) {
      MaturityTier.kids => level <= 1,
      MaturityTier.teen => level <= 2,
      MaturityTier.mature => true,
    };
  }

  static const Map<String, int> _levels = <String, int>{
    'G': 0,
    'TV-Y': 0,
    'TV-Y7': 0,
    'TV-G': 0,
    'U': 0,
    'PG': 1,
    'TV-PG': 1,
    '7': 1,
    '9': 1,
    'PG-13': 2,
    'TV-14': 2,
    'M': 2,
    '12': 2,
    '12A': 2,
    '15': 2,
    'R': 3,
    'TV-MA': 3,
    'MA15+': 3,
    'R18+': 3,
    '18': 3,
    'NC-17': 3,
    'X18+': 3,
  };
}
