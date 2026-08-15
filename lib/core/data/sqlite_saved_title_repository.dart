import 'package:sqflite/sqflite.dart';

import '../models/media_summary.dart';
import '../models/media_type.dart';
import '../services/saved_title_repository.dart';

class SqliteSavedTitleRepository implements SavedTitleRepository {
  const SqliteSavedTitleRepository(this._database);

  final Database _database;

  @override
  Future<List<MediaSummary>> fetchSavedTitles(String profileId) async {
    final rows = await _database.query(
      'saved_titles',
      where: 'profile_id = ?',
      whereArgs: <Object?>[profileId],
      orderBy: 'saved_at DESC',
    );

    return rows.map((row) {
      return MediaSummary(
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
      );
    }).toList();
  }

  @override
  Future<void> removeTitle({
    required String profileId,
    required int tmdbId,
    required MediaType mediaType,
  }) {
    return _database.delete(
      'saved_titles',
      where: 'profile_id = ? AND tmdb_id = ? AND media_type = ?',
      whereArgs: <Object?>[profileId, tmdbId, mediaType.name],
    );
  }

  @override
  Future<void> saveTitle({
    required String profileId,
    required MediaSummary summary,
  }) {
    return _database.insert(
      'saved_titles',
      <String, Object?>{
        'profile_id': profileId,
        'tmdb_id': summary.tmdbId,
        'media_type': summary.mediaType.name,
        'title': summary.title,
        'overview': summary.overview,
        'poster_path': summary.posterPath,
        'backdrop_path': summary.backdropPath,
        'rating': summary.rating,
        'release_date': summary.releaseDate?.toIso8601String(),
        'saved_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
