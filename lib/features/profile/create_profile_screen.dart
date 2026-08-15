import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/profile.dart';
import '../../core/services/profile_avatar_catalog.dart';
import '../../core/theme/cheriflix_theme.dart';
import '../../core/theme/tv_layout.dart';
import '../../core/widgets/cheriflix_chrome.dart';
import '../../core/widgets/tv_character_keyboard.dart';
import '../../core/widgets/tv_shortcuts.dart';
import 'profile_avatar_picker.dart';

class CreateProfileScreen extends StatefulWidget {
  const CreateProfileScreen({
    super.key,
    required this.profiles,
    required this.onBack,
    required this.onCreateProfile,
    this.avatarCatalogService,
  });

  final List<Profile> profiles;
  final VoidCallback onBack;
  final Future<void> Function(String name, String avatarLabel) onCreateProfile;
  final ProfileAvatarCatalogService? avatarCatalogService;

  @override
  State<CreateProfileScreen> createState() => _CreateProfileScreenState();
}

class _CreateProfileScreenState extends State<CreateProfileScreen> {
  late final FocusNode _backButtonFocusNode =
      FocusNode(debugLabel: 'CreateProfileBack');
  late final FocusNode _selectPictureFocusNode =
      FocusNode(debugLabel: 'CreateProfileSelectPicture');
  late final FocusNode _nameFieldFocusNode =
      FocusNode(debugLabel: 'CreateProfileNameField');
  late final FocusNode _firstKeyFocusNode =
      FocusNode(debugLabel: 'CreateProfileFirstKey');
  late final FocusNode _createButtonFocusNode =
      FocusNode(debugLabel: 'CreateProfileSubmit');
  late final FocusNode _cancelButtonFocusNode =
      FocusNode(debugLabel: 'CreateProfileCancel');
  final ScrollController _scrollController = ScrollController();
  late final List<List<FocusNode>> _keyboardFocusNodes =
      _buildKeyboardFocusNodes();

  String _name = '';
  String _avatarLabel = 'C';
  bool _avatarTouched = false;
  bool _avatarPickerOpen = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadSuggestedAvatar();
  }

  @override
  void dispose() {
    _backButtonFocusNode.dispose();
    _selectPictureFocusNode.dispose();
    _nameFieldFocusNode.dispose();
    _firstKeyFocusNode.dispose();
    _createButtonFocusNode.dispose();
    _cancelButtonFocusNode.dispose();
    _scrollController.dispose();
    _disposeKeyboardFocusNodes();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TvShortcutScope(
      onBack: _avatarPickerOpen ? null : widget.onBack,
      child: CheriflixScaffold(
        topBar: const CheriflixTopBar(showTabs: false, showActions: false),
        body: Focus(
          autofocus: true,
          onKeyEvent: _handleNameKey,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layout = CheriflixTvLayout.fromWidth(constraints.maxWidth);
              final contentMaxWidth = layout.value(
                compact: constraints.maxWidth,
                standard: 1020,
                wide: 1100,
              );
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentMaxWidth),
                  child: Padding(
                    padding: layout.pagePadding,
                    child: _buildFormPanel(layout),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFormPanel(CheriflixTvLayout layout) {
    return CheriflixPanel(
      padding: EdgeInsets.fromLTRB(
        layout.value(compact: 20, standard: 24, wide: 28),
        layout.value(compact: 18, standard: 20, wide: 22),
        layout.value(compact: 20, standard: 24, wide: 28),
        layout.value(compact: 20, standard: 24, wide: 26),
      ),
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TvActionButton(
              label: 'Back',
              icon: Icons.arrow_back_rounded,
              onPressed: widget.onBack,
              focusNode: _backButtonFocusNode,
              downFallbackNodes: <FocusNode>[_selectPictureFocusNode],
              onFocusChanged: (focused) {
                _ensureVisibleOnFocus(
                  _backButtonFocusNode,
                  focused,
                  alignment: 0,
                );
              },
              variant: TvButtonVariant.ghost,
            ),
            SizedBox(height: layout.value(compact: 16, standard: 18, wide: 20)),
            Text(
              'Create Profile',
              style: TextStyle(
                fontSize: layout.formTitleSize,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: layout.value(compact: 8, standard: 9, wide: 10)),
            Text(
              'Pick a picture, type a name, and CHERIFLIX will keep watchlists and playback settings separate for this profile.',
              style: TextStyle(
                color: CheriflixColors.textSecondary,
                fontSize: layout.bodySecondarySize,
                height: 1.45,
              ),
            ),
            SizedBox(height: layout.value(compact: 18, standard: 20, wide: 22)),
            Center(
              child: CheriflixProfileArtwork(
                size: layout.value(compact: 118, standard: 126, wide: 136),
                avatarLabel: _avatarLabel,
                avatarCatalogService: widget.avatarCatalogService,
              ),
            ),
            SizedBox(height: layout.value(compact: 12, standard: 14, wide: 16)),
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: layout.value(
                    compact: 290,
                    standard: 320,
                    wide: 340,
                  ),
                ),
                child: TvActionButton(
                  label: 'Select Profile Picture',
                  icon: Icons.account_circle_rounded,
                  onPressed: _submitting ? null : _openAvatarPicker,
                  focusNode: _selectPictureFocusNode,
                  upFallbackNodes: <FocusNode>[_backButtonFocusNode],
                  downFallbackNodes: <FocusNode>[_nameFieldFocusNode],
                  rightFallbackNodes: <FocusNode>[_firstKeyFocusNode],
                  onFocusChanged: (focused) {
                    _ensureVisibleOnFocus(
                      _selectPictureFocusNode,
                      focused,
                      alignment: 0.32,
                    );
                  },
                  variant: TvButtonVariant.dark,
                ),
              ),
            ),
            SizedBox(height: layout.value(compact: 18, standard: 20, wide: 22)),
            Text(
              'PROFILE NAME',
              style: TextStyle(
                color: CheriflixColors.textSecondary,
                fontSize: layout.formLabelSize,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.8,
              ),
            ),
            SizedBox(height: layout.value(compact: 10, standard: 11, wide: 12)),
            _buildNameField(layout),
            SizedBox(height: layout.value(compact: 16, standard: 18, wide: 20)),
            _buildKeyboard(layout),
            SizedBox(height: layout.value(compact: 14, standard: 16, wide: 18)),
            Row(
              children: <Widget>[
                Expanded(
                  child: TvActionButton(
                    label: _submitting ? 'Saving...' : 'Done',
                    onPressed:
                        _canCreate && !_submitting ? _submitCreate : null,
                    focusNode: _createButtonFocusNode,
                    upFallbackNodes: _actionUpFallbackNodes,
                    rightFallbackNodes: <FocusNode>[_cancelButtonFocusNode],
                    onFocusChanged: (focused) {
                      _ensureVisibleOnFocus(
                        _createButtonFocusNode,
                        focused,
                        alignment: 1,
                      );
                    },
                    variant: TvButtonVariant.light,
                  ),
                ),
                SizedBox(
                    width: layout.value(compact: 10, standard: 11, wide: 12)),
                Expanded(
                  child: TvActionButton(
                    label: 'Cancel',
                    onPressed: _submitting ? null : widget.onBack,
                    focusNode: _cancelButtonFocusNode,
                    upFallbackNodes: _actionUpFallbackNodes,
                    leftFallbackNodes: _canCreate
                        ? <FocusNode>[_createButtonFocusNode]
                        : <FocusNode>[_cancelButtonFocusNode],
                    rightFallbackNodes: <FocusNode>[_cancelButtonFocusNode],
                    onFocusChanged: (focused) {
                      _ensureVisibleOnFocus(
                        _cancelButtonFocusNode,
                        focused,
                        alignment: 1,
                      );
                    },
                    variant: TvButtonVariant.ghost,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNameField(CheriflixTvLayout layout) {
    final focused = _nameFieldFocusNode.hasFocus;
    return Focus(
      focusNode: _nameFieldFocusNode,
      onKeyEvent: _handleNameFieldKeyEvent,
      onFocusChange: (value) {
        if (!mounted) {
          return;
        }
        setState(() {});
        _ensureVisibleOnFocus(_nameFieldFocusNode, value, alignment: 0.46);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: const Color(0xFF101010),
          borderRadius: BorderRadius.circular(layout.panelRadius),
          border: Border.all(
            color: focused ? CheriflixColors.focus : const Color(0x22FFFFFF),
            width: focused ? 2.4 : 1.2,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: layout.value(compact: 14, standard: 16, wide: 18),
            vertical: layout.value(compact: 14, standard: 16, wide: 18),
          ),
          child: Text(
            _name.isEmpty ? 'Use the on-screen keyboard' : _name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: layout.value(compact: 17, standard: 18, wide: 20),
              fontWeight: FontWeight.w800,
              color:
                  _name.isEmpty ? Colors.white54 : CheriflixColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeyboard(CheriflixTvLayout layout) {
    return Center(
      child: ConstrainedBox(
        key: const ValueKey<String>('create_profile_keyboard'),
        constraints: BoxConstraints(
          maxWidth: layout.value(compact: 620, standard: 720, wide: 780),
        ),
        child: Column(
          children: <Widget>[
            for (var rowIndex = 0;
                rowIndex < tvCharacterKeyboardRows.length;
                rowIndex += 1) ...<Widget>[
              Row(
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
                        autofocus: rowIndex == 0 && columnIndex == 0,
                        focusNode: _keyboardFocusNodes[rowIndex][columnIndex],
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 8,
                        ),
                        labelStyle: TextStyle(
                          fontSize: layout.value(
                            compact: 14,
                            standard: 15,
                            wide: 16,
                          ),
                          fontWeight: FontWeight.w800,
                        ),
                        borderRadius: 10,
                        focusScale: 1.025,
                        onFocusChanged: (focused) {
                          _ensureVisibleOnFocus(
                            _keyboardFocusNodes[rowIndex][columnIndex],
                            focused,
                            alignment: 0.72,
                          );
                        },
                        upFallbackNodes:
                            _keyboardUpFallback(rowIndex, columnIndex),
                        downFallbackNodes:
                            _keyboardDownFallback(rowIndex, columnIndex),
                        leftFallbackNodes:
                            _keyboardLeftFallback(rowIndex, columnIndex),
                        rightFallbackNodes:
                            _keyboardRightFallback(rowIndex, columnIndex),
                        variant: TvButtonVariant.dark,
                      ),
                    ),
                    if (columnIndex <
                        tvCharacterKeyboardRows[rowIndex].length - 1)
                      SizedBox(
                        width: layout.value(compact: 7, standard: 8, wide: 9),
                      ),
                  ],
                  for (var spacerIndex =
                          tvCharacterKeyboardRows[rowIndex].length;
                      spacerIndex < 6;
                      spacerIndex += 1) ...<Widget>[
                    const Expanded(child: SizedBox.shrink()),
                    if (spacerIndex < 5)
                      SizedBox(
                        width: layout.value(compact: 7, standard: 8, wide: 9),
                      ),
                  ],
                ],
              ),
              if (rowIndex < tvCharacterKeyboardRows.length - 1)
                SizedBox(
                  height: layout.value(compact: 7, standard: 8, wide: 9),
                ),
            ],
          ],
        ),
      ),
    );
  }

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
            debugLabel: 'CreateProfileKey($rowIndex,$columnIndex,$label)',
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

  VoidCallback _keyboardActionFor(String label) {
    return switch (label) {
      'SP' => () => _append(' '),
      'DEL' => _erase,
      'CLR' => _clear,
      _ => () => _append(label),
    };
  }

  List<FocusNode> _keyboardUpFallback(int rowIndex, int columnIndex) {
    if (rowIndex == 0) {
      return <FocusNode>[_nameFieldFocusNode];
    }
    final previousRow = _keyboardFocusNodes[rowIndex - 1];
    final targetIndex = columnIndex.clamp(0, previousRow.length - 1);
    return <FocusNode>[previousRow[targetIndex]];
  }

  List<FocusNode> _keyboardDownFallback(int rowIndex, int columnIndex) {
    if (rowIndex >= _keyboardFocusNodes.length - 1) {
      return _keyboardBottomFallbackNodes;
    }
    final nextRow = _keyboardFocusNodes[rowIndex + 1];
    final targetIndex = columnIndex.clamp(0, nextRow.length - 1);
    return <FocusNode>[nextRow[targetIndex]];
  }

  List<FocusNode> _keyboardLeftFallback(int rowIndex, int columnIndex) {
    final row = _keyboardFocusNodes[rowIndex];
    final targetIndex = columnIndex > 0 ? columnIndex - 1 : 0;
    return <FocusNode>[row[targetIndex]];
  }

  List<FocusNode> _keyboardRightFallback(int rowIndex, int columnIndex) {
    final row = _keyboardFocusNodes[rowIndex];
    if (columnIndex >= row.length - 1) {
      return <FocusNode>[row[row.length - 1]];
    }
    return <FocusNode>[row[columnIndex + 1]];
  }

  KeyEventResult _handleNameFieldKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _selectPictureFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _firstKeyFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA) {
      _firstKeyFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _selectPictureFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleNameKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      _erase();
      return KeyEventResult.handled;
    }

    final character = event.character;
    if (character == null || character.isEmpty) {
      return KeyEventResult.ignored;
    }

    final normalized = character.toUpperCase();
    if (!isSupportedTvKeyboardCharacter(normalized)) {
      return KeyEventResult.ignored;
    }

    _append(normalized);
    return KeyEventResult.handled;
  }

  Future<void> _openAvatarPicker() async {
    setState(() => _avatarPickerOpen = true);
    final selectedAvatar = await showProfileAvatarPickerDialog(
      context,
      selectedAvatarLabel: _avatarLabel,
      title: 'Choose Profile Picture',
      subtitle:
          'Browse the CHERIFLIX avatar catalog and press OK to select one.',
      avatarCatalogService: widget.avatarCatalogService,
    );
    if (mounted) {
      setState(() => _avatarPickerOpen = false);
    }
    if (!mounted || selectedAvatar == null || selectedAvatar == _avatarLabel) {
      return;
    }
    setState(() {
      _avatarTouched = true;
      _avatarLabel = selectedAvatar;
    });
  }

  Future<void> _loadSuggestedAvatar() async {
    try {
      final avatarCatalogService =
          widget.avatarCatalogService ?? ProfileAvatarCatalogService.instance;
      final usedAvatarLabels =
          widget.profiles.map((profile) => profile.avatarLabel).toSet();
      final catalog = await avatarCatalogService.loadCatalog();
      final suggested = await avatarCatalogService.pickRandomDefaultAvatarKey(
        usedAvatarLabels: usedAvatarLabels,
      );
      final fallback = suggested ??
          (catalog.defaultOptions.isNotEmpty
              ? catalog.defaultOptions.first.key
              : catalog.allOptions.isNotEmpty
                  ? catalog.allOptions.first.key
                  : _avatarLabel);
      if (!mounted || _avatarTouched) {
        return;
      }
      setState(() => _avatarLabel = fallback);
    } catch (_) {
      // Fall back to placeholder avatar when catalog cannot be resolved.
    }
  }

  void _append(String value) {
    setState(() {
      _name = '$_name$value';
    });
  }

  void _erase() {
    if (_name.isEmpty) {
      return;
    }
    setState(() {
      _name = _name.substring(0, _name.length - 1);
    });
  }

  void _clear() {
    if (_name.isEmpty) {
      return;
    }
    setState(() => _name = '');
  }

  Future<void> _submitCreate() async {
    if (!_canCreate || _submitting) {
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.onCreateProfile(_name.trim(), _avatarLabel);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  bool get _canCreate => _name.trim().isNotEmpty && _avatarLabel.isNotEmpty;

  List<FocusNode> get _keyboardBottomFallbackNodes {
    if (_canCreate) {
      return <FocusNode>[_createButtonFocusNode];
    }
    return <FocusNode>[_cancelButtonFocusNode];
  }

  List<FocusNode> get _actionUpFallbackNodes => _keyboardFocusNodes.last;

  void _ensureVisibleOnFocus(
    FocusNode node,
    bool hasFocus, {
    double alignment = 0.65,
  }) {
    if (!hasFocus || !mounted) {
      return;
    }
    final context = node.context;
    if (context == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOutCubic,
        alignment: alignment,
      );
    });
  }
}
