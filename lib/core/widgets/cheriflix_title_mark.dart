import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/tmdb_title_logo.dart';
import '../services/tmdb_image_service.dart';
import 'cheriflix_network_image.dart';

Size calculateContainedTitleLogoSize({
  required int intrinsicWidth,
  required int intrinsicHeight,
  required double maxWidth,
  required double maxHeight,
}) {
  if (intrinsicWidth <= 0 || intrinsicHeight <= 0) {
    return Size(maxWidth, maxHeight);
  }
  final scale = math.min(
    maxWidth / intrinsicWidth,
    maxHeight / intrinsicHeight,
  );
  return Size(intrinsicWidth * scale, intrinsicHeight * scale);
}

/// A consistently bounded TMDB title treatment with an immediate text fallback.
///
/// Once the transparent logo has been decoded it replaces the fallback without
/// a fade. This keeps cached/prefetched logos instant while never leaving a
/// blank title when a logo is missing or unavailable.
class CheriflixTitleMark extends StatefulWidget {
  const CheriflixTitleMark({
    super.key,
    required this.logo,
    required this.fallbackTitle,
    required this.maxWidth,
    required this.maxHeight,
    required this.fallbackStyle,
    this.fallbackMaxLines = 3,
    this.imageKey,
  });

  final TmdbTitleLogo? logo;
  final String fallbackTitle;
  final double maxWidth;
  final double maxHeight;
  final TextStyle fallbackStyle;
  final int fallbackMaxLines;
  final Key? imageKey;

  @override
  State<CheriflixTitleMark> createState() => _CheriflixTitleMarkState();
}

class _CheriflixTitleMarkState extends State<CheriflixTitleMark> {
  bool _rendered = false;
  bool _failed = false;

  @override
  void didUpdateWidget(covariant CheriflixTitleMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.logo?.filePath != widget.logo?.filePath) {
      _rendered = false;
      _failed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final logo = widget.logo;
    final fallback = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: widget.maxWidth,
        maxHeight: widget.maxHeight,
      ),
      child: Text(
        widget.fallbackTitle,
        maxLines: widget.fallbackMaxLines,
        overflow: TextOverflow.ellipsis,
        style: widget.fallbackStyle,
      ),
    );
    if (logo == null || _failed) return fallback;

    final size = calculateContainedTitleLogoSize(
      intrinsicWidth: logo.width,
      intrinsicHeight: logo.height,
      maxWidth: widget.maxWidth,
      maxHeight: widget.maxHeight,
    );
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: <Widget>[
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: _rendered ? 0 : 1,
              duration: const Duration(milliseconds: 80),
              child: Align(alignment: Alignment.centerLeft, child: fallback),
            ),
          ),
          CheriflixNetworkImage(
            key: widget.imageKey,
            imageUrl: logo.imageUrl,
            width: size.width,
            height: size.height,
            preset: TmdbImagePreset.titleLogo,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            placeholderColor: Colors.transparent,
            fadeInDuration: Duration.zero,
            onImageLoaded: () {
              if (mounted && !_rendered) setState(() => _rendered = true);
            },
            onFinalError: () {
              if (mounted && !_failed) setState(() => _failed = true);
            },
          ),
        ],
      ),
    );
  }
}
