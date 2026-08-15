import 'package:flutter/material.dart';

import '../theme/cheriflix_theme.dart';

class PlaybackProgressBar extends StatelessWidget {
  const PlaybackProgressBar({
    super.key,
    required this.value,
    this.height = 6,
    this.backgroundColor = const Color(0x66000000),
    this.valueColor = CheriflixColors.accentRed,
  });

  final double value;
  final double height;
  final Color backgroundColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              color: backgroundColor,
            ),
          ),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0.0, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
