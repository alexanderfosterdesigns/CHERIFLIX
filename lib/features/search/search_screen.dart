import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/media_summary.dart';
import '../../core/models/profile.dart';
import '../../core/services/media_catalog_service.dart';
import '../../core/services/tmdb_media_catalog_service.dart';
import '../../core/theme/cheriflix_theme.dart';
import '../../core/utils/user_facing_errors.dart';
import '../../core/widgets/cheriflix_chrome.dart';
import '../../core/widgets/tv_character_keyboard.dart';
import '../../core/widgets/tv_shortcuts.dart';

class _SearchResultGridMetrics {
  const _SearchResultGridMetrics({
    required this.preferredTileWidth,
    required this.posterAspectRatio,
    required this.detailsHeight,
    required this.gridSpacing,
  });

  final double preferredTileWidth;
  final double posterAspectRatio;
  final double detailsHeight;
  final double gridSpacing;

  double posterHeightForWidth(double cardWidth) =>
      cardWidth * posterAspectRatio;

  double tileExtentForWidth(double cardWidth) =>
      posterHeightForWidth(cardWidth) + detailsHeight;
}

class _SearchLayoutMetrics {
  const _SearchLayoutMetrics({
    required this.outerPadding,
    required this.leftPanelWidth,
    required this.panelGap,
    required this.leftPanelPadding,
    required this.resultsPanelPadding,
    required this.keyboardGap,
    required this.resultGrid,
  });

  final EdgeInsets outerPadding;
  final double leftPanelWidth;
  final double panelGap;
  final EdgeInsets leftPanelPadding;
  final EdgeInsets resultsPanelPadding;
  final double keyboardGap;
  final _SearchResultGridMetrics resultGrid;

  static _SearchLayoutMetrics forSize(Size size) {
    final width = size.width;
    final compactHeight = size.height < 560;
    final proportionalPanelWidth =
        width * (compactHeight ? 0.44 : 0.36);
    final responsivePanelWidth = proportionalPanelWidth
        .clamp(compactHeight ? 320.0 : 360.0, 680.0)
        .toDouble();
    if (width >= 1840) {
      return _SearchLayoutMetrics(
        outerPadding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
        leftPanelWidth: responsivePanelWidth,
        panelGap: 24,
        leftPanelPadding: const EdgeInsets.all(20),
        resultsPanelPadding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
        keyboardGap: 8,
        resultGrid: const _SearchResultGridMetrics(
          preferredTileWidth: 205,
          posterAspectRatio: 1.33,
          detailsHeight: 74,
          gridSpacing: 14,
        ),
      );
    }

    if (width >= 1520) {
      return _SearchLayoutMetrics(
        outerPadding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
        leftPanelWidth: responsivePanelWidth,
        panelGap: 22,
        leftPanelPadding: const EdgeInsets.all(19),
        resultsPanelPadding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
        keyboardGap: 8,
        resultGrid: const _SearchResultGridMetrics(
          preferredTileWidth: 185,
          posterAspectRatio: 1.33,
          detailsHeight: 72,
          gridSpacing: 13,
        ),
      );
    }

    if (width >= 1280) {
      return _SearchLayoutMetrics(
        outerPadding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
        leftPanelWidth: responsivePanelWidth,
        panelGap: 18,
        leftPanelPadding: const EdgeInsets.all(17),
        resultsPanelPadding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        keyboardGap: 7,
        resultGrid: const _SearchResultGridMetrics(
          preferredTileWidth: 190,
          posterAspectRatio: 1.32,
          detailsHeight: 68,
          gridSpacing: 12,
        ),
      );
    }

    return _SearchLayoutMetrics(
      outerPadding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      leftPanelWidth: responsivePanelWidth,
      panelGap: 14,
      leftPanelPadding: EdgeInsets.all(compactHeight ? 12 : 15),
      resultsPanelPadding: const EdgeInsets.fromLTRB(15, 16, 15, 16),
      keyboardGap: compactHeight ? 5 : 7,
      resultGrid: const _SearchResultGridMetrics(
        preferredTileWidth: 166,
        posterAspectRatio: 1.32,
        detailsHeight: 64,
        gridSpacing: 10,
      ),
    );
  }
}

class _ScoredFocusNode {
  const _ScoredFocusNode(this.node, this.score);

  final FocusNode node;
  final double score;
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.mediaCatalogService,
    required this.languageCode,
    this.muteAutoplayTrailers = true,
    required this.onBack,
    required this.onOpenTitle,
    this.onPlayTitle,
    this.activeProfile,
    this.savedTitleKeys = const <String>{},
    this.onToggleSaved,
    this.onBrowseHome,
    this.onBrowseTvShows,
    this.onBrowseMovies,
    this.onBrowseNewPopular,
    this.onBrowseMyList,
    this.onOpenSettings,
    this.onSwitchProfile,
  });

  final MediaCatalogService? mediaCatalogService;
  final String languageCode;
  final bool muteAutoplayTrailers;
  final VoidCallback onBack;
  final ValueChanged<MediaSummary> onOpenTitle;
  final ValueChanged<MediaSummary>? onPlayTitle;
  final Profile? activeProfile;
  final Set<String> savedTitleKeys;
  final ValueChanged<MediaSummary>? onToggleSaved;
  final VoidCallback? onBrowseHome;
  final VoidCallback? onBrowseTvShows;
  final VoidCallback? onBrowseMovies;
  final VoidCallback? onBrowseNewPopular;
  final VoidCallback? onBrowseMyList;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onSwitchProfile;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  Timer? _debounce;
  String _query = '';
  int _cursorIndex = 0;
  bool _loading = false;
  String? _error;
  List<MediaSummary> _results = const <MediaSummary>[];
  late final FocusNode _backButtonFocusNode =
      FocusNode(debugLabel: 'SearchBackToBrowse');
  late final FocusNode _firstKeyFocusNode =
      FocusNode(debugLabel: 'SearchFirstKey');
  late final List<List<FocusNode>> _keyboardFocusNodes =
      _buildKeyboardFocusNodes();
  final List<FocusNode> _resultFocusNodes = <FocusNode>[];
  FocusNode? _lastFocusedKeypadNode;

  @override
  void initState() {
    super.initState();
    _lastFocusedKeypadNode = _firstKeyFocusNode;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _backButtonFocusNode.dispose();
    _firstKeyFocusNode.dispose();
    _disposeKeyboardFocusNodes();
    _disposeResultFocusNodes();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The keyboard is laid out before the results panel. Seed the first result
    // node up front so bottom-row D-pad fallbacks are correct on the very first
    // frame that search results appear.
    if (_results.isNotEmpty && _resultFocusNodes.isEmpty) {
      _ensureResultFocusNodeForIndex(0);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _SearchLayoutMetrics.forSize(
          Size(constraints.maxWidth, constraints.maxHeight),
        );
        return TvShortcutScope(
          onBack: widget.onBack,
          child: CheriflixScaffold(
            topBar: CheriflixTopBar(
              profile: widget.activeProfile,
              downFallbackNodes: _topBarDownFallbackNodes,
              onHome: widget.onBrowseHome,
              onTvShows: widget.onBrowseTvShows,
              onMovies: widget.onBrowseMovies,
              onNewPopular: widget.onBrowseNewPopular,
              onMyList: widget.onBrowseMyList,
              onSettings: widget.onOpenSettings,
              onProfiles: widget.onSwitchProfile,
            ),
            body: Focus(
              onKeyEvent: _handleQueryKey,
              child: Stack(
                children: <Widget>[
                  Padding(
                    padding: layout.outerPadding,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(
                          width: layout.leftPanelWidth,
                          child: CheriflixPanel(
                            padding: layout.leftPanelPadding,
                            child: LayoutBuilder(
                              builder: (context, panelConstraints) =>
                                  _buildInsetSearchPanel(
                                layout,
                                panelConstraints,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: layout.panelGap),
                        Expanded(
                          child: CheriflixPanel(
                            padding: layout.resultsPanelPadding,
                            child: _buildResults(layout),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInsetSearchPanel(
    _SearchLayoutMetrics layout,
    BoxConstraints constraints,
  ) {
    final compactHeight = constraints.maxHeight < 560;
    final headerHeight = compactHeight ? 38.0 : 46.0;
    final queryHeight = compactHeight ? 48.0 : 58.0;
    final sectionGap = compactHeight ? 8.0 : 12.0;
    final rowGap = layout.keyboardGap;
    final rowCount = tvCharacterKeyboardRows.length;
    final availableKeyboardHeight = math.max(
      0,
      constraints.maxHeight -
          headerHeight -
          queryHeight -
          sectionGap * 2,
    );
    final fittedKeyHeight =
        (availableKeyboardHeight - rowGap * (rowCount - 1)) / rowCount;
    final keyHeight = fittedKeyHeight
        .clamp(18.0, compactHeight ? 40.0 : 54.0)
        .toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: headerHeight,
          child: Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'SEARCH',
                  style: CheriflixTypography.overline,
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.min(190, constraints.maxWidth * 0.58),
                ),
                child: SizedBox(
                  height: headerHeight,
                  child: TvActionButton(
                    label: 'Back to Browse',
                    onPressed: widget.onBack,
                    autofocus: true,
                    focusNode: _backButtonFocusNode,
                    downFallbackNodes: <FocusNode>[_firstKeyFocusNode],
                    compact: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    borderRadius: 14,
                    focusScale: 1.02,
                    variant: TvButtonVariant.ghost,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: sectionGap),
        SizedBox(
          height: queryHeight,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF101010),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x28FFFFFF)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compactHeight ? 14 : 18,
                vertical: compactHeight ? 10 : 14,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildQueryText(),
              ),
            ),
          ),
        ),
        SizedBox(height: sectionGap),
        for (var rowIndex = 0; rowIndex < rowCount; rowIndex += 1) ...<Widget>[
          SizedBox(
            height: keyHeight,
            child: Row(
              children: <Widget>[
                for (var columnIndex = 0;
                    columnIndex < tvCharacterKeyboardRows[rowIndex].length;
                    columnIndex += 1) ...<Widget>[
                  Expanded(
                    child: TvActionButton(
                      label: tvCharacterKeyboardRows[rowIndex][columnIndex],
                      onPressed: _keyboardActionFor(
                        tvCharacterKeyboardRows[rowIndex][columnIndex],
                      ),
                      compact: true,
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      labelStyle: CheriflixTypography.button.copyWith(
                        fontSize: compactHeight ? 11 : 14,
                        fontWeight: FontWeight.w700,
                      ),
                      borderRadius: keyHeight * 0.34,
                      focusScale: 1.025,
                      focusNode: _keyboardFocusNodes[rowIndex][columnIndex],
                      upFallbackNodes:
                          _keyboardUpFallback(rowIndex, columnIndex),
                      downFallbackNodes:
                          _keyboardDownFallback(rowIndex, columnIndex),
                      leftFallbackNodes:
                          _keyboardLeftFallback(rowIndex, columnIndex),
                      rightFallbackNodes:
                          _keyboardRightFallback(rowIndex, columnIndex),
                      onFocusChanged: (focused) {
                        if (focused) {
                          _rememberKeypadFocus(
                            _keyboardFocusNodes[rowIndex][columnIndex],
                          );
                        }
                      },
                      variant: TvButtonVariant.dark,
                    ),
                  ),
                  if (columnIndex <
                      tvCharacterKeyboardRows[rowIndex].length - 1)
                    SizedBox(width: rowGap),
                ],
              ],
            ),
          ),
          if (rowIndex < rowCount - 1) SizedBox(height: rowGap),
        ],
      ],
    );
  }

  Widget _buildResults(_SearchLayoutMetrics layout) {
    if (widget.mediaCatalogService == null) {
      return const _SearchMessage(
        title: 'TMDb API key missing',
        message:
            'Search needs CHERIFLIX_TMDB_API_KEY before live results can load.',
      );
    }

    if (_query.trim().length < 2) {
      return const _SearchMessage(
        title: 'Results',
        message:
            'Enter at least two characters using the on-screen keyboard or your physical keyboard.',
      );
    }

    if (_loading) {
      return const _SearchMessage(
        title: 'Results',
        message: 'Searching the CHERIFLIX catalog...',
        loading: true,
      );
    }

    if (_error != null) {
      return _SearchMessage(
        title: 'Search failed',
        message: _error!,
      );
    }

    if (_results.isEmpty) {
      return const _SearchMessage(
        title: 'No matches',
        message: 'Try a broader title or a shorter query.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final gridMetrics = layout.resultGrid;
        final gridSpacing = gridMetrics.gridSpacing;
        final resultGridColumnCount = _resultGridColumnCount(
          availableWidth: constraints.maxWidth,
          maxTileWidth: gridMetrics.preferredTileWidth,
          crossAxisSpacing: gridSpacing,
        );
        final cardWidth = _resultCardWidthForColumns(
          availableWidth: constraints.maxWidth,
          columnCount: resultGridColumnCount,
          crossAxisSpacing: gridSpacing,
        );
        final posterHeight = gridMetrics.posterHeightForWidth(cardWidth);
        final tileExtent = gridMetrics.tileExtentForWidth(cardWidth);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const CheriflixSectionTitle(title: 'Results'),
            const SizedBox(height: 6),
            Text(
              'Results for "$_query"',
              style: CheriflixTypography.bodyMedium.copyWith(
                color: CheriflixColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: GridView.builder(
                itemCount: _results.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: resultGridColumnCount,
                  mainAxisSpacing: gridSpacing,
                  crossAxisSpacing: gridSpacing,
                  mainAxisExtent: tileExtent,
                ),
                itemBuilder: (context, index) {
                  final item = _results[index];
                  return TvPosterButton(
                    title: item.title,
                    subtitle: item.metadataLabel,
                    imageUrl: item.posterUrl ?? item.backdropUrl,
                    width: cardWidth,
                    posterHeight: posterHeight,
                    expandedWidth: cardWidth,
                    expandedPosterHeight: posterHeight,
                    expandOnFocus: false,
                    reserveExpandedSpace: false,
                    overlayExpandedDetails: false,
                    autoplayPreviewEnabled: false,
                    autoplayPreviewMuted: widget.muteAutoplayTrailers,
                    previewLoadDelay: const Duration(milliseconds: 1800),
                    focusTransitionDuration: Duration.zero,
                    showFocusedGlow: false,
                    expandedImageUrl: item.backdropUrl ?? item.posterUrl,
                    previewLoader: () => _loadPreviewUri(item),
                    focusNode: _resultFocusNodeForIndex(index),
                    leftFallbackNodes:
                        _resultLeftFallback(index, resultGridColumnCount),
                    rightFallbackNodes:
                        _resultRightFallback(index, resultGridColumnCount),
                    upFallbackNodes:
                        _resultUpFallback(index, resultGridColumnCount),
                    downFallbackNodes:
                        _resultDownFallback(index, resultGridColumnCount),
                    onPressed: () => widget.onOpenTitle(item),
                    saved: widget.savedTitleKeys.contains(item.saveKey),
                    onToggleSaved: widget.onToggleSaved == null
                        ? null
                        : () => widget.onToggleSaved!(item),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQueryText() {
    final style = CheriflixTypography.bodyMedium.copyWith(
      fontSize: 16,
      color: _query.isEmpty ? Colors.white54 : CheriflixColors.textPrimary,
    );
    if (_query.isEmpty) {
      return Text(
        'Type to search...',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    final cursorIndex = _cursorIndex.clamp(0, _query.length);
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: style,
        children: <InlineSpan>[
          TextSpan(text: _query.substring(0, cursorIndex)),
          const TextSpan(
            text: '|',
            style: TextStyle(
              color: CheriflixColors.accentRed,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: _query.substring(cursorIndex)),
        ],
      ),
    );
  }

  List<FocusNode> get _topBarDownFallbackNodes => <FocusNode>[
        for (final row in _keyboardFocusNodes) ...row,
      ];

  FocusNode get _keypadReturnFocusNode =>
      _lastFocusedKeypadNode ?? _firstKeyFocusNode;

  List<List<FocusNode>> _buildKeyboardFocusNodes() {
    return List<List<FocusNode>>.generate(
      tvCharacterKeyboardRows.length,
      (rowIndex) => List<FocusNode>.generate(
        tvCharacterKeyboardRows[rowIndex].length,
        (columnIndex) {
          if (rowIndex == 0 && columnIndex == 0) {
            return _firstKeyFocusNode;
          }
          final label = tvCharacterKeyboardRows[rowIndex][columnIndex];
          return FocusNode(
            debugLabel: 'SearchKey($rowIndex,$columnIndex,$label)',
          );
        },
        growable: false,
      ),
      growable: false,
    );
  }

  void _disposeKeyboardFocusNodes() {
    for (final row in _keyboardFocusNodes) {
      for (final focusNode in row) {
        if (identical(focusNode, _firstKeyFocusNode)) {
          continue;
        }
        focusNode.dispose();
      }
    }
  }

  void _disposeResultFocusNodes() {
    for (final focusNode in _resultFocusNodes) {
      focusNode.dispose();
    }
    _resultFocusNodes.clear();
  }

  FocusNode _resultFocusNodeForIndex(int index) {
    _ensureResultFocusNodeForIndex(index);
    return _resultFocusNodes[index];
  }

  /// Lazily grow the search-result FocusNode pool so only visible items
  /// participate in the traversal graph.
  void _ensureResultFocusNodeForIndex(int index) {
    while (_resultFocusNodes.length <= index) {
      _resultFocusNodes.add(
        FocusNode(debugLabel: 'SearchResult[${_resultFocusNodes.length}]'),
      );
    }
  }

  int _resultGridColumnCount({
    required double availableWidth,
    required double maxTileWidth,
    required double crossAxisSpacing,
  }) {
    if (availableWidth <= 0) {
      return 1;
    }
    final columnCount = ((availableWidth + crossAxisSpacing) /
            (maxTileWidth + crossAxisSpacing))
        .floor();
    return math.max(1, columnCount);
  }

  double _resultCardWidthForColumns({
    required double availableWidth,
    required int columnCount,
    required double crossAxisSpacing,
  }) {
    if (columnCount <= 1) {
      return availableWidth.clamp(120.0, 360.0).toDouble();
    }
    final width =
        (availableWidth - (columnCount - 1) * crossAxisSpacing) / columnCount;
    return width.clamp(120.0, 360.0).toDouble();
  }

  void _rememberKeypadFocus(FocusNode focusNode) {
    if (identical(_lastFocusedKeypadNode, focusNode)) {
      return;
    }
    setState(() {
      _lastFocusedKeypadNode = focusNode;
    });
  }

  List<FocusNode> _resultLeftFallback(int index, int columnCount) {
    if (index % columnCount == 0) {
      return <FocusNode>[_keypadReturnFocusNode];
    }
    return <FocusNode>[_resultFocusNodeForIndex(index - 1)];
  }

  List<FocusNode> _resultRightFallback(int index, int columnCount) {
    final nextIndex = index + 1;
    final isSameRow = nextIndex < _results.length &&
        index ~/ columnCount == nextIndex ~/ columnCount;
    return <FocusNode>[
      isSameRow
          ? _resultFocusNodeForIndex(nextIndex)
          : _resultFocusNodeForIndex(index),
    ];
  }

  List<FocusNode> _resultUpFallback(int index, int columnCount) {
    final targetIndex = index - columnCount;
    return <FocusNode>[
      targetIndex >= 0
          ? _resultFocusNodeForIndex(targetIndex)
          : _keypadReturnFocusNode,
    ];
  }

  List<FocusNode> _resultDownFallback(int index, int columnCount) {
    final targetIndex = index + columnCount;
    return <FocusNode>[
      targetIndex < _results.length
          ? _resultFocusNodeForIndex(targetIndex)
          : _resultFocusNodeForIndex(index),
    ];
  }

  VoidCallback _keyboardActionFor(String label) {
    if (label == '\u2190') {
      return () => _moveCursorBy(-1);
    }
    if (label == '\u2192') {
      return () => _moveCursorBy(1);
    }
    return switch (label) {
      'SP' => () => _append(' '),
      'DEL' => _erase,
      'CLR' => _clear,
      '←' => () => _moveCursorBy(-1),
      '→' => () => _moveCursorBy(1),
      '↑' => _moveCursorToStart,
      '↓' => _moveCursorToEnd,
      _ => () => _append(label),
    };
  }

  List<FocusNode> _keyboardUpFallback(int rowIndex, int columnIndex) {
    if (rowIndex == 0) {
      return <FocusNode>[_backButtonFocusNode];
    }
    final previousRow = _keyboardFocusNodes[rowIndex - 1];
    final targetIndex = columnIndex.clamp(0, previousRow.length - 1);
    return <FocusNode>[
      previousRow[targetIndex],
    ];
  }

  List<FocusNode> _keyboardDownFallback(int rowIndex, int columnIndex) {
    if (rowIndex >= _keyboardFocusNodes.length - 1) {
      if (_resultFocusNodes.isNotEmpty) {
        return _nearestResultFallbackNodes(
          fromNode: _keyboardFocusNodes[rowIndex][columnIndex],
          direction: TraversalDirection.down,
        );
      }
      return <FocusNode>[_keyboardFocusNodes[rowIndex][columnIndex]];
    }
    final nextRow = _keyboardFocusNodes[rowIndex + 1];
    final targetIndex = columnIndex.clamp(0, nextRow.length - 1);
    return <FocusNode>[
      nextRow[targetIndex],
    ];
  }

  List<FocusNode> _keyboardLeftFallback(int rowIndex, int columnIndex) {
    final row = _keyboardFocusNodes[rowIndex];
    final targetIndex = columnIndex > 0 ? columnIndex - 1 : 0;
    return <FocusNode>[row[targetIndex]];
  }

  List<FocusNode> _keyboardRightFallback(int rowIndex, int columnIndex) {
    final row = _keyboardFocusNodes[rowIndex];
    if (columnIndex == row.length - 1 && _resultFocusNodes.isNotEmpty) {
      return _nearestResultFallbackNodes(
        fromNode: row[columnIndex],
        direction: TraversalDirection.right,
      );
    }
    final targetIndex =
        columnIndex < row.length - 1 ? columnIndex + 1 : row.length - 1;
    return <FocusNode>[row[targetIndex]];
  }

  List<FocusNode> _nearestResultFallbackNodes({
    required FocusNode fromNode,
    required TraversalDirection direction,
  }) {
    final mountedResults = _resultFocusNodes
        .where((node) => node.canRequestFocus && node.context != null)
        .toList(growable: false);
    if (mountedResults.isEmpty) {
      // Keyboard fallbacks are built just before the result cards mount in
      // the same frame. Keep the seeded node as a valid destination; by the
      // time a user presses the D-pad it has an attached card context.
      return _resultFocusNodes
          .where((node) => node.canRequestFocus)
          .toList(growable: false);
    }
    if (mountedResults.length <= 1) {
      return mountedResults;
    }

    final fromCenter = _focusNodeGlobalCenter(fromNode);
    if (fromCenter == null) {
      return mountedResults;
    }

    final directionalResults = mountedResults
        .map((node) {
          final score = _directionalResultScore(
            fromCenter: fromCenter,
            candidate: node,
            direction: direction,
          );
          return score == null ? null : _ScoredFocusNode(node, score);
        })
        .whereType<_ScoredFocusNode>()
        .toList(growable: false);

    if (directionalResults.isEmpty) {
      return mountedResults;
    }

    directionalResults.sort((left, right) => left.score.compareTo(right.score));
    return directionalResults
        .map((entry) => entry.node)
        .toList(growable: false);
  }

  double? _directionalResultScore({
    required Offset fromCenter,
    required FocusNode candidate,
    required TraversalDirection direction,
  }) {
    final candidateCenter = _focusNodeGlobalCenter(candidate);
    if (candidateCenter == null) {
      return null;
    }
    final primaryDistance = switch (direction) {
      TraversalDirection.left => fromCenter.dx - candidateCenter.dx,
      TraversalDirection.right => candidateCenter.dx - fromCenter.dx,
      TraversalDirection.up => fromCenter.dy - candidateCenter.dy,
      TraversalDirection.down => candidateCenter.dy - fromCenter.dy,
    };
    if (primaryDistance < -1) {
      return null;
    }
    final perpendicularDistance = switch (direction) {
      TraversalDirection.left ||
      TraversalDirection.right =>
        (candidateCenter.dy - fromCenter.dy).abs(),
      TraversalDirection.up ||
      TraversalDirection.down =>
        (candidateCenter.dx - fromCenter.dx).abs(),
    };
    return perpendicularDistance * 10000 + primaryDistance.abs();
  }

  Offset? _focusNodeGlobalCenter(FocusNode node) {
    final context = node.context;
    if (context == null) {
      return null;
    }
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }
    return renderObject.localToGlobal(renderObject.size.center(Offset.zero));
  }

  KeyEventResult _handleQueryKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final character = event.character;
    if (character == null || character.isEmpty) {
      return KeyEventResult.ignored;
    }

    final normalized = character.toUpperCase();
    final isAllowed = isSupportedTvKeyboardCharacter(normalized);
    if (!isAllowed) {
      return KeyEventResult.ignored;
    }

    _append(normalized);
    return KeyEventResult.handled;
  }

  void _append(String value) {
    final insertionIndex = _cursorIndex.clamp(0, _query.length);
    final next =
        '${_query.substring(0, insertionIndex)}$value${_query.substring(insertionIndex)}';
    setState(() {
      _query = next;
      _cursorIndex = insertionIndex + value.length;
    });
    _scheduleSearch();
  }

  void _erase() {
    if (_query.isEmpty || _cursorIndex <= 0) {
      return;
    }
    final deleteIndex = _cursorIndex - 1;
    setState(() {
      _query =
          '${_query.substring(0, deleteIndex)}${_query.substring(_cursorIndex)}';
      _cursorIndex = deleteIndex;
    });
    _scheduleSearch();
  }

  void _clear() {
    _disposeResultFocusNodes();
    setState(() {
      _query = '';
      _cursorIndex = 0;
      _results = const <MediaSummary>[];
      _error = null;
    });
    _debounce?.cancel();
  }

  void _moveCursorBy(int delta) {
    final next = (_cursorIndex + delta).clamp(0, _query.length);
    if (next == _cursorIndex) {
      return;
    }
    setState(() {
      _cursorIndex = next;
    });
  }

  void _moveCursorToStart() {
    if (_cursorIndex == 0) {
      return;
    }
    setState(() {
      _cursorIndex = 0;
    });
  }

  void _moveCursorToEnd() {
    if (_cursorIndex == _query.length) {
      return;
    }
    setState(() {
      _cursorIndex = _query.length;
    });
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    if (_query.trim().length < 2) {
      _disposeResultFocusNodes();
      setState(() {
        _results = const <MediaSummary>[];
        _error = null;
        _loading = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 350), _runSearch);
  }

  Future<void> _runSearch() async {
    final service = widget.mediaCatalogService;
    if (service == null) {
      return;
    }

    final query = _query.trim();
    if (query.length < 2) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      var results = await service.searchTitles(
        query: query,
        languageCode: widget.languageCode,
      );
      final tmdbService = _tmdbCatalogService;
      final profile = widget.activeProfile;
      if (tmdbService != null && profile != null) {
        results = await tmdbService.filterForMaturity(
          results,
          tier: profile.maturityTier,
          languageCode: widget.languageCode,
        );
      }
      if (!mounted || query != _query.trim()) {
        return;
      }
      _disposeResultFocusNodes();
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = userFacingErrorMessage(
          error,
          fallback: 'Search results could not be loaded right now.',
        );
      });
    }
  }

  Future<Uri?> _loadPreviewUri(MediaSummary item) async {
    final service = _tmdbCatalogService;
    if (service == null) {
      return null;
    }
    return service.fetchTrailerPreviewUri(
      tmdbId: item.tmdbId,
      mediaType: item.mediaType,
      languageCode: widget.languageCode,
      muted: widget.muteAutoplayTrailers,
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

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({
    required this.title,
    required this.message,
    this.loading = false,
  });

  final String title;
  final String message;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (loading) const CircularProgressIndicator(),
            if (loading) const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: CheriflixTypography.sectionTitle,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: CheriflixTypography.body.copyWith(
                color: CheriflixColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
