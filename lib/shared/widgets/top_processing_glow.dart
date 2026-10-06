import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Soft rainbow light that fades across the top half of the page while a
/// conversation is being processed.
class TopProcessingGlow extends StatefulWidget {
  const TopProcessingGlow({super.key, required this.active});

  final bool active;

  @override
  State<TopProcessingGlow> createState() => _TopProcessingGlowState();
}

class _TopProcessingGlowState extends State<TopProcessingGlow>
    with TickerProviderStateMixin {
  late final AnimationController _opacityController;
  late final AnimationController _phaseController;
  late final Animation<double> _opacity;
  late double _phaseOffset = math.Random().nextDouble();
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _opacityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
      reverseDuration: const Duration(milliseconds: 520),
    );
    _opacity = CurvedAnimation(
      parent: _opacityController,
      curve: Curves.easeInOutCubic,
    );
    _opacityController.addStatusListener(_handleOpacityStatus);
    _phaseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 26),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.maybeOf(context);
    _reducedMotion =
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
    _syncAnimations();
  }

  @override
  void didUpdateWidget(TopProcessingGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      if (widget.active) _phaseOffset = math.Random().nextDouble();
      _syncAnimations();
    }
  }

  void _syncAnimations() {
    if (_reducedMotion) {
      _phaseController.stop();
      _phaseController.value = 0;
      _opacityController.value = widget.active ? 1 : 0;
      return;
    }

    if (widget.active) {
      if (!_phaseController.isAnimating) _phaseController.repeat();
      _opacityController.forward();
    } else if (_opacityController.value > 0) {
      _opacityController.reverse();
    } else {
      _phaseController.stop();
      _phaseController.value = 0;
    }
  }

  void _handleOpacityStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !widget.active) {
      _phaseController.stop();
      _phaseController.value = 0;
    }
  }

  @override
  void dispose() {
    _opacityController
      ..removeStatusListener(_handleOpacityStatus)
      ..dispose();
    _phaseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: FractionallySizedBox(
          widthFactor: 1,
          heightFactor: 0.5,
          child: FadeTransition(
            opacity: _opacity,
            child: ClipRect(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, Colors.transparent],
                ).createShader(bounds),
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _phaseController,
                    builder: (context, _) => CustomPaint(
                      painter: _RainbowGlowPainter(
                        phase: (_phaseOffset + _phaseController.value) % 1,
                        brightness: brightness,
                      ),
                      child: const SizedBox.expand(),
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
}

class _RainbowGlowPainter extends CustomPainter {
  const _RainbowGlowPainter({required this.phase, required this.brightness});

  final double phase;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final isDark = brightness == Brightness.dark;
    final time = phase * math.pi * 2;
    final baseHue = (phase * 360) % 360;
    final saturation = isDark ? 0.72 : 0.58;
    final strength = isDark ? 0.47 : 0.52;

    Color hueColor(double offset) =>
        HSVColor.fromAHSV(1, (baseHue + offset) % 360, saturation, 1).toColor();

    final blobs = <_GlowBlob>[
      _GlowBlob(
        color: hueColor(-19),
        x: 0.19 + math.sin(time + 0.4) * 0.15,
        y: 0.23 + math.sin(time * 2 + 1.2) * 0.13,
        width: 0.88,
        height: 0.92,
        opacity: strength,
      ),
      _GlowBlob(
        color: hueColor(8),
        x: 0.78 + math.sin(time * 2 + 2.1) * 0.17,
        y: 0.31 + math.sin(time * 3 + 2.8) * 0.12,
        width: 0.94,
        height: 0.83,
        opacity: strength * 0.88,
      ),
      _GlowBlob(
        color: hueColor(24),
        x: 0.49 + math.sin(time * 3 + 4.0) * 0.19,
        y: 0.56 + math.sin(time + 0.7) * 0.13,
        width: 0.79,
        height: 0.73,
        opacity: strength * 0.75,
      ),
    ];

    for (final blob in blobs) {
      _drawFluidBlob(canvas, size, blob);
    }
  }

  void _drawFluidBlob(Canvas canvas, Size size, _GlowBlob blob) {
    final rx = size.width * blob.width * 0.5;
    final ry = size.height * blob.height * 0.5;
    final center = Offset(size.width * blob.x, size.height * blob.y);
    final color = blob.color;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(rx, ry);
    final shader = RadialGradient(
      colors: [
        color.withValues(alpha: blob.opacity),
        color.withValues(alpha: blob.opacity * 0.54),
        color.withValues(alpha: 0),
      ],
      stops: const [0, 0.54, 1],
    ).createShader(const Rect.fromLTRB(-1, -1, 1, 1));
    canvas.drawCircle(Offset.zero, 1, Paint()..shader = shader);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RainbowGlowPainter oldDelegate) =>
      phase != oldDelegate.phase || brightness != oldDelegate.brightness;
}

class _GlowBlob {
  const _GlowBlob({
    required this.color,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.opacity,
  });

  final Color color;
  final double x;
  final double y;
  final double width;
  final double height;
  final double opacity;
}
