import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/media_summary.dart';
import '../../core/models/media_type.dart';
import '../../core/models/playback_progress_entry.dart';
import '../../core/models/playback_progress_snapshot.dart';
import '../../core/models/profile.dart';
import '../../core/models/title_metadata.dart';
import '../../core/models/tmdb_title_logo.dart';
import '../../core/services/media_catalog_service.dart';
import '../../core/services/offline_download_manager.dart';
import '../../core/services/tmdb_image_service.dart';
import '../../core/services/tmdb_media_catalog_service.dart';
import '../../core/theme/cheriflix_theme.dart';
import '../../core/theme/tv_layout.dart';
import '../../core/widgets/cheriflix_chrome.dart';
import '../../core/widgets/cheriflix_network_image.dart';
import '../../core/widgets/cheriflix_title_mark.dart';
import '../../core/widgets/poster_preview_overlay.dart';
import '../../core/widgets/tv_shortcuts.dart';

class _InertListenable implements Listenable {
  const _InertListenable();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

@visibleForTesting
Size calculateTitleLogoSize({
  required int intrinsicWidth,
  required int intrinsicHeight,
  required double maxWidth,
  required double maxHeight,
}) {
  return calculateContainedTitleLogoSize(
    intrinsicWidth: intrinsicWidth,
    intrinsicHeight: intrinsicHeight,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
  );
}

class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.activeProfile,
    required this.summary,
    required this.languageCode,
    required this.onBack,
    required this.onPlay,
    required this.isSaved,
    required this.onToggleSaved,
    required this.playbackProgress,
    this.mediaCatalogService,
    this.onOpenEpisodes,
    this.onOpenTitleInfo,
    this.onOpenTitle,
    this.onPlayTitle,
    this.onToggleSavedTitle,
    this.savedTitleKeys = const <String>{},
    this.autoplayPreviews = true,
    this.muteAutoplayTrailers = true,
    this.onBrowseHome,
    this.onBrowseTvShows,
    this.onBrowseMovies,
    this.onBrowseNewPopular,
    this.onBrowseMyList,
    this.onOpenSearch,
    this.onOpenSettings,
    this.onSwitchProfile,
    this.onDownload,
    this.downloadManager,
  });

  final Profile activeProfile;
  final MediaSummary summary;
  final String languageCode;
  final VoidCallback onBack;
  final VoidCallback onPlay;
  final bool isSaved;
  final VoidCallback onToggleSaved;
  final PlaybackProgressSnapshot playbackProgress;
  final MediaCatalogService? mediaCatalogService;
  final ValueChanged<MediaSummary>? onOpenEpisodes;
  final VoidCallback? onOpenTitleInfo;
  final ValueChanged<MediaSummary>? onOpenTitle;
  final ValueChanged<MediaSummary>? onPlayTitle;
  final ValueChanged<MediaSummary>? onToggleSavedTitle;
  final Set<String> savedTitleKeys;
  final bool autoplayPreviews;
  final bool muteAutoplayTrailers;
  final VoidCallback? onBrowseHome;
  final VoidCallback? onBrowseTvShows;
  final VoidCallback? onBrowseMovies;
  final VoidCallback? onBrowseNewPopular;
  final VoidCallback? onBrowseMyList;
  final VoidCallback? onOpenSearch;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onSwitchProfile;
  final VoidCallback? onDownload;
  final OfflineDownloadManager? downloadManager;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  static const double _recommendationExpandedPosterAspectRatio = 16 / 9;
  static const double _recommendationLoadingHeight = 140;
  static const double _recommendationEmptyHeight = 86;

  CheriflixTvLayout get _layout => CheriflixTvLayout.of(context);
  double get _recommendationCardWidth => _layout.homeRailCardWidth;
  double get _recommendationCardPosterHeight =>
      _layout.homeRailCardPosterHeight;
  double get _recommendationExpandedPosterHeight =>
      _layout.homeRailExpandedPosterHeight;
  double get _recommendationExpandedWidth =>
      _recommendationExpandedPosterHeight *
      _recommendationExpandedPosterAspectRatio;
  double get _recommendationCardGap => _layout.homeRailGap;
  double get _recommendationCollapsedDetailsTopPadding =>
      _layout.value(compact: 10, standard: 11, wide: 12);
  double get _recommendationCollapsedTitleHeight =>
      _layout.homeRailCollapsedTitleHeight;
  double get _recommendationCollapsedDetailsSpacing =>
      _layout.value(compact: 3, standard: 4, wide: 4);
  double get _recommendationCollapsedSubtitleHeight =>
      _layout.homeRailCollapsedSubtitleHeight;
  double get _recommendationRailHeightBuffer =>
      _layout.value(compact: 6, standard: 7, wide: 8);
  double get _recommendationSafeMargin => _layout.homeRailSafeMargin;
  double get _recommendationCollapsedDetailsHeight =>
      _recommendationCollapsedDetailsTopPadding +
      _recommendationCollapsedTitleHeight +
      _recommendationCollapsedDetailsSpacing +
      _recommendationCollapsedSubtitleHeight;
  double get _recommendationCollapsedRailHeight =>
      _recommendationCardPosterHeight +
      _recommendationCollapsedDetailsHeight +
      _recommendationRailHeightBuffer;
  double get _recommendationExpandedRailHeight =>
      _recommendationCollapsedRailHeight;

  late MediaSummary _summary = widget.summary;
  TitleMetadata? _metadata;
  TmdbTitleLogo? _titleLogo;
  bool _titleLogoRendered = false;
  bool _titleLogoFailed = false;
  List<MediaSummary> _recommendations = const <MediaSummary>[];
  bool _recommendationsLoading = true;
  Uri? _backgroundPreviewUri;
  bool _liked = false;
  bool _disliked = false;
  final List<Timer> _focusRecoveryTimers = <Timer>[];
  final ScrollController _bodyScrollController = ScrollController();
  final ScrollController _recommendationScrollController = ScrollController();
  List<FocusNode> _recommendationFocusNodes = <FocusNode>[];
  List<String> _recommendationFocusKeys = <String>[];
  bool _recommendationRailExpanded = false;

  late final FocusNode _playFocusNode = FocusNode(debugLabel: 'DetailPlay');
  late final FocusNode _downloadFocusNode =
      FocusNode(debugLabel: 'DetailDownload');
  late final FocusNode _listFocusNode = FocusNode(debugLabel: 'DetailList');
  late final FocusNode _likeFocusNode = FocusNode(debugLabel: 'DetailLike');
  late final FocusNode _dislikeFocusNode =
      FocusNode(debugLabel: 'DetailDislike');
  late final FocusNode _overviewTabFocusNode =
      FocusNode(debugLabel: 'DetailOverviewTab');
  late final FocusNode _episodesTabFocusNode =
      FocusNode(debugLabel: 'DetailEpisodesTab');
  late final FocusNode _detailsTabFocusNode =
      FocusNode(debugLabel: 'DetailDetailsTab');
  late final FocusNode _firstRecommendationFocusNode =
      FocusNode(debugLabel: 'DetailFirstRecommendation');

  @override
  void initState() {
    super.initState();
    _syncRecommendationFocusNodes(_recommendations);
    _loadTitleExperience();
    _scheduleFocusRestore();
  }

  @override
  void didUpdateWidget(covariant DetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.summary.saveKey != widget.summary.saveKey ||
        oldWidget.languageCode != widget.languageCode ||
        oldWidget.mediaCatalogService != widget.mediaCatalogService ||
        oldWidget.muteAutoplayTrailers != widget.muteAutoplayTrailers) {
      _summary = widget.summary;
      _metadata = null;
      _titleLogo = null;
      _titleLogoRendered = false;
      _titleLogoFailed = false;
      _recommendations = const <MediaSummary>[];
      _backgroundPreviewUri = null;
      _recommendationsLoading = true;
      _recommendationRailExpanded = false;
      _syncRecommendationFocusNodes(_recommendations);
      _loadTitleExperience();
      _scheduleFocusRestore();
    }
  }

  @override
  void dispose() {
    for (final timer in _focusRecoveryTimers) {
      timer.cancel();
    }
    _bodyScrollController.dispose();
    _recommendationScrollController.dispose();
    _disposeRecommendationFocusNodes();
    _playFocusNode.dispose();
    _downloadFocusNode.dispose();
    _listFocusNode.dispose();
    _likeFocusNode.dispose();
    _dislikeFocusNode.dispose();
    _overviewTabFocusNode.dispose();
    _episodesTabFocusNode.dispose();
    _detailsTabFocusNode.dispose();
    _firstRecommendationFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TvShortcutScope(
      onBack: widget.onBack,
      // Detail navigation manages its vertical position explicitly. The
      // global focus visibility helper would otherwise scroll the Play row
      // into view and push a tall title logo above the screen edge.
      autoEnsureVisible: false,
      child: CheriflixScaffold(
        topBar: null,
        useSafeArea: false,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final layout = CheriflixTvLayout.fromWidth(constraints.maxWidth);
            final heroMaxWidth = layout.detailHeroMaxWidth;
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _FullscreenBackdrop(imageUrl: _summary.backdropUrl),
                Positioned.fill(
                  child: BackdropTrailerPreview(
                    previewUri: _backgroundPreviewUri,
                    onReady: _scheduleFocusRestore,
                  ),
                ),
                const Positioned.fill(child: _DetailBackdropScrim()),
                SafeArea(
                  child: Padding(
                    padding: layout.detailShellPadding,
                    child: ListView(
                      key: const ValueKey<String>('detail_body_list'),
                      controller: _bodyScrollController,
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.topLeft,
                          child: ConstrainedBox(
                            key: const ValueKey<String>('detail_hero_section'),
                            constraints: BoxConstraints(maxWidth: heroMaxWidth),
                            child: _buildHeroContent(),
                          ),
                        ),
                        const SizedBox(height: 34),
                        _buildLowerShelf(),
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeroContent() {
    final layout = CheriflixTvLayout.of(context);
    final progress = _progressEntry;
    final tagline = _metadata?.tagline?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          _summary.mediaType == MediaType.movie ? 'MOVIE' : 'TV SHOW',
          style: CheriflixTypography.overline.copyWith(
            color: CheriflixColors.textPrimary,
          ),
        ),
        const SizedBox(height: 20),
        _buildTitleMark(layout),
        const SizedBox(height: 24),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            if (_summary.rating != null)
              _MetaBadge(
                icon: Icons.star_rounded,
                label: _summary.rating!.toStringAsFixed(1),
              ),
            if (_summary.releaseDate != null)
              _MetaBadge(label: _releaseDateLabel(_summary.releaseDate!)),
            if (_summary.runtimeLabel != null)
              _MetaBadge(label: _summary.runtimeLabel!),
            if (_certificationLabel != null)
              _MetaBadge(label: _certificationLabel!),
            if (_summary.mediaType == MediaType.tv &&
                _summary.seasonLabel != null)
              _MetaBadge(label: _summary.seasonLabel!),
            if (_summary.primaryGenre != null)
              _MetaBadge(label: _summary.primaryGenre!),
          ],
        ),
        if (progress != null && progress.hasStarted) ...<Widget>[
          const SizedBox(height: 24),
          if (_summary.mediaType == MediaType.tv &&
              progress.seasonNumber != null &&
              progress.episodeNumber != null)
            Text(
              'S${progress.seasonNumber}:E${progress.episodeNumber}',
              style: CheriflixTypography.metadata.copyWith(
                color: CheriflixColors.textPrimary,
              ),
            ),
          if (_summary.mediaType == MediaType.tv &&
              progress.seasonNumber != null &&
              progress.episodeNumber != null)
            const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: _progressValue(progress),
                    minHeight: 4,
                    backgroundColor: const Color(0x33FFFFFF),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      CheriflixColors.accentRed,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Text(
                _progressLabel(progress),
                style: CheriflixTypography.metadata.copyWith(
                  color: const Color(0xCCFFFFFF),
                ),
              ),
            ],
          ),
        ],
        if (tagline != null && tagline.isNotEmpty) ...<Widget>[
          const SizedBox(height: 26),
          Text(
            tagline,
            style: CheriflixTypography.bodyMedium.copyWith(
              color: const Color(0xF0FFFFFF),
              fontSize: layout.detailHeroBodySize,
            ),
          ),
        ],
        const SizedBox(height: 26),
        Text(
          _heroOverview,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: CheriflixTypography.body.copyWith(
            color: const Color(0xE6FFFFFF),
            fontSize: layout.detailHeroBodySize,
          ),
        ),
        const SizedBox(height: 32),
        Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.arrowLeft):
                _LocalDirectionalIntent(TraversalDirection.left),
            SingleActivator(LogicalKeyboardKey.arrowRight):
                _LocalDirectionalIntent(TraversalDirection.right),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _LocalDirectionalIntent: CallbackAction<_LocalDirectionalIntent>(
                onInvoke: (intent) {
                  _handleHeroActionRowDirection(intent.direction);
                  return null;
                },
              ),
            },
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Transform.scale(
                    scale: layout.detailHeroActionScale,
                    alignment: Alignment.centerLeft,
                    child: TvActionButton(
                      label: _hasResume ? 'RESUME' : 'Play',
                      icon: Icons.play_arrow_rounded,
                      onPressed: widget.onPlay,
                      autofocus: false,
                      focusNode: _playFocusNode,
                      leftFallbackNodes: <FocusNode>[_playFocusNode],
                      rightFallbackNodes: <FocusNode>[
                        if (widget.onDownload != null) _downloadFocusNode,
                        _listFocusNode,
                      ],
                      downFallbackNodes: <FocusNode>[_overviewTabFocusNode],
                      ensureVisibleOnFocus: false,
                      onFocusChanged: (focused) {
                        if (focused) {
                          _scrollBodyToTop();
                        }
                      },
                      variant: TvButtonVariant.media,
                    ),
                  ),
                  if (widget.onDownload != null) ...<Widget>[
                    const SizedBox(width: 18),
                    AnimatedBuilder(
                      animation:
                          widget.downloadManager ?? const _InertListenable(),
                      builder: (context, child) {
                        final record = widget.downloadManager?.recordFor(
                          OfflineMediaKey(
                            tmdbId: widget.summary.tmdbId,
                            mediaType: widget.summary.mediaType,
                          ),
                        );
                        final label = switch (record?.status) {
                          OfflineDownloadStatus.completed => 'Downloaded',
                          OfflineDownloadStatus.downloading =>
                            'Downloading ${(record!.progress * 100).round()}%',
                          OfflineDownloadStatus.paused => 'Paused',
                          _ => 'Download',
                        };
                        return Transform.scale(
                          scale: layout.detailHeroActionScale,
                          alignment: Alignment.centerLeft,
                          child: TvActionButton(
                            label: label,
                            icon: record?.status ==
                                    OfflineDownloadStatus.completed
                                ? Icons.download_done_rounded
                                : Icons.download_rounded,
                            onPressed: widget.onDownload,
                            focusNode: _downloadFocusNode,
                            leftFallbackNodes: <FocusNode>[_playFocusNode],
                            rightFallbackNodes: <FocusNode>[_listFocusNode],
                            downFallbackNodes: <FocusNode>[
                              _overviewTabFocusNode,
                            ],
                            ensureVisibleOnFocus: false,
                            variant: TvButtonVariant.media,
                          ),
                        );
                      },
                    ),
                  ],
                  const SizedBox(width: 18),
                  Transform.scale(
                    scale: layout.detailHeroActionScale,
                    alignment: Alignment.centerLeft,
                    child: TvActionButton(
                      label: widget.isSaved ? 'In My List' : 'Add to My List',
                      onPressed: widget.onToggleSaved,
                      focusNode: _listFocusNode,
                      leftFallbackNodes: <FocusNode>[
                        if (widget.onDownload != null) _downloadFocusNode,
                        _playFocusNode,
                      ],
                      rightFallbackNodes: <FocusNode>[_likeFocusNode],
                      downFallbackNodes: <FocusNode>[_overviewTabFocusNode],
                      ensureVisibleOnFocus: false,
                      variant: TvButtonVariant.media,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Transform.scale(
                    scale: layout.detailHeroActionScale,
                    alignment: Alignment.centerLeft,
                    child: _DetailIconActionButton(
                      icon: _liked
                          ? Icons.thumb_up_alt_rounded
                          : Icons.thumb_up_off_alt_rounded,
                      semanticLabel: 'Like title',
                      selected: _liked,
                      focusNode: _likeFocusNode,
                      downFallbackNodes: <FocusNode>[_overviewTabFocusNode],
                      onFocusChanged: (_) {},
                      onPressed: () {
                        setState(() {
                          _liked = !_liked;
                          if (_liked) {
                            _disliked = false;
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 18),
                  Transform.scale(
                    scale: layout.detailHeroActionScale,
                    alignment: Alignment.centerLeft,
                    child: _DetailIconActionButton(
                      icon: _disliked
                          ? Icons.thumb_down_alt_rounded
                          : Icons.thumb_down_off_alt_rounded,
                      semanticLabel: 'Dislike title',
                      selected: _disliked,
                      focusNode: _dislikeFocusNode,
                      downFallbackNodes: <FocusNode>[_overviewTabFocusNode],
                      onFocusChanged: (_) {},
                      onPressed: () {
                        setState(() {
                          _disliked = !_disliked;
                          if (_disliked) {
                            _liked = false;
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLowerShelf() {
    return Container(
      key: const ValueKey<String>('detail_lower_shelf'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x0EFFFFFF)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xA0101010),
            Color(0x880D0D0D),
            Color(0x700A0A0A),
          ],
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildSectionTabs(),
            const SizedBox(height: 20),
            _buildOverviewSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTabs() {
    final recommendationFallback = _canShowRecommendationRail
        ? <FocusNode>[_firstRecommendationFocusNode]
        : const <FocusNode>[];
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 18,
        runSpacing: 12,
        alignment: WrapAlignment.start,
        children: <Widget>[
          _DetailTabButton(
            label: 'OVERVIEW',
            selected: true,
            focusNode: _overviewTabFocusNode,
            upFallbackNodes: _heroActionNodes,
            downFallbackNodes: recommendationFallback,
            onFocusChanged: (focused) {
              if (focused) {
                _ensureFocusVisible(_overviewTabFocusNode);
              }
            },
            onPressed: () {},
          ),
          if (widget.onOpenEpisodes != null &&
              _summary.mediaType == MediaType.tv)
            _DetailTabButton(
              label: 'EPISODES',
              selected: false,
              focusNode: _episodesTabFocusNode,
              upFallbackNodes: _heroActionNodes,
              downFallbackNodes: recommendationFallback,
              onFocusChanged: (focused) {
                if (focused) {
                  _ensureFocusVisible(_episodesTabFocusNode);
                }
              },
              onPressed: () => widget.onOpenEpisodes?.call(_summary),
            ),
          if (widget.onOpenTitleInfo != null)
            _DetailTabButton(
              label: 'DETAILS',
              selected: false,
              focusNode: _detailsTabFocusNode,
              upFallbackNodes: _heroActionNodes,
              downFallbackNodes: recommendationFallback,
              onFocusChanged: (focused) {
                if (focused) {
                  _ensureFocusVisible(_detailsTabFocusNode);
                }
              },
              onPressed: widget.onOpenTitleInfo,
            ),
        ],
      ),
    );
  }

  Widget _buildOverviewSection() {
    final recommendationsRail = _buildRecommendationsRail();
    final railContainer = _canShowRecommendationRail
        ? AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: _recommendationShelfHeight,
            child: recommendationsRail,
          )
        : SizedBox(
            height: _recommendationShelfHeight,
            child: recommendationsRail,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text(
          'Others Also Watched',
          style: CheriflixTypography.sectionTitle,
        ),
        const SizedBox(height: 18),
        railContainer,
      ],
    );
  }

  Widget _buildRecommendationsRail() {
    if (_recommendationsLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_recommendations.isEmpty || widget.onOpenTitle == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'No additional recommendations available right now.',
          style: CheriflixTypography.body.copyWith(
            color: CheriflixColors.textSecondary,
          ),
        ),
      );
    }

    return ListView.separated(
      key: const ValueKey<String>('detail_recommendations_rail'),
      controller: _recommendationScrollController,
      clipBehavior: Clip.none,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _recommendations.length,
      separatorBuilder: (_, __) => SizedBox(width: _recommendationCardGap),
      itemBuilder: (context, index) {
        final item = _recommendations[index];
        return TvPosterButton(
          key: ValueKey<String>('detail_recommendation_${item.saveKey}_$index'),
          title: item.title,
          subtitle: item.metadataLabel,
          imageUrl: item.backdropUrl ?? item.posterUrl,
          posterSurfaceKey: ValueKey<String>(
            'detail_recommendation_surface_${item.saveKey}_$index',
          ),
          width: _recommendationCardWidth,
          posterHeight: _recommendationCardPosterHeight,
          expandedWidth: _recommendationExpandedWidth,
          expandedPosterHeight: _recommendationExpandedPosterHeight,
          alignment: Alignment.bottomLeft,
          expandOnFocus: true,
          reserveExpandedSpace: true,
          overlayExpandedDetails: true,
          ensureVisibleOnFocus: false,
          previewLoadDelay: const Duration(milliseconds: 1800),
          autoplayPreviewEnabled: widget.autoplayPreviews,
          autoplayPreviewMuted: widget.muteAutoplayTrailers,
          expandedImageUrl: item.backdropUrl ?? item.posterUrl,
          previewLoader: () => _loadRecommendationPreviewUri(
            item,
            muted: widget.muteAutoplayTrailers,
          ),
          focusNode: _recommendationFocusNodeForIndex(index),
          upFallbackNodes: <FocusNode>[_overviewTabFocusNode],
          leftFallbackNodes: <FocusNode>[
            index > 0
                ? _recommendationFocusNodeForIndex(index - 1)
                : _recommendationFocusNodeForIndex(index),
          ],
          rightFallbackNodes: <FocusNode>[
            index < _recommendations.length - 1
                ? _recommendationFocusNodeForIndex(index + 1)
                : _recommendationFocusNodeForIndex(index),
          ],
          onDirectionalFocus: (direction) =>
              _handleRecommendationDirectionalFocus(index, direction),
          onFocusChanged: (focused, _, __) {
            if (focused) {
              _centerRecommendationIndex(index);
            }
            _updateRecommendationRailExpansion(focused);
          },
          saved: widget.savedTitleKeys.contains(item.saveKey),
          onPressed: () => widget.onOpenTitle!(item),
          onPlay: widget.onPlayTitle == null
              ? null
              : () => widget.onPlayTitle!(item),
          onOpenInfo: () => widget.onOpenTitle!(item),
          onToggleSaved: widget.onToggleSavedTitle == null
              ? null
              : () => widget.onToggleSavedTitle!(item),
        );
      },
    );
  }

  Future<void> _loadTitleExperience() async {
    final catalogService = _tmdbCatalogService;
    if (catalogService == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _metadata = null;
        _recommendationsLoading = false;
        _recommendations = const <MediaSummary>[];
        _backgroundPreviewUri = null;
      });
      return;
    }

    final preparedLogo = catalogService.peekPreferredTitleLogo(
      tmdbId: widget.summary.tmdbId,
      mediaType: widget.summary.mediaType,
      languageCode: widget.languageCode,
    );
    if (preparedLogo != null) {
      _titleLogo = preparedLogo;
    }
    unawaited(_loadTitleLogo(catalogService));

    final metadataFuture = catalogService
        .fetchTitleMetadata(
          tmdbId: widget.summary.tmdbId,
          mediaType: widget.summary.mediaType,
          languageCode: widget.languageCode,
        )
        .then<Object?>((value) => value)
        .catchError((_) => null);
    final recommendationsFuture = catalogService
        .fetchRecommendations(
          tmdbId: widget.summary.tmdbId,
          mediaType: widget.summary.mediaType,
          languageCode: widget.languageCode,
        )
        .then<Object?>((value) => value)
        .catchError((_) => const <MediaSummary>[]);
    final previewFuture = catalogService
        .fetchTrailerPreviewUri(
          tmdbId: widget.summary.tmdbId,
          mediaType: widget.summary.mediaType,
          languageCode: widget.languageCode,
          muted: widget.muteAutoplayTrailers,
        )
        .then<Object?>((value) => value)
        .catchError((_) => null);

    final results = await Future.wait<Object?>(<Future<Object?>>[
      metadataFuture,
      recommendationsFuture,
      previewFuture,
    ]);
    if (!mounted) {
      return;
    }

    final metadata = results[0] as TitleMetadata?;
    final fallbackSummary = metadata == null
        ? await catalogService
            .fetchTitleDetails(
              tmdbId: widget.summary.tmdbId,
              mediaType: widget.summary.mediaType,
              languageCode: widget.languageCode,
            )
            .catchError((_) => widget.summary)
        : null;
    if (!mounted) {
      return;
    }

    setState(() {
      _metadata = metadata;
      _summary = metadata?.summary ?? fallbackSummary ?? widget.summary;
      final rawRecommendations = results[1]! as List<MediaSummary>;
      _recommendations = widget.activeProfile.maturityTier.name == 'mature'
          ? rawRecommendations
          : const <MediaSummary>[];
      _backgroundPreviewUri = results[2] as Uri?;
      _recommendationsLoading = false;
    });
    if (widget.activeProfile.maturityTier.name != 'mature') {
      final filtered = await catalogService.filterForMaturity(
        results[1]! as List<MediaSummary>,
        tier: widget.activeProfile.maturityTier,
        languageCode: widget.languageCode,
      );
      if (mounted) setState(() => _recommendations = filtered);
    }
    _syncRecommendationFocusNodes(_recommendations);
    _scheduleFocusRestore();
  }

  Future<void> _loadTitleLogo(TmdbMediaCatalogService catalogService) async {
    final requestedKey = widget.summary.saveKey;
    final logo = await catalogService
        .fetchPreferredTitleLogo(
          tmdbId: widget.summary.tmdbId,
          mediaType: widget.summary.mediaType,
          languageCode: widget.languageCode,
        )
        .catchError((_) => null);
    if (!mounted || widget.summary.saveKey != requestedKey) return;
    setState(() {
      _titleLogo = logo;
      _titleLogoRendered = false;
      _titleLogoFailed = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _heroActionNodes.any((node) => node.hasFocus)) {
        _scrollBodyToTop(immediate: true);
      }
    });
  }

  Widget _buildTitleMark(CheriflixTvLayout layout) {
    final logo = _titleLogo;
    final showLogo = logo != null && !_titleLogoFailed;
    final maxWidth = layout.value(compact: 400, standard: 500, wide: 560);
    final maxHeight = layout.value(compact: 112, standard: 132, wide: 150);
    final textTitle = Text(
      _summary.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: CheriflixTypography.heroTitle.copyWith(
        fontSize: layout.detailHeroTitleSize,
      ),
    );
    if (!showLogo) return textTitle;

    final logoSize = calculateTitleLogoSize(
      intrinsicWidth: logo.width,
      intrinsicHeight: logo.height,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );

    return SizedBox(
      width: logoSize.width,
      height: logoSize.height,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: <Widget>[
          AnimatedOpacity(
            opacity: _titleLogoRendered ? 0 : 1,
            duration: const Duration(milliseconds: 120),
            child: textTitle,
          ),
          CheriflixNetworkImage(
            imageUrl: logo.imageUrl,
            width: logoSize.width,
            height: logoSize.height,
            preset: TmdbImagePreset.titleLogo,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            placeholderColor: Colors.transparent,
            fadeInDuration: Duration.zero,
            onImageLoaded: () {
              if (mounted && !_titleLogoRendered) {
                setState(() => _titleLogoRendered = true);
              }
            },
            onFinalError: () {
              if (mounted) setState(() => _titleLogoFailed = true);
            },
          ),
        ],
      ),
    );
  }

  void _scheduleFocusRestore() {
    for (final timer in _focusRecoveryTimers) {
      timer.cancel();
    }
    _focusRecoveryTimers.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPrimaryScreenFocus();
    });
    _focusRecoveryTimers.add(
      Timer(const Duration(milliseconds: 120), _requestPrimaryScreenFocus),
    );
    _focusRecoveryTimers.add(
      Timer(const Duration(milliseconds: 320), _requestPrimaryScreenFocus),
    );
  }

  void _requestPrimaryScreenFocus() {
    if (!mounted) {
      return;
    }
    _scrollBodyToTop(immediate: true);
    final preferredNodes = <FocusNode>[
      _playFocusNode,
      _overviewTabFocusNode,
      _listFocusNode,
    ];
    for (final node in preferredNodes) {
      if (node.context != null) {
        node.requestFocus();
        return;
      }
    }
  }

  void _handleHeroActionRowDirection(TraversalDirection direction) {
    switch (direction) {
      case TraversalDirection.left:
        if (_dislikeFocusNode.hasFocus) {
          _likeFocusNode.requestFocus();
        } else if (_likeFocusNode.hasFocus) {
          _listFocusNode.requestFocus();
        } else if (_listFocusNode.hasFocus) {
          _playFocusNode.requestFocus();
        }
        return;
      case TraversalDirection.right:
        if (_playFocusNode.hasFocus) {
          _listFocusNode.requestFocus();
        } else if (_listFocusNode.hasFocus) {
          _likeFocusNode.requestFocus();
        } else if (_likeFocusNode.hasFocus) {
          _dislikeFocusNode.requestFocus();
        }
        return;
      case TraversalDirection.up:
      case TraversalDirection.down:
        return;
    }
  }

  void _scrollBodyToTop({bool immediate = false}) {
    if (!_bodyScrollController.hasClients) {
      return;
    }

    final targetOffset = _bodyScrollController.position.minScrollExtent;
    if ((_bodyScrollController.offset - targetOffset).abs() < 1) {
      return;
    }

    if (immediate) {
      _bodyScrollController.jumpTo(targetOffset);
    } else {
      unawaited(
        _bodyScrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void _ensureFocusVisible(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !node.hasFocus || node.context == null) return;
      Scrollable.ensureVisible(
        node.context!,
        alignment: 0.72,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  List<FocusNode> get _heroActionNodes => <FocusNode>[
        _playFocusNode,
        _listFocusNode,
        _likeFocusNode,
        _dislikeFocusNode,
      ];

  String? get _recommendationFocusKeyForCurrentFocus {
    for (var index = 0; index < _recommendationFocusNodes.length; index += 1) {
      if (_recommendationFocusNodes[index].hasPrimaryFocus) {
        return _recommendationFocusKeys[index];
      }
    }
    return null;
  }

  PlaybackProgressEntry? get _progressEntry =>
      widget.playbackProgress.preferredForTitle(_summary);

  bool get _hasResume => _progressEntry?.isInProgress == true;

  String get _heroOverview {
    final overview = _summary.overview?.trim();
    if (overview != null && overview.isNotEmpty) {
      return overview;
    }
    return 'No synopsis is available for this title yet.';
  }

  String? get _certificationLabel {
    final certification = _metadata?.certification?.trim();
    if (certification == null || certification.isEmpty) {
      return null;
    }
    return certification;
  }

  TmdbMediaCatalogService? get _tmdbCatalogService {
    final service = widget.mediaCatalogService;
    if (service is TmdbMediaCatalogService) {
      return service;
    }
    return null;
  }

  bool get _canShowRecommendationRail =>
      !_recommendationsLoading &&
      _recommendations.isNotEmpty &&
      widget.onOpenTitle != null;

  double get _recommendationRailHeight => _recommendationRailExpanded
      ? _recommendationExpandedRailHeight
      : _recommendationCollapsedRailHeight;

  double get _recommendationShelfHeight {
    if (_canShowRecommendationRail) {
      return _recommendationRailHeight;
    }
    if (_recommendationsLoading) {
      return _recommendationLoadingHeight;
    }
    return _recommendationEmptyHeight;
  }

  void _syncRecommendationFocusNodes(List<MediaSummary> items) {
    final nextKeys = items.map((item) => item.saveKey).toList(growable: false);
    if (_recommendationFocusKeys.length == nextKeys.length) {
      var identical = true;
      for (var index = 0; index < nextKeys.length; index += 1) {
        if (_recommendationFocusKeys[index] != nextKeys[index]) {
          identical = false;
          break;
        }
      }
      if (identical) {
        return;
      }
    }

    _disposeRecommendationFocusNodes();
    _recommendationFocusKeys = nextKeys;
    if (items.isEmpty) {
      _recommendationFocusNodes = <FocusNode>[];
      _recommendationRailExpanded = false;
      return;
    }

    _recommendationFocusNodes = List<FocusNode>.generate(
      items.length,
      (index) => index == 0
          ? _firstRecommendationFocusNode
          : FocusNode(debugLabel: 'DetailRecommendation[$index]'),
      growable: false,
    );
  }

  void _disposeRecommendationFocusNodes() {
    for (final node in _recommendationFocusNodes) {
      if (identical(node, _firstRecommendationFocusNode)) {
        continue;
      }
      node.dispose();
    }
    _recommendationFocusNodes = <FocusNode>[];
    _recommendationFocusKeys = <String>[];
  }

  FocusNode _recommendationFocusNodeForIndex(int index) {
    if (_recommendationFocusNodes.isEmpty) {
      return _firstRecommendationFocusNode;
    }
    return _recommendationFocusNodes[index];
  }

  void _updateRecommendationRailExpansion(bool focused) {
    if (focused) {
      if (!_recommendationRailExpanded && mounted) {
        setState(() => _recommendationRailExpanded = true);
      }
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _recommendationRailHasFocus()) {
        return;
      }
      if (_recommendationRailExpanded) {
        setState(() => _recommendationRailExpanded = false);
      }
    });
  }

  bool _recommendationRailHasFocus() {
    for (final node in _recommendationFocusNodes) {
      if (node.hasFocus) {
        return true;
      }
    }
    return false;
  }

  void _requestRecommendationFocusAt(int index) {
    unawaited(_focusRecommendationAt(index));
  }

  Future<void> _focusRecommendationAt(int index) async {
    if (_recommendationFocusNodes.isEmpty || !mounted) {
      return;
    }
    final clampedIndex = index.clamp(0, _recommendationFocusNodes.length - 1);
    await _scrollRecommendationsToIndexIfNeeded(clampedIndex);
    if (!mounted) {
      return;
    }
    final targetNode = _recommendationFocusNodeForIndex(clampedIndex);
    if (targetNode.context == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        targetNode.requestFocus();
      });
      return;
    }
    targetNode.requestFocus();
  }

  KeyEventResult _handleRecommendationDirectionalFocus(
    int index,
    TraversalDirection direction,
  ) {
    switch (direction) {
      case TraversalDirection.left:
        if (index <= 0) {
          return KeyEventResult.ignored;
        }
        _requestRecommendationFocusAt(index - 1);
        return KeyEventResult.handled;
      case TraversalDirection.right:
        if (index >= _recommendations.length - 1) {
          return KeyEventResult.ignored;
        }
        _requestRecommendationFocusAt(index + 1);
        return KeyEventResult.handled;
      case TraversalDirection.up:
        _overviewTabFocusNode.requestFocus();
        return KeyEventResult.handled;
      case TraversalDirection.down:
        return KeyEventResult.ignored;
    }
  }

  void _centerRecommendationIndex(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_recommendationScrollController.hasClients) {
        return;
      }
      final focusNode = _recommendationFocusNodeForIndex(index);
      if (!focusNode.hasPrimaryFocus) {
        return;
      }
      final focusContext = focusNode.context;
      if (focusContext != null) {
        unawaited(
          Scrollable.ensureVisible(
            focusContext,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          ),
        );
      }
      unawaited(_scrollRecommendationsToIndexIfNeeded(index));
    });
  }

  Future<void> _scrollRecommendationsToIndexIfNeeded(int index) async {
    if (!mounted || !_recommendationScrollController.hasClients) {
      return;
    }
    final position = _recommendationScrollController.position;
    final itemStart =
        index * (_recommendationCardWidth + _recommendationCardGap);
    final itemEnd = itemStart + _recommendationExpandedWidth;
    final viewportStart = position.pixels + _recommendationSafeMargin;
    final viewportEnd = position.pixels +
        position.viewportDimension -
        _recommendationSafeMargin;
    double? desiredPixels;
    if (itemStart < viewportStart) {
      desiredPixels = itemStart - _recommendationSafeMargin;
    } else if (itemEnd > viewportEnd) {
      desiredPixels =
          itemEnd - position.viewportDimension + _recommendationSafeMargin;
    } else {
      return;
    }

    final clampedPixels = desiredPixels.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((clampedPixels - position.pixels).abs() < 1) {
      return;
    }

    await _recommendationScrollController.animateTo(
      clampedPixels.toDouble(),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  Future<Uri?> _loadRecommendationPreviewUri(
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
}

class _FullscreenBackdrop extends StatelessWidget {
  const _FullscreenBackdrop({
    required this.imageUrl,
  });

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final size = MediaQuery.sizeOf(context);
    return CheriflixNetworkImage(
      imageUrl: imageUrl,
      width: size.width,
      height: size.height,
      devicePixelRatio: devicePixelRatio,
      preset: TmdbImagePreset.heroBackdrop,
      maxDecodePixels: 1600,
      placeholderColor: CheriflixColors.background,
    );
  }
}

class _DetailBackdropScrim extends StatelessWidget {
  const _DetailBackdropScrim();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[
            Color(0xFC141414),
            Color(0xF5141414),
            Color(0xE8141414),
            Color(0xCC141414),
            Color(0x9A141414),
            Color(0x5C141414),
            Color(0x24141414),
            Color(0x00141414),
          ],
          stops: <double>[0, 0.08, 0.18, 0.32, 0.5, 0.68, 0.84, 1],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: <Color>[
              Color(0xFF141414),
              Color(0xF8141414),
              Color(0xEE141414),
              Color(0xD8141414),
              Color(0xB1141414),
              Color(0x76141414),
              Color(0x38141414),
              Color(0x08141414),
              Color(0x00141414),
            ],
            stops: <double>[0, 0.06, 0.14, 0.24, 0.38, 0.54, 0.72, 0.9, 1],
          ),
        ),
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge({
    required this.label,
    this.icon,
  });

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x880E0E0E),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x18FFFFFF), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 14, color: const Color(0xBBF0F0F0)),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: CheriflixTypography.metadata.copyWith(
              color: const Color(0xBBF0F0F0),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailTabButton extends StatefulWidget {
  const _DetailTabButton({
    required this.label,
    required this.selected,
    required this.focusNode,
    required this.onPressed,
    this.upFallbackNodes = const <FocusNode>[],
    this.downFallbackNodes = const <FocusNode>[],
    this.onFocusChanged,
  });

  final String label;
  final bool selected;
  final FocusNode focusNode;
  final VoidCallback? onPressed;
  final List<FocusNode> upFallbackNodes;
  final List<FocusNode> downFallbackNodes;
  final ValueChanged<bool>? onFocusChanged;

  @override
  State<_DetailTabButton> createState() => _DetailTabButtonState();
}

class _DetailTabButtonState extends State<_DetailTabButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp):
            _LocalDirectionalIntent(TraversalDirection.up),
        SingleActivator(LogicalKeyboardKey.arrowDown):
            _LocalDirectionalIntent(TraversalDirection.down),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              widget.onPressed?.call();
              return null;
            },
          ),
          _LocalDirectionalIntent: CallbackAction<_LocalDirectionalIntent>(
            onInvoke: (intent) {
              _moveFocusFromNode(
                widget.focusNode,
                intent.direction,
                upFallbackNodes: widget.upFallbackNodes,
                downFallbackNodes: widget.downFallbackNodes,
              );
              return null;
            },
          ),
        },
        child: FocusableActionDetector(
          focusNode: widget.focusNode,
          onFocusChange: widget.onFocusChanged,
          onShowFocusHighlight: (value) {
            setState(() => _focused = value);
            if (value && widget.onFocusChanged == null) {
              _ensureDetailVisible(context);
            }
          },
          child: GestureDetector(
            onTap: widget.onPressed,
              child: AnimatedContainer(
                key: ValueKey<String>('detail_tab_surface_${widget.label}'),
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: widget.selected
                      ? const Color(0xFF1A1A1A)
                      : const Color(0x08111111),
                  border: Border.all(
                    color: _focused
                        ? const Color(0x44FFFFFF)
                        : widget.selected
                            ? const Color(0x20FFFFFF)
                            : Colors.transparent,
                    width: _focused ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      widget.label,
                      style: CheriflixTypography.button.copyWith(
                        color: widget.selected
                            ? CheriflixColors.textPrimary
                            : const Color(0xBBF0F0F0),
                        letterSpacing: 0.35,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      width: 80,
                      height: 3,
                      decoration: BoxDecoration(
                        color: widget.selected
                            ? CheriflixColors.accentRed
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailIconActionButton extends StatefulWidget {
  const _DetailIconActionButton({
    required this.icon,
    required this.semanticLabel,
    required this.focusNode,
    required this.onPressed,
    this.selected = false,
    this.downFallbackNodes = const <FocusNode>[],
    this.onFocusChanged,
  });

  final IconData icon;
  final String semanticLabel;
  final FocusNode focusNode;
  final VoidCallback onPressed;
  final bool selected;
  final List<FocusNode> downFallbackNodes;
  final ValueChanged<bool>? onFocusChanged;

  @override
  State<_DetailIconActionButton> createState() =>
      _DetailIconActionButtonState();
}

class _DetailIconActionButtonState extends State<_DetailIconActionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp):
            _LocalDirectionalIntent(TraversalDirection.up),
        SingleActivator(LogicalKeyboardKey.arrowDown):
            _LocalDirectionalIntent(TraversalDirection.down),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              widget.onPressed();
              return null;
            },
          ),
          _LocalDirectionalIntent: CallbackAction<_LocalDirectionalIntent>(
            onInvoke: (intent) {
              _moveFocusFromNode(
                widget.focusNode,
                intent.direction,
                downFallbackNodes: widget.downFallbackNodes,
              );
              return null;
            },
          ),
        },
        child: FocusableActionDetector(
          focusNode: widget.focusNode,
          onFocusChange: widget.onFocusChanged,
          onShowFocusHighlight: (value) {
            setState(() => _focused = value);
            if (value && widget.onFocusChanged == null) {
              _ensureDetailVisible(context);
            }
          },
          child: Tooltip(
            message: widget.semanticLabel,
            child: GestureDetector(
              onTap: widget.onPressed,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _focused ? const Color(0xFFF0F0F0) : const Color(0xFF1A1A1A),
                  border: Border.all(
                    color: _focused
                        ? const Color(0xF0FFFFFF)
                        : widget.selected
                            ? const Color(0x66CC1020)
                            : const Color(0x1AFFFFFF),
                    width: _focused ? 1.5 : 1,
                  ),
                  boxShadow: <BoxShadow>[
                    const BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                    if (widget.selected && !_focused)
                      const BoxShadow(
                        color: Color(0x22E50914),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                  ],
                ),
                child: Icon(
                  widget.icon,
                  color: _focused
                      ? CheriflixColors.inkOnLight
                      : widget.selected
                          ? CheriflixColors.accentRed
                          : const Color(0xBBF0F0F0),
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _releaseDateLabel(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$month/$day/${value.year}';
}

double _progressValue(PlaybackProgressEntry progress) {
  final totalMillis = progress.totalDuration.inMilliseconds;
  if (totalMillis <= 0) {
    return 0;
  }
  return (progress.position.inMilliseconds / totalMillis).clamp(0.0, 1.0);
}

String _progressLabel(PlaybackProgressEntry progress) {
  final watchedMinutes = (progress.position.inSeconds / 60).round();
  final totalMinutes = (progress.totalDuration.inSeconds / 60).round();
  if (totalMinutes <= 0) {
    return '$watchedMinutes watched';
  }
  return '$watchedMinutes of ${totalMinutes}m';
}

void _ensureDetailVisible(BuildContext context) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) {
      return;
    }
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      alignment: scrollable.position.axis == Axis.horizontal ? 0.5 : 0.35,
    );
  });
}

void _moveFocusFromNode(
  FocusNode currentNode,
  TraversalDirection direction, {
  List<FocusNode> upFallbackNodes = const <FocusNode>[],
  List<FocusNode> downFallbackNodes = const <FocusNode>[],
}) {
  final fallbackNodes = switch (direction) {
    TraversalDirection.up => upFallbackNodes,
    TraversalDirection.down => downFallbackNodes,
    _ => const <FocusNode>[],
  };

  for (final node in fallbackNodes) {
    if (node == currentNode || node.context == null) {
      continue;
    }
    node.requestFocus();
    return;
  }

  final moved = currentNode.focusInDirection(direction);
  if (moved) {
    return;
  }

  for (final node in fallbackNodes) {
    if (node.context != null) {
      node.requestFocus();
      return;
    }
  }
}

class _LocalDirectionalIntent extends Intent {
  const _LocalDirectionalIntent(this.direction);

  final TraversalDirection direction;
}
