import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/runtime_pressure.dart';
import '../services/tmdb_image_service.dart';
import '../theme/cheriflix_theme.dart';
import '../theme/tv_layout.dart';
import 'bounded_asset_image.dart';
import 'cheriflix_network_image.dart';
import 'profile_avatar.dart';
import 'poster_preview_overlay.dart';

class TvShortcutScope extends StatefulWidget {
  const TvShortcutScope({
    super.key,
    required this.child,
    this.onBack,
    this.autoEnsureVisible = true,
  });

  final Widget child;
  final VoidCallback? onBack;
  final bool autoEnsureVisible;

  @override
  State<TvShortcutScope> createState() => _TvShortcutScopeState();
}

class _TvShortcutScopeState extends State<TvShortcutScope> {
  late final FocusScopeNode _focusScopeNode =
      FocusScopeNode(debugLabel: 'TvShortcutScope');
  FocusNode? _lastFocusedNode;
  bool _pendingEnsure = false;
  FocusNode? _pendingEnsureNode;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_handlePrimaryFocusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handlePrimaryFocusChanged);
    _focusScopeNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      node: _focusScopeNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }

        final key = event.logicalKey;
        if (_isBackKey(key)) {
          widget.onBack?.call();
          return KeyEventResult.handled;
        }

        if (_isActivationKey(key) && _invokeFocusedActivateIntent()) {
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: Shortcuts(
        shortcuts: _tvScopeShortcuts,
        child: Actions(
          actions: <Type, Action<Intent>>{
            _DirectionalIntent: CallbackAction<_DirectionalIntent>(
              onInvoke: (intent) {
                _handleDirectionalIntent(intent.direction);
                return null;
              },
            ),
            _BackIntent: CallbackAction<_BackIntent>(
              onInvoke: (intent) {
                widget.onBack?.call();
                return null;
              },
            ),
          },
          child: FocusTraversalGroup(
            policy: ReadingOrderTraversalPolicy(),
            child: widget.child,
          ),
        ),
      ),
    );
  }

  void _handlePrimaryFocusChanged() {
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (_isFocusableDescendant(primaryFocus)) {
      _lastFocusedNode = primaryFocus;
      if (widget.autoEnsureVisible) {
        _scheduleEnsureVisible(primaryFocus!);
      }
    }
  }

  void _handleDirectionalIntent(TraversalDirection direction) {
    final focusNode = _resolveDirectionalAnchor();
    if (focusNode == null || focusNode.context == null) {
      return;
    }
    final moved = focusNode.focusInDirection(direction);
    if (moved) {
      return;
    }
    _scrollInDirectionForFocusNode(focusNode, direction);
  }

  FocusNode? _resolveDirectionalAnchor() {
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (_isFocusableDescendant(primaryFocus)) {
      return primaryFocus;
    }

    final restoredFocus = _restoreLastFocusedNode();
    if (restoredFocus != null) {
      return restoredFocus;
    }

    return _restoreFirstTraversableDescendant();
  }

  FocusNode? _restoreLastFocusedNode() {
    final lastFocusedNode = _lastFocusedNode;
    if (!_isFocusableDescendant(lastFocusedNode)) {
      return null;
    }
    lastFocusedNode!.requestFocus();
    return lastFocusedNode;
  }

  FocusNode? _restoreFirstTraversableDescendant() {
    for (final candidate in _focusScopeNode.traversalDescendants) {
      if (!_isFocusableDescendant(candidate)) {
        continue;
      }
      _lastFocusedNode = candidate;
      candidate.requestFocus();
      return candidate;
    }
    return null;
  }

  void _scheduleEnsureVisible(FocusNode focusNode) {
    if (_pendingEnsure && _pendingEnsureNode == focusNode) {
      return;
    }
    _pendingEnsure = true;
    _pendingEnsureNode = focusNode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingEnsure = false;
      final targetNode = _pendingEnsureNode;
      final targetContext = targetNode?.context;
      if (targetContext == null ||
          !targetContext.mounted ||
          !_isFocusableDescendant(targetNode)) {
        return;
      }
      _ensureVisibleAcrossScrollables(targetNode!);
    });
  }

  void _ensureVisibleAcrossScrollables(FocusNode focusNode) {
    final context = focusNode.context;
    if (context == null || !context.mounted) {
      return;
    }
    final targetObject = context.findRenderObject();
    if (targetObject is! RenderBox || !targetObject.hasSize) {
      return;
    }

    final handledAxes = <Axis>{};
    ScrollableState? scrollable = Scrollable.maybeOf(context);
    while (scrollable != null) {
      final axis = scrollable.position.axis;
      if (!handledAxes.contains(axis)) {
        _ensureVisibleInScrollable(scrollable, targetObject);
        handledAxes.add(axis);
      }
      scrollable =
          scrollable.context.findAncestorStateOfType<ScrollableState>();
    }
  }

  void _ensureVisibleInScrollable(
    ScrollableState scrollable,
    RenderBox targetObject,
  ) {
    final viewportObject = scrollable.context.findRenderObject();
    if (viewportObject is! RenderBox || !viewportObject.hasSize) {
      return;
    }
    final axis = scrollable.position.axis;
    final targetOrigin = targetObject.localToGlobal(
      Offset.zero,
      ancestor: viewportObject,
    );
    final targetExtent = axis == Axis.horizontal
        ? targetObject.size.width
        : targetObject.size.height;
    final viewportExtent = axis == Axis.horizontal
        ? viewportObject.size.width
        : viewportObject.size.height;
    final targetStart =
        axis == Axis.horizontal ? targetOrigin.dx : targetOrigin.dy;
    final targetEnd = targetStart + targetExtent;
    const safeMargin = 40.0;
    final isFullyVisible =
        targetStart >= safeMargin && targetEnd <= viewportExtent - safeMargin;
    if (isFullyVisible) {
      return;
    }

    final position = scrollable.position;
    final desiredPixels = targetStart < safeMargin
        ? position.pixels + targetStart - safeMargin
        : position.pixels + targetEnd - viewportExtent + safeMargin;
    final clampedPixels = desiredPixels.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((clampedPixels - position.pixels).abs() < 1) {
      return;
    }

    position.animateTo(
      clampedPixels.toDouble(),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollInDirectionForFocusNode(
    FocusNode focusNode,
    TraversalDirection direction,
  ) {
    final context = focusNode.context;
    if (context == null) {
      return;
    }
    final axis = switch (direction) {
      TraversalDirection.left => Axis.horizontal,
      TraversalDirection.right => Axis.horizontal,
      TraversalDirection.up => Axis.vertical,
      TraversalDirection.down => Axis.vertical,
    };
    final scrollable = _nearestScrollableForAxis(context, axis);
    if (scrollable == null) {
      return;
    }
    final viewportObject = scrollable.context.findRenderObject();
    final targetObject = context.findRenderObject();
    if (viewportObject is! RenderBox ||
        targetObject is! RenderBox ||
        !viewportObject.hasSize ||
        !targetObject.hasSize) {
      return;
    }

    final stepExtent = axis == Axis.horizontal
        ? targetObject.size.width
        : targetObject.size.height;
    final fallbackStep = (axis == Axis.horizontal
            ? viewportObject.size.width
            : viewportObject.size.height) *
        0.6;
    final step = stepExtent > 0 ? stepExtent + 24.0 : fallbackStep;
    final directionSign = (direction == TraversalDirection.left ||
            direction == TraversalDirection.up)
        ? -1.0
        : 1.0;

    final position = scrollable.position;
    final desiredPixels = (position.pixels + (step * directionSign)).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((desiredPixels - position.pixels).abs() < 1) {
      return;
    }

    position
        .animateTo(
      desiredPixels.toDouble(),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    )
        .then((_) {
      if (!mounted) {
        return;
      }
      focusNode.focusInDirection(direction);
    });
  }

  ScrollableState? _nearestScrollableForAxis(
    BuildContext context,
    Axis axis,
  ) {
    ScrollableState? scrollable = Scrollable.maybeOf(context);
    while (scrollable != null) {
      if (scrollable.position.axis == axis) {
        return scrollable;
      }
      scrollable =
          scrollable.context.findAncestorStateOfType<ScrollableState>();
    }
    return null;
  }

  bool _isFocusableDescendant(FocusNode? focusNode) {
    if (focusNode == null ||
        focusNode == _focusScopeNode ||
        !focusNode.canRequestFocus ||
        focusNode.context == null) {
      return false;
    }
    return focusNode.ancestors.contains(_focusScopeNode);
  }

  bool _invokeFocusedActivateIntent() {
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (!_isFocusableDescendant(primaryFocus)) {
      return false;
    }
    final focusContext = primaryFocus?.context;
    if (focusContext == null) {
      return false;
    }
    try {
      Actions.maybeInvoke(focusContext, const ActivateIntent());
      return true;
    } catch (_) {
      return false;
    }
  }
}

enum TvButtonVariant {
  light,
  dark,
  media,
  ghost,
  danger,
}

enum TvNavPillStyle {
  pill,
  topBarUnderline,
}

enum TvIconButtonStyle {
  standard,
  topBarPlain,
}

enum TvProfileButtonStyle {
  pill,
  topBarCompact,
}

class TvActionButton extends StatefulWidget {
  const TvActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.autofocus = false,
    this.filled = false,
    this.compact = false,
    this.variant,
    this.selected = false,
    this.focusNode,
    this.downFallbackNodes = const <FocusNode>[],
    this.upFallbackNodes = const <FocusNode>[],
    this.leftFallbackNodes = const <FocusNode>[],
    this.rightFallbackNodes = const <FocusNode>[],
    this.onFocusChanged,
    this.ensureVisibleOnFocus = true,
    this.borderRadius,
    this.padding,
    this.labelStyle,
    this.iconSize,
    this.iconGap,
    this.focusScale,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool autofocus;
  final bool filled;
  final bool compact;
  final TvButtonVariant? variant;
  final bool selected;
  final FocusNode? focusNode;
  final List<FocusNode> downFallbackNodes;
  final List<FocusNode> upFallbackNodes;
  final List<FocusNode> leftFallbackNodes;
  final List<FocusNode> rightFallbackNodes;
  final ValueChanged<bool>? onFocusChanged;
  final bool ensureVisibleOnFocus;
  final double? borderRadius;
  final EdgeInsetsGeometry? padding;
  final TextStyle? labelStyle;
  final double? iconSize;
  final double? iconGap;
  final double? focusScale;

  @override
  State<TvActionButton> createState() => _TvActionButtonState();
}

class _TvActionButtonState extends State<TvActionButton> {
  bool _focused = false;
  late final FocusNode _focusNode =
      FocusNode(debugLabel: 'TvActionButton(${widget.label})');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onPressed != null;
    final focusNode = widget.focusNode ?? _focusNode;
    final resolvedVariant = widget.variant ??
        (widget.selected
            ? TvButtonVariant.light
            : widget.filled
                ? TvButtonVariant.light
                : widget.compact
                    ? TvButtonVariant.dark
                    : TvButtonVariant.ghost);
    final style = _buttonStyle(
      variant: resolvedVariant,
      focused: _focused,
      enabled: isEnabled,
      selected: widget.selected,
    );
    final resolvedBorderRadius =
        widget.borderRadius ?? (widget.compact ? 14 : 18).toDouble();
    final resolvedPadding = widget.padding ??
        (widget.compact
            ? const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 10,
              )
            : const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 13,
              ));
    final resolvedLabelStyle = widget.labelStyle ?? CheriflixTypography.button;
    final resolvedIconSize = widget.iconSize ?? 18;
    final resolvedIconGap = widget.iconGap ?? 8;
    final resolvedFocusScale = widget.focusScale ?? 1.04;

    return Shortcuts(
      shortcuts: _tvActionShortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              widget.onPressed?.call();
              return null;
            },
          ),
          _DirectionalFallbackIntent:
              CallbackAction<_DirectionalFallbackIntent>(
            onInvoke: (intent) {
              _moveFocusWithFallback(
                focusNode,
                intent.direction,
                leftFallbackNodes: widget.leftFallbackNodes,
                rightFallbackNodes: widget.rightFallbackNodes,
                downFallbackNodes: widget.downFallbackNodes,
                upFallbackNodes: widget.upFallbackNodes,
              );
              return null;
            },
          ),
        },
        child: FocusableActionDetector(
          focusNode: focusNode,
          autofocus: isEnabled && widget.autofocus,
          onFocusChange: widget.onFocusChanged,
          onShowFocusHighlight: (value) {
            setState(() => _focused = value);
            if (value && widget.ensureVisibleOnFocus) {
              _ensureVisible(context);
            }
          },
          child: AnimatedScale(
            scale: _focused ? resolvedFocusScale : 1,
            duration: const Duration(milliseconds: 140),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: style.backgroundColor,
                borderRadius: BorderRadius.circular(resolvedBorderRadius),
                border: Border.all(
                  color: style.borderColor,
                  width: style.borderWidth,
                ),
                boxShadow: style.shadows,
              ),
              child: InkWell(
                onTap: isEnabled
                    ? () {
                        focusNode.requestFocus();
                        widget.onPressed?.call();
                      }
                    : null,
                borderRadius: BorderRadius.circular(resolvedBorderRadius),
                child: Padding(
                  padding: resolvedPadding,
                  child: widget.compact
                      ? Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              widget.label,
                              style: resolvedLabelStyle.copyWith(
                                color: isEnabled
                                    ? style.foregroundColor
                                    : CheriflixColors.textSecondary,
                                fontSize: widget.labelStyle?.fontSize ?? 13,
                                letterSpacing: 0,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            if (widget.icon != null) ...<Widget>[
                              Icon(
                                widget.icon,
                                size: resolvedIconSize,
                                color: style.foregroundColor,
                              ),
                              SizedBox(width: resolvedIconGap),
                            ],
                            Flexible(
                              fit: FlexFit.loose,
                              child: Text(
                                widget.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: resolvedLabelStyle.copyWith(
                                  color: isEnabled
                                      ? style.foregroundColor
                                      : CheriflixColors.textSecondary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
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

class TvNavPillButton extends StatelessWidget {
  const TvNavPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.style = TvNavPillStyle.pill,
    this.focusNode,
    this.downFallbackNodes = const <FocusNode>[],
    this.upFallbackNodes = const <FocusNode>[],
    this.leftFallbackNodes = const <FocusNode>[],
    this.rightFallbackNodes = const <FocusNode>[],
    this.onFocusChanged,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final TvNavPillStyle style;
  final FocusNode? focusNode;
  final List<FocusNode> downFallbackNodes;
  final List<FocusNode> upFallbackNodes;
  final List<FocusNode> leftFallbackNodes;
  final List<FocusNode> rightFallbackNodes;
  final ValueChanged<bool>? onFocusChanged;

  @override
  Widget build(BuildContext context) {
    if (style == TvNavPillStyle.topBarUnderline) {
      return _TvTopBarNavButton(
        label: label,
        onPressed: onPressed,
        active: active,
        focusNode: focusNode,
        downFallbackNodes: downFallbackNodes,
        upFallbackNodes: upFallbackNodes,
        leftFallbackNodes: leftFallbackNodes,
        rightFallbackNodes: rightFallbackNodes,
        onFocusChanged: onFocusChanged,
      );
    }

    return TvActionButton(
      label: label,
      onPressed: onPressed,
      selected: active,
      variant: active ? TvButtonVariant.light : TvButtonVariant.ghost,
      focusNode: focusNode,
      downFallbackNodes: downFallbackNodes,
      upFallbackNodes: upFallbackNodes,
      leftFallbackNodes: leftFallbackNodes,
      rightFallbackNodes: rightFallbackNodes,
      onFocusChanged: onFocusChanged,
    );
  }
}

class _TvTopBarNavButton extends StatefulWidget {
  const _TvTopBarNavButton({
    required this.label,
    required this.onPressed,
    required this.active,
    this.focusNode,
    this.downFallbackNodes = const <FocusNode>[],
    this.upFallbackNodes = const <FocusNode>[],
    this.leftFallbackNodes = const <FocusNode>[],
    this.rightFallbackNodes = const <FocusNode>[],
    this.onFocusChanged,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final FocusNode? focusNode;
  final List<FocusNode> downFallbackNodes;
  final List<FocusNode> upFallbackNodes;
  final List<FocusNode> leftFallbackNodes;
  final List<FocusNode> rightFallbackNodes;
  final ValueChanged<bool>? onFocusChanged;

  @override
  State<_TvTopBarNavButton> createState() => _TvTopBarNavButtonState();
}

class _TvTopBarNavButtonState extends State<_TvTopBarNavButton> {
  bool _focused = false;
  late final FocusNode _focusNode =
      FocusNode(debugLabel: 'TvActionButton(${widget.label})');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = CheriflixTvLayout.of(context);
    final isEnabled = widget.onPressed != null;
    final focusNode = widget.focusNode ?? _focusNode;
    final labelColor = widget.active || _focused
        ? CheriflixColors.textPrimary
        : const Color(0xFFD7D7D7);
    final labelStyle = CheriflixTypography.button.copyWith(
      color: isEnabled ? labelColor : CheriflixColors.textSecondary,
      fontSize: layout.value(compact: 13, standard: 14, wide: 15),
      fontWeight: widget.active ? FontWeight.w700 : FontWeight.w500,
      letterSpacing: 0,
    );
    final underlineWidth = (() {
      final textPainter = TextPainter(
        text: TextSpan(text: widget.label, style: labelStyle),
        maxLines: 1,
        textDirection: Directionality.of(context),
      )..layout();
      return textPainter.width;
    })();
    final underlineColor = widget.active
        ? CheriflixColors.accentRed
        : _focused
            ? const Color(0x88FFFFFF)
            : Colors.transparent;
    return Shortcuts(
      shortcuts: _tvActionShortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              widget.onPressed?.call();
              return null;
            },
          ),
          _DirectionalFallbackIntent:
              CallbackAction<_DirectionalFallbackIntent>(
            onInvoke: (intent) {
              _moveFocusWithFallback(
                focusNode,
                intent.direction,
                leftFallbackNodes: widget.leftFallbackNodes,
                rightFallbackNodes: widget.rightFallbackNodes,
                downFallbackNodes: widget.downFallbackNodes,
                upFallbackNodes: widget.upFallbackNodes,
              );
              return null;
            },
          ),
        },
        child: FocusableActionDetector(
          focusNode: focusNode,
          onFocusChange: widget.onFocusChanged,
          onShowFocusHighlight: (value) {
            if (_focused != value) {
              setState(() => _focused = value);
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: isEnabled
                ? () {
                    focusNode.requestFocus();
                    widget.onPressed?.call();
                  }
                : null,
            child: SizedBox(
              height: layout.value(compact: 42, standard: 46, wide: 52),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  6,
                  layout.value(compact: 8, standard: 10, wide: 12),
                  6,
                  layout.value(compact: 6, standard: 7, wide: 8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.label,
                      style: labelStyle,
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOutCubic,
                      height:
                          layout.value(compact: 2.5, standard: 2.75, wide: 3),
                      width: underlineWidth,
                      decoration: BoxDecoration(
                        color: underlineColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
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
}

class TvIconButton extends StatefulWidget {
  const TvIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.autofocus = false,
    this.focusNode,
    this.size = 52,
    this.iconSize = 24,
    this.borderRadius,
    this.backgroundColor,
    this.foregroundColor,
    this.style = TvIconButtonStyle.standard,
    this.downFallbackNodes = const <FocusNode>[],
    this.upFallbackNodes = const <FocusNode>[],
    this.leftFallbackNodes = const <FocusNode>[],
    this.rightFallbackNodes = const <FocusNode>[],
    this.immediateActivation = false,
    this.onFocusChanged,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool autofocus;
  final FocusNode? focusNode;
  final double size;
  final double iconSize;
  final double? borderRadius;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final TvIconButtonStyle style;
  final List<FocusNode> downFallbackNodes;
  final List<FocusNode> upFallbackNodes;
  final List<FocusNode> leftFallbackNodes;
  final List<FocusNode> rightFallbackNodes;
  final bool immediateActivation;
  final ValueChanged<bool>? onFocusChanged;

  @override
  State<TvIconButton> createState() => _TvIconButtonState();
}

class _TvIconButtonState extends State<TvIconButton> {
  bool _focused = false;
  late final FocusNode _focusNode =
      FocusNode(debugLabel: 'TvIconButton(${widget.label})');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onPressed != null;
    final focusNode = widget.focusNode ?? _focusNode;
    final resolvedBackgroundColor = widget.backgroundColor ??
        (widget.style == TvIconButtonStyle.topBarPlain
            ? Colors.transparent
            : const Color(0xFF111111));
    final resolvedForegroundColor = widget.foregroundColor ??
        (isEnabled
            ? CheriflixColors.textPrimary
            : CheriflixColors.textSecondary);
    final resolvedBorderRadius = widget.borderRadius;
    if (widget.immediateActivation) {
      return _buildImmediateButton(
        context: context,
        focusNode: focusNode,
        isEnabled: isEnabled,
        resolvedBackgroundColor: resolvedBackgroundColor,
        resolvedForegroundColor: resolvedForegroundColor,
        resolvedBorderRadius: resolvedBorderRadius,
      );
    }
    return Shortcuts(
      shortcuts: _tvActionShortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              widget.onPressed?.call();
              return null;
            },
          ),
          _DirectionalFallbackIntent:
              CallbackAction<_DirectionalFallbackIntent>(
            onInvoke: (intent) {
              _moveFocusWithFallback(
                focusNode,
                intent.direction,
                leftFallbackNodes: widget.leftFallbackNodes,
                rightFallbackNodes: widget.rightFallbackNodes,
                downFallbackNodes: widget.downFallbackNodes,
                upFallbackNodes: widget.upFallbackNodes,
              );
              return null;
            },
          ),
        },
        child: FocusableActionDetector(
          focusNode: focusNode,
          autofocus: isEnabled && widget.autofocus,
          onFocusChange: widget.onFocusChanged,
          onShowFocusHighlight: (value) {
            setState(() => _focused = value);
            if (value) {
              _ensureVisible(context);
            }
          },
          child: Tooltip(
            message: widget.label,
            textStyle: const TextStyle(
              fontFamily: CheriflixTypography.sansFamily,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.0,
            ),
            child: AnimatedScale(
              scale: _focused ? 1.05 : 1,
              duration: const Duration(milliseconds: 140),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: resolvedBackgroundColor,
                  shape: resolvedBorderRadius == null
                      ? (widget.style == TvIconButtonStyle.topBarPlain
                          ? BoxShape.rectangle
                          : BoxShape.circle)
                      : BoxShape.rectangle,
                  borderRadius: resolvedBorderRadius == null
                      ? (widget.style == TvIconButtonStyle.topBarPlain
                          ? BorderRadius.circular(8)
                          : null)
                      : BorderRadius.circular(resolvedBorderRadius),
                  border: Border.all(
                    color: widget.style == TvIconButtonStyle.topBarPlain
                        ? (_focused
                            ? const Color(0x52FFFFFF)
                            : Colors.transparent)
                        : (_focused
                            ? CheriflixColors.focus
                            : const Color(0x26FFFFFF)),
                    width: widget.style == TvIconButtonStyle.topBarPlain
                        ? 1
                        : (_focused ? 3 : 1.2),
                  ),
                  boxShadow: widget.style == TvIconButtonStyle.topBarPlain
                      ? const <BoxShadow>[]
                      : <BoxShadow>[
                          const BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 18,
                            offset: Offset(0, 10),
                          ),
                          if (_focused)
                            const BoxShadow(
                              color: Color(0x26FFFFFF),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                        ],
                ),
                child: InkWell(
                  onTap: isEnabled
                      ? () {
                          focusNode.requestFocus();
                          widget.onPressed?.call();
                        }
                      : null,
                  customBorder: resolvedBorderRadius == null
                      ? (widget.style == TvIconButtonStyle.topBarPlain
                          ? RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            )
                          : const CircleBorder())
                      : RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(resolvedBorderRadius),
                        ),
                  child: SizedBox(
                    width: widget.size,
                    height: widget.size,
                    child: Icon(
                      widget.icon,
                      color: resolvedForegroundColor,
                      size: widget.iconSize,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImmediateButton({
    required BuildContext context,
    required FocusNode focusNode,
    required bool isEnabled,
    required Color resolvedBackgroundColor,
    required Color resolvedForegroundColor,
    required double? resolvedBorderRadius,
  }) {
    return Focus(
      focusNode: focusNode,
      autofocus: isEnabled && widget.autofocus,
      canRequestFocus: isEnabled,
      onFocusChange: (value) {
        if (_focused != value) {
          setState(() => _focused = value);
        }
        widget.onFocusChanged?.call(value);
        if (value) {
          _ensureVisible(context);
        }
      },
      onKeyEvent: (node, event) {
        if (!isEnabled || event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }

        final key = event.logicalKey;
        if (_isActivationKey(key)) {
          widget.onPressed?.call();
          return KeyEventResult.handled;
        }

        final direction = _directionForKey(key);
        if (direction == null) {
          return KeyEventResult.ignored;
        }

        _moveFocusWithFallback(
          focusNode,
          direction,
          leftFallbackNodes: widget.leftFallbackNodes,
          rightFallbackNodes: widget.rightFallbackNodes,
          downFallbackNodes: widget.downFallbackNodes,
          upFallbackNodes: widget.upFallbackNodes,
        );
        return KeyEventResult.handled;
      },
      child: Tooltip(
        message: widget.label,
        textStyle: const TextStyle(
          fontFamily: CheriflixTypography.sansFamily,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 1.0,
        ),
        child: AnimatedScale(
          scale: _focused ? 1.05 : 1,
          duration: const Duration(milliseconds: 140),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: resolvedBackgroundColor,
              shape: resolvedBorderRadius == null
                  ? (widget.style == TvIconButtonStyle.topBarPlain
                      ? BoxShape.rectangle
                      : BoxShape.circle)
                  : BoxShape.rectangle,
              borderRadius: resolvedBorderRadius == null
                  ? (widget.style == TvIconButtonStyle.topBarPlain
                      ? BorderRadius.circular(8)
                      : null)
                  : BorderRadius.circular(resolvedBorderRadius),
              border: Border.all(
                color: widget.style == TvIconButtonStyle.topBarPlain
                    ? (_focused ? const Color(0x52FFFFFF) : Colors.transparent)
                    : (_focused
                        ? CheriflixColors.focus
                        : const Color(0x26FFFFFF)),
                width: widget.style == TvIconButtonStyle.topBarPlain
                    ? 1
                    : (_focused ? 3 : 1.2),
              ),
              boxShadow: widget.style == TvIconButtonStyle.topBarPlain
                  ? const <BoxShadow>[]
                  : <BoxShadow>[
                      const BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 18,
                        offset: Offset(0, 10),
                      ),
                      if (_focused)
                        const BoxShadow(
                          color: Color(0x26FFFFFF),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                    ],
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: isEnabled
                  ? () {
                      widget.onPressed?.call();
                      focusNode.requestFocus();
                    }
                  : null,
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: Icon(
                  widget.icon,
                  color: resolvedForegroundColor,
                  size: widget.iconSize,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TvProfileButton extends StatefulWidget {
  const TvProfileButton({
    super.key,
    required this.avatarLabel,
    required this.onPressed,
    this.autofocus = false,
    this.style = TvProfileButtonStyle.pill,
    this.focusNode,
    this.downFallbackNodes = const <FocusNode>[],
    this.upFallbackNodes = const <FocusNode>[],
    this.leftFallbackNodes = const <FocusNode>[],
    this.rightFallbackNodes = const <FocusNode>[],
    this.onFocusChanged,
  });

  final String avatarLabel;
  final VoidCallback? onPressed;
  final bool autofocus;
  final TvProfileButtonStyle style;
  final FocusNode? focusNode;
  final List<FocusNode> downFallbackNodes;
  final List<FocusNode> upFallbackNodes;
  final List<FocusNode> leftFallbackNodes;
  final List<FocusNode> rightFallbackNodes;
  final ValueChanged<bool>? onFocusChanged;

  @override
  State<TvProfileButton> createState() => _TvProfileButtonState();
}

class _TvProfileButtonState extends State<TvProfileButton> {
  bool _focused = false;
  late final FocusNode _focusNode =
      FocusNode(debugLabel: 'TvProfileButton(${widget.avatarLabel})');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onPressed != null;
    final focusNode = widget.focusNode ?? _focusNode;
    final compact = widget.style == TvProfileButtonStyle.topBarCompact;
    final layout = CheriflixTvLayout.of(context);
    final compactPadding = layout.topBarCompactProfilePadding;
    final compactOuterSize = layout.topBarCompactProfileOuterSize;
    final compactAvatarSize = layout.topBarCompactProfileAvatarSize;
    return Shortcuts(
      shortcuts: _tvActionShortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              widget.onPressed?.call();
              return null;
            },
          ),
          _DirectionalFallbackIntent:
              CallbackAction<_DirectionalFallbackIntent>(
            onInvoke: (intent) {
              _moveFocusWithFallback(
                focusNode,
                intent.direction,
                leftFallbackNodes: widget.leftFallbackNodes,
                rightFallbackNodes: widget.rightFallbackNodes,
                downFallbackNodes: widget.downFallbackNodes,
                upFallbackNodes: widget.upFallbackNodes,
              );
              return null;
            },
          ),
        },
        child: FocusableActionDetector(
          focusNode: focusNode,
          autofocus: isEnabled && widget.autofocus,
          onFocusChange: widget.onFocusChanged,
          onShowFocusHighlight: (value) {
            setState(() => _focused = value);
            if (value) {
              _ensureVisible(context);
            }
          },
          child: AnimatedScale(
            scale: _focused && !compact ? 1.04 : 1,
            duration: const Duration(milliseconds: 140),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: compact ? Colors.transparent : const Color(0xFF181818),
                borderRadius: BorderRadius.circular(compact ? 8 : 18),
                border: Border.all(
                  color: compact
                      ? (_focused
                          ? const Color(0x52FFFFFF)
                          : Colors.transparent)
                      : (_focused
                          ? CheriflixColors.focus
                          : const Color(0x26FFFFFF)),
                  width: compact ? 1 : (_focused ? 3 : 1.2),
                ),
                boxShadow: compact
                    ? const <BoxShadow>[]
                    : <BoxShadow>[
                        const BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 18,
                          offset: Offset(0, 10),
                        ),
                        if (_focused)
                          const BoxShadow(
                            color: Color(0x22FFFFFF),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                      ],
              ),
              child: InkWell(
                onTap: isEnabled
                    ? () {
                        focusNode.requestFocus();
                        widget.onPressed?.call();
                      }
                    : null,
                borderRadius: BorderRadius.circular(compact ? 8 : 18),
                child: Padding(
                  padding: compact
                      ? compactPadding
                      : const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: compact ? compactOuterSize : 36,
                        height: compact ? compactOuterSize : 36,
                        decoration: BoxDecoration(
                          color: null,
                          borderRadius:
                              BorderRadius.circular(compact ? 8 : 999),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(compact ? 4 : 0),
                          child: CheriflixProfileAvatar(
                            avatarLabel: widget.avatarLabel,
                            width: compact ? compactAvatarSize : 36,
                            height: compact ? compactAvatarSize : 36,
                            shape:
                                compact ? BoxShape.rectangle : BoxShape.circle,
                            borderRadius:
                                compact ? BorderRadius.circular(6) : null,
                            fallbackTextStyle: const TextStyle(
                              color: CheriflixColors.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      if (!compact) ...<Widget>[
                        const SizedBox(width: 12),
                        Text(
                          'PROFILES',
                          style: CheriflixTypography.button.copyWith(
                            color: isEnabled
                                ? CheriflixColors.textPrimary
                                : CheriflixColors.textSecondary,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ] else ...<Widget>[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.arrow_drop_down_rounded,
                          color: isEnabled
                              ? CheriflixColors.textPrimary
                              : CheriflixColors.textSecondary,
                          size: layout.topBarCompactArrowSize,
                        ),
                      ],
                    ],
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

class TvPosterButton extends StatefulWidget {
  const TvPosterButton({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onPressed,
    this.onPlay,
    this.onOpenInfo,
    this.imageUrl,
    this.autofocus = false,
    this.width = 210,
    this.posterHeight = 280,
    this.saved = false,
    this.onToggleSaved,
    this.focusNode,
    this.downFallbackNodes = const <FocusNode>[],
    this.upFallbackNodes = const <FocusNode>[],
    this.leftFallbackNodes = const <FocusNode>[],
    this.rightFallbackNodes = const <FocusNode>[],
    this.onFocusChanged,
    this.expandOnFocus = false,
    this.autoplayPreviewEnabled = false,
    this.autoplayPreviewMuted = true,
    this.previewLoader,
    this.expandedImageUrl,
    this.expandedWidth = 352,
    this.expandedPosterHeight = 198,
    this.ensureVisibleOnFocus = true,
    this.alignment = Alignment.bottomLeft,
    this.reserveExpandedSpace = true,
    this.overlayExpandedDetails = false,
    this.previewLoadDelay = const Duration(milliseconds: 1800),
    this.focusTransitionDuration = const Duration(milliseconds: 180),
    this.showFocusedGlow = true,
    this.posterSurfaceKey,
    this.posterBottomOverlay,
    this.onDirectionalFocus,
  });

  final String title;
  final String subtitle;
  final String? imageUrl;
  final VoidCallback onPressed;
  final VoidCallback? onPlay;
  final VoidCallback? onOpenInfo;
  final bool autofocus;
  final double width;
  final double posterHeight;
  final bool saved;
  final VoidCallback? onToggleSaved;
  final FocusNode? focusNode;
  final List<FocusNode> downFallbackNodes;
  final List<FocusNode> upFallbackNodes;
  final List<FocusNode> leftFallbackNodes;
  final List<FocusNode> rightFallbackNodes;
  final void Function(bool focused, LayerLink layerLink, Size previewSize)?
      onFocusChanged;
  final bool expandOnFocus;
  final bool autoplayPreviewEnabled;
  final bool autoplayPreviewMuted;
  final Future<Uri?> Function()? previewLoader;
  final String? expandedImageUrl;
  final double expandedWidth;
  final double expandedPosterHeight;
  final bool ensureVisibleOnFocus;
  final Alignment alignment;
  final bool reserveExpandedSpace;
  final bool overlayExpandedDetails;
  final Duration previewLoadDelay;
  final Duration focusTransitionDuration;
  final bool showFocusedGlow;
  final Key? posterSurfaceKey;
  final Widget? posterBottomOverlay;
  final KeyEventResult Function(TraversalDirection direction)?
      onDirectionalFocus;

  @override
  State<TvPosterButton> createState() => _TvPosterButtonState();
}

class _TvPosterButtonState extends State<TvPosterButton> {
  bool _focused = false;
  bool _hovered = false;
  final OverlayPortalController _overlayController = OverlayPortalController();
  late final FocusNode _focusNode =
      FocusNode(debugLabel: 'TvPosterButton(${widget.title})');
  final LayerLink _previewLayerLink = LayerLink();
  Timer? _previewLoadTimer;
  Uri? _previewUri;
  bool _loadingPreview = false;
  bool _requestedPreview = false;
  int _previewRequestId = 0;
  int _selectedAction = -1;

  @override
  void initState() {
    super.initState();
    CheriflixRuntimePressureController.instance.addListener(
      _handleRuntimePressureChanged,
    );
  }

  @override
  void didUpdateWidget(covariant TvPosterButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.expandOnFocus && oldWidget.expandOnFocus) {
      _overlayController.hide();
    }
    if (oldWidget.autoplayPreviewEnabled == widget.autoplayPreviewEnabled &&
        oldWidget.autoplayPreviewMuted == widget.autoplayPreviewMuted) {
      return;
    }

    _clearPreviewState();
    final shouldReloadPreview = widget.expandOnFocus &&
        widget.autoplayPreviewEnabled &&
        !CheriflixRuntimePressureController
            .instance.previewSuspendedForSession &&
        widget.previewLoader != null &&
        _focused;
    if (shouldReloadPreview) {
      _schedulePreviewLoad();
    }
  }

  @override
  void dispose() {
    CheriflixRuntimePressureController.instance.removeListener(
      _handleRuntimePressureChanged,
    );
    _previewRequestId += 1;
    _previewLoadTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focusNode = widget.focusNode ?? _focusNode;
    final devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final expanded = widget.expandOnFocus && _focused;
    final motionDisabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final transitionDuration =
        motionDisabled ? Duration.zero : widget.focusTransitionDuration;
    final semanticLabel = <String>[
      widget.title,
      if (widget.subtitle.trim().isNotEmpty) widget.subtitle,
      if (widget.saved) 'Saved to My List',
    ].join('. ');

    return Shortcuts(
      shortcuts: _tvPosterShortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              _activateSelectedAction();
              return null;
            },
          ),
          _SecondaryIntent: CallbackAction<_SecondaryIntent>(
            onInvoke: (intent) {
              widget.onToggleSaved?.call();
              return null;
            },
          ),
          _DirectionalFallbackIntent:
              CallbackAction<_DirectionalFallbackIntent>(
            onInvoke: (intent) {
              _moveFocusWithFallback(
                focusNode,
                intent.direction,
                leftFallbackNodes: widget.leftFallbackNodes,
                rightFallbackNodes: widget.rightFallbackNodes,
                downFallbackNodes: widget.downFallbackNodes,
                upFallbackNodes: widget.upFallbackNodes,
              );
              return null;
            },
          ),
        },
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            final direction = _directionForKey(event.logicalKey);
            if (direction == null) {
              return KeyEventResult.ignored;
            }
            final actionResult = _handleActionDirection(direction, expanded);
            if (actionResult != KeyEventResult.ignored) return actionResult;
            if (widget.onDirectionalFocus == null) {
              return KeyEventResult.ignored;
            }
            return widget.onDirectionalFocus!(direction);
          },
          child: FocusableActionDetector(
            focusNode: focusNode,
            autofocus: widget.autofocus,
            onFocusChange: (value) => _handleFocusChanged(value, context),
            onShowHoverHighlight: (value) {
              if (_hovered != value) {
                setState(() => _hovered = value);
              }
            },
            child: Semantics(
              button: true,
              selected: _focused,
              label: semanticLabel,
              child: RepaintBoundary(
                child: SizedBox(
                  width: widget.width,
                  height: double.infinity,
                  child: OverlayPortal(
                    controller: _overlayController,
                    overlayChildBuilder: (overlayContext) {
                      if (!expanded) {
                        return const SizedBox.shrink();
                      }
                      return CompositedTransformFollower(
                        link: _previewLayerLink,
                        showWhenUnlinked: false,
                        targetAnchor: Alignment.topLeft,
                        followerAnchor: Alignment.topLeft,
                        child: IgnorePointer(
                          child: Material(
                            type: MaterialType.transparency,
                            child: _buildPosterCardVisual(
                              context: overlayContext,
                              expanded: true,
                              devicePixelRatio: devicePixelRatio,
                              transitionDuration: transitionDuration,
                              showCollapsedDetails: false,
                            ),
                          ),
                        ),
                      );
                    },
                    child: CompositedTransformTarget(
                      link: _previewLayerLink,
                      child: InkWell(
                        onTap: () {
                          focusNode.requestFocus();
                          widget.onPressed();
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: _buildPosterCardVisual(
                          context: context,
                          expanded: false,
                          devicePixelRatio: devicePixelRatio,
                          transitionDuration: transitionDuration,
                          showCollapsedDetails: !expanded,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPosterCardVisual({
    required BuildContext context,
    required bool expanded,
    required double devicePixelRatio,
    required Duration transitionDuration,
    required bool showCollapsedDetails,
  }) {
    final cardWidth = expanded ? widget.expandedWidth : widget.width;
    final posterHeight =
        expanded ? widget.expandedPosterHeight : widget.posterHeight;
    final previewAllowed = widget.autoplayPreviewEnabled &&
        cheriflixTrailerPreviewsSupported &&
        !CheriflixRuntimePressureController.instance.previewSuspendedForSession;
    final surfaceImageUrl = expanded
        ? (widget.expandedImageUrl ?? widget.imageUrl)
        : widget.imageUrl;
    final borderColor = _focused
        ? CheriflixColors.focus
        : _hovered
            ? const Color(0x80FFFFFF)
            : Colors.transparent;
    final borderWidth = _focused ? 3.0 : _hovered ? 1.5 : 0.0;

    return SizedBox(
      width: cardWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AnimatedContainer(
            key: expanded ? null : widget.posterSurfaceKey,
            duration: transitionDuration,
            curve: Curves.easeOutCubic,
            width: cardWidth,
            height: posterHeight,
            decoration: BoxDecoration(
              color: CheriflixColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: borderWidth),
              boxShadow: <BoxShadow>[
                const BoxShadow(
                  color: Color(0x38000000),
                  blurRadius: 14,
                  offset: Offset(0, 10),
                ),
                if (_focused && widget.showFocusedGlow)
                  const BoxShadow(
                    color: Color(0x22FFFFFF),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _PosterArtworkSurface(
                  imageUrl: surfaceImageUrl,
                  width: cardWidth,
                  height: posterHeight,
                  devicePixelRatio: devicePixelRatio,
                  borderRadius: 11,
                ),
                if (expanded && previewAllowed && _previewUri != null)
                  BackdropTrailerPreview(
                    previewUri: _previewUri,
                    mode: TrailerPreviewMode.card,
                    borderRadius: 11,
                  ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      gradient: expanded
                          ? const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Color(0x00000000),
                                Color(0x04000000),
                                Color(0x1C000000),
                                Color(0x7A000000),
                              ],
                              stops: <double>[0, 0.44, 0.74, 1],
                            )
                          : const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Color(0x06000000),
                                Color(0x14000000),
                                Color(0x64000000),
                              ],
                            ),
                    ),
                  ),
                ),
                if (surfaceImageUrl == null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(36),
                      child: Image(
                        image: boundedAssetImageProvider(
                          context,
                          CheriflixAssets.icon,
                          logicalWidth: cardWidth,
                          logicalHeight: posterHeight,
                          maxDecodeWidth: 768,
                          maxDecodeHeight: 768,
                        ),
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.low,
                      ),
                    ),
                  ),
                if (expanded && previewAllowed && _loadingPreview)
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(11)),
                        color: Color(0x44000000),
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: _SaveBadge(saved: widget.saved),
                ),
                if (widget.posterBottomOverlay != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: widget.posterBottomOverlay!,
                  ),
                if (expanded && widget.overlayExpandedDetails)
                  Positioned(
                    left: 22,
                    right: 22,
                    bottom: 22,
                    child: _ExpandedPosterDetails(
                      title: widget.title,
                      subtitle: widget.subtitle,
                      saved: widget.saved,
                      hasSaveAction: widget.onToggleSaved != null,
                      selectedAction: _selectedAction,
                    ),
                  ),
                // Keep the expanded actions in the card's semantic/widget
                // subtree for deterministic testing while the painted copy is
                // promoted to the overlay above neighbouring rail cards.
                if (!expanded && widget.overlayExpandedDetails && _focused)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: ExcludeSemantics(
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: 0,
                          child: _ExpandedPosterDetails(
                            title: widget.title,
                            subtitle: widget.subtitle,
                            saved: widget.saved,
                            hasSaveAction: widget.onToggleSaved != null,
                            selectedAction: _selectedAction,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!(expanded && widget.overlayExpandedDetails))
            Opacity(
              opacity: showCollapsedDetails ? 1 : 0,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _PosterCardDetails(
                  title: widget.title,
                  subtitle: widget.subtitle,
                  expanded: false,
                  saved: widget.saved,
                  hasSaveAction: widget.onToggleSaved != null,
                  selectedAction: _selectedAction,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _handleFocusChanged(bool value, BuildContext context) {
    if (_focused != value) {
      setState(() => _focused = value);
    }
    if (widget.expandOnFocus) {
      if (value) {
        _overlayController.show();
      } else {
        _overlayController.hide();
      }
    }

    widget.onFocusChanged?.call(
      value,
      _previewLayerLink,
      Size(
        value && widget.expandOnFocus ? widget.expandedWidth : widget.width,
        value && widget.expandOnFocus
            ? widget.expandedPosterHeight
            : widget.posterHeight,
      ),
    );
    if (value) {
      final likelyDetailArtwork = widget.expandedImageUrl;
      if (likelyDetailArtwork != null) {
        unawaited(
          TmdbImageService.preload(
            context,
            likelyDetailArtwork,
            preset: TmdbImagePreset.cardBackdrop,
            decodeWidth: (widget.expandedWidth *
                    (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1))
                .round()
                .clamp(1, 1200),
          ),
        );
      }
      if (widget.ensureVisibleOnFocus) {
        _ensureVisible(context);
      }
      _schedulePreviewLoad();
      return;
    }
    _clearPreviewState();
  }

  void _schedulePreviewLoad() {
    _previewLoadTimer?.cancel();
    if (!widget.expandOnFocus ||
        !widget.autoplayPreviewEnabled ||
        !cheriflixTrailerPreviewsSupported ||
        CheriflixRuntimePressureController
            .instance.previewSuspendedForSession ||
        !_focused ||
        _requestedPreview ||
        widget.previewLoader == null) {
      return;
    }

    if (widget.previewLoadDelay <= Duration.zero) {
      _loadPreview();
      return;
    }

    _previewLoadTimer = Timer(widget.previewLoadDelay, _loadPreview);
  }

  Future<void> _loadPreview() async {
    if (!widget.expandOnFocus ||
        !widget.autoplayPreviewEnabled ||
        !cheriflixTrailerPreviewsSupported ||
        CheriflixRuntimePressureController
            .instance.previewSuspendedForSession ||
        !_focused ||
        _requestedPreview ||
        widget.previewLoader == null) {
      return;
    }

    final requestId = ++_previewRequestId;
    _requestedPreview = true;
    if (mounted) {
      setState(() => _loadingPreview = true);
    }
    try {
      final previewUri = await widget.previewLoader!();
      if (!mounted ||
          requestId != _previewRequestId ||
          !_focused ||
          CheriflixRuntimePressureController
              .instance.previewSuspendedForSession) {
        return;
      }
      setState(() {
        _previewUri = previewUri;
        _loadingPreview = false;
      });
    } catch (_) {
      CheriflixRuntimePressureController.instance.recordPreviewFailure();
      if (!mounted || requestId != _previewRequestId) {
        return;
      }
      setState(() => _loadingPreview = false);
    }
  }

  void _clearPreviewState() {
    _previewRequestId += 1;
    _previewLoadTimer?.cancel();
    if (!mounted) {
      _previewUri = null;
      _loadingPreview = false;
      _requestedPreview = false;
      return;
    }
    setState(() {
      _previewUri = null;
      _loadingPreview = false;
      _requestedPreview = false;
    });
  }

  void _handleRuntimePressureChanged() {
    if (!CheriflixRuntimePressureController
        .instance.previewSuspendedForSession) {
      return;
    }
    if (_selectedAction != -1) {
      setState(() => _selectedAction = -1);
    }
    _clearPreviewState();
  }

  int get _actionCount => widget.onToggleSaved == null ? 2 : 3;

  void _activateSelectedAction() {
    if (_selectedAction < 0) {
      if (widget.expandOnFocus && _focused) {
        setState(() => _selectedAction = 0);
        return;
      }
      widget.onPressed();
      return;
    }
    if (_selectedAction == 0) {
      (widget.onPlay ?? widget.onPressed).call();
      return;
    }
    if (widget.onToggleSaved != null && _selectedAction == 1) {
      widget.onToggleSaved!.call();
      return;
    }
    (widget.onOpenInfo ?? widget.onPressed).call();
  }

  KeyEventResult _handleActionDirection(
    TraversalDirection direction,
    bool expanded,
  ) {
    if (!expanded) return KeyEventResult.ignored;
    if (_selectedAction < 0) {
      return KeyEventResult.ignored;
    }
    switch (direction) {
      case TraversalDirection.left:
        setState(() =>
            _selectedAction = (_selectedAction - 1).clamp(0, _actionCount - 1));
        return KeyEventResult.handled;
      case TraversalDirection.right:
        setState(() =>
            _selectedAction = (_selectedAction + 1).clamp(0, _actionCount - 1));
        return KeyEventResult.handled;
      case TraversalDirection.up:
        setState(() => _selectedAction = -1);
        return KeyEventResult.handled;
      case TraversalDirection.down:
        setState(() => _selectedAction = -1);
        return KeyEventResult.ignored;
    }
  }
}

class _PosterCardDetails extends StatelessWidget {
  const _PosterCardDetails({
    required this.title,
    required this.subtitle,
    required this.expanded,
    required this.saved,
    required this.hasSaveAction,
    required this.selectedAction,
  });

  final String title;
  final String subtitle;
  final bool expanded;
  final bool saved;
  final bool hasSaveAction;
  final int selectedAction;

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CheriflixTypography.cardTitle,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CheriflixTypography.metadata.copyWith(letterSpacing: 0.2),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: CheriflixTypography.cardTitle.copyWith(fontSize: 17),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: CheriflixTypography.metadata.copyWith(letterSpacing: 0.2),
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: <Widget>[
              _PosterActionPill(
                icon: Icons.play_arrow_rounded,
                label: 'Play',
                selected: selectedAction == 0,
              ),
              if (hasSaveAction) ...<Widget>[
                const SizedBox(width: 10),
                _PosterActionPill(
                  icon: saved ? Icons.check_rounded : Icons.add_rounded,
                  label: saved ? 'In My List' : 'Add to List',
                  selected: selectedAction == 1,
                ),
              ],
              const SizedBox(width: 10),
              _PosterActionPill(
                icon: Icons.info_outline_rounded,
                label: 'Info',
                selected: selectedAction == (hasSaveAction ? 2 : 1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExpandedPosterDetails extends StatelessWidget {
  const _ExpandedPosterDetails({
    required this.title,
    required this.subtitle,
    required this.saved,
    required this.hasSaveAction,
    required this.selectedAction,
  });

  final String title;
  final String subtitle;
  final bool saved;
  final bool hasSaveAction;
  final int selectedAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: CheriflixTypography.cardTitle.copyWith(
            color: CheriflixColors.textPrimary,
            fontSize: 17,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: CheriflixTypography.metadata.copyWith(
            color: const Color(0xFFD3D3D3),
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: <Widget>[
              _PosterActionPill(
                icon: Icons.play_arrow_rounded,
                label: 'Play',
                selected: selectedAction == 0,
              ),
              if (hasSaveAction) ...<Widget>[
                const SizedBox(width: 10),
                _PosterActionPill(
                  icon: saved ? Icons.check_rounded : Icons.add_rounded,
                  label: saved ? 'In My List' : 'Add to List',
                  selected: selectedAction == 1,
                ),
              ],
              const SizedBox(width: 10),
              _PosterActionPill(
                icon: Icons.info_outline_rounded,
                label: 'Info',
                selected: selectedAction == (hasSaveAction ? 2 : 1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PosterActionPill extends StatelessWidget {
  const _PosterActionPill({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? Colors.white : const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected ? CheriflixColors.focus : const Color(0x34FFFFFF),
          width: selected ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            icon,
            color: selected ? Colors.black : CheriflixColors.textPrimary,
            size: 17,
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: CheriflixTypography.button.copyWith(
              color: selected ? Colors.black : CheriflixColors.textPrimary,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _PosterArtworkSurface extends StatelessWidget {
  const _PosterArtworkSurface({
    required this.imageUrl,
    required this.width,
    required this.height,
    required this.devicePixelRatio,
    this.borderRadius = 0,
  });

  final String? imageUrl;
  final double width;
  final double height;
  final double devicePixelRatio;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ClipRRect(
        borderRadius: borderRadius <= 0
            ? BorderRadius.zero
            : BorderRadius.circular(borderRadius),
        child: ColoredBox(
          color: CheriflixColors.surface,
          child: CheriflixNetworkImage(
            imageUrl: imageUrl,
            width: width,
            height: height,
            devicePixelRatio: devicePixelRatio,
            preset: width > height
                ? TmdbImagePreset.cardBackdrop
                : TmdbImagePreset.smallPoster,
            borderRadius: borderRadius,
          ),
        ),
      ),
    );
  }
}

class TvEpisodeButton extends StatefulWidget {
  const TvEpisodeButton({
    super.key,
    required this.episodeNumber,
    required this.title,
    required this.overview,
    required this.durationLabel,
    required this.onPressed,
    this.imageUrl,
    this.autofocus = false,
    this.focusNode,
    this.downFallbackNodes = const <FocusNode>[],
    this.upFallbackNodes = const <FocusNode>[],
    this.leftFallbackNodes = const <FocusNode>[],
    this.rightFallbackNodes = const <FocusNode>[],
  });

  final int episodeNumber;
  final String title;
  final String overview;
  final String durationLabel;
  final String? imageUrl;
  final VoidCallback onPressed;
  final bool autofocus;
  final FocusNode? focusNode;
  final List<FocusNode> downFallbackNodes;
  final List<FocusNode> upFallbackNodes;
  final List<FocusNode> leftFallbackNodes;
  final List<FocusNode> rightFallbackNodes;

  @override
  State<TvEpisodeButton> createState() => _TvEpisodeButtonState();
}

class _TvEpisodeButtonState extends State<TvEpisodeButton> {
  bool _focused = false;
  late final FocusNode _focusNode =
      FocusNode(debugLabel: 'TvEpisodeButton(${widget.title})');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focusNode = widget.focusNode ?? _focusNode;
    return Shortcuts(
      shortcuts: _tvActionShortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              widget.onPressed();
              return null;
            },
          ),
          _DirectionalFallbackIntent:
              CallbackAction<_DirectionalFallbackIntent>(
            onInvoke: (intent) {
              _moveFocusWithFallback(
                focusNode,
                intent.direction,
                leftFallbackNodes: widget.leftFallbackNodes,
                rightFallbackNodes: widget.rightFallbackNodes,
                downFallbackNodes: widget.downFallbackNodes,
                upFallbackNodes: widget.upFallbackNodes,
              );
              return null;
            },
          ),
        },
        child: FocusableActionDetector(
          focusNode: focusNode,
          autofocus: widget.autofocus,
          onShowFocusHighlight: (value) {
            setState(() => _focused = value);
            if (value) {
              _ensureVisible(context);
            }
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final imageHeight = constraints.maxHeight * 0.56;
              final devicePixelRatio =
                  MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
              return RepaintBoundary(
                child: AnimatedScale(
                  scale: _focused ? 1.03 : 1,
                  duration: const Duration(milliseconds: 160),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: CheriflixColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _focused
                            ? CheriflixColors.focus
                            : const Color(0x18FFFFFF),
                        width: _focused ? 3 : 1,
                      ),
                      boxShadow: <BoxShadow>[
                        const BoxShadow(
                          color: Color(0x3B000000),
                          blurRadius: 14,
                          offset: Offset(0, 10),
                        ),
                        if (_focused)
                          const BoxShadow(
                            color: Color(0x18FFFFFF),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                      ],
                    ),
                    child: InkWell(
                      onTap: () {
                        focusNode.requestFocus();
                        widget.onPressed();
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SizedBox(
                            height: imageHeight,
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(19),
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: <Widget>[
                                  CheriflixNetworkImage(
                                    imageUrl: widget.imageUrl,
                                    width: constraints.maxWidth,
                                    height: imageHeight,
                                    devicePixelRatio: devicePixelRatio,
                                    preset: TmdbImagePreset.episodeStill,
                                    placeholderColor: const Color(0xFF101010),
                                  ),
                                  const Positioned.fill(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: <Color>[
                                            Color(0x10000000),
                                            Color(0x22000000),
                                            Color(0x44000000),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 14,
                                    top: 14,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xCC1E2328),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${widget.episodeNumber}',
                                        style: CheriflixTypography.metadata
                                            .copyWith(
                                          color: CheriflixColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                18,
                                20,
                                18,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        CheriflixTypography.cardTitle.copyWith(
                                      fontSize: 17,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Expanded(
                                    child: Text(
                                      widget.overview,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: CheriflixTypography.body.copyWith(
                                        color: CheriflixColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: <Widget>[
                                      const Icon(
                                        Icons.access_time_filled_rounded,
                                        color: Color(0xFF21E57F),
                                        size: 18,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        widget.durationLabel,
                                        style: CheriflixTypography.metadata
                                            .copyWith(
                                          color: CheriflixColors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SaveBadge extends StatelessWidget {
  const _SaveBadge({
    required this.saved,
  });

  final bool saved;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: saved ? CheriflixColors.accentRed : const Color(0xBF111111),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: saved ? CheriflixColors.accentRed : const Color(0x30FFFFFF),
        ),
      ),
      child: Text(
        saved ? 'SAVED' : 'SAVE',
        style: CheriflixTypography.metadata.copyWith(
          color: CheriflixColors.textPrimary,
          fontSize: 12,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ResolvedButtonStyle {
  const _ResolvedButtonStyle({
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
    required this.borderWidth,
    required this.shadows,
  });

  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
  final double borderWidth;
  final List<BoxShadow> shadows;
}

_ResolvedButtonStyle _buttonStyle({
  required TvButtonVariant variant,
  required bool focused,
  required bool enabled,
  required bool selected,
}) {
  if (!enabled) {
    return const _ResolvedButtonStyle(
      backgroundColor: Color(0xFF121212),
      foregroundColor: CheriflixColors.textSecondary,
      borderColor: Color(0x14FFFFFF),
      borderWidth: 1.3,
      shadows: <BoxShadow>[],
    );
  }

  switch (variant) {
    case TvButtonVariant.light:
      return _ResolvedButtonStyle(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        borderColor: focused ? CheriflixColors.focus : Colors.white,
        borderWidth: focused ? 3 : 1.3,
        shadows: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      );
    case TvButtonVariant.dark:
      return _ResolvedButtonStyle(
        backgroundColor: const Color(0xFF2B2B2B),
        foregroundColor: CheriflixColors.textPrimary,
        borderColor: focused ? CheriflixColors.focus : const Color(0x30FFFFFF),
        borderWidth: focused ? 3 : 1.3,
        shadows: const <BoxShadow>[
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      );
    case TvButtonVariant.media:
      return _ResolvedButtonStyle(
        backgroundColor: focused ? Colors.white : const Color(0xFF2B2B2B),
        foregroundColor: focused ? Colors.black : CheriflixColors.textPrimary,
        borderColor: focused ? Colors.white : const Color(0x36FFFFFF),
        borderWidth: 2,
        shadows: <BoxShadow>[
          const BoxShadow(
            color: Color(0x66000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
          if (focused)
            const BoxShadow(
              color: Color(0x22FFFFFF),
              blurRadius: 10,
              spreadRadius: 1,
            ),
        ],
      );
    case TvButtonVariant.danger:
      return _ResolvedButtonStyle(
        backgroundColor: CheriflixColors.accentRed,
        foregroundColor: CheriflixColors.textPrimary,
        borderColor:
            focused ? CheriflixColors.focus : CheriflixColors.accentRedMuted,
        borderWidth: focused ? 3 : 1.3,
        shadows: const <BoxShadow>[
          BoxShadow(
            color: Color(0x55E50914),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      );
    case TvButtonVariant.ghost:
      return _ResolvedButtonStyle(
        backgroundColor: selected ? Colors.white : const Color(0xFF121212),
        foregroundColor: selected ? Colors.black : CheriflixColors.textPrimary,
        borderColor: focused ? CheriflixColors.focus : const Color(0x30FFFFFF),
        borderWidth: focused ? 3 : 1.3,
        shadows: const <BoxShadow>[
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      );
  }
}

void _ensureVisible(BuildContext context) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) {
      return;
    }
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) {
      return;
    }

    final targetObject = context.findRenderObject();
    final viewportObject = scrollable.context.findRenderObject();
    if (targetObject is RenderBox &&
        viewportObject is RenderBox &&
        targetObject.hasSize &&
        viewportObject.hasSize) {
      final axis = scrollable.position.axis;
      final targetOrigin = targetObject.localToGlobal(
        Offset.zero,
        ancestor: viewportObject,
      );
      final targetSize = targetObject.size;
      final viewportExtent = axis == Axis.horizontal
          ? viewportObject.size.width
          : viewportObject.size.height;
      final targetStart =
          axis == Axis.horizontal ? targetOrigin.dx : targetOrigin.dy;
      final targetExtent =
          axis == Axis.horizontal ? targetSize.width : targetSize.height;
      const safeMargin = 40.0;
      final isFullyVisible = targetStart >= safeMargin &&
          targetStart + targetExtent <= viewportExtent - safeMargin;
      if (isFullyVisible) {
        return;
      }

      final position = scrollable.position;
      final targetEnd = targetStart + targetExtent;
      late final double desiredPixels;
      if (targetStart < safeMargin) {
        desiredPixels = position.pixels + targetStart - safeMargin;
      } else {
        desiredPixels =
            position.pixels + targetEnd - viewportExtent + safeMargin;
      }
      final clampedPixels = desiredPixels.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((clampedPixels - position.pixels).abs() < 1) {
        return;
      }

      position.animateTo(
        clampedPixels.toDouble(),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
      return;
    }
  });
}

void _moveFocusWithFallback(
  FocusNode currentNode,
  TraversalDirection direction, {
  List<FocusNode> leftFallbackNodes = const <FocusNode>[],
  List<FocusNode> rightFallbackNodes = const <FocusNode>[],
  List<FocusNode> downFallbackNodes = const <FocusNode>[],
  List<FocusNode> upFallbackNodes = const <FocusNode>[],
}) {
  final fallbackNodes = switch (direction) {
    TraversalDirection.left => leftFallbackNodes,
    TraversalDirection.right => rightFallbackNodes,
    TraversalDirection.down => downFallbackNodes,
    TraversalDirection.up => upFallbackNodes,
  };
  final fallbackNode = _firstAvailableFallbackNode(currentNode, fallbackNodes);
  final shouldPreferFallback = switch (direction) {
    TraversalDirection.left => leftFallbackNodes.isNotEmpty,
    TraversalDirection.right => rightFallbackNodes.isNotEmpty,
    TraversalDirection.down => downFallbackNodes.isNotEmpty,
    TraversalDirection.up => upFallbackNodes.isNotEmpty,
  };
  if (shouldPreferFallback && fallbackNode != null) {
    fallbackNode.requestFocus();
    return;
  }

  final moved = currentNode.focusInDirection(direction);
  if (moved) {
    return;
  }

  fallbackNode?.requestFocus();
}

FocusNode? _firstAvailableFallbackNode(
  FocusNode currentNode,
  List<FocusNode> candidates,
) {
  FocusNode? firstMountedCandidate;
  FocusNode? selfCandidate;

  for (final candidate in candidates) {
    if (!candidate.canRequestFocus) {
      continue;
    }
    if (candidate == currentNode && candidate.context != null) {
      selfCandidate ??= candidate;
      continue;
    }
    if (candidate.context == null) {
      continue;
    }
    firstMountedCandidate ??= candidate;
  }

  return firstMountedCandidate ?? selfCandidate;
}

class _DirectionalIntent extends Intent {
  const _DirectionalIntent(this.direction);

  final TraversalDirection direction;
}

class _BackIntent extends Intent {
  const _BackIntent();
}

class _SecondaryIntent extends Intent {
  const _SecondaryIntent();
}

class _DirectionalFallbackIntent extends Intent {
  const _DirectionalFallbackIntent(this.direction);

  final TraversalDirection direction;
}

const Map<ShortcutActivator, Intent> _tvScopeShortcuts =
    <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.arrowLeft):
      _DirectionalIntent(TraversalDirection.left),
  SingleActivator(LogicalKeyboardKey.arrowRight):
      _DirectionalIntent(TraversalDirection.right),
  SingleActivator(LogicalKeyboardKey.arrowUp):
      _DirectionalIntent(TraversalDirection.up),
  SingleActivator(LogicalKeyboardKey.arrowDown):
      _DirectionalIntent(TraversalDirection.down),
  SingleActivator(LogicalKeyboardKey.escape): _BackIntent(),
  SingleActivator(LogicalKeyboardKey.backspace): _BackIntent(),
  SingleActivator(LogicalKeyboardKey.goBack): _BackIntent(),
  SingleActivator(LogicalKeyboardKey.browserBack): _BackIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonB): _BackIntent(),
};

const Map<ShortcutActivator, Intent> _tvActionShortcuts =
    <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.accept): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonSelect): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonStart): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.arrowLeft):
      _DirectionalFallbackIntent(TraversalDirection.left),
  SingleActivator(LogicalKeyboardKey.arrowRight):
      _DirectionalFallbackIntent(TraversalDirection.right),
  SingleActivator(LogicalKeyboardKey.arrowUp):
      _DirectionalFallbackIntent(TraversalDirection.up),
  SingleActivator(LogicalKeyboardKey.arrowDown):
      _DirectionalFallbackIntent(TraversalDirection.down),
};

const Map<ShortcutActivator, Intent> _tvPosterShortcuts =
    <ShortcutActivator, Intent>{
  ..._tvActionShortcuts,
  SingleActivator(LogicalKeyboardKey.keyS): _SecondaryIntent(),
};

bool _isActivationKey(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.accept ||
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.gameButtonA ||
      key == LogicalKeyboardKey.gameButtonSelect ||
      key == LogicalKeyboardKey.gameButtonStart ||
      key == LogicalKeyboardKey.mediaPlayPause ||
      key == LogicalKeyboardKey.mediaPlay ||
      key == LogicalKeyboardKey.mediaPause;
}

bool _isBackKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.escape ||
    key == LogicalKeyboardKey.backspace ||
    key == LogicalKeyboardKey.goBack ||
    key == LogicalKeyboardKey.browserBack ||
    key == LogicalKeyboardKey.gameButtonB;

TraversalDirection? _directionForKey(LogicalKeyboardKey key) {
  return switch (key) {
    LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
    LogicalKeyboardKey.arrowRight => TraversalDirection.right,
    LogicalKeyboardKey.arrowUp => TraversalDirection.up,
    LogicalKeyboardKey.arrowDown => TraversalDirection.down,
    _ => null,
  };
}
