import 'package:flutter/widgets.dart';

ImageProvider<Object> boundedAssetImageProvider(
  BuildContext context,
  String assetName, {
  required double logicalWidth,
  required double logicalHeight,
  int maxDecodeWidth = 1024,
  int maxDecodeHeight = 1024,
}) {
  final devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
  return ResizeImage.resizeIfNeeded(
    _boundedCacheDimension(
      logicalWidth,
      devicePixelRatio,
      maxDecodeWidth,
    ),
    _boundedCacheDimension(
      logicalHeight,
      devicePixelRatio,
      maxDecodeHeight,
    ),
    AssetImage(assetName),
  );
}

int _boundedCacheDimension(
  double logicalPixels,
  double devicePixelRatio,
  int maxDecodePixels,
) {
  if (!logicalPixels.isFinite || logicalPixels <= 0) {
    return 1;
  }
  final physicalPixels = (logicalPixels * devicePixelRatio).ceil();
  return physicalPixels.clamp(1, maxDecodePixels).toInt();
}
