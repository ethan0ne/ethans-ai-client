import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Adds the recurring text sweep used by active chat activities.
class CadencedActivityShimmer extends StatefulWidget {
  const CadencedActivityShimmer({
    super.key,
    required this.child,
    required this.enabled,
    required this.settleOnDisable,
    required this.baseColor,
  });

  final Widget child;
  final bool enabled;
  final bool settleOnDisable;
  final Color baseColor;

  @override
  State<CadencedActivityShimmer> createState() =>
      _CadencedActivityShimmerState();
}

class _CadencedActivityShimmerState extends State<CadencedActivityShimmer>
    with SingleTickerProviderStateMixin {
  static const _periodSeconds = 4.0;
  static const _sweepStartSeconds = 0.6;
  static const _sweepDurationSeconds = 1.4;
  static const _sweepEndSeconds = _sweepStartSeconds + _sweepDurationSeconds;
  static const _sweepGradientLength = 48.0;

  late final AnimationController _controller;
  bool _settling = false;

  double get _phaseSeconds => _controller.value * _periodSeconds;
  bool get _insideSweep =>
      _phaseSeconds >= _sweepStartSeconds && _phaseSeconds < _sweepEndSeconds;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..addListener(_handleTick);
    if (widget.enabled) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant CadencedActivityShimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled) {
      _settling = false;
      if (!_controller.isAnimating) _controller.repeat();
    } else if (oldWidget.enabled && _controller.isAnimating) {
      if (widget.settleOnDisable && _insideSweep) {
        _settling = true;
      } else {
        _controller.stop();
      }
    }
  }

  void _handleTick() {
    if (_settling && _phaseSeconds >= _sweepEndSeconds) {
      _settling = false;
      _controller.stop();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled && !_settling) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final phase = _phaseSeconds;
        if ((!widget.enabled && !_settling) ||
            phase < _sweepStartSeconds ||
            phase >= _sweepEndSeconds) {
          return child!;
        }

        final rawProgress =
            ((_phaseSeconds - _sweepStartSeconds) / _sweepDurationSeconds)
                .clamp(0.0, 1.0);
        final progress = (rawProgress * 48).floorToDouble() / 48;
        final transparentBase = widget.baseColor.withValues(alpha: 0);
        final highlightAlpha = Theme.of(context).brightness == Brightness.dark
            ? 1.0
            : 0.6;
        final highlight = Colors.white.withValues(alpha: highlightAlpha);

        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final gradientStart = (-0.75 + 2.5 * progress) * bounds.width;
            return ui.Gradient.linear(
              Offset(gradientStart, bounds.height / 2),
              Offset(gradientStart + _sweepGradientLength, bounds.height / 2),
              [transparentBase, highlight, highlight, transparentBase],
              const [0, 1 / 3, 0.5, 1],
            );
          },
          child: child!,
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
