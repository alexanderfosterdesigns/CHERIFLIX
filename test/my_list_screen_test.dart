import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cheriflix/core/models/maturity_tier.dart';
import 'package:cheriflix/core/models/media_summary.dart';
import 'package:cheriflix/core/models/media_type.dart';
import 'package:cheriflix/core/models/playback_progress_entry.dart';
import 'package:cheriflix/core/models/playback_progress_snapshot.dart';
import 'package:cheriflix/core/models/profile.dart';
import 'package:cheriflix/core/theme/tv_layout.dart';
import 'package:cheriflix/core/widgets/playback_progress_bar.dart';
import 'package:cheriflix/core/widgets/tv_shortcuts.dart';
import 'package:cheriflix/features/my_list/my_list_screen.dart';

void main() {
  testWidgets('MyListScreen splits continue watching and already watched',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final show = MediaSummary(
      tmdbId: 101,
      mediaType: MediaType.tv,
      title: 'The Rookie',
    );
    final completedMovie = MediaSummary(
      tmdbId: 202,
      mediaType: MediaType.movie,
      title: 'Dune',
    );
    final savedMovie = MediaSummary(
      tmdbId: 303,
      mediaType: MediaType.movie,
      title: 'Carry-On',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MyListScreen(
          activeProfile: Profile(
            id: 'p1',
            name: 'Cherif',
            avatarLabel: 'C',
            languageCode: 'en',
            maturityTier: MaturityTier.mature,
            createdAt: DateTime.utc(2026, 3, 8),
          ),
          savedTitles: <MediaSummary>[show, savedMovie],
          playbackProgress: PlaybackProgressSnapshot(
            <PlaybackProgressEntry>[
              PlaybackProgressEntry(
                summary: show,
                seasonNumber: 1,
                episodeNumber: 3,
                episodeTitle: 'The Bet',
                position: const Duration(minutes: 18),
                totalDuration: const Duration(minutes: 43),
                updatedAt: DateTime.utc(2026, 3, 12),
              ),
              PlaybackProgressEntry(
                summary: completedMovie,
                position: const Duration(minutes: 155),
                totalDuration: const Duration(minutes: 155),
                updatedAt: DateTime.utc(2026, 3, 11),
              ),
            ],
          ),
          mediaCatalogService: null,
          languageCode: 'en',
          autoplayPreviews: true,
          muteAutoplayTrailers: true,
          onOpenTitle: (_) {},
          onPlayTitle: (_) {},
          onToggleSaved: (_) {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Continue Watching'), findsOneWidget);
    expect(find.text('Already Watched'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('my_list_continue_tv:101_0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('my_list_watched_movie:202_0')),
      findsOneWidget,
    );
    expect(find.byType(PlaybackProgressBar), findsNWidgets(2));

    await tester.dragUntilVisible(
      find.text('Saved Titles'),
      find.byType(ListView).first,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();

    expect(find.text('Saved Titles'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('my_list_saved_tv:101_0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('my_list_saved_movie:303_1')),
      findsOneWidget,
    );
  });

  testWidgets('MyListScreen plays continue watching cards directly',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final show = MediaSummary(
      tmdbId: 101,
      mediaType: MediaType.tv,
      title: 'The Rookie',
    );
    final savedMovie = MediaSummary(
      tmdbId: 303,
      mediaType: MediaType.movie,
      title: 'Carry-On',
    );
    MediaSummary? openedTitle;
    MediaSummary? playedTitle;

    await tester.pumpWidget(
      MaterialApp(
        home: MyListScreen(
          activeProfile: Profile(
            id: 'p1',
            name: 'Cherif',
            avatarLabel: 'C',
            languageCode: 'en',
            maturityTier: MaturityTier.mature,
            createdAt: DateTime.utc(2026, 3, 8),
          ),
          savedTitles: <MediaSummary>[show, savedMovie],
          playbackProgress: PlaybackProgressSnapshot(
            <PlaybackProgressEntry>[
              PlaybackProgressEntry(
                summary: show,
                seasonNumber: 1,
                episodeNumber: 3,
                episodeTitle: 'The Bet',
                position: const Duration(minutes: 18),
                totalDuration: const Duration(minutes: 43),
                updatedAt: DateTime.utc(2026, 3, 12),
              ),
            ],
          ),
          mediaCatalogService: null,
          languageCode: 'en',
          autoplayPreviews: true,
          muteAutoplayTrailers: true,
          onOpenTitle: (value) => openedTitle = value,
          onPlayTitle: (value) => playedTitle = value,
          onToggleSaved: (_) {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    tester
        .widget<TvPosterButton>(
          find.byKey(
            const ValueKey<String>('my_list_continue_tv:101_0'),
            skipOffstage: false,
          ),
        )
        .onPressed();
    await tester.pump();

    expect(playedTitle?.tmdbId, 101);
    expect(openedTitle, isNull);

    playedTitle = null;
    tester
        .widget<TvPosterButton>(
          find.byKey(
            const ValueKey<String>('my_list_saved_movie:303_1'),
            skipOffstage: false,
          ),
        )
        .onPressed();
    await tester.pump();

    expect(openedTitle?.tmdbId, 303);
    expect(playedTitle, isNull);
  });

  testWidgets('MyListScreen uses the shared home rail sizing on TV layouts',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final show = MediaSummary(
      tmdbId: 101,
      mediaType: MediaType.tv,
      title: 'The Rookie',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MyListScreen(
          activeProfile: Profile(
            id: 'p1',
            name: 'Cherif',
            avatarLabel: 'C',
            languageCode: 'en',
            maturityTier: MaturityTier.mature,
            createdAt: DateTime.utc(2026, 3, 8),
          ),
          savedTitles: const <MediaSummary>[],
          playbackProgress: PlaybackProgressSnapshot(
            <PlaybackProgressEntry>[
              PlaybackProgressEntry(
                summary: show,
                seasonNumber: 1,
                episodeNumber: 3,
                episodeTitle: 'The Bet',
                position: const Duration(minutes: 18),
                totalDuration: const Duration(minutes: 43),
                updatedAt: DateTime.utc(2026, 3, 12),
              ),
            ],
          ),
          mediaCatalogService: null,
          languageCode: 'en',
          autoplayPreviews: true,
          muteAutoplayTrailers: true,
          onOpenTitle: (_) {},
          onPlayTitle: (_) {},
          onToggleSaved: (_) {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    final layout = CheriflixTvLayout.of(
      tester.element(find.byType(MyListScreen)),
    );
    final card = tester.widget<TvPosterButton>(
      find.byKey(const ValueKey<String>('my_list_continue_tv:101_0')),
    );

    expect(card.width, layout.homeRailCardWidth);
    expect(card.posterHeight, layout.homeRailCardPosterHeight);
    expect(card.expandedPosterHeight, layout.homeRailExpandedPosterHeight);
  });
}
