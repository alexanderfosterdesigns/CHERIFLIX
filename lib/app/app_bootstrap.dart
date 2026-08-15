import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../core/data/sqlite_app_settings_repository.dart';
import '../core/data/sqlite_audio_language_preference_store.dart';
import '../core/data/sqlite_database.dart';
import '../core/data/sqlite_json_cache_store.dart';
import '../core/data/sqlite_playback_progress_repository.dart';
import '../core/data/sqlite_profile_repository.dart';
import '../core/data/sqlite_provider_preference_store.dart';
import '../core/data/sqlite_saved_title_repository.dart';
import '../core/models/maturity_tier.dart';
import '../core/models/media_summary.dart';
import '../core/models/media_type.dart';
import '../core/models/playback_progress_entry.dart';
import '../core/models/playback_progress_snapshot.dart';
import '../core/models/profile.dart';
import '../core/models/profile_playback_settings.dart';
import '../core/models/provider_config.dart';
import '../core/services/caption_service.dart';
import '../core/services/built_in_source_resolver_service.dart';
import '../core/services/embed_playback_provider.dart';
import '../core/services/media_catalog_service.dart';
import '../core/services/offline_download_manager.dart';
import '../core/services/playback_progress_repository.dart';
import '../core/services/profile_repository.dart';
import '../core/services/provider_catalog.dart';
import '../core/services/saved_title_repository.dart';
import '../core/services/session_gate_service.dart';
import '../core/services/source_health_store.dart';
import '../core/services/source_resolver_service.dart';
import '../core/services/tmdb_client.dart';
import '../core/services/tmdb_media_catalog_service.dart';
import '../core/services/trakt_client.dart';
import '../core/services/trakt_home_recommendation_service.dart';
import '../core/services/trakt_playback_reporter.dart';
import '../core/services/subtitles/subdl_caption_service.dart';
import '../core/services/subtitles/subdl_client.dart';
import '../core/services/subtitles/subdl_provider.dart';
import '../core/services/subtitles/subtitle_cache_store.dart';
import '../core/services/subtitles/subtitle_provider.dart';
import '../core/services/update_service.dart';
import '../core/utils/safe_logging.dart';
import '../core/utils/release_date_utils.dart';
import '../core/widgets/tv_text_editor_dialog.dart';
import '../features/details/detail_screen.dart';
import '../features/details/title_info_screen.dart';
import '../features/episodes/episodes_screen.dart';
import '../features/home/home_screen.dart';
import '../features/my_list/my_list_screen.dart';
import '../features/player/player_screen.dart';
import '../features/profile/create_profile_screen.dart';
import '../features/profile/profile_selection_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/splash/splash_screen.dart';

const String _cheriflixAppVersion = String.fromEnvironment(
  'CHERIFLIX_APP_VERSION',
  defaultValue: '0.1.0',
);

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  static const Duration _bootstrapTimeout = Duration(seconds: 12);

  late Future<_AppDependencies> _dependencies;

  @override
  void initState() {
    super.initState();
    _dependencies = _loadDependencies();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AppDependencies>(
      future: _dependencies,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _BootstrapErrorScreen(
            error: snapshot.error!,
            onRetry: () {
              setState(() {
                _dependencies = _loadDependencies();
              });
            },
          );
        }

        if (!snapshot.hasData) {
          return const SplashScreen(loadingOnly: true);
        }

        return _AppShell(dependencies: snapshot.data!);
      },
    );
  }

  Future<_AppDependencies> _loadDependencies() async {
    final runtimeConfig = _RuntimeConfig.fromEnvironment();
    final databaseFuture =
        CheriflixDatabase.open().timeout(_bootstrapTimeout);
    final supportDirectoryFuture = getApplicationSupportDirectory();
    final providerConfigFuture =
        _loadProviderConfig(runtimeConfig.providerConfigPath).timeout(
      _bootstrapTimeout,
    );

    final database = await databaseFuture;
    final profileRepository = SqliteProfileRepository(database);
    final settingsRepository = SqliteAppSettingsRepository(database);
    final audioLanguagePreferenceStore =
        SqliteAudioLanguagePreferenceStore(database);
    final supportDirectory = await supportDirectoryFuture;
    final captionServiceFuture = _buildCaptionService(
      runtimeConfig,
      supportDirectory: supportDirectory,
    );
    final configuredDownloadLocation =
        (await settingsRepository.readDownloadLocation())?.trim();
    var downloadRoot = Directory(
      configuredDownloadLocation?.isNotEmpty == true
          ? configuredDownloadLocation!
          : '${supportDirectory.path}${Platform.pathSeparator}downloads',
    );
    try {
      await downloadRoot.create(recursive: true);
    } catch (_) {
      downloadRoot = Directory(
        '${supportDirectory.path}${Platform.pathSeparator}downloads',
      );
      await downloadRoot.create(recursive: true);
    }
    final offlineDownloadManagerFuture = OfflineDownloadManager.open(
      rootDirectory: downloadRoot,
    );
    final providerPreferenceStore = SqliteProviderPreferenceStore(database);
    final jsonCacheStore = SqliteJsonCacheStore(database);
    final savedTitleRepository = SqliteSavedTitleRepository(database);
    final playbackProgressRepository = SqlitePlaybackProgressRepository(
      database,
    );

    final providerConfig = await providerConfigFuture;

    final tmdbClient = runtimeConfig.tmdbApiKey.isEmpty
        ? null
        : TmdbClient(apiKey: runtimeConfig.tmdbApiKey);
    final mediaCatalogService = tmdbClient == null
        ? null
        : TmdbMediaCatalogService(
            tmdbClient: tmdbClient,
            cacheStore: jsonCacheStore,
          );
    final traktClient = runtimeConfig.traktClientId.isEmpty ||
            runtimeConfig.traktClientSecret.isEmpty ||
            runtimeConfig.traktRedirectUri.isEmpty
        ? null
        : TraktClient(
            clientId: runtimeConfig.traktClientId,
            clientSecret: runtimeConfig.traktClientSecret,
            redirectUri: runtimeConfig.traktRedirectUri,
          );
    final traktHomeRecommendationService = traktClient == null
        ? null
        : TraktHomeRecommendationService(
            traktClient: traktClient,
            cacheStore: jsonCacheStore,
            tmdbMediaCatalogService: mediaCatalogService,
          );
    final traktPlaybackReporter = traktClient == null
        ? null
        : TraktPlaybackReporter(
            traktClient: traktClient,
          );

    final builtInSourceResolverService = BuiltInSourceResolverService(
      providerCatalog: const ProviderCatalog(),
      mediaCatalogService: mediaCatalogService,
    );
    final sourceResolverService = runtimeConfig.sourceResolverServiceUrl.isEmpty
        ? builtInSourceResolverService
        : FallbackSourceResolverService(
            primary: HttpSourceResolverService(
              baseUri: Uri.parse(runtimeConfig.sourceResolverServiceUrl),
            ),
            fallback: builtInSourceResolverService,
          );

    Map<String, Object?>? persistedProviderHealth;
    try {
      final entry = await jsonCacheStore.read(
        key: 'playback-provider-health-v1',
      );
      final decoded = entry == null ? null : jsonDecode(entry.payload);
      if (decoded is Map) {
        persistedProviderHealth = decoded.cast<String, Object?>();
      }
    } catch (_) {
      // Provider history is an optimisation. Corrupt history must never block
      // app startup or source resolution.
    }
    final sourceHealthStore = SourceHealthStore(
      persistedState: persistedProviderHealth,
      onPersist: (state) => jsonCacheStore.write(
        key: 'playback-provider-health-v1',
        payload: jsonEncode(state),
      ),
    );

    final offlineDownloadManager = await offlineDownloadManagerFuture;
    final playbackProvider = EmbedPlaybackProvider(
      providerCatalog: const ProviderCatalog(),
      preferenceStore: providerPreferenceStore,
      profileSettingsStore: profileRepository,
      providerConfig: providerConfig,
      probe: HttpEmbedProbe(),
      mediaCatalogService: mediaCatalogService,
      sourceResolverService: sourceResolverService,
      sourceHealthStore: sourceHealthStore,
      allowEmbedFallback: true,
      offlineMediaLibrary: offlineDownloadManager,
    );

    final updateService = runtimeConfig.updateManifestUrl.isEmpty
        ? null
        : UpdateService(
            manifestUrl: Uri.parse(runtimeConfig.updateManifestUrl),
          );
    final captionService = await captionServiceFuture;

    return _AppDependencies(
      profileRepository: profileRepository,
      settingsRepository: settingsRepository,
      audioLanguagePreferenceStore: audioLanguagePreferenceStore,
      playbackProvider: playbackProvider,
      sessionGateService: const SessionGateService(),
      mediaCatalogService: mediaCatalogService,
      tmdbClient: tmdbClient,
      traktClient: traktClient,
      traktHomeRecommendationService: traktHomeRecommendationService,
      traktPlaybackReporter: traktPlaybackReporter,
      updateService: updateService,
      captionService: captionService,
      savedTitleRepository: savedTitleRepository,
      playbackProgressRepository: playbackProgressRepository,
      offlineDownloadManager: offlineDownloadManager,
      downloadLocation: downloadRoot.path,
    );
  }

  Future<ProviderConfig> _loadProviderConfig(String path) async {
    if (path.isEmpty) {
      return ProviderConfig.defaults();
    }

    final file = File(path);
    if (!await file.exists()) {
      return ProviderConfig.defaults();
    }

    final rawJson =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return ProviderConfig.fromJson(rawJson);
  }

  Future<CaptionService> _buildCaptionService(
    _RuntimeConfig runtimeConfig, {
    required Directory supportDirectory,
  }) async {
    final apiKey = runtimeConfig.subdlApiKey.trim();
    if (apiKey.isEmpty) {
      cheriflixLog(
        'subtitles',
        'Missing CHERIFLIX_SUBDL_API_KEY. Subtitle search will return empty.',
      );
    }
    if (runtimeConfig.captionServiceUrl.isNotEmpty) {
      cheriflixLog(
        'subtitles',
        'Ignoring CHERIFLIX_CAPTION_SERVICE_URL and forcing '
            'SubdlCaptionService.',
      );
    }

    final subtitleRoot = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}subtitles${Platform.pathSeparator}subdl',
    );
    final hiveDirectory = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}hive',
    );
    await hiveDirectory.create(recursive: true);
    Hive.init(hiveDirectory.path);
    final metadataBox = await Hive.openBox<String>('subtitle_search_cache');
    final offsetBox = await Hive.openBox<int>('subtitle_offset_cache');
    final cacheStore = SubtitleCacheStore(
      metadataBox: metadataBox,
      offsetBox: offsetBox,
      subtitleRootDirectory: subtitleRoot,
    );
    final service = SubdlCaptionService(
      coordinator: SubtitleProviderCoordinator(
        primary: SubdlProvider(
          client: SubdlClient(apiKey: apiKey),
          cacheStore: cacheStore,
        ),
        fallback: const OpenSubtitlesProviderStub(),
      ),
      cacheStore: cacheStore,
      hasConfiguredApiKey: apiKey.isNotEmpty,
    );
    unawaited(service.scheduleCleanup());
    return service;
  }
}

class _AppShell extends StatefulWidget {
  const _AppShell({required this.dependencies});

  final _AppDependencies dependencies;

  @override
  State<_AppShell> createState() => _AppShellState();
}

enum _AppStage {
  loading,
  splash,
  profileSelection,
  createProfile,
  home,
  tvShows,
  movies,
  newPopular,
  myList,
  search,
  settings,
  details,
  titleInfo,
  episodes,
  player,
}

class _AppNavigationSnapshot {
  const _AppNavigationSnapshot({
    required this.entryId,
    required this.stage,
    required this.selectedSummary,
    required this.selectedTmdbId,
    required this.selectedMediaType,
    required this.selectedSeason,
    required this.selectedEpisode,
    required this.selectedResumePosition,
  });

  final int entryId;
  final _AppStage stage;
  final MediaSummary? selectedSummary;
  final int selectedTmdbId;
  final MediaType selectedMediaType;
  final int selectedSeason;
  final int selectedEpisode;
  final Duration selectedResumePosition;
}

class _AppShellState extends State<_AppShell> {
  static const Duration _backNavigationDispatchGuardDuration =
      Duration(milliseconds: 260);
  static const Duration _startupTimeout = Duration(seconds: 12);

  _AppStage _stage = _AppStage.loading;
  int _currentNavigationEntryId = 0;
  int _nextNavigationEntryId = 1;
  final List<_AppNavigationSnapshot> _navigationStack =
      <_AppNavigationSnapshot>[];
  List<Profile> _profiles = const <Profile>[];
  Profile? _activeProfile;
  ProfilePlaybackSettings _playbackSettings =
      const ProfilePlaybackSettings(languageCode: 'en');
  bool _hideSpoilersInEpisodes = false;
  List<MediaSummary> _savedTitles = const <MediaSummary>[];
  List<PlaybackProgressEntry> _playbackProgressEntries =
      const <PlaybackProgressEntry>[];
  Future<void> _playbackProgressSaveQueue = Future<void>.value();
  MediaSummary? _selectedSummary;
  int _selectedTmdbId = 1399;
  MediaType _selectedMediaType = MediaType.tv;
  int _selectedSeason = 1;
  int _selectedEpisode = 1;
  Duration _selectedResumePosition = Duration.zero;
  Object? _hydrateError;
  Timer? _backNavigationDispatchGuardTimer;
  bool _backNavigationDispatchGuardActive = false;
  final Map<int, double> _browseScrollOffsets = <int, double>{};
  final Map<int, ({int railIndex, int itemIndex})> _browseFocusedItems =
      <int, ({int railIndex, int itemIndex})>{};

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  @override
  void dispose() {
    _backNavigationDispatchGuardTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hydrateError != null) {
      return _BootstrapErrorScreen(
        error: _hydrateError!,
        onRetry: _retryHydrate,
      );
    }

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        if (_stage == _AppStage.player) {
          return;
        }
        _handleBackNavigation();
      },
      child: _buildNavigationStack(context),
    );
  }

  Widget _buildNavigationStack(BuildContext context) {
    final currentSnapshot = _currentNavigationSnapshot();
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        for (final snapshot in _navigationStack)
          _buildNavigationEntry(
            context,
            snapshot: snapshot,
            active: false,
          ),
        _buildNavigationEntry(
          context,
          snapshot: currentSnapshot,
          active: true,
        ),
      ],
    );
  }

  Widget _buildNavigationEntry(
    BuildContext context, {
    required _AppNavigationSnapshot snapshot,
    required bool active,
  }) {
    // When the Player is the active stage, drop the predecessor subtrees
    // from the widget tree entirely. The navigation snapshot data is kept
    // in [_navigationStack] so back-navigation still works (it rebuilds
    // the screen on return). This is the biggest single memory win on TV
    // because the Player uses video + WebView embeds.
    final releaseInactiveWidgets = _stage == _AppStage.player && !active;
    final child = releaseInactiveWidgets
        ? const SizedBox.shrink()
        : _buildScreenForSnapshot(context, snapshot);
    return KeyedSubtree(
      key: ValueKey<int>(snapshot.entryId),
      child: Offstage(
        offstage: !active,
        child: TickerMode(
          enabled: active,
          child: ExcludeFocus(
            excluding: !active,
            child: IgnorePointer(
              ignoring: !active,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScreenForSnapshot(
    BuildContext context,
    _AppNavigationSnapshot snapshot,
  ) {
    switch (snapshot.stage) {
      case _AppStage.loading:
        return const SplashScreen(loadingOnly: true);
      case _AppStage.splash:
        return SplashScreen(onFinished: _handleSplashFinished);
      case _AppStage.profileSelection:
        return ProfileSelectionScreen(
          profiles: _profiles,
          onSelectProfile: _requestProfileActivation,
          onCreateProfile: _openCreateProfile,
        );
      case _AppStage.createProfile:
        return CreateProfileScreen(
          profiles: _profiles,
          onBack: _handleBackNavigation,
          onCreateProfile: _createProfile,
        );
      case _AppStage.home:
        return _buildBrowseScreen(BrowseMode.home, snapshot.entryId);
      case _AppStage.tvShows:
        return _buildBrowseScreen(BrowseMode.tvShows, snapshot.entryId);
      case _AppStage.movies:
        return _buildBrowseScreen(BrowseMode.movies, snapshot.entryId);
      case _AppStage.newPopular:
        return _buildBrowseScreen(BrowseMode.newPopular, snapshot.entryId);
      case _AppStage.myList:
        return MyListScreen(
          activeProfile: _activeProfile!,
          savedTitles: _savedTitles,
          playbackProgress: _playbackProgress,
          mediaCatalogService: widget.dependencies.mediaCatalogService,
          languageCode: _activeProfile!.languageCode,
          autoplayPreviews: _playbackSettings.autoplayPreviews,
          muteAutoplayTrailers: _playbackSettings.muteAutoplayTrailers,
          onOpenTitle: _openDetails,
          onPlayTitle: _playTitle,
          onToggleSaved: _toggleSavedTitle,
          onBack: _handleBackNavigation,
          onBrowseHome: () => _openTopLevelStage(_AppStage.home),
          onBrowseTvShows: () => _openTopLevelStage(_AppStage.tvShows),
          onBrowseMovies: () => _openTopLevelStage(_AppStage.movies),
          onBrowseNewPopular: () => _openTopLevelStage(_AppStage.newPopular),
          onOpenSearch: _openSearch,
          onOpenSettings: _openSettings,
          onSwitchProfile: _openProfileSelection,
        );
      case _AppStage.search:
        return SearchScreen(
          mediaCatalogService: widget.dependencies.mediaCatalogService,
          languageCode: _activeProfile!.languageCode,
          muteAutoplayTrailers: _playbackSettings.muteAutoplayTrailers,
          activeProfile: _activeProfile,
          savedTitleKeys: _savedTitleKeys,
          onToggleSaved: _toggleSavedTitle,
          onBack: _handleBackNavigation,
          onOpenTitle: _openDetails,
          onPlayTitle: _playTitle,
          onBrowseHome: () => _openTopLevelStage(_AppStage.home),
          onBrowseTvShows: () => _openTopLevelStage(_AppStage.tvShows),
          onBrowseMovies: () => _openTopLevelStage(_AppStage.movies),
          onBrowseNewPopular: () => _openTopLevelStage(_AppStage.newPopular),
          onBrowseMyList: () => _openTopLevelStage(_AppStage.myList),
          onOpenSettings: _openSettings,
          onSwitchProfile: _openProfileSelection,
        );
      case _AppStage.settings:
        return SettingsScreen(
          activeProfile: _activeProfile!,
          playbackSettings: _playbackSettings,
          hideSpoilers: _hideSpoilersInEpisodes,
          onHideSpoilersChanged: (value) {
            if (!mounted) {
              return;
            }
            setState(() => _hideSpoilersInEpisodes = value);
          },
          onBack: _handleBackNavigation,
          onSaveProfile: (profile) async {
            final updated = await widget.dependencies.profileRepository
                .updateProfile(profile);
            if (!mounted) {
              return;
            }
            setState(() {
              _profiles = _profiles
                  .map((entry) => entry.id == updated.id ? updated : entry)
                  .toList();
              if (_activeProfile?.id == updated.id) {
                _activeProfile = updated;
              }
            });
          },
          onSavePlaybackSettings: (settings) async {
            await widget.dependencies.profileRepository.savePlaybackSettings(
              _activeProfile!.id,
              settings,
            );
            if (!mounted) {
              return;
            }
            setState(() => _playbackSettings = settings);
          },
          onClearRememberedAudioLanguages: () async {
            await widget.dependencies.audioLanguagePreferenceStore
                .clearAllForProfile(_activeProfile!.id);
          },
          traktAuthorizationUri:
              widget.dependencies.traktClient?.buildAuthorizationUri(),
          onConnectTrakt:
              widget.dependencies.traktClient == null ? null : _connectTrakt,
          onDisconnectTrakt:
              _activeProfile?.traktAccount == null ? null : _disconnectTrakt,
          onCheckForUpdates: widget.dependencies.updateService == null
              ? null
              : () async {
                  final result = await widget.dependencies.updateService!
                      .checkForUpdate(currentVersion: _cheriflixAppVersion);
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result.message),
                    ),
                  );
                },
          onBrowseHome: () => _openTopLevelStage(_AppStage.home),
          onBrowseTvShows: () => _openTopLevelStage(_AppStage.tvShows),
          onBrowseMovies: () => _openTopLevelStage(_AppStage.movies),
          onBrowseNewPopular: () => _openTopLevelStage(_AppStage.newPopular),
          onBrowseMyList: () => _openTopLevelStage(_AppStage.myList),
          onOpenSearch: _openSearch,
          onSwitchProfile: _openProfileSelection,
          downloadManager: widget.dependencies.offlineDownloadManager,
          downloadLocation: widget.dependencies.downloadLocation,
          onDownloadLocationChanged: (path) async {
            await widget.dependencies.offlineDownloadManager
                .changeDownloadLocation(Directory(path));
            await widget.dependencies.settingsRepository
                .writeDownloadLocation(path);
          },
        );
      case _AppStage.details:
        final selectedSummary = snapshot.selectedSummary!;
        return DetailScreen(
          activeProfile: _activeProfile!,
          summary: selectedSummary,
          languageCode: _activeProfile!.languageCode,
          mediaCatalogService: widget.dependencies.mediaCatalogService,
          playbackProgress: _playbackProgress,
          isSaved: _savedTitleKeys.contains(selectedSummary.saveKey),
          onToggleSaved: () => _toggleSavedTitle(selectedSummary),
          onBack: _handleBackNavigation,
          onPlay: () => _playTitle(selectedSummary),
          onPlayTitle: _playTitle,
          onToggleSavedTitle: _toggleSavedTitle,
          onOpenTitleInfo: _openTitleInfo,
          onOpenEpisodes:
              selectedSummary.mediaType == MediaType.tv ? _openEpisodes : null,
          onOpenTitle: _openDetails,
          savedTitleKeys: _savedTitleKeys,
          autoplayPreviews: _playbackSettings.autoplayPreviews,
          muteAutoplayTrailers: _playbackSettings.muteAutoplayTrailers,
          onBrowseHome: () => _openTopLevelStage(_AppStage.home),
          onBrowseTvShows: () => _openTopLevelStage(_AppStage.tvShows),
          onBrowseMovies: () => _openTopLevelStage(_AppStage.movies),
          onBrowseNewPopular: () => _openTopLevelStage(_AppStage.newPopular),
          onBrowseMyList: () => _openTopLevelStage(_AppStage.myList),
          onOpenSearch: _openSearch,
          onOpenSettings: _openSettings,
          onSwitchProfile: _openProfileSelection,
          onDownload: selectedSummary.mediaType == MediaType.movie
              ? () => _downloadMedia(selectedSummary)
              : null,
          downloadManager: widget.dependencies.offlineDownloadManager,
        );
      case _AppStage.titleInfo:
        return TitleInfoScreen(
          summary: snapshot.selectedSummary!,
          languageCode: _activeProfile!.languageCode,
          mediaCatalogService: widget.dependencies.mediaCatalogService,
          onBack: _handleBackNavigation,
        );
      case _AppStage.episodes:
        final selectedSummary = snapshot.selectedSummary!;
        return EpisodesScreen(
          activeProfile: _activeProfile!,
          summary: selectedSummary,
          languageCode: _activeProfile!.languageCode,
          mediaCatalogService: widget.dependencies.mediaCatalogService,
          playbackProgress: _playbackProgress,
          hideSpoilers: _hideSpoilersInEpisodes,
          initialSeasonNumber: snapshot.selectedSeason,
          onBack: _handleBackNavigation,
          onPlayEpisode: (seasonNumber, episode) {
            if (episode.isUpcoming) {
              _showUnreleasedMessage(episode.airDate);
              return;
            }
            _playEpisode(
              selectedSummary,
              seasonNumber: seasonNumber,
              episodeNumber: episode.episodeNumber,
            );
          },
          onDownloadEpisode: (seasonNumber, episode) => _downloadMedia(
            selectedSummary,
            seasonNumber: seasonNumber,
            episodeNumber: episode.episodeNumber,
            displayTitle:
                '${selectedSummary.title} S$seasonNumber E${episode.episodeNumber}',
          ),
          downloadManager: widget.dependencies.offlineDownloadManager,
          onBrowseHome: () => _openTopLevelStage(_AppStage.home),
          onBrowseTvShows: () => _openTopLevelStage(_AppStage.tvShows),
          onBrowseMovies: () => _openTopLevelStage(_AppStage.movies),
          onBrowseNewPopular: () => _openTopLevelStage(_AppStage.newPopular),
          onBrowseMyList: () => _openTopLevelStage(_AppStage.myList),
          onOpenSearch: _openSearch,
          onOpenSettings: _openSettings,
          onSwitchProfile: _openProfileSelection,
        );
      case _AppStage.player:
        return PlayerScreen(
          playbackProvider: widget.dependencies.playbackProvider,
          captionService: widget.dependencies.captionService,
          mediaCatalogService: widget.dependencies.mediaCatalogService,
          playbackSettings: _playbackSettings,
          playbackProgress: _playbackProgress,
          audioLanguagePreferenceStore:
              widget.dependencies.audioLanguagePreferenceStore,
          hideSpoilers: _hideSpoilersInEpisodes,
          profileId: _activeProfile!.id,
          tmdbId: snapshot.selectedTmdbId,
          mediaType: snapshot.selectedMediaType,
          seasonNumber: snapshot.selectedSeason,
          episodeNumber: snapshot.selectedEpisode,
          languageCode: _activeProfile!.languageCode,
          initialSummary: snapshot.selectedSummary,
          initialResumePosition: snapshot.selectedResumePosition,
          onProgressChanged: _handlePlaybackProgressChanged,
          onTraktPlaybackReported: _handleTraktPlaybackReported,
          onPlaybackSettingsChanged: (settings) {
            if (!mounted) {
              return;
            }
            setState(() => _playbackSettings = settings);
          },
          onBack: _handleBackNavigation,
        );
    }
  }

  Widget _buildBrowseScreen(BrowseMode mode, int entryId) {
    return HomeScreen(
      activeProfile: _activeProfile!,
      playbackSettings: _playbackSettings,
      mediaCatalogService: widget.dependencies.mediaCatalogService,
      languageCode: _activeProfile!.languageCode,
      savedTitleKeys: _savedTitleKeys,
      playbackProgress: _playbackProgress,
      loadHomeRecommendations: _loadHomeRecommendations,
      browseMode: mode,
      onBack: _handleBackNavigation,
      onOpenSearch: _openSearch,
      onOpenSettings: _openSettings,
      onSwitchProfile: _openProfileSelection,
      onOpenTitle: _openDetails,
      onPlayTitle: _playTitle,
      onToggleSaved: _toggleSavedTitle,
      onBrowseHome: () => _openTopLevelStage(_AppStage.home),
      onBrowseTvShows: () => _openTopLevelStage(_AppStage.tvShows),
      onBrowseMovies: () => _openTopLevelStage(_AppStage.movies),
      onBrowseNewPopular: () => _openTopLevelStage(_AppStage.newPopular),
      onBrowseMyList: () => _openTopLevelStage(_AppStage.myList),
      initialScrollOffset: _browseScrollOffsets[entryId] ?? 0,
      initialFocusedRailIndex: _browseFocusedItems[entryId]?.railIndex,
      initialFocusedItemIndex: _browseFocusedItems[entryId]?.itemIndex,
      onFocusedItemChanged: (railIndex, itemIndex) {
        _browseFocusedItems[entryId] = (
          railIndex: railIndex,
          itemIndex: itemIndex,
        );
      },
      onScrollOffsetChanged: (offset) {
        _browseScrollOffsets[entryId] = offset;
      },
    );
  }

  _AppNavigationSnapshot _currentNavigationSnapshot() {
    return _AppNavigationSnapshot(
      entryId: _currentNavigationEntryId,
      stage: _stage,
      selectedSummary: _selectedSummary,
      selectedTmdbId: _selectedTmdbId,
      selectedMediaType: _selectedMediaType,
      selectedSeason: _selectedSeason,
      selectedEpisode: _selectedEpisode,
      selectedResumePosition: _selectedResumePosition,
    );
  }

  void _pushNavigationSnapshot([_AppNavigationSnapshot? snapshot]) {
    _navigationStack.add(snapshot ?? _currentNavigationSnapshot());
  }

  void _advanceNavigationEntry() {
    _currentNavigationEntryId = _nextNavigationEntryId;
    _nextNavigationEntryId += 1;
  }

  bool _restorePreviousNavigationSnapshot() {
    if (_navigationStack.isEmpty) {
      return false;
    }
    final snapshot = _navigationStack.removeLast();
    setState(() {
      _currentNavigationEntryId = snapshot.entryId;
      _stage = snapshot.stage;
      _selectedSummary = snapshot.selectedSummary;
      _selectedTmdbId = snapshot.selectedTmdbId;
      _selectedMediaType = snapshot.selectedMediaType;
      _selectedSeason = snapshot.selectedSeason;
      _selectedEpisode = snapshot.selectedEpisode;
      _selectedResumePosition = snapshot.selectedResumePosition;
    });
    return true;
  }

  void _openTopLevelStage(_AppStage stage) {
    if (_stage == stage) {
      return;
    }

    if (_isPrimaryTabStage(_stage) && _isPrimaryTabStage(stage)) {
      final canReuseCatalogScreen =
          _isCatalogBrowseStage(_stage) && _isCatalogBrowseStage(stage);
      setState(() {
        if (!canReuseCatalogScreen) {
          _advanceNavigationEntry();
        }
        _stage = stage;
      });
      return;
    }

    _pushNavigationSnapshot();
    setState(() {
      _advanceNavigationEntry();
      _stage = stage;
    });
  }

  bool _isCatalogBrowseStage(_AppStage stage) {
    return stage == _AppStage.home ||
        stage == _AppStage.tvShows ||
        stage == _AppStage.movies ||
        stage == _AppStage.newPopular;
  }

  bool _isPrimaryTabStage(_AppStage stage) {
    return _isCatalogBrowseStage(stage) || stage == _AppStage.myList;
  }

  void _openProfileSelection() {
    _openTopLevelStage(_AppStage.profileSelection);
  }

  void _openCreateProfile() {
    _pushNavigationSnapshot();
    setState(() {
      _advanceNavigationEntry();
      _stage = _AppStage.createProfile;
    });
  }

  void _handleBackNavigation() {
    if (_backNavigationDispatchGuardActive) {
      return;
    }
    _startBackNavigationDispatchGuard();

    switch (_stage) {
      case _AppStage.createProfile:
        _restorePreviousNavigationSnapshot();
        return;
      case _AppStage.search:
      case _AppStage.settings:
      case _AppStage.details:
      case _AppStage.titleInfo:
      case _AppStage.episodes:
      case _AppStage.player:
        _restorePreviousNavigationSnapshot();
        return;
      case _AppStage.tvShows:
      case _AppStage.movies:
      case _AppStage.newPopular:
      case _AppStage.myList:
      case _AppStage.home:
        _restorePreviousNavigationSnapshot();
        return;
      case _AppStage.profileSelection:
        _restorePreviousNavigationSnapshot();
        return;
      case _AppStage.loading:
      case _AppStage.splash:
        return;
    }
  }

  void _startBackNavigationDispatchGuard() {
    _backNavigationDispatchGuardTimer?.cancel();
    _backNavigationDispatchGuardActive = true;
    _backNavigationDispatchGuardTimer = Timer(
      _backNavigationDispatchGuardDuration,
      () {
        _backNavigationDispatchGuardActive = false;
        _backNavigationDispatchGuardTimer = null;
      },
    );
  }

  Future<void> _hydrate() async {
    try {
      final profiles = await widget.dependencies.profileRepository
          .fetchProfiles()
          .timeout(_startupTimeout);
      if (profiles.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _navigationStack.clear();
          _advanceNavigationEntry();
          _profiles = profiles;
          _hydrateError = null;
          _stage = _AppStage.profileSelection;
        });
        return;
      }

      final activeProfileId = await widget.dependencies.profileRepository
          .getLastActiveProfileId()
          .timeout(_startupTimeout);
      final lastUnlockedAt = await widget.dependencies.settingsRepository
          .readSessionUnlockedAt()
          .timeout(_startupTimeout);
      final shouldShowGate =
          widget.dependencies.sessionGateService.shouldShowGate(
        now: DateTime.now().toUtc(),
        lastUnlockedAt: lastUnlockedAt,
      );

      final activeProfile =
          _findProfile(profiles, activeProfileId) ?? profiles.first;
      final playbackSettings = await widget.dependencies.profileRepository
          .loadPlaybackSettings(activeProfile.id)
          .timeout(_startupTimeout);
      final savedTitles = await widget.dependencies.savedTitleRepository
          .fetchSavedTitles(activeProfile.id)
          .timeout(_startupTimeout);
      final playbackProgressEntries = await widget
          .dependencies.playbackProgressRepository
          .fetchProgressEntries(activeProfile.id)
          .timeout(_startupTimeout);

      if (!mounted) {
        return;
      }

      setState(() {
        _navigationStack.clear();
        _advanceNavigationEntry();
        _profiles = profiles;
        _activeProfile = activeProfile;
        _playbackSettings = playbackSettings;
        _savedTitles = savedTitles;
        _playbackProgressEntries = playbackProgressEntries;
        _hydrateError = null;
        _stage = shouldShowGate ? _AppStage.profileSelection : _AppStage.home;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _hydrateError = error;
        _advanceNavigationEntry();
        _stage = _AppStage.loading;
      });
    }
  }

  void _retryHydrate() {
    setState(() {
      _hydrateError = null;
      _advanceNavigationEntry();
      _stage = _AppStage.loading;
    });
    _hydrate();
  }

  Profile? _findProfile(List<Profile> profiles, String? id) {
    if (id == null) {
      return null;
    }
    for (final profile in profiles) {
      if (profile.id == id) {
        return profile;
      }
    }
    return null;
  }

  Future<void> _handleSplashFinished() async {
    if (_profiles.isEmpty) {
      setState(() {
        _navigationStack.clear();
        _advanceNavigationEntry();
        _stage = _AppStage.profileSelection;
      });
      return;
    }

    final profile = _activeProfile ?? _profiles.first;
    await widget.dependencies.settingsRepository
        .writeSessionUnlockedAt(DateTime.now().toUtc());
    await widget.dependencies.profileRepository
        .setLastActiveProfileId(profile.id);

    if (!mounted) {
      return;
    }

    setState(() {
      _navigationStack.clear();
      _advanceNavigationEntry();
      _activeProfile = profile;
      _stage = _AppStage.home;
    });
  }

  Future<void> _activateProfile(Profile profile) async {
    final previousProfileId = _activeProfile?.id;
    await widget.dependencies.profileRepository
        .setLastActiveProfileId(profile.id);
    await widget.dependencies.settingsRepository
        .writeSessionUnlockedAt(DateTime.now().toUtc());
    final playbackSettings = await widget.dependencies.profileRepository
        .loadPlaybackSettings(profile.id);
    final savedTitles = await widget.dependencies.savedTitleRepository
        .fetchSavedTitles(profile.id);
    final playbackProgressEntries = await widget
        .dependencies.playbackProgressRepository
        .fetchProgressEntries(profile.id);

    if (!mounted) {
      return;
    }

    if (previousProfileId != null && previousProfileId != profile.id) {
      widget.dependencies.traktPlaybackReporter
          ?.clearProfile(previousProfileId);
    }
    setState(() {
      _navigationStack.clear();
      _advanceNavigationEntry();
      _activeProfile = profile;
      _playbackSettings = playbackSettings;
      _savedTitles = savedTitles;
      _playbackProgressEntries = playbackProgressEntries;
      _stage = _AppStage.home;
    });
  }

  Future<void> _requestProfileActivation(Profile profile) async {
    if (!profile.isLocked) {
      await _activateProfile(profile);
      return;
    }
    final pin = await showTvTextEditorDialog(
      context,
      title: 'Enter PIN for ${profile.name}',
      initialValue: '',
      maxLength: 4,
      numericOnly: true,
    );
    if (!mounted || pin == null) return;
    final enteredHash = sha256.convert(utf8.encode(pin)).toString();
    if (enteredHash != profile.pinHash) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect profile PIN.')),
      );
      return;
    }
    await _activateProfile(profile);
  }

  Future<void> _createProfile(String name, String avatarLabel) async {
    final profile = await widget.dependencies.profileRepository.createProfile(
      name: name,
      languageCode: 'en',
      maturityTier: MaturityTier.mature,
      avatarLabel: avatarLabel,
    );

    final profiles =
        await widget.dependencies.profileRepository.fetchProfiles();
    if (!mounted) {
      return;
    }

    setState(() {
      _profiles = profiles;
    });

    await _activateProfile(profile);
  }

  void _openDetails(MediaSummary summary) {
    _pushNavigationSnapshot();
    _prefetchSubtitles(summary);
    setState(() {
      _advanceNavigationEntry();
      _selectedSummary = summary;
      _stage = _AppStage.details;
    });
  }

  Future<void> _openEpisodes(MediaSummary summary) async {
    final returnSnapshot = _currentNavigationSnapshot();
    final resolvedSummary = await _resolveDetailedSummary(summary);
    final progress = _playbackProgress.preferredForTitle(resolvedSummary);
    if (!mounted) {
      return;
    }
    _pushNavigationSnapshot(returnSnapshot);
    setState(() {
      _advanceNavigationEntry();
      _selectedSummary = resolvedSummary;
      _selectedSeason = progress?.seasonNumber ?? 1;
      _stage = _AppStage.episodes;
    });
  }

  void _openTitleInfo() {
    _pushNavigationSnapshot();
    setState(() {
      _advanceNavigationEntry();
      _stage = _AppStage.titleInfo;
    });
  }

  void _playTitle(MediaSummary summary) {
    if (summary.isUpcoming) {
      _showUnreleasedMessage(summary.releaseDate);
      return;
    }
    _pushNavigationSnapshot();
    _prefetchSubtitles(summary);
    final progress = _playbackProgress.preferredForTitle(summary);
    setState(() {
      _advanceNavigationEntry();
      _selectedSummary = summary;
      _selectedTmdbId = summary.tmdbId;
      _selectedMediaType = summary.mediaType;
      _selectedSeason =
          summary.mediaType == MediaType.tv ? progress?.seasonNumber ?? 1 : 1;
      _selectedEpisode =
          summary.mediaType == MediaType.tv ? progress?.episodeNumber ?? 1 : 1;
      _selectedResumePosition = progress?.resumePosition ?? Duration.zero;
      _stage = _AppStage.player;
    });
  }

  void _showUnreleasedMessage(DateTime? releaseDate) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(comingSoonMessage(releaseDate)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _prefetchSubtitles(MediaSummary summary) {
    if (widget.dependencies.captionService is! SubtitlePrefetchService) {
      return;
    }
    final prefetchService =
        widget.dependencies.captionService as SubtitlePrefetchService;
    unawaited(
      prefetchService.prefetchForSummary(
        summary,
        preferredLanguageCode: _activeProfile?.languageCode,
      ),
    );
  }

  void _playEpisode(
    MediaSummary summary, {
    required int seasonNumber,
    required int episodeNumber,
  }) {
    _pushNavigationSnapshot();
    final progress = _playbackProgress.entryForTarget(
      summary: summary,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
    setState(() {
      _advanceNavigationEntry();
      _selectedSummary = summary;
      _selectedTmdbId = summary.tmdbId;
      _selectedMediaType = summary.mediaType;
      _selectedSeason = seasonNumber;
      _selectedEpisode = episodeNumber;
      _selectedResumePosition = progress?.resumePosition ?? Duration.zero;
      _stage = _AppStage.player;
    });
  }

  Future<void> _downloadMedia(
    MediaSummary summary, {
    int? seasonNumber,
    int? episodeNumber,
    String? displayTitle,
  }) async {
    final profile = _activeProfile;
    if (profile == null) {
      return;
    }
    final key = OfflineMediaKey(
      tmdbId: summary.tmdbId,
      mediaType: summary.mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
    final existing = widget.dependencies.offlineDownloadManager.recordFor(key);
    if (existing?.status == OfflineDownloadStatus.completed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Already available offline.')),
        );
      }
      return;
    }
    try {
      final target =
          await widget.dependencies.playbackProvider.resolveDownloadTarget(
        profileId: profile.id,
        tmdbId: summary.tmdbId,
        mediaType: summary.mediaType,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      );
      if (target == null) {
        throw const OfflineDownloadException(
          'No validated source is currently available.',
        );
      }
      await widget.dependencies.offlineDownloadManager.enqueue(
        key: key,
        title: displayTitle ?? summary.title,
        target: target,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download started.')),
        );
      }
    } on OfflineDownloadException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'A downloadable stream could not be prepared. Please retry.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _toggleSavedTitle(MediaSummary summary) async {
    final profile = _activeProfile;
    if (profile == null) {
      return;
    }

    if (_savedTitleKeys.contains(summary.saveKey)) {
      await widget.dependencies.savedTitleRepository.removeTitle(
        profileId: profile.id,
        tmdbId: summary.tmdbId,
        mediaType: summary.mediaType,
      );
    } else {
      await widget.dependencies.savedTitleRepository.saveTitle(
        profileId: profile.id,
        summary: summary,
      );
    }

    final savedTitles = await widget.dependencies.savedTitleRepository
        .fetchSavedTitles(profile.id);
    if (!mounted) {
      return;
    }
    setState(() => _savedTitles = savedTitles);
  }

  void _openSearch() {
    if (_stage == _AppStage.search) {
      return;
    }
    _pushNavigationSnapshot();
    setState(() {
      _advanceNavigationEntry();
      _stage = _AppStage.search;
    });
  }

  void _openSettings() {
    if (_stage == _AppStage.settings) {
      return;
    }
    _pushNavigationSnapshot();
    setState(() {
      _advanceNavigationEntry();
      _stage = _AppStage.settings;
    });
  }

  Future<MediaSummary> _resolveDetailedSummary(MediaSummary summary) async {
    final service = widget.dependencies.mediaCatalogService;
    final activeProfile = _activeProfile;
    if (service == null || activeProfile == null) {
      return summary;
    }
    if (summary.mediaType != MediaType.tv &&
        summary.runtimeMinutes != null &&
        summary.overview?.trim().isNotEmpty == true) {
      return summary;
    }
    if (summary.mediaType == MediaType.tv &&
        summary.seasonCount != null &&
        summary.seasonCount! > 1 &&
        summary.overview?.trim().isNotEmpty == true) {
      return summary;
    }

    try {
      return await service.fetchTitleDetails(
        tmdbId: summary.tmdbId,
        mediaType: summary.mediaType,
        languageCode: activeProfile.languageCode,
      );
    } catch (_) {
      return summary;
    }
  }

  Future<void> _handlePlaybackProgressChanged(
    PlaybackProgressEntry entry,
  ) {
    _playbackProgressSaveQueue = _playbackProgressSaveQueue
        .then((_) => _persistPlaybackProgress(entry))
        .catchError((Object _) {
      // Keep the queue usable so a transient database error cannot prevent
      // every later checkpoint and the final exit flush from being saved.
    });
    return _playbackProgressSaveQueue;
  }

  Future<void> _persistPlaybackProgress(
    PlaybackProgressEntry entry,
  ) async {
    final profile = _activeProfile;
    if (profile == null) {
      return;
    }

    if (!entry.hasStarted) {
      // Startup, route teardown, and renderer changes can briefly report 0:00.
      // Do not let those transient samples erase a valid resume point.
      return;
    }

    await widget.dependencies.playbackProgressRepository.saveProgress(
      profileId: profile.id,
      entry: entry,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _playbackProgressEntries = <PlaybackProgressEntry>[
        entry,
        ..._playbackProgressEntries.where(
          (item) => item.entryKey != entry.entryKey,
        ),
      ].take(200).toList(growable: false);
    });
  }

  Future<void> _connectTrakt(String code) async {
    final profile = _activeProfile;
    final traktClient = widget.dependencies.traktClient;
    if (profile == null || traktClient == null) {
      return;
    }

    final account = await traktClient.exchangeAuthorizationCode(code);
    final updated = await widget.dependencies.profileRepository.updateProfile(
      profile.copyWith(traktAccount: account),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _replaceProfile(updated);
      _activeProfile = updated;
    });
  }

  Future<void> _disconnectTrakt() async {
    final profile = _activeProfile;
    if (profile == null || profile.traktAccount == null) {
      return;
    }

    final updated = await widget.dependencies.profileRepository.updateProfile(
      profile.copyWith(traktAccount: null),
    );
    widget.dependencies.traktPlaybackReporter?.clearProfile(profile.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _replaceProfile(updated);
      _activeProfile = updated;
    });
  }

  Future<List<MediaSummary>> _loadHomeRecommendations() async {
    final profile = _activeProfile;
    final recommendationService =
        widget.dependencies.traktHomeRecommendationService;
    if (profile == null || recommendationService == null) {
      return const <MediaSummary>[];
    }

    final freshProfile = await _ensureFreshTraktProfile(profile);
    if (freshProfile.traktAccount == null) {
      return const <MediaSummary>[];
    }

    try {
      return await recommendationService.fetchRecommendations(
        profile: freshProfile,
        languageCode: freshProfile.languageCode,
        fallbackSeeds: <MediaSummary>[
          for (final entry in _playbackProgress.continueWatchingEntries)
            entry.summary,
          ..._savedTitles,
        ],
      );
    } catch (_) {
      return const <MediaSummary>[];
    }
  }

  Future<void> _handleTraktPlaybackReported(
    PlaybackProgressEntry entry,
    bool paused,
  ) async {
    final profile = _activeProfile;
    final reporter = widget.dependencies.traktPlaybackReporter;
    if (profile == null || reporter == null) {
      return;
    }

    final freshProfile = await _ensureFreshTraktProfile(profile);
    if (freshProfile.traktAccount == null) {
      return;
    }

    try {
      await reporter.reportPlayback(
        profile: freshProfile,
        entry: entry,
        paused: paused,
      );
    } catch (_) {
      // Playback should continue even when watch sync fails.
    }
  }

  Future<Profile> _ensureFreshTraktProfile(Profile profile) async {
    final traktClient = widget.dependencies.traktClient;
    final account = profile.traktAccount;
    if (traktClient == null || account == null || !account.needsRefresh) {
      return profile;
    }

    try {
      final refreshedAccount = await traktClient.refreshAccount(account);
      final updated = await widget.dependencies.profileRepository.updateProfile(
        profile.copyWith(traktAccount: refreshedAccount),
      );
      if (!mounted) {
        return updated;
      }
      setState(() {
        _replaceProfile(updated);
        if (_activeProfile?.id == updated.id) {
          _activeProfile = updated;
        }
      });
      return updated;
    } on TraktApiException catch (error) {
      if (error.statusCode != 400 && error.statusCode != 401) {
        return profile;
      }

      final disconnected = await widget.dependencies.profileRepository
          .updateProfile(profile.copyWith(traktAccount: null));
      widget.dependencies.traktPlaybackReporter?.clearProfile(profile.id);
      if (!mounted) {
        return disconnected;
      }
      setState(() {
        _replaceProfile(disconnected);
        if (_activeProfile?.id == disconnected.id) {
          _activeProfile = disconnected;
        }
      });
      return disconnected;
    }
  }

  void _replaceProfile(Profile updated) {
    _profiles = _profiles
        .map((entry) => entry.id == updated.id ? updated : entry)
        .toList(growable: false);
  }

  Set<String> get _savedTitleKeys =>
      _savedTitles.map((summary) => summary.saveKey).toSet();

  PlaybackProgressSnapshot get _playbackProgress =>
      PlaybackProgressSnapshot(_playbackProgressEntries);
}

class _AppDependencies {
  const _AppDependencies({
    required this.profileRepository,
    required this.settingsRepository,
    required this.audioLanguagePreferenceStore,
    required this.playbackProvider,
    required this.sessionGateService,
    required this.mediaCatalogService,
    required this.tmdbClient,
    required this.traktClient,
    required this.traktHomeRecommendationService,
    required this.traktPlaybackReporter,
    required this.updateService,
    required this.captionService,
    required this.savedTitleRepository,
    required this.playbackProgressRepository,
    required this.offlineDownloadManager,
    required this.downloadLocation,
  });

  final ProfileRepository profileRepository;
  final SqliteAppSettingsRepository settingsRepository;
  final SqliteAudioLanguagePreferenceStore audioLanguagePreferenceStore;
  final EmbedPlaybackProvider playbackProvider;
  final SessionGateService sessionGateService;
  final MediaCatalogService? mediaCatalogService;
  final TmdbClient? tmdbClient;
  final TraktClient? traktClient;
  final TraktHomeRecommendationService? traktHomeRecommendationService;
  final TraktPlaybackReporter? traktPlaybackReporter;
  final UpdateService? updateService;
  final CaptionService captionService;
  final SavedTitleRepository savedTitleRepository;
  final PlaybackProgressRepository playbackProgressRepository;
  final OfflineDownloadManager offlineDownloadManager;
  final String downloadLocation;
}

class _RuntimeConfig {
  const _RuntimeConfig({
    required this.tmdbApiKey,
    required this.traktClientId,
    required this.traktClientSecret,
    required this.traktRedirectUri,
    required this.updateManifestUrl,
    required this.providerConfigPath,
    required this.captionServiceUrl,
    required this.sourceResolverServiceUrl,
    required this.subdlApiKey,
  });

  factory _RuntimeConfig.fromEnvironment() {
    return _RuntimeConfig(
      tmdbApiKey: _readConfigValue(
        'CHERIFLIX_TMDB_API_KEY',
        compileTimeValue: const String.fromEnvironment(
          'CHERIFLIX_TMDB_API_KEY',
        ),
        defaultValue: 'fb3ed1699a1fa5907eb72ad6870f8ddc',
      ),
      traktClientId: _readConfigValue(
        'CHERIFLIX_TRAKT_CLIENT_ID',
        compileTimeValue: const String.fromEnvironment(
          'CHERIFLIX_TRAKT_CLIENT_ID',
        ),
        defaultValue:
            'ba9b74e4981e997438b7cdeabf602d560d5e3bcb0fb875a47ea7498dab6578dd',
      ),
      traktClientSecret: _readConfigValue(
        'CHERIFLIX_TRAKT_CLIENT_SECRET',
        compileTimeValue: const String.fromEnvironment(
          'CHERIFLIX_TRAKT_CLIENT_SECRET',
        ),
        defaultValue:
            '46979cabb4ed93dda8c94450310503b211602c738591dccad08456551d614063',
      ),
      traktRedirectUri: _readConfigValue(
        'CHERIFLIX_TRAKT_REDIRECT_URI',
        compileTimeValue: const String.fromEnvironment(
          'CHERIFLIX_TRAKT_REDIRECT_URI',
        ),
        defaultValue: 'urn:ietf:wg:oauth:2.0:oob',
      ),
      updateManifestUrl: _readConfigValue(
        'CHERIFLIX_UPDATE_MANIFEST_URL',
        compileTimeValue: const String.fromEnvironment(
          'CHERIFLIX_UPDATE_MANIFEST_URL',
        ),
      ),
      providerConfigPath: _readConfigValue(
        'CHERIFLIX_PROVIDER_CONFIG_PATH',
        compileTimeValue: const String.fromEnvironment(
          'CHERIFLIX_PROVIDER_CONFIG_PATH',
        ),
      ),
      captionServiceUrl: _readConfigValue(
        'CHERIFLIX_CAPTION_SERVICE_URL',
        compileTimeValue: const String.fromEnvironment(
          'CHERIFLIX_CAPTION_SERVICE_URL',
        ),
      ),
      subdlApiKey: _readConfigValue(
        'CHERIFLIX_SUBDL_API_KEY',
        compileTimeValue: const String.fromEnvironment(
          'CHERIFLIX_SUBDL_API_KEY',
        ),
        defaultValue: 'PtFmHz7Gzv3FnK0P9GFTbFWRgDQFI9wH',
      ),
      sourceResolverServiceUrl: _readConfigValue(
        'CHERIFLIX_SOURCE_RESOLVER_URL',
        compileTimeValue: const String.fromEnvironment(
          'CHERIFLIX_SOURCE_RESOLVER_URL',
        ),
      ),
    );
  }

  static String _readConfigValue(
    String name, {
    required String compileTimeValue,
    String defaultValue = '',
  }) {
    final normalizedCompileTimeValue = compileTimeValue.trim();
    if (normalizedCompileTimeValue.isNotEmpty) {
      return normalizedCompileTimeValue;
    }

    final runtimeValue = Platform.environment[name]?.trim();
    if (runtimeValue != null && runtimeValue.isNotEmpty) {
      return runtimeValue;
    }

    return defaultValue;
  }

  final String tmdbApiKey;
  final String traktClientId;
  final String traktClientSecret;
  final String traktRedirectUri;
  final String updateManifestUrl;
  final String providerConfigPath;
  final String captionServiceUrl;
  final String sourceResolverServiceUrl;
  final String subdlApiKey;
}

class _BootstrapErrorScreen extends StatelessWidget {
  const _BootstrapErrorScreen({
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0x22FFFFFF)),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x4DE50914),
                  blurRadius: 28,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Startup failed',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'CHERIFLIX could not finish bootstrapping app services.',
                  style: TextStyle(
                    color: Color(0xFFB8B8B8),
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                SelectableText(
                  error.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 18,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    textStyle: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: const Text('Retry startup'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
