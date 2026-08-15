import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:cheriflix/core/models/caption_resolution.dart';
import 'package:cheriflix/core/models/media_type.dart';
import 'package:cheriflix/core/services/subtitles/subdl_caption_service.dart';
import 'package:cheriflix/core/services/subtitles/subdl_client.dart';
import 'package:cheriflix/core/services/subtitles/subdl_models.dart';
import 'package:cheriflix/core/services/subtitles/subdl_provider.dart';
import 'package:cheriflix/core/services/subtitles/subtitle_cache_store.dart';
import 'package:cheriflix/core/services/subtitles/subtitle_provider.dart';

void main() {
  test('SubdlSubtitle parses URL-only payload into usable download identity',
      () {
    final subtitle = SubdlSubtitle.fromJson(<String, dynamic>{
      'url': '/subtitle/3519200-8441826.zip',
      'language': 'EN',
      'release_name': 'The.Boys.S01E01',
    });

    expect(subtitle.id, '3519200-8441826');
    expect(subtitle.hasDownloadReference, isTrue);
    expect(
      subtitle.resolveDownloadUri(),
      Uri.parse('https://dl.subdl.com/subtitle/3519200-8441826.zip'),
    );
  });

  test('SubdlClient downloads using relative and absolute subtitle URLs',
      () async {
    final requestedUris = <Uri>[];
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requestedUris.add(options.uri);
          handler.resolve(
            Response<List<int>>(
              requestOptions: options,
              statusCode: 200,
              data: const <int>[1, 2, 3],
            ),
          );
        },
      ),
    );
    final client = SubdlClient(apiKey: 'api-key', dio: dio);

    final relative = SubdlSubtitle.fromJson(<String, dynamic>{
      'subtitle_id': '3519200-8441826',
      'url': '/subtitle/3519200-8441826.zip',
      'language': 'EN',
    });
    final absolute = SubdlSubtitle.fromJson(<String, dynamic>{
      'subtitle_id': '3573796-8492652',
      'url': 'https://dl.subdl.com/subtitle/3573796-8492652.zip',
      'language': 'EN',
    });

    final firstBytes = await client.downloadSubtitleByMetadata(relative);
    final secondBytes = await client.downloadSubtitleByMetadata(absolute);

    expect(firstBytes, isNotEmpty);
    expect(secondBytes, isNotEmpty);
    expect(
      requestedUris,
      <Uri>[
        Uri.parse('https://dl.subdl.com/subtitle/3519200-8441826.zip'),
        Uri.parse('https://dl.subdl.com/subtitle/3573796-8492652.zip'),
      ],
    );
  });

  test('SubdlProvider does not cache empty search results', () async {
    final harness = await _SubtitleCacheHarness.create();
    final client = _FakeSubdlClient(tmdbResults: const <SubdlSubtitle>[]);
    final provider = SubdlProvider(
      client: client,
      cacheStore: harness.cacheStore,
    );

    const request = SubtitleSearchRequest(
      tmdbId: 76479,
      mediaType: MediaType.tv,
      seasonNumber: 1,
      episodeNumber: 1,
      languageCodes: <String>['en'],
    );

    await provider.search(request);
    await provider.search(request);

    expect(client.tmdbSearchCalls, 2);
  });

  test('SubdlProvider v2 cache key bypasses older cache entries', () async {
    final harness = await _SubtitleCacheHarness.create();
    const oldCachedSubtitle = SubdlSubtitle(
      id: 'old-id',
      language: 'EN',
      releaseName: 'old',
      author: 'old',
      hi: false,
      url: '/subtitle/old-id.zip',
      rating: 0,
    );
    await harness.cacheStore.writeSearchEntry(
      'tmdb:76479:s01e01:EN',
      const <SubdlSubtitle>[oldCachedSubtitle],
    );

    const freshSubtitle = SubdlSubtitle(
      id: 'fresh-id',
      language: 'EN',
      releaseName: 'fresh',
      author: 'fresh',
      hi: false,
      url: '/subtitle/fresh-id.zip',
      rating: 0,
    );
    final client =
        _FakeSubdlClient(tmdbResults: const <SubdlSubtitle>[freshSubtitle]);
    final provider = SubdlProvider(
      client: client,
      cacheStore: harness.cacheStore,
    );

    const request = SubtitleSearchRequest(
      tmdbId: 76479,
      mediaType: MediaType.tv,
      seasonNumber: 1,
      episodeNumber: 1,
      languageCodes: <String>['en'],
    );

    final results = await provider.search(request);

    expect(client.tmdbSearchCalls, 1);
    expect(results, isNotEmpty);
    expect(results.first.id, 'fresh-id');
  });

  test('SubdlProvider prioritizes exact TV episode subtitles', () async {
    final harness = await _SubtitleCacheHarness.create();
    const episodeOne = SubdlSubtitle(
      id: 's01e01',
      language: 'EN',
      releaseName: 'Demo.Show.S01E01.1080p',
      author: 'exact',
      hi: false,
      url: '/subtitle/s01e01.zip',
      rating: 2,
      seasonNumber: 1,
      episodeNumber: 1,
    );
    const episodeTwo = SubdlSubtitle(
      id: 's01e02',
      language: 'EN',
      releaseName: 'Demo.Show.S01E02.1080p',
      author: 'wrong',
      hi: false,
      url: '/subtitle/s01e02.zip',
      rating: 9,
      seasonNumber: 1,
      episodeNumber: 2,
    );
    final client = _FakeSubdlClient(
      tmdbResults: const <SubdlSubtitle>[episodeTwo, episodeOne],
    );
    final provider = SubdlProvider(
      client: client,
      cacheStore: harness.cacheStore,
    );

    const request = SubtitleSearchRequest(
      tmdbId: 79744,
      mediaType: MediaType.tv,
      seasonNumber: 1,
      episodeNumber: 1,
      languageCodes: <String>['en'],
    );

    final results = await provider.search(request);

    expect(results.map((subtitle) => subtitle.id), <String>['s01e01']);
  });

  test(
      'SubdlProvider keeps exact episode matches ahead of full-season fallback',
      () async {
    final harness = await _SubtitleCacheHarness.create();
    const exact = SubdlSubtitle(
      id: 'exact-s01e03',
      language: 'EN',
      releaseName: 'Demo.Show.S01E03.1080p',
      author: 'exact',
      hi: false,
      url: '/subtitle/exact-s01e03.zip',
      rating: 2,
      seasonNumber: 1,
      episodeNumber: 3,
    );
    const fullSeason = SubdlSubtitle(
      id: 'full-s01',
      language: 'EN',
      releaseName: 'Demo.Show.S01.COMPLETE',
      author: 'season-pack',
      hi: false,
      url: '/subtitle/full-s01.zip',
      rating: 10,
      seasonNumber: 1,
      fullSeason: true,
    );
    final client = _FakeSubdlClient(
      tmdbResults: const <SubdlSubtitle>[fullSeason, exact],
    );
    final provider = SubdlProvider(
      client: client,
      cacheStore: harness.cacheStore,
    );

    const request = SubtitleSearchRequest(
      tmdbId: 79744,
      mediaType: MediaType.tv,
      seasonNumber: 1,
      episodeNumber: 3,
      languageCodes: <String>['en'],
    );

    final results = await provider.search(request);
    expect(results.map((subtitle) => subtitle.id), <String>['exact-s01e03']);
  });

  test('SubdlCaptionService returns missing_api_key failure code', () async {
    final harness = await _SubtitleCacheHarness.create();
    final fakeProvider = _FakeSubtitleProvider(
      searchResults: const <SubdlSubtitle>[],
    );
    final service = SubdlCaptionService(
      coordinator: SubtitleProviderCoordinator(primary: fakeProvider),
      cacheStore: harness.cacheStore,
      hasConfiguredApiKey: false,
    );

    final resolution = await service.resolveCaptions(
      tmdbId: 76479,
      mediaType: MediaType.tv,
      languageCode: 'en',
      seasonNumber: 1,
      episodeNumber: 1,
      title: 'The Boys',
    );

    expect(resolution.tracks, isEmpty);
    expect(resolution.failureCode, CaptionFailureCode.missingApiKey);
  });

  test('SubdlCaptionService maps no-match and prepare-failed outcomes',
      () async {
    final noMatchHarness = await _SubtitleCacheHarness.create();
    final noMatchProvider = _FakeSubtitleProvider(
      searchResults: const <SubdlSubtitle>[],
    );
    final noMatchService = SubdlCaptionService(
      coordinator: SubtitleProviderCoordinator(primary: noMatchProvider),
      cacheStore: noMatchHarness.cacheStore,
      hasConfiguredApiKey: true,
    );

    final noMatchResolution = await noMatchService.resolveCaptions(
      tmdbId: 76479,
      mediaType: MediaType.tv,
      languageCode: 'en',
      seasonNumber: 1,
      episodeNumber: 1,
      title: 'The Boys',
    );
    expect(noMatchResolution.failureCode, CaptionFailureCode.noMatch);

    final prepareHarness = await _SubtitleCacheHarness.create();
    const subtitle = SubdlSubtitle(
      id: 'prepare-me',
      language: 'EN',
      releaseName: 'The.Boys.S01E01',
      author: 'test',
      hi: false,
      url: '/subtitle/prepare-me.zip',
      rating: 0,
    );
    final prepareProvider = _FakeSubtitleProvider(
      searchResults: const <SubdlSubtitle>[subtitle],
      preparedTracks: const <String, SubtitleTrack?>{},
    );
    final prepareService = SubdlCaptionService(
      coordinator: SubtitleProviderCoordinator(primary: prepareProvider),
      cacheStore: prepareHarness.cacheStore,
      hasConfiguredApiKey: true,
    );

    final prepareResolution = await prepareService.resolveCaptions(
      tmdbId: 76479,
      mediaType: MediaType.tv,
      languageCode: 'en',
      seasonNumber: 1,
      episodeNumber: 1,
      title: 'The Boys',
    );
    expect(prepareResolution.failureCode, CaptionFailureCode.prepareFailed);
  });

  test('SubdlCaptionService stores subtitle offsets per provider key',
      () async {
    final harness = await _SubtitleCacheHarness.create();
    final service = SubdlCaptionService(
      coordinator: SubtitleProviderCoordinator(
        primary: _FakeSubtitleProvider(searchResults: const <SubdlSubtitle>[]),
      ),
      cacheStore: harness.cacheStore,
      hasConfiguredApiKey: true,
    );

    await service.writeOffsetMs(
      tmdbId: 79744,
      mediaType: MediaType.tv,
      seasonNumber: 1,
      episodeNumber: 1,
      offsetMs: 900,
      providerKey: 'vidsrc',
    );
    await service.writeOffsetMs(
      tmdbId: 79744,
      mediaType: MediaType.tv,
      seasonNumber: 1,
      episodeNumber: 1,
      offsetMs: -200,
      providerKey: 'vidlink',
    );

    final vidsrcOffset = await service.readOffsetMs(
      tmdbId: 79744,
      mediaType: MediaType.tv,
      seasonNumber: 1,
      episodeNumber: 1,
      providerKey: 'vidsrc',
    );
    final vidlinkOffset = await service.readOffsetMs(
      tmdbId: 79744,
      mediaType: MediaType.tv,
      seasonNumber: 1,
      episodeNumber: 1,
      providerKey: 'vidlink',
    );

    expect(vidsrcOffset, 900);
    expect(vidlinkOffset, -200);
  });

  test('SubdlCaptionService offset lookup prefers exact VidSrc episode key',
      () async {
    final harness = await _SubtitleCacheHarness.create();
    final service = SubdlCaptionService(
      coordinator: SubtitleProviderCoordinator(
        primary: _FakeSubtitleProvider(searchResults: const <SubdlSubtitle>[]),
      ),
      cacheStore: harness.cacheStore,
      hasConfiguredApiKey: true,
    );

    await service.writeOffsetMs(
      tmdbId: 79744,
      mediaType: MediaType.tv,
      seasonNumber: 1,
      episodeNumber: 2,
      offsetMs: 700,
      providerKey: 'vidsrc',
    );
    await service.writeOffsetMs(
      tmdbId: 79744,
      mediaType: MediaType.tv,
      seasonNumber: 1,
      episodeNumber: 1,
      offsetMs: 150,
      providerKey: 'vidsrc',
    );

    final offset = await service.readOffsetMs(
      tmdbId: 79744,
      mediaType: MediaType.tv,
      seasonNumber: 1,
      episodeNumber: 1,
      providerKey: 'vidsrc',
      allowProviderScopedFallback: true,
    );

    expect(offset, 150);
  });

  test('SubdlCaptionService VidSrc fallback inherits nearest season episode',
      () async {
    final harness = await _SubtitleCacheHarness.create();
    final service = SubdlCaptionService(
      coordinator: SubtitleProviderCoordinator(
        primary: _FakeSubtitleProvider(searchResults: const <SubdlSubtitle>[]),
      ),
      cacheStore: harness.cacheStore,
      hasConfiguredApiKey: true,
    );

    await service.writeOffsetMs(
      tmdbId: 79744,
      mediaType: MediaType.tv,
      seasonNumber: 1,
      episodeNumber: 2,
      offsetMs: 450,
      providerKey: 'vidsrc',
    );
    await service.writeOffsetMs(
      tmdbId: 79744,
      mediaType: MediaType.tv,
      seasonNumber: 1,
      episodeNumber: 6,
      offsetMs: -300,
      providerKey: 'vidsrc',
    );

    final offset = await service.readOffsetMs(
      tmdbId: 79744,
      mediaType: MediaType.tv,
      seasonNumber: 1,
      episodeNumber: 4,
      providerKey: 'vidsrc',
      allowProviderScopedFallback: true,
    );

    expect(offset, -300);
  });

  test('SubdlCaptionService VidSrc fallback does not read other providers',
      () async {
    final harness = await _SubtitleCacheHarness.create();
    final service = SubdlCaptionService(
      coordinator: SubtitleProviderCoordinator(
        primary: _FakeSubtitleProvider(searchResults: const <SubdlSubtitle>[]),
      ),
      cacheStore: harness.cacheStore,
      hasConfiguredApiKey: true,
    );

    await service.writeOffsetMs(
      tmdbId: 79744,
      mediaType: MediaType.tv,
      seasonNumber: 1,
      episodeNumber: 2,
      offsetMs: 500,
      providerKey: 'vidlink',
    );

    final offset = await service.readOffsetMs(
      tmdbId: 79744,
      mediaType: MediaType.tv,
      seasonNumber: 1,
      episodeNumber: 3,
      providerKey: 'vidsrc',
      allowProviderScopedFallback: true,
    );

    expect(offset, 0);
  });
}

class _FakeSubdlClient extends SubdlClient {
  _FakeSubdlClient({
    required this.tmdbResults,
  }) : super(apiKey: 'api-key', dio: Dio());

  final List<SubdlSubtitle> tmdbResults;
  int tmdbSearchCalls = 0;

  @override
  Future<List<SubdlSubtitle>> searchByTmdb({
    required int tmdbId,
    required MediaType mediaType,
    int? seasonNumber,
    int? episodeNumber,
    required List<String> languages,
    int? year,
  }) async {
    tmdbSearchCalls += 1;
    return tmdbResults;
  }

  @override
  Future<List<SubdlSubtitle>> searchByImdb({
    required String imdbId,
    required MediaType mediaType,
    int? seasonNumber,
    int? episodeNumber,
    required List<String> languages,
    int? year,
  }) async {
    return const <SubdlSubtitle>[];
  }

  @override
  Future<List<SubdlSubtitle>> searchByName({
    required String filmName,
    required MediaType mediaType,
    int? seasonNumber,
    int? episodeNumber,
    required List<String> languages,
    int? year,
  }) async {
    return const <SubdlSubtitle>[];
  }
}

class _FakeSubtitleProvider implements SubtitleProvider {
  _FakeSubtitleProvider({
    required this.searchResults,
    this.preparedTracks = const <String, SubtitleTrack?>{},
    this.throwOnSearch = false,
  });

  final List<SubdlSubtitle> searchResults;
  final Map<String, SubtitleTrack?> preparedTracks;
  final bool throwOnSearch;

  @override
  Future<SubtitleTrack?> downloadAndPrepareTrack(
    SubdlSubtitle subtitle, {
    required String expectedLanguageCode,
    required bool preferHi,
  }) async {
    return preparedTracks[subtitle.id];
  }

  @override
  Future<void> prefetch(SubtitleSearchRequest request) async {}

  @override
  Future<List<SubdlSubtitle>> search(SubtitleSearchRequest request) async {
    if (throwOnSearch) {
      throw StateError('search failed');
    }
    return searchResults;
  }
}

class _SubtitleCacheHarness {
  _SubtitleCacheHarness({
    required this.directory,
    required this.metadataBox,
    required this.offsetBox,
    required this.cacheStore,
  });

  final Directory directory;
  final Box<String> metadataBox;
  final Box<int> offsetBox;
  final SubtitleCacheStore cacheStore;

  static int _counter = 0;

  static Future<_SubtitleCacheHarness> create() async {
    _counter += 1;
    final directory =
        Directory.systemTemp.createTempSync('cheriflix-subdl-test-$_counter');
    Hive.init(directory.path);
    final metadataBox = await Hive.openBox<String>('subtitle_meta_$_counter');
    final offsetBox = await Hive.openBox<int>('subtitle_offset_$_counter');
    final store = SubtitleCacheStore(
      metadataBox: metadataBox,
      offsetBox: offsetBox,
      subtitleRootDirectory:
          Directory('${directory.path}${Platform.pathSeparator}subtitles'),
    );
    final harness = _SubtitleCacheHarness(
      directory: directory,
      metadataBox: metadataBox,
      offsetBox: offsetBox,
      cacheStore: store,
    );
    addTearDown(harness.dispose);
    return harness;
  }

  Future<void> dispose() async {
    await metadataBox.close();
    await offsetBox.close();
    try {
      await Hive.deleteBoxFromDisk(metadataBox.name);
    } catch (_) {}
    try {
      await Hive.deleteBoxFromDisk(offsetBox.name);
    } catch (_) {}
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }
}
