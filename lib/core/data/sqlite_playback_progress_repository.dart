import 'package:sqflite/sqflite.dart';

import '../models/media_summary.dart';
import '../models/media_type.dart';
import '../models/playback_progress_entry.dart';
import '../services/playback_progress_repository.dart';

class SqlitePlaybackProgressRepository implements PlaybackProgressRepository {
  const SqlitePlaybackProgressRepository(this._database);

  final Database _database;

  @override
  Future<List<PlaybackProgressEntry>> fetchProgressEntries(
    String profileId, {
    int limit = 200,
  }) async {
    final rows = await _database.query(
      'playback_progress',
      where: 'profile_id = ?',
      whereArgs: <Object?>[profileId],
      orderBy: 'updated_at DESC',
      limit: limit,
    );

    return rows.map(_entryFromRow).toList(growable: false);
  }

  @override
  Future<void> removeProgress({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
    int? seasonNumber,
    int? episodeNumber,
  }) {
    return _database.delete(
      'playback_progress',
      where: '''
        profile_id = ? AND
        tmdb_id = ? AND
        media_type = ? AND
        season_number = ? AND
        episode_number = ?
      ''',
      whereArgs: <Object?>[
        profileId,
        tmdbId,
        mediaType.name,
        seasonNumber ?? 0,
        episodeNumber ?? 0,
      ],
    );
  }

  @override
  Future<void> saveProgress({
    required String profileId,
    required PlaybackProgressEntry entry,
    int limit = 200,
  }) async {
    await _database.insert(
      'playback_progress',
      <String, Object?>{
        'profile_id': profileId,
        'tmdb_id': entry.summary.tmdbId,
        'media_type': entry.summary.mediaType.name,
        'season_number': entry.seasonNumber ?? 0,
        'episode_number': entry.episodeNumber ?? 0,
        'title': entry.summary.title,
        'overview': entry.summary.overview,
        'poster_path': entry.summary.posterPath,
        'backdrop_path': entry.summary.backdropPath,
        'rating': entry.summary.rating,
        'release_date': entry.summary.releaseDate?.toIso8601String(),
        'episode_title': entry.episodeTitle,
        'episode_still_path': entry.episodeStillPath,
        'position_ms': entry.position.inMilliseconds,
        'duration_ms': entry.totalDuration.inMilliseconds,
        'updated_at': entry.updatedAt.toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _database.rawDelete(
      '''
      DELETE FROM playback_progress
      WHERE rowid NOT IN (
        SELECT rowid
        FROM playback_progress
        WHERE profile_id = ?
        ORDER BY updated_at DESC
        LIMIT ?
      )
      AND profile_id = ?
      ''',
      <Object?>[profileId, limit, profileId],
    );
  }

  PlaybackProgressEntry _entryFromRow(Map<String, Object?> row) {
    return PlaybackProgressEntry(
      summary: MediaSummary(
        tmdbId: row['tmdb_id']! as int,
        mediaType: (row['media_type']! as String) == 'tv'
            ? MediaType.tv
            : MediaType.movie,
        title: row['title']! as String,
        overview: row['overview'] as String?,
        posterPath: row['poster_path'] as String?,
        backdropPath: row['backdrop_path'] as String?,
        rating: (row['rating'] as num?)?.toDouble(),
        releaseDate: row['release_date'] == null
            ? null
            : DateTime.tryParse(row['release_date']! as String),
      ),
      seasonNumber: () {
        final value = (row['season_number'] as num?)?.toInt() ?? 0;
        return value > 0 ? value : null;
      }(),
      episodeNumber: () {
        final value = (row['episode_number'] as num?)?.toInt() ?? 0;
        return value > 0 ? value : null;
      }(),
      episodeTitle: row['episode_title'] as String?,
      episodeStillPath: row['episode_still_path'] as String?,
      position:
          Duration(milliseconds: (row['position_ms'] as num?)?.toInt() ?? 0),
      totalDuration:
          Duration(milliseconds: (row['duration_ms'] as num?)?.toInt() ?? 0),
      updatedAt: DateTime.tryParse(row['updated_at']! as String)?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}
