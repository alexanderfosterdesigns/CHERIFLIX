import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

import '../services/tmdb_image_service.dart';
import '../theme/cheriflix_theme.dart';

/// Locally cached, decode-sized artwork with automatic wsrv -> direct-source
/// fallback. Identical requests are deduplicated by the shared cache manager.
class CheriflixNetworkImage extends StatefulWidget {
  const CheriflixNetworkImage({
    super.key,
    required this.imageUrl,
    required this.width,
    required this.height,
    this.preset,
    this.devicePixelRatio = 1,
    this.fit = BoxFit.cover,
    this.filterQuality = FilterQuality.low,
    this.maxDecodePixels = 1600,
    this.placeholderColor = CheriflixColors.surface,
    this.borderRadius = 0,
    this.fadeInDuration,
    this.onImageLoaded,
    this.onFinalError,
  });

  final String? imageUrl;
  final double width;
  final double height;
  final TmdbImagePreset? preset;
  final double devicePixelRatio;
  final BoxFit fit;
  final FilterQuality filterQuality;
  final int maxDecodePixels;
  final Color placeholderColor;
  final double borderRadius;
  final Duration? fadeInDuration;
  final VoidCallback? onImageLoaded;
  final VoidCallback? onFinalError;

  @override
  State<CheriflixNetworkImage> createState() => _CheriflixNetworkImageState();
}

class _CheriflixNetworkImageState extends State<CheriflixNetworkImage> {
  bool _usingFallback = false;
  bool _finalErrorReported = false;

  @override
  void didUpdateWidget(covariant CheriflixNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.preset != widget.preset) {
      _usingFallback = false;
      _finalErrorReported = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final preset = widget.preset ??
        (widget.width > widget.height
            ? TmdbImagePreset.cardBackdrop
            : TmdbImagePreset.smallPoster);
    final request = TmdbImageService.request(
      widget.imageUrl,
      preset: preset,
    );
    final cacheWidth =
        widget.width > widget.height ? _decodePixels(widget.width) : null;
    final cacheHeight =
        widget.width <= widget.height ? _decodePixels(widget.height) : null;

    final content = request == null
        ? _placeholder()
        : CachedNetworkImage(
            key: ValueKey<String>(
              _usingFallback ? request.fallbackUrl : request.primaryUrl,
            ),
            imageUrl: _usingFallback ? request.fallbackUrl : request.primaryUrl,
            cacheManager: TmdbImageService.cacheManager,
            fit: widget.fit,
            filterQuality: widget.filterQuality,
            memCacheWidth: cacheWidth,
            memCacheHeight: cacheHeight,
            fadeInDuration:
                widget.fadeInDuration ?? const Duration(milliseconds: 180),
            imageBuilder: (_, provider) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) widget.onImageLoaded?.call();
              });
              return Image(
                image: provider,
                fit: widget.fit,
                filterQuality: widget.filterQuality,
              );
            },
            placeholder: (_, __) => _placeholder(),
            errorWidget: (_, __, ___) {
              if (!_usingFallback &&
                  request.fallbackUrl != request.primaryUrl) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _usingFallback = true);
                });
              } else if (!_finalErrorReported) {
                _finalErrorReported = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) widget.onFinalError?.call();
                });
              }
              return _placeholder();
            },
          );

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: widget.borderRadius <= 0
          ? content
          : ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: content,
            ),
    );
  }

  int _decodePixels(double logicalPixels) {
    if (!logicalPixels.isFinite || logicalPixels <= 0) return 1;
    return (logicalPixels * widget.devicePixelRatio)
        .round()
        .clamp(1, widget.maxDecodePixels);
  }

  Widget _placeholder() => ColoredBox(
        color: widget.placeholderColor,
        child: const SizedBox.expand(),
      );
}
