# liquid_glass_flutter

`liquid_glass_flutter` ports the shape of [`@callstack/liquid-glass`](https://github.com/callstack/liquid-glass) into Flutter.

What it does:

- uses the real native `UIGlassEffect` on iOS 26+ when built with Xcode 26
- keeps a Flutter-first widget API for `LiquidGlassView` and `LiquidGlassContainer`
- falls back to a layered blur surface on Windows, Android, older iOS, and tests

## Usage

```dart
import 'package:liquid_glass_flutter/liquid_glass_flutter.dart';

LiquidGlassView(
  width: 220,
  height: 96,
  borderRadius: BorderRadius.circular(28),
  effect: LiquidGlassEffect.clear,
  tintColor: const Color(0x1AFFFFFF),
  colorScheme: LiquidGlassColorScheme.dark,
  child: const Center(
    child: Text('Play'),
  ),
);
```

```dart
final supported = await isLiquidGlassSupported();
```

## Notes

- Native glass support follows the upstream library and depends on iOS 26 APIs plus `UIDesignRequiresCompatibility` being disabled in the host app.
- Flutter children are composited above the native surface, so the glass itself is real on iOS 26, but UIKit-only behaviors such as automatic text color adaptation inside the glass do not fully transfer to Flutter child widgets.
- The native press morph for `interactive` is constrained by Flutter platform-view layering when Flutter children sit above the glass surface.
- `LiquidGlassContainer` is a lightweight grouping wrapper in Flutter. Native sibling-merging behavior is limited by Flutter platform-view composition.
