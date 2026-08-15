import 'dart:math' as math;

import 'package:dio/dio.dart';

import '../../models/media_type.dart';
import '../../utils/safe_logging.dart';
import 'subdl_models.dart';

class SubdlClient {
  SubdlClient({
    required String apiKey,
    Dio? dio,
  })  : _apiKey = apiKey.trim(),
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://api.subdl.com/api/v1/subtitles',
                connectTimeout: const Duration(seconds: 6),
                receiveTimeout: const Duration(seconds: 14),
                sendTimeout: const Duration(seconds: 8),
              ),
            );

  final Dio _dio;
  final String _apiKey;

  bool get hasApiKey => _apiKey.isNotEmpty;

  Future<List<SubdlSubtitle>> searchByImdb({
    required String imdbId,
    required MediaType mediaType,
    int? seasonNumber,
    int? episodeNumber,
    required List<String> languages,
    int? year,
  }) {
    return _search(
      <String, String>{
        'imdb_id': imdbId,
        'type': mediaType == MediaType.movie ? 'movie' : 'tv',
        if (seasonNumber != null) 'season_number': '$seasonNumber',
        if (episodeNumber != null) 'episode_number': '$episodeNumber',
        if (languages.isNotEmpty) 'languages': languages.join(','),
        if (year != null) 'year': '$year',
      },
    );
  }

  Future<List<SubdlSubtitle>> searchByTmdb({
    required int tmdbId,
    required MediaType mediaType,
    int? seasonNumber,
    int? episodeNumber,
    required List<String> languages,
    int? year,
  }) {
    return _search(
      <String, String>{
        'tmdb_id': '$tmdbId',
        'type': mediaType == MediaType.movie ? 'movie' : 'tv',
        if (seasonNumber != null) 'season_number': '$seasonNumber',
        if (episodeNumber != null) 'episode_number': '$episodeNumber',
        if (languages.isNotEmpty) 'languages': languages.join(','),
        if (year != null) 'year': '$year',
      },
    );
  }

  Future<List<SubdlSubtitle>> searchByName({
    required String filmName,
    required MediaType mediaType,
    int? seasonNumber,
    int? episodeNumber,
    required List<String> languages,
    int? year,
  }) {
    return _search(
      <String, String>{
        'film_name': filmName,
        'type': mediaType == MediaType.movie ? 'movie' : 'tv',
        if (seasonNumber != null) 'season_number': '$seasonNumber',
        if (episodeNumber != null) 'episode_number': '$episodeNumber',
        if (languages.isNotEmpty) 'languages': languages.join(','),
        if (year != null) 'year': '$year',
      },
    );
  }

  Future<List<int>> downloadSubtitle(String subtitleId) async {
    if (!hasApiKey) {
      return const <int>[];
    }
    final downloadUri = subtitleId.trim().isEmpty
        ? null
        : Uri.parse('https://dl.subdl.com/subtitle/${subtitleId.trim()}.zip');
    if (downloadUri == null) {
      return const <int>[];
    }
    final response = await _requestWithRetry<List<int>>(
      () => _dio.getUri<List<int>>(
        downloadUri,
        options: Options(responseType: ResponseType.bytes),
      ),
    );
    return response.data ?? const <int>[];
  }

  Future<List<int>> downloadSubtitleByMetadata(SubdlSubtitle subtitle) async {
    if (!hasApiKey) {
      return const <int>[];
    }
    final downloadUri = subtitle.resolveDownloadUri();
    if (downloadUri == null) {
      return const <int>[];
    }
    final response = await _requestWithRetry<List<int>>(
      () => _dio.getUri<List<int>>(
        downloadUri,
        options: Options(responseType: ResponseType.bytes),
      ),
    );
    return response.data ?? const <int>[];
  }

  Future<List<SubdlSubtitle>> _search(Map<String, String> params) async {
    if (!hasApiKey) {
      return const <SubdlSubtitle>[];
    }
    final normalized = <String, String>{
      ...params,
      'api_key': _apiKey,
    };
    Response<Map<String, dynamic>> response;
    try {
      response = await _requestWithRetry<Map<String, dynamic>>(
        () => _dio.get<Map<String, dynamic>>(
          '',
          queryParameters: normalized,
        ),
      );
    } catch (error) {
      cheriflixLog('subdl', 'Search request failed.', error: error);
      rethrow;
    }
    final payload = response.data;
    if (payload == null) {
      cheriflixLog(
        'subdl',
        'Search returned no payload. status=${response.statusCode}',
      );
      return const <SubdlSubtitle>[];
    }
    if (payload['status'] != true) {
      cheriflixLog(
        'subdl',
        'Search returned unsuccessful payload. status=${response.statusCode}',
      );
      return const <SubdlSubtitle>[];
    }
    final list = payload['subtitles'] ?? payload['results'];
    if (list is! List<dynamic>) {
      cheriflixLog(
        'subdl',
        'Search returned no subtitle list. status=${response.statusCode}',
      );
      return const <SubdlSubtitle>[];
    }
    final subtitles = list
        .whereType<Map<String, dynamic>>()
        .map(SubdlSubtitle.fromJson)
        .where((subtitle) => subtitle.hasDownloadReference)
        .toList(growable: false);
    cheriflixLog(
      'subdl',
      'Search returned ${subtitles.length} usable subtitles. '
          'status=${response.statusCode}',
    );
    return subtitles;
  }

  Future<Response<T>> _requestWithRetry<T>(
    Future<Response<T>> Function() request,
  ) async {
    const maxAttempts = 4;
    var attempt = 0;
    while (true) {
      attempt += 1;
      try {
        return await request();
      } on DioException catch (error) {
        final statusCode = error.response?.statusCode ?? 0;
        final isRetriableStatus = statusCode == 429 || statusCode >= 500;
        final isRetriableType =
            error.type == DioExceptionType.connectionTimeout ||
                error.type == DioExceptionType.sendTimeout ||
                error.type == DioExceptionType.receiveTimeout ||
                error.type == DioExceptionType.connectionError;
        if (attempt >= maxAttempts ||
            (!isRetriableStatus && !isRetriableType)) {
          rethrow;
        }
        final retryAfterHeader =
            error.response?.headers.value('retry-after')?.trim();
        final retryAfterSeconds = int.tryParse(retryAfterHeader ?? '');
        final jitterMs = math.Random().nextInt(220);
        final delayMs = retryAfterSeconds != null && retryAfterSeconds > 0
            ? retryAfterSeconds * 1000 + jitterMs
            : (220 * (1 << (attempt - 1))) + jitterMs;
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
    }
  }
}
