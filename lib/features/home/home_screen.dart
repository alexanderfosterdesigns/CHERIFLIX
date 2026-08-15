import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/home_catalog_data.dart';
import '../../core/models/just_released_catalog.dart';
import '../../core/models/media_summary.dart';
import '../../core/models/media_type.dart';
import '../../core/models/playback_progress_entry.dart';
import '../../core/models/playback_progress_snapshot.dart';
import '../../core/models/profile.dart';
import '../../core/models/profile_playback_settings.dart';
import '../../core/models/tmdb_title_logo.dart';
import '../../core/models/upcoming_catalog.dart';
import '../../core/services/media_catalog_service.dart';
import '../../core/services/runtime_pressure.dart';
import '../../core/services/tmdb_media_catalog_service.dart';
import '../../core/services/tmdb_image_service.dart';
import '../../core/theme/cheriflix_theme.dart';
import '../../core/theme/tv_layout.dart';
import '../../core/utils/user_facing_errors.dart';
import '../../core/utils/release_date_utils.dart';
import '../../core/widgets/cheriflix_chrome.dart';
import '../../core/widgets/cheriflix_network_image.dart';
import '../../core/widgets/cheriflix_title_mark.dart';
import '../../core/widgets/playback_progress_bar.dart';
import '../../core/widgets/poster_preview_overlay.dart';
import '../../core/widgets/tv_shortcuts.dart';

enum BrowseMode {
  home,
  tvShows,
  movies,
  newPopular,
}

extension BrowseModeX on BrowseMode {
  String get label {
    switch (this) {
      case BrowseMode.home:
        return 'Home';
      case BrowseMode.tvShows:
        return 'TV Shows';
      case BrowseMode.movies:
        return 'Movies';
      case BrowseMode.newPopular:
        return 'New & Popular';
    }
  }

  String get heroLabel {
    return 'CHERIFLIX $heroLabelSuffix';
  }

  String get heroLabelSuffix {
    switch (this) {
      case BrowseMode.home:
        return 'FEATURE';
      case BrowseMode.tvShows:
        return 'SERIES';
      case BrowseMode.movies:
        return 'MOVIE';
      case BrowseMode.newPopular:
        return 'NEW & POPULAR';
    }
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.activeProfile,
    required this.playbackSettings,
    required this.mediaCatalogService,
    required this.languageCode,
    this.loadHomeRecommendations,
    required this.onOpenSearch,
    required this.onOpenSettings,
    required this.onSwitchProfile,
    this.onBack,
    required this.onOpenTitle,
    this.onPlayTitle,
    this.onToggleSaved,
    this.savedTitleKeys = const <String>{},
    required this.playbackProgress,
    this.browseMode = BrowseMode.home,
    this.onBrowseHome,
    this.onBrowseTvShows,
    this.onBrowseMovies,
    this.onBrowseNewPopular,
    this.onBrowseMyList,
    this.initialScrollOffset = 0,
    this.onScrollOffsetChanged,
    this.initialFocusedRailIndex,
    this.initialFocusedItemIndex,
    this.onFocusedItemChanged,
  });

  final Profile activeProfile;
  final ProfilePlaybackSettings playbackSettings;
  final MediaCatalogService? mediaCatalogService;
  final String languageCode;
  final Future<List<MediaSummary>> Function()? loadHomeRecommendations;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenSettings;
  final VoidCallback onSwitchProfile;
  final VoidCallback? onBack;
  final ValueChanged<MediaSummary> onOpenTitle;
  final ValueChanged<MediaSummary>? onPlayTitle;
  final ValueChanged<MediaSummary>? onToggleSaved;
  final Set<String> savedTitleKeys;
  final PlaybackProgressSnapshot playbackProgress;
  final BrowseMode browseMode;
  final VoidCallback? onBrowseHome;
  final VoidCallback? onBrowseTvShows;
  final VoidCallback? onBrowseMovies;
  final VoidCallback? onBrowseNewPopular;
  final VoidCallback? onBrowseMyList;
  final double initialScrollOffset;
  final ValueChanged<double>? onScrollOffsetChanged;
  final int? initialFocusedRailIndex;
  final int? initialFocusedItemIndex;
  final void Function(int railIndex, int itemIndex)? onFocusedItemChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeCatalogData? _catalog;
  JustReleasedCatalog? _justReleasedCatalog;
  UpcomingCatalog _upcomingCatalog = const UpcomingCatalog(
    movies: <MediaSummary>[],
    series: <MediaSummary>[],
    seasons: <UpcomingSeasonEntry>[],
  );
  List<MediaSummary> _homeRecommendations = const <MediaSummary>[];
  String? _error;
  String? _justReleasedError;
  bool _loading = true;
  bool _loadingJustReleased = false;
  late final FocusNode _heroPlayFocusNode =
      FocusNode(debugLabel: 'HomeHeroPlay');
  late final FocusNode _heroInfoFocusNode =
      FocusNode(debugLabel: 'HomeHeroInfo');
  late final FocusNode _heroListFocusNode =
      FocusNode(debugLabel: 'HomeHeroList');
  late final FocusNode _firstRailFocusNode =
      FocusNode(debugLabel: 'HomeFirstRail');
  late final FocusNode _homeTabFocusNode =
      FocusNode(debugLabel: 'HomeTopBarHome');
  late final FocusNode _tvShowsTabFocusNode =
      FocusNode(debugLabel: 'HomeTopBarTvShows');
  late final FocusNode _moviesTabFocusNode =
      FocusNode(debugLabel: 'HomeTopBarMovies');
  late final FocusNode _newPopularTabFocusNode =
      FocusNode(debugLabel: 'HomeTopBarNewPopular');
  late final FocusNode _myListTabFocusNode =
      FocusNode(debugLabel: 'HomeTopBarMyList');
  late final FocusNode _searchFocusNode =
      FocusNode(debugLabel: 'HomeTopBarSearch');
  late final FocusNode _settingsFocusNode =
      FocusNode(debugLabel: 'HomeTopBarSettings');
  late final FocusNode _profilesFocusNode =
      FocusNode(debugLabel: 'HomeTopBarProfiles');
  late final ScrollController _bodyScrollController = ScrollController(
    initialScrollOffset: widget.initialScrollOffset,
  );
  final Map<String, GlobalKey<_ContentRailState>> _railKeys =
      <String, GlobalKey<_ContentRailState>>{};
  List<String> _visibleRailTitles = const <String>[];
  String? _focusedRailItemKey;
  String? _focusedRailTitle;
  int? _focusedRailItemIndex;
  int _bodyScrollRequestSequence = 0;
  final Map<String, TmdbTitleLogo?> _preparedTitleLogos =
      <String, TmdbTitleLogo?>{};
  final Set<String> _logoPreparationKeys = <String>{};
  int _logoPreparationGeneration = 0;
  int _catalogLoadGeneration = 0;

  @override
  void dispose() {
    _reportScrollOffset();
    _bodyScrollController.removeListener(_reportScrollOffset);
    _heroPlayFocusNode.dispose();
    _heroInfoFocusNode.dispose();
    _heroListFocusNode.dispose();
    _firstRailFocusNode.dispose();
    _homeTabFocusNode.dispose();
    _tvShowsTabFocusNode.dispose();
    _moviesTabFocusNode.dispose();
    _newPopularTabFocusNode.dispose();
    _myListTabFocusNode.dispose();
    _searchFocusNode.dispose();
    _settingsFocusNode.dispose();
    _profilesFocusNode.dispose();
    _bodyScrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _bodyScrollController.addListener(_reportScrollOffset);
    _loadCatalog();
  }

  void _reportScrollOffset() {
    if (_bodyScrollController.hasClients) {
      widget.onScrollOffsetChanged?.call(_bodyScrollController.offset);
    }
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaCatalogService != widget.mediaCatalogService ||
        oldWidget.languageCode != widget.languageCode ||
        oldWidget.activeProfile.id != widget.activeProfile.id ||
        oldWidget.activeProfile.maturityTier !=
            widget.activeProfile.maturityTier ||
        oldWidget.loadHomeRecommendations != widget.loadHomeRecommendations) {
      _loadCatalog();
      return;
    }

    if (oldWidget.browseMode != widget.browseMode && _catalog != null) {
      if (widget.browseMode == BrowseMode.newPopular &&
          _justReleasedCatalog == null &&
          !_loadingJustReleased) {
        unawaited(_loadJustReleasedCatalog(showErrors: true));
      }
      _requestInitialFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return TvShortcutScope(
      onBack: widget.onBack,
      autoEnsureVisible: false,
      child: CheriflixScaffold(
        topBar: CheriflixTopBar(
          activeTab: widget.browseMode.label,
          profile: widget.activeProfile,
          downFallbackNodes: _topBarDownFallbackNodes,
          onControlFocusChanged: _handleHeaderFocusChanged,
          homeFocusNode: _homeTabFocusNode,
          tvShowsFocusNode: _tvShowsTabFocusNode,
          moviesFocusNode: _moviesTabFocusNode,
          newPopularFocusNode: _newPopularTabFocusNode,
          myListFocusNode: _myListTabFocusNode,
          searchFocusNode: _searchFocusNode,
          settingsFocusNode: _settingsFocusNode,
          profilesFocusNode: _profilesFocusNode,
          onHome: widget.onBrowseHome,
          onTvShows: widget.onBrowseTvShows,
          onMovies: widget.onBrowseMovies,
          onNewPopular: widget.onBrowseNewPopular,
          onMyList: widget.onBrowseMyList,
          onSearch: widget.onOpenSearch,
          onSettings: widget.onOpenSettings,
          onProfiles: widget.onSwitchProfile,
        ),
        body: Stack(
          children: <Widget>[
            _buildBody(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final layout = CheriflixTvLayout.of(context);
    if (widget.mediaCatalogService == null) {
      return const _CenteredMessage(
        title: 'TMDb API key missing',
        message:
            'Set CHERIFLIX_TMDB_API_KEY to load live discovery rails and search results.',
      );
    }

    if (_loading) {
      return const _BrowseLoadingSkeleton();
    }

    if (_error != null || _catalog == null) {
      return _CenteredMessage(
        title: 'Unable to load catalog',
        message: _error ?? 'The browse rails could not be loaded.',
        action: TvActionButton(
          label: 'Retry',
          icon: Icons.refresh_rounded,
          onPressed: _loadCatalog,
          variant: TvButtonVariant.light,
        ),
      );
    }

    final catalog = _catalog!;
    final homeRecommendations = _resolvedHomeRecommendations(catalog);
    final featured = _currentHeroItem(
      catalog,
      homeRecommendations: homeRecommendations,
      justReleasedCatalog: _justReleasedCatalog,
    );
    final rails = _railsForMode(
      catalog,
      widget.browseMode,
      playbackProgress: widget.playbackProgress,
      homeRecommendations: homeRecommendations,
      homeRecommendationsTitle: _homeRecommendationsTitle,
      justReleasedCatalog: _justReleasedCatalog,
      upcomingCatalog: _upcomingCatalog,
    ).where((rail) => rail.items.isNotEmpty).toList(growable: false);
    _visibleRailTitles =
        rails.map((rail) => rail.title).toList(growable: false);
    return ListView(
      key: const ValueKey<String>('home_body_list'),
      controller: _bodyScrollController,
      // Build ~2 extra rails above/below the viewport. Each rail is
      // roughly 320px tall, so 800px buffer keeps D-pad scroll smooth
      // without eagerly constructing every rail on first paint.
      cacheExtent: 800,
      padding: EdgeInsets.fromLTRB(
        layout.pagePadding.left,
        layout.value(compact: 12, standard: 14, wide: 16),
        layout.pagePadding.right,
        layout.pagePadding.bottom,
      ),
      children: <Widget>[
        _HeroBanner(
          item: featured,
          titleLogo: _preparedTitleLogos[featured.saveKey],
          browseMode: widget.browseMode,
          isSaved: widget.savedTitleKeys.contains(featured.saveKey),
          hasResume:
              widget.playbackProgress.latestResumeForTitle(featured) != null,
          previewLoader: _loadPreviewUri,
          autoplayPreviews: widget.playbackSettings.autoplayPreviews,
          muteAutoplayTrailers: widget.playbackSettings.muteAutoplayTrailers,
          playFocusNode: _heroPlayFocusNode,
          infoFocusNode: _heroInfoFocusNode,
          listFocusNode: _heroListFocusNode,
          heroActionUpFallbackNodes: _preferredTopBarFocusNodes,
          heroActionDownFallbackNodes: <FocusNode>[_firstRailFocusNode],
          onHeroControlFocusChanged: _handleHeroControlFocusChanged,
          onPlay: () =>
              (widget.onPlayTitle ?? widget.onOpenTitle).call(featured),
          onOpenDetails: () => widget.onOpenTitle(featured),
          onToggleSaved: widget.onToggleSaved == null
              ? null
              : () => widget.onToggleSaved!(featured),
        ),
        const SizedBox(height: 18),
        for (var index = 0; index < rails.length; index += 1) ...<Widget>[
          _ContentRail(
            key: _railKeyForTitle(rails[index].title),
            title: rails[index].title,
            items: rails[index].items,
            savedTitleKeys: widget.savedTitleKeys,
            onOpenTitle: widget.onOpenTitle,
            onPlayTitle: widget.onPlayTitle,
            onToggleSaved: widget.onToggleSaved,
            firstItemFocusNode: index == 0 ? _firstRailFocusNode : null,
            upFocusNodeForIndex: (itemIndex) => index == 0
                ? _heroActionFocusNodeForIndex(itemIndex)
                : _railStateFor(index - 1)?.focusNodeForIndex(itemIndex),
            downFocusNodeForIndex: (itemIndex) => index >= rails.length - 1
                ? null
                : _railStateFor(index + 1)?.focusNodeForIndex(itemIndex),
            previewLoader: _loadPreviewUri,
            autoplayPreviews: widget.playbackSettings.autoplayPreviews,
            muteAutoplayTrailers: widget.playbackSettings.muteAutoplayTrailers,
            onCardFocusChanged: (itemKey, itemIndex, focused, cardContext) {
              if (focused) {
                unawaited(
                  _prepareTitleLogo(
                    rails[index].items[itemIndex].summary,
                    notifyWhenReady: false,
                  ),
                );
              }
              _handleRailCardFocusChanged(
                itemKey,
                index,
                itemIndex,
                focused,
                cardContext,
              );
            },
            onRequestNeighborFocus: (itemIndex, direction) =>
                _handleNeighborRailFocusRequest(index, itemIndex, direction),
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }

  List<FocusNode> get _topBarDownFallbackNodes => <FocusNode>[
        ..._heroActionFocusNodes,
      ];

  List<FocusNode> get _heroActionFocusNodes => <FocusNode>[
        _heroPlayFocusNode,
        _heroInfoFocusNode,
        if (widget.onToggleSaved != null) _heroListFocusNode,
      ];

  List<FocusNode> get _preferredTopBarFocusNodes {
    final activeNode = switch (widget.browseMode) {
      BrowseMode.home => _homeTabFocusNode,
      BrowseMode.tvShows => _tvShowsTabFocusNode,
      BrowseMode.movies => _moviesTabFocusNode,
      BrowseMode.newPopular => _newPopularTabFocusNode,
    };
    return <FocusNode>[
      activeNode,
      for (final node in _topBarFocusNodes)
        if (node != activeNode) node,
    ];
  }

  List<FocusNode> get _topBarFocusNodes => <FocusNode>[
        _homeTabFocusNode,
        _tvShowsTabFocusNode,
        _moviesTabFocusNode,
        _newPopularTabFocusNode,
        _myListTabFocusNode,
        _searchFocusNode,
        _settingsFocusNode,
        _profilesFocusNode,
      ];

  Future<void> _loadCatalog() async {
    final service = widget.mediaCatalogService;
    final loadGeneration = ++_catalogLoadGeneration;
    if (service == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _catalog = null;
        _justReleasedCatalog = null;
        _homeRecommendations = const <MediaSummary>[];
        _error = null;
        _justReleasedError = null;
        _loadingJustReleased = false;
      });
      return;
    }

    _logoPreparationGeneration += 1;
    _preparedTitleLogos.clear();
    _logoPreparationKeys.clear();
    setState(() {
      _loading = true;
      _error = null;
      _justReleasedCatalog = null;
      _justReleasedError = null;
      _loadingJustReleased = false;
      _homeRecommendations = const <MediaSummary>[];
      _upcomingCatalog = const UpcomingCatalog(
        movies: <MediaSummary>[],
        series: <MediaSummary>[],
        seasons: <UpcomingSeasonEntry>[],
      );
    });

    // Start optional enrichment at the same time as the base catalog, but do
    // not keep already-usable browse content behind it. The final rails and
    // data sources remain identical; only their presentation is progressive.
    final homeRecommendationsFuture =
        (widget.loadHomeRecommendations?.call() ??
                Future<List<MediaSummary>>.value(const <MediaSummary>[]))
            .catchError((_) => const <MediaSummary>[]);
    final upcomingService =
        widget.mediaCatalogService.runtimeType == TmdbMediaCatalogService
            ? _tmdbCatalogService
            : null;
    final upcomingFuture = upcomingService
            ?.fetchUpcomingCatalog(languageCode: widget.languageCode)
            .catchError(
              (_) => const UpcomingCatalog(
                movies: <MediaSummary>[],
                series: <MediaSummary>[],
                seasons: <UpcomingSeasonEntry>[],
              ),
            ) ??
        Future<UpcomingCatalog>.value(
          const UpcomingCatalog(
            movies: <MediaSummary>[],
            series: <MediaSummary>[],
            seasons: <UpcomingSeasonEntry>[],
          ),
        );

    try {
      var catalog = await service.fetchHomeCatalog(
        languageCode: widget.languageCode,
      );
      final tmdbService = _tmdbCatalogService;
      if (tmdbService != null) {
        // Never publish an unfiltered catalog for a restricted profile.
        catalog = await tmdbService.filterHomeCatalogForMaturity(
          catalog,
          tier: widget.activeProfile.maturityTier,
          languageCode: widget.languageCode,
        );
      }
      if (!mounted || loadGeneration != _catalogLoadGeneration) {
        return;
      }

      setState(() {
        _catalog = catalog;
        _loading = false;
      });
      _prepareTabHeroLogos(catalog);
      _requestInitialFocus();
      unawaited(
        _loadJustReleasedCatalog(
          showErrors: widget.browseMode == BrowseMode.newPopular,
        ),
      );
      unawaited(
        _loadSupplementalCatalog(
          loadGeneration: loadGeneration,
          homeRecommendationsFuture: homeRecommendationsFuture,
          upcomingFuture: upcomingFuture,
        ),
      );
    } catch (error) {
      if (!mounted || loadGeneration != _catalogLoadGeneration) {
        return;
      }
      setState(() {
        _loading = false;
        _homeRecommendations = const <MediaSummary>[];
        _error = userFacingErrorMessage(
          error,
          fallback: 'The browse rails could not be loaded.',
        );
      });
    }
  }

  Future<void> _loadSupplementalCatalog({
    required int loadGeneration,
    required Future<List<MediaSummary>> homeRecommendationsFuture,
    required Future<UpcomingCatalog> upcomingFuture,
  }) async {
    try {
      var homeRecommendations = await homeRecommendationsFuture;
      var upcomingCatalog = await upcomingFuture;
      final tmdbService = _tmdbCatalogService;
      if (tmdbService != null) {
        final filtered = await Future.wait<Object>(<Future<Object>>[
          tmdbService.filterForMaturity(
            homeRecommendations,
            tier: widget.activeProfile.maturityTier,
            languageCode: widget.languageCode,
          ),
          tmdbService.filterUpcomingCatalogForMaturity(
            upcomingCatalog,
            tier: widget.activeProfile.maturityTier,
            languageCode: widget.languageCode,
          ),
        ]);
        homeRecommendations = filtered[0] as List<MediaSummary>;
        upcomingCatalog = filtered[1] as UpcomingCatalog;
      }
      if (!mounted || loadGeneration != _catalogLoadGeneration) {
        return;
      }
      final focusedRailTitle = _focusedRailTitle;
      final focusedItemIndex = _focusedRailItemIndex;
      setState(() {
        _homeRecommendations = homeRecommendations;
        _upcomingCatalog = upcomingCatalog;
      });
      if (focusedRailTitle != null && focusedItemIndex != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _focusedRailTitle != focusedRailTitle) {
            return;
          }
          final newRailIndex = _visibleRailTitles.indexOf(focusedRailTitle);
          if (newRailIndex >= 0) {
            unawaited(
              _railStateFor(newRailIndex)?.requestFocusAtIndex(focusedItemIndex),
            );
          }
        });
      }
    } catch (_) {
      // Base browse content is already usable. Optional enrichment failures
      // retain the existing fallback rows instead of blanking the screen.
    }
  }

  Future<void> _loadJustReleasedCatalog({required bool showErrors}) async {
    final service = widget.mediaCatalogService;
    if (service == null || _loadingJustReleased) {
      return;
    }
    setState(() {
      _loadingJustReleased = true;
      if (showErrors) {
        _justReleasedError = null;
      }
    });
    try {
      final releasedAfter =
          DateTime.now().toUtc().subtract(const Duration(days: 105));
      final catalog = await service.fetchJustReleasedCatalog(
        languageCode: widget.languageCode,
        releasedAfter: releasedAfter,
      );
      final visibleCatalog = _tmdbCatalogService == null
          ? catalog
          : await _tmdbCatalogService!.filterJustReleasedCatalogForMaturity(
              catalog,
              tier: widget.activeProfile.maturityTier,
              languageCode: widget.languageCode,
            );
      if (!mounted) {
        return;
      }
      setState(() {
        _justReleasedCatalog = visibleCatalog;
        _loadingJustReleased = false;
        _justReleasedError = null;
      });
      final homeCatalog = _catalog;
      if (homeCatalog != null) {
        _prepareTabHeroLogos(
          homeCatalog,
          justReleasedCatalog: visibleCatalog,
        );
      }
      if (widget.browseMode == BrowseMode.newPopular) {
        _requestInitialFocus();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingJustReleased = false;
        if (showErrors) {
          _justReleasedError = userFacingErrorMessage(
            error,
            fallback: 'The latest release rails could not be loaded.',
          );
        }
      });
    }
  }

  Future<Uri?> _loadPreviewUri(
    MediaSummary item, {
    bool muted = true,
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

  void _prepareTabHeroLogos(
    HomeCatalogData catalog, {
    JustReleasedCatalog? justReleasedCatalog,
  }) {
    final candidates = <MediaSummary>[
      for (final mode in BrowseMode.values)
        _featuredForMode(
          catalog,
          mode,
          justReleasedCatalog: justReleasedCatalog ?? _justReleasedCatalog,
        ),
    ];
    final seen = <String>{};
    for (final item in candidates) {
      if (seen.add(item.saveKey)) {
        unawaited(_prepareTitleLogo(item, notifyWhenReady: true));
      }
    }
  }

  Future<void> _prepareTitleLogo(
    MediaSummary item, {
    required bool notifyWhenReady,
  }) async {
    final service = _tmdbCatalogService;
    if (service == null) return;
    final generation = _logoPreparationGeneration;
    final preparationKey = '${widget.languageCode}:${item.saveKey}';
    if (!_logoPreparationKeys.add(preparationKey)) return;

    try {
      final cached = service.peekPreferredTitleLogo(
        tmdbId: item.tmdbId,
        mediaType: item.mediaType,
        languageCode: widget.languageCode,
      );
      final logo = cached ??
          await service
              .fetchPreferredTitleLogo(
                tmdbId: item.tmdbId,
                mediaType: item.mediaType,
                languageCode: widget.languageCode,
              )
              .catchError((_) => null);
      if (!mounted || generation != _logoPreparationGeneration) return;

      _preparedTitleLogos[item.saveKey] = logo;
      if (notifyWhenReady) setState(() {});
      if (logo != null) {
        await TmdbImageService.preload(
          context,
          logo.imageUrl,
          preset: TmdbImagePreset.titleLogo,
          decodeWidth: 700,
        );
      }
    } catch (_) {
      // The normal text title remains available when a logo cannot be warmed.
    }
  }

  void _handleRailCardFocusChanged(
    String itemKey,
    int railIndex,
    int itemIndex,
    bool focused,
    BuildContext cardContext,
  ) {
    if (focused) {
      _focusedRailItemKey = itemKey;
      _focusedRailTitle = railIndex >= 0 && railIndex < _visibleRailTitles.length
          ? _visibleRailTitles[railIndex]
          : null;
      _focusedRailItemIndex = itemIndex;
      widget.onFocusedItemChanged?.call(railIndex, itemIndex);
      // Keep the whole rail visible, including its heading. Using only the
      // card rectangle allowed the heading to slip underneath the fixed TV
      // navigation bar when the first card expanded.
      final railContext = _railStateFor(railIndex)?.context;
      _ensureBodyVisibleOnFocusedRailCard(
        railContext ?? cardContext,
        itemKey,
      );
      return;
    }

    if (_focusedRailItemKey == itemKey) {
      _focusedRailItemKey = null;
      _focusedRailTitle = null;
      _focusedRailItemIndex = null;
    }
  }

  void _handleHeaderFocusChanged(bool focused) {
    if (!focused) {
      return;
    }
    _scrollBodyToTop();
  }

  void _handleHeroControlFocusChanged(bool focused) {
    if (!focused) {
      return;
    }
    if (FocusManager.instance.primaryFocus == _heroPlayFocusNode) {
      _scrollBodyToTop();
    }
  }

  void _handleNeighborRailFocusRequest(
    int railIndex,
    int itemIndex,
    TraversalDirection direction,
  ) {
    switch (direction) {
      case TraversalDirection.up:
        if (railIndex <= 0) {
          _heroActionFocusNodeForIndex(itemIndex).requestFocus();
          return;
        }
        final upRail = _railStateFor(railIndex - 1);
        if (upRail != null) {
          unawaited(upRail.requestFocusAtIndex(itemIndex));
          return;
        }
        _heroActionFocusNodeForIndex(itemIndex).requestFocus();
        return;
      case TraversalDirection.down:
        final downRail = _railStateFor(railIndex + 1);
        if (downRail != null) {
          unawaited(downRail.requestFocusAtIndex(itemIndex));
        }
        return;
      case TraversalDirection.left:
      case TraversalDirection.right:
        return;
    }
  }

  void _scrollBodyToTop() {
    if (!_bodyScrollController.hasClients) {
      return;
    }

    final targetOffset = _bodyScrollController.position.minScrollExtent;
    if ((_bodyScrollController.offset - targetOffset).abs() < 1) {
      return;
    }

    _requestBodyScrollTo(targetOffset);
  }

  void _jumpBodyToTop() {
    if (!_bodyScrollController.hasClients) {
      return;
    }

    final targetOffset = _bodyScrollController.position.minScrollExtent;
    if ((_bodyScrollController.offset - targetOffset).abs() < 1) {
      return;
    }

    _bodyScrollController.jumpTo(targetOffset);
  }

  void _ensureBodyVisibleOnFocusedRailCard(
    BuildContext cardContext,
    String itemKey,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !cardContext.mounted || _focusedRailItemKey != itemKey) {
        return;
      }
      // Align the complete rail rather than a card-only rectangle. This keeps
      // the section heading clear of the fixed TV top bar and gives every
      // vertical D-pad move the same predictable camera position. Horizontal
      // moves reuse the same rail context, so they do not shift the page.
      unawaited(
        Scrollable.ensureVisible(
          cardContext,
          alignment: 0.04,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        ),
      );
    });
  }

  void _requestBodyScrollTo(double targetOffset) {
    if (!_bodyScrollController.hasClients) {
      return;
    }

    final position = _bodyScrollController.position;
    final clampedTarget = targetOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((clampedTarget - position.pixels).abs() < 1) {
      return;
    }

    _runBodyScrollAnimation(clampedTarget.toDouble());
  }

  void _runBodyScrollAnimation(double targetOffset) {
    if (!_bodyScrollController.hasClients) {
      return;
    }
    final position = _bodyScrollController.position;
    if ((position.pixels - targetOffset).abs() < 1) {
      return;
    }

    final requestId = ++_bodyScrollRequestSequence;
    unawaited(
      _bodyScrollController
          .animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      )
          .catchError((_) {
        // Ignore transient ScrollController state races during quick focus hops.
      }).whenComplete(() {
        if (!mounted || requestId != _bodyScrollRequestSequence) {
          return;
        }
      }),
    );
  }

  GlobalKey<_ContentRailState> _railKeyForTitle(String title) {
    return _railKeys.putIfAbsent(
      title,
      () => GlobalKey<_ContentRailState>(debugLabel: 'HomeRail($title)'),
    );
  }

  _ContentRailState? _railStateFor(int index) {
    if (index < 0 || index >= _visibleRailTitles.length) {
      return null;
    }
    return _railKeys[_visibleRailTitles[index]]?.currentState;
  }

  FocusNode _heroActionFocusNodeForIndex(int itemIndex) {
    final actionNodes = _heroActionFocusNodes;
    if (actionNodes.length == 1) {
      return actionNodes.first;
    }
    final clampedIndex = itemIndex.clamp(0, actionNodes.length - 1);
    return actionNodes[clampedIndex];
  }

  void _requestInitialFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loading || _catalog == null) {
        return;
      }
      if (widget.initialScrollOffset <= 1) {
        _jumpBodyToTop();
        _heroPlayFocusNode.requestFocus();
      } else {
        final railIndex = widget.initialFocusedRailIndex;
        final itemIndex = widget.initialFocusedItemIndex;
        if (railIndex != null && itemIndex != null) {
          unawaited(_railStateFor(railIndex)?.requestFocusAtIndex(itemIndex));
        }
      }
    });
  }

  MediaSummary _currentHeroItem(
    HomeCatalogData catalog, {
    required List<MediaSummary> homeRecommendations,
    JustReleasedCatalog? justReleasedCatalog,
  }) {
    return _featuredForMode(
      catalog,
      widget.browseMode,
      justReleasedCatalog: justReleasedCatalog,
    );
  }

  List<MediaSummary> _resolvedHomeRecommendations(HomeCatalogData catalog) {
    if (_homeRecommendations.isNotEmpty) {
      return _homeRecommendations;
    }
    return catalog.newAndPopular;
  }

  String get _homeRecommendationsTitle => _homeRecommendations.isEmpty
      ? 'New & Popular'
      : 'Recommended For ${widget.activeProfile.name}';
}

class _HeroBanner extends StatefulWidget {
  const _HeroBanner({
    required this.item,
    required this.titleLogo,
    required this.browseMode,
    required this.isSaved,
    required this.hasResume,
    required this.previewLoader,
    required this.autoplayPreviews,
    required this.muteAutoplayTrailers,
    required this.playFocusNode,
    required this.infoFocusNode,
    required this.listFocusNode,
    required this.heroActionUpFallbackNodes,
    required this.heroActionDownFallbackNodes,
    required this.onHeroControlFocusChanged,
    required this.onPlay,
    required this.onOpenDetails,
    this.onToggleSaved,
  });

  final MediaSummary item;
  final TmdbTitleLogo? titleLogo;
  final BrowseMode browseMode;
  final bool isSaved;
  final bool hasResume;
  final Future<Uri?> Function(MediaSummary item, {bool muted}) previewLoader;
  final bool autoplayPreviews;
  final bool muteAutoplayTrailers;
  final FocusNode playFocusNode;
  final FocusNode infoFocusNode;
  final FocusNode listFocusNode;
  final List<FocusNode> heroActionUpFallbackNodes;
  final List<FocusNode> heroActionDownFallbackNodes;
  final ValueChanged<bool> onHeroControlFocusChanged;
  final VoidCallback onPlay;
  final VoidCallback onOpenDetails;
  final VoidCallback? onToggleSaved;

  @override
  State<_HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<_HeroBanner> {
  static const Duration _previewLoadDelay = Duration(milliseconds: 1800);

  Timer? _previewLoadTimer;
  Uri? _previewUri;
  bool _loadingPreview = false;
  bool _requestedPreview = false;
  bool _heroFocused = false;
  int _previewRequestId = 0;

  @override
  void initState() {
    super.initState();
    CheriflixRuntimePressureController.instance.addListener(
      _handleRuntimePressureChanged,
    );
    widget.playFocusNode.addListener(_handleHeroFocusNodeChanged);
    widget.infoFocusNode.addListener(_handleHeroFocusNodeChanged);
    widget.listFocusNode.addListener(_handleHeroFocusNodeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _syncHeroFocusState();
    });
  }

  @override
  void didUpdateWidget(covariant _HeroBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playFocusNode != widget.playFocusNode) {
      oldWidget.playFocusNode.removeListener(_handleHeroFocusNodeChanged);
      widget.playFocusNode.addListener(_handleHeroFocusNodeChanged);
    }
    if (oldWidget.infoFocusNode != widget.infoFocusNode) {
      oldWidget.infoFocusNode.removeListener(_handleHeroFocusNodeChanged);
      widget.infoFocusNode.addListener(_handleHeroFocusNodeChanged);
    }
    if (oldWidget.listFocusNode != widget.listFocusNode) {
      oldWidget.listFocusNode.removeListener(_handleHeroFocusNodeChanged);
      widget.listFocusNode.addListener(_handleHeroFocusNodeChanged);
    }
    if (oldWidget.item.saveKey != widget.item.saveKey ||
        oldWidget.autoplayPreviews != widget.autoplayPreviews ||
        oldWidget.muteAutoplayTrailers != widget.muteAutoplayTrailers) {
      _previewRequestId += 1;
      _previewLoadTimer?.cancel();
      _requestedPreview = false;
      _previewUri = null;
      _loadingPreview = false;
      _syncPreviewState();
    }
  }

  @override
  void dispose() {
    CheriflixRuntimePressureController.instance.removeListener(
      _handleRuntimePressureChanged,
    );
    _previewRequestId += 1;
    _previewLoadTimer?.cancel();
    widget.playFocusNode.removeListener(_handleHeroFocusNodeChanged);
    widget.infoFocusNode.removeListener(_handleHeroFocusNodeChanged);
    widget.listFocusNode.removeListener(_handleHeroFocusNodeChanged);
    super.dispose();
  }

  void _syncPreviewState() {
    _previewLoadTimer?.cancel();
    if (!_heroFocused ||
        !widget.autoplayPreviews ||
        !cheriflixTrailerPreviewsSupported ||
        CheriflixRuntimePressureController
            .instance.previewSuspendedForSession) {
      _clearPreviewState();
      return;
    }
    if (_requestedPreview || _loadingPreview || _previewUri != null) {
      return;
    }
    _previewLoadTimer = Timer(_previewLoadDelay, _loadPreview);
  }

  Future<void> _loadPreview() async {
    if (!mounted ||
        !widget.autoplayPreviews ||
        !cheriflixTrailerPreviewsSupported ||
        CheriflixRuntimePressureController
            .instance.previewSuspendedForSession ||
        _requestedPreview) {
      return;
    }
    if (!_heroFocused) {
      return;
    }

    final requestId = ++_previewRequestId;
    _requestedPreview = true;
    setState(() => _loadingPreview = true);
    try {
      final previewUri = await widget.previewLoader(
        widget.item,
        muted: widget.muteAutoplayTrailers,
      );
      if (!mounted ||
          requestId != _previewRequestId ||
          !_heroFocused ||
          !widget.autoplayPreviews ||
          !cheriflixTrailerPreviewsSupported ||
          CheriflixRuntimePressureController
              .instance.previewSuspendedForSession) {
        return;
      }
      setState(() {
        _previewUri = previewUri;
        _loadingPreview = false;
      });
    } catch (_) {
      CheriflixRuntimePressureController.instance.recordPreviewFailure();
      if (!mounted || requestId != _previewRequestId) {
        return;
      }
      setState(() => _loadingPreview = false);
    }
  }

  void _handleHeroControlFocusChanged(bool focused) {
    widget.onHeroControlFocusChanged(focused);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncHeroFocusState());
  }

  void _handleHeroFocusNodeChanged() {
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncHeroFocusState());
  }

  void _syncHeroFocusState() {
    if (!mounted) {
      return;
    }
    final hasHeroFocus = widget.playFocusNode.hasFocus ||
        widget.infoFocusNode.hasFocus ||
        (widget.onToggleSaved != null && widget.listFocusNode.hasFocus);
    if (_heroFocused == hasHeroFocus) {
      if (hasHeroFocus &&
          widget.autoplayPreviews &&
          !_requestedPreview &&
          !_loadingPreview &&
          _previewUri == null) {
        _syncPreviewState();
      }
      return;
    }
    _heroFocused = hasHeroFocus;
    _syncPreviewState();
  }

  void _clearPreviewState() {
    _previewRequestId += 1;
    _previewLoadTimer?.cancel();
    _requestedPreview = false;
    if (!mounted) {
      _previewUri = null;
      _loadingPreview = false;
      return;
    }
    if (_previewUri == null && !_loadingPreview) {
      return;
    }
    setState(() {
      _previewUri = null;
      _loadingPreview = false;
    });
  }

  void _handleRuntimePressureChanged() {
    if (!CheriflixRuntimePressureController
        .instance.previewSuspendedForSession) {
      return;
    }
    _clearPreviewState();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = CheriflixTvLayout.fromWidth(constraints.maxWidth);
        final devicePixelRatio =
            MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
        final compact = layout.isCompact;
        final bannerHeight = layout.homeHeroHeight;
        final heroTitleSize = _heroTitleFontSize(
          widget.item.title,
          compact: compact,
        );
        return SizedBox(
          key: const ValueKey<String>('home_hero_banner'),
          height: bannerHeight,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Color(0xFF050505),
                      Color(0xFF1B1B1B),
                      Color(0xFF2D1C09),
                    ],
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CheriflixNetworkImage(
                    imageUrl: widget.item.backdropUrl,
                    width: constraints.maxWidth,
                    height: bannerHeight,
                    devicePixelRatio: devicePixelRatio,
                    preset: TmdbImagePreset.heroBackdrop,
                    maxDecodePixels: 1600,
                    placeholderColor: Colors.transparent,
                  ),
                ),
              ),
              Positioned.fill(
                child: BackdropTrailerPreview(
                  previewUri: _previewUri,
                  mode: TrailerPreviewMode.backdrop,
                  borderRadius: 16,
                ),
              ),
              if (_loadingPreview)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                        color: Color(0x18000000),
                      ),
                    ),
                  ),
                ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: <Color>[
                        Color(0xF4000000),
                        Color(0xED000000),
                        Color(0xBF000000),
                        Color(0x7D000000),
                        Color(0x32000000),
                        Color(0x00000000),
                      ],
                      stops: <double>[0, 0.12, 0.28, 0.46, 0.7, 1],
                    ),
                  ),
                ),
              ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.center,
                      colors: <Color>[
                        Color(0xDC000000),
                        Color(0x54000000),
                        Color(0x00000000),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  layout.homeHeroContentLeftPadding,
                  layout.homeHeroContentTopPadding,
                  compact
                      ? constraints.maxWidth * 0.5
                      : constraints.maxWidth * 0.58,
                  layout.homeHeroContentBottomPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    Text.rich(
                      TextSpan(
                        style: CheriflixTypography.heroBannerEyebrow.copyWith(
                          fontSize: 14,
                        ),
                        children: <InlineSpan>[
                          const TextSpan(
                            text: 'CHERIFLIX',
                            style: TextStyle(
                              color: CheriflixColors.accentRed,
                            ),
                          ),
                          TextSpan(
                            text: ' ${widget.browseMode.heroLabelSuffix}',
                            style: const TextStyle(
                              color: CheriflixColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    CheriflixTitleMark(
                      key: ValueKey<String>(
                        'hero_title_mark_${widget.item.saveKey}',
                      ),
                      imageKey: const ValueKey<String>('hero_title_logo'),
                      logo: widget.titleLogo,
                      fallbackTitle: widget.item.title.toUpperCase(),
                      maxWidth: layout.homeHeroTitleMaxWidth,
                      maxHeight: layout.value(
                        compact: 90,
                        standard: 118,
                        wide: 138,
                      ),
                      fallbackMaxLines: compact ? 2 : 3,
                      fallbackStyle:
                          CheriflixTypography.heroBannerTitle.copyWith(
                        fontSize: heroTitleSize,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        CheriflixBadge(
                          label: widget.browseMode == BrowseMode.newPopular
                              ? 'NEW & POPULAR'
                              : widget.item.mediaLabel,
                          backgroundColor: CheriflixColors.accentRed,
                          textStyle: CheriflixTypography.heroBannerMeta
                              .copyWith(fontSize: 14),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          borderRadius: 4,
                        ),
                        Text(
                          _heroMomentumText(widget.item, widget.browseMode),
                          style: CheriflixTypography.heroBannerMeta.copyWith(
                            fontSize: 14,
                            color: CheriflixColors.textPrimary,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 14,
                          color: const Color(0x55FFFFFF),
                        ),
                        Text(
                          _heroRatingText(widget.item),
                          style: CheriflixTypography.heroBannerMeta.copyWith(
                            fontSize: 14,
                            color: CheriflixColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: compact ? 240 : 400,
                      height: 1,
                      color: const Color(0x36FFFFFF),
                    ),
                    const SizedBox(height: 18),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: layout.homeHeroCopyMaxWidth,
                      ),
                      child: Text(
                        widget.item.overview ?? 'No overview available.',
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: CheriflixTypography.heroBannerSynopsis.copyWith(
                          fontSize: 14.8,
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      child: Row(
                        key: const ValueKey<String>('hero_action_row'),
                        children: <Widget>[
                          TvActionButton(
                            key: const ValueKey<String>('hero_play_button'),
                            label: widget.hasResume ? 'Resume' : 'Play',
                            icon: Icons.play_arrow_rounded,
                            onPressed: widget.onPlay,
                            autofocus: false,
                            focusNode: widget.playFocusNode,
                            variant: TvButtonVariant.danger,
                            leftFallbackNodes: <FocusNode>[
                              widget.playFocusNode,
                            ],
                            rightFallbackNodes: <FocusNode>[
                              widget.infoFocusNode,
                            ],
                            upFallbackNodes: widget.heroActionUpFallbackNodes,
                            downFallbackNodes:
                                widget.heroActionDownFallbackNodes,
                            onFocusChanged: _handleHeroControlFocusChanged,
                            ensureVisibleOnFocus: false,
                            borderRadius: 8,
                            padding: EdgeInsets.symmetric(
                              horizontal: layout.value(
                                compact: 14,
                                standard: 16,
                                wide: 18,
                              ),
                              vertical: layout.value(
                                compact: 11,
                                standard: 12,
                                wide: 13,
                              ),
                            ),
                            labelStyle: CheriflixTypography.button.copyWith(
                              fontSize: 13.5,
                              letterSpacing: 0,
                            ),
                            iconSize: 20,
                            iconGap: 7,
                            focusScale: 1.02,
                          ),
                          SizedBox(width: layout.homeHeroActionSpacing),
                          TvActionButton(
                            key: const ValueKey<String>('hero_info_button'),
                            label: 'More Info',
                            icon: Icons.info_outline_rounded,
                            onPressed: widget.onOpenDetails,
                            focusNode: widget.infoFocusNode,
                            variant: TvButtonVariant.dark,
                            leftFallbackNodes: <FocusNode>[
                              widget.playFocusNode,
                            ],
                            rightFallbackNodes: <FocusNode>[
                              widget.onToggleSaved != null
                                  ? widget.listFocusNode
                                  : widget.infoFocusNode,
                            ],
                            upFallbackNodes: widget.heroActionUpFallbackNodes,
                            downFallbackNodes:
                                widget.heroActionDownFallbackNodes,
                            onFocusChanged: _handleHeroControlFocusChanged,
                            ensureVisibleOnFocus: false,
                            borderRadius: 8,
                            padding: EdgeInsets.symmetric(
                              horizontal: layout.value(
                                compact: 14,
                                standard: 16,
                                wide: 18,
                              ),
                              vertical: layout.value(
                                compact: 10,
                                standard: 11,
                                wide: 12,
                              ),
                            ),
                            labelStyle: CheriflixTypography.button.copyWith(
                              fontSize: 14,
                              letterSpacing: 0,
                            ),
                            iconSize: 18,
                            iconGap: 7,
                            focusScale: 1.02,
                          ),
                          if (widget.onToggleSaved != null) ...<Widget>[
                            SizedBox(width: layout.homeHeroActionSpacing),
                            TvActionButton(
                              key:
                                  const ValueKey<String>('hero_my_list_button'),
                              label: widget.isSaved
                                  ? 'In My List'
                                  : 'Add to My List',
                              onPressed: widget.onToggleSaved,
                              focusNode: widget.listFocusNode,
                              variant: TvButtonVariant.dark,
                              leftFallbackNodes: <FocusNode>[
                                widget.infoFocusNode,
                              ],
                              rightFallbackNodes: <FocusNode>[
                                widget.listFocusNode,
                              ],
                              upFallbackNodes: widget.heroActionUpFallbackNodes,
                              downFallbackNodes:
                                  widget.heroActionDownFallbackNodes,
                              onFocusChanged: _handleHeroControlFocusChanged,
                              ensureVisibleOnFocus: false,
                              borderRadius: 8,
                              padding: EdgeInsets.symmetric(
                                horizontal: layout.value(
                                  compact: 14,
                                  standard: 16,
                                  wide: 18,
                                ),
                                vertical: layout.value(
                                  compact: 10,
                                  standard: 11,
                                  wide: 12,
                                ),
                              ),
                              labelStyle: CheriflixTypography.button.copyWith(
                                fontSize: 14,
                                letterSpacing: 0,
                              ),
                              focusScale: 1.02,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ContentRail extends StatefulWidget {
  const _ContentRail({
    super.key,
    required this.title,
    required this.items,
    required this.savedTitleKeys,
    required this.onOpenTitle,
    required this.onPlayTitle,
    required this.previewLoader,
    required this.autoplayPreviews,
    required this.muteAutoplayTrailers,
    required this.onCardFocusChanged,
    this.onToggleSaved,
    this.firstItemFocusNode,
    this.upFocusNodeForIndex,
    this.downFocusNodeForIndex,
    this.onRequestNeighborFocus,
  });

  final String title;
  final List<_RailCardData> items;
  final Set<String> savedTitleKeys;
  final ValueChanged<MediaSummary> onOpenTitle;
  final ValueChanged<MediaSummary>? onPlayTitle;
  final Future<Uri?> Function(MediaSummary item, {bool muted}) previewLoader;
  final bool autoplayPreviews;
  final bool muteAutoplayTrailers;
  final void Function(
    String itemKey,
    int itemIndex,
    bool focused,
    BuildContext cardContext,
  ) onCardFocusChanged;
  final ValueChanged<MediaSummary>? onToggleSaved;
  final FocusNode? firstItemFocusNode;
  final FocusNode? Function(int itemIndex)? upFocusNodeForIndex;
  final FocusNode? Function(int itemIndex)? downFocusNodeForIndex;
  final void Function(int itemIndex, TraversalDirection direction)?
      onRequestNeighborFocus;

  @override
  State<_ContentRail> createState() => _ContentRailState();
}

class _ContentRailState extends State<_ContentRail> {
  static const double _expandedPosterAspectRatio = 16 / 9;

  late final ScrollController _scrollController = ScrollController();
  List<FocusNode> _focusNodes = <FocusNode>[];
  bool _railExpanded = false;
  int _scrollRequestSequence = 0;

  CheriflixTvLayout get _layout => CheriflixTvLayout.of(context);
  double get _cardWidth => _layout.homeRailCardWidth;
  double get _cardPosterHeight => _layout.homeRailCardPosterHeight;
  double get _cardGap => _layout.homeRailGap;
  double get _expandedPosterHeight => _layout.homeRailExpandedPosterHeight;
  double get _expandedWidth =>
      _expandedPosterHeight * _expandedPosterAspectRatio;
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
  double get _collapsedRailHeight =>
      _cardPosterHeight + _collapsedDetailsHeight + _railHeightBuffer;
  double get _expandedRailHeight => _collapsedRailHeight;

  double get _railHeight =>
      _railExpanded ? _expandedRailHeight : _collapsedRailHeight;

  @override
  void initState() {
    super.initState();
    // FocusNodes are created lazily in _focusNodeForIndex so that only
    // the visible-window items participate in the traversal graph.
  }

  @override
  void didUpdateWidget(covariant _ContentRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_itemsChanged(oldWidget.items, widget.items)) {
      _disposeFocusNodes();
      // Nodes will be created lazily on next build.
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _disposeFocusNodes();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.title,
          style: CheriflixTypography.sectionTitle.copyWith(
            fontSize: _layout.sectionTitleSize,
          ),
        ),
        SizedBox(height: _layout.value(compact: 10, standard: 11, wide: 12)),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: _railHeight,
          child: ListView.separated(
            key: ValueKey<String>('home_rail_list_${widget.title}'),
            controller: _scrollController,
            clipBehavior: Clip.none,
            scrollDirection: Axis.horizontal,
            // Allow lazy item building: with NeverScrollableScrollPhysics
            // the ListView lays out every child immediately. Using
            // ClampingScrollPhysics lets Flutter only build the visible
            // window while still supporting the programmatic _scrollController
            // centering used for D-pad navigation.
            physics: const ClampingScrollPhysics(),
            // Build ~3 extra cards worth of width outside each edge so
            // focused-card expansion doesn't flash empty space.
            cacheExtent: _cardWidth * 3,
            padding: EdgeInsets.zero,
            itemCount: widget.items.length,
            separatorBuilder: (_, __) => SizedBox(width: _cardGap),
            itemBuilder: (context, index) {
              final item = widget.items[index];
              return Builder(
                builder: (cardContext) => TvPosterButton(
                  key: ValueKey<String>(
                    'home_rail_${widget.title}_${item.summary.saveKey}_$index',
                  ),
                  title: item.title,
                  subtitle: item.subtitle,
                  imageUrl: item.imageUrl,
                  posterSurfaceKey: ValueKey<String>(
                    'home_rail_surface_${widget.title}_${item.summary.saveKey}_$index',
                  ),
                  width: _cardWidth,
                  posterHeight: _cardPosterHeight,
                  expandedWidth: _expandedWidth,
                  expandedPosterHeight: _expandedPosterHeight,
                  alignment: Alignment.bottomLeft,
                  ensureVisibleOnFocus: false,
                  reserveExpandedSpace: true,
                  overlayExpandedDetails: true,
                  autoplayPreviewEnabled: widget.autoplayPreviews,
                  autoplayPreviewMuted: widget.muteAutoplayTrailers,
                  previewLoadDelay: const Duration(milliseconds: 1800),
                  previewLoader: () => widget.previewLoader(
                    item.summary,
                    muted: widget.muteAutoplayTrailers,
                  ),
                  focusNode: _focusNodeForIndex(index),
                  leftFallbackNodes: <FocusNode>[
                    index > 0
                        ? _focusNodeForIndex(index - 1)
                        : _focusNodeForIndex(index),
                  ],
                  rightFallbackNodes: <FocusNode>[
                    index < widget.items.length - 1
                        ? _focusNodeForIndex(index + 1)
                        : _focusNodeForIndex(index),
                  ],
                  upFallbackNodes: () {
                    final node = widget.upFocusNodeForIndex?.call(index);
                    if (node == null) {
                      return const <FocusNode>[];
                    }
                    return <FocusNode>[node];
                  }(),
                  downFallbackNodes: () {
                    final node = widget.downFocusNodeForIndex?.call(index);
                    if (node == null) {
                      return const <FocusNode>[];
                    }
                    return <FocusNode>[node];
                  }(),
                  onPressed: item.progress != null && widget.onPlayTitle != null
                      ? () => widget.onPlayTitle!(item.summary)
                      : () => widget.onOpenTitle(item.summary),
                  onPlay: () =>
                      (widget.onPlayTitle ?? widget.onOpenTitle)(item.summary),
                  onOpenInfo: () => widget.onOpenTitle(item.summary),
                  expandOnFocus: true,
                  expandedImageUrl: item.summary.backdropUrl ?? item.imageUrl,
                  posterBottomOverlay: item.progress == null
                      ? null
                      : _RailProgressOverlay(progress: item.progress!),
                  onDirectionalFocus: (direction) =>
                      _handleDirectionalFocus(index, direction),
                  onFocusChanged: (focused, _, __) {
                    widget.onCardFocusChanged(
                      item.summary.saveKey,
                      index,
                      focused,
                      cardContext,
                    );
                    if (focused) {
                      _centerFocusedIndex(index);
                    }
                    _updateRailExpansion(focused);
                  },
                  onToggleSaved: widget.onToggleSaved == null
                      ? null
                      : () => widget.onToggleSaved!(item.summary),
                  saved: widget.savedTitleKeys.contains(item.summary.saveKey),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Lazily grow the [FocusNode] pool so that a node for [index] exists.
  /// Nodes are only created for indices that have been built (visible
  /// window), which dramatically reduces traversal-graph work on first paint.
  void _ensureFocusNodeForIndex(int index) {
    // The pool is never shrunk mid-life; excess nodes survive until
    // _disposeFocusNodes (called on item-list changes or dispose).
    while (_focusNodes.length <= index &&
        _focusNodes.length < widget.items.length) {
      _focusNodes.add(FocusNode(
        debugLabel: 'HomeRail(${widget.title})[${_focusNodes.length}]',
      ));
    }
  }

  void _disposeFocusNodes() {
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    _focusNodes = <FocusNode>[];
  }

  bool _itemsChanged(
      List<_RailCardData> oldItems, List<_RailCardData> newItems) {
    if (oldItems.length != newItems.length) {
      return true;
    }
    for (var index = 0; index < oldItems.length; index += 1) {
      if (oldItems[index].summary.saveKey != newItems[index].summary.saveKey) {
        return true;
      }
    }
    return false;
  }

  FocusNode _focusNodeForIndex(int itemIndex) {
    if (widget.firstItemFocusNode != null && itemIndex == 0) {
      return widget.firstItemFocusNode!;
    }
    _ensureFocusNodeForIndex(itemIndex);
    return _focusNodes[itemIndex];
  }

  void _updateRailExpansion(bool focused) {
    if (focused) {
      if (!_railExpanded) {
        setState(() => _railExpanded = true);
      }
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_railHasFocus()) {
        return;
      }
      if (_railExpanded) {
        setState(() => _railExpanded = false);
      }
    });
  }

  bool _railHasFocus() {
    if (widget.firstItemFocusNode?.hasFocus == true) {
      return true;
    }
    for (final node in _focusNodes) {
      if (node.hasFocus) {
        return true;
      }
    }
    return false;
  }

  FocusNode? focusNodeForIndex(int itemIndex) {
    if (widget.items.isEmpty) {
      return null;
    }
    final clampedIndex = itemIndex.clamp(0, widget.items.length - 1);
    return _focusNodeForIndex(clampedIndex);
  }

  Future<void> requestFocusAtIndex(int itemIndex) async {
    final targetNode = focusNodeForIndex(itemIndex);
    if (targetNode == null) {
      return;
    }
    if (targetNode.context != null) {
      targetNode.requestFocus();
      unawaited(_scrollToIndexIfNeeded(itemIndex));
      return;
    }
    await _scrollToIndexIfNeeded(itemIndex);
    if (!mounted) {
      return;
    }
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

  void _centerFocusedIndex(int itemIndex) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final focusNode = _focusNodeForIndex(itemIndex);
      if (!focusNode.hasPrimaryFocus) {
        return;
      }
      unawaited(_scrollToIndexIfNeeded(itemIndex));
    });
  }

  KeyEventResult _handleDirectionalFocus(
    int itemIndex,
    TraversalDirection direction,
  ) {
    switch (direction) {
      case TraversalDirection.left:
        if (itemIndex <= 0) {
          return KeyEventResult.ignored;
        }
        _requestFocusAt(itemIndex - 1);
        return KeyEventResult.handled;
      case TraversalDirection.right:
        if (itemIndex >= widget.items.length - 1) {
          return KeyEventResult.ignored;
        }
        _requestFocusAt(itemIndex + 1);
        return KeyEventResult.handled;
      case TraversalDirection.up:
        if (widget.onRequestNeighborFocus != null) {
          widget.onRequestNeighborFocus!(
            itemIndex,
            TraversalDirection.up,
          );
          return KeyEventResult.handled;
        }
        final targetNode = widget.upFocusNodeForIndex?.call(itemIndex);
        if (targetNode == null) {
          return KeyEventResult.ignored;
        }
        targetNode.requestFocus();
        return KeyEventResult.handled;
      case TraversalDirection.down:
        if (widget.onRequestNeighborFocus != null) {
          widget.onRequestNeighborFocus!(
            itemIndex,
            TraversalDirection.down,
          );
          return KeyEventResult.handled;
        }
        final targetNode = widget.downFocusNodeForIndex?.call(itemIndex);
        if (targetNode == null) {
          return KeyEventResult.ignored;
        }
        targetNode.requestFocus();
        return KeyEventResult.handled;
    }
  }

  void _requestFocusAt(int itemIndex) {
    unawaited(requestFocusAtIndex(itemIndex));
  }

  Future<void> _scrollToIndexIfNeeded(int itemIndex) async {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final safeMargin = _layout.homeRailSafeMargin;
    final leadingOffset = itemIndex * (_cardWidth + _cardGap);
    final itemStart = leadingOffset;
    final itemEnd = leadingOffset + _expandedWidth;
    final viewportStart = position.pixels + safeMargin;
    final viewportEnd =
        position.pixels + position.viewportDimension - safeMargin;
    double? desiredPixels;
    if (itemStart < viewportStart) {
      desiredPixels = itemStart - safeMargin;
    } else if (itemEnd > viewportEnd) {
      desiredPixels = itemEnd - position.viewportDimension + safeMargin;
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

    final requestId = ++_scrollRequestSequence;
    await _scrollController
        .animateTo(
      clampedPixels.toDouble(),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
    )
        .catchError((_) {
      // New focus moves cancel old rail scroll animations during rapid input.
    });
    if (!mounted || requestId != _scrollRequestSequence) {
      return;
    }
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.title,
    required this.message,
    this.action,
  });

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: CheriflixPanel(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: CheriflixTypography.sectionTitle.copyWith(
                    fontSize: 22,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: CheriflixTypography.body.copyWith(
                    color: CheriflixColors.textSecondary,
                  ),
                ),
                if (action != null) ...<Widget>[
                  const SizedBox(height: 22),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BrowseLoadingSkeleton extends StatelessWidget {
  const _BrowseLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final layout = CheriflixTvLayout.of(context);
    const base = Color(0xFF1D1D1D);
    const highlight = Color(0xFF292929);
    return ExcludeSemantics(
      child: ListView(
        padding: layout.pagePadding,
        physics: const NeverScrollableScrollPhysics(),
        children: <Widget>[
          Container(
            height: layout.homeHeroHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[base, highlight, base],
              ),
            ),
          ),
          const SizedBox(height: 24),
          for (var rail = 0; rail < 2; rail += 1) ...<Widget>[
            Container(
              width: 190,
              height: 22,
              alignment: Alignment.centerLeft,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: highlight,
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                child: SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: layout.homeRailCardPosterHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 6,
                separatorBuilder: (_, __) => SizedBox(width: layout.homeRailGap),
                itemBuilder: (_, __) => Container(
                  width: layout.homeRailCardWidth,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0x12FFFFFF)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
          ],
        ],
      ),
    );
  }
}

class _RailData {
  const _RailData({
    required this.title,
    required this.items,
  });

  final String title;
  final List<_RailCardData> items;
}

class _RailCardData {
  const _RailCardData({
    required this.summary,
    required this.title,
    required this.subtitle,
    this.progress,
  });

  factory _RailCardData.fromSummary(MediaSummary summary) {
    return _RailCardData(
      summary: summary,
      title: summary.title,
      subtitle: summary.metadataLabel,
    );
  }

  factory _RailCardData.fromProgress(PlaybackProgressEntry progress) {
    return _RailCardData(
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

class _RailProgressOverlay extends StatelessWidget {
  const _RailProgressOverlay({
    required this.progress,
  });

  final PlaybackProgressEntry progress;

  @override
  Widget build(BuildContext context) {
    return PlaybackProgressBar(
      value: progress.progressFraction,
      height: 6,
    );
  }
}

MediaSummary _featuredForMode(
  HomeCatalogData catalog,
  BrowseMode browseMode, {
  JustReleasedCatalog? justReleasedCatalog,
}) {
  final movies = _filterMedia(catalog, MediaType.movie);
  final shows = _filterMedia(catalog, MediaType.tv);
  switch (browseMode) {
    case BrowseMode.home:
      return catalog.featured;
    case BrowseMode.tvShows:
      return _pickFirst(shows) ?? catalog.featured;
    case BrowseMode.movies:
      return _pickFirst(movies) ?? catalog.featured;
    case BrowseMode.newPopular:
      return _pickFirst(
              justReleasedCatalog?.recentReleases ?? catalog.newAndPopular) ??
          catalog.featured;
  }
}

List<_RailData> _railsForMode(
  HomeCatalogData catalog,
  BrowseMode browseMode, {
  required PlaybackProgressSnapshot playbackProgress,
  required List<MediaSummary> homeRecommendations,
  required String homeRecommendationsTitle,
  JustReleasedCatalog? justReleasedCatalog,
  UpcomingCatalog upcomingCatalog = const UpcomingCatalog(
    movies: <MediaSummary>[],
    series: <MediaSummary>[],
    seasons: <UpcomingSeasonEntry>[],
  ),
}) {
  final continueWatching = playbackProgress.continueWatchingEntries;
  final continueWatchingTitleKeys =
      continueWatching.map((entry) => entry.saveKey).toSet();

  List<_RailCardData> summaryCards(Iterable<MediaSummary> items) {
    return items
        .where((item) => !continueWatchingTitleKeys.contains(item.saveKey))
        .map(_RailCardData.fromSummary)
        .toList(growable: false);
  }

  List<_RailCardData> continueWatchingCards({MediaType? mediaType}) {
    return continueWatching
        .where(
          (entry) => mediaType == null || entry.summary.mediaType == mediaType,
        )
        .map(_RailCardData.fromProgress)
        .toList(growable: false);
  }

  List<_RailCardData> upcomingCards(Iterable<MediaSummary> items) {
    return items.map((item) {
      final date = item.releaseDate;
      return _RailCardData(
        summary: item,
        title: item.title,
        subtitle: date == null
            ? 'COMING SOON'
            : 'COMING ${releaseDateLabel(date).toUpperCase()}',
      );
    }).toList(growable: false);
  }

  List<_RailCardData> seasonCards(Iterable<UpcomingSeasonEntry> items) {
    return items.map((item) {
      final stateLabel = switch (item.state) {
        SeasonReleaseState.upcoming =>
          'COMING ${releaseDateLabel(item.premiereDate).toUpperCase()}',
        SeasonReleaseState.currentlyAiring => 'AIRING NOW',
        SeasonReleaseState.recentlyStarted => 'NEW SEASON',
      };
      return _RailCardData(
        summary: item.summary,
        title: item.summary.title,
        subtitle: 'SEASON ${item.seasonNumber}  ·  $stateLabel',
      );
    }).toList(growable: false);
  }

  final trendingMovies = catalog.trending
      .where((item) => item.mediaType == MediaType.movie)
      .toList(growable: false);
  final trendingShows = catalog.trending
      .where((item) => item.mediaType == MediaType.tv)
      .toList(growable: false);
  final freshMovies = catalog.newAndPopular
      .where((item) => item.mediaType == MediaType.movie)
      .toList(growable: false);
  final freshShows = catalog.newAndPopular
      .where((item) => item.mediaType == MediaType.tv)
      .toList(growable: false);

  switch (browseMode) {
    case BrowseMode.home:
      return <_RailData>[
        _RailData(
          title: 'Coming Soon',
          items: upcomingCards(upcomingCatalog.mixed),
        ),
        _RailData(
          title: 'New On Streaming',
          items: summaryCards(catalog.newOnStreaming),
        ),
        _RailData(
          title: 'Trending Now',
          items: summaryCards(catalog.trending),
        ),
        _RailData(
          title: 'Continue Watching',
          items: continueWatchingCards(),
        ),
        _RailData(
          title: 'Popular Movies',
          items: summaryCards(catalog.popularMovies),
        ),
        _RailData(
          title: 'Popular Series',
          items: summaryCards(catalog.popularSeries),
        ),
        _RailData(
          title: homeRecommendationsTitle,
          items: summaryCards(homeRecommendations),
        ),
      ];
    case BrowseMode.tvShows:
      return <_RailData>[
        _RailData(
          title: 'Coming Soon Series',
          items: upcomingCards(upcomingCatalog.series),
        ),
        _RailData(
          title: 'New & Upcoming Seasons',
          items: seasonCards(upcomingCatalog.seasons),
        ),
        _RailData(
          title: 'Series Trending Today',
          items: summaryCards(trendingShows),
        ),
        _RailData(
          title: 'Popular Series',
          items: summaryCards(catalog.popularSeries),
        ),
        _RailData(
          title: 'Continue Your Series Queue',
          items: continueWatchingCards(mediaType: MediaType.tv),
        ),
        _RailData(
          title: 'Fresh Series Picks',
          items: summaryCards(freshShows),
        ),
      ];
    case BrowseMode.movies:
      return <_RailData>[
        _RailData(
          title: 'Coming Soon Movies',
          items: upcomingCards(upcomingCatalog.movies),
        ),
        _RailData(
          title: 'Movies Trending Today',
          items: summaryCards(trendingMovies),
        ),
        _RailData(
          title: 'Popular Movies',
          items: summaryCards(catalog.popularMovies),
        ),
        _RailData(
          title: 'Continue Watching',
          items: continueWatchingCards(mediaType: MediaType.movie),
        ),
        _RailData(
          title: 'Fresh Movie Picks',
          items: summaryCards(freshMovies),
        ),
      ];
    case BrowseMode.newPopular:
      if (justReleasedCatalog == null) {
        return <_RailData>[
          _RailData(
            title: 'Just Released',
            items: summaryCards(catalog.newAndPopular),
          ),
          _RailData(
            title: 'Just Added',
            items: summaryCards(catalog.newOnStreaming),
          ),
          _RailData(
            title: 'Trending Now',
            items: summaryCards(catalog.trending),
          ),
        ];
      }
      return <_RailData>[
        _RailData(
          title: 'Just Released',
          items: summaryCards(justReleasedCatalog.recentReleases),
        ),
        _RailData(
          title: 'Top Rated Recent',
          items: summaryCards(justReleasedCatalog.topRatedRecent),
        ),
        _RailData(
          title: 'New Thrillers',
          items: summaryCards(justReleasedCatalog.newThrillers),
        ),
        _RailData(
          title: 'New Romance',
          items: summaryCards(justReleasedCatalog.newRomance),
        ),
        _RailData(
          title: 'New Drama',
          items: summaryCards(justReleasedCatalog.newDrama),
        ),
        _RailData(
          title: 'Just Hit Streaming',
          items: summaryCards(justReleasedCatalog.justHitStreaming),
        ),
      ];
  }
}

List<MediaSummary> _filterMedia(
  HomeCatalogData catalog,
  MediaType mediaType,
) {
  return <MediaSummary>[
    catalog.featured,
    ...catalog.newOnStreaming,
    ...catalog.trending,
    ...catalog.popularMovies,
    ...catalog.popularSeries,
    ...catalog.newAndPopular,
  ].where((item) => item.mediaType == mediaType).toList();
}

MediaSummary? _pickFirst(List<MediaSummary> items) {
  if (items.isEmpty) {
    return null;
  }
  return items.first;
}

String _heroMomentumText(MediaSummary item, BrowseMode browseMode) {
  switch (browseMode) {
    case BrowseMode.home:
      return item.mediaType == MediaType.movie
          ? 'Featured Movie'
          : 'Featured Series';
    case BrowseMode.tvShows:
      return 'Featured Series';
    case BrowseMode.movies:
      return 'Featured Movie';
    case BrowseMode.newPopular:
      return 'Recently Added';
  }
}

String _heroRatingText(MediaSummary item) {
  final rating = item.rating;
  if (rating == null) {
    return 'TMDb';
  }
  return '${rating.toStringAsFixed(1)} ★ TMDb';
}

// ignore: unused_element
double _heroTitleFontSize(
  String title, {
  required bool compact,
}) {
  final normalizedLength = title.trim().length;
  if (compact) {
    if (normalizedLength >= 30) {
      return 34;
    }
    if (normalizedLength >= 20) {
      return 46;
    }
    return 54;
  }

  if (normalizedLength >= 30) {
    return 40;
  }
  if (normalizedLength >= 20) {
    return 54;
  }
  return 62;
}
