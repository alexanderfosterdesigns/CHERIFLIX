import 'package:flutter/material.dart';

import '../../core/models/episode_summary.dart';
import '../../core/models/media_summary.dart';
import '../../core/models/playback_progress_snapshot.dart';
import '../../core/models/profile.dart';
import '../../core/services/media_catalog_service.dart';
import '../../core/services/offline_download_manager.dart';
import '../../core/theme/cheriflix_theme.dart';
import '../../core/services/tmdb_image_service.dart';
import '../../core/widgets/cheriflix_network_image.dart';
import '../../core/widgets/cheriflix_chrome.dart';
import '../../core/widgets/tv_shortcuts.dart';
import 'episodes_browser.dart';

class EpisodesScreen extends StatelessWidget {
  const EpisodesScreen({
    super.key,
    required this.activeProfile,
    required this.summary,
    required this.playbackProgress,
    required this.languageCode,
    this.hideSpoilers = false,
    required this.onBack,
    required this.onPlayEpisode,
    this.mediaCatalogService,
    this.initialSeasonNumber = 1,
    this.onBrowseHome,
    this.onBrowseTvShows,
    this.onBrowseMovies,
    this.onBrowseNewPopular,
    this.onBrowseMyList,
    this.onOpenSearch,
    this.onOpenSettings,
    this.onSwitchProfile,
    this.onDownloadEpisode,
    this.downloadManager,
  });

  final Profile activeProfile;
  final MediaSummary summary;
  final PlaybackProgressSnapshot playbackProgress;
  final String languageCode;
  final bool hideSpoilers;
  final VoidCallback onBack;
  final void Function(int seasonNumber, EpisodeSummary episode) onPlayEpisode;
  final MediaCatalogService? mediaCatalogService;
  final int initialSeasonNumber;
  final VoidCallback? onBrowseHome;
  final VoidCallback? onBrowseTvShows;
  final VoidCallback? onBrowseMovies;
  final VoidCallback? onBrowseNewPopular;
  final VoidCallback? onBrowseMyList;
  final VoidCallback? onOpenSearch;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onSwitchProfile;
  final void Function(int seasonNumber, EpisodeSummary episode)?
      onDownloadEpisode;
  final OfflineDownloadManager? downloadManager;

  @override
  Widget build(BuildContext context) {
    return TvShortcutScope(
      onBack: onBack,
      child: CheriflixScaffold(
        topBar: null,
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            EpisodesBackdrop(imageUrl: summary.backdropUrl),
            Padding(
              padding: episodesPagePaddingFor(context),
              child: EpisodesBrowser(
                summary: summary,
                playbackProgress: playbackProgress,
                languageCode: languageCode,
                hideSpoilers: hideSpoilers,
                mediaCatalogService: mediaCatalogService,
                initialSeasonNumber: initialSeasonNumber,
                onPlayEpisode: onPlayEpisode,
                onDownloadEpisode: onDownloadEpisode,
                downloadManager: downloadManager,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

EdgeInsets episodesPagePaddingFor(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return EdgeInsets.fromLTRB(
    size.width * 0.014,
    size.height * 0.036,
    size.width * 0.032,
    size.height * 0.032,
  );
}

class EpisodesBackdrop extends StatelessWidget {
  const EpisodesBackdrop({
    super.key,
    required this.imageUrl,
  });

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final size = MediaQuery.sizeOf(context);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        CheriflixNetworkImage(
          imageUrl: imageUrl,
          width: size.width,
          height: size.height,
          devicePixelRatio: devicePixelRatio,
          preset: TmdbImagePreset.heroBackdrop,
          maxDecodePixels: 1600,
          placeholderColor: CheriflixColors.background,
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[
                Color(0xF0141414),
                Color(0xCC141414),
                Color(0x8C141414),
                Color(0x44141414),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
