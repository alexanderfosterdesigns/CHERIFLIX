import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/media_type.dart';
import 'package:cheriflix/core/services/source_health_store.dart';

void main() {
  test('provider history is isolated between movies and television', () {
    final store = SourceHealthStore();
    for (var index = 0; index < 3; index += 1) {
      store.recordFailure(
        profileId: 'p',
        tmdbId: 10 + index,
        mediaType: MediaType.movie,
        providerIndex: 17,
        kind: SourceFailureKind.startupStall,
      );
    }

    expect(
      store.priorityScore(17, MediaType.movie),
      greaterThan(store.priorityScore(17, MediaType.tv)),
    );
  });

  test('a title cooldown never blacklists another title', () {
    final store = SourceHealthStore();
    store.recordFailure(
      profileId: 'p',
      tmdbId: 10,
      mediaType: MediaType.movie,
      providerIndex: 17,
      kind: SourceFailureKind.validation,
    );

    expect(
      store.cooldownRemaining(
        profileId: 'p',
        tmdbId: 10,
        mediaType: MediaType.movie,
        providerIndex: 17,
      ),
      isNotNull,
    );
    expect(
      store.cooldownRemaining(
        profileId: 'p',
        tmdbId: 11,
        mediaType: MediaType.movie,
        providerIndex: 17,
      ),
      isNull,
    );
  });

  test('performance history can be persisted and restored', () {
    final original = SourceHealthStore();
    original.recordSuccess(
      profileId: 'p',
      tmdbId: 10,
      mediaType: MediaType.tv,
      providerIndex: 23,
      startupDuration: const Duration(seconds: 8),
    );
    final restored = SourceHealthStore(persistedState: original.toJson());

    expect(
      restored.priorityScore(23, MediaType.tv),
      closeTo(original.priorityScore(23, MediaType.tv), 0.001),
    );
    expect(restored.priorityScore(23, MediaType.movie), 3500);
  });
}
