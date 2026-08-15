import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/episode_summary.dart';
import '../../core/models/media_summary.dart';
import '../../core/models/playback_progress_entry.dart';
import '../../core/models/playback_progress_snapshot.dart';
import '../../core/services/media_catalog_service.dart';
import '../../core/services/offline_download_manager.dart';
import '../../core/services/tmdb_media_catalog_service.dart';
import '../../core/services/tmdb_image_service.dart';
import '../../core/theme/cheriflix_theme.dart';
import '../../core/utils/user_facing_errors.dart';
import '../../core/utils/release_date_utils.dart';
import '../../core/widgets/playback_progress_bar.dart';
import '../../core/widgets/cheriflix_network_image.dart';

class EpisodesBrowser extends StatefulWidget {
  const EpisodesBrowser({
    super.key,
    required this.summary,
    required this.playbackProgress,
    required this.languageCode,
    this.hideSpoilers = false,
    required this.onPlayEpisode,
    this.mediaCatalogService,
    this.initialSeasonNumber = 1,
    this.onDownloadEpisode,
    this.downloadManager,
  });

  final MediaSummary? summary;
  final PlaybackProgressSnapshot playbackProgress;
  final String languageCode;
  final bool hideSpoilers;
  final void Function(int seasonNumber, EpisodeSummary episode) onPlayEpisode;
  final MediaCatalogService? mediaCatalogService;
  final int initialSeasonNumber;
  final void Function(int seasonNumber, EpisodeSummary episode)?
      onDownloadEpisode;
  final OfflineDownloadManager? downloadManager;

  @override
  State<EpisodesBrowser> createState() => _EpisodesBrowserState();
}

class _EpisodesBrowserState extends State<EpisodesBrowser> {
  late int _selectedSeason;
  List<EpisodeSummary> _episodes = const <EpisodeSummary>[];
  final Map<int, int> _seasonEpisodeCounts = <int, int>{};
  final Map<int, FocusNode> _seasonFocusNodes = <int, FocusNode>{};
  bool _loading = true;
  String? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _selectedSeason = _clampSeason(widget.initialSeasonNumber);
    _ensureSeasonFocusNodes();
    _loadEpisodes();
    _warmSeasonCounts();
    _requestSelectedSeasonFocus();
  }

  @override
  void dispose() {
    for (final node in _seasonFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _EpisodesLayoutMetrics.of(context, constraints);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: metrics.seasonRailWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    summary?.title ?? 'Episodes',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: metrics.titleFontSize,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: metrics.headerGapSmall),
                  Text(
                    _seasonHeader(summary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xD8FFFFFF),
                      fontSize: metrics.headerFontSize,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: metrics.headerGapLarge),
                  Expanded(child: _buildSeasonRail(metrics)),
                ],
              ),
            ),
            SizedBox(width: metrics.columnGap),
            Expanded(child: _buildEpisodePane(summary, metrics)),
          ],
        );
      },
    );
  }

  Widget _buildSeasonRail(_EpisodesLayoutMetrics metrics) {
    final seasons = _availableSeasons;
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: seasons.length,
      separatorBuilder: (_, __) => SizedBox(height: metrics.seasonGap),
      itemBuilder: (context, index) {
        final seasonNumber = seasons[index];
        return _SeasonRowButton(
          metrics: metrics,
          label: 'Season $seasonNumber',
          countLabel: _seasonCountLabel(seasonNumber),
          active: seasonNumber == _selectedSeason,
          focusNode: _seasonFocusNodes[seasonNumber],
          autofocus: seasonNumber == _selectedSeason,
          onPressed: () {
            if (seasonNumber == _selectedSeason) {
              return;
            }
            setState(() {
              _selectedSeason = seasonNumber;
            });
            _requestSelectedSeasonFocus();
            _loadEpisodes();
          },
        );
      },
    );
  }

  Widget _buildEpisodePane(
    MediaSummary? summary,
    _EpisodesLayoutMetrics metrics,
  ) {
    if (_loading) {
      return _EpisodeListSkeleton(metrics: metrics);
    }

    if (_error != null) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: metrics.messageMaxWidth),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontSize: metrics.messageFontSize,
              height: 1.45,
            ),
          ),
        ),
      );
    }

    if (_episodes.isEmpty) {
      return Center(
        child: Text(
          'No episodes are available for this season yet.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white70,
            fontSize: metrics.messageFontSize,
            height: 1.45,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _episodes.length,
      separatorBuilder: (_, __) => SizedBox(height: metrics.episodeGap),
      itemBuilder: (context, index) {
        final episode = _episodes[index];
        final manager = widget.downloadManager;
        Widget buildRow() {
          final key = summary == null
              ? null
              : OfflineMediaKey(
                  tmdbId: summary.tmdbId,
                  mediaType: summary.mediaType,
                  seasonNumber: _selectedSeason,
                  episodeNumber: episode.episodeNumber,
                );
          final record = key == null ? null : manager?.recordFor(key);
          final VoidCallback? downloadAction = episode.isUpcoming
              ? null
              : switch (record?.status) {
                  OfflineDownloadStatus.downloading when manager != null =>
                    () => manager.pause(key!),
                  OfflineDownloadStatus.paused when manager != null => () =>
                      manager.resume(key!),
                  OfflineDownloadStatus.completed => null,
                  _ => widget.onDownloadEpisode == null
                      ? null
                      : () =>
                          widget.onDownloadEpisode!(_selectedSeason, episode),
                };
          return _EpisodeRowButton(
            metrics: metrics,
            episode: episode,
            progress: _progressForEpisode(episode),
            hideSpoilers: widget.hideSpoilers,
            fallbackImageUrl: summary?.backdropUrl,
            onPressed: () => widget.onPlayEpisode(_selectedSeason, episode),
            onDownload: downloadAction,
            downloadRecord: record,
          );
        }

        if (manager == null) {
          return buildRow();
        }
        return AnimatedBuilder(
          animation: manager,
          builder: (context, child) => buildRow(),
        );
      },
    );
  }

  Future<void> _loadEpisodes() async {
    final catalogService = _tmdbCatalogService;
    final summary = widget.summary;
    if (catalogService == null || summary == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _episodes = const <EpisodeSummary>[];
        _error =
            'TMDb episode data is unavailable until CHERIFLIX is configured with live catalog access.';
      });
      return;
    }

    final currentGeneration = ++_loadGeneration;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final episodes = await catalogService.fetchSeasonEpisodes(
        tmdbId: summary.tmdbId,
        seasonNumber: _selectedSeason,
        languageCode: widget.languageCode,
        fallbackRuntimeMinutes: summary.runtimeMinutes,
      );
      if (!mounted || currentGeneration != _loadGeneration) {
        return;
      }
      setState(() {
        _episodes = episodes;
        _seasonEpisodeCounts[_selectedSeason] = episodes.length;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || currentGeneration != _loadGeneration) {
        return;
      }
      setState(() {
        _loading = false;
        _episodes = const <EpisodeSummary>[];
        _error = userFacingErrorMessage(
          error,
          fallback: 'Episode details could not be loaded right now.',
        );
      });
    }
  }

  Future<void> _warmSeasonCounts() async {
    final catalogService = _tmdbCatalogService;
    if (catalogService == null || _availableSeasons.length <= 1) {
      return;
    }

    final summary = widget.summary;
    if (summary == null) {
      return;
    }

    for (final season in _availableSeasons) {
      if (_seasonEpisodeCounts.containsKey(season)) {
        continue;
      }
      try {
        final episodes = await catalogService.fetchSeasonEpisodes(
          tmdbId: summary.tmdbId,
          seasonNumber: season,
          languageCode: widget.languageCode,
          fallbackRuntimeMinutes: summary.runtimeMinutes,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _seasonEpisodeCounts[season] = episodes.length;
        });
      } catch (_) {
        // Season counts are a secondary affordance, so a failed prefetch should
        // not block the episode browser.
      }
    }
  }

  TmdbMediaCatalogService? get _tmdbCatalogService {
    final service = widget.mediaCatalogService;
    if (service is TmdbMediaCatalogService) {
      return service;
    }
    return null;
  }

  List<int> get _availableSeasons {
    final seasonCount = math.max(widget.summary?.seasonCount ?? 1, 1);
    return List<int>.generate(seasonCount, (index) => index + 1);
  }

  int _clampSeason(int seasonNumber) {
    final seasons = _availableSeasons;
    if (seasons.contains(seasonNumber)) {
      return seasonNumber;
    }
    return seasons.first;
  }

  String _seasonCountLabel(int season) {
    final count = _seasonEpisodeCounts[season];
    if (count == null) {
      return '';
    }
    return count == 1 ? '1 episode' : '$count episodes';
  }

  PlaybackProgressEntry? _progressForEpisode(EpisodeSummary episode) {
    final summary = widget.summary;
    if (summary == null) {
      return null;
    }

    return widget.playbackProgress.entryForTarget(
      summary: summary,
      seasonNumber: episode.seasonNumber,
      episodeNumber: episode.episodeNumber,
    );
  }

  void _ensureSeasonFocusNodes() {
    for (final season in _availableSeasons) {
      _seasonFocusNodes.putIfAbsent(
        season,
        () => FocusNode(debugLabel: 'TvActionButton(Season $season)'),
      );
    }
  }

  void _requestSelectedSeasonFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _seasonFocusNodes[_selectedSeason]?.requestFocus();
    });
  }
}

class _EpisodeListSkeleton extends StatelessWidget {
  const _EpisodeListSkeleton({required this.metrics});

  final _EpisodesLayoutMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Column(
        children: <Widget>[
          for (var index = 0; index < 4; index += 1) ...<Widget>[
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0x66131313),
                  borderRadius: BorderRadius.circular(metrics.rowRadius),
                  border: Border.all(color: const Color(0x14FFFFFF)),
                ),
                padding: EdgeInsets.all(metrics.episodeRowPadding),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: metrics.thumbnailWidth,
                      decoration: BoxDecoration(
                        color: const Color(0xFF222222),
                        borderRadius:
                            BorderRadius.circular(metrics.thumbnailRadius),
                      ),
                    ),
                    SizedBox(width: metrics.episodeContentGap),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          FractionallySizedBox(
                            widthFactor: 0.54,
                            child: Container(
                              height: metrics.episodeTitleFontSize,
                              decoration: BoxDecoration(
                                color: const Color(0xFF292929),
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                          ),
                          SizedBox(height: metrics.textGapSmall * 2),
                          FractionallySizedBox(
                            widthFactor: 0.82,
                            child: Container(
                              height: metrics.episodeSynopsisFontSize * 1.8,
                              decoration: BoxDecoration(
                                color: const Color(0xFF202020),
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (index < 3) SizedBox(height: metrics.episodeGap),
          ],
        ],
      ),
    );
  }
}

class _SeasonRowButton extends StatefulWidget {
  const _SeasonRowButton({
    required this.metrics,
    required this.label,
    required this.countLabel,
    required this.active,
    required this.onPressed,
    this.focusNode,
    this.autofocus = false,
  });

  final _EpisodesLayoutMetrics metrics;
  final String label;
  final String countLabel;
  final bool active;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<_SeasonRowButton> createState() => _SeasonRowButtonState();
}

class _SeasonRowButtonState extends State<_SeasonRowButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final metrics = widget.metrics;
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              widget.onPressed();
              return null;
            },
          ),
        },
        child: FocusableActionDetector(
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          onShowFocusHighlight: (value) {
            setState(() => _focused = value);
            if (value) {
              _scrollIntoView(context);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: EdgeInsets.symmetric(
              horizontal: metrics.seasonPaddingHorizontal,
              vertical: metrics.seasonPaddingVertical,
            ),
            decoration: BoxDecoration(
              color: widget.active
                  ? const Color(0x33FFFFFF)
                  : const Color(0x12000000),
              borderRadius: BorderRadius.circular(metrics.buttonRadius),
              border: Border.all(
                color: _focused
                    ? CheriflixColors.focus
                    : widget.active
                        ? const Color(0x28FFFFFF)
                        : Colors.transparent,
                width: _focused
                    ? metrics.focusBorderWidth
                    : metrics.hairlineBorderWidth,
              ),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: metrics.seasonFontSize,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (widget.countLabel.isNotEmpty) ...<Widget>[
                  SizedBox(width: metrics.seasonLabelGap),
                  Text(
                    widget.countLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: CheriflixColors.textSecondary,
                      fontSize: metrics.seasonCountFontSize,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodeRowButton extends StatefulWidget {
  const _EpisodeRowButton({
    required this.metrics,
    required this.episode,
    required this.onPressed,
    required this.hideSpoilers,
    this.progress,
    this.fallbackImageUrl,
    this.onDownload,
    this.downloadRecord,
  });

  final _EpisodesLayoutMetrics metrics;
  final EpisodeSummary episode;
  final PlaybackProgressEntry? progress;
  final bool hideSpoilers;
  final String? fallbackImageUrl;
  final VoidCallback onPressed;
  final VoidCallback? onDownload;
  final OfflineDownloadRecord? downloadRecord;

  @override
  State<_EpisodeRowButton> createState() => _EpisodeRowButtonState();
}

class _EpisodeRowButtonState extends State<_EpisodeRowButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final metrics = widget.metrics;
    final devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final hasStarted =
        widget.progress != null && widget.progress!.position > Duration.zero;
    final spoilersHidden = widget.hideSpoilers && !hasStarted;
    final imageUrl = widget.episode.stillUrl ?? widget.fallbackImageUrl;
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              widget.onPressed();
              return null;
            },
          ),
        },
        child: FocusableActionDetector(
          onShowFocusHighlight: (value) {
            setState(() => _focused = value);
            if (value) {
              _scrollIntoView(context);
            }
          },
          child: SizedBox(
            height: metrics.episodeRowHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0x66131313),
                borderRadius: BorderRadius.circular(metrics.rowRadius),
                border: Border.all(
                  color: _focused
                      ? CheriflixColors.focus
                      : const Color(0x18FFFFFF),
                  width: _focused
                      ? metrics.focusBorderWidth
                      : metrics.hairlineBorderWidth,
                ),
              ),
              child: InkWell(
                onTap: widget.onPressed,
                borderRadius: BorderRadius.circular(metrics.rowRadius),
                child: Padding(
                  padding: EdgeInsets.all(metrics.episodeRowPadding),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(
                        width: metrics.thumbnailWidth,
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(metrics.thumbnailRadius),
                          child: spoilersHidden
                              ? DecoratedBox(
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF080808),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      Icons.hide_image_rounded,
                                      color: const Color(0x80FFFFFF),
                                      size: metrics.placeholderIconSize,
                                    ),
                                  ),
                                )
                              : Stack(
                                  fit: StackFit.expand,
                                  children: <Widget>[
                                    CheriflixNetworkImage(
                                      imageUrl: imageUrl,
                                      width: metrics.thumbnailWidth,
                                      height: metrics.thumbnailHeight,
                                      devicePixelRatio: devicePixelRatio,
                                      preset: TmdbImagePreset.episodeStill,
                                      maxDecodePixels: 1024,
                                      placeholderColor: const Color(0xFF101010),
                                    ),
                                    const Positioned.fill(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.center,
                                            end: Alignment.bottomCenter,
                                            colors: <Color>[
                                              Color(0x05000000),
                                              Color(0x33000000),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    Center(
                                      child: DecoratedBox(
                                        decoration: const BoxDecoration(
                                          color: Color(0xE8FFFFFF),
                                          shape: BoxShape.circle,
                                        ),
                                        child: SizedBox.square(
                                          dimension: metrics.playCircleSize,
                                          child: Icon(
                                            widget.episode.isUpcoming
                                                ? Icons.schedule_rounded
                                                : Icons.play_arrow_rounded,
                                            color: Colors.black,
                                            size: metrics.playIconSize,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (widget.episode.isUpcoming)
                                      Positioned(
                                        top: 7,
                                        right: 7,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xE61A1A1A),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            border: Border.all(
                                              color: CheriflixColors.focus,
                                            ),
                                          ),
                                          child: Text(
                                            'COMING ${releaseDateLabel(widget.episode.airDate!).toUpperCase()}',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize:
                                                  metrics.episodeMetaFontSize *
                                                      0.78,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (widget.progress != null)
                                      Positioned(
                                        left: 0,
                                        right: 0,
                                        bottom: 0,
                                        child: PlaybackProgressBar(
                                          value:
                                              widget.progress!.progressFraction,
                                          height: metrics.progressBarHeight,
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                      ),
                      SizedBox(width: metrics.episodeContentGap),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Episode ${widget.episode.episodeNumber} - ${widget.episode.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: metrics.episodeTitleFontSize,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: metrics.textGapSmall),
                            if (widget.episode.airDate != null) ...<Widget>[
                              Text(
                                _formatDate(widget.episode.airDate!),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: CheriflixColors.textSecondary,
                                  fontSize: metrics.episodeMetaFontSize,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: metrics.textGapSmall),
                            ],
                            Expanded(
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: Text(
                                  spoilersHidden
                                      ? ''
                                      : widget.episode.overview
                                                  ?.trim()
                                                  .isNotEmpty ==
                                              true
                                          ? widget.episode.overview!
                                          : 'No synopsis available for this episode yet.',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: const Color(0xE6FFFFFF),
                                    fontSize: metrics.episodeSynopsisFontSize,
                                    height: 1.22,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: metrics.textGapTiny),
                            Text(
                              widget.episode.runtimeLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: CheriflixColors.textSecondary,
                                fontSize: metrics.episodeMetaFontSize,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.onDownload != null ||
                          widget.downloadRecord != null) ...<Widget>[
                        SizedBox(width: metrics.textGapSmall),
                        Center(
                          child: Semantics(
                            label: _downloadSemanticLabel,
                            button: true,
                            child: IconButton(
                              tooltip: _downloadSemanticLabel,
                              onPressed: widget.onDownload,
                              icon: Icon(
                                _downloadIcon,
                                color: Colors.white,
                                size: metrics.playIconSize * 0.8,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _downloadSemanticLabel {
    return switch (widget.downloadRecord?.status) {
      OfflineDownloadStatus.completed => 'Downloaded',
      OfflineDownloadStatus.downloading =>
        'Downloading ${(widget.downloadRecord!.progress * 100).round()} percent',
      OfflineDownloadStatus.paused => 'Download paused',
      OfflineDownloadStatus.failed => 'Retry download',
      _ => 'Download episode',
    };
  }

  IconData get _downloadIcon {
    return switch (widget.downloadRecord?.status) {
      OfflineDownloadStatus.completed => Icons.download_done_rounded,
      OfflineDownloadStatus.downloading => Icons.downloading_rounded,
      OfflineDownloadStatus.paused => Icons.pause_circle_outline_rounded,
      OfflineDownloadStatus.failed => Icons.refresh_rounded,
      _ => Icons.download_rounded,
    };
  }
}

class _EpisodesLayoutMetrics {
  const _EpisodesLayoutMetrics({
    required this.seasonRailWidth,
    required this.columnGap,
    required this.titleFontSize,
    required this.headerFontSize,
    required this.headerGapSmall,
    required this.headerGapLarge,
    required this.seasonGap,
    required this.seasonPaddingHorizontal,
    required this.seasonPaddingVertical,
    required this.seasonLabelGap,
    required this.seasonFontSize,
    required this.seasonCountFontSize,
    required this.buttonRadius,
    required this.rowRadius,
    required this.thumbnailRadius,
    required this.focusBorderWidth,
    required this.hairlineBorderWidth,
    required this.episodeGap,
    required this.episodeRowHeight,
    required this.episodeRowPadding,
    required this.thumbnailWidth,
    required this.thumbnailHeight,
    required this.episodeContentGap,
    required this.episodeTitleFontSize,
    required this.episodeMetaFontSize,
    required this.episodeSynopsisFontSize,
    required this.textGapSmall,
    required this.textGapTiny,
    required this.playCircleSize,
    required this.playIconSize,
    required this.placeholderIconSize,
    required this.progressBarHeight,
    required this.loadingIndicatorSize,
    required this.loadingIndicatorStrokeWidth,
    required this.messageMaxWidth,
    required this.messageFontSize,
  });

  final double seasonRailWidth;
  final double columnGap;
  final double titleFontSize;
  final double headerFontSize;
  final double headerGapSmall;
  final double headerGapLarge;
  final double seasonGap;
  final double seasonPaddingHorizontal;
  final double seasonPaddingVertical;
  final double seasonLabelGap;
  final double seasonFontSize;
  final double seasonCountFontSize;
  final double buttonRadius;
  final double rowRadius;
  final double thumbnailRadius;
  final double focusBorderWidth;
  final double hairlineBorderWidth;
  final double episodeGap;
  final double episodeRowHeight;
  final double episodeRowPadding;
  final double thumbnailWidth;
  final double thumbnailHeight;
  final double episodeContentGap;
  final double episodeTitleFontSize;
  final double episodeMetaFontSize;
  final double episodeSynopsisFontSize;
  final double textGapSmall;
  final double textGapTiny;
  final double playCircleSize;
  final double playIconSize;
  final double placeholderIconSize;
  final double progressBarHeight;
  final double loadingIndicatorSize;
  final double loadingIndicatorStrokeWidth;
  final double messageMaxWidth;
  final double messageFontSize;

  static _EpisodesLayoutMetrics of(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    final screen = MediaQuery.sizeOf(context);
    final width =
        constraints.hasBoundedWidth ? constraints.maxWidth : screen.width;
    final height =
        constraints.hasBoundedHeight ? constraints.maxHeight : screen.height;
    final base = math.min(screen.width, screen.height);
    final localBase = math.min(width, height);
    final episodeGap = height * 0.014;
    final episodeRowHeight = (height - episodeGap * 3) / 4;
    final episodeRowPadding = height * 0.014;
    final thumbnailHeight = episodeRowHeight - episodeRowPadding * 2;
    final thumbnailWidth = thumbnailHeight * 16 / 9;
    final playCircleSize = thumbnailHeight * 0.42;

    return _EpisodesLayoutMetrics(
      seasonRailWidth: width * 0.25,
      columnGap: width * 0.016,
      titleFontSize: base * 0.033,
      headerFontSize: base * 0.02,
      headerGapSmall: height * 0.012,
      headerGapLarge: height * 0.034,
      seasonGap: height * 0.014,
      seasonPaddingHorizontal: width * 0.014,
      seasonPaddingVertical: height * 0.017,
      seasonLabelGap: width * 0.008,
      seasonFontSize: base * 0.024,
      seasonCountFontSize: base * 0.018,
      buttonRadius: localBase * 0.018,
      rowRadius: localBase * 0.02,
      thumbnailRadius: localBase * 0.016,
      focusBorderWidth: localBase * 0.004,
      hairlineBorderWidth: localBase * 0.0014,
      episodeGap: episodeGap,
      episodeRowHeight: episodeRowHeight,
      episodeRowPadding: episodeRowPadding,
      thumbnailWidth: thumbnailWidth,
      thumbnailHeight: thumbnailHeight,
      episodeContentGap: width * 0.018,
      episodeTitleFontSize: base * 0.026,
      episodeMetaFontSize: base * 0.018,
      episodeSynopsisFontSize: base * 0.02,
      textGapSmall: height * 0.006,
      textGapTiny: height * 0.004,
      playCircleSize: playCircleSize,
      playIconSize: playCircleSize * 0.56,
      placeholderIconSize: thumbnailHeight * 0.26,
      progressBarHeight: base * 0.006,
      loadingIndicatorSize: localBase * 0.055,
      loadingIndicatorStrokeWidth: localBase * 0.005,
      messageMaxWidth: width * 0.48,
      messageFontSize: base * 0.022,
    );
  }
}

String _seasonHeader(MediaSummary? summary) {
  if (summary == null) {
    return '';
  }

  final parts = <String>[
    if (summary.releaseDate != null) '${summary.releaseDate!.year}',
    if (summary.seasonLabel != null) summary.seasonLabel!.toLowerCase(),
  ];
  return parts.join('    ');
}

String _formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

void _scrollIntoView(BuildContext context) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) {
      return;
    }
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) {
      return;
    }

    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      alignment: 0.45,
    );
  });
}
