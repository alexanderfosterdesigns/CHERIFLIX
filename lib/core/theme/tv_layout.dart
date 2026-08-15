import 'package:flutter/material.dart';

enum CheriflixTvWidthTier {
  compact,
  standard,
  wide,
}

class CheriflixTvLayout {
  const CheriflixTvLayout._({
    required this.width,
    required this.tier,
  });

  final double width;
  final CheriflixTvWidthTier tier;

  bool get isCompact => tier == CheriflixTvWidthTier.compact;
  bool get isStandard => tier == CheriflixTvWidthTier.standard;
  bool get isWide => tier == CheriflixTvWidthTier.wide;

  static CheriflixTvLayout of(BuildContext context) {
    return fromWidth(MediaQuery.sizeOf(context).width);
  }

  static CheriflixTvLayout fromWidth(double width) {
    final resolvedWidth = width.isFinite && width > 0 ? width : 1280.0;
    if (resolvedWidth < 1100) {
      return CheriflixTvLayout._(
        width: resolvedWidth,
        tier: CheriflixTvWidthTier.compact,
      );
    }
    if (resolvedWidth < 1600) {
      return CheriflixTvLayout._(
        width: resolvedWidth,
        tier: CheriflixTvWidthTier.standard,
      );
    }
    return CheriflixTvLayout._(
      width: resolvedWidth,
      tier: CheriflixTvWidthTier.wide,
    );
  }

  T select<T>({
    required T compact,
    required T standard,
    T? wide,
  }) {
    return switch (tier) {
      CheriflixTvWidthTier.compact => compact,
      CheriflixTvWidthTier.standard => standard,
      CheriflixTvWidthTier.wide => wide ?? standard,
    };
  }

  double value({
    required double compact,
    required double standard,
    double? wide,
  }) {
    return select<double>(
      compact: compact,
      standard: standard,
      wide: wide,
    );
  }

  EdgeInsets insets({
    required EdgeInsets compact,
    required EdgeInsets standard,
    EdgeInsets? wide,
  }) {
    return select<EdgeInsets>(
      compact: compact,
      standard: standard,
      wide: wide,
    );
  }

  EdgeInsets get topBarPadding => insets(
        compact: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        standard: const EdgeInsets.fromLTRB(18, 12, 18, 10),
        wide: const EdgeInsets.fromLTRB(22, 14, 22, 12),
      );

  double get topBarLogoHeight => value(
        compact: 34,
        standard: 38,
        wide: 42,
      );

  double get topBarTabSpacing => value(
        compact: 16,
        standard: 18,
        wide: 22,
      );

  double get topBarDividerHeight => value(
        compact: 34,
        standard: 36,
        wide: 40,
      );

  double get topBarActionSize => value(
        compact: 42,
        standard: 44,
        wide: 48,
      );

  double get topBarActionIconSize => value(
        compact: 22,
        standard: 23,
        wide: 25,
      );

  double get topBarPassiveIconBoxSize => value(
        compact: 36,
        standard: 38,
        wide: 42,
      );

  double get topBarPassiveIconSize => value(
        compact: 20,
        standard: 21,
        wide: 24,
      );

  EdgeInsets get topBarCompactProfilePadding => insets(
        compact: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        standard: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        wide: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      );

  double get topBarCompactProfileOuterSize => value(
        compact: 32,
        standard: 34,
        wide: 38,
      );

  double get topBarCompactProfileAvatarSize => value(
        compact: 26,
        standard: 28,
        wide: 32,
      );

  double get topBarCompactArrowSize => value(
        compact: 16,
        standard: 18,
        wide: 18,
      );

  double get panelRadius => value(
        compact: 18,
        standard: 20,
        wide: 22,
      );

  double get panelBorderWidth => value(
        compact: 1,
        standard: 1,
        wide: 1.15,
      );

  double get panelShadowBlur => value(
        compact: 16,
        standard: 18,
        wide: 20,
      );

  double get panelShadowOffsetY => value(
        compact: 10,
        standard: 12,
        wide: 14,
      );

  EdgeInsets get pagePadding => insets(
        compact: const EdgeInsets.fromLTRB(18, 12, 18, 22),
        standard: const EdgeInsets.fromLTRB(24, 14, 24, 24),
        wide: const EdgeInsets.fromLTRB(30, 18, 30, 28),
      );

  EdgeInsets get dialogInsetPadding => insets(
        compact: const EdgeInsets.all(16),
        standard: const EdgeInsets.all(22),
        wide: const EdgeInsets.all(24),
      );

  double get dialogMaxWidth => value(
        compact: 920,
        standard: 1120,
        wide: 1240,
      );

  double get dialogMaxHeight => value(
        compact: 620,
        standard: 700,
        wide: 760,
      );

  double get sectionTitleSize => value(
        compact: 20,
        standard: 22,
        wide: 24,
      );

  double get bodySize => value(
        compact: 14,
        standard: 15,
        wide: 16,
      );

  double get bodySecondarySize => value(
        compact: 13,
        standard: 15,
        wide: 16,
      );

  double get formTitleSize => value(
        compact: 30,
        standard: 34,
        wide: 38,
      );

  double get formLabelSize => value(
        compact: 13,
        standard: 14,
        wide: 15,
      );

  double get profileArtworkSize => value(
        compact: 132,
        standard: 150,
        wide: 176,
      );

  double get profileSelectionContentMaxWidth => value(
        compact: 920,
        standard: 1080,
        wide: 1180,
      );

  double get profileSelectionTitleSize => value(
        compact: 34,
        standard: 40,
        wide: 46,
      );

  double get profileSelectionCardWidth => value(
        compact: 182,
        standard: 198,
        wide: 214,
      );

  double get profileSelectionCardRadius => value(
        compact: 18,
        standard: 19,
        wide: 20,
      );

  double get profileSelectionAvatarRadius => value(
        compact: 16,
        standard: 17,
        wide: 18,
      );

  double get profileSelectionAvatarSize => value(
        compact: 96,
        standard: 106,
        wide: 118,
      );

  double get profileSelectionFallbackAvatarFontSize => value(
        compact: 34,
        standard: 38,
        wide: 42,
      );

  double get profileSelectionIconSize => value(
        compact: 64,
        standard: 70,
        wide: 78,
      );

  double get profileSelectionCardTitleSize => value(
        compact: 18,
        standard: 20,
        wide: 22,
      );

  double get profileSelectionMetaSize => value(
        compact: 12,
        standard: 13,
        wide: 14,
      );

  double get profileSelectionCardSpacing => value(
        compact: 18,
        standard: 20,
        wide: 24,
      );

  double get profileSelectionReflectionHeight => value(
        compact: 112,
        standard: 124,
        wide: 136,
      );

  double get profileSelectionReflectionOffset => value(
        compact: 116,
        standard: 128,
        wide: 140,
      );

  EdgeInsets get profileSelectionCardPadding => insets(
        compact: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        standard: const EdgeInsets.fromLTRB(20, 20, 20, 22),
        wide: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      );

  double get avatarPickerTitleSize => value(
        compact: 24,
        standard: 27,
        wide: 30,
      );

  double get avatarPickerSubtitleSize => value(
        compact: 13,
        standard: 14,
        wide: 15,
      );

  double get avatarPickerCategoryTitleSize => value(
        compact: 28,
        standard: 31,
        wide: 34,
      );

  double get avatarPickerRowHeight => value(
        compact: 86,
        standard: 94,
        wide: 106,
      );

  double get avatarPickerTileSize => value(
        compact: 74,
        standard: 82,
        wide: 94,
      );

  double get avatarPickerTileRadius => value(
        compact: 8,
        standard: 9,
        wide: 10,
      );

  double get avatarPickerFallbackFontSize => value(
        compact: 28,
        standard: 31,
        wide: 34,
      );

  double get avatarPickerGap => value(
        compact: 10,
        standard: 11,
        wide: 12,
      );

  double get homeHeroHeight => value(
        compact: 408,
        standard: 470,
        wide: 540,
      );

  double get homeHeroContentLeftPadding => value(
        compact: 20,
        standard: 24,
        wide: 30,
      );

  double get homeHeroContentTopPadding => value(
        compact: 26,
        standard: 32,
        wide: 40,
      );

  double get homeHeroContentBottomPadding => value(
        compact: 24,
        standard: 28,
        wide: 36,
      );

  double get homeHeroTitleMaxWidth => value(
        compact: 320,
        standard: 380,
        wide: 470,
      );

  double get homeHeroCopyMaxWidth => value(
        compact: 360,
        standard: 430,
        wide: 520,
      );

  double get homeHeroActionSpacing => value(
        compact: 10,
        standard: 12,
        wide: 14,
      );

  double get homeRailCardWidth => value(
        compact: 184,
        standard: 208,
        wide: 232,
      );

  double get homeRailCardPosterHeight => value(
        compact: 262,
        standard: 294,
        wide: 328,
      );

  double get homeRailExpandedPosterHeight => value(
        compact: 272,
        standard: 308,
        wide: 344,
      );

  double get homeRailGap => value(
        compact: 12,
        standard: 13,
        wide: 14,
      );

  double get homeRailCollapsedTitleHeight => value(
        compact: 38,
        standard: 42,
        wide: 44,
      );

  double get homeRailCollapsedSubtitleHeight => value(
        compact: 16,
        standard: 17,
        wide: 18,
      );

  double get homeRailSafeMargin => value(
        compact: 28,
        standard: 34,
        wide: 40,
      );

  double get settingsContentMaxWidth => value(
        compact: 960,
        standard: 1080,
        wide: 1180,
      );

  double get settingsPanelPaddingValue => value(
        compact: 24,
        standard: 30,
        wide: 36,
      );

  double get settingsAvatarBlockWidth => value(
        compact: 150,
        standard: 164,
        wide: 180,
      );

  double get settingsArtworkSize => value(
        compact: 128,
        standard: 144,
        wide: 160,
      );

  double get settingsSectionTitleSize => value(
        compact: 22,
        standard: 24,
        wide: 26,
      );

  double get episodesSeasonRailWidth => value(
        compact: width,
        standard: 280,
        wide: 320,
      );

  double get episodesTitleSize => value(
        compact: 32,
        standard: 36,
        wide: 42,
      );

  double get episodesMetadataSize => value(
        compact: 14,
        standard: 15,
        wide: 16,
      );

  double get episodesPaneRadius => value(
        compact: 18,
        standard: 20,
        wide: 22,
      );

  double get episodesPanePadding => value(
        compact: 12,
        standard: 14,
        wide: 16,
      );

  double get episodeRowPadding => value(
        compact: 8,
        standard: 10,
        wide: 12,
      );

  double get episodeImageWidth => value(
        compact: 188,
        standard: 220,
        wide: 252,
      );

  double get episodeImageHeight => value(
        compact: 106,
        standard: 124,
        wide: 142,
      );

  double get episodeTitleSize => value(
        compact: 17,
        standard: 19,
        wide: 21,
      );

  double get episodeSynopsisSize => value(
        compact: 13,
        standard: 14,
        wide: 15,
      );

  double get episodeMetaSize => value(
        compact: 12,
        standard: 13,
        wide: 14,
      );

  double get detailHeroMaxWidth => value(
        compact: width * 0.72,
        standard: 760,
        wide: 860,
      );

  EdgeInsets get detailShellPadding => insets(
        compact: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        standard: const EdgeInsets.fromLTRB(34, 30, 34, 28),
        wide: const EdgeInsets.fromLTRB(46, 38, 46, 34),
      );

  double get detailHeroTitleSize => value(
        compact: 34,
        standard: 38,
        wide: 40,
      );

  double get detailHeroBodySize => value(
        compact: 14,
        standard: 15,
        wide: 16,
      );

  double get detailHeroActionScale => value(
        compact: 1.0,
        standard: 1.02,
        wide: 1.04,
      );

  double get detailRecommendationCardWidth => value(
        compact: 250,
        standard: 278,
        wide: 308,
      );

  double get detailRecommendationPosterHeight => value(
        compact: 356,
        standard: 396,
        wide: 440,
      );

  double get detailRecommendationExpandedPosterHeight => value(
        compact: 380,
        standard: 422,
        wide: 468,
      );

  double get detailRecommendationGap => value(
        compact: 14,
        standard: 16,
        wide: 18,
      );
}
