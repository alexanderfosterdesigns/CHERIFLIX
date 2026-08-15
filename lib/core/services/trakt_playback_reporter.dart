import '../models/media_type.dart';
import '../models/playback_progress_entry.dart';
import '../models/profile.dart';
import 'trakt_client.dart';

class TraktPlaybackReporter {
  TraktPlaybackReporter({
    required this.traktClient,
  });

  final TraktClient traktClient;
  final Map<String, TraktScrobbleAction> _lastActionByPlaybackKey =
      <String, TraktScrobbleAction>{};
  final Set<String> _historySyncedPlaybackKeys = <String>{};

  Future<void> reportPlayback({
    required Profile profile,
    required PlaybackProgressEntry entry,
    required bool paused,
  }) async {
    final account = profile.traktAccount;
    if (account == null || !entry.hasStarted) {
      return;
    }

    final playbackKey = '${profile.id}:${entry.entryKey}';
    final action = entry.isCompleted
        ? TraktScrobbleAction.stop
        : paused
            ? TraktScrobbleAction.pause
            : TraktScrobbleAction.start;
    if (_lastActionByPlaybackKey[playbackKey] == action) {
      return;
    }

    final progress = _progressPercent(entry);
    if (entry.summary.mediaType == MediaType.movie) {
      await traktClient.scrobbleMovie(
        accessToken: account.accessToken,
        summary: entry.summary,
        progress: progress,
        action: action,
      );
    } else {
      final seasonNumber = entry.seasonNumber;
      final episodeNumber = entry.episodeNumber;
      if (seasonNumber == null || episodeNumber == null) {
        return;
      }
      await traktClient.scrobbleEpisode(
        accessToken: account.accessToken,
        showTmdbId: entry.summary.tmdbId,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        progress: progress,
        action: action,
      );
    }

    _lastActionByPlaybackKey[playbackKey] = action;
    if (entry.isCompleted && _historySyncedPlaybackKeys.add(playbackKey)) {
      await traktClient.addPlaybackToHistory(
        accessToken: account.accessToken,
        entry: entry,
      );
    }
  }

  void clearProfile(String profileId) {
    final keyPrefix = '$profileId:';
    _lastActionByPlaybackKey.removeWhere((key, _) => key.startsWith(keyPrefix));
    _historySyncedPlaybackKeys.removeWhere((key) => key.startsWith(keyPrefix));
  }

  int _progressPercent(PlaybackProgressEntry entry) {
    final totalMillis = entry.totalDuration.inMilliseconds;
    if (totalMillis <= 0) {
      return 0;
    }
    final rawProgress = entry.position.inMilliseconds / totalMillis * 100;
    return rawProgress.round().clamp(0, 100);
  }
}
