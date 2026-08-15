class SessionGateService {
  const SessionGateService({this.ttl = const Duration(minutes: 5)});

  final Duration ttl;

  bool shouldShowGate({
    required DateTime now,
    required DateTime? lastUnlockedAt,
  }) {
    if (lastUnlockedAt == null) {
      return true;
    }

    return now.toUtc().difference(lastUnlockedAt.toUtc()) >= ttl;
  }

  DateTime expiresAt(DateTime lastUnlockedAt) {
    return lastUnlockedAt.toUtc().add(ttl);
  }
}
