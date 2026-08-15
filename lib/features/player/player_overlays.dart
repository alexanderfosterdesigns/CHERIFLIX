part of 'player_screen.dart';

enum _PlayerShortcutAction {
  playPause,
  play,
  pause,
  seekForward,
  seekBackward,
}

class _PlayerShortcutIntent extends Intent {
  const _PlayerShortcutIntent._(this.action);

  const _PlayerShortcutIntent.playPause()
      : this._(_PlayerShortcutAction.playPause);
  const _PlayerShortcutIntent.play() : this._(_PlayerShortcutAction.play);
  const _PlayerShortcutIntent.pause() : this._(_PlayerShortcutAction.pause);
  const _PlayerShortcutIntent.seekForward()
      : this._(_PlayerShortcutAction.seekForward);
  const _PlayerShortcutIntent.seekBackward()
      : this._(_PlayerShortcutAction.seekBackward);

  final _PlayerShortcutAction action;
}

// ignore: unused_element
class _PlayerChromeOverlay extends StatelessWidget {
  const _PlayerChromeOverlay({
    required this.title,
    required this.subtitle,
    required this.providerLabel,
    required this.presentation,
    required this.onBack,
    required this.onPlayPause,
    required this.onSeekBackward,
    required this.onSeekForward,
    required this.onToggleMute,
    required this.onToggleCaptions,
    required this.onCycleQuality,
    required this.onCyclePlaybackRate,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onChangeServer,
    required this.onOpenMoreControls,
    required this.onNextSource,
    required this.backFocusNode,
    required this.playPauseFocusNode,
    required this.seekBackwardFocusNode,
    required this.seekForwardFocusNode,
    required this.muteFocusNode,
    required this.changeServerFocusNode,
    required this.nextSourceFocusNode,
    required this.captionsFocusNode,
    required this.qualityFocusNode,
    required this.moreControlsFocusNode,
    required this.playbackRateFocusNode,
    required this.zoomOutFocusNode,
    required this.zoomInFocusNode,
  });

  final String title;
  final String subtitle;
  final String providerLabel;
  final PlaybackPresentation presentation;
  final VoidCallback onBack;
  final VoidCallback? onPlayPause;
  final VoidCallback? onSeekBackward;
  final VoidCallback? onSeekForward;
  final VoidCallback? onToggleMute;
  final VoidCallback? onToggleCaptions;
  final VoidCallback? onCycleQuality;
  final VoidCallback? onCyclePlaybackRate;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomIn;
  final VoidCallback? onChangeServer;
  final VoidCallback? onOpenMoreControls;
  final VoidCallback? onNextSource;
  final FocusNode backFocusNode;
  final FocusNode playPauseFocusNode;
  final FocusNode seekBackwardFocusNode;
  final FocusNode seekForwardFocusNode;
  final FocusNode muteFocusNode;
  final FocusNode changeServerFocusNode;
  final FocusNode nextSourceFocusNode;
  final FocusNode captionsFocusNode;
  final FocusNode qualityFocusNode;
  final FocusNode moreControlsFocusNode;
  final FocusNode playbackRateFocusNode;
  final FocusNode zoomOutFocusNode;
  final FocusNode zoomInFocusNode;

  List<FocusNode> get _transportFocusNodes => <FocusNode>[
        seekBackwardFocusNode,
        playPauseFocusNode,
        seekForwardFocusNode,
        nextSourceFocusNode,
      ];

  List<FocusNode> get _utilityFocusNodes => <FocusNode>[
        changeServerFocusNode,
        qualityFocusNode,
        captionsFocusNode,
        moreControlsFocusNode,
      ];

  List<FocusNode> _leftTransportFallback(FocusNode node) {
    final index = _transportFocusNodes.indexOf(node);
    if (index <= 0) {
      return <FocusNode>[_transportFocusNodes.first];
    }
    return <FocusNode>[_transportFocusNodes[index - 1]];
  }

  List<FocusNode> _rightTransportFallback(FocusNode node) {
    final index = _transportFocusNodes.indexOf(node);
    if (index < 0 || index >= _transportFocusNodes.length - 1) {
      return <FocusNode>[node];
    }
    return <FocusNode>[_transportFocusNodes[index + 1]];
  }

  List<FocusNode> _leftUtilityFallback(FocusNode node) {
    final index = _utilityFocusNodes.indexOf(node);
    if (index <= 0) {
      return <FocusNode>[node];
    }
    return <FocusNode>[_utilityFocusNodes[index - 1]];
  }

  List<FocusNode> _rightUtilityFallback(FocusNode node) {
    final index = _utilityFocusNodes.indexOf(node);
    if (index < 0 || index >= _utilityFocusNodes.length - 1) {
      return <FocusNode>[node];
    }
    return <FocusNode>[_utilityFocusNodes[index + 1]];
  }

  @override
  Widget build(BuildContext context) {
    final totalMillis = presentation.totalDuration.inMilliseconds;
    final progress = totalMillis <= 0
        ? 0.0
        : (presentation.currentPosition.inMilliseconds / totalMillis)
            .clamp(0.0, 1.0);
    final totalLabel = totalMillis <= 0
        ? '--:--'
        : _formatDurationLabel(presentation.totalDuration);
    return Stack(
      children: <Widget>[
        Positioned(
          left: 18,
          top: 18,
          child: TvIconButton(
            icon: Icons.arrow_back_rounded,
            label: 'Back',
            onPressed: onBack,
            autofocus: true,
            focusNode: backFocusNode,
            downFallbackNodes: <FocusNode>[playPauseFocusNode],
          ),
        ),
        Positioned(
          top: 18,
          right: 18,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xB8111111),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0x24FFFFFF)),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 18,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          TvActionButton(
                            label: 'Server',
                            icon: Icons.swap_horiz_rounded,
                            onPressed: onChangeServer,
                            focusNode: changeServerFocusNode,
                            variant: TvButtonVariant.dark,
                            leftFallbackNodes:
                                _leftUtilityFallback(changeServerFocusNode),
                            rightFallbackNodes:
                                _rightUtilityFallback(changeServerFocusNode),
                            downFallbackNodes: <FocusNode>[playPauseFocusNode],
                          ),
                          const SizedBox(width: 8),
                          TvActionButton(
                            label:
                                'Quality ${presentation.selectedQualityLabel}',
                            onPressed: onCycleQuality,
                            focusNode: qualityFocusNode,
                            variant: TvButtonVariant.dark,
                            leftFallbackNodes:
                                _leftUtilityFallback(qualityFocusNode),
                            rightFallbackNodes:
                                _rightUtilityFallback(qualityFocusNode),
                            downFallbackNodes: <FocusNode>[
                              seekForwardFocusNode
                            ],
                          ),
                          const SizedBox(width: 8),
                          TvActionButton(
                            label: presentation.captionsAvailable
                                ? 'CC ${presentation.selectedCaptionLabel}'
                                : 'CC Off',
                            icon: presentation.captionsEnabled
                                ? Icons.closed_caption_rounded
                                : Icons.closed_caption_off_rounded,
                            onPressed: presentation.captionsAvailable
                                ? onToggleCaptions
                                : null,
                            focusNode: captionsFocusNode,
                            variant: TvButtonVariant.dark,
                            leftFallbackNodes:
                                _leftUtilityFallback(captionsFocusNode),
                            rightFallbackNodes:
                                _rightUtilityFallback(captionsFocusNode),
                            downFallbackNodes: <FocusNode>[nextSourceFocusNode],
                          ),
                          const SizedBox(width: 8),
                          TvIconButton(
                            icon: Icons.more_horiz_rounded,
                            label: 'More',
                            onPressed: onOpenMoreControls,
                            focusNode: moreControlsFocusNode,
                            leftFallbackNodes:
                                _leftUtilityFallback(moreControlsFocusNode),
                            rightFallbackNodes:
                                _rightUtilityFallback(moreControlsFocusNode),
                            downFallbackNodes: <FocusNode>[nextSourceFocusNode],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '$providerLabel | $subtitle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CheriflixTypography.metadata.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 98,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xB8111111),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: const Color(0x24FFFFFF)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x73000000),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TvIconButton(
                      icon: Icons.replay_10_rounded,
                      label: 'Back 10',
                      onPressed: onSeekBackward,
                      focusNode: seekBackwardFocusNode,
                      upFallbackNodes: <FocusNode>[backFocusNode],
                      leftFallbackNodes:
                          _leftTransportFallback(seekBackwardFocusNode),
                      rightFallbackNodes:
                          _rightTransportFallback(seekBackwardFocusNode),
                    ),
                    const SizedBox(width: 10),
                    TvActionButton(
                      label: presentation.isPaused ? 'Play' : 'Pause',
                      icon: presentation.isPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      onPressed: onPlayPause,
                      focusNode: playPauseFocusNode,
                      filled: true,
                      leftFallbackNodes:
                          _leftTransportFallback(playPauseFocusNode),
                      rightFallbackNodes:
                          _rightTransportFallback(playPauseFocusNode),
                      upFallbackNodes: <FocusNode>[changeServerFocusNode],
                    ),
                    const SizedBox(width: 10),
                    TvIconButton(
                      icon: Icons.forward_10_rounded,
                      label: 'Forward 10',
                      onPressed: onSeekForward,
                      focusNode: seekForwardFocusNode,
                      upFallbackNodes: <FocusNode>[qualityFocusNode],
                      leftFallbackNodes:
                          _leftTransportFallback(seekForwardFocusNode),
                      rightFallbackNodes:
                          _rightTransportFallback(seekForwardFocusNode),
                    ),
                    const SizedBox(width: 10),
                    TvIconButton(
                      icon: Icons.skip_next_rounded,
                      label: 'Next Source',
                      onPressed: onNextSource,
                      focusNode: nextSourceFocusNode,
                      upFallbackNodes: <FocusNode>[captionsFocusNode],
                      leftFallbackNodes:
                          _leftTransportFallback(nextSourceFocusNode),
                      rightFallbackNodes:
                          _rightTransportFallback(nextSourceFocusNode),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x00000000),
                  Color(0x66000000),
                  Color(0xCC000000),
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 36, 18, 18),
              child: Row(
                children: <Widget>[
                  Text(
                    _formatDurationLabel(presentation.currentPosition),
                    style: CheriflixTypography.metadata.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFFE50914),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    totalLabel,
                    style: CheriflixTypography.metadata.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlayerSubtitleOverlay extends StatelessWidget {
  const _PlayerSubtitleOverlay({
    required this.linesListenable,
    required this.showControls,
  });

  final ValueListenable<List<String>> linesListenable;
  final bool showControls;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<List<String>>(
        valueListenable: linesListenable,
        builder: (context, rawLines, child) {
          final lines = _formatSubtitleLines(rawLines);
          if (lines.isEmpty) {
            return const SizedBox.shrink();
          }

          final mediaQuery = MediaQuery.of(context);
          final size = mediaQuery.size;
          final horizontalPadding = size.width * 0.05;
          final bottomPadding = size.height * (showControls ? 0.15 : 0.07) +
              mediaQuery.viewPadding.bottom;
          return AnimatedPadding(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              0,
              horizontalPadding,
              bottomPadding,
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: size.width * 0.78,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    for (var index = 0; index < lines.length; index += 1)
                      Padding(
                        padding: EdgeInsets.only(
                          top: index == 0 ? 0 : size.height * 0.003,
                        ),
                        child: _SubtitleLineText(text: lines[index]),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SubtitleLineText extends StatelessWidget {
  const _SubtitleLineText({required this.text});

  final String text;

  static const TextStyle _fillStyle = CheriflixTypography.subtitle;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final base = math.min(size.width, size.height);
    final textStyle = _fillStyle.copyWith(
      fontSize: (base * 0.032).clamp(18, 34).toDouble(),
      height: 1.2,
      fontWeight: FontWeight.w500,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(base * 0.01),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: size.width * 0.006,
          vertical: size.height * 0.003,
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: textStyle,
        ),
      ),
    );
  }
}

const String _subtitleLeadDash = '\u2013';

final RegExp _subtitleLeadingDashPattern = RegExp(
  r'^[\s]*[-\u2013\u2014]+[\s]*',
);
final RegExp _subtitleSpeakerPrefixPattern = RegExp(
  "^\\s*(?:[-\u2013\u2014]+\\s*)?([A-Z][A-Za-z0-9 .'-]{0,30})\\s*:\\s*(.+)\$",
);
final RegExp _subtitleBracketSpeakerPattern = RegExp(
  "^\\[[A-Z][A-Za-z0-9 .'-]{0,30}\\](?:\\s|\$)",
);

List<String> _formatSubtitleLines(List<String> rawLines) {
  final formatted = <String>[];
  for (final rawLine in rawLines) {
    final line = _formatSubtitleLine(rawLine);
    if (line.isNotEmpty) {
      formatted.add(line);
    }
  }
  return formatted;
}

String _formatSubtitleLine(String rawLine) {
  var line = rawLine.trim();
  if (line.isEmpty) {
    return '';
  }

  line = line.replaceAll(RegExp(r'\s+'), ' ');

  final speakerMatch = _subtitleSpeakerPrefixPattern.firstMatch(line);
  if (speakerMatch != null) {
    final speaker = _normalizeSubtitleSpeaker(speakerMatch.group(1)!);
    final dialogue = speakerMatch.group(2)!.trim();
    return dialogue.isEmpty
        ? '$_subtitleLeadDash[$speaker]'
        : '$_subtitleLeadDash[$speaker] $dialogue';
  }

  line = line.replaceFirst(_subtitleLeadingDashPattern, '');
  if (line.isEmpty) {
    return '';
  }
  if (_subtitleBracketSpeakerPattern.hasMatch(line)) {
    return _subtitleLeadDash + line;
  }
  if (line.startsWith('[') || line.startsWith('(') || line.startsWith('<')) {
    return line;
  }
  return _subtitleLeadDash + line;
}

String _normalizeSubtitleSpeaker(String rawSpeaker) {
  return rawSpeaker.trim().replaceAll(RegExp(r'\s+'), ' ');
}

class _EpisodePreviewPathData {
  const _EpisodePreviewPathData({
    required this.basePath,
    required this.maxFrame,
    required this.padWidth,
  });

  final String basePath;
  final int maxFrame;
  final int padWidth;

  factory _EpisodePreviewPathData.fromPreviewPath(String previewPath) {
    final separatorIndex = previewPath.indexOf('|');
    if (separatorIndex <= 0 || separatorIndex >= previewPath.length - 1) {
      throw const FormatException('Invalid preview_path format.');
    }

    final base = previewPath.substring(0, separatorIndex).trim();
    final frameCountText = previewPath.substring(separatorIndex + 1).trim();
    final frameCount = int.tryParse(frameCountText);
    if (base.isEmpty || frameCount == null || frameCount <= 0) {
      throw const FormatException('Invalid preview_path contents.');
    }

    return _EpisodePreviewPathData(
      basePath: base,
      maxFrame: frameCount,
      padWidth: frameCountText.length,
    );
  }

  String thumbnailUrlForTimestamp(int timestampMs) {
    var frameIndex = timestampMs ~/ 10000;
    frameIndex = math.max(1, frameIndex);
    frameIndex = math.min(frameIndex, maxFrame);
    return '$basePath/preview-${frameIndex.toString().padLeft(padWidth, '0')}.jpg';
  }
}

class _PlayerChromeOverlayV2 extends StatelessWidget {
  const _PlayerChromeOverlayV2({
    required this.title,
    required this.presentation,
    this.playbackHint,
    required this.onBack,
    required this.onPlayPause,
    required this.onSeekBackward,
    required this.onSeekForward,
    required this.onSeekToPosition,
    required this.onRequestScrubFrame,
    required this.scrubFrameCache,
    required this.onExitScrubFocus,
    required this.onOpenEpisodes,
    required this.onOpenCaptions,
    required this.onOpenAudioLanguage,
    required this.onOpenSettings,
    required this.onNextEpisode,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onPlaceholderFullscreenExit,
    required this.backFocusNode,
    required this.playPauseFocusNode,
    required this.scrubFocusNode,
    required this.seekBackwardFocusNode,
    required this.seekForwardFocusNode,
    required this.episodesFocusNode,
    required this.captionsFocusNode,
    required this.audioLanguageFocusNode,
    required this.settingsFocusNode,
    required this.nextEpisodeFocusNode,
    required this.zoomOutFocusNode,
    required this.zoomInFocusNode,
    required this.fullscreenFocusNode,
    required this.showNextEpisodeButton,
    required this.showEpisodesButton,
    required this.scrubUiVisible,
    required this.onScrubUiVisibilityChanged,
  });

  final String title;
  final PlaybackPresentation presentation;
  final String? playbackHint;
  final VoidCallback onBack;
  final VoidCallback? onPlayPause;
  final VoidCallback? onSeekBackward;
  final VoidCallback? onSeekForward;
  final PlayerScrubSeekCallback? onSeekToPosition;
  final PlayerScrubFrameLoader? onRequestScrubFrame;
  final Map<int, String> scrubFrameCache;
  final VoidCallback onExitScrubFocus;
  final VoidCallback? onOpenEpisodes;
  final VoidCallback? onOpenCaptions;
  final VoidCallback? onOpenAudioLanguage;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomIn;
  final VoidCallback? onPlaceholderFullscreenExit;
  final FocusNode backFocusNode;
  final FocusNode playPauseFocusNode;
  final FocusNode scrubFocusNode;
  final FocusNode seekBackwardFocusNode;
  final FocusNode seekForwardFocusNode;
  final FocusNode episodesFocusNode;
  final FocusNode captionsFocusNode;
  final FocusNode audioLanguageFocusNode;
  final FocusNode settingsFocusNode;
  final FocusNode nextEpisodeFocusNode;
  final FocusNode zoomOutFocusNode;
  final FocusNode zoomInFocusNode;
  final FocusNode fullscreenFocusNode;
  final bool showNextEpisodeButton;
  final bool showEpisodesButton;
  final bool scrubUiVisible;
  final ValueChanged<bool> onScrubUiVisibilityChanged;

  List<FocusNode> get _topRightFocusNodes => <FocusNode>[
        episodesFocusNode,
        if (showNextEpisodeButton) nextEpisodeFocusNode,
        audioLanguageFocusNode,
        captionsFocusNode,
        settingsFocusNode,
      ];

  List<FocusNode> get _bottomFocusNodes => <FocusNode>[
        playPauseFocusNode,
        seekBackwardFocusNode,
        seekForwardFocusNode,
        zoomOutFocusNode,
        zoomInFocusNode,
        fullscreenFocusNode,
      ];

  List<FocusNode> get _scrubUpFallbackNodes => <FocusNode>[
        backFocusNode,
        episodesFocusNode,
        audioLanguageFocusNode,
        captionsFocusNode,
        settingsFocusNode,
      ];

  List<FocusNode> get _scrubDownFallbackNodes => <FocusNode>[
        ..._bottomFocusNodes,
      ];

  List<FocusNode> _fallbackLeft(List<FocusNode> nodes, FocusNode node) {
    final index = nodes.indexOf(node);
    if (index <= 0) {
      return <FocusNode>[node];
    }
    return <FocusNode>[nodes[index - 1]];
  }

  List<FocusNode> _fallbackRight(List<FocusNode> nodes, FocusNode node) {
    final index = nodes.indexOf(node);
    if (index < 0 || index >= nodes.length - 1) {
      return <FocusNode>[node];
    }
    return <FocusNode>[nodes[index + 1]];
  }

  Widget _orderedBottomControl(double order, Widget child) {
    return FocusTraversalOrder(
      order: NumericFocusOrder(order),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    const topLabelStyle = TextStyle(
      fontFamily: CheriflixTypography.sansFamily,
      color: Color(0xB3FFFFFF),
      fontSize: 11,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      height: 1.1,
    );
    const titleStyle = TextStyle(
      fontFamily: CheriflixTypography.sansFamily,
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w700,
      height: 1.15,
    );
    const topButtonBackground = Color(0xCC1A1A1A);
    const topButtonForeground = Colors.white;
    const bottomButtonBackground = Color(0xC91A1A1A);
    const zoomButtonBackground = Color(0xCC1A1A1A);
    final zoomLabel = 'Zoom ${(presentation.zoomScale * 100).round()}%';

    return Stack(
      children: <Widget>[
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 152,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0xE6000000),
                    Color(0x96000000),
                    Color(0x00000000),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 360,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0x00000000),
                    Color(0x73000000),
                    Color(0xE6000000),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 560,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: scrubUiVisible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    stops: <double>[0, 0.12, 0.34, 0.62, 1],
                    colors: <Color>[
                      Color(0xFF000000),
                      Color(0xF4000000),
                      Color(0xB4000000),
                      Color(0x42000000),
                      Color(0x00000000),
                    ],
                  ),
                ),
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
        Positioned(
          left: 18,
          top: 16,
          right: 18,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TvIconButton(
                icon: Icons.arrow_back_rounded,
                label: 'Back',
                onPressed: onBack,
                focusNode: backFocusNode,
                size: 36,
                iconSize: 18,
                backgroundColor: topButtonBackground,
                foregroundColor: topButtonForeground,
                downFallbackNodes: <FocusNode>[
                  scrubFocusNode,
                  playPauseFocusNode,
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'YOU\'RE WATCHING',
                      style: topLabelStyle,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TvIconButton(
                    icon: Icons.view_agenda_rounded,
                    label: 'Browse episodes',
                    onPressed: showEpisodesButton ? onOpenEpisodes : null,
                    focusNode: episodesFocusNode,
                    size: 36,
                    iconSize: 17,
                    borderRadius: 10,
                    backgroundColor: topButtonBackground,
                    foregroundColor: topButtonForeground,
                    leftFallbackNodes:
                        _fallbackLeft(_topRightFocusNodes, episodesFocusNode),
                    rightFallbackNodes:
                        _fallbackRight(_topRightFocusNodes, episodesFocusNode),
                    downFallbackNodes: <FocusNode>[
                      scrubFocusNode,
                      playPauseFocusNode,
                    ],
                  ),
                  if (showNextEpisodeButton) ...<Widget>[
                    const SizedBox(width: 8),
                    TvActionButton(
                      label: 'Next episode',
                      icon: Icons.arrow_forward_rounded,
                      onPressed: onNextEpisode,
                      focusNode: nextEpisodeFocusNode,
                      variant: TvButtonVariant.dark,
                      borderRadius: 10,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      labelStyle: CheriflixTypography.button.copyWith(
                        fontFamily: CheriflixTypography.sansFamily,
                        fontWeight: FontWeight.w700,
                      ),
                      iconSize: 17,
                      leftFallbackNodes: _fallbackLeft(
                        _topRightFocusNodes,
                        nextEpisodeFocusNode,
                      ),
                      rightFallbackNodes: _fallbackRight(
                        _topRightFocusNodes,
                        nextEpisodeFocusNode,
                      ),
                      downFallbackNodes: <FocusNode>[
                        scrubFocusNode,
                        playPauseFocusNode,
                      ],
                    ),
                  ],
                  const SizedBox(width: 8),
                  TvIconButton(
                    key: const ValueKey<String>('player_audio_language_button'),
                    icon: Icons.language_rounded,
                    label: 'Audio / Language',
                    onPressed: onOpenAudioLanguage,
                    focusNode: audioLanguageFocusNode,
                    size: 36,
                    iconSize: 17,
                    borderRadius: 10,
                    backgroundColor: topButtonBackground,
                    foregroundColor: topButtonForeground,
                    leftFallbackNodes: _fallbackLeft(
                      _topRightFocusNodes,
                      audioLanguageFocusNode,
                    ),
                    rightFallbackNodes: _fallbackRight(
                      _topRightFocusNodes,
                      audioLanguageFocusNode,
                    ),
                    downFallbackNodes: <FocusNode>[
                      scrubFocusNode,
                      playPauseFocusNode,
                    ],
                  ),
                  const SizedBox(width: 8),
                  TvIconButton(
                    icon: Icons.closed_caption_rounded,
                    label: 'Subtitles',
                    onPressed: onOpenCaptions,
                    focusNode: captionsFocusNode,
                    size: 36,
                    iconSize: 17,
                    borderRadius: 10,
                    backgroundColor: topButtonBackground,
                    foregroundColor: topButtonForeground,
                    leftFallbackNodes:
                        _fallbackLeft(_topRightFocusNodes, captionsFocusNode),
                    rightFallbackNodes:
                        _fallbackRight(_topRightFocusNodes, captionsFocusNode),
                    downFallbackNodes: <FocusNode>[
                      scrubFocusNode,
                      playPauseFocusNode,
                    ],
                  ),
                  const SizedBox(width: 8),
                  TvIconButton(
                    icon: Icons.settings_rounded,
                    label: 'Settings',
                    onPressed: onOpenSettings,
                    focusNode: settingsFocusNode,
                    size: 36,
                    iconSize: 17,
                    borderRadius: 10,
                    backgroundColor: topButtonBackground,
                    foregroundColor: topButtonForeground,
                    leftFallbackNodes:
                        _fallbackLeft(_topRightFocusNodes, settingsFocusNode),
                    rightFallbackNodes:
                        _fallbackRight(_topRightFocusNodes, settingsFocusNode),
                    downFallbackNodes: <FocusNode>[
                      scrubFocusNode,
                      playPauseFocusNode,
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        if (playbackHint != null && playbackHint!.trim().isNotEmpty)
          Positioned(
            left: 20,
            right: 20,
            bottom: 136,
            child: IgnorePointer(
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xC4181818),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x24FFFFFF)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Text(
                      playbackHint!,
                      textAlign: TextAlign.center,
                      style: CheriflixTypography.metadata.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 18,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              PlayerScrubBar(
                position: presentation.currentPosition,
                totalDuration: presentation.totalDuration,
                focusNode: scrubFocusNode,
                thumbnailAspectRatio:
                    presentation.videoWidth > 0 && presentation.videoHeight > 0
                        ? presentation.videoWidth / presentation.videoHeight
                        : PlayerScrubBar.defaultThumbnailAspectRatio,
                onSeekRequested: onSeekToPosition,
                onFrameRequested: onRequestScrubFrame,
                frameCache: scrubFrameCache,
                onExitRequested: onExitScrubFocus,
                onScrubUiVisibilityChanged: onScrubUiVisibilityChanged,
                upFallbackNodes: _scrubUpFallbackNodes,
                downFallbackNodes: _scrubDownFallbackNodes,
                enabled: onSeekToPosition != null,
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _orderedBottomControl(
                            1,
                            TvIconButton(
                              icon: presentation.isPaused
                                  ? Icons.play_arrow_rounded
                                  : Icons.pause_rounded,
                              label: presentation.isPaused ? 'Play' : 'Pause',
                              onPressed: onPlayPause,
                              focusNode: playPauseFocusNode,
                              size: 52,
                              iconSize: 24,
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              immediateActivation: true,
                              leftFallbackNodes: _fallbackLeft(
                                  _bottomFocusNodes, playPauseFocusNode),
                              rightFallbackNodes: _fallbackRight(
                                  _bottomFocusNodes, playPauseFocusNode),
                              upFallbackNodes: <FocusNode>[scrubFocusNode],
                            ),
                          ),
                          const SizedBox(width: 10),
                          _orderedBottomControl(
                            2,
                            TvIconButton(
                              icon: Icons.replay_10_rounded,
                              label: 'Back 10',
                              onPressed: onSeekBackward,
                              focusNode: seekBackwardFocusNode,
                              size: 44,
                              iconSize: 28,
                              backgroundColor: bottomButtonBackground,
                              foregroundColor: Colors.white,
                              upFallbackNodes: <FocusNode>[scrubFocusNode],
                              leftFallbackNodes: _fallbackLeft(
                                  _bottomFocusNodes, seekBackwardFocusNode),
                              rightFallbackNodes: _fallbackRight(
                                  _bottomFocusNodes, seekBackwardFocusNode),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _orderedBottomControl(
                            3,
                            TvIconButton(
                              icon: Icons.forward_10_rounded,
                              label: 'Forward 10',
                              onPressed: onSeekForward,
                              focusNode: seekForwardFocusNode,
                              size: 44,
                              iconSize: 28,
                              backgroundColor: bottomButtonBackground,
                              foregroundColor: Colors.white,
                              upFallbackNodes: <FocusNode>[scrubFocusNode],
                              leftFallbackNodes: _fallbackLeft(
                                  _bottomFocusNodes, seekForwardFocusNode),
                              rightFallbackNodes: _fallbackRight(
                                  _bottomFocusNodes, seekForwardFocusNode),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _orderedBottomControl(
                            5,
                            TvIconButton(
                              icon: Icons.remove_rounded,
                              label: 'Zoom Out',
                              onPressed: onZoomOut,
                              focusNode: zoomOutFocusNode,
                              size: 36,
                              iconSize: 18,
                              borderRadius: 8,
                              backgroundColor: zoomButtonBackground,
                              foregroundColor: Colors.white,
                              upFallbackNodes: <FocusNode>[scrubFocusNode],
                              leftFallbackNodes: _fallbackLeft(
                                  _bottomFocusNodes, zoomOutFocusNode),
                              rightFallbackNodes: _fallbackRight(
                                  _bottomFocusNodes, zoomOutFocusNode),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            zoomLabel,
                            style: CheriflixTypography.button.copyWith(
                              color: Colors.white,
                              fontFamily: CheriflixTypography.sansFamily,
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(width: 10),
                          _orderedBottomControl(
                            6,
                            TvIconButton(
                              icon: Icons.add_rounded,
                              label: 'Zoom In',
                              onPressed: onZoomIn,
                              focusNode: zoomInFocusNode,
                              size: 36,
                              iconSize: 18,
                              borderRadius: 8,
                              backgroundColor: zoomButtonBackground,
                              foregroundColor: Colors.white,
                              upFallbackNodes: <FocusNode>[scrubFocusNode],
                              leftFallbackNodes: _fallbackLeft(
                                  _bottomFocusNodes, zoomInFocusNode),
                              rightFallbackNodes: _fallbackRight(
                                  _bottomFocusNodes, zoomInFocusNode),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _orderedBottomControl(
                            7,
                            TvIconButton(
                              icon: Icons.fullscreen_rounded,
                              label: 'Fullscreen',
                              onPressed: onPlaceholderFullscreenExit,
                              focusNode: fullscreenFocusNode,
                              size: 36,
                              iconSize: 18,
                              borderRadius: 8,
                              backgroundColor: zoomButtonBackground,
                              foregroundColor: Colors.white,
                              upFallbackNodes: <FocusNode>[scrubFocusNode],
                              leftFallbackNodes: _fallbackLeft(
                                  _bottomFocusNodes, fullscreenFocusNode),
                              rightFallbackNodes: _fallbackRight(
                                  _bottomFocusNodes, fullscreenFocusNode),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExitPlayerConfirmationDialog extends StatelessWidget {
  const _ExitPlayerConfirmationDialog();

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: TvShortcutScope(
        onBack: () {},
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xF21A1A1A),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x28FFFFFF)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0xA6000000),
                    blurRadius: 28,
                    offset: Offset(0, 18),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Are you sure you want to exit?',
                      style: CheriflixTypography.sectionTitle.copyWith(
                        fontFamily: CheriflixTypography.sansFamily,
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        TvActionButton(
                          label: 'No',
                          autofocus: true,
                          onPressed: () => Navigator.of(context).pop(false),
                          variant: TvButtonVariant.light,
                        ),
                        const SizedBox(width: 12),
                        TvActionButton(
                          label: 'Yes',
                          onPressed: () => Navigator.of(context).pop(true),
                          variant: TvButtonVariant.dark,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaybackErrorDialog extends StatelessWidget {
  const _PlaybackErrorDialog({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xF21A1A1A),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x28FFFFFF)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0xA6000000),
                blurRadius: 28,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Playback error',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: CheriflixTypography.body.copyWith(
                    color: CheriflixColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: TvActionButton(
                    label: 'OK',
                    autofocus: true,
                    onPressed: () => Navigator.of(context).pop(),
                    variant: TvButtonVariant.light,
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

class _ServerPickerDialog extends StatelessWidget {
  const _ServerPickerDialog({
    required this.providers,
    required this.currentProviderIndex,
  });

  final List<ProviderDescriptor> providers;
  final int currentProviderIndex;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(28),
      child: TvShortcutScope(
        onBack: () => Navigator.of(context).pop(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xF2121212),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0x14FFFFFF)),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x99000000),
                  blurRadius: 24,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Choose playback server',
                          style: CheriflixTypography.sectionTitle,
                        ),
                      ),
                      TvActionButton(
                        label: 'Close',
                        icon: Icons.close_rounded,
                        onPressed: () => Navigator.of(context).pop(),
                        variant: TvButtonVariant.ghost,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This only changes the server for the current player session.',
                    style: CheriflixTypography.body.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: providers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final provider = providers[index];
                        final selected =
                            provider.canonicalIndex == currentProviderIndex;
                        return TvActionButton(
                          label: provider.label,
                          icon: selected
                              ? Icons.check_circle_rounded
                              : Icons.cloud_queue_rounded,
                          onPressed: () => Navigator.of(context)
                              .pop(provider.canonicalIndex),
                          autofocus: index == 0,
                          selected: selected,
                          variant: selected
                              ? TvButtonVariant.light
                              : TvButtonVariant.dark,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AudioTrackPickerDialog extends StatelessWidget {
  const _AudioTrackPickerDialog({
    required this.tracks,
    required this.selectedTrackId,
    this.originalLanguageCode,
  });

  final List<PlaybackAudioTrack> tracks;
  final String? selectedTrackId;
  final String? originalLanguageCode;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(28),
      child: TvShortcutScope(
        onBack: () => Navigator.of(context).pop(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xF2121212),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0x14FFFFFF)),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x99000000),
                  blurRadius: 24,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Choose audio language',
                          style: CheriflixTypography.sectionTitle,
                        ),
                      ),
                      TvActionButton(
                        label: 'Close',
                        icon: Icons.close_rounded,
                        onPressed: () => Navigator.of(context).pop(),
                        variant: TvButtonVariant.ghost,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Languages available inside the current stream.',
                    style: CheriflixTypography.body.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: tracks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final track = tracks[index];
                        final selected = track.id == selectedTrackId;
                        final language = normalizeAudioLanguageCode(
                          track.languageCode ?? '',
                        );
                        final original = normalizeAudioLanguageCode(
                          originalLanguageCode ?? '',
                        );
                        final confidentlyOriginal = track.isOriginal ??
                            language.isNotEmpty &&
                                original.isNotEmpty &&
                                language == original;
                        final confidentlyDubbed = track.isOriginal == false ||
                            language.isNotEmpty &&
                                original.isNotEmpty &&
                                language != original;
                        final status = confidentlyOriginal
                            ? 'Original'
                            : confidentlyDubbed
                                ? 'Dub'
                                : null;
                        final label = status == null ||
                                track.label.toLowerCase().contains(
                                      status.toLowerCase(),
                                    )
                            ? track.label
                            : '${track.label} — $status';
                        return TvActionButton(
                          label: label,
                          icon: selected
                              ? Icons.check_circle_rounded
                              : Icons.language_rounded,
                          onPressed: () => Navigator.of(context).pop(track.id),
                          autofocus:
                              selected || selectedTrackId == null && index == 0,
                          selected: selected,
                          variant: selected
                              ? TvButtonVariant.light
                              : TvButtonVariant.dark,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CaptionPickerResult {
  const _CaptionPickerResult({
    required this.selectedTrackId,
    required this.subtitleOffsetMs,
    required this.preferHi,
  });

  final String? selectedTrackId;
  final int subtitleOffsetMs;
  final bool preferHi;
}

class _CaptionPickerDialog extends StatefulWidget {
  const _CaptionPickerDialog({
    required this.tracks,
    required this.selectedTrackId,
    required this.subtitleOffsetMs,
    required this.preferHi,
    this.onSubtitleOffsetChanged,
  });

  final List<CaptionTrack> tracks;
  final String? selectedTrackId;
  final int subtitleOffsetMs;
  final bool preferHi;
  final ValueChanged<int>? onSubtitleOffsetChanged;

  @override
  State<_CaptionPickerDialog> createState() => _CaptionPickerDialogState();
}

class _CaptionPickerDialogState extends State<_CaptionPickerDialog> {
  static const int _subtitleOffsetLimitMs = 3600000;
  static const int _subtitleOffsetStepMs = 250;
  static const int _subtitleOffsetQuickStepMs = 500;
  late int _subtitleOffsetMs;
  late bool _preferHi;

  @override
  void initState() {
    super.initState();
    _subtitleOffsetMs = widget.subtitleOffsetMs
        .clamp(-_subtitleOffsetLimitMs, _subtitleOffsetLimitMs)
        .toInt();
    _preferHi = widget.preferHi;
  }

  List<CaptionTrack> get _visibleTracks {
    return widget.tracks;
  }

  void _closeWithTrack(String? trackId) {
    Navigator.of(context).pop(
      _CaptionPickerResult(
        selectedTrackId: trackId,
        subtitleOffsetMs: _subtitleOffsetMs,
        preferHi: _preferHi,
      ),
    );
  }

  void _adjustSubtitleOffsetBy(int deltaMs) {
    setState(() {
      _subtitleOffsetMs = (_subtitleOffsetMs + deltaMs)
          .clamp(-_subtitleOffsetLimitMs, _subtitleOffsetLimitMs)
          .toInt();
    });
    widget.onSubtitleOffsetChanged?.call(_subtitleOffsetMs);
  }

  @override
  Widget build(BuildContext context) {
    final visibleTracks = _visibleTracks;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(28),
      child: TvShortcutScope(
        onBack: () => Navigator.of(context).pop(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xF2121212),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0x14FFFFFF)),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x99000000),
                  blurRadius: 24,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Caption tracks',
                          style: CheriflixTypography.sectionTitle,
                        ),
                      ),
                      TvActionButton(
                        label: 'Close',
                        icon: Icons.close_rounded,
                        onPressed: () =>
                            _closeWithTrack(widget.selectedTrackId),
                        variant: TvButtonVariant.ghost,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose a subtitle source and adjust subtitle delay without rebuilding playback.',
                    style: CheriflixTypography.body.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'If subtitles appear early, tap "Subtitles ahead" (+500ms). If they appear late, tap "Subtitles behind" (-500ms).',
                    style: CheriflixTypography.metadata.copyWith(
                      color: Colors.white60,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TvActionButton(
                          label: 'Subtitles ahead',
                          icon: Icons.fast_forward_rounded,
                          onPressed: () => _adjustSubtitleOffsetBy(
                              _subtitleOffsetQuickStepMs),
                          variant: TvButtonVariant.dark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TvActionButton(
                          label: 'Subtitles behind',
                          icon: Icons.fast_rewind_rounded,
                          onPressed: () => _adjustSubtitleOffsetBy(
                            -_subtitleOffsetQuickStepMs,
                          ),
                          variant: TvButtonVariant.dark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      TvIconButton(
                        icon: Icons.remove_rounded,
                        label: 'Subtitle delay -100ms',
                        onPressed: () =>
                            _adjustSubtitleOffsetBy(-_subtitleOffsetStepMs),
                        size: 34,
                        iconSize: 18,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Delay: ${_subtitleOffsetMs >= 0 ? '+' : ''}${_subtitleOffsetMs}ms',
                          textAlign: TextAlign.center,
                          style: CheriflixTypography.body.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      TvIconButton(
                        icon: Icons.add_rounded,
                        label: 'Subtitle delay +100ms',
                        onPressed: () =>
                            _adjustSubtitleOffsetBy(_subtitleOffsetStepMs),
                        size: 34,
                        iconSize: 18,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Flexible(
                    child: RepaintBoundary(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: visibleTracks.length + 1,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return TvActionButton(
                              label: 'Off',
                              icon: widget.selectedTrackId == null
                                  ? Icons.check_circle_rounded
                                  : Icons.closed_caption_off_rounded,
                              onPressed: () => _closeWithTrack(null),
                              autofocus: true,
                              selected: widget.selectedTrackId == null,
                              variant: widget.selectedTrackId == null
                                  ? TvButtonVariant.light
                                  : TvButtonVariant.dark,
                            );
                          }

                          final track = visibleTracks[index - 1];
                          final selected = track.id == widget.selectedTrackId;
                          final originalIndex = widget.tracks.indexWhere(
                            (candidate) => candidate.id == track.id,
                          );
                          return TvActionButton(
                            label: _genericTrackLabelForIndex(
                              originalIndex < 0 ? index - 1 : originalIndex,
                            ),
                            icon: selected
                                ? Icons.check_circle_rounded
                                : Icons.closed_caption_rounded,
                            onPressed: () => _closeWithTrack(track.id),
                            selected: selected,
                            variant: selected
                                ? TvButtonVariant.light
                                : TvButtonVariant.dark,
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AudioSyncDialog extends StatefulWidget {
  const _AudioSyncDialog({
    required this.initialOffsetMs,
    required this.onOffsetChanged,
  });

  final int initialOffsetMs;
  final ValueChanged<int> onOffsetChanged;

  @override
  State<_AudioSyncDialog> createState() => _AudioSyncDialogState();
}

class _AudioSyncDialogState extends State<_AudioSyncDialog> {
  late int _offsetMs;

  @override
  void initState() {
    super.initState();
    _offsetMs = widget.initialOffsetMs.clamp(-5000, 5000).toInt();
  }

  void _adjust(int deltaMs) {
    final next = (_offsetMs + deltaMs).clamp(-5000, 5000).toInt();
    if (next == _offsetMs) {
      return;
    }
    setState(() => _offsetMs = next);
    widget.onOffsetChanged(next);
  }

  void _reset() {
    if (_offsetMs == 0) {
      return;
    }
    setState(() => _offsetMs = 0);
    widget.onOffsetChanged(0);
  }

  @override
  Widget build(BuildContext context) {
    final valueLabel = '${_offsetMs >= 0 ? '+' : ''}${_offsetMs}ms';
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(28),
      child: TvShortcutScope(
        onBack: () => Navigator.of(context).pop(_offsetMs),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xF2121212),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0x14FFFFFF)),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x99000000),
                  blurRadius: 24,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Audio sync',
                          style: CheriflixTypography.sectionTitle,
                        ),
                      ),
                      TvActionButton(
                        label: 'Done',
                        icon: Icons.check_rounded,
                        onPressed: () => Navigator.of(context).pop(_offsetMs),
                        variant: TvButtonVariant.ghost,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Current adjustment: $valueLabel',
                    style: CheriflixTypography.body.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'If voices happen before lips move, choose Audio later. If voices happen after lips move, choose Audio earlier.',
                    style: CheriflixTypography.metadata.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: <Widget>[
                      TvActionButton(
                        label: 'Audio earlier -100ms',
                        icon: Icons.fast_rewind_rounded,
                        onPressed: () => _adjust(-100),
                        autofocus: true,
                        variant: TvButtonVariant.dark,
                      ),
                      TvActionButton(
                        label: 'Audio later +100ms',
                        icon: Icons.fast_forward_rounded,
                        onPressed: () => _adjust(100),
                        variant: TvButtonVariant.dark,
                      ),
                      TvActionButton(
                        label: 'Earlier -500ms',
                        icon: Icons.keyboard_double_arrow_left_rounded,
                        onPressed: () => _adjust(-500),
                        variant: TvButtonVariant.dark,
                      ),
                      TvActionButton(
                        label: 'Later +500ms',
                        icon: Icons.keyboard_double_arrow_right_rounded,
                        onPressed: () => _adjust(500),
                        variant: TvButtonVariant.dark,
                      ),
                      TvActionButton(
                        label: 'Reset to 0ms',
                        icon: Icons.restart_alt_rounded,
                        onPressed: _reset,
                        variant: TvButtonVariant.dark,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerSettingsDialog extends StatelessWidget {
  const _PlayerSettingsDialog({
    required this.playerState,
    required this.currentProviderLabel,
    required this.canOpenServerPicker,
    required this.onOpenServerPicker,
    required this.onOpenCaptionPicker,
    required this.onOpenAudioTrackPicker,
    required this.audioDelayMs,
    required this.onOpenAudioSyncPicker,
    required this.onCycleQuality,
    required this.onCyclePlaybackRate,
    required this.onToggleMute,
  });

  final ValueListenable<PlaybackPresentation> playerState;
  final String? currentProviderLabel;
  final bool canOpenServerPicker;
  final VoidCallback onOpenServerPicker;
  final Future<void> Function() onOpenCaptionPicker;
  final Future<void> Function() onOpenAudioTrackPicker;
  final int audioDelayMs;
  final Future<void> Function() onOpenAudioSyncPicker;
  final VoidCallback onCycleQuality;
  final VoidCallback onCyclePlaybackRate;
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(28),
      child: TvShortcutScope(
        onBack: () => Navigator.of(context).pop(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xF2121212),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0x14FFFFFF)),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x99000000),
                  blurRadius: 24,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
              child: ValueListenableBuilder<PlaybackPresentation>(
                valueListenable: playerState,
                builder: (context, presentation, child) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'Playback settings',
                              style: CheriflixTypography.sectionTitle,
                            ),
                          ),
                          TvActionButton(
                            label: 'Close',
                            icon: Icons.close_rounded,
                            onPressed: () => Navigator.of(context).pop(),
                            variant: TvButtonVariant.ghost,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Server, audio, subtitles, quality, speed, and mute stay inside this overlay.',
                        style: CheriflixTypography.body.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: <Widget>[
                          TvActionButton(
                            label: currentProviderLabel == null
                                ? 'Server'
                                : 'Server: $currentProviderLabel',
                            icon: Icons.swap_horiz_rounded,
                            onPressed:
                                canOpenServerPicker ? onOpenServerPicker : null,
                            autofocus: true,
                            variant: TvButtonVariant.dark,
                          ),
                          TvActionButton(
                            label:
                                'Quality ${presentation.selectedQualityLabel}',
                            icon: Icons.high_quality_rounded,
                            onPressed: onCycleQuality,
                            variant: TvButtonVariant.dark,
                          ),
                          TvActionButton(
                            label: presentation.audioTracks.isEmpty
                                ? 'Audio: Unavailable'
                                : 'Audio: ${presentation.selectedAudioTrackLabel}',
                            icon: Icons.language_rounded,
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await onOpenAudioTrackPicker();
                            },
                            variant: TvButtonVariant.dark,
                          ),
                          TvActionButton(
                            label:
                                'Audio sync: ${audioDelayMs >= 0 ? '+' : ''}${audioDelayMs}ms',
                            icon: Icons.sync_rounded,
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await onOpenAudioSyncPicker();
                            },
                            variant: TvButtonVariant.dark,
                          ),
                          TvActionButton(
                            label: presentation.selectedCaptionLabel == 'Off'
                                ? 'Subtitles'
                                : 'Subtitles: ${presentation.selectedCaptionLabel}',
                            icon: Icons.closed_caption_rounded,
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await onOpenCaptionPicker();
                            },
                            variant: TvButtonVariant.dark,
                          ),
                          TvActionButton(
                            label:
                                'Speed ${presentation.playbackRate.toStringAsFixed(2)}x',
                            icon: Icons.speed_rounded,
                            onPressed: onCyclePlaybackRate,
                            variant: TvButtonVariant.dark,
                          ),
                          TvActionButton(
                            label: presentation.isMuted ? 'Unmute' : 'Mute',
                            icon: presentation.isMuted
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                            onPressed: onToggleMute,
                            variant: presentation.isMuted
                                ? TvButtonVariant.danger
                                : TvButtonVariant.dark,
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerEpisodesOverlayDialog extends StatelessWidget {
  const _PlayerEpisodesOverlayDialog({
    required this.summary,
    required this.activeSeasonNumber,
    required this.languageCode,
    required this.hideSpoilers,
    required this.playbackProgress,
    required this.mediaCatalogService,
  });

  final MediaSummary? summary;
  final int activeSeasonNumber;
  final String languageCode;
  final bool hideSpoilers;
  final PlaybackProgressSnapshot playbackProgress;
  final MediaCatalogService? mediaCatalogService;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: TvShortcutScope(
        onBack: () => Navigator.of(context).pop(),
        autoEnsureVisible: false,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            EpisodesBackdrop(imageUrl: summary?.backdropUrl),
            Padding(
              padding: episodesPagePaddingFor(context),
              child: EpisodesBrowser(
                summary: summary,
                playbackProgress: playbackProgress,
                languageCode: languageCode,
                hideSpoilers: hideSpoilers,
                mediaCatalogService: mediaCatalogService,
                initialSeasonNumber: activeSeasonNumber,
                onPlayEpisode: (seasonNumber, episode) {
                  Navigator.of(context).pop(
                    _EpisodeSelection(
                      seasonNumber: seasonNumber,
                      episodeNumber: episode.episodeNumber,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerEpisodesDialog extends StatefulWidget {
  const _PlayerEpisodesDialog({
    required this.summary,
    required this.activeSeasonNumber,
    required this.activeEpisodeNumber,
    required this.languageCode,
    required this.mediaCatalogService,
  });

  final MediaSummary? summary;
  final int activeSeasonNumber;
  final int activeEpisodeNumber;
  final String languageCode;
  final MediaCatalogService? mediaCatalogService;

  @override
  State<_PlayerEpisodesDialog> createState() => _PlayerEpisodesDialogState();
}

class _PlayerEpisodesDialogState extends State<_PlayerEpisodesDialog> {
  late int _selectedSeasonNumber = widget.activeSeasonNumber;
  List<EpisodeSummary> _episodes = const <EpisodeSummary>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedSeasonNumber = _clampSeason(widget.activeSeasonNumber);
    _loadEpisodes();
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final layout = CheriflixTvLayout.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: layout.dialogInsetPadding,
      child: TvShortcutScope(
        onBack: () => Navigator.of(context).pop(),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: layout.dialogMaxWidth,
            maxHeight: layout.dialogMaxHeight,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xF2121212),
              borderRadius: BorderRadius.circular(layout.episodesPaneRadius),
              border: Border.all(color: const Color(0x14FFFFFF)),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x99000000),
                  blurRadius: 24,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                layout.value(compact: 18, standard: 20, wide: 24),
                layout.value(compact: 18, standard: 20, wide: 22),
                layout.value(compact: 18, standard: 20, wide: 24),
                layout.value(compact: 18, standard: 20, wide: 22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          summary?.title ?? 'Episodes',
                          style: CheriflixTypography.sectionTitle.copyWith(
                            fontSize: layout.sectionTitleSize,
                          ),
                        ),
                      ),
                      TvActionButton(
                        label: 'Close',
                        icon: Icons.close_rounded,
                        onPressed: () => Navigator.of(context).pop(),
                        variant: TvButtonVariant.ghost,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Playback pauses while you browse episodes. Picking one stays in the player.',
                    style: CheriflixTypography.body.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final dialogLayout =
                            CheriflixTvLayout.fromWidth(constraints.maxWidth);
                        final compact = dialogLayout.isCompact;
                        final seasonRail = _buildSeasonRail();
                        final episodePane = _buildEpisodePane(summary);

                        if (compact) {
                          return Column(
                            children: <Widget>[
                              SizedBox(
                                height: dialogLayout.value(
                                  compact: 84,
                                  standard: 90,
                                  wide: 96,
                                ),
                                child: seasonRail,
                              ),
                              const SizedBox(height: 16),
                              Expanded(child: episodePane),
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            SizedBox(
                              width: dialogLayout.episodesSeasonRailWidth,
                              child: seasonRail,
                            ),
                            SizedBox(
                              width: dialogLayout.value(
                                compact: 16,
                                standard: 20,
                                wide: 24,
                              ),
                            ),
                            Expanded(child: episodePane),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeasonRail() {
    final seasons = _availableSeasons;
    if (seasons.length <= 1) {
      return const SizedBox.shrink();
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: seasons.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final seasonNumber = seasons[index];
        return TvNavPillButton(
          label: 'Season $seasonNumber',
          active: seasonNumber == _selectedSeasonNumber,
          onPressed: () {
            if (seasonNumber == _selectedSeasonNumber) {
              return;
            }
            setState(() {
              _selectedSeasonNumber = seasonNumber;
            });
            _loadEpisodes();
          },
        );
      },
    );
  }

  Widget _buildEpisodePane(MediaSummary? summary) {
    final layout = CheriflixTvLayout.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: CheriflixTypography.body.copyWith(
              color: Colors.white70,
            ),
          ),
        ),
      );
    }

    if (_episodes.isEmpty) {
      return Center(
        child: Text(
          'No episodes are available for this season yet.',
          style: CheriflixTypography.body.copyWith(
            color: Colors.white70,
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x62000000),
        borderRadius: BorderRadius.circular(layout.episodesPaneRadius),
        border: Border.all(color: const Color(0x12FFFFFF)),
      ),
      child: ListView.separated(
        padding: EdgeInsets.all(layout.episodesPanePadding),
        itemCount: _episodes.length,
        separatorBuilder: (_, __) => SizedBox(
          height: layout.value(compact: 10, standard: 11, wide: 12),
        ),
        itemBuilder: (context, index) {
          final episode = _episodes[index];
          final isSelected =
              episode.episodeNumber == widget.activeEpisodeNumber &&
                  _selectedSeasonNumber == widget.activeSeasonNumber;
          final episodeLabel = summary == null
              ? 'Episode ${episode.episodeNumber}'
              : '[S$_selectedSeasonNumber:E${episode.episodeNumber}] ${episode.title}';
          return TvActionButton(
            label: episodeLabel,
            icon: isSelected
                ? Icons.check_circle_rounded
                : Icons.play_arrow_rounded,
            onPressed: () {
              Navigator.of(context).pop(
                _EpisodeSelection(
                  seasonNumber: _selectedSeasonNumber,
                  episodeNumber: episode.episodeNumber,
                ),
              );
            },
            selected: isSelected,
            variant: isSelected ? TvButtonVariant.light : TvButtonVariant.dark,
          );
        },
      ),
    );
  }

  List<int> get _availableSeasons {
    final seasonCount = widget.summary?.seasonCount ?? 1;
    final clampedCount = seasonCount < 1 ? 1 : seasonCount;
    return List<int>.generate(clampedCount, (index) => index + 1);
  }

  int _clampSeason(int seasonNumber) {
    final seasons = _availableSeasons;
    if (seasons.contains(seasonNumber)) {
      return seasonNumber;
    }
    return seasons.first;
  }

  TmdbMediaCatalogService? get _tmdbCatalogService {
    final service = widget.mediaCatalogService;
    if (service is TmdbMediaCatalogService) {
      return service;
    }
    return null;
  }

  Future<void> _loadEpisodes() async {
    final catalogService = _tmdbCatalogService;
    final summary = widget.summary;
    if (catalogService == null || summary == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _episodes = const <EpisodeSummary>[];
        _error =
            'TMDb episode data is unavailable until CHERIFLIX is connected to live catalog access.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final episodes = await catalogService.fetchSeasonEpisodes(
        tmdbId: summary.tmdbId,
        seasonNumber: _selectedSeasonNumber,
        languageCode: widget.languageCode,
        fallbackRuntimeMinutes: summary.runtimeMinutes,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _episodes = episodes;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _episodes = const <EpisodeSummary>[];
        _error = userFacingErrorMessage(
          error,
          fallback: 'Episode choices could not be loaded right now.',
        );
      });
    }
  }
}

class _NextEpisodePromptOverlay extends StatelessWidget {
  const _NextEpisodePromptOverlay({
    required this.title,
    required this.nextEpisodeTitle,
    required this.countdownSeconds,
    required this.onPlayNow,
    required this.onCancel,
    required this.playButtonFocusNode,
  });

  final String title;
  final String nextEpisodeTitle;
  final int countdownSeconds;
  final VoidCallback onPlayNow;
  final VoidCallback onCancel;
  final FocusNode playButtonFocusNode;

  @override
  Widget build(BuildContext context) {
    final progress = (5 - countdownSeconds).clamp(0, 5) / 5.0;
    return ColoredBox(
      color: const Color(0xB3000000),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF151515),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0x22FFFFFF)),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x99000000),
                  blurRadius: 28,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'AUTOPLAY IN',
                    style: CheriflixTypography.overline,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    nextEpisodeTitle,
                    style: CheriflixTypography.cardTitle.copyWith(
                      color: Colors.white,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFE50914),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TvActionButton(
                          label: 'Play now',
                          icon: Icons.play_arrow_rounded,
                          onPressed: onPlayNow,
                          autofocus: true,
                          focusNode: playButtonFocusNode,
                          filled: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TvActionButton(
                          label: 'Cancel',
                          onPressed: onCancel,
                          variant: TvButtonVariant.dark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Playing in ${countdownSeconds.clamp(1, 5)}s',
                    style: CheriflixTypography.metadata.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: CheriflixTypography.metadata.copyWith(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodeSelection {
  const _EpisodeSelection({
    required this.seasonNumber,
    required this.episodeNumber,
  });

  final int seasonNumber;
  final int episodeNumber;
}

// ignore: unused_element
class _PlayerMoreControlsDialog extends StatelessWidget {
  const _PlayerMoreControlsDialog({
    required this.presentation,
    required this.onToggleMute,
    required this.onCyclePlaybackRate,
    required this.onZoomOut,
    required this.onZoomIn,
  });

  final PlaybackPresentation presentation;
  final VoidCallback? onToggleMute;
  final VoidCallback? onCyclePlaybackRate;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomIn;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(28),
      child: TvShortcutScope(
        onBack: () => Navigator.of(context).pop(),
        child: Align(
          alignment: Alignment.topRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xF2121212),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0x14FFFFFF)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x99000000),
                    blurRadius: 24,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'More playback controls',
                              style: CheriflixTypography.sectionTitle,
                            ),
                          ),
                          TvActionButton(
                            label: 'Close',
                            icon: Icons.close_rounded,
                            onPressed: () => Navigator.of(context).pop(),
                            variant: TvButtonVariant.ghost,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Secondary controls live here so transport stays clean.',
                        style: CheriflixTypography.body.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: <Widget>[
                          TvActionButton(
                            label: presentation.isMuted ? 'Unmute' : 'Mute',
                            icon: presentation.isMuted
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                            onPressed: onToggleMute,
                            autofocus: true,
                            variant: TvButtonVariant.dark,
                          ),
                          TvActionButton(
                            label:
                                'Speed ${presentation.playbackRate.toStringAsFixed(2)}x',
                            icon: Icons.speed_rounded,
                            onPressed: onCyclePlaybackRate,
                            variant: TvButtonVariant.dark,
                          ),
                          TvActionButton(
                            label: 'Zoom Out',
                            icon: Icons.remove_rounded,
                            onPressed: onZoomOut,
                            variant: TvButtonVariant.dark,
                          ),
                          TvActionButton(
                            label: 'Zoom In',
                            icon: Icons.add_rounded,
                            onPressed: onZoomIn,
                            variant: TvButtonVariant.dark,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Zoom ${(presentation.zoomScale * 100).round()}%',
                        style: CheriflixTypography.metadata.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDurationLabel(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = (totalSeconds ~/ 60).toString();
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

@visibleForTesting
Future<bool> isLikelyBlankScrubFrame(Uint8List bytes) {
  return _isLikelyBlankScrubFrame(bytes);
}

@visibleForTesting
bool shouldUseFfmpegScrubExtraction({
  required PlaybackSourceKind? sourceKind,
  required Uri mediaUri,
}) {
  final effectiveSourceKind = sourceKind ??
      (mediaUri.path.toLowerCase().endsWith('.m3u8')
          ? PlaybackSourceKind.hls
          : PlaybackSourceKind.file);
  return effectiveSourceKind == PlaybackSourceKind.file;
}

const Duration _scrubFrameProbeOffset = Duration(milliseconds: 80);
const Duration _scrubFrameMaxProbeOffset = Duration(milliseconds: 160);
const String _scrubFrameExtractionStrategyVersion = 'scrub-local-sync-v2';

@visibleForTesting
Duration scrubFrameCapturePosition(Duration position) {
  if (position <= Duration.zero) {
    return Duration.zero;
  }
  return position;
}

Iterable<Duration> _scrubFrameCaptureProbes(Duration position) sync* {
  final orderedOffsets = <Duration>[
    Duration.zero,
    _scrubFrameProbeOffset,
    -_scrubFrameProbeOffset,
    _scrubFrameMaxProbeOffset,
    -_scrubFrameMaxProbeOffset,
  ];
  final seen = <int>{};
  for (final offset in orderedOffsets) {
    final candidate = position + offset;
    final normalized = candidate.isNegative ? Duration.zero : candidate;
    if (seen.add(normalized.inMilliseconds)) {
      yield normalized;
    }
  }
}

Future<bool> _isLikelyBlankScrubFrame(Uint8List bytes) async {
  if (bytes.isEmpty) {
    return true;
  }

  ui.Codec? codec;
  ui.Image? image;
  try {
    codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 32,
    );
    final frame = await codec.getNextFrame();
    image = frame.image;
    final byteData = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null) {
      return false;
    }

    final rgba = byteData.buffer.asUint8List();
    var opaquePixels = 0;
    var nearBlackOpaquePixels = 0;
    var brightestOpaquePixel = 0;

    for (var index = 0; index < rgba.length; index += 4) {
      final alpha = rgba[index + 3];
      if (alpha < 250) {
        continue;
      }

      opaquePixels += 1;
      final red = rgba[index];
      final green = rgba[index + 1];
      final blue = rgba[index + 2];
      final maxChannel = math.max(red, math.max(green, blue));
      if (maxChannel > brightestOpaquePixel) {
        brightestOpaquePixel = maxChannel;
      }
      if (maxChannel <= 12) {
        nearBlackOpaquePixels += 1;
      }
    }

    if (opaquePixels == 0) {
      return false;
    }

    final nearBlackRatio = nearBlackOpaquePixels / opaquePixels;
    return nearBlackRatio >= 0.985 && brightestOpaquePixel <= 24;
  } catch (_) {
    return false;
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}

@visibleForTesting
bool evaluateAndroidFrameHealth({
  required bool hasVisibleScreenshot,
  required bool screenshotMissing,
  required bool hasFrameCallbacks,
  required bool hasFrameCallbacksProgressed,
  required bool useSurfaceTexture,
  required bool hasAttachedSurface,
  required bool startupPhase,
  int surfaceAttachRetryCount = 0,
  int frameWatchdogReattachCount = 0,
}) {
  if (!hasAttachedSurface) {
    return false;
  }

  final hasDeadSurfaceTelemetry =
      surfaceAttachRetryCount > 0 || frameWatchdogReattachCount > 0;
  if (startupPhase && hasDeadSurfaceTelemetry) {
    return false;
  }

  if (useSurfaceTexture) {
    if (!hasFrameCallbacks) {
      return false;
    }
    if (frameWatchdogReattachCount > 0) {
      return false;
    }
    if (!hasFrameCallbacksProgressed && !hasVisibleScreenshot) {
      return false;
    }
    return hasVisibleScreenshot || !screenshotMissing;
  }

  if (surfaceAttachRetryCount > 0 && startupPhase) {
    return false;
  }

  if (hasVisibleScreenshot) {
    return true;
  }
  if (screenshotMissing) {
    return false;
  }
  return false;
}

typedef _HlsScrubFrameExtractor = Future<String?> Function({
  required Duration position,
  required bool prioritizeVisible,
});

class _HlsScrubFrameCoordinator {
  _HlsScrubFrameCoordinator({
    required this.bucketStep,
    required this.extractor,
  });

  final Duration bucketStep;
  final _HlsScrubFrameExtractor extractor;

  final Map<int, String> _cache = <int, String>{};
  final Map<int, Future<String?>> _requests = <int, Future<String?>>{};
  final Queue<_HlsScrubFrameTask> _priorityQueue = Queue<_HlsScrubFrameTask>();
  final Queue<_HlsScrubFrameTask> _backgroundQueue =
      Queue<_HlsScrubFrameTask>();
  final Set<int> _queuedKeys = <int>{};

  bool _disposed = false;
  bool _backgroundPaused = false;
  bool _workerActive = false;
  bool _workerScheduled = false;

  Future<String?> resolveFrameUri(
    Duration position, {
    required bool prioritize,
  }) {
    final normalized = _normalize(position);
    final cacheKey = normalized.inSeconds;
    final cached = _cache[cacheKey];
    if (cached != null) {
      if (prioritize) {
        primeVisibleStrip(position);
        primeRollingWindow(position);
      }
      return Future<String?>.value(cached);
    }
    final existing = _requests[cacheKey];
    if (existing != null) {
      if (prioritize) {
        _promoteQueuedTask(cacheKey);
        primeVisibleStrip(position);
        primeRollingWindow(position);
      }
      return existing;
    }

    final completer = Completer<String?>();
    final future = completer.future.whenComplete(() {
      _requests.remove(cacheKey);
    });
    _requests[cacheKey] = future;
    _enqueue(
      _HlsScrubFrameTask(
        position: normalized,
        cacheKey: cacheKey,
        prioritizeVisible: prioritize,
        completer: completer,
      ),
    );
    if (prioritize) {
      primeVisibleStrip(position);
      primeRollingWindow(position);
    }
    return future;
  }

  void primeVisibleStrip(Duration center) {
    for (final position in _stripPositions(center)) {
      _enqueuePrefetch(position, prioritizeVisible: true);
    }
  }

  void primeRollingWindow(Duration center) {
    for (final position in _rollingWindowPositions(center)) {
      _enqueuePrefetch(position, prioritizeVisible: false);
    }
  }

  void pauseBackgroundWork() {
    _backgroundPaused = true;
  }

  void resumeBackgroundWork() {
    _backgroundPaused = false;
    _scheduleWorker();
  }

  void dispose() {
    _disposed = true;
    for (final request in _priorityQueue) {
      if (!request.completer.isCompleted) {
        request.completer.complete(null);
      }
    }
    for (final request in _backgroundQueue) {
      if (!request.completer.isCompleted) {
        request.completer.complete(null);
      }
    }
    _priorityQueue.clear();
    _backgroundQueue.clear();
    _queuedKeys.clear();
    _requests.clear();
    _cache.clear();
  }

  void _enqueuePrefetch(
    Duration position, {
    required bool prioritizeVisible,
  }) {
    if (_disposed) {
      return;
    }
    final normalized = _normalize(position);
    final cacheKey = normalized.inSeconds;
    if (_cache.containsKey(cacheKey) ||
        _requests.containsKey(cacheKey) ||
        _queuedKeys.contains(cacheKey)) {
      return;
    }
    final completer = Completer<String?>();
    _requests[cacheKey] = completer.future.whenComplete(() {
      _requests.remove(cacheKey);
    });
    _enqueue(
      _HlsScrubFrameTask(
        position: normalized,
        cacheKey: cacheKey,
        prioritizeVisible: prioritizeVisible,
        completer: completer,
      ),
    );
  }

  void _enqueue(_HlsScrubFrameTask task) {
    if (_disposed || !_queuedKeys.add(task.cacheKey)) {
      return;
    }
    if (task.prioritizeVisible) {
      _priorityQueue.addLast(task);
    } else {
      _backgroundQueue.addLast(task);
    }
    _scheduleWorker();
  }

  void _promoteQueuedTask(int cacheKey) {
    final pending = _backgroundQueue.toList(growable: false);
    if (pending.isEmpty) {
      return;
    }
    for (final task in pending) {
      if (task.cacheKey != cacheKey) {
        continue;
      }
      _backgroundQueue.remove(task);
      _priorityQueue.addFirst(task.copyWith(prioritizeVisible: true));
      _scheduleWorker();
      return;
    }
  }

  void _scheduleWorker() {
    if (_disposed || _workerActive || _workerScheduled) {
      return;
    }
    _workerScheduled = true;
    scheduleMicrotask(() async {
      _workerScheduled = false;
      if (_disposed || _workerActive) {
        return;
      }
      final task = _priorityQueue.isNotEmpty
          ? _priorityQueue.removeFirst()
          : (_backgroundPaused || _backgroundQueue.isEmpty
              ? null
              : _backgroundQueue.removeFirst());
      if (task == null) {
        return;
      }

      _queuedKeys.remove(task.cacheKey);
      _workerActive = true;
      try {
        final uri = await extractor(
          position: task.position,
          prioritizeVisible: task.prioritizeVisible,
        );
        if (uri != null && uri.trim().isNotEmpty) {
          _cache[task.cacheKey] = uri;
        }
        if (!task.completer.isCompleted) {
          task.completer.complete(uri);
        }
      } catch (_) {
        if (!task.completer.isCompleted) {
          task.completer.complete(null);
        }
      } finally {
        _workerActive = false;
        if (!_disposed) {
          _scheduleWorker();
        }
      }
    });
  }

  Duration _normalize(Duration position) {
    final totalMs = position.inMilliseconds;
    final snapped = bucketStep.inMilliseconds <= 0
        ? totalMs
        : ((totalMs / bucketStep.inMilliseconds).round() *
                bucketStep.inMilliseconds)
            .clamp(0, 1 << 30);
    return Duration(milliseconds: snapped.toInt());
  }

  Iterable<Duration> _stripPositions(Duration center) sync* {
    final offsets = <Duration>[
      Duration(milliseconds: -(bucketStep * 2).inMilliseconds),
      Duration(milliseconds: -bucketStep.inMilliseconds),
      Duration.zero,
      bucketStep,
      bucketStep * 2,
    ];
    final seen = <int>{};
    for (final offset in offsets) {
      final candidate = _normalize(center + offset);
      if (seen.add(candidate.inMilliseconds)) {
        yield candidate;
      }
    }
  }

  Iterable<Duration> _rollingWindowPositions(Duration center) sync* {
    final offsets = <Duration>[
      Duration(milliseconds: -(bucketStep * 6).inMilliseconds),
      Duration(milliseconds: -(bucketStep * 5).inMilliseconds),
      Duration(milliseconds: -(bucketStep * 4).inMilliseconds),
      Duration(milliseconds: -(bucketStep * 3).inMilliseconds),
      bucketStep * 3,
      bucketStep * 4,
      bucketStep * 5,
      bucketStep * 6,
    ];
    final seen = <int>{};
    for (final offset in offsets) {
      final candidate = _normalize(center + offset);
      if (seen.add(candidate.inMilliseconds)) {
        yield candidate;
      }
    }
  }
}

class _HlsScrubFrameTask {
  const _HlsScrubFrameTask({
    required this.position,
    required this.cacheKey,
    required this.prioritizeVisible,
    required this.completer,
  });

  final Duration position;
  final int cacheKey;
  final bool prioritizeVisible;
  final Completer<String?> completer;

  _HlsScrubFrameTask copyWith({
    Duration? position,
    int? cacheKey,
    bool? prioritizeVisible,
    Completer<String?>? completer,
  }) {
    return _HlsScrubFrameTask(
      position: position ?? this.position,
      cacheKey: cacheKey ?? this.cacheKey,
      prioritizeVisible: prioritizeVisible ?? this.prioritizeVisible,
      completer: completer ?? this.completer,
    );
  }
}

class _PlaybackLoadingIndicator extends StatelessWidget {
  const _PlaybackLoadingIndicator({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const CircularProgressIndicator(),
        const SizedBox(height: 18),
        Text(
          message,
          style: CheriflixTypography.body.copyWith(color: Colors.white),
        ),
      ],
    );
  }
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({
    required this.title,
    required this.message,
    this.icon,
    // ignore: unused_element_parameter
    this.loading = false,
  });

  final String title;
  final String message;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (loading)
                    const CircularProgressIndicator()
                  else if (icon != null)
                    Icon(icon, size: 56, color: Colors.white70),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: CheriflixTypography.sectionTitle,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: CheriflixTypography.body.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
