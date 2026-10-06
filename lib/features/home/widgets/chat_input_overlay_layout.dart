import 'package:flutter/material.dart';
import '../../../shared/widgets/top_processing_glow.dart';
import '../../../shared/widgets/top_scroll_overlay.dart';

class ChatInputOverlayLayout extends StatefulWidget {
  const ChatInputOverlayLayout({
    super.key,
    required this.topInset,
    required this.content,
    required this.bottomOverlay,
    this.bottomOverlayHeight,
    this.background,
    this.backgroundFade,
    this.backgroundImageActive = false,
    this.showTopScrollOverlay = true,
    this.processingGlow = false,
    this.foreground,
  });

  static const double _bottomOverlayFadeHeight = 180;
  static const double _expandedComposerHeight = 96;
  static const double _collapsedFadeExtraReduction = 16;
  static const double _bottomFadeExtraAboveComposer =
      _bottomOverlayFadeHeight - _expandedComposerHeight;

  final double topInset;
  final Widget content;
  final Widget bottomOverlay;

  /// Measured input overlay height, including its bottom safe-area inset.
  /// When omitted, the bottom fade keeps its original fixed height.
  final double? bottomOverlayHeight;
  final Widget? background;
  final Widget? backgroundFade;
  final bool backgroundImageActive;
  final bool showTopScrollOverlay;

  /// Drawn above the chat background and behind messages and controls.
  final bool processingGlow;
  final Widget? foreground;

  @override
  State<ChatInputOverlayLayout> createState() => _ChatInputOverlayLayoutState();
}

class _ChatInputOverlayLayoutState extends State<ChatInputOverlayLayout> {
  bool _scrolled = false;
  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final scrolled = notification.metrics.pixels > 16;
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    return false;
  }

  Widget _fade(Widget child) => AnimatedOpacity(
    opacity: _scrolled || widget.processingGlow ? 1 : 0,
    duration: const Duration(milliseconds: 160),
    curve: Curves.easeInOut,
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final safeTop = media.padding.top > media.viewPadding.top
        ? media.padding.top
        : media.viewPadding.top;
    final topBand = safeTop > 0 ? safeTop : 32.0;
    final fadeHeight = (widget.topInset - safeTop).clamp(0.0, double.infinity);
    final maskHeight = topBand + fadeHeight;
    final measuredComposerHeight = widget.bottomOverlayHeight == null
        ? null
        : (widget.bottomOverlayHeight! - media.padding.bottom)
              .clamp(0.0, double.infinity)
              .toDouble();
    final bottomFadeHeight = measuredComposerHeight == null
        ? ChatInputOverlayLayout._bottomOverlayFadeHeight
        : (measuredComposerHeight +
                  ChatInputOverlayLayout._bottomFadeExtraAboveComposer -
                  (measuredComposerHeight <
                          ChatInputOverlayLayout._expandedComposerHeight
                      ? ChatInputOverlayLayout._collapsedFadeExtraReduction
                      : 0))
              .clamp(0.0, ChatInputOverlayLayout._bottomOverlayFadeHeight)
              .toDouble();
    return Stack(
      children: [
        if (widget.background != null)
          Positioned.fill(child: widget.background!),
        Positioned.fill(
          child: TopProcessingGlow(active: widget.processingGlow),
        ),
        Positioned.fill(
          child: Stack(
            children: [
              Positioned.fill(
                child: widget.showTopScrollOverlay
                    ? NotificationListener<ScrollNotification>(
                        onNotification: _onScroll,
                        child: widget.content,
                      )
                    : widget.content,
              ),
              if (widget.showTopScrollOverlay)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: maskHeight,
                  child: _fade(
                    IgnorePointer(
                      key: const Key('chat-input-overlay-top-fade'),
                      child: TopScrollOverlay(
                        backgroundColor: Theme.of(
                          context,
                        ).scaffoldBackgroundColor,
                        topBandHeight: topBand,
                        gradientHeight: fadeHeight,
                        notched: safeTop > 0,
                      ),
                    ),
                  ),
                ),
              if (widget.backgroundImageActive && widget.backgroundFade != null)
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: bottomFadeHeight),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  builder: (context, height, child) => Positioned.fill(
                    child: ClipRect(
                      clipper: _BottomOverlayClipper(height),
                      child: _BottomBackgroundFade(
                        height: height,
                        child: child!,
                      ),
                    ),
                  ),
                  child: IgnorePointer(
                    key: const Key('chat-input-overlay-bottom-background'),
                    child: widget.backgroundFade!,
                  ),
                )
              else if (!widget.backgroundImageActive)
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: bottomFadeHeight),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  builder: (context, height, child) => Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: height,
                    child: child!,
                  ),
                  child: const _BottomOverlayFade(),
                ),
              if (widget.foreground != null)
                Positioned.fill(child: widget.foreground!),
            ],
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: UnconstrainedBox(
            constrainedAxis: Axis.horizontal,
            alignment: Alignment.bottomCenter,
            child: widget.bottomOverlay,
          ),
        ),
      ],
    );
  }
}

class _BottomOverlayClipper extends CustomClipper<Rect> {
  const _BottomOverlayClipper(this.height);

  final double height;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(
    0,
    (size.height - height).clamp(0, size.height),
    size.width,
    height.clamp(0, size.height),
  );

  @override
  bool shouldReclip(_BottomOverlayClipper oldClipper) =>
      height != oldClipper.height;
}

class _BottomBackgroundFade extends StatelessWidget {
  const _BottomBackgroundFade({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.48, 1.0],
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: isDark ? 0.74 : 0.82),
            Colors.white.withValues(alpha: isDark ? 0.92 : 0.98),
          ],
        ).createShader(
          Rect.fromLTWH(0, bounds.height - height, bounds.width, height),
        );
      },
      child: child,
    );
  }
}

class _BottomOverlayFade extends StatelessWidget {
  const _BottomOverlayFade();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = theme.colorScheme.surface;
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: const [0.0, 0.48, 1.0],
      colors: [
        surface.withValues(alpha: 0),
        surface.withValues(alpha: isDark ? 0.64 : 0.82),
        surface.withValues(alpha: isDark ? 0.92 : 0.98),
      ],
    );

    return IgnorePointer(
      key: const Key('chat-input-overlay-bottom-fade'),
      child: DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
    );
  }
}
