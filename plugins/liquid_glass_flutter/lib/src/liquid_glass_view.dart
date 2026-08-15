import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'liquid_glass_container.dart';
import 'liquid_glass_platform.dart';
import 'liquid_glass_types.dart';

class LiquidGlassView extends StatefulWidget {
  const LiquidGlassView({
    super.key,
    this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.alignment,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.interactive = false,
    this.effect = LiquidGlassEffect.regular,
    this.tintColor,
    this.colorScheme = LiquidGlassColorScheme.system,
    this.clipBehavior = Clip.antiAlias,
  }) : assert(
          child != null || (width != null && height != null),
          'LiquidGlassView needs a child or an explicit size.',
        );

  final Widget? child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final AlignmentGeometry? alignment;
  final BorderRadiusGeometry borderRadius;
  final bool interactive;
  final LiquidGlassEffect effect;
  final Color? tintColor;
  final LiquidGlassColorScheme colorScheme;
  final Clip clipBehavior;

  @override
  State<LiquidGlassView> createState() => _LiquidGlassViewState();
}

class _LiquidGlassViewState extends State<LiquidGlassView> {
  static const Duration _pressDuration = Duration(milliseconds: 180);

  int? _platformViewId;
  bool _pressed = false;

  @override
  void didUpdateWidget(covariant LiquidGlassView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncNativeView();
  }

  @override
  Widget build(BuildContext context) {
    final resolvedBorderRadius =
        widget.borderRadius.resolve(Directionality.maybeOf(context));

    Widget body = ClipRRect(
      borderRadius: resolvedBorderRadius,
      clipBehavior: widget.clipBehavior,
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          Positioned.fill(
            child: _buildBackground(resolvedBorderRadius),
          ),
          if (widget.child != null)
            Padding(
              padding: widget.padding ?? EdgeInsets.zero,
              child: widget.child!,
            )
          else
            SizedBox(
              width: widget.width,
              height: widget.height,
            ),
        ],
      ),
    );

    if (widget.width != null || widget.height != null) {
      body = SizedBox(
        width: widget.width,
        height: widget.height,
        child: body,
      );
    }

    if (widget.margin != null) {
      body = Padding(
        padding: widget.margin!,
        child: body,
      );
    }

    if (widget.interactive) {
      body = Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: AnimatedScale(
          scale: _pressed ? 1.015 : 1,
          duration: _pressDuration,
          curve: Curves.easeOutCubic,
          child: body,
        ),
      );
    }

    if (widget.alignment != null) {
      body = Align(
        alignment: widget.alignment!,
        child: body,
      );
    }

    return body;
  }

  Widget _buildBackground(BorderRadius resolvedBorderRadius) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: 'liquid_glass_flutter/view',
        creationParams: _configurationFor(resolvedBorderRadius).toMap(),
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (id) {
          _platformViewId = id;
          _syncNativeView();
        },
      );
    }

    return _LiquidGlassFallbackBackground(
      effect: widget.effect,
      tintColor: widget.tintColor,
      colorScheme: widget.colorScheme,
      mergeSpacing: LiquidGlassContainer.maybeOf(context),
      pressed: _pressed,
    );
  }

  LiquidGlassConfiguration _configurationFor(BorderRadius resolvedBorderRadius) {
    return LiquidGlassConfiguration(
      interactive: widget.interactive,
      effect: widget.effect,
      tintColor: widget.tintColor,
      colorScheme: widget.colorScheme,
      cornerRadius: _cornerRadiusFor(resolvedBorderRadius),
    );
  }

  double _cornerRadiusFor(BorderRadius borderRadius) {
    final radii = <double>[
      borderRadius.topLeft.x,
      borderRadius.topRight.x,
      borderRadius.bottomLeft.x,
      borderRadius.bottomRight.x,
    ];
    return radii.reduce((value, element) => value > element ? value : element);
  }

  Future<void> _syncNativeView() async {
    if (_platformViewId == null ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    try {
      final resolvedBorderRadius =
          widget.borderRadius.resolve(Directionality.maybeOf(context));
      await LiquidGlassPlatform.updateView(
        _platformViewId!,
        _configurationFor(resolvedBorderRadius),
      );
    } catch (_) {}
  }

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) {
      return;
    }
    setState(() => _pressed = value);
  }
}

class _LiquidGlassFallbackBackground extends StatelessWidget {
  const _LiquidGlassFallbackBackground({
    required this.effect,
    required this.tintColor,
    required this.colorScheme,
    required this.mergeSpacing,
    required this.pressed,
  });

  final LiquidGlassEffect effect;
  final Color? tintColor;
  final LiquidGlassColorScheme colorScheme;
  final double? mergeSpacing;
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    if (effect == LiquidGlassEffect.none) {
      return const ColoredBox(color: Colors.transparent);
    }

    final isDark = switch (colorScheme) {
      LiquidGlassColorScheme.dark => true,
      LiquidGlassColorScheme.light => false,
      LiquidGlassColorScheme.system =>
        Theme.of(context).brightness == Brightness.dark,
    };
    final mergeStrength = mergeSpacing == null
        ? 0.0
        : ((24 - mergeSpacing!).clamp(0.0, 24.0) / 24.0);
    final blurSigma =
        effect.blurSigma + (pressed ? 3 : 0) + (mergeStrength * 4);
    final baseTint = tintColor ??
        (isDark ? const Color(0x22FFFFFF) : const Color(0x14FFFFFF));
    final surfaceColor = baseTint.withOpacity(
      effect.tintOpacity + (pressed ? 0.03 : 0),
    );
    final borderColor = (isDark ? Colors.white : Colors.black).withOpacity(
      effect == LiquidGlassEffect.regular ? 0.22 : 0.14,
    );
    final lowerShadow = Colors.black.withOpacity(isDark ? 0.16 : 0.06);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: blurSigma,
          sigmaY: blurSigma,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                surfaceColor.withOpacity(isDark ? 1.0 : 0.72),
                surfaceColor.withOpacity(isDark ? 0.66 : 0.5),
                lowerShadow,
              ],
              stops: const <double>[0, 0.48, 1],
            ),
            border: Border.all(color: borderColor),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.white.withOpacity(isDark ? 0.2 : 0.12),
                      Colors.white.withOpacity(0),
                      Colors.black.withOpacity(isDark ? 0.12 : 0.04),
                    ],
                    stops: const <double>[0, 0.38, 1],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.85, -0.95),
                    radius: 1.18,
                    colors: <Color>[
                      Colors.white.withOpacity(pressed ? 0.26 : 0.16),
                      Colors.white.withOpacity(0),
                    ],
                  ),
                ),
              ),
              if (pressed)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        Colors.white.withOpacity(0.12),
                        Colors.white.withOpacity(0),
                        Colors.white.withOpacity(0.06),
                      ],
                      stops: const <double>[0, 0.46, 1],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
