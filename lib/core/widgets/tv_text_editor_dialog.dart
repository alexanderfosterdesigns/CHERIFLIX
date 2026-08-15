import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/cheriflix_theme.dart';
import 'tv_character_keyboard.dart';
import 'tv_shortcuts.dart';

Future<String?> showTvTextEditorDialog(
  BuildContext context, {
  required String title,
  required String initialValue,
  int maxLength = 32,
  bool numericOnly = false,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    barrierColor: const Color(0x99000000),
    builder: (_) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
      child: _TvTextEditorDialog(
        title: title,
        initialValue: initialValue,
        maxLength: maxLength,
        numericOnly: numericOnly,
      ),
    ),
  );
}

class _TvTextEditorDialog extends StatefulWidget {
  const _TvTextEditorDialog({
    required this.title,
    required this.initialValue,
    required this.maxLength,
    required this.numericOnly,
  });

  final String title;
  final String initialValue;
  final int maxLength;
  final bool numericOnly;

  @override
  State<_TvTextEditorDialog> createState() => _TvTextEditorDialogState();
}

class _TvTextEditorDialogState extends State<_TvTextEditorDialog> {
  List<List<String>> get _rows => widget.numericOnly
      ? const <List<String>>[
          <String>['1', '2', '3'],
          <String>['4', '5', '6'],
          <String>['7', '8', '9'],
          <String>['CLR', '0', 'DEL'],
        ]
      : tvCharacterKeyboardRows;
  late String _value = widget.initialValue;
  late final List<List<FocusNode>> _keyNodes = List.generate(
    _rows.length,
    (row) => List.generate(
      _rows[row].length,
      (column) => FocusNode(debugLabel: 'TvTextEditorKey($row,$column)'),
      growable: false,
    ),
    growable: false,
  );
  late final FocusNode _doneNode = FocusNode(debugLabel: 'TvTextEditorDone');
  late final FocusNode _cancelNode =
      FocusNode(debugLabel: 'TvTextEditorCancel');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _keyNodes.first.first.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (final row in _keyNodes) {
      for (final node in row) {
        node.dispose();
      }
    }
    _doneNode.dispose();
    _cancelNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TvShortcutScope(
      onBack: () => Navigator.of(context).pop(),
      child: Dialog(
        backgroundColor: CheriflixColors.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 18),
        child: Focus(
          onKeyEvent: _handlePhysicalKeyboard,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: widget.numericOnly ? 420 : 760,
              maxHeight: MediaQuery.sizeOf(context).height * 0.94,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      widget.title,
                      style: CheriflixTypography.sectionTitle.copyWith(
                        fontSize: 26,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      key: const ValueKey<String>('tv_text_editor_value'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF101010),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0x44FFFFFF)),
                      ),
                      child: Text(
                        _value.isEmpty ? 'Enter a name' : _value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _value.isEmpty ? Colors.white54 : Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (var row = 0; row < _rows.length; row += 1) ...<Widget>[
                      Row(
                        children: <Widget>[
                          for (var column = 0;
                              column < _rows[row].length;
                              column += 1) ...<Widget>[
                            Expanded(
                              child: TvActionButton(
                                label: _rows[row][column],
                                compact: true,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 4,
                                ),
                                labelStyle: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                                autofocus: false,
                                focusNode: _keyNodes[row][column],
                                onPressed: () => _applyKey(_rows[row][column]),
                                upFallbackNodes: <FocusNode>[
                                  row == 0
                                      ? _keyNodes[row][column]
                                      : _keyNodes[row - 1][column.clamp(
                                          0, _keyNodes[row - 1].length - 1)],
                                ],
                                downFallbackNodes: <FocusNode>[
                                  row == _keyNodes.length - 1
                                      ? (_value.trim().isEmpty
                                          ? _cancelNode
                                          : _doneNode)
                                      : _keyNodes[row + 1][column.clamp(
                                          0, _keyNodes[row + 1].length - 1)],
                                ],
                                leftFallbackNodes: <FocusNode>[
                                  _keyNodes[row][column == 0 ? 0 : column - 1]
                                ],
                                rightFallbackNodes: <FocusNode>[
                                  _keyNodes[row][
                                      column == _keyNodes[row].length - 1
                                          ? column
                                          : column + 1]
                                ],
                                variant: TvButtonVariant.dark,
                              ),
                            ),
                            if (column < _rows[row].length - 1)
                              const SizedBox(width: 8),
                          ],
                          for (var spacer = _rows[row].length;
                              spacer < 6;
                              spacer += 1) ...<Widget>[
                            const Expanded(child: SizedBox.shrink()),
                            if (spacer < 5) const SizedBox(width: 8),
                          ],
                        ],
                      ),
                      if (row < _rows.length - 1) const SizedBox(height: 5),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TvActionButton(
                            label: 'Done',
                            compact: true,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            labelStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                            focusNode: _doneNode,
                            onPressed: _value.trim().isEmpty
                                ? null
                                : () =>
                                    Navigator.of(context).pop(_value.trim()),
                            upFallbackNodes: <FocusNode>[
                              _keyNodes.last.first,
                            ],
                            rightFallbackNodes: <FocusNode>[_cancelNode],
                            variant: TvButtonVariant.light,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TvActionButton(
                            label: 'Cancel',
                            compact: true,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            labelStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                            focusNode: _cancelNode,
                            onPressed: () => Navigator.of(context).pop(),
                            upFallbackNodes: <FocusNode>[
                              _keyNodes.last.last,
                            ],
                            leftFallbackNodes: <FocusNode>[_doneNode],
                            variant: TvButtonVariant.ghost,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _applyKey(String label) {
    setState(() {
      if (label == 'SP') {
        if (_value.length < widget.maxLength) _value += ' ';
      } else if (label == 'DEL') {
        if (_value.isNotEmpty) _value = _value.substring(0, _value.length - 1);
      } else if (label == 'CLR') {
        _value = '';
      } else if (label != '\u2190' &&
          label != '\u2192' &&
          _value.length < widget.maxLength) {
        _value += label;
      }
    });
  }

  KeyEventResult _handlePhysicalKeyboard(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.delete) {
      _applyKey('DEL');
      return KeyEventResult.handled;
    }
    final character = event.character?.toUpperCase();
    if (widget.numericOnly &&
        (character == null || !RegExp(r'^\d$').hasMatch(character))) {
      return KeyEventResult.ignored;
    }
    if (character == null || !isSupportedTvKeyboardCharacter(character)) {
      return KeyEventResult.ignored;
    }
    _applyKey(character);
    return KeyEventResult.handled;
  }
}
