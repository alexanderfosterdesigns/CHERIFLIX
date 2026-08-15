import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../services/profile_avatar_catalog.dart';
import '../theme/cheriflix_theme.dart';
import '../theme/tv_layout.dart';
import 'bounded_asset_image.dart';
import 'profile_avatar.dart';
import 'tv_shortcuts.dart';

class CheriflixScaffold extends StatelessWidget {
  const CheriflixScaffold({
    super.key,
    required this.body,
    this.topBar,
    this.useSafeArea = true,
  });

  final Widget body;
  final Widget? topBar;
  final bool useSafeArea;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: <Widget>[
        if (topBar != null) topBar!,
        Expanded(child: body),
      ],
    );

    return Scaffold(
      body: CheriflixBackdrop(
        child: useSafeArea ? SafeArea(child: content) : content,
      ),
    );
  }
}

class CheriflixBackdrop extends StatelessWidget {
  const CheriflixBackdrop({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: CheriflixColors.background,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF070707),
            CheriflixColors.background,
            Color(0xFF101010),
          ],
        ),
      ),
      child: child,
    );
  }
}

class CheriflixTopBar extends StatelessWidget {
  const CheriflixTopBar({
    super.key,
    this.activeTab,
    this.profile,
    this.onHome,
    this.onTvShows,
    this.onMovies,
    this.onNewPopular,
    this.onMyList,
    this.onSearch,
    this.onSettings,
    this.onProfiles,
    this.showTabs = true,
    this.showActions = true,
    this.downFallbackNodes = const <FocusNode>[],
    this.onControlFocusChanged,
    this.homeFocusNode,
    this.tvShowsFocusNode,
    this.moviesFocusNode,
    this.newPopularFocusNode,
    this.myListFocusNode,
    this.searchFocusNode,
    this.settingsFocusNode,
    this.profilesFocusNode,
  });

  final String? activeTab;
  final Profile? profile;
  final VoidCallback? onHome;
  final VoidCallback? onTvShows;
  final VoidCallback? onMovies;
  final VoidCallback? onNewPopular;
  final VoidCallback? onMyList;
  final VoidCallback? onSearch;
  final VoidCallback? onSettings;
  final VoidCallback? onProfiles;
  final bool showTabs;
  final bool showActions;
  final List<FocusNode> downFallbackNodes;
  final ValueChanged<bool>? onControlFocusChanged;
  final FocusNode? homeFocusNode;
  final FocusNode? tvShowsFocusNode;
  final FocusNode? moviesFocusNode;
  final FocusNode? newPopularFocusNode;
  final FocusNode? myListFocusNode;
  final FocusNode? searchFocusNode;
  final FocusNode? settingsFocusNode;
  final FocusNode? profilesFocusNode;

  @override
  Widget build(BuildContext context) {
    final layout = CheriflixTvLayout.of(context);
    final orderedFocusNodes = <FocusNode?>[
      homeFocusNode,
      tvShowsFocusNode,
      moviesFocusNode,
      newPopularFocusNode,
      myListFocusNode,
      searchFocusNode,
      settingsFocusNode,
      profilesFocusNode,
    ];
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: CheriflixColors.nav,
          border: Border(
            top: BorderSide(color: Color(0x1AFFFFFF)),
            bottom: BorderSide(color: Color(0x14FFFFFF)),
          ),
        ),
        child: Padding(
          padding: layout.topBarPadding,
          child: Row(
            children: <Widget>[
              CheriflixLogo(height: layout.topBarLogoHeight),
              if (showTabs) ...<Widget>[
                SizedBox(width: layout.topBarTabSpacing),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        _buildTab(
                          context,
                          'Home',
                          onHome,
                          focusNode: homeFocusNode,
                          leftFallbackNodes: _leftFallbackNodesFor(
                            homeFocusNode,
                            orderedFocusNodes,
                          ),
                          rightFallbackNodes: _rightFallbackNodesFor(
                            homeFocusNode,
                            orderedFocusNodes,
                          ),
                        ),
                        _buildTab(
                          context,
                          'TV Shows',
                          onTvShows,
                          focusNode: tvShowsFocusNode,
                          leftFallbackNodes: _leftFallbackNodesFor(
                            tvShowsFocusNode,
                            orderedFocusNodes,
                          ),
                          rightFallbackNodes: _rightFallbackNodesFor(
                            tvShowsFocusNode,
                            orderedFocusNodes,
                          ),
                        ),
                        _buildTab(
                          context,
                          'Movies',
                          onMovies,
                          focusNode: moviesFocusNode,
                          leftFallbackNodes: _leftFallbackNodesFor(
                            moviesFocusNode,
                            orderedFocusNodes,
                          ),
                          rightFallbackNodes: _rightFallbackNodesFor(
                            moviesFocusNode,
                            orderedFocusNodes,
                          ),
                        ),
                        _buildTab(
                          context,
                          'New & Popular',
                          onNewPopular,
                          focusNode: newPopularFocusNode,
                          leftFallbackNodes: _leftFallbackNodesFor(
                            newPopularFocusNode,
                            orderedFocusNodes,
                          ),
                          rightFallbackNodes: _rightFallbackNodesFor(
                            newPopularFocusNode,
                            orderedFocusNodes,
                          ),
                        ),
                        _buildTab(
                          context,
                          'My List',
                          onMyList,
                          focusNode: myListFocusNode,
                          leftFallbackNodes: _leftFallbackNodesFor(
                            myListFocusNode,
                            orderedFocusNodes,
                          ),
                          rightFallbackNodes: _rightFallbackNodesFor(
                            myListFocusNode,
                            orderedFocusNodes,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else
                const Spacer(),
              if (showActions) ...<Widget>[
                Container(
                  width: 1,
                  height: layout.topBarDividerHeight,
                  color: const Color(0x16FFFFFF),
                ),
                SizedBox(
                    width: layout.value(compact: 10, standard: 12, wide: 14)),
                _buildAction(
                  context: context,
                  icon: Icons.search_rounded,
                  label: 'Search',
                  onPressed: onSearch,
                  onFocusChanged: onControlFocusChanged,
                  focusNode: searchFocusNode,
                  leftFallbackNodes: _leftFallbackNodesFor(
                    searchFocusNode,
                    orderedFocusNodes,
                  ),
                  rightFallbackNodes: _rightFallbackNodesFor(
                    searchFocusNode,
                    orderedFocusNodes,
                  ),
                ),
                SizedBox(width: layout.value(compact: 4, standard: 6)),
                _buildAction(
                  context: context,
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  onPressed: onSettings,
                  onFocusChanged: onControlFocusChanged,
                  focusNode: settingsFocusNode,
                  leftFallbackNodes: _leftFallbackNodesFor(
                    settingsFocusNode,
                    orderedFocusNodes,
                  ),
                  rightFallbackNodes: _rightFallbackNodesFor(
                    settingsFocusNode,
                    orderedFocusNodes,
                  ),
                ),
                SizedBox(width: layout.value(compact: 6, standard: 8)),
                onProfiles == null
                    ? CheriflixPassiveProfilePill(
                        avatarLabel: profile?.avatarLabel ?? 'C',
                        compact: true,
                      )
                    : TvProfileButton(
                        avatarLabel: profile?.avatarLabel ?? 'C',
                        onPressed: onProfiles,
                        style: TvProfileButtonStyle.topBarCompact,
                        focusNode: profilesFocusNode,
                        downFallbackNodes: downFallbackNodes,
                        leftFallbackNodes: _leftFallbackNodesFor(
                          profilesFocusNode,
                          orderedFocusNodes,
                        ),
                        rightFallbackNodes: _rightFallbackNodesFor(
                          profilesFocusNode,
                          orderedFocusNodes,
                        ),
                        onFocusChanged: onControlFocusChanged,
                      ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAction({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    ValueChanged<bool>? onFocusChanged,
    FocusNode? focusNode,
    List<FocusNode> leftFallbackNodes = const <FocusNode>[],
    List<FocusNode> rightFallbackNodes = const <FocusNode>[],
  }) {
    final layout = CheriflixTvLayout.of(context);
    if (onPressed == null) {
      return CheriflixPassiveIconButton(
        icon: icon,
        label: label,
        topBarPlain: true,
      );
    }

    return TvIconButton(
      icon: icon,
      label: label,
      onPressed: onPressed,
      size: layout.topBarActionSize,
      iconSize: layout.topBarActionIconSize,
      style: TvIconButtonStyle.topBarPlain,
      focusNode: focusNode,
      downFallbackNodes: downFallbackNodes,
      leftFallbackNodes: leftFallbackNodes,
      rightFallbackNodes: rightFallbackNodes,
      onFocusChanged: onFocusChanged,
    );
  }

  Widget _buildTab(
    BuildContext context,
    String label,
    VoidCallback? onPressed, {
    FocusNode? focusNode,
    List<FocusNode> leftFallbackNodes = const <FocusNode>[],
    List<FocusNode> rightFallbackNodes = const <FocusNode>[],
  }) {
    final tabSpacing = CheriflixTvLayout.of(context).topBarTabSpacing;
    if (onPressed == null) {
      return Padding(
        padding: EdgeInsets.only(right: tabSpacing),
        child: CheriflixNavPill(
          label: label,
          active: activeTab == label,
          topBarStyle: true,
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(right: tabSpacing),
      child: TvNavPillButton(
        label: label,
        onPressed: onPressed,
        active: activeTab == label,
        style: TvNavPillStyle.topBarUnderline,
        focusNode: focusNode,
        downFallbackNodes: downFallbackNodes,
        leftFallbackNodes: leftFallbackNodes,
        rightFallbackNodes: rightFallbackNodes,
        onFocusChanged: onControlFocusChanged,
      ),
    );
  }

  List<FocusNode> _leftFallbackNodesFor(
    FocusNode? currentNode,
    List<FocusNode?> orderedNodes,
  ) {
    final fallbackNode = _adjacentFocusableNode(
      currentNode,
      orderedNodes,
      step: -1,
    );
    if (fallbackNode != null) {
      return <FocusNode>[fallbackNode];
    }
    return currentNode == null ? const <FocusNode>[] : <FocusNode>[currentNode];
  }

  List<FocusNode> _rightFallbackNodesFor(
    FocusNode? currentNode,
    List<FocusNode?> orderedNodes,
  ) {
    final fallbackNode = _adjacentFocusableNode(
      currentNode,
      orderedNodes,
      step: 1,
    );
    if (fallbackNode != null) {
      return <FocusNode>[fallbackNode];
    }
    return currentNode == null ? const <FocusNode>[] : <FocusNode>[currentNode];
  }

  FocusNode? _adjacentFocusableNode(
    FocusNode? currentNode,
    List<FocusNode?> orderedNodes, {
    required int step,
  }) {
    if (currentNode == null) {
      return null;
    }
    final currentIndex = orderedNodes.indexOf(currentNode);
    if (currentIndex < 0) {
      return null;
    }
    for (var index = currentIndex + step;
        index >= 0 && index < orderedNodes.length;
        index += step) {
      final candidate = orderedNodes[index];
      if (candidate != null) {
        return candidate;
      }
    }
    return null;
  }
}

class CheriflixLogo extends StatelessWidget {
  const CheriflixLogo({
    super.key,
    this.height = 64,
  });

  final double height;

  @override
  Widget build(BuildContext context) {
    final layout = CheriflixTvLayout.of(context);
    final width =
        height * layout.value(compact: 4.05, standard: 4.15, wide: 4.25);
    return SizedBox(
      width: width,
      height: height,
      child: Image(
        image: boundedAssetImageProvider(
          context,
          CheriflixAssets.logo,
          logicalWidth: width,
          logicalHeight: height,
          maxDecodeWidth: 1024,
          maxDecodeHeight: 320,
        ),
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        filterQuality: FilterQuality.low,
        errorBuilder: (context, error, stackTrace) {
          return Text(
            'CHERIFLIX',
            style: CheriflixTypography.sectionTitle.copyWith(
              fontSize: layout.value(compact: 22, standard: 24, wide: 28),
              letterSpacing: 1,
            ),
          );
        },
      ),
    );
  }
}

class CheriflixNavPill extends StatelessWidget {
  const CheriflixNavPill({
    super.key,
    required this.label,
    this.active = false,
    this.topBarStyle = false,
  });

  final String label;
  final bool active;
  final bool topBarStyle;

  @override
  Widget build(BuildContext context) {
    if (topBarStyle) {
      final layout = CheriflixTvLayout.of(context);
      return SizedBox(
        height: layout.value(compact: 42, standard: 46, wide: 52),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            6,
            layout.value(compact: 8, standard: 10, wide: 12),
            6,
            layout.value(compact: 6, standard: 7, wide: 8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: CheriflixTypography.button.copyWith(
                  color: active
                      ? CheriflixColors.textPrimary
                      : const Color(0xFFD7D7D7),
                  fontSize: layout.value(compact: 13, standard: 14, wide: 15),
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
              Container(
                width: layout.value(compact: 56, standard: 60, wide: 66),
                height: layout.value(compact: 2.5, standard: 2.75, wide: 3),
                decoration: BoxDecoration(
                  color:
                      active ? CheriflixColors.accentRed : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(
        color: active ? Colors.white : const Color(0xFF101010),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: active ? Colors.white : const Color(0x26FFFFFF),
        ),
        boxShadow: active
            ? const <BoxShadow>[
                BoxShadow(
                  color: Color(0x22FFFFFF),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ]
            : const <BoxShadow>[],
      ),
      child: Text(
        label,
        style: CheriflixTypography.button.copyWith(
          color: active ? Colors.black : CheriflixColors.textPrimary,
          fontSize: 13,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class CheriflixPassiveIconButton extends StatelessWidget {
  const CheriflixPassiveIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.topBarPlain = false,
  });

  final IconData icon;
  final String label;
  final bool topBarPlain;

  @override
  Widget build(BuildContext context) {
    final layout = CheriflixTvLayout.of(context);
    return Tooltip(
      message: label,
      child: Container(
        width: topBarPlain ? layout.topBarPassiveIconBoxSize : 48,
        height: topBarPlain ? layout.topBarPassiveIconBoxSize : 48,
        decoration: BoxDecoration(
          color: topBarPlain ? Colors.transparent : const Color(0xFF121212),
          shape: topBarPlain ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: topBarPlain ? BorderRadius.circular(8) : null,
          border: Border.all(
            color: topBarPlain ? Colors.transparent : const Color(0x20FFFFFF),
          ),
          boxShadow: topBarPlain
              ? const <BoxShadow>[]
              : const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 12,
                    offset: Offset(0, 8),
                  ),
                ],
        ),
        child: Icon(
          icon,
          color: CheriflixColors.textPrimary,
          size: topBarPlain ? layout.topBarPassiveIconSize : 24,
        ),
      ),
    );
  }
}

class CheriflixPassiveProfilePill extends StatelessWidget {
  const CheriflixPassiveProfilePill({
    super.key,
    required this.avatarLabel,
    this.compact = false,
  });

  final String avatarLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final layout = CheriflixTvLayout.of(context);
    final compactPadding = layout.topBarCompactProfilePadding;
    final compactOuterSize = layout.topBarCompactProfileOuterSize;
    final compactAvatarSize = layout.topBarCompactProfileAvatarSize;
    return Container(
      padding: compact
          ? compactPadding
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: compact ? Colors.transparent : const Color(0xFF181818),
        borderRadius: BorderRadius.circular(compact ? 8 : 15),
        border: Border.all(
          color: compact ? Colors.transparent : const Color(0x26FFFFFF),
        ),
        boxShadow: compact
            ? const <BoxShadow>[]
            : const <BoxShadow>[
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 12,
                  offset: Offset(0, 8),
                ),
              ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: compact ? compactOuterSize : 36,
            height: compact ? compactOuterSize : 36,
            decoration: BoxDecoration(
              color: null,
              borderRadius: BorderRadius.circular(compact ? 8 : 999),
            ),
            padding: EdgeInsets.all(compact ? 3 : 0),
            child: CheriflixProfileAvatar(
              avatarLabel: avatarLabel,
              width: compact ? compactAvatarSize : 36,
              height: compact ? compactAvatarSize : 36,
              shape: compact ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: compact ? BorderRadius.circular(6) : null,
              fallbackTextStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                color: CheriflixColors.textPrimary,
              ),
            ),
          ),
          if (!compact) ...<Widget>[
            const SizedBox(width: 12),
            Text(
              'PROFILES',
              style: CheriflixTypography.button.copyWith(
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(width: 6),
          ] else ...<Widget>[
            const SizedBox(width: 6),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: layout.topBarCompactArrowSize,
              color: CheriflixColors.textPrimary,
            ),
          ],
        ],
      ),
    );
  }
}

class CheriflixPanel extends StatelessWidget {
  const CheriflixPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final layout = CheriflixTvLayout.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xEE1A1A1A),
        borderRadius: BorderRadius.circular(layout.panelRadius),
        border: Border.all(
          color: const Color(0x18FFFFFF),
          width: layout.panelBorderWidth,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0xA3000000),
            blurRadius: layout.panelShadowBlur,
            offset: Offset(0, layout.panelShadowOffsetY),
          ),
        ],
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

class CheriflixSectionTitle extends StatelessWidget {
  const CheriflixSectionTitle({
    super.key,
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: CheriflixTypography.sectionTitle,
    );
  }
}

class CheriflixBadge extends StatelessWidget {
  const CheriflixBadge({
    super.key,
    required this.label,
    this.backgroundColor = CheriflixColors.surface,
    this.foregroundColor = CheriflixColors.textPrimary,
    this.borderColor,
    this.compact = false,
    this.textStyle,
    this.padding,
    this.borderRadius,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;
  final bool compact;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ??
          EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: compact ? 6 : 8,
          ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius ?? 999),
        border: borderColor == null ? null : Border.all(color: borderColor!),
      ),
      child: Text(
        label,
        style: (textStyle ?? CheriflixTypography.metadata).copyWith(
          color: foregroundColor,
          fontSize: compact ? 12 : 13,
          letterSpacing: compact ? 0.18 : 0.24,
        ),
      ),
    );
  }
}

class CheriflixProfileArtwork extends StatelessWidget {
  const CheriflixProfileArtwork({
    super.key,
    required this.avatarLabel,
    this.size = 148,
    this.avatarCatalogService,
  });

  final String avatarLabel;
  final double size;
  final ProfileAvatarCatalogService? avatarCatalogService;

  @override
  Widget build(BuildContext context) {
    final layout = CheriflixTvLayout.of(context);
    final resolvedSize = size == 148 ? layout.profileArtworkSize : size;
    final borderRadius = layout.value(compact: 18, standard: 19, wide: 20);
    return Container(
      width: resolvedSize,
      height: resolvedSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color: const Color(0xFF202A30),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: CheriflixProfileAvatar(
        avatarLabel: avatarLabel,
        width: resolvedSize,
        height: resolvedSize,
        borderRadius: BorderRadius.circular(borderRadius),
        avatarCatalogService: avatarCatalogService,
        fallbackBackgroundColor: const Color(0xFF0EA5C6),
        fallbackTextStyle: TextStyle(
          fontSize: resolvedSize * 0.42,
          color: CheriflixColors.textPrimary,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
