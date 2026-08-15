import 'package:flutter/material.dart';

enum LiquidGlassEffect {
  regular,
  clear,
  none,
}

extension LiquidGlassEffectX on LiquidGlassEffect {
  String get platformValue => switch (this) {
        LiquidGlassEffect.regular => 'regular',
        LiquidGlassEffect.clear => 'clear',
        LiquidGlassEffect.none => 'none',
      };

  double get blurSigma => switch (this) {
        LiquidGlassEffect.regular => 22,
        LiquidGlassEffect.clear => 14,
        LiquidGlassEffect.none => 0,
      };

  double get tintOpacity => switch (this) {
        LiquidGlassEffect.regular => 0.16,
        LiquidGlassEffect.clear => 0.09,
        LiquidGlassEffect.none => 0,
      };
}

enum LiquidGlassColorScheme {
  light,
  dark,
  system,
}

extension LiquidGlassColorSchemeX on LiquidGlassColorScheme {
  String get platformValue => switch (this) {
        LiquidGlassColorScheme.light => 'light',
        LiquidGlassColorScheme.dark => 'dark',
        LiquidGlassColorScheme.system => 'system',
      };
}

@immutable
class LiquidGlassConfiguration {
  const LiquidGlassConfiguration({
    required this.interactive,
    required this.effect,
    required this.tintColor,
    required this.colorScheme,
    required this.cornerRadius,
  });

  final bool interactive;
  final LiquidGlassEffect effect;
  final Color? tintColor;
  final LiquidGlassColorScheme colorScheme;
  final double cornerRadius;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'interactive': interactive,
      'effect': effect.platformValue,
      'tintColor': tintColor?.value,
      'colorScheme': colorScheme.platformValue,
      'cornerRadius': cornerRadius,
    };
  }
}
