import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/profile.dart';
import '../../core/theme/cheriflix_theme.dart';
import '../../core/theme/tv_layout.dart';
import '../../core/widgets/cheriflix_chrome.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../core/widgets/tv_shortcuts.dart';

class ProfileSelectionScreen extends StatelessWidget {
  const ProfileSelectionScreen({
    super.key,
    required this.profiles,
    required this.onSelectProfile,
    required this.onCreateProfile,
  });

  final List<Profile> profiles;
  final ValueChanged<Profile> onSelectProfile;
  final VoidCallback onCreateProfile;

  @override
  Widget build(BuildContext context) {
    return TvShortcutScope(
      child: CheriflixScaffold(
        topBar: const CheriflixTopBar(showTabs: false, showActions: false),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final layout = CheriflixTvLayout.fromWidth(constraints.maxWidth);
            return Padding(
              padding: layout.pagePadding,
              child: Center(
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context)
                      .copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      layout.value(compact: 18, standard: 24, wide: 32),
                      layout.value(compact: 18, standard: 20, wide: 24),
                      layout.value(compact: 18, standard: 24, wide: 32),
                      layout.value(compact: 20, standard: 24, wide: 32),
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight > 80
                            ? constraints.maxHeight - 80
                            : 0,
                        maxWidth: layout.profileSelectionContentMaxWidth,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Text(
                            'Who\'s watching?',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: layout.profileSelectionTitleSize,
                              fontWeight: FontWeight.w900,
                              height: 1.05,
                            ),
                          ),
                          SizedBox(
                            height: layout.profileSelectionCardSpacing + 8,
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: layout.value(
                                compact: 0,
                                standard: 4,
                                wide: 8,
                              ),
                            ),
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              spacing: layout.profileSelectionCardSpacing,
                              runSpacing: layout.profileSelectionCardSpacing,
                              children: <Widget>[
                                for (var index = 0;
                                    index < profiles.length;
                                    index += 1)
                                  _ProfileCard(
                                    profile: profiles[index],
                                    onTap: () =>
                                        onSelectProfile(profiles[index]),
                                    autofocus: index == 0,
                                  ),
                                _CreateProfileCard(
                                  onTap: onCreateProfile,
                                  autofocus: profiles.isEmpty,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ProfileCard extends StatefulWidget {
  const _ProfileCard({
    required this.profile,
    required this.onTap,
    this.autofocus = false,
  });

  final Profile profile;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  bool _focused = false;
  late final FocusNode _focusNode =
      FocusNode(debugLabel: 'ProfileCard(${widget.profile.name})');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = CheriflixTvLayout.of(context);
    return _SelectableProfileTile(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      focused: _focused,
      onFocusChanged: (value) => setState(() => _focused = value),
      onTap: widget.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CheriflixProfileAvatar(
            avatarLabel: widget.profile.avatarLabel,
            width: layout.profileSelectionAvatarSize,
            height: layout.profileSelectionAvatarSize,
            borderRadius: BorderRadius.circular(
              layout.profileSelectionAvatarRadius,
            ),
            fallbackTextStyle: TextStyle(
              color: CheriflixColors.textPrimary,
              fontSize: layout.profileSelectionFallbackAvatarFontSize,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: layout.value(compact: 14, standard: 16, wide: 18)),
          Text(
            widget.profile.name,
            style: TextStyle(
              fontSize: layout.profileSelectionCardTitleSize,
              fontWeight: FontWeight.w900,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: layout.value(compact: 6, standard: 7, wide: 8)),
          Text(
            widget.profile.languageCode.toUpperCase(),
            style: TextStyle(
              color: CheriflixColors.textSecondary,
              fontSize: layout.profileSelectionMetaSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateProfileCard extends StatefulWidget {
  const _CreateProfileCard({
    required this.onTap,
    this.autofocus = false,
  });

  final VoidCallback onTap;
  final bool autofocus;

  @override
  State<_CreateProfileCard> createState() => _CreateProfileCardState();
}

class _CreateProfileCardState extends State<_CreateProfileCard> {
  bool _focused = false;
  late final FocusNode _focusNode =
      FocusNode(debugLabel: 'ProfileCard(CreateProfile)');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = CheriflixTvLayout.of(context);
    return _SelectableProfileTile(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      focused: _focused,
      onFocusChanged: (value) => setState(() => _focused = value),
      onTap: widget.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: layout.profileSelectionAvatarSize,
            height: layout.profileSelectionAvatarSize,
            decoration: BoxDecoration(
              color: const Color(0xFF171717),
              borderRadius: BorderRadius.circular(
                layout.profileSelectionAvatarRadius,
              ),
            ),
            child: Icon(
              Icons.add_rounded,
              size: layout.profileSelectionIconSize,
              color: CheriflixColors.textPrimary,
            ),
          ),
          SizedBox(height: layout.value(compact: 14, standard: 16, wide: 18)),
          Text(
            'Create profile',
            style: TextStyle(
              fontSize: layout.profileSelectionCardTitleSize,
              fontWeight: FontWeight.w900,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: layout.value(compact: 6, standard: 7, wide: 8)),
          Text(
            'NEW',
            style: TextStyle(
              color: CheriflixColors.textSecondary,
              fontSize: layout.profileSelectionMetaSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectableProfileTile extends StatelessWidget {
  const _SelectableProfileTile({
    required this.focusNode,
    required this.autofocus,
    required this.focused,
    required this.onFocusChanged,
    required this.onTap,
    required this.child,
  });

  final FocusNode focusNode;
  final bool autofocus;
  final bool focused;
  final ValueChanged<bool> onFocusChanged;
  final VoidCallback onTap;
  final Widget child;

  Widget _buildTileSurface({
    required BuildContext context,
    required bool focused,
    bool forReflection = false,
  }) {
    final layout = CheriflixTvLayout.of(context);
    return Container(
      width: layout.profileSelectionCardWidth,
      padding: layout.profileSelectionCardPadding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            focused ? const Color(0x10FFFFFF) : const Color(0x06FFFFFF),
            const Color(0x02000000),
            const Color(0xFF080808),
          ],
          stops: const <double>[0, 0.2, 1],
        ),
        borderRadius: BorderRadius.circular(layout.profileSelectionCardRadius),
        border: forReflection
            ? null
            : Border.all(
                color:
                    focused ? const Color(0x55FFFFFF) : const Color(0x12FFFFFF),
                width: focused ? 2 : 1,
              ),
        boxShadow: forReflection
            ? null
            : <BoxShadow>[
                const BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
                if (focused)
                  const BoxShadow(
                    color: Color(0x14FFFFFF),
                    blurRadius: 8,
                    spreadRadius: 0.5,
                  ),
              ],
      ),
      child: child,
    );
  }

  Widget _buildReflection(
    BuildContext context, {
    required bool focused,
  }) {
    final layout = CheriflixTvLayout.of(context);
    return Positioned(
      left: -2,
      right: -2,
      bottom: -layout.profileSelectionReflectionOffset,
      height: layout.profileSelectionReflectionHeight,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: focused ? 0.42 : 0.26,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: AnimatedScale(
            scale: focused ? 1.0 : 0.98,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: RepaintBoundary(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (Rect rect) {
                  return const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Color(0x00000000),
                      Color(0xFF909090),
                      Color(0xFF505050),
                      Color(0x00101010),
                    ],
                    stops: <double>[0.0, 0.08, 0.5, 1.0],
                  ).createShader(rect);
                },
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: 1.2,
                    sigmaY: 4.0,
                    tileMode: TileMode.decal,
                  ),
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: 0.75,
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minWidth: 0,
                        maxWidth: double.infinity,
                        minHeight: 0,
                        maxHeight: double.infinity,
                        child: Transform.translate(
                          offset: const Offset(0, -2),
                          child: Transform.flip(
                            flipY: true,
                            child: _buildTileSurface(
                              context: context,
                              focused: focused,
                              forReflection: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              onTap();
              return null;
            },
          ),
        },
        child: FocusableActionDetector(
          focusNode: focusNode,
          autofocus: autofocus,
          onShowFocusHighlight: onFocusChanged,
          child: AnimatedScale(
            scale: focused ? 1.05 : 1,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: <Widget>[
                _buildReflection(
                  context,
                  focused: focused,
                ),
                InkWell(
                  onTap: () {
                    focusNode.requestFocus();
                    onTap();
                  },
                  borderRadius: BorderRadius.circular(
                    CheriflixTvLayout.of(context).profileSelectionCardRadius,
                  ),
                  child: _buildTileSurface(
                    context: context,
                    focused: focused,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
