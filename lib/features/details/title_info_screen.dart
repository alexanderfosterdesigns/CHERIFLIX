import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/media_summary.dart';
import '../../core/models/media_type.dart';
import '../../core/models/title_metadata.dart';
import '../../core/services/media_catalog_service.dart';
import '../../core/services/tmdb_media_catalog_service.dart';
import '../../core/services/tmdb_image_service.dart';
import '../../core/theme/cheriflix_theme.dart';
import '../../core/widgets/cheriflix_chrome.dart';
import '../../core/widgets/cheriflix_network_image.dart';
import '../../core/widgets/tv_shortcuts.dart';

class TitleInfoScreen extends StatefulWidget {
  const TitleInfoScreen({
    super.key,
    required this.summary,
    required this.languageCode,
    required this.onBack,
    this.mediaCatalogService,
  });

  final MediaSummary summary;
  final String languageCode;
  final VoidCallback onBack;
  final MediaCatalogService? mediaCatalogService;

  @override
  State<TitleInfoScreen> createState() => _TitleInfoScreenState();
}

enum _TitleInfoBreakpoint {
  compact,
  standard,
  wide,
}

class _TitleInfoLayoutConfig {
  const _TitleInfoLayoutConfig({
    required this.breakpoint,
    required this.shellPadding,
    required this.heroTitleFontSize,
    required this.headerTopSpacing,
    required this.headerToMetadataSpacing,
    required this.metadataToContentSpacing,
    required this.sectionSpacing,
    required this.headerMaxWidth,
    required this.contentMaxWidth,
    required this.scrollRightPadding,
  });

  final _TitleInfoBreakpoint breakpoint;
  final EdgeInsets shellPadding;
  final double heroTitleFontSize;
  final double headerTopSpacing;
  final double headerToMetadataSpacing;
  final double metadataToContentSpacing;
  final double sectionSpacing;
  final double headerMaxWidth;
  final double contentMaxWidth;
  final double scrollRightPadding;

  bool get isCompact => breakpoint == _TitleInfoBreakpoint.compact;

  static _TitleInfoLayoutConfig fromWidth(double width) {
    final resolvedWidth = width.isFinite && width > 0 ? width : 1280;
    if (resolvedWidth < 1100) {
      return const _TitleInfoLayoutConfig(
        breakpoint: _TitleInfoBreakpoint.compact,
        shellPadding: EdgeInsets.fromLTRB(20, 18, 20, 18),
        heroTitleFontSize: 34,
        headerTopSpacing: 8,
        headerToMetadataSpacing: 14,
        metadataToContentSpacing: 18,
        sectionSpacing: 18,
        headerMaxWidth: 980,
        contentMaxWidth: 980,
        scrollRightPadding: 4,
      );
    }
    if (resolvedWidth < 1600) {
      return const _TitleInfoLayoutConfig(
        breakpoint: _TitleInfoBreakpoint.standard,
        shellPadding: EdgeInsets.fromLTRB(32, 24, 32, 24),
        heroTitleFontSize: 40,
        headerTopSpacing: 14,
        headerToMetadataSpacing: 18,
        metadataToContentSpacing: 22,
        sectionSpacing: 22,
        headerMaxWidth: 1180,
        contentMaxWidth: 1280,
        scrollRightPadding: 10,
      );
    }
    return const _TitleInfoLayoutConfig(
      breakpoint: _TitleInfoBreakpoint.wide,
      shellPadding: EdgeInsets.fromLTRB(42, 28, 42, 28),
      heroTitleFontSize: 44,
      headerTopSpacing: 16,
      headerToMetadataSpacing: 20,
      metadataToContentSpacing: 24,
      sectionSpacing: 24,
      headerMaxWidth: 1280,
      contentMaxWidth: 1380,
      scrollRightPadding: 12,
    );
  }
}

class _TitleInfoScreenState extends State<TitleInfoScreen> {
  late MediaSummary _summary = widget.summary;
  TitleMetadata? _metadata;
  bool _loading = true;
  String? _notice;
  late final ScrollController _scrollController = ScrollController();
  late final FocusNode _scrollFocusNode =
      FocusNode(debugLabel: 'TitleInfoScroll');

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  @override
  void didUpdateWidget(covariant TitleInfoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.summary.saveKey != widget.summary.saveKey ||
        oldWidget.languageCode != widget.languageCode ||
        oldWidget.mediaCatalogService != widget.mediaCatalogService) {
      _summary = widget.summary;
      _metadata = null;
      _loading = true;
      _notice = null;
      _loadMetadata();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _scrollFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TvShortcutScope(
      onBack: widget.onBack,
      child: CheriflixScaffold(
        topBar: null,
        useSafeArea: false,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final metadata = _effectiveMetadata;
            final layout = _TitleInfoLayoutConfig.fromWidth(
              constraints.maxWidth,
            );
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _InfoBackdrop(imageUrl: _summary.backdropUrl),
                const Positioned.fill(child: _InfoBackdropScrim()),
                SafeArea(
                  child: Padding(
                    padding: layout.shellPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(height: layout.headerTopSpacing),
                        const Text(
                          'DETAILS',
                          style: CheriflixTypography.overline,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _summary.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: CheriflixTypography.heroTitle.copyWith(
                            fontSize: layout.heroTitleFontSize,
                          ),
                        ),
                        SizedBox(height: layout.headerToMetadataSpacing),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: layout.headerMaxWidth,
                          ),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: <Widget>[
                              _InfoBadge(label: _summary.mediaLabel),
                              if (_summary.rating != null)
                                _InfoBadge(
                                  label:
                                      'TMDb ${_summary.rating!.toStringAsFixed(1)}',
                                ),
                              if (_summary.releaseDate != null)
                                _InfoBadge(
                                  label: _fullDateLabel(_summary.releaseDate!),
                                ),
                              if (metadata.certification?.trim().isNotEmpty ==
                                  true)
                                _InfoBadge(
                                    label: metadata.certification!.trim()),
                              if (_summary.runtimeLabel != null)
                                _InfoBadge(label: _summary.runtimeLabel!),
                              if (_summary.seasonLabel != null)
                                _InfoBadge(label: _summary.seasonLabel!),
                            ],
                          ),
                        ),
                        SizedBox(height: layout.metadataToContentSpacing),
                        Expanded(
                          child: Focus(
                            autofocus: true,
                            focusNode: _scrollFocusNode,
                            onKeyEvent: _handleScrollKeyEvent,
                            child: SingleChildScrollView(
                              controller: _scrollController,
                              padding: EdgeInsets.only(
                                right: layout.scrollRightPadding,
                                bottom: 32,
                              ),
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: layout.contentMaxWidth,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      if (_loading)
                                        const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 40,
                                          ),
                                          child: Center(
                                            child: CircularProgressIndicator(),
                                          ),
                                        )
                                      else ...<Widget>[
                                        if (_notice != null) ...<Widget>[
                                          _InfoNoticeBanner(message: _notice!),
                                          SizedBox(
                                            height: layout.sectionSpacing,
                                          ),
                                        ],
                                        _buildAboutPanel(
                                          metadata,
                                          layout: layout,
                                        ),
                                        SizedBox(height: layout.sectionSpacing),
                                        _buildCastPanel(
                                          metadata,
                                          layout: layout,
                                        ),
                                        SizedBox(height: layout.sectionSpacing),
                                        _buildPeoplePanel(
                                          metadata,
                                          layout: layout,
                                        ),
                                        SizedBox(height: layout.sectionSpacing),
                                        _buildFactsPanel(
                                          metadata,
                                          layout: layout,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAboutPanel(
    TitleMetadata metadata, {
    required _TitleInfoLayoutConfig layout,
  }) {
    final overview = _summary.overview?.trim();
    return _InfoSectionShell(
      title: 'About',
      subtitle: metadata.tagline?.trim().isNotEmpty == true
          ? metadata.tagline!.trim()
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            overview?.isNotEmpty == true
                ? overview!
                : 'No synopsis is available for this title yet.',
            style: CheriflixTypography.body.copyWith(
              color: const Color(0xE6FFFFFF),
              fontSize: layout.isCompact ? 15 : 16,
            ),
          ),
          if (metadata.genres.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                for (final genre in metadata.genres.take(6))
                  _InfoBadge(label: genre),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFactsPanel(
    TitleMetadata metadata, {
    required _TitleInfoLayoutConfig layout,
  }) {
    final facts = _quickFacts(metadata);
    return _InfoSectionShell(
      title: 'Quick Facts',
      subtitle: 'Supporting production and release details',
      compact: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final spacing = layout.isCompact ? 10.0 : 12.0;
          final columns = _factColumnCountForWidth(constraints.maxWidth);
          final tileWidth = _gridItemWidth(
            maxWidth: constraints.maxWidth,
            columns: columns,
            spacing: spacing,
            maxWidthCap: 260,
          );
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: <Widget>[
              for (final fact in facts)
                SizedBox(
                  width: tileWidth,
                  child: _CompactFactTile(item: fact),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPeoplePanel(
    TitleMetadata metadata, {
    required _TitleInfoLayoutConfig layout,
  }) {
    return _InfoSectionShell(
      title: 'Creative Team',
      subtitle: 'The people shaping this story',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LayoutBuilder(
            builder: (context, constraints) {
              final spacing = layout.isCompact ? 14.0 : 18.0;
              final columns = _peopleColumnCountForWidth(constraints.maxWidth);
              final cardWidth = _gridItemWidth(
                maxWidth: constraints.maxWidth,
                columns: columns,
                spacing: spacing,
                maxWidthCap: 360,
              );
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: <Widget>[
                  SizedBox(
                    width: cardWidth,
                    child: _PeopleGroupCard(
                      title: _summary.mediaType == MediaType.tv
                          ? 'Created by'
                          : 'Directed by',
                      items: metadata.creators,
                      emptyLabel: _summary.mediaType == MediaType.tv
                          ? 'Creator information is unavailable right now.'
                          : 'Director information is unavailable right now.',
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _PeopleGroupCard(
                      title: 'Writers',
                      items: metadata.writers,
                      emptyLabel:
                          'Writer information is unavailable right now.',
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          _CrewSection(
            title: 'Key Crew',
            credits: metadata.crew,
          ),
        ],
      ),
    );
  }

  Widget _buildCastPanel(
    TitleMetadata metadata, {
    required _TitleInfoLayoutConfig layout,
  }) {
    return _InfoSectionShell(
      title: 'Featured Cast',
      subtitle: 'The performers leading the story',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (metadata.cast.isEmpty)
            const Text(
              'Cast information is unavailable right now.',
              style: CheriflixTypography.body,
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final spacing = layout.isCompact ? 12.0 : 16.0;
                final credits = metadata.cast.take(12).toList(growable: false);
                final columns = _castColumnCountForWidth(constraints.maxWidth);
                final cardWidth = _gridItemWidth(
                  maxWidth: constraints.maxWidth,
                  columns: columns,
                  spacing: spacing,
                  maxWidthCap: 236,
                );
                return Wrap(
                  key: const ValueKey<String>('title_info_cast_grid'),
                  spacing: spacing,
                  runSpacing: spacing,
                  children: <Widget>[
                    for (var index = 0; index < credits.length; index += 1)
                      SizedBox(
                        key: ValueKey<String>('title_info_cast_card_$index'),
                        width: cardWidth,
                        child: _CastCard(
                          credit: credits[index],
                          width: cardWidth,
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  int _castColumnCountForWidth(double maxWidth) {
    if (!maxWidth.isFinite) {
      return 4;
    }
    if (maxWidth >= 914) {
      return 5;
    }
    if (maxWidth >= 728) {
      return 4;
    }
    if (maxWidth >= 542) {
      return 3;
    }
    if (maxWidth >= 356) {
      return 2;
    }
    return 1;
  }

  int _peopleColumnCountForWidth(double maxWidth) {
    if (!maxWidth.isFinite) {
      return 2;
    }
    return maxWidth >= 538 ? 2 : 1;
  }

  int _factColumnCountForWidth(double maxWidth) {
    if (!maxWidth.isFinite) {
      return 4;
    }
    if (maxWidth >= 676) {
      return 4;
    }
    if (maxWidth >= 504) {
      return 3;
    }
    if (maxWidth >= 332) {
      return 2;
    }
    return 1;
  }

  double _gridItemWidth({
    required double maxWidth,
    required int columns,
    required double spacing,
    required double maxWidthCap,
  }) {
    final safeColumns = columns < 1 ? 1 : columns;
    final safeWidth =
        maxWidth.isFinite && maxWidth > 0 ? maxWidth : maxWidthCap;
    final totalSpacing = spacing * (safeColumns - 1);
    final rawWidth = (safeWidth - totalSpacing) / safeColumns;
    if (!rawWidth.isFinite || rawWidth <= 0) {
      return maxWidthCap;
    }
    return rawWidth > maxWidthCap ? maxWidthCap : rawWidth;
  }

  List<_InfoFactItem> _quickFacts(TitleMetadata metadata) {
    final items = <_InfoFactItem>[
      _InfoFactItem(
        label: 'Type',
        value: _summary.mediaType == MediaType.movie ? 'Movie' : 'TV Show',
      ),
      _InfoFactItem(
        label: 'Release',
        value: _summary.releaseDate == null
            ? 'Unknown'
            : _fullDateLabel(_summary.releaseDate!),
      ),
      _InfoFactItem(
        label: 'Rating',
        value: _summary.rating == null
            ? 'Unavailable'
            : _summary.rating!.toStringAsFixed(1),
      ),
      _InfoFactItem(
        label: 'Certification',
        value: metadata.certification?.trim().isNotEmpty == true
            ? metadata.certification!.trim()
            : 'Not rated',
      ),
    ];

    if (_summary.runtimeLabel != null) {
      items.add(_InfoFactItem(label: 'Runtime', value: _summary.runtimeLabel!));
    }
    if (_summary.seasonLabel != null) {
      items.add(_InfoFactItem(label: 'Seasons', value: _summary.seasonLabel!));
    }
    if (metadata.status?.trim().isNotEmpty == true) {
      items.add(_InfoFactItem(label: 'Status', value: metadata.status!));
    }
    if (metadata.originalTitle?.trim().isNotEmpty == true) {
      items.add(
        _InfoFactItem(label: 'Original Title', value: metadata.originalTitle!),
      );
    }
    if (metadata.originalLanguage?.trim().isNotEmpty == true) {
      items.add(
        _InfoFactItem(
          label: 'Original Language',
          value: metadata.originalLanguage!.toUpperCase(),
        ),
      );
    }
    if (_summary.collectionName?.trim().isNotEmpty == true) {
      items.add(
        _InfoFactItem(label: 'Collection', value: _summary.collectionName!),
      );
    }
    if (metadata.studios.isNotEmpty) {
      items.add(
        _InfoFactItem(label: 'Studios', value: metadata.studios.join(', ')),
      );
    }
    if (metadata.networks.isNotEmpty) {
      items.add(
        _InfoFactItem(label: 'Networks', value: metadata.networks.join(', ')),
      );
    }
    if (metadata.spokenLanguages.isNotEmpty) {
      items.add(
        _InfoFactItem(
          label: 'Languages',
          value: metadata.spokenLanguages.join(', '),
        ),
      );
    }
    if (metadata.originCountries.isNotEmpty) {
      items.add(
        _InfoFactItem(
          label: 'Countries',
          value: metadata.originCountries.join(', '),
        ),
      );
    }
    if (metadata.homepage?.trim().isNotEmpty == true) {
      items.add(_InfoFactItem(label: 'Homepage', value: metadata.homepage!));
    }

    return items;
  }

  Future<void> _loadMetadata() async {
    final catalogService = _tmdbCatalogService;
    if (catalogService == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _notice =
            'Live cast and production details are unavailable until CHERIFLIX is connected to TMDb metadata.';
      });
      return;
    }

    try {
      final metadata = await catalogService.fetchTitleMetadata(
        tmdbId: widget.summary.tmdbId,
        mediaType: widget.summary.mediaType,
        languageCode: widget.languageCode,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _metadata = metadata;
        _summary = metadata.summary;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _notice =
            'Some live title details could not be loaded right now. Showing the information CHERIFLIX already has cached for this title.';
      });
    }
  }

  KeyEventResult _handleScrollKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !_scrollController.hasClients) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _nudgeScroll(180);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _nudgeScroll(-180);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      _nudgeScroll(420);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      _nudgeScroll(-420);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _nudgeScroll(double delta) {
    final position = _scrollController.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  TitleMetadata get _effectiveMetadata {
    return _metadata ??
        TitleMetadata(
          summary: _summary,
          genres: _summary.genreNames,
        );
  }

  TmdbMediaCatalogService? get _tmdbCatalogService {
    final service = widget.mediaCatalogService;
    if (service is TmdbMediaCatalogService) {
      return service;
    }
    return null;
  }
}

class _InfoBackdrop extends StatelessWidget {
  const _InfoBackdrop({
    required this.imageUrl,
  });

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final size = MediaQuery.sizeOf(context);
    return CheriflixNetworkImage(
      imageUrl: imageUrl,
      width: size.width,
      height: size.height,
      devicePixelRatio: devicePixelRatio,
      preset: TmdbImagePreset.heroBackdrop,
      maxDecodePixels: 1600,
      placeholderColor: CheriflixColors.background,
    );
  }
}

class _InfoBackdropScrim extends StatelessWidget {
  const _InfoBackdropScrim();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xEE111111),
            Color(0xD6141414),
            Color(0xF3141414),
          ],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: <Color>[
              Color(0xC8141414),
              Color(0x8A141414),
              Color(0x40141414),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xC8171717),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x26FFFFFF)),
      ),
      child: Text(
        label,
        style: CheriflixTypography.metadata.copyWith(
          color: CheriflixColors.textPrimary,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _InfoNoticeBanner extends StatelessWidget {
  const _InfoNoticeBanner({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xB01A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x18FFFFFF)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Text(
          message,
          style: CheriflixTypography.body.copyWith(
            color: Color(0xE6FFFFFF),
          ),
        ),
      ),
    );
  }
}

class _InfoSectionShell extends StatelessWidget {
  const _InfoSectionShell({
    required this.title,
    required this.child,
    this.subtitle,
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final bool compact;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = compact ? 22.0 : 28.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compressed = constraints.maxWidth < 860;
        final horizontalPadding =
            compact ? (compressed ? 16.0 : 20.0) : (compressed ? 20.0 : 28.0);
        final topPadding =
            compact ? (compressed ? 16.0 : 18.0) : (compressed ? 20.0 : 24.0);
        final bottomPadding =
            compact ? (compressed ? 16.0 : 20.0) : (compressed ? 20.0 : 24.0);
        final subtitleColor =
            compact ? CheriflixColors.textSecondary : const Color(0xF0FFFFFF);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: const Color(0x18FFFFFF)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: compact
                  ? const <Color>[
                      Color(0xC8181818),
                      Color(0xAA141414),
                    ]
                  : const <Color>[
                      Color(0xD81B1B1B),
                      Color(0xB0141414),
                      Color(0x92101010),
                    ],
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 20,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              topPadding,
              horizontalPadding,
              bottomPadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: CheriflixTypography.sectionTitle.copyWith(
                    fontSize: compact ? 20 : 22,
                  ),
                ),
                if (subtitle?.trim().isNotEmpty == true) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    subtitle!.trim(),
                    style: CheriflixTypography.bodyMedium.copyWith(
                      color: subtitleColor,
                      fontSize: compact ? 15 : 16,
                    ),
                  ),
                ],
                SizedBox(height: compact ? 16 : 18),
                child,
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PeopleGroupCard extends StatelessWidget {
  const _PeopleGroupCard({
    required this.title,
    required this.items,
    required this.emptyLabel,
  });

  final String title;
  final List<String> items;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0x6E202020),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: CheriflixTypography.cardTitle,
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Text(
              emptyLabel,
              style: CheriflixTypography.body.copyWith(
                color: CheriflixColors.textSecondary,
              ),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                for (final item in items.take(6)) _InfoBadge(label: item),
              ],
            ),
        ],
      ),
    );
  }
}

class _CrewSection extends StatelessWidget {
  const _CrewSection({
    required this.title,
    required this.credits,
  });

  final String title;
  final List<TitleCredit> credits;

  @override
  Widget build(BuildContext context) {
    if (credits.isEmpty) {
      return const Text(
        'Additional crew information is unavailable right now.',
        style: CheriflixTypography.body,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: CheriflixTypography.cardTitle,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: <Widget>[
            for (final credit in credits.take(10))
              _CrewCreditTile(credit: credit),
          ],
        ),
      ],
    );
  }
}

class _CrewCreditTile extends StatelessWidget {
  const _CrewCreditTile({
    required this.credit,
  });

  final TitleCredit credit;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0x7A202020),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x16FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            credit.name,
            style: CheriflixTypography.cardTitle.copyWith(fontSize: 15),
          ),
          if (credit.role.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              credit.role,
              style: CheriflixTypography.metadata.copyWith(fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

class _CastCard extends StatelessWidget {
  const _CastCard({
    required this.credit,
    required this.width,
  });

  final TitleCredit credit;
  final double width;

  @override
  Widget build(BuildContext context) {
    const imageHeightRatio = 248 / 206;
    final cardWidth = width;
    final imageHeight = cardWidth * imageHeightRatio;
    final iconSize = (cardWidth * 0.26).clamp(38.0, 54.0);
    final devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return SizedBox(
      width: cardWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xC81A1A1A),
              Color(0xB2151515),
            ],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0x16FFFFFF)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x6A000000),
              blurRadius: 18,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(21),
              ),
              child: SizedBox(
                width: cardWidth,
                height: imageHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    CheriflixNetworkImage(
                      imageUrl: credit.profileUrl,
                      width: cardWidth,
                      height: imageHeight,
                      devicePixelRatio: devicePixelRatio,
                      preset: TmdbImagePreset.castProfile,
                      maxDecodePixels: 768,
                      placeholderColor: const Color(0xFF101010),
                    ),
                    if (credit.profileUrl == null)
                      Center(
                        child: Icon(
                          Icons.person_rounded,
                          size: iconSize,
                          color: const Color(0x80FFFFFF),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    credit.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: CheriflixTypography.cardTitle.copyWith(fontSize: 17),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    credit.role.trim().isNotEmpty ? credit.role : 'Cast member',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: CheriflixTypography.metadata,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactFactTile extends StatelessWidget {
  const _CompactFactTile({
    required this.item,
  });

  final _InfoFactItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0x7C1B1B1B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            item.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CheriflixTypography.metadata.copyWith(
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.value,
            style: CheriflixTypography.bodyMedium.copyWith(
              color: CheriflixColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoFactItem {
  const _InfoFactItem({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;
}

String _fullDateLabel(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$month/$day/${value.year}';
}
