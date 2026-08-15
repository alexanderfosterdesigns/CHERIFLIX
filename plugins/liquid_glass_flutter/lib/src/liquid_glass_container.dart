import 'package:flutter/widgets.dart';

class LiquidGlassContainer extends StatelessWidget {
  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.spacing = 0,
  });

  final Widget child;
  final double spacing;

  static double? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_LiquidGlassContainerScope>()
        ?.spacing;
  }

  @override
  Widget build(BuildContext context) {
    return _LiquidGlassContainerScope(
      spacing: spacing,
      child: child,
    );
  }
}

class _LiquidGlassContainerScope extends InheritedWidget {
  const _LiquidGlassContainerScope({
    required this.spacing,
    required super.child,
  });

  final double spacing;

  @override
  bool updateShouldNotify(_LiquidGlassContainerScope oldWidget) {
    return spacing != oldWidget.spacing;
  }
}
