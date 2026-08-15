import 'package:flutter/services.dart';

import 'liquid_glass_types.dart';

class LiquidGlassPlatform {
  LiquidGlassPlatform._();

  static const MethodChannel _channel = MethodChannel('liquid_glass_flutter');

  static Future<bool> isSupported() async {
    return (await _channel.invokeMethod<bool>('isLiquidGlassSupported')) ??
        false;
  }

  static Future<void> updateView(
    int id,
    LiquidGlassConfiguration configuration,
  ) {
    return _channel.invokeMethod<void>(
      'updateView',
      <String, Object?>{
        'id': id,
        ...configuration.toMap(),
      },
    );
  }
}
