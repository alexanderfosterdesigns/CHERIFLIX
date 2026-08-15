import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/profile_avatar_catalog.dart';
import '../../core/theme/cheriflix_theme.dart';
import '../../core/theme/tv_layout.dart';
import '../../core/widgets/cheriflix_chrome.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../core/widgets/tv_shortcuts.dart';

Future<String?> showProfileAvatarPickerDialog(
  BuildContext context, {
  required String selectedAvatarLabel,
  String title = 'Choose profile picture',
  String subtitle = 'Default profile pictures are shown first.',
  ProfileAvatarCatalogService? avatarCatalogService,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      final layout = CheriflixTvLayout.of(context);
      return TvShortcutScope(
        onBack: () => Navigator.of(context).pop(),
        child: Scaffold(
          backgroundColor: const Color(0xF2121212),
          body: SafeArea(
            child: Padding(
              padding: layout.dialogInsetPadding,
              child: CheriflixPanel(
                padding: EdgeInsets.fromLTRB(
                  layout.value(compact: 18, standard: 20, wide: 24),
                  layout.value(compact: 16, standard: 18, wide: 20),
                  layout.value(compact: 18, standard: 20, wide: 24),
                  layout.value(compact: 16, standard: 18, wide: 20),
                ),
                child: ProfileAvatarPickerGallery(
                  selectedAvatarLabel: selectedAvatarLabel,
                  title: title,
                  subtitle: subtitle,
                  avatarCatalogService: avatarCatalogService,
                  onClose: () => Navigator.of(context).pop(),
                  onSelect: (key) => Navigator.of(context).pop(key),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class ProfileAvatarPickerGallery extends StatefulWidget {
  const ProfileAvatarPickerGallery({
    super.key,
    required this.selectedAvatarLabel,
    required this.onSelect,
    this.title = 'Choose profile picture',
    this.subtitle = 'Default profile pictures are shown first.',
    this.onClose,
    this.requestInitialFocus = true,
    this.entryFocusNode,
    this.leftFallbackNodes = const <FocusNode>[],
    this.avatarCatalogService,
  });

  final String selectedAvatarLabel;
  final ValueChanged<String> onSelect;
  final String title;
  final String subtitle;
  final VoidCallback? onClose;
  final bool requestInitialFocus;
  final FocusNode? entryFocusNode;
  final List<FocusNode> leftFallbackNodes;
  final ProfileAvatarCatalogService? avatarCatalogService;

  @override
  State<ProfileAvatarPickerGallery> createState() =>
      _ProfileAvatarPickerGalleryState();
}

class _ProfileAvatarPickerGalleryState
    extends State<ProfileAvatarPickerGallery> {
  late final ProfileAvatarCatalogService _avatarCatalogService =
      widget.avatarCatalogService ?? ProfileAvatarCatalogService.instance;
  late final Future<ProfileAvatarCatalog> _catalogFuture =
      _avatarCatalogService.loadCatalog();
  final ScrollController _verticalController = ScrollController();
  final List<List<FocusNode>?> _focusRows = <List<FocusNode>?>[];
  List<_AvatarPickerRow> _rows = const <_AvatarPickerRow>[];
  String _layoutSignature = '';
  bool _requestedInitialFocus = false;

  @override
  void dispose() {
    _verticalController.dispose();
    _disposeFocusNodes();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = CheriflixTvLayout.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                widget.title,
                style: TextStyle(
                  fontSize: layout.avatarPickerTitleSize,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (widget.onClose != null)
              TvActionButton(
                label: 'Close',
                icon: Icons.close_rounded,
                onPressed: widget.onClose,
                variant: TvButtonVariant.ghost,
              ),
          ],
        ),
        if (widget.subtitle.isNotEmpty) ...<Widget>[
          SizedBox(height: layout.value(compact: 6, standard: 7, wide: 8)),
          Text(
            widget.subtitle,
            style: TextStyle(
              color: CheriflixColors.textSecondary,
              fontSize: layout.avatarPickerSubtitleSize,
            ),
          ),
        ],
        SizedBox(height: layout.value(compact: 14, standard: 16, wide: 18)),
        Expanded(
          child: FutureBuilder<ProfileAvatarCatalog>(
            future: _catalogFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final catalog =
                  snapshot.data ?? const ProfileAvatarCatalog.empty();
              if (catalog.allOptions.isEmpty) {
                return _AvatarCatalogEmptyPane(
                  focusNode: widget.entryFocusNode,
                  leftFallbackNodes: widget.leftFallbackNodes,
                );
              }

              final rows = _rowsForCatalog(catalog);
              _ensureFocusLayout(rows);
              if (widget.requestInitialFocus) {
                _requestInitialFocus();
              }
              final normalizedSelected = _avatarCatalogService
                      .normalizeAvatarKey(widget.selectedAvatarLabel) ??
                  widget.selectedAvatarLabel.replaceAll('\\', '/');
              return ListView.separated(
                controller: _verticalController,
                itemCount: _rows.length,
                separatorBuilder: (context, index) {
                  return SizedBox(
                    height: layout.value(compact: 16, standard: 18, wide: 22),
                  );
                },
                itemBuilder: (context, rowIndex) {
                  final row = _rows[rowIndex];
                  return _AvatarCategoryRail(
                    title: row.title,
                    options: row.options,
                    selectedAvatarLabel: normalizedSelected,
                    focusNodes: _focusNodesForRow(rowIndex),
                    leftFallbackNodes: widget.leftFallbackNodes,
                    onMove: (columnIndex, direction) {
                      _moveFocus(
                        rowIndex: rowIndex,
                        columnIndex: columnIndex,
                        direction: direction,
                      );
                    },
                    onSelect: widget.onSelect,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  List<_AvatarPickerRow> _rowsForCatalog(ProfileAvatarCatalog catalog) {
    final rows = <_AvatarPickerRow>[];
    if (catalog.defaultOptions.isNotEmpty) {
      rows.add(
        _AvatarPickerRow(
          id: 'default',
          title: 'Default',
          options: catalog.defaultOptions,
        ),
      );
    }
    rows.addAll(
      catalog.categories.map(
        (category) => _AvatarPickerRow(
          id: category.id,
          title: category.title,
          options: category.options,
        ),
      ),
    );
    return rows;
  }

  void _ensureFocusLayout(List<_AvatarPickerRow> rows) {
    final signature =
        rows.map((row) => '${row.id}:${row.options.length}').join('|');
    if (signature == _layoutSignature) {
      return;
    }
    _disposeFocusNodes();
    _rows = rows;
    _focusRows.addAll(List<List<FocusNode>?>.filled(rows.length, null));
    _layoutSignature = signature;
    _requestedInitialFocus = false;
  }

  List<FocusNode> _focusNodesForRow(int rowIndex) {
    final existing = _focusRows[rowIndex];
    if (existing != null) {
      return existing;
    }
    final row = _rows[rowIndex];
    final nodes = <FocusNode>[
      for (var itemIndex = 0; itemIndex < row.options.length; itemIndex += 1)
        rowIndex == 0 && itemIndex == 0 && widget.entryFocusNode != null
            ? widget.entryFocusNode!
            : FocusNode(debugLabel: 'AvatarPicker(${row.id}-$itemIndex)'),
    ];
    _focusRows[rowIndex] = nodes;
    return nodes;
  }

  void _disposeFocusNodes() {
    for (final row in _focusRows.whereType<List<FocusNode>>()) {
      for (final node in row) {
        if (identical(node, widget.entryFocusNode)) {
          continue;
        }
        node.dispose();
      }
    }
    _focusRows.clear();
  }

  void _requestInitialFocus() {
    if (_requestedInitialFocus || _focusRows.isEmpty) {
      return;
    }
    _requestedInitialFocus = true;
    final normalizedSelected =
        _avatarCatalogService.normalizeAvatarKey(widget.selectedAvatarLabel) ??
            widget.selectedAvatarLabel.replaceAll('\\', '/');

    var rowIndex = 0;
    var columnIndex = 0;
    for (var r = 0; r < _rows.length; r += 1) {
      final row = _rows[r];
      for (var c = 0; c < row.options.length; c += 1) {
        if (row.options[c].key == normalizedSelected) {
          rowIndex = r;
          columnIndex = c;
          r = _rows.length;
          break;
        }
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _focusRows.isEmpty) {
        return;
      }
      _focusNodesForRow(rowIndex)[columnIndex].requestFocus();
    });
  }

  void _moveFocus({
    required int rowIndex,
    required int columnIndex,
    required _AvatarMoveDirection direction,
  }) {
    if (_focusRows.isEmpty) {
      return;
    }
    if (direction == _AvatarMoveDirection.left &&
        columnIndex == 0 &&
        widget.leftFallbackNodes.isNotEmpty) {
      widget.leftFallbackNodes.first.requestFocus();
      return;
    }
    var nextRow = rowIndex;
    var nextColumn = columnIndex;
    switch (direction) {
      case _AvatarMoveDirection.left:
        nextColumn = math.max(0, columnIndex - 1);
      case _AvatarMoveDirection.right:
        nextColumn = math.min(
          _focusNodesForRow(rowIndex).length - 1,
          columnIndex + 1,
        );
      case _AvatarMoveDirection.up:
        nextRow = math.max(0, rowIndex - 1);
        nextColumn = math.min(
          columnIndex,
          _focusNodesForRow(nextRow).length - 1,
        );
      case _AvatarMoveDirection.down:
        nextRow = math.min(_focusRows.length - 1, rowIndex + 1);
        nextColumn = math.min(
          columnIndex,
          _focusNodesForRow(nextRow).length - 1,
        );
    }
    _focusNodesForRow(nextRow)[nextColumn].requestFocus();
  }
}

class _AvatarPickerRow {
  const _AvatarPickerRow({
    required this.id,
    required this.title,
    required this.options,
  });

  final String id;
  final String title;
  final List<ProfileAvatarOption> options;
}

class _AvatarCatalogEmptyPane extends StatefulWidget {
  const _AvatarCatalogEmptyPane({
    required this.focusNode,
    required this.leftFallbackNodes,
  });

  final FocusNode? focusNode;
  final List<FocusNode> leftFallbackNodes;

  @override
  State<_AvatarCatalogEmptyPane> createState() =>
      _AvatarCatalogEmptyPaneState();
}

class _AvatarCatalogEmptyPaneState extends State<_AvatarCatalogEmptyPane> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final focusNode = widget.focusNode;
    if (focusNode == null) {
      return const Center(
        child: Text(
          'No profile pictures were found.',
          style: TextStyle(
            color: CheriflixColors.textSecondary,
            fontSize: 18,
          ),
        ),
      );
    }

    return Focus(
      focusNode: focusNode,
      onFocusChange: (value) => setState(() => _focused = value),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
            widget.leftFallbackNodes.isNotEmpty) {
          widget.leftFallbackNodes.first.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          decoration: BoxDecoration(
            color: _focused ? const Color(0x26111111) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _focused
                  ? CheriflixColors.focus
                  : Colors.white.withValues(alpha: 0.22),
              width: _focused ? 2.6 : 1.2,
            ),
          ),
          child: const Text(
            'No profile pictures were found.',
            style: TextStyle(
              color: CheriflixColors.textSecondary,
              fontSize: 18,
            ),
          ),
        ),
      ),
    );
  }
}

enum _AvatarMoveDirection {
  left,
  right,
  up,
  down,
}

class _AvatarCategoryRail extends StatefulWidget {
  const _AvatarCategoryRail({
    required this.title,
    required this.options,
    required this.selectedAvatarLabel,
    required this.focusNodes,
    required this.leftFallbackNodes,
    required this.onMove,
    required this.onSelect,
  });

  final String title;
  final List<ProfileAvatarOption> options;
  final String selectedAvatarLabel;
  final List<FocusNode> focusNodes;
  final List<FocusNode> leftFallbackNodes;
  final void Function(int columnIndex, _AvatarMoveDirection direction) onMove;
  final ValueChanged<String> onSelect;

  @override
  State<_AvatarCategoryRail> createState() => _AvatarCategoryRailState();
}

class _AvatarCategoryRailState extends State<_AvatarCategoryRail> {
  final ScrollController _controller = ScrollController();
  bool _showRightHint = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateHints);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateHints());
  }

  @override
  void dispose() {
    _controller.removeListener(_updateHints);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = CheriflixTvLayout.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.title,
          style: TextStyle(
            fontSize: layout.avatarPickerCategoryTitleSize,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: layout.value(compact: 8, standard: 9, wide: 10)),
        SizedBox(
          height: layout.avatarPickerRowHeight,
          child: Stack(
            children: <Widget>[
              ListView.separated(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                itemCount: widget.options.length,
                separatorBuilder: (context, index) => SizedBox(
                  width: layout.avatarPickerGap,
                ),
                itemBuilder: (context, index) {
                  final option = widget.options[index];
                  return _AvatarRailTile(
                    option: option,
                    selected: option.key == widget.selectedAvatarLabel,
                    focusNode: widget.focusNodes[index],
                    onSelect: widget.onSelect,
                    onMove: (direction) => widget.onMove(index, direction),
                  );
                },
              ),
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _showRightHint ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Container(
                      width: 52,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: <Color>[
                            Colors.transparent,
                            Color(0xCC111111),
                          ],
                        ),
                      ),
                      child: const Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 22,
                            color: Color(0xCCFFFFFF),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _updateHints() {
    if (!_controller.hasClients) {
      return;
    }
    final maxExtent = _controller.position.maxScrollExtent;
    final pixels = _controller.position.pixels;
    final shouldShow = maxExtent - pixels > 8;
    if (shouldShow == _showRightHint) {
      return;
    }
    setState(() => _showRightHint = shouldShow);
  }
}

class _AvatarRailTile extends StatefulWidget {
  const _AvatarRailTile({
    required this.option,
    required this.selected,
    required this.focusNode,
    required this.onSelect,
    required this.onMove,
  });

  final ProfileAvatarOption option;
  final bool selected;
  final FocusNode focusNode;
  final ValueChanged<String> onSelect;
  final ValueChanged<_AvatarMoveDirection> onMove;

  @override
  State<_AvatarRailTile> createState() => _AvatarRailTileState();
}

class _AvatarRailTileState extends State<_AvatarRailTile> {
  static const Map<ShortcutActivator, Intent> _shortcuts =
      <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.arrowLeft):
        _AvatarMoveIntent(_AvatarMoveDirection.left),
    SingleActivator(LogicalKeyboardKey.arrowRight):
        _AvatarMoveIntent(_AvatarMoveDirection.right),
    SingleActivator(LogicalKeyboardKey.arrowUp):
        _AvatarMoveIntent(_AvatarMoveDirection.up),
    SingleActivator(LogicalKeyboardKey.arrowDown):
        _AvatarMoveIntent(_AvatarMoveDirection.down),
  };

  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final layout = CheriflixTvLayout.of(context);
    final borderColor = _focused
        ? CheriflixColors.focus
        : widget.selected
            ? CheriflixColors.accentRed
            : Colors.white.withValues(alpha: 0.22);
    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              widget.onSelect(widget.option.key);
              return null;
            },
          ),
          _AvatarMoveIntent: CallbackAction<_AvatarMoveIntent>(
            onInvoke: (intent) {
              widget.onMove(intent.direction);
              return null;
            },
          ),
        },
        child: FocusableActionDetector(
          focusNode: widget.focusNode,
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 140),
            scale: _focused ? 1.03 : 1,
            child: InkWell(
              key: ValueKey<String>('AvatarTile:${widget.option.key}'),
              borderRadius:
                  BorderRadius.circular(layout.avatarPickerTileRadius),
              onTap: () {
                widget.focusNode.requestFocus();
                widget.onSelect(widget.option.key);
              },
              child: Container(
                width: layout.avatarPickerTileSize,
                decoration: BoxDecoration(
                  color: const Color(0xFF171717),
                  borderRadius:
                      BorderRadius.circular(layout.avatarPickerTileRadius),
                  border: Border.all(
                    color: borderColor,
                    width: _focused
                        ? 2.6
                        : widget.selected
                            ? 2.1
                            : 1.1,
                  ),
                  boxShadow: <BoxShadow>[
                    const BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 10,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: CheriflixProfileAvatar(
                  avatarLabel: widget.option.key,
                  resolvedFile: widget.option.file,
                  resolvedAssetPath: widget.option.assetPath,
                  width: layout.avatarPickerTileSize,
                  height: layout.avatarPickerTileSize,
                  borderRadius: BorderRadius.circular(
                    layout.avatarPickerTileRadius - 1,
                  ),
                  fallbackTextStyle: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: layout.avatarPickerFallbackFontSize,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarMoveIntent extends Intent {
  const _AvatarMoveIntent(this.direction);

  final _AvatarMoveDirection direction;
}
