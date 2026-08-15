import 'package:flutter/material.dart';

import '../../core/models/media_summary.dart';
import '../../core/models/playback_progress_entry.dart';
import '../../core/models/playback_progress_snapshot.dart';
import '../../core/models/profile.dart';
import '../../core/services/media_catalog_service.dart';
import '../../core/services/tmdb_media_catalog_service.dart';
import '../../core/widgets/cheriflix_chrome.dart';
import '../../core/widgets/playback_progress_bar.dart';
import '../../core/widgets/tv_shortcuts.dart';
import '../../core/theme/cheriflix_theme.dart';
import '../../core/theme/tv_layout.dart';

class MyListScreen extends StatefulWidget {
  const MyListScreen({
    super.key,
    required this.activeProfile,
    required this.savedTitles,
    required this.playbackProgress,
    required this.mediaCatalogService,
    required this.languageCode,
    required this.autoplayPreviews,
    required this.muteAutoplayTrailers,
    required this.onOpenTitle,
    this.onPlayTitle,
    required this.onToggleSaved,
    this.onBack,
    this.onBrowseHome,
    this.onBrowseTvShows,
    this.onBrowseMovies,
    this.onBrowseNewPopular,
    this.onOpenSearch,
    this.onOpenSettings,
    this.onSwitchProfile,
  });

  final Profile activeProfile;
  final List<MediaSummary> savedTitles;
  final PlaybackProgressSnapshot playbackProgress;
  final MediaCatalogService? mediaCatalogService;
  final String languageCode;
  final bool autoplayPreviews;
  final bool muteAutoplayTrailers;
  final ValueChanged<MediaSummary> onOpenTitle;
  final ValueChanged<MediaSummary>? onPlayTitle;
  final ValueChanged<MediaSummary> onToggleSaved;
  final VoidCallback? onBack;
  final VoidCallback? onBrowseHome;
  final VoidCallback? onBrowseTvShows;
  final VoidCallback? onBrowseMovies;
  final VoidCallback? onBrowseNewPopular;
  final VoidCallback? onOpenSearch;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onSwitchProfile;

  @override
  State<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends State<MyListScreen> {
  static const double _expandedPosterAspectRatio = 16 / 9;

  CheriflixTvLayout get _layout => CheriflixTvLayout.of(context);
  double get _cardWidth => _layout.homeRailCardWidth;
  double get _cardPosterHeight => _layout.homeRailCardPosterHeight;
  double get _expandedPosterHeight => _layout.homeRailExpandedPosterHeight;
  double get _expandedWidth =>
      _expandedPosterHeight * _expandedPosterAspectRatio;
  double get _cardGap => _layout.homeRailGap;
  double get _collapsedDetailsTopPadding =>
      _layout.value(compact: 10, standard: 11, wide: 12);
  double get _collapsedTitleHeight => _layout.homeRailCollapsedTitleHeight;
  double get _collapsedSubtitleHeight =>
      _layout.homeRailCollapsedSubtitleHeight;
  double get _collapsedDetailsSpacing =>
      _layout.value(compact: 3, standard: 4, wide: 4);
  double get _railHeightBuffer =>
      _layout.value(compact: 6, standard: 7, wide: 8);
  double get _collapsedDetailsHeight =>
      _collapsedDetailsTopPadding +
      _collapsedTitleHeight +
      _collapsedDetailsSpacing +
      _collapsedSubtitleHeight;
  double get _railHeight =>
      _cardPosterHeight + _collapsedDetailsHeight + _railHeightBuffer;

  late final FocusNode _firstContinueFocusNode =
      FocusNode(debugLabel: 'MyListFirstContinue');
  late final FocusNode _firstCompletedFocusNode =
      FocusNode(debugLabel: 'MyListFirstCompleted');
  late final FocusNode _firstSavedFocusNode =
      FocusNode(debugLabel: 'MyListFirstSaved');

  @override
  void dispose() {
    _firstContinueFocusNode.dispose();
    _firstCompletedFocusNode.dispose();
    _firstSavedFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = _layout;
    final continueWatching = widget.playbackProgress.continueWatchingEntries;
    final alreadyWatched = widget.playbackProgress.alreadyWatchedEntries;
    final savedTitles = widget.savedTitles;
    final hasContent = continueWatching.isNotEmpty ||
        alreadyWatched.isNotEmpty ||
        savedTitles.isNotEmpty;
    final firstContentFocusNode = continueWatching.isNotEmpty
        ? _firstContinueFocusNode
        : alreadyWatched.isNotEmpty
            ? _firstCompletedFocusNode
            : savedTitles.isNotEmpty
                ? _firstSavedFocusNode
                : null;

    return TvShortcutScope(
      onBack: widget.onBack,
      child: CheriflixScaffold(
        topBar: CheriflixTopBar(
          activeTab: 'My List',
          profile: widget.activeProfile,
          downFallbackNodes: firstContentFocusNode == null
              ? const <FocusNode>[]
              : <FocusNode>[firstContentFocusNode],
          onHome: widget.onBrowseHome,
          onTvShows: widget.onBrowseTvShows,
          onMovies: widget.onBrowseMovies,
          onNewPopular: widget.onBrowseNewPopular,
          onSearch: widget.onOpenSearch,
          onSettings: widget.onOpenSettings,
          onProfiles: widget.onSwitchProfile,
        ),
        body: Padding(
          padding: EdgeInsets.fromLTRB(
            layout.pagePadding.left,
            layout.value(compact: 12, standard: 14, wide: 16),
            layout.pagePadding.right,
            layout.pagePadding.bottom,
          ),
          child: !hasContent
              ? const _MyListEmptyState()
              : ListView(
                  children: <Widget>[
                    Text(
                      'My List',
                      style: CheriflixTypography.sectionTitle.copyWith(
                        fontSize: layout.sectionTitleSize,
                      ),
                    ),
                    SizedBox(
                      height: layout.value(compact: 8, standard: 9, wide: 10),
                    ),
                    Text(
                      'Saved titles, in-progress playback, and completed watches stay attached to this profile so you can jump back in anytime.',
                      style: CheriflixTypography.body.copyWith(
                        fontSize: layout.bodySize,
                      ),
                    ),
                    SizedBox(
                      height: layout.value(compact: 22, standard: 24, wide: 28),
                    ),
                    if (continueWatching.isNotEmpty)
                      _buildSection(
                        title: 'Continue Watching',
                        sectionKey: 'continue',
                        cards: continueWatching
                            .map(_MyListRailCardData.fromProgress)
                            .toList(growable: false),
                        firstFocusNode: _firstContinueFocusNode,
                      ),
                    if (continueWatching.isNotEmpty &&
                        (alreadyWatched.isNotEmpty || savedTitles.isNotEmpty))
                      SizedBox(
                        height: layout.value(
                          compact: 24,
                          standard: 26,
                          wide: 30,
                        ),
                      ),
                    if (alreadyWatched.isNotEmpty)
                      _buildSection(
                        title: 'Already Watched',
                        sectionKey: 'watched',
                        cards: alreadyWatched
                            .map(_MyListRailCardData.fromProgress)
                            .toList(growable: false),
                        firstFocusNode: _firstCompletedFocusNode,
                      ),
                    if (alreadyWatched.isNotEmpty && savedTitles.isNotEmpty)
                      SizedBox(
                        height: layout.value(
                          compact: 24,
                          standard: 26,
                          wide: 30,
                        ),
                      ),
                    if (savedTitles.isNotEmpty)
                      _buildSection(
                        title: 'Saved Titles',
                        sectionKey: 'saved',
                        cards: savedTitles
                            .map(_MyListRailCardData.fromSummary)
                            .toList(growable: false),
                        firstFocusNode: _firstSavedFocusNode,
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required String sectionKey,
    required List<_MyListRailCardData> cards,
    required FocusNode firstFocusNode,
  }) {
    final layout = _layout;
    final savedTitleKeys =
        widget.savedTitles.map((item) => item.saveKey).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: CheriflixTypography.sectionTitle.copyWith(
            fontSize: layout.sectionTitleSize,
          ),
        ),
        SizedBox(height: layout.value(compact: 10, standard: 11, wide: 12)),
        SizedBox(
          height: _railHeight,
          child: ListView.separated(
            clipBehavior: Clip.none,
            physics: const ClampingScrollPhysics(),
            scrollDirection: Axis.horizontal,
            cacheExtent: _cardWidth * 3,
            padding: EdgeInsets.zero,
            itemCount: cards.length,
            separatorBuilder: (_, __) => SizedBox(width: _cardGap),
            itemBuilder: (context, index) {
              final item = cards[index];
              return TvPosterButton(
                key: ValueKey<String>(
                  'my_list_${sectionKey}_${item.summary.saveKey}_$index',
                ),
                title: item.title,
                subtitle: item.subtitle,
                imageUrl: item.imageUrl,
                posterSurfaceKey: ValueKey<String>(
                  'my_list_surface_${sectionKey}_${item.summary.saveKey}_$index',
                ),
                width: _cardWidth,
                posterHeight: _cardPosterHeight,
                expandedWidth: _expandedWidth,
                expandedPosterHeight: _expandedPosterHeight,
                alignment: Alignment.bottomLeft,
                expandOnFocus: true,
                ensureVisibleOnFocus: false,
                reserveExpandedSpace: true,
                overlayExpandedDetails: true,
                autoplayPreviewEnabled: widget.autoplayPreviews,
                autoplayPreviewMuted: widget.muteAutoplayTrailers,
                previewLoadDelay: const Duration(milliseconds: 1800),
                expandedImageUrl: item.summary.backdropUrl ?? item.imageUrl,
                previewLoader: () => _loadPreviewUri(
                  item.summary,
                  muted: widget.muteAutoplayTrailers,
                ),
                saved: savedTitleKeys.contains(item.summary.saveKey),
                posterBottomOverlay: item.progress == null
                    ? null
                    : PlaybackProgressBar(
                        value: item.progress!.progressFraction,
                        height: 6,
                      ),
                focusNode: index == 0 ? firstFocusNode : null,
                onPressed: item.progress != null && widget.onPlayTitle != null
                    ? () => widget.onPlayTitle!(item.summary)
                    : () => widget.onOpenTitle(item.summary),
                onPlay: () =>
                    (widget.onPlayTitle ?? widget.onOpenTitle)(item.summary),
                onOpenInfo: () => widget.onOpenTitle(item.summary),
                onToggleSaved: () => widget.onToggleSaved(item.summary),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<Uri?> _loadPreviewUri(
    MediaSummary item, {
    required bool muted,
  }) async {
    final service = _tmdbCatalogService;
    if (service == null) {
      return null;
    }
    return service.fetchTrailerPreviewUri(
      tmdbId: item.tmdbId,
      mediaType: item.mediaType,
      languageCode: widget.languageCode,
      muted: muted,
    );
  }

  TmdbMediaCatalogService? get _tmdbCatalogService {
    final service = widget.mediaCatalogService;
    if (service is TmdbMediaCatalogService) {
      return service;
    }
    return null;
  }
}

class _MyListRailCardData {
  const _MyListRailCardData({
    required this.summary,
    required this.title,
    required this.subtitle,
    this.progress,
  });

  factory _MyListRailCardData.fromSummary(MediaSummary summary) {
    return _MyListRailCardData(
      summary: summary,
      title: summary.title,
      subtitle: summary.metadataLabel,
    );
  }

  factory _MyListRailCardData.fromProgress(PlaybackProgressEntry progress) {
    return _MyListRailCardData(
      summary: progress.summary,
      title: progress.displayTitle,
      subtitle: progress.displaySubtitle,
      progress: progress,
    );
  }

  final MediaSummary summary;
  final String title;
  final String subtitle;
  final PlaybackProgressEntry? progress;

  String? get imageUrl =>
      progress?.artworkUrl ?? summary.posterUrl ?? summary.backdropUrl;
}

class _MyListEmptyState extends StatelessWidget {
  const _MyListEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: CheriflixPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const <Widget>[
              CheriflixSectionTitle(title: 'My List'),
              SizedBox(height: 12),
              Text(
                'Save titles from Home, Search, or the detail view, then start watching to build your Continue Watching and Already Watched sections here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF999999),
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
