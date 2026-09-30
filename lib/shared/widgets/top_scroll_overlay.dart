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
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: notched ? const [0, 0.5, 1] : const [0, 1],
              colors: notched
                  ? [
                      backgroundColor.withValues(alpha: 0.9),
                      backgroundColor.withValues(alpha: 0.7),
                      backgroundColor.withValues(alpha: 0),
                    ]
                  : [
                      backgroundColor.withValues(alpha: 0.9),
                      backgroundColor.withValues(alpha: 0),
                    ],
            ),
          ),
        ),
      ],
    );
  }
}
