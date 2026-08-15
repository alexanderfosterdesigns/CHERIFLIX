class CachedJsonEntry {
  const CachedJsonEntry({
    required this.payload,
    required this.fetchedAt,
  });

  final String payload;
  final DateTime fetchedAt;

  bool isFresh(Duration maxAge) {
    return DateTime.now().toUtc().difference(fetchedAt.toUtc()) < maxAge;
  }
}

abstract interface class JsonCacheStore {
  Future<CachedJsonEntry?> read({
    required String key,
  });

  Future<String?> readFresh({
    required String key,
    required Duration maxAge,
  });

  Future<void> write({
    required String key,
    required String payload,
  });
}
