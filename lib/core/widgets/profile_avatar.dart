import 'dart:io';

import 'package:flutter/material.dart';

import '../services/profile_avatar_catalog.dart';
import '../theme/cheriflix_theme.dart';

class CheriflixProfileAvatar extends StatelessWidget {
  const CheriflixProfileAvatar({
    super.key,
    required this.avatarLabel,
    required this.width,
    required this.height,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    this.resolvedFile,
    this.resolvedAssetPath,
    this.fallbackBackgroundColor = CheriflixColors.accentRed,
    this.fallbackTextStyle,
    this.fit = BoxFit.cover,
    this.avatarCatalogService,
  });

  final String avatarLabel;
  final double width;
  final double height;
  final BorderRadiusGeometry? borderRadius;
  final BoxShape shape;
  final File? resolvedFile;
  final String? resolvedAssetPath;
  final Color fallbackBackgroundColor;
  final TextStyle? fallbackTextStyle;
  final BoxFit fit;
  final ProfileAvatarCatalogService? avatarCatalogService;

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    if (resolvedFile != null) {
      return _buildImage(resolvedFile!, devicePixelRatio);
    }
    final assetPath = resolvedAssetPath?.trim();
    if (assetPath != null && assetPath.isNotEmpty) {
      return _buildAssetImage(assetPath, devicePixelRatio);
    }

    final catalogService =
        avatarCatalogService ?? ProfileAvatarCatalogService.instance;
    return FutureBuilder<ProfileAvatarOption?>(
      future: catalogService.resolveAvatarOption(avatarLabel),
      builder: (context, snapshot) {
        final option = snapshot.data;
        final file = option?.file;
        if (file != null) {
          return _buildImage(file, devicePixelRatio);
        }
        final resolvedAssetPath = option?.assetPath?.trim();
        if (resolvedAssetPath != null && resolvedAssetPath.isNotEmpty) {
          return _buildAssetImage(resolvedAssetPath, devicePixelRatio);
        }
        return _buildFallback();
      },
    );
  }

  Widget _buildImage(File file, double devicePixelRatio) {
    final image = SizedBox(
      width: width,
      height: height,
      child: Image.file(
        file,
        cacheWidth: _cacheDimension(width, devicePixelRatio),
        cacheHeight: _cacheDimension(height, devicePixelRatio),
        fit: fit,
        filterQuality: FilterQuality.low,
        errorBuilder: (context, error, stackTrace) => _buildFallback(),
      ),
    );

    if (shape == BoxShape.circle) {
      return ClipOval(child: image);
    }

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(16),
      child: image,
    );
  }

  Widget _buildAssetImage(String path, double devicePixelRatio) {
    final image = SizedBox(
      width: width,
      height: height,
      child: Image.asset(
        path,
        cacheWidth: _cacheDimension(width, devicePixelRatio),
        cacheHeight: _cacheDimension(height, devicePixelRatio),
        fit: fit,
        filterQuality: FilterQuality.low,
        errorBuilder: (context, error, stackTrace) => _buildFallback(),
      ),
    );

    if (shape == BoxShape.circle) {
      return ClipOval(child: image);
    }

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(16),
      child: image,
    );
  }

  Widget _buildFallback() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: fallbackBackgroundColor,
        shape: shape,
        borderRadius: shape == BoxShape.circle ? null : borderRadius,
      ),
      alignment: Alignment.center,
      child: Text(
        _fallbackGlyph(avatarLabel),
        style: fallbackTextStyle ??
            const TextStyle(
              color: CheriflixColors.textPrimary,
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }
}

int _cacheDimension(double logicalPixels, double devicePixelRatio) {
  if (!logicalPixels.isFinite || logicalPixels <= 0) {
    return 1;
  }
  final physicalPixels = (logicalPixels * devicePixelRatio).ceil();
  return physicalPixels.clamp(1, 768).toInt();
}

String _fallbackGlyph(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return 'C';
  }
  final fileName = trimmed.replaceAll('\\', '/').split('/').last;
  if (fileName.isNotEmpty && fileName.contains('.')) {
    final first = fileName.substring(0, 1);
    if (RegExp(r'[A-Za-z0-9]').hasMatch(first)) {
      return first.toUpperCase();
    }
  }
  final first = trimmed.substring(0, 1);
  if (RegExp(r'[A-Za-z0-9]').hasMatch(first)) {
    return first.toUpperCase();
  }
  return 'C';
}
