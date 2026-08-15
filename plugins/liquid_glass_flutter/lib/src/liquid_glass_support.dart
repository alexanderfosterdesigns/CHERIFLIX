import 'package:flutter/foundation.dart';

import 'liquid_glass_platform.dart';

Future<bool> isLiquidGlassSupported() {
  return LiquidGlassSupport.instance.isSupported();
}

class LiquidGlassSupport {
  LiquidGlassSupport._();

  static final LiquidGlassSupport instance = LiquidGlassSupport._();

  Future<bool>? _pending;
  bool? _cachedValue;

  bool get maybeSupported {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  }

  bool get cachedValue => _cachedValue ?? false;

  Future<bool> isSupported() {
    if (!maybeSupported) {
      _cachedValue = false;
      return SynchronousFuture<bool>(false);
    }

    _pending ??= LiquidGlassPlatform.isSupported().then((value) {
      _cachedValue = value;
      return value;
    }).catchError((_) {
      _cachedValue = false;
      return false;
    });

    return _pending!;
  }

  @visibleForTesting
  void reset() {
    _pending = null;
    _cachedValue = null;
  }
}
