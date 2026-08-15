import 'source_resolver_models.dart';

class ProviderCatalog {
  const ProviderCatalog();

  static const List<ProviderDescriptor> _defaultProviders =
      <ProviderDescriptor>[
    ProviderDescriptor(
      canonicalIndex: 1,
      key: 'vidlink',
      label: 'VidLink',
      buildMovieUri: _vidLinkMovie,
      buildShowUri: _showUnsupported,
      buildEpisodeUri: _vidLinkEpisode,
    ),
    ProviderDescriptor(
      canonicalIndex: 2,
      key: 'vidsrc_embed',
      label: 'VidSrc Embed',
      buildMovieUri: _vidsrcEmbedMovie,
      buildShowUri: _vidsrcEmbedShow,
      buildEpisodeUri: _vidsrcEmbedEpisode,
    ),
    ProviderDescriptor(
      canonicalIndex: 3,
      key: 'videasy',
      label: 'VidEasy',
      buildMovieUri: _vidEasyMovie,
      buildShowUri: _showUnsupported,
      buildEpisodeUri: _vidEasyEpisode,
    ),
    ProviderDescriptor(
      canonicalIndex: 4,
      key: '111movies',
      label: '111Movies',
      buildMovieUri: _oneElevenMoviesMovie,
      buildShowUri: _showUnsupported,
      buildEpisodeUri: _oneElevenMoviesEpisode,
    ),
    ProviderDescriptor(
      canonicalIndex: 5,
      key: 'vidzee',
      label: 'VidZee',
      buildMovieUri: _vidzeeMovie,
      buildShowUri: _showUnsupported,
      buildEpisodeUri: _vidzeeEpisode,
    ),
    ProviderDescriptor(
      canonicalIndex: 6,
      key: 'vidsrc',
      label: 'VidSrc',
      buildMovieUri: _vidsrcMovie,
      buildShowUri: _showUnsupported,
      buildEpisodeUri: _vidsrcEpisode,
      probeAttempts: 3,
      probeTimeoutSeconds: 12,
    ),
    ProviderDescriptor(
      canonicalIndex: 7,
      key: '2embed',
      label: '2Embed',
      buildMovieUri: _twoEmbedMovie,
      buildShowUri: _showUnsupported,
      buildEpisodeUri: _twoEmbedEpisode,
    ),
    ProviderDescriptor(
      canonicalIndex: 8,
      key: 'mapple',
      label: 'Mapple',
      buildMovieUri: _mappleMovie,
      buildShowUri: _showUnsupported,
      buildEpisodeUri: _mappleEpisode,
    ),
    ProviderDescriptor(
      canonicalIndex: 9,
      key: 'primesrc',
      label: 'PrimeSRC',
      buildMovieUri: _primeSrcMovie,
      buildShowUri: _showUnsupported,
      buildEpisodeUri: _primeSrcEpisode,
    ),
    ProviderDescriptor(
      canonicalIndex: 10,
      key: 'multiembed',
      label: 'MultiEmbed',
      buildMovieUri: _multiEmbedMovie,
      buildShowUri: _multiEmbedShow,
      buildEpisodeUri: _multiEmbedEpisode,
    ),
    ProviderDescriptor(
      canonicalIndex: 11,
      key: 'autoembed',
      label: 'AutoEmbed',
      buildMovieUri: _autoEmbedMovie,
      buildShowUri: _showUnsupported,
      buildEpisodeUri: _autoEmbedEpisode,
    ),
    ProviderDescriptor(
      canonicalIndex: 12,
      key: 'embedsu',
      label: 'Embed.su',
      buildMovieUri: _embedSuMovie,
      buildShowUri: _embedSuShow,
      buildEpisodeUri: _embedSuEpisode,
    ),
    ProviderDescriptor(
      canonicalIndex: 13,
      key: 'vsembed',
      label: 'VSEmbed',
      buildMovieUri: _vsEmbedMovie,
      buildShowUri: _vsEmbedShow,
      buildEpisodeUri: _vsEmbedEpisode,
    ),
    ProviderDescriptor(
      canonicalIndex: 14,
      key: 'vsrcsu',
      label: 'VSrc.su',
      buildMovieUri: _vsrcSuMovie,
      buildShowUri: _vsrcSuShow,
      buildEpisodeUri: _vsrcSuEpisode,
    ),
    ProviderDescriptor(
      canonicalIndex: 15,
      key: 'vidsrcme',
      label: 'VidSrc.me',
      buildMovieUri: _vidsrcMeMovie,
      buildShowUri: _vidsrcMeShow,
      buildEpisodeUri: _vidsrcMeEpisode,
    ),
    ProviderDescriptor(
      canonicalIndex: 16,
      key: 'hdrezka',
      label: 'HDRezka',
      buildMovieUri: _hdRezkaMovie,
      buildShowUri: _hdRezkaShow,
      buildEpisodeUri: _hdRezkaEpisode,
    ),
  ];

  List<ProviderDescriptor> orderedProviders(ProviderConfig config) {
    final disabledKeys = config.disabledProviders;
    final byKey = <String, ProviderDescriptor>{
      for (final provider in _defaultProviders) provider.key: provider,
    };
    final ordered = <ProviderDescriptor>[];
    final seenKeys = <String>{};

    for (final key in config.providerPriority) {
      final provider = byKey[key];
      if (provider == null ||
          disabledKeys.contains(key) ||
          seenKeys.contains(key)) {
        continue;
      }
      ordered.add(provider);
      seenKeys.add(key);
    }

    for (final provider in _defaultProviders) {
      if (disabledKeys.contains(provider.key) ||
          seenKeys.contains(provider.key)) {
        continue;
      }
      ordered.add(provider);
    }

    return ordered;
  }

  List<ProviderDescriptor> get defaultProviders =>
      List<ProviderDescriptor>.unmodifiable(_defaultProviders);

  static Uri? buildUri({
    required ProviderDescriptor provider,
    required int tmdbId,
    required String mediaType,
    required ProfilePlaybackSettings settings,
    int? seasonNumber,
    int? episodeNumber,
  }) {
    if (mediaType == 'movie') {
      return provider.buildMovieUri(tmdbId, settings);
    }

    if (mediaType != 'tv') {
      return null;
    }

    if (seasonNumber != null && episodeNumber != null) {
      return provider.buildEpisodeUri(
        tmdbId,
        seasonNumber,
        episodeNumber,
        settings,
      );
    }

    return provider.buildShowUri(tmdbId, settings);
  }

  static Uri _vidLinkMovie(int tmdbId, ProfilePlaybackSettings settings) =>
      Uri.parse('https://vidlink.pro/movie/$tmdbId');
  static Uri? _vidLinkEpisode(
    int tmdbId,
    int season,
    int episode,
    ProfilePlaybackSettings settings,
  ) =>
      Uri.parse('https://vidlink.pro/tv/$tmdbId/$season/$episode');
  static Uri _vidsrcEmbedMovie(int tmdbId, ProfilePlaybackSettings settings) =>
      Uri.https(
        'vidsrc-embed.ru',
        '/embed/movie',
        _mergeQuery(
          <String, String>{
            'tmdb': '$tmdbId',
            'autoplay': '1',
            'mute': '1',
          },
          settings: settings,
        ),
      );
  static Uri? _vidsrcEmbedShow(int tmdbId, ProfilePlaybackSettings settings) =>
      Uri.https(
        'vidsrc-embed.ru',
        '/embed/tv',
        _mergeQuery(<String, String>{'tmdb': '$tmdbId'}, settings: settings),
      );
  static Uri? _vidsrcEmbedEpisode(
    int tmdbId,
    int season,
    int episode,
    ProfilePlaybackSettings settings,
  ) =>
      Uri.https(
        'vidsrc-embed.ru',
        '/embed/tv',
        _mergeQuery(
          <String, String>{
            'tmdb': '$tmdbId',
            'season': '$season',
            'episode': '$episode',
            'autoplay': '1',
            'autonext': '1',
            'mute': '1',
          },
          settings: settings,
        ),
      );
  static Uri _vidEasyMovie(int tmdbId, ProfilePlaybackSettings settings) =>
      Uri.parse('https://vidembed.cc/movie/$tmdbId');
  static Uri? _vidEasyEpisode(
    int tmdbId,
    int season,
    int episode,
    ProfilePlaybackSettings settings,
  ) =>
      Uri.parse('https://vidembed.cc/episode/$tmdbId-$season-$episode');
  static Uri _oneElevenMoviesMovie(
    int tmdbId,
    ProfilePlaybackSettings settings,
  ) =>
      Uri.parse('https://111movies.net/movie/$tmdbId');
  static Uri? _oneElevenMoviesEpisode(
    int tmdbId,
    int season,
    int episode,
    ProfilePlaybackSettings settings,
  ) =>
      Uri.parse('https://111movies.net/tv/$tmdbId/$season/$episode');
  static Uri _vidzeeMovie(int tmdbId, ProfilePlaybackSettings settings) =>
      Uri.parse('https://vidzee.wtf/movie/$tmdbId');
  static Uri? _vidzeeEpisode(
    int tmdbId,
    int season,
    int episode,
    ProfilePlaybackSettings settings,
  ) =>
      Uri.parse('https://vidzee.wtf/tv/$tmdbId/$season/$episode');
  static Uri _vidsrcMovie(int tmdbId, ProfilePlaybackSettings settings) =>
      Uri.https(
        'vidsrc.to',
        '/embed/movie/$tmdbId',
        const <String, String>{
          'autoplay': '1',
          'mute': '1',
        },
      );
  static Uri? _vidsrcEpisode(
    int tmdbId,
    int season,
    int episode,
    ProfilePlaybackSettings settings,
  ) =>
      Uri.https(
        'vidsrc.to',
        '/embed/tv/$tmdbId/$season/$episode',
        const <String, String>{
          'autoplay': '1',
          'autonext': '1',
          'mute': '1',
        },
      );
  static Uri _twoEmbedMovie(int tmdbId, ProfilePlaybackSettings settings) =>
      Uri.parse('https://2embed.cc/embed/$tmdbId');
  static Uri? _twoEmbedEpisode(
    int tmdbId,
    int season,
    int episode,
    ProfilePlaybackSettings settings,
  ) =>
      Uri.parse('https://2embed.cc/embedtv/$tmdbId&s=$season&e=$episode');
  static Uri _mappleMovie(int tmdbId, ProfilePlaybackSettings settings) =>
      Uri.parse('https://maplestage.com/movie/$tmdbId');
  static Uri? _mappleEpisode(
    int tmdbId,
    int season,
    int episode,
    ProfilePlaybackSettings settings,
  ) =>
      Uri.parse('https://maplestage.com/tv/$tmdbId/$season/$episode');
  static Uri _primeSrcMovie(int tmdbId, ProfilePlaybackSettings settings) =>
      Uri.https(
        'primewire.tf',
        '/embed/movie',
        <String, String>{'tmdb': '$tmdbId'},
      );
  static Uri? _primeSrcEpisode(
    int tmdbId,
    int season,
    int episode,
    ProfilePlaybackSettings settings,
  ) =>
      Uri.https(
        'primewire.tf',
        '/embed/tv',
        <String, String>{
          'tmdb': '$tmdbId',
          's': '$season',
          'e': '$episode',
        },
      );
  static Uri _multiEmbedMovie(int tmdbId, ProfilePlaybackSettings settings) =>
      Uri.https(
        'multiembed.mov',
        '/',
        <String, String>{
          'video_id': '$tmdbId',
          'tmdb': '1',
        },
      );
  static Uri? _multiEmbedShow(int tmdbId, ProfilePlaybackSettings settings) =>
      Uri.https(
        'multiembed.mov',
        '/',
        <String, String>{
          'video_id': '$tmdbId',
          'tmdb': '1',
        },
      );
  static Uri? _multiEmbedEpisode(
    int tmdbId,
    int season,
    int episode,
    ProfilePlaybackSettings settings,
  ) =>
      Uri.https(
        'multiembed.mov',
        '/',
        <String, String>{
          'video_id': '$tmdbId',
          'tmdb': '1',
          's': '$season',
          'e': '$episode',
        },
      );
  static Uri _autoEmbedMovie(int tmdbId, ProfilePlaybackSettings settings) =>
      Uri.parse('https://autoembed.co/embed/movie/$tmdbId');
  static Uri? _autoEmbedEpisode(
    int tmdbId,
    int season,
    int episode,
    ProfilePlaybackSettings settings,
  ) =>
      Uri.parse('https://autoembed.co/embed/tv/$tmdbId/$season/$episode');
  static Uri _embedSuMovie(int tmdbId, ProfilePlaybackSettings settings) =>
      _routedEmbedMovie('embed.su', tmdbId);
  static Uri? _embedSuShow(int tmdbId, ProfilePlaybackSettings settings) =>
      _routedEmbedShow('embed.su', tmdbId);
  static Uri? _embedSuEpisode(
    int tmdbId,
    int season,
    int episode,
    ProfilePlaybackSettings settings,
  ) =>
      _routedEmbedEpisode('embed.su', tmdbId, season, episode);
  static Uri _vsEmbedMovie(int tmdbId, ProfilePlaybackSettings settings) =>
      _routedEmbedMovie('vsembed.ru', tmdbId);
  static Uri? _vsEmbedShow(int tmdbId, ProfilePlaybackSettings settings) =>
      _routedEmbedShow('vsembed.ru', tmdbId);
  static Uri? _vsEmbedEpisode(
    int tmdbId,
    int season,
    int episode,
    ProfilePlaybackSettings settings,
  ) =>
      _routedEmbedEpisode('vsembed.ru', tmdbId, season, episode);
  static Uri _vsrcSuMovie(int tmdbId, ProfilePlaybackSettings settings) =>
      _routedEmbedMovie('vsrc.su', tmdbId);
  static Uri? _vsrcSuShow(int tmdbId, ProfilePlaybackSettings settings) =>
      _routedEmbedShow('vsrc.su', tmdbId);
  static Uri? _vsrcSuEpisode(
    int tmdbId,
    int season,
    int episode,
    ProfilePlaybackSettings settings,
  ) =>
      _routedEmbedEpisode('vsrc.su', tmdbId, season, episode);
  static Uri _vidsrcMeMovie(int tmdbId, ProfilePlaybackSettings settings) =>
      _routedEmbedMovie('vidsrc.me', tmdbId);
  static Uri? _vidsrcMeShow(int tmdbId, ProfilePlaybackSettings settings) =>
      _routedEmbedShow('vidsrc.me', tmdbId);
  static Uri? _vidsrcMeEpisode(
    int tmdbId,
    int season,
    int episode,
    ProfilePlaybackSettings settings,
  ) =>
      _routedEmbedEpisode('vidsrc.me', tmdbId, season, episode);
  static Uri _hdRezkaMovie(int tmdbId, ProfilePlaybackSettings settings) =>
      Uri.https('hdrezka.ag', '/');
  static Uri? _hdRezkaShow(int tmdbId, ProfilePlaybackSettings settings) =>
      Uri.https('hdrezka.ag', '/');
  static Uri? _hdRezkaEpisode(
    int tmdbId,
    int season,
    int episode,
    ProfilePlaybackSettings settings,
  ) =>
      Uri.https('hdrezka.ag', '/');
  static Uri? _showUnsupported(int tmdbId, ProfilePlaybackSettings settings) =>
      null;

  static Uri _routedEmbedMovie(String host, int tmdbId) => Uri.https(
        host,
        '/embed/movie/$tmdbId',
        const <String, String>{
          'autoplay': '1',
          'mute': '1',
        },
      );

  static Uri _routedEmbedShow(String host, int tmdbId) => Uri.https(
        host,
        '/embed/tv/$tmdbId',
        const <String, String>{'autoplay': '1'},
      );

  static Uri _routedEmbedEpisode(
    String host,
    int tmdbId,
    int season,
    int episode,
  ) =>
      Uri.https(
        host,
        '/embed/tv/$tmdbId/$season/$episode',
        const <String, String>{
          'autoplay': '1',
          'autonext': '1',
          'mute': '1',
        },
      );

  static Map<String, String> _mergeQuery(
    Map<String, String> query, {
    required ProfilePlaybackSettings settings,
  }) {
    final merged = <String, String>{...query};
    if (settings.preferredAudioLanguageCode.isNotEmpty) {
      merged['ds_lang'] = settings.preferredAudioLanguageCode;
    }
    if (settings.subtitleUrl != null && settings.subtitleUrl!.isNotEmpty) {
      merged['sub_url'] = settings.subtitleUrl!;
    }
    return merged;
  }
}

class ProviderDescriptor {
  const ProviderDescriptor({
    required this.canonicalIndex,
    required this.key,
    required this.label,
    required this.buildMovieUri,
    required this.buildShowUri,
    required this.buildEpisodeUri,
    this.probeAttempts = 1,
    this.probeTimeoutSeconds,
  });

  final int canonicalIndex;
  final String key;
  final String label;
  final Uri Function(int tmdbId, ProfilePlaybackSettings settings)
      buildMovieUri;
  final Uri? Function(int tmdbId, ProfilePlaybackSettings settings)
      buildShowUri;
  final Uri? Function(
          int tmdbId, int season, int episode, ProfilePlaybackSettings settings)
      buildEpisodeUri;
  final int probeAttempts;
  final int? probeTimeoutSeconds;
}
