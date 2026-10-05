import 'package:flutter/material.dart';

/// Opaque navigation band and fade used above scrollable page content.
class TopScrollOverlay extends StatelessWidget {
  const TopScrollOverlay({
    required this.backgroundColor,
    required this.topBandHeight,
    required this.gradientHeight,
    required this.notched,
    super.key,
  });

  final Color backgroundColor;
  final double topBandHeight;
  final double gradientHeight;
  final bool notched;

  static LinearGradient fadeGradient(Color color, {required bool notched}) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: notched ? const [0, 0.5, 1] : const [0, 1],
      colors: [
        color.withValues(alpha: 0.9),
        if (notched) color.withValues(alpha: 0.7),
        color.withValues(alpha: 0),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: topBandHeight,
          color: backgroundColor.withValues(alpha: 0.9),
        ),
        Container(
          height: gradientHeight,
          decoration: BoxDecoration(
            gradient: fadeGradient(backgroundColor, notched: notched),
          ),
        ),
      ],
    );
  }
}
